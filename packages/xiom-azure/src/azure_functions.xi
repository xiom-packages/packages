// XIOM -- xiom.azure.functions: pure-XIOM Azure Functions model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the Azure Functions deploy/invoke surface the caller drives over its
// own transport:
//
//   * Function app shape: globally unique name rules, pinned runtime subset
//     (dotnet / node / python / java / powershell / custom), location check
//     and default hostname.
//   * HTTP trigger routes: literal and whole-segment `{name}` placeholders
//     with the documented constraint subset (alpha, int, long, bool, guid,
//     float, datetime, string) and an optional `?` suffix; route validity,
//     parameter extraction and path matching (literals case-insensitive).
//   * Trigger shape: method CSV, route and auth level (anonymous / function /
//     admin); function-key shape; invoke URL assembly; HTTP status classes
//     and retryability.
//
// Documented subset: placeholders must span a whole path segment, optional
// placeholders may also match an empty segment, and route matching is
// case-insensitive by segment.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.functions

use xiom.azure.base;
use xiom.azure.compute;
use xiom.string;

// Runtimes.
pub const AZURE_RUNTIME_DOTNET: Int = 0;
pub const AZURE_RUNTIME_NODE: Int = 1;
pub const AZURE_RUNTIME_PYTHON: Int = 2;
pub const AZURE_RUNTIME_JAVA: Int = 3;
pub const AZURE_RUNTIME_POWERSHELL: Int = 4;
pub const AZURE_RUNTIME_CUSTOM: Int = 5;

// HTTP trigger auth levels.
pub const AZURE_AUTH_ANONYMOUS: Int = 0;
pub const AZURE_AUTH_FUNCTION: Int = 1;
pub const AZURE_AUTH_ADMIN: Int = 2;

// HTTP status classes (azure_function_status_class).
pub const AZURE_HTTP_UNKNOWN: Int = 0;
pub const AZURE_HTTP_INFORMATIONAL: Int = 1;
pub const AZURE_HTTP_SUCCESS: Int = 2;
pub const AZURE_HTTP_REDIRECT: Int = 3;
pub const AZURE_HTTP_CLIENT_ERROR: Int = 4;
pub const AZURE_HTTP_SERVER_ERROR: Int = 5;

/// One function app.
pub type AzureFunctionApp = {
  name: Str;
  location: Str;
  runtime: Int;
  runtime_version: Str;
}

