// XIOM -- xiom.vault.client: request / response / body model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of a secret-vault HTTP API client (Hashicorp-Vault-shaped):
// it builds and inspects the request and response STRUCTURES -- method codes,
// API paths, query strings, headers, JSON-ish bodies and response envelopes
// -- and deliberately performs no I/O, no cryptography and no networking.
//
// Documented scope limits:
//   * Paths, query strings and header values are validated but never
//     percent-encoded: callers pass wire-ready text (a space or control byte
//     is rejected, not escaped).
//   * The body builder renders a flat JSON object; string values are escaped,
//     raw values must be JSON scalars (number / true / false / null).
//   * Header names use the RFC 7230 token alphabet; values reject control
//     bytes except HTAB. Header operations are case-insensitive.
//
// v0.62.2 notes: free functions only; no methods, no lambdas, no match, no
// floats, no Vec of structs, no Vec[fn] dispatch; Ok(...)/Err(...) only in the
// `_ok_*`/`_err_*` leaf helpers below; every byte read widened with
// `(x as Int) & 0xFF`; Str equality through core.vault_str_eq (never `==`);
// `&mut Vec` parameters take an explicit `&mut` at every call site; local
// Vec[Str] pushes only (no module-level vectors).

module xiom.vault.client

use xiom.vault.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Body member kind: JSON string value (0), escaped on render.
pub const VAULT_BODY_STR: Int = 0;

/// Body member kind: raw JSON scalar (1), emitted verbatim.
pub const VAULT_BODY_RAW: Int = 1;

// --------------------------------------------------
//  Public data model (flat; no Vec of structs)
// --------------------------------------------------

/// A vault API request under construction. Parallel header vectors are always
/// the same length: header i is (header_names[i], header_values[i]).
pub type VaultRequest = {
  // Method code, one of the core.VAULT_METHOD_* constants.
  method: Int;
  // Normalized API path with a leading '/', no repeated or trailing '/'.
  path: Str;
  // Canonical query string without the leading '?' ("" when absent).
  query: Str;
  header_names: Vec[Str];
  header_values: Vec[Str];
  // Rendered JSON body ("" when absent).
  body: Str;
  // True once a body has been set.
  has_body: Bool;
}

/// A flat JSON object body under construction. Parallel vectors are always
/// the same length: member i is (names[i], kinds[i], values[i]).
pub type VaultBody = {
  names: Vec[Str];
  kinds: Vec[Int];
  values: Vec[Str];
}

