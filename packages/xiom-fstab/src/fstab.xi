// XIOM -- xiom.fstab: fstab parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed /etc/fstab document is a set of index-aligned vectors
// owned by Fstab: entry i has devices[i], mountpoints[i], fstypes[i],
// options_text[i] (the options field exactly as written), dumps[i], passes[i]
// and lines[i] (its 1-based source line); its option names live in the shared
// flat pool option_pool[option_starts[i] .. option_starts[i] +
// option_counts[i]], in field order. Vec[StructType] is unsupported in this
// compiler, so the document is deliberately flat instead of a vector of entry
// structs. Duplicate mountpoints are preserved in document order; there is no
// dedup and no last-wins merging.
//
// Documented subset (see SPEC.md for the exact grammar):
//   * an entry line is six whitespace-separated fields
//     `device mountpoint fstype options dump pass`; runs of space/tab collapse
//     to one separator, leading/trailing whitespace and blank lines are
//     ignored, and LF or CRLF line endings are accepted (a missing final
//     newline is fine);
//   * the first `#` on a line starts a comment that runs to end of line; `#`
//     can never occur inside a field, not even escaped;
//   * device, mountpoint and fstype are "word fields": the four documented
//     octal escapes are decoded on parse -- \040 SP, \011 TAB, \012 LF,
//     \134 backslash -- and a literal backslash, space, tab or newline is
//     re-encoded by fstab_emit; any other backslash sequence is
//     Err("fstab: bad escape in <field>: <token>"); a word field that decodes
//     to empty or whitespace only is Err("fstab: empty <field>: <token>");
//   * options is a non-empty comma-separated list of non-empty option names
//     in written order; names are stored and compared verbatim, and no
//     semantics are attached (in particular rw/ro are not enforced and not
//     implied);
//   * dump and pass are each exactly one of "0", "1" or "2"; any other token
//     is Err("fstab: bad dump: <token>") or Err("fstab: bad pass: <token>");
//   * any byte 0x00..0x1F other than TAB (and the CR of a CRLF pair) or DEL is
//     Err("fstab: control byte in line <n>"), comments included.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     _fs_byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF` before any
//     comparison (a raw UInt8 compared against a constant >= 128 miscompiles);
//   * no `==` on Str values read from Vec[Str] elements; each is bound to a
//     typed local first and compared with compare.str_compare (BUG 17);
//   * Ok/Err for the struct-payload Result are constructed only in the leaf
//     helpers _fs_ok/_fs_err;
//   * every push on the index-aligned vectors is mirrored in _fs_push_entry,
//     and accessors/emit clamp against mismatched lengths so a corrupted
//     document cannot drive out-of-range reads.
//
// See SPEC.md for the model, grammar, error catalog and test plan.

module xiom.fstab

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed fstab document. `devices`, `mountpoints`, `fstypes`, `options_text`,
/// `option_starts`, `option_counts`, `dumps`, `passes` and `lines` are
/// index-aligned per-entry vectors: entry i has device devices[i], mountpoint
/// mountpoints[i], filesystem type fstypes[i], the options field exactly as
/// written in options_text[i], dump/pass values dumps[i]/passes[i] (each 0, 1
/// or 2) and 1-based source line lines[i]. The entry's option names, in
/// written order, are the slice option_pool[option_starts[i] ..
/// option_starts[i] + option_counts[i]] of the shared flat pool.
/// Vec[StructType] is unsupported in this compiler, so the model is flat.
/// Duplicate mountpoints are preserved in document order (no dedup, no
/// last-wins): fstab_mountpoint_index reports the first match and
/// fstab_entries_for_mountpoint reports every match, in order.
pub type Fstab = {
  devices: Vec[Str];
  mountpoints: Vec[Str];
  fstypes: Vec[Str];
  options_text: Vec[Str];
  option_starts: Vec[Int];
  option_counts: Vec[Int];
  option_pool: Vec[Str];
  dumps: Vec[Int];
  passes: Vec[Int];
  lines: Vec[Int];
}

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