/// One HTTP trigger definition.
pub type AzureHttpTrigger = {
  methods_csv: Str;
  route: Str;
  auth_level: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_app(v: AzureFunctionApp) -> Result[AzureFunctionApp, Str] {
  return Ok(v);
}

fn _err_app(m: Str) -> Result[AzureFunctionApp, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq_ci(a: Str, b: Str) -> Bool {
  return base.azure_streq_ignore_case(a, b);
}

fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _strip_lead_slash(s: Str) -> Str {
  let n = s.len();
  if n == 0 {
    return s;
  }
  let b0: Int = _byte_at(s, 0);
  if b0 == 47 {
    return base.azure_substr(s, 1, n);
  }
  return s;
}

fn _trim(s: Str) -> Str {
  let n = s.len();
  var a = 0;
  var done = false;
  while a < n && !done {
    let b: Int = _byte_at(s, a);
    if b == 32 || b == 9 {
      a = a + 1;
    } else {
      done = true;
    }
  }
  var z = n;
  done = false;
  while z > a && !done {
    let b: Int = _byte_at(s, z - 1);
    if b == 32 || b == 9 {
      z = z - 1;
    } else {
      done = true;
    }
  }
  return base.azure_substr(s, a, z);
}

// Split on '/', rejecting empty segments; false when one is found.
fn _split_nonempty(s: Str, out: &mut Vec[Str]) -> Bool {
  let n = s.len();
  if n == 0 {
    return true;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    var boundary = false;
    if i == n {
      boundary = true;
    } else {
      let b: Int = _byte_at(s, i);
      if b == 47 {
        boundary = true;
      }
    }
    if boundary {
      if i == start {
        return false;
      }
      out.push(base.azure_substr(s, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

// Split a comma-separated list (empty input has no tokens).
fn _split_csv(s: Str, out: &mut Vec[Str]) {
  let n = s.len();
  if n == 0 {
    return;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    var boundary = false;
    if i == n {
      boundary = true;
    } else {
      let b: Int = _byte_at(s, i);
      if b == 44 {
        boundary = true;
      }
    }
    if boundary {
      out.push(base.azure_substr(s, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
}

// Split on '/', keeping empty segments (an empty input has no segments).
fn _split_allow_empty(s: Str, out: &mut Vec[Str]) {
  let n = s.len();
  if n == 0 {
    return;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    var boundary = false;
    if i == n {
      boundary = true;
    } else {
      let b: Int = _byte_at(s, i);
      if b == 47 {
        boundary = true;
      }
    }
    if boundary {
      out.push(base.azure_substr(s, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Route placeholders
// --------------------------------------------------

// Placeholder body of a `{...}` segment, or "" when the segment is not a
// whole-segment placeholder.
fn _placeholder_body(seg: Str) -> Str {
  let n = seg.len();
  if n < 3 {
    return "";
  }
  let b0: Int = _byte_at(seg, 0);
  let bl: Int = _byte_at(seg, n - 1);
  if b0 != 123 || bl != 125 {
    return "";
  }
  return base.azure_substr(seg, 1, n - 1);
}

// Parameter name of a placeholder body (the part before ':', without '?').
fn _placeholder_name(body: Str) -> Str {
  let core = _placeholder_core(body);
  let n = core.len();
  var i = 0;
  while i < n {
    let b: Int = _byte_at(core, i);
    if b == 58 {
      return base.azure_substr(core, 0, i);
    }
    i = i + 1;
  }
  return core;
}

// Body without a trailing '?'.
fn _placeholder_core(body: Str) -> Str {
  let n = body.len();
  if n > 0 {
    let bl: Int = _byte_at(body, n - 1);
    if bl == 63 {
      return base.azure_substr(body, 0, n - 1);
    }
  }
  return body;
}

// True when the placeholder body ends with '?'.
fn _placeholder_optional(body: Str) -> Bool {
  let n = body.len();
  if n > 0 {
    let bl: Int = _byte_at(body, n - 1);
    if bl == 63 {
      return true;
    }
  }
  return false;
}

// Constraint of a placeholder body, or "" when absent.
fn _placeholder_constraint(body: Str) -> Str {
  let core = _placeholder_core(body);
  let n = core.len();
  var i = 0;
  while i < n {
    let b: Int = _byte_at(core, i);
    if b == 58 {
      return base.azure_substr(core, i + 1, n);
    }
    i = i + 1;
  }
  return "";
}

// Parameter names: 1..32 chars, first a letter or '_', then letters, digits,
// '_' or '-'.
fn _param_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > 32 {
    return false;
  }
  let b0: Int = _byte_at(s, 0);
  if !base.azure_is_alpha(b0) && b0 != 95 {
    return false;
  }
  var i = 1;
  while i < n {
    let b: Int = _byte_at(s, i);
    let ok = base.azure_is_alpha(b) || base.azure_is_digit(b) || b == 95 || b == 45;
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Constraint names in the pinned subset.
fn _constraint_valid(c: Str) -> Bool {
  if c.len() == 0 {
    return false;
  }
  if _streq_ci(c, "alpha") {
    return true;
  }
  if _streq_ci(c, "int") {
    return true;
  }
  if _streq_ci(c, "long") {
    return true;
  }
  if _streq_ci(c, "bool") {
    return true;
  }
  if _streq_ci(c, "guid") {
    return true;
  }
  if _streq_ci(c, "float") {
    return true;
  }
  if _streq_ci(c, "datetime") {
    return true;
  }
  if _streq_ci(c, "string") {
    return true;
  }
  return false;
}

fn _placeholder_valid(body: Str) -> Bool {
  if body.len() < 1 || body.len() > 64 {
    return false;
  }
  let core = _placeholder_core(body);
  if core.len() == 0 {
    return false;
  }
  let name = _placeholder_name(body);
  if !_param_name_valid(name) {
    return false;
  }
  let c = _placeholder_constraint(body);
  if c.len() == 0 {
    return true;
  }
  return _constraint_valid(c);
}

fn _route_segment_valid(seg: Str) -> Bool {
  let n = seg.len();
  if n == 0 {
    return false;
  }
  let body = _placeholder_body(seg);
  if body.len() > 0 {
    return _placeholder_valid(body);
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(seg, i);
    let ok = base.azure_is_alpha(b) || base.azure_is_digit(b) || b == 45 || b == 46 || b == 95 || b == 126;
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Route validity: "" (function root) or up to 32 non-empty segments of
/// literals and whole-segment placeholders, at most 16 placeholders and 512
/// bytes. A leading '/' is tolerated and ignored.
pub fn azure_route_valid(route: Str) -> Bool {
  let r = _strip_lead_slash(route);
  if r.len() == 0 {
    return true;
  }
  if r.len() > 512 {
    return false;
  }
  var segs = Vec[Str].new();
  let ok = _split_nonempty(r, &mut segs);
  if !ok {
    return false;
  }
  if segs.len() > 32 {
    return false;
  }
  var placeholders = 0;
  var i = 0;
  while i < segs.len() {
    let seg: Str = segs[i];
    if !_route_segment_valid(seg) {
      return false;
    }
    let body = _placeholder_body(seg);
    if body.len() > 0 {
      placeholders = placeholders + 1;
    }
    i = i + 1;
  }
  if placeholders > 16 {
    return false;
  }
  return true;
}

/// Comma-joined placeholder names in route order ("" when none).
/// Err("azure: invalid route") for a malformed route.
pub fn azure_route_parameter_names(route: Str) -> Result[Str, Str] {
  if !azure_route_valid(route) {
    return _err_str("azure: invalid route");
  }
  let r = _strip_lead_slash(route);
  var segs = Vec[Str].new();
  _split_nonempty(r, &mut segs);
  var out = "";
  var first = true;
  var i = 0;
  while i < segs.len() {
    let seg: Str = segs[i];
    let body = _placeholder_body(seg);
    if body.len() > 0 {
      let nm = _placeholder_name(body);
      if !first {
        out = out + ",";
      }
      out = out + nm;
      first = false;
    }
    i = i + 1;
  }
  return _ok_str(out);
}

// --------------------------------------------------
//  Route matching
// --------------------------------------------------

fn _all_digits(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if !base.azure_is_digit(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _signed_digits(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var start = 0;
  let b0: Int = _byte_at(s, 0);
  if b0 == 45 {
    start = 1;
  }
  if start == n {
    return false;
  }
  var i = start;
  while i < n {
    let b: Int = _byte_at(s, i);
    if !base.azure_is_digit(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _all_alpha(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if !base.azure_is_alpha(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _float_valid(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var dots = 0;
  var digits = 0;
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    if b == 46 {
      dots = dots + 1;
      if dots > 1 {
        return false;
      }
    } else if base.azure_is_digit(b) {
      digits = digits + 1;
    } else {
      return false;
    }
    i = i + 1;
  }
  return digits > 0;
}

fn _datetime_valid(s: Str) -> Bool {
  if s.len() < 10 {
    return false;
  }
  var i = 0;
  while i < 10 {
    let b: Int = _byte_at(s, i);
    let dash = i == 4 || i == 7;
    if dash {
      if b != 45 {
        return false;
      }
    } else if !base.azure_is_digit(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _constraint_matches(c: Str, seg: Str) -> Bool {
  if c.len() == 0 {
    return seg.len() > 0;
  }
  if _streq_ci(c, "alpha") {
    return _all_alpha(seg);
  }
  if _streq_ci(c, "int") {
    return _signed_digits(seg);
  }
  if _streq_ci(c, "long") {
    return _signed_digits(seg);
  }
  if _streq_ci(c, "bool") {
    return _streq_ci(seg, "true") || _streq_ci(seg, "false");
  }
  if _streq_ci(c, "guid") {
    return base.azure_guid_valid(seg);
  }
  if _streq_ci(c, "float") {
    return _float_valid(seg);
  }
  if _streq_ci(c, "datetime") {
    return _datetime_valid(seg);
  }
  if _streq_ci(c, "string") {
    return seg.len() > 0;
  }
  return false;
}

/// True when `path` matches `route`: same segment count, literals compared
/// case-insensitively, placeholders against their constraints, optional
/// placeholders also matching an empty segment. An invalid route or path
/// never matches; the function root "" matches "" only.
pub fn azure_route_match(route: Str, path: Str) -> Bool {
  if !azure_route_valid(route) {
    return false;
  }
  let r = _strip_lead_slash(route);
  let p = _strip_lead_slash(path);
  if r.len() == 0 {
    return p.len() == 0;
  }
  var rsegs = Vec[Str].new();
  _split_nonempty(r, &mut rsegs);
  var psegs = Vec[Str].new();
  _split_allow_empty(p, &mut psegs);
  var common = rsegs.len();
  if rsegs.len() != psegs.len() {
    if rsegs.len() != psegs.len() + 1 {
      return false;
    }
    let last: Str = rsegs[rsegs.len() - 1];
    let lb = _placeholder_body(last);
    if lb.len() == 0 || !_placeholder_optional(lb) {
      return false;
    }
    common = psegs.len();
  }
  var i = 0;
  while i < common {
    let rs: Str = rsegs[i];
    let ps: Str = psegs[i];
    let body = _placeholder_body(rs);
    if body.len() > 0 {
      let optional = _placeholder_optional(body);
      let c = _placeholder_constraint(body);
      if ps.len() == 0 {
        if !optional {
          return false;
        }
      } else {
        if !_constraint_matches(c, ps) {
          return false;
        }
      }
    } else {
      if !_streq_ci(rs, ps) {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  App model
// --------------------------------------------------

/// Function app name: 2..60 chars, lowercase letters, digits and hyphens,
/// starting and ending with a letter or digit.
pub fn azure_function_app_name_valid(s: Str) -> Bool {
  let n = s.len();
  if n < 2 || n > 60 {
    return false;
  }
  var i = 0;
  var last_dash = false;
  while i < n {
    let b: Int = _byte_at(s, i);
    let lower = b >= 97 && b <= 122;
    if lower || base.azure_is_digit(b) {
      last_dash = false;
    } else if b == 45 {
      if i == 0 {
        return false;
      }
      last_dash = true;
    } else {
      return false;
    }
    i = i + 1;
  }
  if last_dash {
    return false;
  }
  return true;
}

/// True for a pinned runtime constant.
pub fn azure_function_runtime_valid(runtime: Int) -> Bool {
  if runtime < AZURE_RUNTIME_DOTNET {
    return false;
  }
  if runtime > AZURE_RUNTIME_CUSTOM {
    return false;
  }
  return true;
}

/// Runtime name (unknown -> "unknown").
pub fn azure_function_runtime_name(runtime: Int) -> Str {
  if runtime == AZURE_RUNTIME_DOTNET {
    return "dotnet";
  }
  if runtime == AZURE_RUNTIME_NODE {
    return "node";
  }
  if runtime == AZURE_RUNTIME_PYTHON {
    return "python";
  }
  if runtime == AZURE_RUNTIME_JAVA {
    return "java";
  }
  if runtime == AZURE_RUNTIME_POWERSHELL {
    return "powershell";
  }
  if runtime == AZURE_RUNTIME_CUSTOM {
    return "custom";
  }
  return "unknown";
}

/// Reverse runtime lookup (case-insensitive), or -1 when unknown.
pub fn azure_function_runtime_lookup(name: Str) -> Int {
  if _streq_ci(name, "dotnet") {
    return AZURE_RUNTIME_DOTNET;
  }
  if _streq_ci(name, "node") {
    return AZURE_RUNTIME_NODE;
  }
  if _streq_ci(name, "python") {
    return AZURE_RUNTIME_PYTHON;
  }
  if _streq_ci(name, "java") {
    return AZURE_RUNTIME_JAVA;
  }
  if _streq_ci(name, "powershell") {
    return AZURE_RUNTIME_POWERSHELL;
  }
  if _streq_ci(name, "custom") {
    return AZURE_RUNTIME_CUSTOM;
  }
  return -1;
}

/// Validate a function app shape (name, Azure location, runtime, version).
pub fn azure_function_app_lookup(name: Str, location: Str, runtime: Int, runtime_version: Str) -> Result[AzureFunctionApp, Str] {
  if !azure_function_app_name_valid(name) {
    return _err_app("azure: invalid function app name");
  }
  if !compute.azure_location_valid(location) {
    return _err_app("azure: unknown location: " + location);
  }
  if !azure_function_runtime_valid(runtime) {
    return _err_app("azure: invalid runtime");
  }
  if runtime_version.len() == 0 || runtime_version.len() > 32 {
    return _err_app("azure: invalid runtime version");
  }
  return _ok_app(AzureFunctionApp{ name: name; location: location; runtime: runtime; runtime_version: runtime_version; });
}

/// Default hostname "{app}.azurewebsites.net".
pub fn azure_function_default_hostname(app: &AzureFunctionApp) -> Str {
  let n: Str = app.name;
  return n + ".azurewebsites.net";
}

// --------------------------------------------------
//  Trigger, keys, invoke
// --------------------------------------------------

/// True for the eight HTTP methods Azure Functions routes accept.
pub fn azure_trigger_method_valid(method: Str) -> Bool {
  let m = base.azure_lower(_trim(method));
  if m.len() == 0 {
    return false;
  }
  if _streq_ci(m, "get") {
    return true;
  }
  if _streq_ci(m, "post") {
    return true;
  }
  if _streq_ci(m, "put") {
    return true;
  }
  if _streq_ci(m, "delete") {
    return true;
  }
  if _streq_ci(m, "patch") {
    return true;
  }
  if _streq_ci(m, "head") {
    return true;
  }
  if _streq_ci(m, "options") {
    return true;
  }
  if _streq_ci(m, "trace") {
    return true;
  }
  return false;
}

/// True when `method` appears in a comma-separated methods list.
pub fn azure_trigger_method_allowed(methods_csv: Str, method: Str) -> Bool {
  if methods_csv.len() == 0 {
    return false;
  }
  var toks = Vec[Str].new();
  _split_csv(methods_csv, &mut toks);
  var i = 0;
  while i < toks.len() {
    let t: Str = toks[i];
    let tt = _trim(t);
    if tt.len() > 0 {
      if _streq_ci(tt, method) {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

/// Trigger shape: valid route, 1..8 valid HTTP methods, known auth level.
pub fn azure_trigger_valid(t: &AzureHttpTrigger) -> Bool {
  let route: Str = t.route;
  let csv: Str = t.methods_csv;
  let lvl: Int = t.auth_level;
  if !azure_route_valid(route) {
    return false;
  }
  if lvl < AZURE_AUTH_ANONYMOUS || lvl > AZURE_AUTH_ADMIN {
    return false;
  }
  if csv.len() == 0 {
    return false;
  }
  var toks = Vec[Str].new();
  _split_csv(csv, &mut toks);
  if toks.len() < 1 || toks.len() > 8 {
    return false;
  }
  var i = 0;
  while i < toks.len() {
    let t2: Str = toks[i];
    let tt = _trim(t2);
    if !azure_trigger_method_valid(tt) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Function key: 1..128 URL-safe base64 characters.
pub fn azure_function_key_valid(key: Str) -> Bool {
  let n = key.len();
  if n < 1 || n > 128 {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(key, i);
    let ok = base.azure_is_alpha(b) || base.azure_is_digit(b) || b == 95 || b == 45;
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Invoke URL "https://{app}.azurewebsites.net/{route}" (leading '/' in the
/// route is ignored; the root route yields a trailing '/').
pub fn azure_function_invoke_url(app_name: Str, route: Str) -> Result[Str, Str] {
  if !azure_function_app_name_valid(app_name) {
    return _err_str("azure: invalid function app name");
  }
  let r = _strip_lead_slash(route);
  return _ok_str("https://" + app_name + ".azurewebsites.net/" + r);
}

/// HTTP status class for Azure Functions responses.
pub fn azure_function_status_class(status: Int) -> Int {
  if status >= 100 && status <= 199 {
    return AZURE_HTTP_INFORMATIONAL;
  }
  if status >= 200 && status <= 299 {
    return AZURE_HTTP_SUCCESS;
  }
  if status >= 300 && status <= 399 {
    return AZURE_HTTP_REDIRECT;
  }
  if status >= 400 && status <= 499 {
    return AZURE_HTTP_CLIENT_ERROR;
  }
  if status >= 500 && status <= 599 {
    return AZURE_HTTP_SERVER_ERROR;
  }
  return AZURE_HTTP_UNKNOWN;
}

/// True for throttling / transient gateway statuses (408, 429, 500, 502,
/// 503, 504).
pub fn azure_function_status_retryable(status: Int) -> Bool {
  if status == 408 {
    return true;
  }
  if status == 429 {
    return true;
  }
  if status == 500 {
    return true;
  }
  if status == 502 {
    return true;
  }
  if status == 503 {
    return true;
  }
  if status == 504 {
    return true;
  }
  return false;
}
