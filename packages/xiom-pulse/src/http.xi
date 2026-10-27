// XIOM PULSE -- HTTP/1.1 request parsing and response building.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure, socket-free helpers (unit-testable). Reads are done by the caller
// through xiom.net.socket (raw fd) because C-PULSE-01 disables one-arg
// `.read(...)` methods on the pinned compiler.
module xiom.pulse.http

use xiom.string;
use xiom.string.slice;
use xiom.string.compare;
use xiom.convert.parse;
use xiom.net.server;

/// PulseRequest - a parsed HTTP/1.1 request head plus buffered body bytes.
pub type PulseRequest = {
  method: Str;
  target: Str;
  version: Str;
  header_names: Vec[Str];
  header_values: Vec[Str];
  body: Vec[UInt8];
  ok: Bool;
  error: Str;
}

/// RouteResult - status code + JSON body for one route dispatch.
pub type RouteResult = {
  status: Int;
  body: Str;
}

/// DEFAULT_SERVER_TOKEN is the neutral, version-free Server header token.
/// Consumers (Station or any other product) replace it through
/// `set_server_token`/`app.app_set_server_token` so the response advertises
/// their own release identity. Version reporting lives in `pulse_version()`.
const DEFAULT_SERVER_TOKEN: Str = "xiom-pulse";

// Process-wide Server token consulted by both response builders. The loop is
// single-threaded, so a plain module global is the intended seam.
var server_token_value: Str = DEFAULT_SERVER_TOKEN;

/// server_token returns the current Server header token
/// (default "xiom-pulse", version-free). Complexity: O(1).
pub fn server_token() -> Str {
  return server_token_value;
}

/// set_server_token replaces the Server header token used by every response
/// builder. The token must be non-empty printable ASCII (32..126) so it can
/// never inject CR/LF or another header line; invalid input leaves the
/// current token unchanged and returns false. RFC 9110 `Server:
/// <token>` shape. Complexity: O(token).
pub fn set_server_token(token: Str) -> Bool {
  if token.len() == 0 { return false; }
  var i: Int = 0;
  while i < token.len() {
    let b = token.byte_at(i);
    if b < 32u8 || b > 126u8 { return false; }
    i = i + 1;
  }
  server_token_value = token;
  return true;
}

/// server_header_line returns the complete `Server: <token>` header line
/// (without CRLF) for the current token. Complexity: O(token). Pure.
fn server_header_line() -> Str {
  return "Server: " + server_token_value;
}

/// str_to_bytes converts Str to its raw bytes. Thin alias for the stdlib
/// `xiom.string.slice.str_bytes` (submodule import; the root `xiom.string`
/// does not re-export submodule functions). Complexity: O(n). Pure.
pub fn str_to_bytes(s: Str) -> Vec[UInt8] {
  return slice.str_bytes(s);
}

