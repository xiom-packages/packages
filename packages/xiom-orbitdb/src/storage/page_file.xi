// XIOM ORBITDB -- durable page file v1 (text codec).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The first on-disk page store: one line per page, byte-true payload,
// CRC32C-verified on read.
//
//   page_id|len|checksum|b0,b1,...      (bytes are 0..255; empty = zero bytes)
//
// Writes are upserts: the whole file is rebuilt into a temp file and moved
// over the original (io.rename = atomic replace), so a crash mid-write never
// destroys the previous state; malformed/torn tail lines are skipped on read.
// This is O(n) per write and honest about it: it is the Phase-1 seam for the
// pager (C2), replaced by fixed-size page IO when stdlib byte IO lands.
//
// Durability honesty: no fsync yet (`page_file_sync` is a documented no-op)
// -- see STDLIB-WISHLIST-ORBITDB.md row 1.

module xiom.db.storage.page_file

use xiom.io;
use xiom.os.sync_io;
use xiom.convert;
use xiom.convert.parse;
use xiom.string.trim;
use xiom.string.split;
use xiom.db.storage.page;
use xiom.db.storage.byte_io;

pub type PageFile = { path: Str; }

pub fn page_file_open(path: Str) -> PageFile {
  return PageFile{ path: path };
}

fn parse_int_into(s: Str, out: &mut Int) -> Bool {
  match parse.parse_int(s) {
    Ok(v) => {
      *out = v;
      return true;
    }
    Err(_) => { return false; }
  }
}

// Parse one record line; None for malformed/torn lines (skipped by readers).
fn parse_page_line(raw: Str) -> Option[Page] {
  let parts = split.str_split(raw, "|");
  if parts.len() != 4 { return None; }
  var id = 0;
  var len = 0;
  var cs = 0;
  if !parse_int_into(parts[0], &mut id) { return None; }
  if !parse_int_into(parts[1], &mut len) { return None; }
  if !parse_int_into(parts[2], &mut cs) { return None; }
  if len < 0 { return None; }
  if len > 4096 { return None; } // Page contract

  var data = Vec[Int].new();
  if len > 0 {
    let nums = split.str_split(parts[3], ",");
    if nums.len() != len { return None; }
    var i = 0;
    while i < len {
      var b = 0;
      if !parse_int_into(nums[i], &mut b) { return None; }
      if b < 0 { return None; }
      if b > 255 { return None; }
      data.push(b);
      i = i + 1;
    }
  }
  let p = Page.new(id, data, cs);
  return Some(p);
}

fn format_page_line(p: &Page) -> Str {
  var s = convert.int_to_string(p.id) + "|" + convert.int_to_string(p.data.len())
        + "|" + convert.int_to_string(p.checksum) + "|";
  var i = 0;
  while i < p.data.len() {
    if i > 0 { s = s + ","; }
    s = s + convert.int_to_string(p.data[i] & 0xFF);
    i = i + 1;
  }
  return s;
}

// All page ids in file order (malformed lines skipped).
pub fn page_file_ids(pf: &PageFile) -> Vec[Int] {
  var out = Vec[Int].new();
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => { return out; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(p) => {
              // Integrity view: checksum-invalid lines are garbage, not pages
              // (a crash can leave a structurally complete but corrupt line).
              if p.is_valid() {
                out.push(p.id);
              }
            }
          }
        }
        i = i + 1;
      }
      return out;
    }
  }
}

pub fn page_file_count(pf: &PageFile) -> Int {
  return page_file_ids(pf).len();
}

// Read one page by id; None when absent, malformed, or checksum-invalid
// (Page.is_valid recomputes CRC32C over the byte view).
pub fn page_file_read(pf: &PageFile, page_id: Int) -> Option[Page] {
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => { return None; }
    Ok(lines) => {
      var found = false;
      var page = Page.new(0, Vec[Int].new(), 0);
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(p) => {
              if p.id == page_id {
                if p.is_valid() {
                  page = p;
                  found = true;
                }
              }
            }
          }
        }
        i = i + 1;
      }
      if !found { return None; }
      return Some(page);
    }
  }
}

// Every valid page in file order, from ONE scan of the file (malformed and
// checksum-invalid lines are skipped). Whole-set readers -- the checkpoint
// snapshot loader -- use this instead of one `page_file_read` scan per page.
pub fn page_file_read_all(pf: &PageFile) -> Vec[Page] {
  var out = Vec[Page].new();
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => { return out; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(p) => {
              if p.is_valid() { out.push(p); }
            }
          }
        }
        i = i + 1;
      }
      return out;
    }
  }
}

// Replace the ENTIRE page set with `pages` in one temp write + atomic rename
// (upserts in `page_file_write` keep unlisted pages; this does not). This is
// the snapshot install path: a crash before the rename leaves the previous
// page set fully intact, so a checkpoint is all-or-nothing.
pub fn page_file_write_batch(pf: &PageFile, pages: Vec[Page]) -> Bool {
  var body = "";
  var i = 0;
  while i < pages.len() {
    let p = pages[i];
    body = body + format_page_line(&p) + "\n";
    i = i + 1;
  }

  var tmp = pf.path + ".tmp";
  let _ = io.remove_file(tmp);
  let wrote = io.write_file(tmp, body);
  match wrote {
    Err(_) => { return false; }
    Ok(_) => {}
  }
  // Rename durability (P3, M1.2 S4): sync the temp before publishing the new
  // name, then sync the directory that received the rename.
  let _ = byte_io.byteio_sync(tmp);
  let moved = io.rename(tmp, pf.path);
  match moved {
    Ok(_) => {
      let _ = byte_io.byteio_sync_dir(pf.path);
      return true;
    }
    Err(_) => { return false; }
  }
}

