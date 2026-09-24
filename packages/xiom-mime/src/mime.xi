// XIOM -- xiom.mime: media type helpers (normalization, extension mapping and
// top-level class checks)
// Port task: create the xiom.mime package as a real, tested, pure-XIOM module
// (no FFI, no IANA registry parse).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact rules, the curated table and the
// test plan):
//   * mime_normalize: ASCII trim, lowercase, drop parameters after ';',
//     trim again;
//   * mime_type_for_extension: ASCII trim + lowercase, leading dots tolerated,
//     curated extension -> media type lookup, unknown input falls back to
//     "application/octet-stream";
//   * mime_extension_for: normalized media type -> primary extension, "" when
//     the type is unknown;
//   * mime_is_text / mime_is_image / mime_is_audio / mime_is_video /
//     mime_is_application: top-level type prefix checks on the normalized
//     value;
//   * mime_type_count: number of curated table entries.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no self methods, no lambdas, no match arms, no
//     Vec[fn] dispatch and no struct values. Scanning is byte-wise over the
//     input Str.
//   * Every byte read is widened once: (string.byte_at(s, i) as Int) & 0xFF,
//     so no UInt8 value is ever compared against an integer literal.
//   * The curated table is a flat Vec[Str] of alternating extension /
//     media-type entries. Table reads are bound to explicitly typed locals
//     (let e: Str = table[i];) before any use, and all Str equality goes
//     through xiom.string.compare.str_compare, never `==` (BUG 17).
//   * Fresh Str values are materialized with xiom.string.builder.sb_to_str;
//     substrings use xiom.string.str_slice.

module xiom.mime

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _MIME_DOT: Int = 46;
const _MIME_SEMI: Int = 59;

// --------------------------------------------------
//  Shared byte helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here.
fn _mime_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for the ASCII whitespace bytes trimmed by mime_normalize: TAB (9),
// LF (10), VT (11), FF (12), CR (13) and space (32).
fn _mime_is_ws(b: Int) -> Bool {
  if b == 9 || b == 10 || b == 11 || b == 12 || b == 13 || b == 32 {
    return true;
  }
  return false;
}

// ASCII lowercase of byte b; every other byte passes through untouched.
fn _mime_to_lower_byte(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b + 32;
  }
  return b;
}