/// bytes_to_str converts the byte span [start, end) to Str.
/// Complexity: O(n). Pure.
pub fn bytes_to_str(buf: &Vec[UInt8], start: Int, end: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = start;
  while i < end && i < buf.len() {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// find_header_end returns the index of the CRLFCRLF terminator, or -1.
/// Complexity: O(n). Pure.
pub fn find_header_end(buf: &Vec[UInt8]) -> Int {
  let n = buf.len();
  if n < 4 { return -1; }
  var i: Int = 0;
  while i + 4 <= n {
    if buf[i] == 13u8 && buf[i + 1] == 10u8 && buf[i + 2] == 13u8 && buf[i + 3] == 10u8 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// header_limit_bytes returns the max request-head size the server buffers.
/// Complexity: O(1). Pure.
pub fn header_limit_bytes() -> Int {
  return 16384;
}

/// header_overflow is true when no CRLFCRLF terminator was seen within the
/// head-size limit (slow-client / oversized-header guard). O(n). Pure.
pub fn header_overflow(raw: &Vec[UInt8]) -> Bool {
  return find_header_end(raw) < 0 && raw.len() > header_limit_bytes();
}

/// header_count_limit returns the max accepted header lines. O(1). Pure.
pub fn header_count_limit() -> Int {
  return 100;
}

/// find_crlf returns the index of the next CRLF in [from, limit), or -1.
/// Complexity: O(n). Pure.
fn find_crlf(buf: &Vec[UInt8], from: Int, limit: Int) -> Int {  var i: Int = from;
  while i + 2 <= limit && i + 2 <= buf.len() {
    if buf[i] == 13u8 && buf[i + 1] == 10u8 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// parse_request parses the request line, headers and body (Content-Length
/// or chunked transfer-encoding) from raw bytes. Never traps: failures set
/// ok=false + error.
///
/// Since 2026-10-07 the syntax layer is the shared stdlib parser
/// (`xiom.net.server.server_parse_request`, built for PULSE); this adapter
/// keeps PULSE's contract:
///   - 100-header cap (error "too many headers") in addition to the
///     16 KiB read-loop guard (header_overflow);
///   - header names arrive lowercased from the stdlib; `header_get` stays
///     case-insensitive, so callers are unaffected;
///   - header values are trimmed (stdlib strips one leading space only);
///   - invalid Content-Length (negative/non-numeric) is now REJECTED
///     (hardening; the differential probe pins it on both parsers);
///   - `Transfer-Encoding: chunked` bodies are decoded (chunk extensions
///     ignored, trailers validated + skipped, 1 MiB decoded cap, errors:
///     "incomplete/malformed chunked body", "chunked body too large");
///     any other transfer-coding keeps the body empty for the 501 guard.
///   - a non-chunked declared Content-Length above the body cap is
///     rejected as "body too large" before any body bytes are copied
///     (hardening: a truncated oversized body must never parse as ok).
/// Complexity: O(n). Pure.
pub fn parse_request(raw: &Vec[UInt8]) -> PulseRequest {
  var req: PulseRequest = PulseRequest{
    method: "";
    target: "";
    version: "";
    header_names: Vec[Str].new();
    header_values: Vec[Str].new();
    body: Vec[UInt8].new();
    ok: false;
    error: "";
  };

  let hdr_end = find_header_end(raw);
  if hdr_end < 0 {
    req.error = "incomplete headers";
    return req;
  }

  // PULSE cap: count header lines before handing the raw bytes over.
  let line_end = find_crlf(raw, 0, hdr_end + 2);
  if line_end < 0 || line_end > hdr_end {
    req.error = "malformed request line";
    return req;
  }
  var pos: Int = line_end + 2;
  var hcount: Int = 0;
  while pos < hdr_end {
    let next = find_crlf(raw, pos, hdr_end + 2);
    if next < 0 { break; }
    if next > pos {
      hcount = hcount + 1;
      if hcount > header_count_limit() {
        req.error = "too many headers";
        return req;
      }
    }
    pos = next + 2;
  }

  let sr = server.server_parse_request(raw);
  if sr.is_none {
    req.error = "malformed request";
    return req;
  }
  let r = sr.value;
  req.method = r.method;
  req.target = r.target;
  req.version = r.version;

  // Copy the parser's header list into the parallel Vecs the request API
  // exposes. Pre-size both (one allocation each instead of grow-doubling)
  // and trim only when the parser left surrounding whitespace: the parser
  // already strips the leading space and the CRLF, so the common case is a
  // straight move and we avoid a fresh Str per header.
  var names: Vec[Str] = Vec[Str].with_capacity(8 as UInt);
  var values: Vec[Str] = Vec[Str].with_capacity(8 as UInt);
  var hi: Int = 0;
  while hi < r.headers.len() {
    let hn: Str = r.headers[hi].0;
    let rv: Str = r.headers[hi].1;
    names.push(hn);
    var tv: Str = rv;
    if rv.len() > 0 {
      let fb: UInt8 = rv.byte_at(0);
      let lb: UInt8 = rv.byte_at(rv.len() - 1);
      if fb == 32u8 || lb == 32u8 { tv = string.str_trim(rv); }
    }
    values.push(tv);
    hi = hi + 1;
  }
  req.header_names = names;
  req.header_values = values;

  // Transfer-Encoding: `chunked` is decoded here (v0.64.1-era smuggling
  // guard kept: any OTHER coding stays unread and the route layer answers
  // 501; TE + Content-Length together are rejected by the route layer).
  let te = header_get(&req, "transfer-encoding");
  if te.len() > 0 {
    if !te_is_chunked(te) {
      req.ok = true;
      return req;
    }
    let dec = decode_chunked(raw, hdr_end, body_limit_bytes());
    if !dec.ok {
      req.error = dec.error;
      return req;
    }
    req.body = dec.body;
    req.ok = true;
    return req;
  }

  // Hardening (2026-10-17): reject an oversized declared Content-Length
  // before copying the body. The read loop may hand us a complete head
  // plus only part of a declared body; trusting the declaration would
  // return ok=true with truncated bytes and dispatch partial data.
  // Chunked bodies are capped separately by decode_chunked.
  if content_length_of(raw, hdr_end) > body_limit_bytes() {
    req.error = "body too large";
    return req;
  }

  var bs: Int = r.body_start;
  var be: Int = r.body_start + r.body_len;
  if be > raw.len() { be = raw.len(); }
  var bi: Int = bs;
  while bi < be {
    req.body.push(raw[bi]);
    bi = bi + 1;
  }

  req.ok = true;
  return req;
}

/// header_get returns the value of the named header (case-insensitive),
/// or "" when absent. Complexity: O(headers). Pure.
pub fn header_get(req: &PulseRequest, name: Str) -> Str {
  var i: Int = 0;
  while i < req.header_names.len() {
    let hname = req.header_names[i];
    if str_eq_ignore_case(hname, name) {
      return req.header_values[i];
    }
    i = i + 1;
  }
  return "";
}

/// connection_close_requested is true when the peer asked for close
/// (`Connection` comma-token "close", case-insensitive) or spoke a
/// version below HTTP/1.1 -- a 1.0 peer never gets keep-alive, even with
/// `Connection: keep-alive` (h11 rule; deliberately adopted).
/// Complexity: O(value). Pure.
pub fn connection_close_requested(req: &PulseRequest) -> Bool {
  if req.version != "HTTP/1.1" { return true; }
  let v = header_get(req, "connection");
  if v.len() == 0 { return false; }
  let lv = string.str_lower(v);
  var i: Int = 0;
  var start: Int = 0;
  while i <= lv.len() {
    if i == lv.len() || lv.byte_at(i) == 44u8 {
      let tok = string.str_trim(string.str_slice(lv, start, i));
      if tok == "close" { return true; }
      start = i + 1;
    }
    i = i + 1;
  }
  return false;
}

/// content_length_of returns the request's Content-Length parsed from the
/// header span [0, hdr_end), or 0 when absent/invalid. O(n). Pure.
pub fn content_length_of(raw: &Vec[UInt8], hdr_end: Int) -> Int {
  let v = raw_header_value(raw, hdr_end, "content-length");
  if v.len() == 0 { return 0; }
  let pr = parse_int(v);
  if pr.is_ok {
    return pr.value;
  }
  return 0;
}

/// raw_header_value returns the first value of the named header
/// (case-insensitive) from the head span [0, hdr_end) of raw bytes, or "".
/// Complexity: O(n). Pure.
pub fn raw_header_value(raw: &Vec[UInt8], hdr_end: Int, name: Str) -> Str {
  var pos: Int = 0;
  var line_end = find_crlf(raw, pos, hdr_end + 2);
  if line_end < 0 { return ""; }
  pos = line_end + 2;
  while pos < hdr_end {
    let next = find_crlf(raw, pos, hdr_end + 2);
    if next < 0 { break; }
    let line = bytes_to_str(raw, pos, next);
    var col: Int = -1;
    match string.str_index_of(line, ":") {
      Some(v) => { col = v; },
      None => { col = -1; },
    }
    if col > 0 {
      let hname = string.str_slice(line, 0, col);
      if str_eq_ignore_case(hname, name) {
        return string.str_trim(string.str_slice(line, col + 1, line.len()));
      }
    }
    pos = next + 2;
  }
  return "";
}

/// transfer_encoding_of returns the lowercased, trimmed Transfer-Encoding
/// value from the request head, or "". Complexity: O(n). Pure.
pub fn transfer_encoding_of(raw: &Vec[UInt8], hdr_end: Int) -> Str {
  let v = raw_header_value(raw, hdr_end, "transfer-encoding");
  return string.str_lower(string.str_trim(v));
}

/// te_is_chunked is true only for the exact single coding "chunked"
/// (case-insensitive). Lists (`gzip, chunked`) and other codings are false;
/// the route layer answers those 501. Complexity: O(n). Pure.
pub fn te_is_chunked(te: Str) -> Bool {
  let t = string.str_lower(string.str_trim(te));
  return t == "chunked";
}

/// body_limit_bytes returns the max decoded request body the server accepts
/// (keep in sync with `server.xi MAX_BODY`). Complexity: O(1). Pure.
pub fn body_limit_bytes() -> Int {
  return 1048576;
}

/// hex_digit returns the value of hex char at index i (lowercased), or -1.
/// Complexity: O(1). Pure.
fn hex_digit(s: Str, i: Int) -> Int {
  let ch = string.str_lower(string.str_slice(s, i, i + 1));
  match string.str_index_of("0123456789abcdef", ch) {
    Some(v) => { return v; },
    None => { return -1; },
  }
  return -1;
}

/// parse_hex_uint parses 1..8 hex digits (chunk sizes); -1 on empty,
/// overlong, or non-hex input. Complexity: O(n). Pure.
fn parse_hex_uint(s: Str) -> Int {
  let n = s.len();
  if n == 0 || n > 8 { return -1; }
  var v: Int = 0;
  var i: Int = 0;
  while i < n {
    let d = hex_digit(s, i);
    if d < 0 { return -1; }
    v = v * 16 + d;
    i = i + 1;
  }
  return v;
}

/// chunk_size_text strips an optional chunk extension (`;...`) and trims a
/// chunk-size line. Complexity: O(n). Pure.
fn chunk_size_text(line: Str) -> Str {
  var cut: Int = line.len();
  match string.str_index_of(line, ";") {
    Some(v) => { cut = v; },
    None => { cut = line.len(); },
  }
  return string.str_trim(string.str_slice(line, 0, cut));
}

/// chunked_state scans the chunked framing after `hdr_end`:
///   1 = terminating zero chunk + trailers fully present
///   0 = need more bytes
///  -1 = malformed framing (bad size line, bad chunk CRLF, bad trailer)
/// Complexity: O(n). Pure.
pub fn chunked_state(raw: &Vec[UInt8], hdr_end: Int) -> Int {
  var p: Int = hdr_end + 4;
  var guard: Int = 0;
  while guard < 1000000 {
    guard = guard + 1;
    if p > raw.len() { return 0; }
    let le = find_crlf(raw, p, raw.len());
    if le < 0 {
      if raw.len() - p > 1024 { return -1; }
      return 0;
    }
    let sz = parse_hex_uint(chunk_size_text(bytes_to_str(raw, p, le)));
    if sz < 0 { return -1; }
    if sz == 0 {
      var q: Int = le + 2;
      var tg: Int = 0;
      while tg < 1000 {
        tg = tg + 1;
        let te2 = find_crlf(raw, q, raw.len());
        if te2 < 0 {
          if raw.len() - q > 1024 { return -1; }
          return 0;
        }
        if te2 == q { return 1; }
        q = te2 + 2;
      }
      return -1;
    }
    let de: Int = le + 2 + sz;
    if de + 2 > raw.len() { return 0; }
    if raw[de] != 13u8 || raw[de + 1] != 10u8 { return -1; }
    p = de + 2;
  }
  return -1;
}

/// chunked_end returns the offset just past the terminating zero chunk
/// (trailers included), or -1 when incomplete/malformed. Mirror of the
/// chunked_state walk that also yields the consumed length for the
/// keep-alive trailing buffer. Complexity: O(n). Pure.
fn chunked_end(raw: &Vec[UInt8], hdr_end: Int) -> Int {
  var p: Int = hdr_end + 4;
  var guard: Int = 0;
  while guard < 1000000 {
    guard = guard + 1;
    if p > raw.len() { return -1; }
    let le = find_crlf(raw, p, raw.len());
    if le < 0 { return -1; }
    let sz = parse_hex_uint(chunk_size_text(bytes_to_str(raw, p, le)));
    if sz < 0 { return -1; }
    if sz == 0 {
      var q: Int = le + 2;
      var tg: Int = 0;
      while tg < 1000 {
        tg = tg + 1;
        let te2 = find_crlf(raw, q, raw.len());
        if te2 < 0 { return -1; }
        if te2 == q { return te2 + 2; }
        q = te2 + 2;
      }
      return -1;
    }
    let de: Int = le + 2 + sz;
    if de + 2 > raw.len() { return -1; }
    if raw[de] != 13u8 || raw[de + 1] != 10u8 { return -1; }
    p = de + 2;
  }
  return -1;
}

/// framed_end returns the byte offset just past the complete request
/// framed by `raw` (head + body), or -1 when incomplete, oversize, or
/// TE-framed with an unsupported coding -- the keep-alive loop closes
/// after responding on -1 (an unread body must never be reused as a
/// request). Complexity: O(n). Pure.
pub fn framed_end(raw: &Vec[UInt8]) -> Int {
  let he = find_header_end(raw);
  if he < 0 { return -1; }
  let te = transfer_encoding_of(raw, he);
  if te.len() > 0 {
    if !te_is_chunked(te) { return -1; }
    return chunked_end(raw, he);
  }
  let cl = content_length_of(raw, he);
  if cl > body_limit_bytes() { return -1; }
  let end = he + 4 + cl;
  if end > raw.len() { return -1; }
  return end;
}

/// ChunkedBody - decoded chunked-transfer body or the failure reason.
pub type ChunkedBody = {
  body: Vec[UInt8];
  ok: Bool;
  error: Str;
}

/// decode_chunked decodes the chunked framing after `hdr_end`, enforcing
/// `max_body` on the DECODED size. Fails close on any inconsistency (the
/// caller should have waited for chunked_state == 1 first). Trailers are
/// validated and skipped. Complexity: O(n). Pure.
pub fn decode_chunked(raw: &Vec[UInt8], hdr_end: Int, max_body: Int) -> ChunkedBody {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var res: ChunkedBody = ChunkedBody{ body: out; ok: false; error: "" };
  var p: Int = hdr_end + 4;
  var guard: Int = 0;
  while guard < 1000000 {
    guard = guard + 1;
    let le = find_crlf(raw, p, raw.len());
    if le < 0 {
      res.error = "incomplete chunked body";
      return res;
    }
    let sz = parse_hex_uint(chunk_size_text(bytes_to_str(raw, p, le)));
    if sz < 0 {
      res.error = "malformed chunked body";
      return res;
    }
    if sz == 0 {
      var q: Int = le + 2;
      var tg: Int = 0;
      while tg < 1000 {
        tg = tg + 1;
        let te2 = find_crlf(raw, q, raw.len());
        if te2 < 0 {
          res.error = "incomplete chunked body";
          return res;
        }
        if te2 == q {
          res.body = out;
          res.ok = true;
          return res;
        }
        q = te2 + 2;
      }
      res.error = "malformed chunked body";
      return res;
    }
    if out.len() + sz > max_body {
      res.error = "chunked body too large";
      return res;
    }
    let ds: Int = le + 2;
    let de: Int = ds + sz;
    if de + 2 > raw.len() {
      res.error = "incomplete chunked body";
      return res;
    }
    var i: Int = ds;
    while i < de {
      out.push(raw[i]);
      i = i + 1;
    }
    if raw[de] != 13u8 || raw[de + 1] != 10u8 {
      res.error = "malformed chunked body";
      return res;
    }
    p = de + 2;
  }
  res.error = "malformed chunked body";
  return res;
}

/// with_header_line inserts `line` (without CRLF) immediately after the
/// status line of a built response. Used by the app to add Date at the
/// assembly point. Complexity: O(n). Pure.
pub fn with_header_line(resp: &Vec[UInt8], line: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].with_capacity((resp.len() + line.len() + 4) as UInt);
  let first = find_crlf(resp, 0, resp.len());
  if first < 0 { return out; }
  var i: Int = 0;
  while i < first + 2 {
    out.push(resp[i]);
    i = i + 1;
  }
  append_str(&mut out, line);
  append_str(&mut out, "\r\n");
  var k: Int = first + 2;
  while k < resp.len() {
    out.push(resp[k]);
    k = k + 1;
  }
  return out;
}

/// expects_continue reports whether the request carries
/// `Expect: 100-continue` (case-insensitive; absent or another value is
/// false). Complexity: O(header). Pure.
pub fn expects_continue(req: &PulseRequest) -> Bool {
  let v = header_get(req, "expect");
  if v.len() == 0 { return false; }
  return string.str_contains(string.str_lower(v), "100-continue");
}

/// status_text returns the HTTP/1.1 reason phrase. Complexity: O(1).
pub fn status_text(code: Int) -> Str {
  if code == 200 { return "OK"; }
  if code == 201 { return "Created"; }
  if code == 204 { return "No Content"; }
  if code == 206 { return "Partial Content"; }
  if code == 301 { return "Moved Permanently"; }
  if code == 302 { return "Found"; }
  if code == 304 { return "Not Modified"; }
  if code == 400 { return "Bad Request"; }
  if code == 401 { return "Unauthorized"; }
  if code == 403 { return "Forbidden"; }
  if code == 404 { return "Not Found"; }
  if code == 405 { return "Method Not Allowed"; }
  if code == 408 { return "Request Timeout"; }
  if code == 411 { return "Length Required"; }
  if code == 413 { return "Payload Too Large"; }
  if code == 415 { return "Unsupported Media Type"; }
  if code == 416 { return "Range Not Satisfiable"; }
  if code == 429 { return "Too Many Requests"; }
  if code == 500 { return "Internal Server Error"; }
  if code == 501 { return "Not Implemented"; }
  if code == 502 { return "Bad Gateway"; }
  if code == 503 { return "Service Unavailable"; }
  if code == 504 { return "Gateway Timeout"; }
  return "Unknown";
}

/// security_head_lines returns the reviewed security-header block
/// (helmet-derived policy set; fixed values). CSP is deliberately NOT part
/// of the fixed block -- it is configurable (PULSE_CSP) and injected at
/// the server assembly point, because site mode serves arbitrary pre-built
/// trees whose inline scripts a default policy would break.
/// Complexity: O(1). Pure.
pub fn security_head_lines() -> Str {
  // One literal, not a concat chain: each `+` allocates a fresh Str and the
  // compiler retains it, so the old form cost ~2.5 KB per response.
  return "X-Content-Type-Options: nosniff\r\nX-Frame-Options: DENY\r\nReferrer-Policy: no-referrer\r\nCross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Resource-Policy: same-origin\r\nOrigin-Agent-Cluster: ?1\r\nStrict-Transport-Security: max-age=15552000; includeSubDomains\r\nX-DNS-Prefetch-Control: off\r\nX-Permitted-Cross-Domain-Policies: none\r\nX-XSS-Protection: 0\r\n";
}

/// append_str appends a Str's bytes to a response buffer without an
/// intermediate Vec. Complexity: O(n). Pure.
fn append_str(out: &mut Vec[UInt8], s: Str) {
  var i: Int = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
}

/// build_response_full builds a response with a custom content type and
/// extra headers (Set-Cookie, Allow, ...). `keep` controls the Connection
/// header: false emits `Connection: close`; true emits nothing (the
/// HTTP/1.1 keep-alive default; a 1.0 peer never sees keep-alive).
/// The head is appended straight into one pre-sized buffer: the old
/// concat chain allocated a fresh Str per line (and retained it on the
/// current compiler), which dominated the per-response growth.
/// Complexity: O(n). Pure.
pub fn build_response_full(status: Int, content_type: Str, extra_headers: &Vec[(Str, Str)], body: Str, keep: Bool) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].with_capacity((body.len() + 1024) as UInt);
  append_str(&mut out, "HTTP/1.1 ");
  append_str(&mut out, status.to_str());
  append_str(&mut out, " ");
  append_str(&mut out, status_text(status));
  append_str(&mut out, "\r\nContent-Type: ");
  append_str(&mut out, content_type);
  append_str(&mut out, "\r\n");
  var i: Int = 0;
  while i < extra_headers.len() {
    let h = extra_headers[i];
    let hn: Str = h.0;
    let hv: Str = h.1;
    append_str(&mut out, hn);
    append_str(&mut out, ": ");
    append_str(&mut out, hv);
    append_str(&mut out, "\r\n");
    i = i + 1;
  }
  append_str(&mut out, security_head_lines());
  append_str(&mut out, "Content-Length: ");
  append_str(&mut out, body.len().to_str());
  append_str(&mut out, "\r\n");
  if !keep {
    append_str(&mut out, "Connection: close\r\n");
  }
  append_str(&mut out, server_header_line());
  append_str(&mut out, "\r\n\r\n");
  append_str(&mut out, body);
  return out;
}

/// build_response_bytes builds a response with a raw byte body (icons,
/// binary assets). `keep` as in build_response_full. Complexity: O(n).
/// Pure.
pub fn build_response_bytes(status: Int, content_type: Str, extra_headers: &Vec[(Str, Str)], body: &Vec[UInt8], keep: Bool) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].with_capacity((body.len() + 1024) as UInt);
  append_str(&mut out, "HTTP/1.1 ");
  append_str(&mut out, status.to_str());
  append_str(&mut out, " ");
  append_str(&mut out, status_text(status));
  append_str(&mut out, "\r\nContent-Type: ");
  append_str(&mut out, content_type);
  append_str(&mut out, "\r\n");
  var i: Int = 0;
  while i < extra_headers.len() {
    let h = extra_headers[i];
    let hn: Str = h.0;
    let hv: Str = h.1;
    append_str(&mut out, hn);
    append_str(&mut out, ": ");
    append_str(&mut out, hv);
    append_str(&mut out, "\r\n");
    i = i + 1;
  }
  append_str(&mut out, security_head_lines());
  append_str(&mut out, "Content-Length: ");
  append_str(&mut out, body.len().to_str());
  append_str(&mut out, "\r\n");
  if !keep {
    append_str(&mut out, "Connection: close\r\n");
  }
  append_str(&mut out, server_header_line());
  append_str(&mut out, "\r\n\r\n");
  var j: Int = 0;
  while j < body.len() {
    out.push(body[j]);
    j = j + 1;
  }
  return out;
}

/// build_response builds a JSON response (close unless keep).
/// Complexity: O(n). Pure.
pub fn build_response(status: Int, body: Str, keep: Bool) -> Vec[UInt8] {
  var none: Vec[(Str, Str)] = Vec[(Str, Str)].new();
  return build_response_full(status, "application/json; charset=utf-8", &none, body, keep);
}

/// bearer_token extracts the token from an `Authorization: Bearer x`
/// header ("" when absent or malformed). The scheme match is
/// case-insensitive per RFC 9110. Complexity: O(n). Pure.
pub fn bearer_token(req: &PulseRequest) -> Str {
  let h = header_get(req, "authorization");
  if h.len() < 8 { return ""; }
  let scheme = string.str_slice(h, 0, 7);
  if string.str_lower(scheme) != "bearer " { return ""; }
  return string.str_slice(h, 7, h.len());
}

/// idem_key_valid guards the Idempotency-Key header: 1-200 bytes, no
/// control characters. Complexity: O(key). Pure.
pub fn idem_key_valid(s: Str) -> Bool {
  if s.len() < 1 || s.len() > 200 { return false; }
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 32u8 || b == 127u8 { return false; }
    i = i + 1;
  }
  return true;
}
