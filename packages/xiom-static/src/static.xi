// XIOM -- xiom.static: static-file response planning
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, stdlib-only static-file layer: MIME typing, stat and sha256 ETags,
// hand-rolled RFC 1123 dates, Cache-Control policy strings, a single-range
// parser, a lexical path-traversal guard and one orchestration function that
// turns (root, url_path, validators, range header, HEAD flag) into a status
// code, ordered response headers and a binary-safe body. See SPEC.md for the
// contract, error catalog and test plan.
//
// What is covered:
//   * static_mime_of, static_etag_stat, static_etag_sha256,
//     static_etag_matches: content validators;
//   * static_http_date, static_last_modified: RFC 1123 dates (the stdlib has
//     no HTTP-date formatter, so the formatting is hand-rolled here);
//   * static_cache_control: one deterministic Cache-Control value;
//   * static_range_parse, static_content_range, static_accept_ranges:
//     single byte-range support (206 / 416);
//   * static_resolve_path: lexical child-path guard (raw %00, absolute path,
//     `..` segments under both separators, backslash, drive colon) plus a
//     manual join;
//   * static_serve: 200/206/304/404/416 orchestration with HEAD support;
//   * static_body_ints: a 0..255 byte-preserving bridge for APIs that only
//     accept Vec[Int].
//
// Deliberate boundaries: no streaming or mmap, no symlink resolution, no
// multi-range, no gzip, no directory indexes and no If-Modified-Since parser
// (the stdlib exposes no public HTTP-date parser). File bytes never travel
// through a Str: a Str round-trip corrupts 0x00 and bytes above 0x7A, so the
// body stays a Vec[UInt8] end to end and static_body_ints is the only bridge.
//
// v0.64.0 notes that shaped this module:
//   * free functions only; all state travels in values or `&` references;
//   * every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison (_byte_at_i);
//   * no `==` on Str anywhere and no Vec[(Str, Str)] anywhere;
//   * every Vec element read is bound to a typed local first.

module xiom.static

use xiom.string;
use xiom.convert;
use xiom.convert.percent;
use xiom.io;
use xiom.io.fs;
use xiom.net.mime;
use xiom.time;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One HTTP response header: the canonical `name` and the raw `value`.
pub type StaticHeader = { name: Str; value: Str; }

/// A parsed single byte-range request.
/// valid: the header was a well-formed single `bytes=...` range. A header
/// that is not valid is ignored by static_serve (the full 200 is served).
/// unsatisfiable: the range is well-formed but cannot be satisfied (the
/// first byte is at/after the size, or a zero-length suffix was requested);
/// static_serve answers 416.
/// start/end: inclusive byte offsets, meaningful only when valid; end is
/// already clamped to size - 1 for satisfiable ranges.
pub type StaticRange = { valid: Bool; unsatisfiable: Bool; start: Int; end: Int; }

/// Cache policy inputs for static_cache_control. `max_age` is in seconds and
/// is clamped to >= 0; `no_store` also selects the `private` visibility.
pub type StaticPolicy = { max_age: Int; immutable: Bool; must_revalidate: Bool; no_store: Bool; }