/// A parsed API response envelope. The body is kept verbatim for the JSON
/// scanner in `xiom.vault.json`.
pub type VaultResponse = {
  status: Int;
  body: Str;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only, see header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_req(v: VaultRequest) -> Result[VaultRequest, Str] {
  return Ok(v);
}

fn _err_req(m: Str) -> Result[VaultRequest, Str] {
  return Err(m);
}

fn _ok_resp(v: VaultResponse) -> Result[VaultResponse, Str] {
  return Ok(v);
}

fn _err_resp(m: Str) -> Result[VaultResponse, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Method table
// --------------------------------------------------

/// Method code of an HTTP/Vault method name (case-insensitive); 0 when the
/// name is not one of GET, POST, PUT, PATCH, DELETE, LIST, HEAD, OPTIONS.
/// Params: name - the method name. Returns: the code or 0.
/// Error case: none. Complexity: O(name.len()).
pub fn vault_method_code(name: Str) -> Int {
  if core.vault_str_eq_ci(name, "GET") {
    return core.VAULT_METHOD_GET;
  }
  if core.vault_str_eq_ci(name, "POST") {
    return core.VAULT_METHOD_POST;
  }
  if core.vault_str_eq_ci(name, "PUT") {
    return core.VAULT_METHOD_PUT;
  }
  if core.vault_str_eq_ci(name, "PATCH") {
    return core.VAULT_METHOD_PATCH;
  }
  if core.vault_str_eq_ci(name, "DELETE") {
    return core.VAULT_METHOD_DELETE;
  }
  if core.vault_str_eq_ci(name, "LIST") {
    return core.VAULT_METHOD_LIST;
  }
  if core.vault_str_eq_ci(name, "HEAD") {
    return core.VAULT_METHOD_HEAD;
  }
  if core.vault_str_eq_ci(name, "OPTIONS") {
    return core.VAULT_METHOD_OPTIONS;
  }
  return core.VAULT_METHOD_UNKNOWN;
}

/// Canonical uppercase name of a method code; "" for 0 or out-of-range codes.
/// Params: code - a method code. Returns: the canonical name.
/// Error case: none. Complexity: O(1).
pub fn vault_method_name(code: Int) -> Str {
  if code == core.VAULT_METHOD_GET {
    return "GET";
  }
  if code == core.VAULT_METHOD_POST {
    return "POST";
  }
  if code == core.VAULT_METHOD_PUT {
    return "PUT";
  }
  if code == core.VAULT_METHOD_PATCH {
    return "PATCH";
  }
  if code == core.VAULT_METHOD_DELETE {
    return "DELETE";
  }
  if code == core.VAULT_METHOD_LIST {
    return "LIST";
  }
  if code == core.VAULT_METHOD_HEAD {
    return "HEAD";
  }
  if code == core.VAULT_METHOD_OPTIONS {
    return "OPTIONS";
  }
  return "";
}

// --------------------------------------------------
//  Path normalization
// --------------------------------------------------

/// Normalize an API path: reject an empty path, control bytes and spaces,
/// prepend a leading '/', collapse runs of '/' and strip a trailing '/'
/// (except for the root path "/"). Percent-encoding is the caller's concern.
/// Params: path - the raw API path. Returns: Ok(normalized path).
/// Error case: Err("vault: path is empty"), Err("vault: path is too long"),
/// Err("vault: path has a control or space byte at offset N").
/// Complexity: O(path.len()).
pub fn vault_path_normalize(path: Str) -> Result[Str, Str] {
  let n = path.len();
  if n == 0 {
    return _err_str(core.vault_err("path is empty"));
  }
  if n > core.VAULT_MAX_PATH {
    return _err_str(core.vault_err("path is too long"));
  }
  var i = 0;
  while i < n {
    let c = core.vault_byte(path, i);
    if core.vault_is_ctl(c) || c == 32 {
      return _err_str(core.vault_err_at("path has a control or space byte", i));
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  out.push(47 as UInt8);
  var last_slash = true;
  i = 0;
  while i < n {
    let c = core.vault_byte(path, i);
    if c == 47 {
      if !last_slash {
        out.push(47 as UInt8);
        last_slash = true;
      }
    } else {
      out.push(string.byte_at(path, i));
      last_slash = false;
    }
    i = i + 1;
  }
  if out.len() > 1 {
    let last = (out[out.len() - 1] as Int) & 0xFF;
    if last == 47 {
      var trimmed = Vec[UInt8].new();
      var k = 0;
      while k < out.len() - 1 {
        trimmed.push(out[k]);
        k = k + 1;
      }
      out = trimmed;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Request construction and mutation
// --------------------------------------------------

/// Start a request with a method code and an API path (normalized).
/// Params: method - one of the VAULT_METHOD_* codes (0 is rejected);
/// path - the raw API path.
/// Returns: Ok(request) with no query, headers or body.
/// Error case: Err("vault: unknown method code"), Err("vault: method code out
/// of range at offset N") and the vault_path_normalize catalog.
/// Complexity: O(path.len()).
pub fn vault_request_new(method: Int, path: Str) -> Result[VaultRequest, Str] {
  if method == core.VAULT_METHOD_UNKNOWN {
    return _err_req(core.vault_err("unknown method code"));
  }
  if method < core.VAULT_METHOD_GET || method > core.VAULT_METHOD_OPTIONS {
    return _err_req(core.vault_err_at("method code out of range", method));
  }
  let pr = vault_path_normalize(path);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let np: Str = pr.value;
  return _ok_req(VaultRequest{
    method: method;
    path: np;
    query: "";
    header_names: Vec[Str].new();
    header_values: Vec[Str].new();
    body: "";
    has_body: false
  });
}

/// Set (or clear) the query string. A leading '?' is accepted and stripped;
/// the stored form never has one. Empty input clears the query. Every
/// '&'-separated segment must be non-empty; '?', '#', control bytes and
/// spaces are rejected.
/// Params: req - the request; query - the raw query text.
/// Returns: Ok(0).
/// Error case: Err("vault: query is too long"), Err("vault: query contains
/// '?' or '#' at offset N"), Err("vault: query has a control or space byte
/// at offset N"), Err("vault: query has an empty parameter at offset N").
/// Complexity: O(query.len()).
pub fn vault_request_set_query(req: &mut VaultRequest, query: Str) -> Result[Int, Str] {
  var q = query;
  if q.len() > 0 {
    if core.vault_byte(q, 0) == 63 {
      q = string.str_slice(q, 1, q.len());
    }
  }
  let n = q.len();
  if n == 0 {
    req.query = "";
    return _ok_int(0);
  }
  if n > 4096 {
    return _err_int(core.vault_err("query is too long"));
  }
  var i = 0;
  var seg_start = 0;
  while i < n {
    let c = core.vault_byte(q, i);
    if c == 63 || c == 35 {
      return _err_int(core.vault_err_at("query contains '?' or '#'", i));
    }
    if core.vault_is_ctl(c) || c == 32 {
      return _err_int(core.vault_err_at("query has a control or space byte", i));
    }
    if c == 38 {
      if i == seg_start {
        return _err_int(core.vault_err_at("query has an empty parameter", i));
      }
      seg_start = i + 1;
    }
    i = i + 1;
  }
  if seg_start == n {
    return _err_int(core.vault_err_at("query has an empty parameter", n));
  }
  req.query = q;
  return _ok_int(0);
}

// Index of the first header named `name` (case-insensitive), or -1.
fn _find_header(req: &VaultRequest, name: Str) -> Int {
  var i = 0;
  while i < req.header_names.len() {
    let cur: Str = req.header_names[i];
    if core.vault_str_eq_ci(cur, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Set or replace a header (case-insensitive name match). The name must be an
/// RFC 7230 token (up to 128 bytes); the value may be empty and must reject
/// control bytes other than HTAB (up to 4096 bytes).
/// Params: req - the request; name - the header name; value - the value.
/// Returns: Ok(0).
/// Error case: Err("vault: header name is empty"), Err("vault: header name
/// is too long"), Err("vault: header name has an invalid character"),
/// Err("vault: header value is too long"), Err("vault: header value has a
/// control byte at offset N"), Err("vault: too many headers").
/// Complexity: O(name.len() + value.len() + header count).
pub fn vault_request_set_header(req: &mut VaultRequest, name: Str, value: Str) -> Result[Int, Str] {
  if name.len() == 0 {
    return _err_int(core.vault_err("header name is empty"));
  }
  if name.len() > 128 {
    return _err_int(core.vault_err("header name is too long"));
  }
  if !core.vault_is_token(name) {
    return _err_int(core.vault_err("header name has an invalid character"));
  }
  if value.len() > 4096 {
    return _err_int(core.vault_err("header value is too long"));
  }
  var i = 0;
  while i < value.len() {
    let c = core.vault_byte(value, i);
    if c == 9 {
      i = i + 1;
    } elif core.vault_is_ctl(c) {
      return _err_int(core.vault_err_at("header value has a control byte", i));
    } else {
      i = i + 1;
    }
  }
  let idx = _find_header(req, name);
  if idx >= 0 {
    req.header_values[idx] = value;
    return _ok_int(0);
  }
  if req.header_names.len() >= core.VAULT_MAX_HEADERS {
    return _err_int(core.vault_err("too many headers"));
  }
  req.header_names.push(name);
  req.header_values.push(value);
  return _ok_int(0);
}

/// Remove every header named `name` (case-insensitive).
/// Params: req - the request; name - the header name.
/// Returns: the number of removed headers.
/// Error case: none. Complexity: O(header count).
pub fn vault_request_remove_header(req: &mut VaultRequest, name: Str) -> Int {
  var nn = Vec[Str].new();
  var vv = Vec[Str].new();
  var removed = 0;
  var i = 0;
  while i < req.header_names.len() {
    let cn: Str = req.header_names[i];
    if core.vault_str_eq_ci(cn, name) {
      removed = removed + 1;
    } else {
      let cv: Str = req.header_values[i];
      nn.push(cn);
      vv.push(cv);
    }
    i = i + 1;
  }
  req.header_names = nn;
  req.header_values = vv;
  return removed;
}

/// First value of the header named `name` (case-insensitive).
/// Params: req - the request; name - the header name.
/// Returns: Ok(value) for the first match.
/// Error case: Err("vault: header not found: <name>").
/// Complexity: O(header count).
pub fn vault_request_header_get(req: &VaultRequest, name: Str) -> Result[Str, Str] {
  let idx = _find_header(req, name);
  if idx < 0 {
    return _err_str("vault: header not found: " + name);
  }
  let v: Str = req.header_values[idx];
  return _ok_str(v);
}

/// True when a header named `name` is present (case-insensitive).
/// Params: req - the request; name - the header name.
/// Returns: the predicate. Error case: none. Complexity: O(header count).
pub fn vault_request_has_header(req: &VaultRequest, name: Str) -> Bool {
  if _find_header(req, name) >= 0 {
    return true;
  }
  return false;
}

/// Attach the Vault token header (core.VAULT_HEADER_TOKEN). The token must be
/// non-empty and contain no control bytes.
/// Params: req - the request; token - the client token.
/// Returns: Ok(0). Error case: Err("vault: token is empty") or
/// Err("vault: token has a control byte at offset N").
/// Complexity: O(token.len()).
pub fn vault_request_set_token(req: &mut VaultRequest, token: Str) -> Result[Int, Str] {
  if token.len() == 0 {
    return _err_int(core.vault_err("token is empty"));
  }
  var i = 0;
  while i < token.len() {
    if core.vault_is_ctl(core.vault_byte(token, i)) {
      return _err_int(core.vault_err_at("token has a control byte", i));
    }
    i = i + 1;
  }
  return vault_request_set_header(req, core.VAULT_HEADER_TOKEN, token);
}

/// Attach a rendered body (see vault_body_render) and mark the request as
/// having one.
/// Params: req - the request; body - the body builder.
/// Returns: Ok(0). Error case: none. Complexity: O(body size).
pub fn vault_request_set_body(req: &mut VaultRequest, body: &VaultBody) -> Result[Int, Str] {
  let rendered = vault_body_render(body);
  req.body = rendered;
  req.has_body = true;
  return _ok_int(0);
}

/// Attach a pre-rendered JSON body text and mark the request as having one.
/// The text must be non-empty, may contain newlines and HTAB, and must not
/// contain other control bytes (a JSON document escapes them).
/// Params: req - the request; body - the rendered JSON text.
/// Returns: Ok(0).
/// Error case: Err("vault: body text is empty"), Err("vault: body text has a
/// control byte at offset N").
/// Complexity: O(body.len()).
pub fn vault_request_set_body_text(req: &mut VaultRequest, body: Str) -> Result[Int, Str] {
  if body.len() == 0 {
    return _err_int(core.vault_err("body text is empty"));
  }
  var i = 0;
  while i < body.len() {
    let c = core.vault_byte(body, i);
    if c == 10 || c == 13 || c == 9 {
      i = i + 1;
    } elif core.vault_is_ctl(c) {
      return _err_int(core.vault_err_at("body text has a control byte", i));
    } else {
      i = i + 1;
    }
  }
  req.body = body;
  req.has_body = true;
  return _ok_int(0);
}

/// Clear the body.
/// Params: req - the request. Returns: the previous body length.
/// Error case: none. Complexity: O(1).
pub fn vault_request_clear_body(req: &mut VaultRequest) -> Int {
  let old = req.body.len();
  req.body = "";
  req.has_body = false;
  return old;
}

/// Request target: the path plus "?<query>" when a query is set.
/// Params: req - the request. Returns: the target text.
/// Error case: none. Complexity: O(path.len() + query.len()).
pub fn vault_request_target(req: &VaultRequest) -> Str {
  if req.query.len() == 0 {
    return req.path;
  }
  return (req.path + "?") + req.query;
}

/// Method code of the request. Error case: none. Complexity: O(1).
pub fn vault_request_method(req: &VaultRequest) -> Int {
  return req.method;
}

/// Canonical method name of the request. Error case: none. Complexity: O(1).
pub fn vault_request_method_name(req: &VaultRequest) -> Str {
  return vault_method_name(req.method);
}

/// Normalized path of the request. Error case: none. Complexity: O(1).
pub fn vault_request_path(req: &VaultRequest) -> Str {
  let v: Str = req.path;
  return v;
}

/// Query string of the request ("" when absent, no leading '?').
/// Error case: none. Complexity: O(1).
pub fn vault_request_query(req: &VaultRequest) -> Str {
  let v: Str = req.query;
  return v;
}

/// Rendered body of the request ("" when absent).
/// Error case: none. Complexity: O(1).
pub fn vault_request_body(req: &VaultRequest) -> Str {
  let v: Str = req.body;
  return v;
}

/// True when a body has been set. Error case: none. Complexity: O(1).
pub fn vault_request_has_body(req: &VaultRequest) -> Bool {
  return req.has_body;
}

/// Number of headers. Error case: none. Complexity: O(1).
pub fn vault_request_header_count(req: &VaultRequest) -> Int {
  return req.header_names.len();
}

/// Name of header i (wire text). Params: req - the request; i - a valid
/// index. Returns: the name. Error case: none for a valid index.
/// Complexity: O(1).
pub fn vault_request_header_name(req: &VaultRequest, i: Int) -> Str {
  let v: Str = req.header_names[i];
  return v;
}

/// Value of header i. Params: req - the request; i - a valid index.
/// Returns: the value. Error case: none for a valid index. Complexity: O(1).
pub fn vault_request_header_value(req: &VaultRequest, i: Int) -> Str {
  let v: Str = req.header_values[i];
  return v;
}

// --------------------------------------------------
//  JSON-ish body builder
// --------------------------------------------------

// True when `name` is a usable flat JSON member name: 1..128 printable bytes
// without '"' or '\'.
fn _body_name_ok(name: Str) -> Bool {
  let n = name.len();
  if n == 0 || n > 128 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.vault_byte(name, i);
    if core.vault_is_ctl(c) || c == 32 || c == 34 || c == 92 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `raw` is a bare JSON scalar: a number per the JSON grammar, or
// exactly true / false / null.
fn _raw_scalar_ok(raw: Str) -> Bool {
  let n = raw.len();
  if n == 0 {
    return false;
  }
  if core.vault_str_eq(raw, "true") || core.vault_str_eq(raw, "false") || core.vault_str_eq(raw, "null") {
    return true;
  }
  var i = 0;
  if core.vault_byte(raw, 0) == 45 {
    i = 1;
  }
  if i >= n {
    return false;
  }
  let d0 = core.vault_byte(raw, i);
  if d0 == 48 {
    i = i + 1;
  } elif d0 >= 49 && d0 <= 57 {
    while i < n && core.vault_byte(raw, i) >= 48 && core.vault_byte(raw, i) <= 57 {
      i = i + 1;
    }
  } else {
    return false;
  }
  if i < n && core.vault_byte(raw, i) == 46 {
    i = i + 1;
    var frac = 0;
    while i < n && core.vault_byte(raw, i) >= 48 && core.vault_byte(raw, i) <= 57 {
      i = i + 1;
      frac = frac + 1;
    }
    if frac == 0 {
      return false;
    }
  }
  if i < n {
    let ex = core.vault_byte(raw, i);
    if ex == 101 || ex == 69 {
      i = i + 1;
      if i < n && (core.vault_byte(raw, i) == 43 || core.vault_byte(raw, i) == 45) {
        i = i + 1;
      }
      var digits = 0;
      while i < n && core.vault_byte(raw, i) >= 48 && core.vault_byte(raw, i) <= 57 {
        i = i + 1;
        digits = digits + 1;
      }
      if digits == 0 {
        return false;
      }
    }
  }
  if i != n {
    return false;
  }
  return true;
}

/// A new empty body.
/// Params: none. Returns: an empty VaultBody.
/// Error case: none. Complexity: O(1).
pub fn vault_body_new() -> VaultBody {
  return VaultBody{
    names: Vec[Str].new();
    kinds: Vec[Int].new();
    values: Vec[Str].new()
  };
}

/// Append a string member (escaped when rendered).
/// Params: b - the body; name - the member name; value - the string value.
/// Returns: Ok(0).
/// Error case: Err("vault: body member name is empty or invalid") or
/// Err("vault: body has too many members").
/// Complexity: O(name.len()).
pub fn vault_body_add_str(b: &mut VaultBody, name: Str, value: Str) -> Result[Int, Str] {
  if !_body_name_ok(name) {
    return _err_int(core.vault_err("body member name is empty or invalid"));
  }
  if b.names.len() >= core.VAULT_MAX_BODY_MEMBERS {
    return _err_int(core.vault_err("body has too many members"));
  }
  b.names.push(name);
  b.kinds.push(VAULT_BODY_STR);
  b.values.push(value);
  return _ok_int(0);
}

/// Append a raw JSON scalar member (number / true / false / null), emitted
/// verbatim.
/// Params: b - the body; name - the member name; raw - the scalar text.
/// Returns: Ok(0).
/// Error case: Err("vault: body member name is empty or invalid"),
/// Err("vault: body raw value is not a JSON scalar"),
/// Err("vault: body has too many members").
/// Complexity: O(name.len() + raw.len()).
pub fn vault_body_add_raw(b: &mut VaultBody, name: Str, raw: Str) -> Result[Int, Str] {
  if !_body_name_ok(name) {
    return _err_int(core.vault_err("body member name is empty or invalid"));
  }
  if !_raw_scalar_ok(raw) {
    return _err_int(core.vault_err("body raw value is not a JSON scalar"));
  }
  if b.names.len() >= core.VAULT_MAX_BODY_MEMBERS {
    return _err_int(core.vault_err("body has too many members"));
  }
  b.names.push(name);
  b.kinds.push(VAULT_BODY_RAW);
  b.values.push(raw);
  return _ok_int(0);
}

/// Append an integer member (decimal rendering, via core.vault_int_str).
/// Params: b - the body; name - the member name; v - the integer.
/// Returns: Ok(0). Error case: the vault_body_add_raw catalog.
/// Complexity: O(name.len() + digits).
pub fn vault_body_add_int(b: &mut VaultBody, name: Str, v: Int) -> Result[Int, Str] {
  return vault_body_add_raw(b, name, core.vault_int_str(v));
}

/// Append a boolean member.
/// Params: b - the body; name - the member name; v - the value.
/// Returns: Ok(0). Error case: the vault_body_add_raw catalog.
/// Complexity: O(name.len()).
pub fn vault_body_add_bool(b: &mut VaultBody, name: Str, v: Bool) -> Result[Int, Str] {
  if v {
    return vault_body_add_raw(b, name, "true");
  }
  return vault_body_add_raw(b, name, "false");
}

/// Number of members.
/// Params: b - the body. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn vault_body_count(b: &VaultBody) -> Int {
  return b.names.len();
}

/// Remove every member.
/// Params: b - the body. Returns: the previous member count.
/// Error case: none. Complexity: O(1).
pub fn vault_body_clear(b: &mut VaultBody) -> Int {
  let old = b.names.len();
  b.names = Vec[Str].new();
  b.kinds = Vec[Int].new();
  b.values = Vec[Str].new();
  return old;
}

// Append `"s"` to `out`, escaping '"', '\' and control bytes as \u00xx.
fn _json_quote_into(out: &mut Vec[UInt8], s: Str) {
  let hexa = "0123456789abcdef";
  out.push(34 as UInt8);
  var i = 0;
  while i < s.len() {
    let b = core.vault_byte(s, i);
    if b == 34 {
      out.push(92 as UInt8);
      out.push(34 as UInt8);
    } elif b == 92 {
      out.push(92 as UInt8);
      out.push(92 as UInt8);
    } elif core.vault_is_ctl(b) {
      out.push(92 as UInt8);
      out.push(117 as UInt8);
      out.push(48 as UInt8);
      out.push(48 as UInt8);
      out.push(string.byte_at(hexa, b / 16));
      out.push(string.byte_at(hexa, b % 16));
    } else {
      out.push(string.byte_at(s, i));
    }
    i = i + 1;
  }
  out.push(34 as UInt8);
}

/// Render the body as a flat JSON object: {"name":value,...} with members in
/// insertion order, string values escaped and raw values verbatim. An empty
/// body renders "{}".
/// Params: b - the body. Returns: the rendered text.
/// Error case: none. Complexity: O(total member text).
pub fn vault_body_render(b: &VaultBody) -> Str {
  var out = Vec[UInt8].new();
  out.push(123 as UInt8);
  var i = 0;
  while i < b.names.len() {
    if i > 0 {
      out.push(44 as UInt8);
    }
    let nm: Str = b.names[i];
    let kd: Int = b.kinds[i];
    let vl: Str = b.values[i];
    _json_quote_into(&mut out, nm);
    out.push(58 as UInt8);
    if kd == VAULT_BODY_STR {
      _json_quote_into(&mut out, vl);
    } else {
      var k = 0;
      while k < vl.len() {
        out.push(string.byte_at(vl, k));
        k = k + 1;
      }
    }
    i = i + 1;
  }
  out.push(125 as UInt8);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Response envelope
// --------------------------------------------------

/// Build a response envelope. The status must be a three-digit HTTP status
/// (100..599); the body is kept verbatim.
/// Params: status - the HTTP status; body - the response body text.
/// Returns: Ok(response).
/// Error case: Err("vault: response status out of range: N").
/// Complexity: O(body.len()).
pub fn vault_response_new(status: Int, body: Str) -> Result[VaultResponse, Str] {
  if status < 100 || status > 599 {
    return _err_resp(core.vault_err("response status out of range: " + core.vault_int_str(status)));
  }
  return _ok_resp(VaultResponse{ status: status; body: body });
}

/// HTTP status of a response. Error case: none. Complexity: O(1).
pub fn vault_response_status(r: &VaultResponse) -> Int {
  return r.status;
}

/// Verbatim body of a response. Error case: none. Complexity: O(1).
pub fn vault_response_body(r: &VaultResponse) -> Str {
  let v: Str = r.body;
  return v;
}

/// True when the response status is 2xx.
/// Error case: none. Complexity: O(1).
pub fn vault_response_is_success(r: &VaultResponse) -> Bool {
  if r.status >= 200 && r.status <= 299 {
    return true;
  }
  return false;
}