// Byte-wise ASCII lowercase copy of s (UTF-8 bytes >= 0x80 pass through).
fn _mime_lower(s: Str) -> Str {
  let n = s.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push((_mime_to_lower_byte(_mime_byte_at(s, i))) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Copy of s without leading/trailing ASCII whitespace.
fn _mime_trim(s: Str) -> Str {
  let n = s.len();
  var start = 0;
  var start_done = false;
  while start < n && !start_done {
    if _mime_is_ws(_mime_byte_at(s, start)) {
      start = start + 1;
    } else {
      start_done = true;
    }
  }
  var end = n;
  var end_done = false;
  while end > start && !end_done {
    if _mime_is_ws(_mime_byte_at(s, end - 1)) {
      end = end - 1;
    } else {
      end_done = true;
    }
  }
  return string.str_slice(s, start, end);
}

// Index of the first ';' in s, or s.len() when there is none.
fn _mime_semicolon_cut(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  var found = false;
  while i < n && !found {
    if _mime_byte_at(s, i) == _MIME_SEMI {
      found = true;
    } else {
      i = i + 1;
    }
  }
  return i;
}

// Copy of s without any run of leading '.' bytes ("...png" -> "png").
fn _mime_strip_leading_dots(s: Str) -> Str {
  let n = s.len();
  var start = 0;
  var done = false;
  while start < n && !done {
    if _mime_byte_at(s, start) == _MIME_DOT {
      start = start + 1;
    } else {
      done = true;
    }
  }
  return string.str_slice(s, start, n);
}

// True when s starts with prefix (byte-wise; both are plain values).
fn _mime_has_prefix(s: Str, prefix: Str) -> Bool {
  let n = prefix.len();
  if n > s.len() {
    return false;
  }
  var i = 0;
  var ok = true;
  while i < n && ok {
    if _mime_byte_at(s, i) != _mime_byte_at(prefix, i) {
      ok = false;
    }
    i = i + 1;
  }
  return ok;
}

// True when a and b are byte-equal (BUG 17 workaround: str_compare, not `==`).
fn _mime_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Curated extension table
// --------------------------------------------------

// Flat table of (extension, media type) pairs in primary-extension-first
// order: the first pair carrying a media type also carries its primary
// extension for mime_extension_for. 82 entries; see SPEC.md section 3.
fn _mime_table() -> Vec[Str] {
  var t = Vec[Str].new();
  // text/plain family
  t.push("txt"); t.push("text/plain");
  t.push("text"); t.push("text/plain");
  t.push("log"); t.push("text/plain");
  t.push("ini"); t.push("text/plain");
  t.push("cfg"); t.push("text/plain");
  t.push("conf"); t.push("text/plain");
  // text/* (structured)
  t.push("csv"); t.push("text/csv");
  t.push("tsv"); t.push("text/tab-separated-values");
  t.push("html"); t.push("text/html");
  t.push("htm"); t.push("text/html");
  t.push("css"); t.push("text/css");
  t.push("js"); t.push("text/javascript");
  t.push("mjs"); t.push("text/javascript");
  t.push("md"); t.push("text/markdown");
  // application/* (textual data)
  t.push("xml"); t.push("application/xml");
  t.push("json"); t.push("application/json");
  t.push("jsonl"); t.push("application/x-ndjson");
  t.push("ndjson"); t.push("application/x-ndjson");
  t.push("yaml"); t.push("application/yaml");
  t.push("yml"); t.push("application/yaml");
  t.push("toml"); t.push("application/toml");
  t.push("sh"); t.push("application/x-sh");
  t.push("sql"); t.push("application/sql");
  // documents
  t.push("pdf"); t.push("application/pdf");
  t.push("doc"); t.push("application/msword");
  t.push("docx"); t.push("application/vnd.openxmlformats-officedocument.wordprocessingml.document");
  t.push("xls"); t.push("application/vnd.ms-excel");
  t.push("xlsx"); t.push("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
  t.push("ppt"); t.push("application/vnd.ms-powerpoint");
  t.push("pptx"); t.push("application/vnd.openxmlformats-officedocument.presentationml.presentation");
  t.push("rtf"); t.push("application/rtf");
  t.push("epub"); t.push("application/epub+zip");
  // images
  t.push("png"); t.push("image/png");
  t.push("jpg"); t.push("image/jpeg");
  t.push("jpeg"); t.push("image/jpeg");
  t.push("gif"); t.push("image/gif");
  t.push("webp"); t.push("image/webp");
  t.push("svg"); t.push("image/svg+xml");
  t.push("ico"); t.push("image/x-icon");
  t.push("bmp"); t.push("image/bmp");
  t.push("ppm"); t.push("image/x-portable-pixmap");
  t.push("tiff"); t.push("image/tiff");
  t.push("tif"); t.push("image/tiff");
  t.push("avif"); t.push("image/avif");
  // audio
  t.push("wav"); t.push("audio/wav");
  t.push("mp3"); t.push("audio/mpeg");
  t.push("ogg"); t.push("audio/ogg");
  t.push("oga"); t.push("audio/ogg");
  t.push("flac"); t.push("audio/flac");
  t.push("aac"); t.push("audio/aac");
  t.push("m4a"); t.push("audio/mp4");
  t.push("midi"); t.push("audio/midi");
  t.push("mid"); t.push("audio/midi");
  // video
  t.push("mp4"); t.push("video/mp4");
  t.push("m4v"); t.push("video/x-m4v");
  t.push("webm"); t.push("video/webm");
  t.push("mkv"); t.push("video/x-matroska");
  t.push("avi"); t.push("video/x-msvideo");
  t.push("mov"); t.push("video/quicktime");
  t.push("mpg"); t.push("video/mpeg");
  t.push("mpeg"); t.push("video/mpeg");
  t.push("ogv"); t.push("video/ogg");
  // archives
  t.push("zip"); t.push("application/zip");
  t.push("gz"); t.push("application/gzip");
  t.push("tar"); t.push("application/x-tar");
  t.push("bz2"); t.push("application/x-bzip2");
  t.push("xz"); t.push("application/x-xz");
  t.push("zst"); t.push("application/zstd");
  t.push("7z"); t.push("application/x-7z-compressed");
  t.push("rar"); t.push("application/vnd.rar");
  // executables and binary blobs
  t.push("wasm"); t.push("application/wasm");
  t.push("exe"); t.push("application/vnd.microsoft.portable-executable");
  t.push("dll"); t.push("application/vnd.microsoft.portable-executable");
  t.push("bin"); t.push("application/octet-stream");
  t.push("so"); t.push("application/octet-stream");
  t.push("iso"); t.push("application/x-iso9660-image");
  // fonts
  t.push("woff"); t.push("font/woff");
  t.push("woff2"); t.push("font/woff2");
  t.push("ttf"); t.push("font/ttf");
  t.push("otf"); t.push("font/otf");
  // columnar / database files
  t.push("parquet"); t.push("application/vnd.apache.parquet");
  t.push("sqlite"); t.push("application/vnd.sqlite3");
  return t;
}

// Extension -> media type. `ext` must already be normalized (lowercase, no
// leading dots, trimmed). Returns "application/octet-stream" when unknown.
fn _mime_from_ext(ext: Str) -> Str {
  let table = _mime_table();
  let n = table.len();
  var i = 0;
  while i + 1 < n {
    let e: Str = table[i];
    if _mime_streq(e, ext) {
      let m: Str = table[i + 1];
      return m;
    }
    i = i + 2;
  }
  return "application/octet-stream";
}

// Media type -> primary extension. `m` must already be normalized. Returns ""
// when the type is unknown.
fn _mime_ext_of_type(m: Str) -> Str {
  let table = _mime_table();
  let n = table.len();
  var i = 0;
  while i + 1 < n {
    let mt: Str = table[i + 1];
    if _mime_streq(mt, m) {
      let e: Str = table[i];
      return e;
    }
    i = i + 2;
  }
  return "";
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Normalize a media type: ASCII trim, lowercase, drop any parameter section
/// after the first ';', then trim again.
/// Params: m - candidate media type, with or without parameters.
/// Returns: the canonical lowercase type/subtype with no parameters and no
/// surrounding whitespace; "" for empty, whitespace-only or parameter-only
/// input (e.g. "" or "; charset=utf-8").
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_normalize(m: Str) -> Str {
  let trimmed = _mime_trim(m);
  let lowered = _mime_lower(trimmed);
  let cut = _mime_semicolon_cut(lowered);
  return _mime_trim(string.str_slice(lowered, 0, cut));
}

/// Map a file extension to its media type from the curated table.
/// Params: ext - extension with or without a leading dot, any case, optional
/// surrounding whitespace.
/// Returns: the media type registered for ext; "application/octet-stream"
/// when ext is unknown or empty. Input is ASCII-trimmed, lowercased and any
/// leading dots are stripped before the lookup.
/// Error case: none.
/// Complexity: O(table_size + ext.len()).
pub fn mime_type_for_extension(ext: Str) -> Str {
  let e = _mime_strip_leading_dots(_mime_lower(_mime_trim(ext)));
  if e.len() == 0 {
    return "application/octet-stream";
  }
  return _mime_from_ext(e);
}

/// Map a media type to its primary file extension.
/// Params: m - media type, with or without parameters, any case.
/// Returns: the primary extension (no dot) from the curated table; "" when
/// the normalized media type is not registered. Normalization matches
/// mime_normalize, so "Text/HTML; charset=utf-8" yields "html".
/// Error case: none.
/// Complexity: O(table_size + m.len()).
pub fn mime_extension_for(m: Str) -> Str {
  let norm = mime_normalize(m);
  if norm.len() == 0 {
    return "";
  }
  return _mime_ext_of_type(norm);
}

/// True when the normalized media type is in the text top-level class.
/// Params: m - media type, with or without parameters, any case.
/// Returns: true when mime_normalize(m) starts with "text/".
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_is_text(m: Str) -> Bool {
  return _mime_has_prefix(mime_normalize(m), "text/");
}

/// True when the normalized media type is in the image top-level class.
/// Params: m - media type, with or without parameters, any case.
/// Returns: true when mime_normalize(m) starts with "image/".
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_is_image(m: Str) -> Bool {
  return _mime_has_prefix(mime_normalize(m), "image/");
}

/// True when the normalized media type is in the audio top-level class.
/// Params: m - media type, with or without parameters, any case.
/// Returns: true when mime_normalize(m) starts with "audio/".
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_is_audio(m: Str) -> Bool {
  return _mime_has_prefix(mime_normalize(m), "audio/");
}

/// True when the normalized media type is in the video top-level class.
/// Params: m - media type, with or without parameters, any case.
/// Returns: true when mime_normalize(m) starts with "video/".
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_is_video(m: Str) -> Bool {
  return _mime_has_prefix(mime_normalize(m), "video/");
}

/// True when the normalized media type is in the application top-level class.
/// Params: m - media type, with or without parameters, any case.
/// Returns: true when mime_normalize(m) starts with "application/", which
/// includes the unknown-extension fallback "application/octet-stream".
/// Error case: none.
/// Complexity: O(m.len()).
pub fn mime_is_application(m: Str) -> Bool {
  return _mime_has_prefix(mime_normalize(m), "application/");
}

/// Number of (extension, media type) entries in the curated table.
/// Params: none.
/// Returns: the entry count (82 in this version); mime_type_count() is
/// always mime_extension_for-independent: it is table.len() / 2.
/// Error case: none.
/// Complexity: O(table_size).
pub fn mime_type_count() -> Int {
  return _mime_table().len() / 2;
}