/// One planned static response: the HTTP status, the ordered headers and the
/// binary-safe body. For HEAD requests the body is empty while the headers
/// still describe the full (or ranged) representation.
pub type StaticResult = { status: Int; headers: Vec[StaticHeader]; body: Vec[UInt8]; }

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every raw byte read in
// this module goes through here, so comparisons never touch raw UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when s starts with the literal byte prefix `prefix` (case-sensitive).
fn _has_prefix(s: Str, prefix: Str) -> Bool {
  let n = s.len();
  let p = prefix.len();
  if n < p {
    return false;
  }
  var i = 0;
  while i < p {
    if _byte_at_i(s, i) != _byte_at_i(prefix, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the raw url_path contains the escape `%00` (the only escape that
// decodes to a NUL byte). This must run BEFORE percent_decode: the stdlib
// decoder builds its result through a C string, so an embedded NUL silently
// truncates the decoded path ("secret%00.txt" would become "secret").
fn _contains_nul_escape(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i + 2 < n {
    if _byte_at_i(s, i) == 37 && _byte_at_i(s, i + 1) == 48 && _byte_at_i(s, i + 2) == 48 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when the decoded path contains a `..` segment delimited by `/` or `\`
// (or by the start/end of the string). "..." and "a..b" are not parent
// segments.
fn _has_parent_segment(p: Str) -> Bool {
  let n = p.len();
  if n < 2 {
    return false;
  }
  var i = 0;
  while i + 1 < n {
    if _byte_at_i(p, i) == 46 && _byte_at_i(p, i + 1) == 46 {
      var before_ok = false;
      if i == 0 {
        before_ok = true;
      } elif _byte_at_i(p, i - 1) == 47 || _byte_at_i(p, i - 1) == 92 {
        before_ok = true;
      }
      var after_ok = false;
      if i + 2 >= n {
        after_ok = true;
      } elif _byte_at_i(p, i + 2) == 47 || _byte_at_i(p, i + 2) == 92 {
        after_ok = true;
      }
      if before_ok && after_ok {
        return true;
      }
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  return false;
}

// --------------------------------------------------
//  Dates and numbers
// --------------------------------------------------

// Two decimal digits, zero-padded (0 -> "00", 9 -> "09", 31 -> "31").
fn _pad2(n: Int) -> Str {
  if n < 0 {
    return int_to_string(n);
  }
  if n < 10 {
    return "0" + int_to_string(n);
  }
  return int_to_string(n);
}

// Three-letter English weekday name for 0 = Sunday .. 6 = Saturday (the
// convention of xiom.time.date_day_of_week).
fn _weekday_name(i: Int) -> Str {
  if i == 0 { return "Sun"; }
  if i == 1 { return "Mon"; }
  if i == 2 { return "Tue"; }
  if i == 3 { return "Wed"; }
  if i == 4 { return "Thu"; }
  if i == 5 { return "Fri"; }
  if i == 6 { return "Sat"; }
  return "Sun";
}

// Three-letter English month name for 1 = Jan .. 12 = Dec.
fn _month_name(m: Int) -> Str {
  if m == 1 { return "Jan"; }
  if m == 2 { return "Feb"; }
  if m == 3 { return "Mar"; }
  if m == 4 { return "Apr"; }
  if m == 5 { return "May"; }
  if m == 6 { return "Jun"; }
  if m == 7 { return "Jul"; }
  if m == 8 { return "Aug"; }
  if m == 9 { return "Sep"; }
  if m == 10 { return "Oct"; }
  if m == 11 { return "Nov"; }
  if m == 12 { return "Dec"; }
  return "Jan";
}

// Parse the decimal digits s[from, to) with saturation at `cap` (cap >= 0).
// The pre-multiply guard keeps the accumulation from overflowing for
// arbitrarily long digit strings, so callers get cap instead of a wrapped
// value.
fn _parse_digits(s: Str, from: Int, to: Int, cap: Int) -> Int {
  var v = 0;
  var i = from;
  while i < to {
    let d = _byte_at_i(s, i) - 48;
    if v > (cap - d) / 10 {
      return cap;
    }
    v = v * 10 + d;
    if v > cap {
      return cap;
    }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Validators
// --------------------------------------------------

/// MIME type for a file path, delegated to xiom.net.mime.mime_type_of.
/// Params: path - a file path (only the extension is inspected).
/// Returns: the lower-case MIME type, or "application/octet-stream" when the
/// extension is unknown or absent.
/// Error case: none.
/// Complexity: O(1). Pure.
pub fn static_mime_of(path: Str) -> Str {
  return mime.mime_type_of(path);
}

/// O(1) entity tag derived from size and mtime: the quoted string
/// `"<size>-<mtime>"`. This is the primary ETag (a stat is cheaper than
/// hashing the file); use static_etag_sha256 for a strong content tag.
/// Params: size - the file size in bytes; mtime - the Unix mtime in seconds.
/// Returns: the quoted tag, e.g. `"1024-1600000000"`.
/// Error case: none.
/// Complexity: O(1). Pure.
pub fn static_etag_stat(size: Int, mtime: Int) -> Str {
  return "\"" + int_to_string(size) + "-" + int_to_string(mtime) + "\"";
}

/// Strong entity tag over the content bytes: a quoted lowercase SHA-256 hex
/// string, delegated to xiom.net.mime.etag_new.
/// Params: data - the content bytes.
/// Returns: the quoted tag (66 characters).
/// Error case: none.
/// Complexity: O(n). Pure.
pub fn static_etag_sha256(data: &Vec[UInt8]) -> Str {
  return mime.etag_new(data);
}

/// Test an entity tag against an If-None-Match header value, delegated to
/// xiom.net.mime.etag_matches.
/// Params: etag - the current entity tag (quoted); if_none_match - the header
/// value: `*`, a single tag, a comma-separated list, optionally W/ prefixed
/// and whitespace padded.
/// Returns: true when any list entry matches etag.
/// Error case: none.
/// Complexity: O(n). Pure.
pub fn static_etag_matches(etag: Str, if_none_match: Str) -> Bool {
  return mime.etag_matches(etag, if_none_match);
}

/// RFC 1123 / IMF-fixdate string for a Unix epoch in UTC:
/// `W, DD Mon YYYY HH:MM:SS GMT`. The stdlib has no HTTP-date formatter, so
/// the weekday (via time.date_day_of_week, 0 = Sunday) and the zero-padded
/// fields are formatted by hand. Epochs below 0 clamp to 0 (the Unix epoch).
/// Params: epoch - seconds since 1970-01-01T00:00:00Z.
/// Returns: e.g. "Thu, 01 Jan 1970 00:00:00 GMT".
/// Error case: none.
/// Complexity: O(1).
pub fn static_http_date(epoch: Int) -> Str {
  var e = epoch;
  if e < 0 {
    e = 0;
  }
  let dt = time.datetime_from_epoch(e);
  let wd = time.date_day_of_week(dt.year, dt.month, dt.day);
  return _weekday_name(wd) + ", " + _pad2(dt.day) + " " + _month_name(dt.month) + " " + int_to_string(dt.year) + " " + _pad2(dt.hour) + ":" + _pad2(dt.minute) + ":" + _pad2(dt.second) + " GMT";
}

/// `Last-Modified` header for an epoch; the value is static_http_date(epoch).
/// Params: epoch - the file mtime in seconds.
/// Returns: a StaticHeader named "Last-Modified".
/// Error case: none.
/// Complexity: O(1).
pub fn static_last_modified(epoch: Int) -> StaticHeader {
  return StaticHeader{ name: "Last-Modified"; value: static_http_date(epoch); };
}

/// Deterministic Cache-Control value. The order is always
/// `<public|private>, max-age=<N>[, immutable][, must-revalidate][, no-store]`.
/// `no_store` selects the `private` visibility and appends `no-store`; a
/// negative `max_age` clamps to 0.
/// Params: p - the policy inputs.
/// Returns: e.g. "public, max-age=3600" or "private, max-age=0, no-store".
/// Error case: none.
/// Complexity: O(1). Pure.
pub fn static_cache_control(p: &StaticPolicy) -> Str {
  var out = "public";
  if p.no_store {
    out = "private";
  }
  var age = p.max_age;
  if age < 0 {
    age = 0;
  }
  out = out + ", max-age=" + int_to_string(age);
  if p.immutable {
    out = out + ", immutable";
  }
  if p.must_revalidate {
    out = out + ", must-revalidate";
  }
  if p.no_store {
    out = out + ", no-store";
  }
  return out;
}

// --------------------------------------------------
//  Ranges
// --------------------------------------------------

// The three StaticRange outcomes: malformed, well-formed but unsatisfiable,
// and satisfiable.
fn _range_invalid() -> StaticRange {
  return StaticRange{ valid: false; unsatisfiable: false; start: 0; end: 0; };
}

fn _range_unsat() -> StaticRange {
  return StaticRange{ valid: true; unsatisfiable: true; start: 0; end: 0; };
}

fn _range_ok(start: Int, end: Int) -> StaticRange {
  return StaticRange{ valid: true; unsatisfiable: false; start: start; end: end; };
}

/// Parse a single byte-range request against a resource size.
/// Grammar accepted (case-sensitive `bytes=` prefix): `bytes=a-b` with a <= b,
/// `bytes=a-` (open-ended) and `bytes=-n` (suffix). Anything else - a missing
/// or wrong prefix, a comma (multi-range is unsupported), whitespace, signs,
/// a second dash, empty digits, or b < a - yields valid = false and is meant
/// to be ignored by the caller (serve the full 200).
/// Outcomes: valid && !unsatisfiable -> 206 with [start, end]; valid &&
/// unsatisfiable (first byte >= size, or the zero-length suffix `bytes=-0`) ->
/// 416; !valid -> ignore the header.
/// Params: header - the raw Range header value; size - the resource size in
/// bytes (negative values clamp to 0).
/// Returns: a StaticRange. `end` is clamped to size - 1 for satisfiable
/// ranges; digit strings that overflow Int saturate at the size, so huge
/// offsets behave as >= size instead of wrapping.
/// Error case: none.
/// Complexity: O(header length). Pure.
pub fn static_range_parse(header: Str, size: Int) -> StaticRange {
  var siz = size;
  if siz < 0 {
    siz = 0;
  }
  if header.len() < 8 {
    return _range_invalid();
  }
  if !_has_prefix(header, "bytes=") {
    return _range_invalid();
  }
  let n = header.len();
  var dash = -1;
  var i = 6;
  while i < n {
    let c = _byte_at_i(header, i);
    if c == 44 {
      return _range_invalid();
    }
    if c == 45 {
      if dash >= 0 {
        return _range_invalid();
      }
      dash = i;
    } elif c < 48 || c > 57 {
      return _range_invalid();
    }
    i = i + 1;
  }
  if dash < 0 {
    return _range_invalid();
  }
  let a_len = dash - 6;
  let b_len = n - dash - 1;
  if a_len == 0 && b_len == 0 {
    return _range_invalid();
  }
  if a_len == 0 {
    let suffix = _parse_digits(header, dash + 1, n, siz);
    if suffix == 0 || siz == 0 {
      return _range_unsat();
    }
    if suffix >= siz {
      return _range_ok(0, siz - 1);
    }
    return _range_ok(siz - suffix, siz - 1);
  }
  let a = _parse_digits(header, 6, dash, siz);
  if a >= siz {
    return _range_unsat();
  }
  if b_len == 0 {
    return _range_ok(a, siz - 1);
  }
  let b = _parse_digits(header, dash + 1, n, siz);
  if b < a {
    return _range_invalid();
  }
  var end = b;
  if end > siz - 1 {
    end = siz - 1;
  }
  return _range_ok(a, end);
}

/// `Content-Range` header for a satisfied range:
/// `bytes <start>-<end>/<size>` with inclusive offsets.
/// Params: start, end - inclusive byte offsets; size - the full resource size.
/// Returns: a StaticHeader named "Content-Range".
/// Error case: none.
/// Complexity: O(1). Pure.
pub fn static_content_range(start: Int, end: Int, size: Int) -> StaticHeader {
  return StaticHeader{ name: "Content-Range"; value: "bytes " + int_to_string(start) + "-" + int_to_string(end) + "/" + int_to_string(size); };
}

/// `Accept-Ranges: bytes` marker: this server supports single byte ranges.
/// Returns: a StaticHeader named "Accept-Ranges".
/// Error case: none.
/// Complexity: O(1). Pure.
pub fn static_accept_ranges() -> StaticHeader {
  return StaticHeader{ name: "Accept-Ranges"; value: "bytes"; };
}

// --------------------------------------------------
//  Path resolution
// --------------------------------------------------

/// Resolve an untrusted URL path against a trusted root directory.
/// Steps: reject a raw `%00` escape (a decoded NUL would truncate the path);
/// percent_decode; reject an empty decoded path; reject a leading '/' (an
/// absolute path); reject any `..` segment delimited by '/' or '\'; reject
/// any backslash (a second Windows separator, so patterns such as `..\x`
/// never reach a filesystem call); reject any ':' (drive letters and NTFS
/// alternate data streams). "." segments are allowed. The result is a manual
/// lexical join: one '/' is inserted unless the root already ends with '/' or
/// '\'. Preview of check order: NUL escape, decode, decoded NUL, empty,
/// leading '/', `..` segment, backslash, colon.
/// Params: root - the trusted directory (caller-provided, never validated);
/// url_path - the untrusted request path, without the query string.
/// Returns: Ok(joined absolute-or-relative path) for a safe child path.
/// Error case: Err with one of "static: NUL byte in path", "static: invalid
/// percent-encoding", "static: empty path", "static: absolute path", "static:
/// parent segment in path", "static: backslash in path", "static: drive
/// colon in path".
/// Complexity: O(root + url_path length). Pure.
/// Note: lexical guard only - no symlink resolution, no case folding.
pub fn static_resolve_path(root: Str, url_path: Str) -> Result[Str, Str] {
  if _contains_nul_escape(url_path) {
    return Err("static: NUL byte in path");
  }
  let dec = percent.percent_decode(url_path);
  if !dec.is_ok {
    return Err("static: invalid percent-encoding");
  }
  let p: Str = dec.value;
  let n = p.len();
  if n == 0 {
    return Err("static: empty path");
  }
  if _byte_at_i(p, 0) == 47 {
    return Err("static: absolute path");
  }
  var i = 0;
  while i < n {
    if _byte_at_i(p, i) == 0 {
      return Err("static: NUL byte in path");
    }
    i = i + 1;
  }
  if _has_parent_segment(p) {
    return Err("static: parent segment in path");
  }
  i = 0;
  while i < n {
    if _byte_at_i(p, i) == 92 {
      return Err("static: backslash in path");
    }
    i = i + 1;
  }
  i = 0;
  while i < n {
    if _byte_at_i(p, i) == 58 {
      return Err("static: drive colon in path");
    }
    i = i + 1;
  }
  var joined = root;
  if root.len() > 0 {
    let last = _byte_at_i(root, root.len() - 1);
    if last != 47 && last != 92 {
      joined = joined + "/";
    }
  } else {
    joined = "/";
  }
  joined = joined + p;
  return Ok(joined);
}

// --------------------------------------------------
//  Orchestration
// --------------------------------------------------

// A header builder helper.
fn _hdr(name: Str, value: Str) -> StaticHeader {
  return StaticHeader{ name: name; value: value; };
}

// 200 header block for a full representation (also used for HEAD).
fn _headers_full(content_type: Str, length: Int, etag: Str, last_modified: Str, cache: Str) -> Vec[StaticHeader] {
  var out = Vec[StaticHeader].new();
  out.push(_hdr("Content-Type", content_type));
  out.push(_hdr("Content-Length", int_to_string(length)));
  out.push(_hdr("ETag", etag));
  out.push(_hdr("Last-Modified", last_modified));
  out.push(_hdr("Cache-Control", cache));
  out.push(static_accept_ranges());
  return out;
}

// 206 header block: the ranged representation plus Content-Range.
fn _headers_partial(content_type: Str, length: Int, start: Int, end: Int, size: Int, etag: Str, last_modified: Str, cache: Str) -> Vec[StaticHeader] {
  var out = Vec[StaticHeader].new();
  out.push(_hdr("Content-Type", content_type));
  out.push(_hdr("Content-Length", int_to_string(length)));
  out.push(static_content_range(start, end, size));
  out.push(_hdr("ETag", etag));
  out.push(_hdr("Last-Modified", last_modified));
  out.push(_hdr("Cache-Control", cache));
  out.push(static_accept_ranges());
  return out;
}

// 304 header block: validators plus the cache policy, no entity headers.
fn _headers_not_modified(etag: Str, last_modified: Str, cache: Str) -> Vec[StaticHeader] {
  var out = Vec[StaticHeader].new();
  out.push(_hdr("ETag", etag));
  out.push(_hdr("Last-Modified", last_modified));
  out.push(_hdr("Cache-Control", cache));
  return out;
}

// 416 header block: unsatisfied-range form of Content-Range.
fn _headers_unsatisfiable(size: Int) -> Vec[StaticHeader] {
  var out = Vec[StaticHeader].new();
  out.push(_hdr("Content-Range", "bytes */" + int_to_string(size)));
  out.push(static_accept_ranges());
  return out;
}

// The single 404 shape: no headers and no body (no information leak).
fn _not_found() -> StaticResult {
  return StaticResult{ status: 404; headers: Vec[StaticHeader].new(); body: Vec[UInt8].new(); };
}

// Read the whole file and build a 200 (HEAD empties the body, the headers
// still carry the full Content-Length).
fn _serve_full(path: Str, content_type: Str, size: Int, etag: Str, last_modified: Str, cache: Str, is_head: Bool) -> StaticResult {
  let read = fs.fs_read(path);
  if !read.is_ok {
    return _not_found();
  }
  var body: Vec[UInt8] = Vec[UInt8].new();
  if !is_head {
    body = read.value;
  }
  return StaticResult{ status: 200; headers: _headers_full(content_type, size, etag, last_modified, cache); body: body; };
}

/// Plan one static-file response. The pipeline is: resolve the safe child
/// path -> stat it (a directory or a stat error is 404) -> derive MIME, the
/// stat ETag and Last-Modified -> evaluate If-None-Match (304 wins over
/// Range) -> parse the Range header -> read the bytes.
/// Statuses: 200 full body; 206 partial (single range, byte-exact via
/// fs_read_range); 304 empty body with ETag/Last-Modified/Cache-Control when
/// if_none_match matches; 404 for resolve/stat/read errors, directories and
/// files above 2 GiB - 1 (fs_read_range seeks with Int32); 416 for a
/// well-formed but unsatisfiable range (Content-Range: bytes */size). A
/// malformed Range header is ignored (200). HEAD returns the same status and
/// headers with an empty body, including the would-be Content-Length.
/// Params: root - trusted root directory; url_path - untrusted path without
/// query; if_none_match - If-None-Match value ("" to skip); range_header -
/// Range value ("" to skip); is_head - true for HEAD requests; policy - the
/// cache policy.
/// Returns: a StaticResult; error strings never travel inside it - I/O
/// failures collapse to 404.
/// Error case: none.
/// Complexity: O(body bytes read) plus one stat.
pub fn static_serve(root: Str, url_path: Str, if_none_match: Str, range_header: Str, is_head: Bool, policy: &StaticPolicy) -> StaticResult {
  let resolved = static_resolve_path(root, url_path);
  if !resolved.is_ok {
    return _not_found();
  }
  let path: Str = resolved.value;
  let meta_r = io.metadata(path);
  if !meta_r.is_ok {
    return _not_found();
  }
  let meta = meta_r.value;
  if !meta.is_file {
    return _not_found();
  }
  let size: Int = meta.size;
  if size > 2147483647 {
    return _not_found();
  }
  let mtime: Int = meta.modified;
  let etag = static_etag_stat(size, mtime);
  let last_modified = static_http_date(mtime);
  let cache = static_cache_control(policy);
  if if_none_match.len() > 0 {
    if static_etag_matches(etag, if_none_match) {
      return StaticResult{ status: 304; headers: _headers_not_modified(etag, last_modified, cache); body: Vec[UInt8].new(); };
    }
  }
  let content_type = static_mime_of(path);
  if range_header.len() == 0 {
    return _serve_full(path, content_type, size, etag, last_modified, cache, is_head);
  }
  let r = static_range_parse(range_header, size);
  if !r.valid {
    return _serve_full(path, content_type, size, etag, last_modified, cache, is_head);
  }
  if r.unsatisfiable {
    return StaticResult{ status: 416; headers: _headers_unsatisfiable(size); body: Vec[UInt8].new(); };
  }
  let length = r.end - r.start + 1;
  let read = fs.fs_read_range(path, r.start, length);
  if !read.is_ok {
    return _not_found();
  }
  var body: Vec[UInt8] = Vec[UInt8].new();
  if !is_head {
    body = read.value;
  }
  return StaticResult{ status: 206; headers: _headers_partial(content_type, length, r.start, r.end, size, etag, last_modified, cache); body: body; };
}

/// Byte-preserving bridge from Vec[UInt8] to Vec[Int]: out[i] = body[i] in
/// 0..255 for every i. No Str is involved, so 0x00 and bytes above 0x7A
/// survive; this is the sanctioned way to hand a body to numeric-only APIs.
/// Params: body - the raw bytes.
/// Returns: a new Vec[Int] with the same length, values 0..255.
/// Error case: none.
/// Complexity: O(n).
pub fn static_body_ints(body: &Vec[UInt8]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < body.len() {
    let b: UInt8 = body[i];
    out.push((b as Int) & 0xFF);
    i = i + 1;
  }
  return out;
}