// Upsert a page: rebuild the file into a temp, then atomically replace.
// Returns false on any IO failure (the original file is left untouched).
pub fn page_file_write(pf: &PageFile, page: Page) -> Bool {
  var body = "";
  var replaced = false;
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => {}
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(p) => {
              if p.id == page.id {
                body = body + format_page_line(&page) + "\n";
                replaced = true;
              } elif p.is_valid() {
                // Rebuild heals: checksum-invalid survivors are dropped.
                body = body + format_page_line(&p) + "\n";
              }
            }
          }
        }
        i = i + 1;
      }
    }
  }
  if !replaced {
    body = body + format_page_line(&page) + "\n";
  }

  var tmp = pf.path + ".tmp";
  let _ = io.remove_file(tmp);
  let wrote = io.write_file(tmp, body);
  match wrote {
    Err(_) => { return false; }
    Ok(_) => {}
  }
  // Rename durability (P3, M1.2 S4): sync the temp before publishing, then
  // sync the directory that received the rename.
  let _ = byte_io.byteio_sync(tmp);
  let moved = io.rename(tmp, pf.path);
  match moved {
    Ok(_) => {
      let _ = byte_io.byteio_sync_dir(pf.path);
      return true;
    }
    Err(_) => { return false; }
  }
}

// Durability seam (M2.1 second half, real since M1.2 S4): fsync the file.
pub fn page_file_sync(pf: &PageFile) -> Bool {
  if !io.file_exists(pf.path) { return true; }
  match sync_io.open_append(pf.path) {
    Err(_) => { return false; }
    Ok(fd) => {
      var ok = false;
      match sync_io.sync_fd(fd) {
        Ok(_) => { ok = true; }
        Err(_) => {}
      }
      let _ = sync_io.close_fd(fd);
      return ok;
    }
  }
}

// ---------------------------------------------------------------------------
// Append-only page log (incremental node-page persistence)
// ---------------------------------------------------------------------------
// Same line codec as above; a page id may appear many times -- later entries
// are newer versions. A checkpoint appends new versions of only the pages
// that changed and commits by appending the header page LAST; callers resolve
// the newest committed version (see the snapshot loader in engine.xi).
// Compaction rewrites one version per page via `page_file_write_batch`
// (atomic replace).

// Append one page version. O(1); a crash may leave a torn last line, which
// readers skip -- call `page_log_heal_tail` before appending again so the
// torn line cannot merge with the new one.
pub fn page_log_append(pf: &PageFile, page: Page) -> Bool {
  let line = format_page_line(&page);
  let wrote = io.append_line(pf.path, line);
  match wrote {
    Ok(_) => { return true; }
    Err(_) => { return false; }
  }
}

// Heal a torn trailing line (crash mid-append): if the file does not end with
// a newline, terminate the partial line so the next append starts clean.
// O(1) since M1.2 S4: file_last_byte + append_line_sync (stdlib wave 117).
pub fn page_log_heal_tail(pf: &PageFile) -> Bool {
  if !io.file_exists(pf.path) { return true; } // missing file: nothing to heal
  match io.file_last_byte(pf.path) {
    None => { return true; } // empty file
    Some(b) => {
      if b == (10 as UInt8) { return true; }
      match io.append_line_sync(pf.path, "") {
        Ok(_) => { return true; }
        Err(_) => { return false; }
      }
    }
  }
}

// Raw entry count -- well-formed lines, duplicates included. Compaction is
// triggered on physical log growth, not on the unique-page count.
pub fn page_log_len(pf: &PageFile) -> Int {
  var count = 0;
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => { return 0; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(_) => { count = count + 1; }
          }
        }
        i = i + 1;
      }
      return count;
    }
  }
}

// Latest version per page id (last occurrence in file order wins); malformed
// and checksum-invalid lines are skipped. Deduplicated view for tests and
// whole-set readers; the engine's generation-aware loader scans the raw list
// instead so it can reason about generations.
pub fn page_log_read_all(pf: &PageFile) -> Vec[Page] {
  var all = Vec[Page].new();
  let lines_r = io.read_file_lines(pf.path);
  match lines_r {
    Err(_) => { return all; }
    Ok(lines) => {
      var i = 0;
      while i < lines.len() {
        let raw = trim.str_trim(lines[i]);
        if raw != "" {
          match parse_page_line(raw) {
            None => {}
            Some(p) => {
              if p.is_valid() { all.push(p); }
            }
          }
        }
        i = i + 1;
      }
    }
  }

  // Latest occurrence wins: keep every page that no later page supersedes.
  // This is the nested `Vec[Page]` shape that aborted before v0.64.2
  // (C-ORBIT-05, m235 loop-body alloca fix); the repro bundle
  // docs/repro/vec-push-nested/ is green unchanged on the new archive.
  var out = Vec[Page].new();
  var k = 0;
  while k < all.len() {
    var superseded = false;
    var j = k + 1;
    while j < all.len() && !superseded {
      if all[j].id == all[k].id { superseded = true; }
      j = j + 1;
    }
    if !superseded { out.push(all[k]); }
    k = k + 1;
  }
  return out;
}