const _FS_TAB: Int = 9;
const _FS_LF: Int = 10;
const _FS_CR: Int = 13;
const _FS_SPACE: Int = 32;
const _FS_HASH: Int = 35;
const _FS_COMMA: Int = 44;
const _FS_ZERO: Int = 48;
const _FS_ONE: Int = 49;
const _FS_TWO: Int = 50;
const _FS_BS: Int = 92;
const _FS_DEL: Int = 127;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _fs_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _fs_is_space(c: Int) -> Bool {
  return c == _FS_SPACE || c == _FS_TAB;
}

// Octal digit value of an ASCII byte, or -1.
fn _fs_octal_value(c: Int) -> Int {
  if c >= 48 && c <= 55 { return c - 48; }
  return -1;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 constructors for the struct-payload Result: Ok/Err are built only in
// these tiny wrappers, never inside a larger function.

fn _fs_ok(d: Fstab) -> Result[Fstab, Str] {
  return Ok(d);
}

fn _fs_err(m: Str) -> Result[Fstab, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Escapes
// --------------------------------------------------

// Decode the four documented octal escapes (\040 SP, \011 TAB, \012 LF,
// \134 backslash) of one word field. Returns None when a backslash does not
// begin exactly one of those four-byte sequences; otherwise Some(decoded),
// which may still be empty or whitespace-only (the caller checks that).
fn _fs_decode(s: Str) -> Option[Str] {
  var out = "";
  let n = s.len();
  var i = 0;
  while i < n {
    let c = _fs_byte_at(s, i);
    if c == _FS_BS {
      if i + 3 >= n { return None; }
      let d1 = _fs_octal_value(_fs_byte_at(s, i + 1));
      let d2 = _fs_octal_value(_fs_byte_at(s, i + 2));
      let d3 = _fs_octal_value(_fs_byte_at(s, i + 3));
      if d1 < 0 { return None; }
      if d2 < 0 { return None; }
      if d3 < 0 { return None; }
      let v = d1 * 64 + d2 * 8 + d3;
      if v == _FS_SPACE {
        out = out + " ";
      } elif v == _FS_TAB {
        out = out + "\t";
      } elif v == _FS_LF {
        out = out + "\n";
      } elif v == _FS_BS {
        out = out + "\\";
      } else {
        return None;
      }
      i = i + 4;
    } else {
      out = out + string.str_slice(s, i, i + 1);
      i = i + 1;
    }
  }
  return Some(out);
}

// True when s contains at least one byte that is not an ASCII space, TAB or
// LF. A decoded word field without such a byte is treated as empty.
fn _fs_has_content(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let c = _fs_byte_at(s, i);
    if c != _FS_SPACE && c != _FS_TAB && c != _FS_LF { return true; }
    i = i + 1;
  }
  return false;
}

// Canonical escape encoding of one word field: a literal backslash, space, TAB
// or LF becomes \134, \040, \011 or \012; every other byte is copied verbatim.
fn _fs_encode_word(s: Str) -> Str {
  var out = "";
  let n = s.len();
  var i = 0;
  while i < n {
    let c = _fs_byte_at(s, i);
    if c == _FS_BS {
      out = out + "\\134";
    } elif c == _FS_SPACE {
      out = out + "\\040";
    } elif c == _FS_TAB {
      out = out + "\\011";
    } elif c == _FS_LF {
      out = out + "\\012";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Line scanning
// --------------------------------------------------

// True when s[start, stop) contains a byte that is neither printable ASCII nor
// TAB: bytes 0..31 (TAB excepted) and DEL. A CR is only legal as the CR of a
// CRLF pair, which the caller strips before calling this.
fn _fs_line_has_control(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    let c = _fs_byte_at(s, i);
    if c < 32 && c != _FS_TAB { return true; }
    if c == _FS_DEL { return true; }
    i = i + 1;
  }
  return false;
}

// Append the whitespace-separated tokens of s[start, stop) to `out`.
fn _fs_split_tokens(s: Str, start: Int, stop: Int, out: &mut Vec[Str]) {
  var i = start;
  while i < stop {
    while i < stop && _fs_is_space(_fs_byte_at(s, i)) { i = i + 1; }
    if i >= stop { break; }
    var j = i;
    while j < stop && !_fs_is_space(_fs_byte_at(s, j)) { j = j + 1; }
    out.push(string.str_slice(s, i, j));
    i = j;
  }
}

// Split one options field on commas. Returns false (after pushing the elements
// seen so far) when the field is empty or has an empty element, i.e. a leading,
// trailing or doubled comma.
fn _fs_split_options(s: Str, out: &mut Vec[Str]) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  var start = 0;
  while i <= n {
    if i == n || _fs_byte_at(s, i) == _FS_COMMA {
      if i == start { return false; }
      out.push(string.str_slice(s, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

// Value of a dump/pass token: 0, 1 or 2 for exactly those single bytes,
// otherwise -1.
fn _fs_parse_012(s: Str) -> Int {
  if s.len() != 1 { return -1; }
  let c = _fs_byte_at(s, 0);
  if c == _FS_ZERO { return 0; }
  if c == _FS_ONE { return 1; }
  if c == _FS_TWO { return 2; }
  return -1;
}

// Append one parsed entry. Every index-aligned vector is pushed here and the
// option names are copied into the shared pool, so the vectors cannot drift
// apart.
fn _fs_push_entry(doc: &mut Fstab, device: Str, mountpoint: Str, fstype: Str, options_text: Str, options: &Vec[Str], dump: Int, pass_no: Int, line: Int) {
  let opt_start = doc.option_pool.len();
  doc.devices.push(device);
  doc.mountpoints.push(mountpoint);
  doc.fstypes.push(fstype);
  doc.options_text.push(options_text);
  doc.option_starts.push(opt_start);
  doc.option_counts.push(options.len());
  doc.dumps.push(dump);
  doc.passes.push(pass_no);
  doc.lines.push(line);
  var k = 0;
  while k < options.len() {
    let o: Str = options[k];
    doc.option_pool.push(o);
    k = k + 1;
  }
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse an fstab document.
/// Params: text - the whole file (LF or CRLF line endings; a missing final
/// newline is accepted).
/// Returns: Ok(Fstab) for a document in the documented subset, including an
/// empty one and one with only comments/blank lines. Every entry line
/// contributes one entry with decoded word fields, the options field exactly
/// as written, dump/pass as 0/1/2 and its 1-based source line, in document
/// order. Duplicate mountpoints are preserved.
/// Error case: the first failing line in document order, with an exact ASCII
/// message: "fstab: control byte in line <n>"; "fstab: too few fields in line
/// <n>"; "fstab: too many fields in line <n>"; "fstab: bad escape in device:
/// <token>", "... in mountpoint: <token>", "... in fstype: <token>"; "fstab:
/// empty device: <token>", "fstab: empty mountpoint: <token>", "fstab: empty
/// fstype: <token>"; "fstab: empty option: <token>"; "fstab: bad dump:
/// <token>"; "fstab: bad pass: <token>". Within a line the checks run control
/// byte, field count, then the fields left to right (device, mountpoint,
/// fstype, options, dump, pass). <token> is the offending field exactly as
/// written, before decoding.
/// Examples: "dev mnt ext4 defaults 0 0\n" -> Ok with one entry;
/// "/dev/disk\040one mnt ext4 defaults 0 0\n" -> the device is decoded to
/// "/dev/disk one"; "dev mnt ext4 defaults 3 0\n" ->
/// Err("fstab: bad dump: 3").
/// Complexity: O(text.len()).
pub fn fstab_parse(text: Str) -> Result[Fstab, Str] {
  var doc = Fstab{
    devices: Vec[Str].new();
    mountpoints: Vec[Str].new();
    fstypes: Vec[Str].new();
    options_text: Vec[Str].new();
    option_starts: Vec[Int].new();
    option_counts: Vec[Int].new();
    option_pool: Vec[Str].new();
    dumps: Vec[Int].new();
    passes: Vec[Int].new();
    lines: Vec[Int].new();
  };
  let n = text.len();
  var line_no = 1;
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _fs_byte_at(text, i) == _FS_LF {
      var stop = i;
      if stop > start && _fs_byte_at(text, stop - 1) == _FS_CR {
        stop = stop - 1;
      }
      if _fs_line_has_control(text, start, stop) {
        return _fs_err("fstab: control byte in line " + convert.int_to_string(line_no));
      }
      var cut = stop;
      var h = start;
      while h < stop {
        if _fs_byte_at(text, h) == _FS_HASH {
          cut = h;
          break;
        }
        h = h + 1;
      }
      var tokens = Vec[Str].new();
      _fs_split_tokens(text, start, cut, &mut tokens);
      if tokens.len() > 0 {
        if tokens.len() < 6 {
          return _fs_err("fstab: too few fields in line " + convert.int_to_string(line_no));
        }
        if tokens.len() > 6 {
          return _fs_err("fstab: too many fields in line " + convert.int_to_string(line_no));
        }
        let raw_device: Str = tokens[0];
        let raw_mount: Str = tokens[1];
        let raw_fstype: Str = tokens[2];
        let raw_options: Str = tokens[3];
        let raw_dump: Str = tokens[4];
        let raw_pass: Str = tokens[5];
        var device = "";
        let dev_opt = _fs_decode(raw_device);
        match dev_opt {
          Some(v) => { device = v; },
          None => { return _fs_err("fstab: bad escape in device: " + raw_device); },
        }
        if !_fs_has_content(device) {
          return _fs_err("fstab: empty device: " + raw_device);
        }
        var mountpoint = "";
        let mnt_opt = _fs_decode(raw_mount);
        match mnt_opt {
          Some(v) => { mountpoint = v; },
          None => { return _fs_err("fstab: bad escape in mountpoint: " + raw_mount); },
        }
        if !_fs_has_content(mountpoint) {
          return _fs_err("fstab: empty mountpoint: " + raw_mount);
        }
        var fstype = "";
        let fst_opt = _fs_decode(raw_fstype);
        match fst_opt {
          Some(v) => { fstype = v; },
          None => { return _fs_err("fstab: bad escape in fstype: " + raw_fstype); },
        }
        if !_fs_has_content(fstype) {
          return _fs_err("fstab: empty fstype: " + raw_fstype);
        }
        var options = Vec[Str].new();
        if !_fs_split_options(raw_options, &mut options) {
          return _fs_err("fstab: empty option: " + raw_options);
        }
        let dump = _fs_parse_012(raw_dump);
        if dump < 0 {
          return _fs_err("fstab: bad dump: " + raw_dump);
        }
        let pass_no = _fs_parse_012(raw_pass);
        if pass_no < 0 {
          return _fs_err("fstab: bad pass: " + raw_pass);
        }
        _fs_push_entry(&mut doc, device, mountpoint, fstype, raw_options, &options, dump, pass_no, line_no);
      }
      line_no = line_no + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return _fs_ok(doc);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of entries in the document.
/// Params: d - parsed document.
/// Returns: the entry count; a corrupted document reports the smallest of the
/// nine index-aligned vectors, so trailing rows are ignored rather than read
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_entry_count(d: &Fstab) -> Int {
  var n = d.devices.len();
  if d.mountpoints.len() < n { n = d.mountpoints.len(); }
  if d.fstypes.len() < n { n = d.fstypes.len(); }
  if d.options_text.len() < n { n = d.options_text.len(); }
  if d.option_starts.len() < n { n = d.option_starts.len(); }
  if d.option_counts.len() < n { n = d.option_counts.len(); }
  if d.dumps.len() < n { n = d.dumps.len(); }
  if d.passes.len() < n { n = d.passes.len(); }
  if d.lines.len() < n { n = d.lines.len(); }
  return n;
}

/// Device field of entry i, decoded.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(device) for 0 <= i < fstab_entry_count(d), else None. The
/// text is the field after the documented octal escapes were decoded.
/// Error case: none.
/// Examples: entry "/dev/disk\040one ..." -> Some("/dev/disk one").
/// Complexity: O(1).
pub fn fstab_device(d: &Fstab, i: Int) -> Option[Str] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Str = d.devices[i];
  return Some(v);
}

/// Mountpoint field of entry i, decoded.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(mountpoint) for 0 <= i < fstab_entry_count(d), else None.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_mountpoint(d: &Fstab, i: Int) -> Option[Str] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Str = d.mountpoints[i];
  return Some(v);
}

/// Filesystem type field of entry i, decoded.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(fstype) for 0 <= i < fstab_entry_count(d), else None.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_fstype(d: &Fstab, i: Int) -> Option[Str] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Str = d.fstypes[i];
  return Some(v);
}

/// Options field of entry i exactly as written (no decoding).
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(text) for 0 <= i < fstab_entry_count(d), else None. The text
/// is the raw comma-separated field; see fstab_options for the split list.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_options_string(d: &Fstab, i: Int) -> Option[Str] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Str = d.options_text[i];
  return Some(v);
}

/// Number of options of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: the option count for 0 <= i < fstab_entry_count(d), else 0. The
/// count is clamped to the shared pool, so a corrupted document reports 0
/// rather than reading past `option_pool`.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_option_count(d: &Fstab, i: Int) -> Int {
  if i < 0 || i >= fstab_entry_count(d) { return 0; }
  let start: Int = d.option_starts[i];
  if start < 0 { return 0; }
  var c: Int = d.option_counts[i];
  if c < 0 { c = 0; }
  if start + c > d.option_pool.len() { c = d.option_pool.len() - start; }
  if c < 0 { c = 0; }
  return c;
}

/// Option j of entry i, in written order.
/// Params: d - parsed document; i - zero-based entry index; j - zero-based
/// option index.
/// Returns: Some(name) for 0 <= j < fstab_option_count(d, i), else None. Names
/// are byte-exact and case-sensitive; no semantic checks were applied.
/// Error case: none.
/// Examples: "rw,noatime" -> j 0 "rw", j 1 "noatime".
/// Complexity: O(1).
pub fn fstab_option(d: &Fstab, i: Int, j: Int) -> Option[Str] {
  let c = fstab_option_count(d, i);
  if j < 0 || j >= c { return None; }
  let start: Int = d.option_starts[i];
  let v: Str = d.option_pool[start + j];
  return Some(v);
}

/// Options of entry i as a fresh list, in written order.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: a fresh Vec with the entry's option names for 0 <= i <
/// fstab_entry_count(d), else an empty Vec. Mutating the result does not
/// change the document.
/// Error case: none.
/// Complexity: O(options).
pub fn fstab_options(d: &Fstab, i: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let c = fstab_option_count(d, i);
  if c == 0 { return out; }
  let start: Int = d.option_starts[i];
  var k = 0;
  while k < c {
    let o: Str = d.option_pool[start + k];
    out.push(o);
    k = k + 1;
  }
  return out;
}

/// True when option `name` is present in entry i.
/// Params: d - parsed document; i - zero-based entry index; name - query.
/// Returns: true when some option of entry i compares byte-equal to `name`;
/// false for an out-of-range entry or when the option is absent. Matching is
/// byte-exact and case-sensitive, and the helper attaches no semantics: in
/// particular "rw" and "ro" are not enforced, not mutually exclusive and not
/// implied by any other option.
/// Error case: none.
/// Examples: "rw,noatime" has "rw" and "noatime" but not "atime" or "RW".
/// Complexity: O(options * name length).
pub fn fstab_has_option(d: &Fstab, i: Int, name: Str) -> Bool {
  let c = fstab_option_count(d, i);
  if c == 0 { return false; }
  let start: Int = d.option_starts[i];
  var k = 0;
  while k < c {
    let o: Str = d.option_pool[start + k];
    if compare.str_compare(o, name) == 0 { return true; }
    k = k + 1;
  }
  return false;
}

/// Dump value (fifth field) of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(value) with value 0, 1 or 2 for 0 <= i <
/// fstab_entry_count(d), else None. 0 is a real value, so out-of-range is
/// reported as None rather than 0.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_dump(d: &Fstab, i: Int) -> Option[Int] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Int = d.dumps[i];
  return Some(v);
}

/// Pass value (sixth field) of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(value) with value 0, 1 or 2 for 0 <= i <
/// fstab_entry_count(d), else None. 0 is a real value, so out-of-range is
/// reported as None rather than 0.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_pass(d: &Fstab, i: Int) -> Option[Int] {
  if i < 0 || i >= fstab_entry_count(d) { return None; }
  let v: Int = d.passes[i];
  return Some(v);
}

/// 1-based source line number of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: the line number for 0 <= i < fstab_entry_count(d), else 0.
/// Error case: none.
/// Complexity: O(1).
pub fn fstab_line(d: &Fstab, i: Int) -> Int {
  if i < 0 || i >= fstab_entry_count(d) { return 0; }
  let v: Int = d.lines[i];
  return v;
}

/// Zero-based index of the first entry whose mountpoint equals `mountpoint`.
/// Params: d - parsed document; mountpoint - decoded mountpoint query.
/// Returns: the first matching entry index in document order, or -1 when no
/// entry matches. Duplicate mountpoints are preserved by the parser, so this
/// is a documented first-match policy; use fstab_entries_for_mountpoint for
/// every match. Comparison is byte-exact and case-sensitive against the
/// decoded stored mountpoint, so use the decoded spelling ("/mnt/my disk"),
/// not the escaped one ("/mnt/my\040disk").
/// Error case: none.
/// Examples: two "/mnt/dup" entries -> 0.
/// Complexity: O(entries * mountpoint length).
pub fn fstab_mountpoint_index(d: &Fstab, mountpoint: Str) -> Int {
  let n = fstab_entry_count(d);
  var i = 0;
  while i < n {
    let m: Str = d.mountpoints[i];
    if compare.str_compare(m, mountpoint) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Zero-based indexes of every entry whose mountpoint equals `mountpoint`.
/// Params: d - parsed document; mountpoint - decoded mountpoint query.
/// Returns: a fresh Vec of entry indexes in document order (empty when nothing
/// matches). Comparison follows fstab_mountpoint_index.
/// Error case: none.
/// Examples: two "/mnt/dup" entries -> [0, 2].
/// Complexity: O(entries * mountpoint length).
pub fn fstab_entries_for_mountpoint(d: &Fstab, mountpoint: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = fstab_entry_count(d);
  var i = 0;
  while i < n {
    let m: Str = d.mountpoints[i];
    if compare.str_compare(m, mountpoint) == 0 { out.push(i); }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

/// Emit a document in the canonical fstab form.
/// Params: d - parsed document.
/// Returns: one line per entry, the six fields joined by single TABs
/// (`device<TAB>mountpoint<TAB>fstype<TAB>options<TAB>dump<TAB>pass`) and a
/// trailing LF after every line; an empty document emits "". Comments, blank
/// lines and original whitespace are not preserved (source line numbers are
/// not part of the output). device, mountpoint and fstype are re-encoded: a
/// literal backslash, space, TAB or LF in a stored value becomes \134, \040,
/// \011 or \012; the options, dump and pass fields are written verbatim. For a
/// document produced by fstab_parse, emit(parse(x)) is a fixed point: parsing
/// the emitted text yields the same entries and emitting that result
/// reproduces the text byte for byte.
/// Error case: none.
/// Examples: parse("dev mnt ext4 defaults 0 0\n") emits
/// "dev<TAB>mnt<TAB>ext4<TAB>defaults<TAB>0<TAB>0\n".
/// Complexity: O(total output length).
pub fn fstab_emit(d: &Fstab) -> Str {
  var out = "";
  let n = fstab_entry_count(d);
  var i = 0;
  while i < n {
    let dev: Str = d.devices[i];
    let mnt: Str = d.mountpoints[i];
    let fst: Str = d.fstypes[i];
    let opt: Str = d.options_text[i];
    let dump: Int = d.dumps[i];
    let pass_no: Int = d.passes[i];
    let dev_e = _fs_encode_word(dev);
    let mnt_e = _fs_encode_word(mnt);
    let fst_e = _fs_encode_word(fst);
    var line = dev_e;
    line = line + "\t" + mnt_e;
    line = line + "\t" + fst_e;
    line = line + "\t" + opt;
    line = line + "\t" + convert.int_to_string(dump);
    line = line + "\t" + convert.int_to_string(pass_no);
    out = out + line + "\n";
    i = i + 1;
  }
  return out;
}
