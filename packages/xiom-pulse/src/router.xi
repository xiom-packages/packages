// XIOM PULSE -- route matching, query-string splitting and percent-decoding.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Carved from the frozen PULSE core at 56eb9f8 (see PROVENANCE.md) with two
// extraction changes, both documented in SPEC.md:
//   * the product route table (route_defs/routes_list, the original 25-entry
//     app table) is OUT; route_match now matches against a caller-supplied
//     (method, pattern) list in registration order, and the route id is
//     still the 1-based index into that list;
//   * `use xiom.router;` (a registry package) is dropped -- the dependency
//     target is xiom.std only -- and its matching mechanism (pattern
//     shapes, :param capture, registration-order first match, 404/405 +
//     allowed-methods) is inlined below as a documented local shim
//     (local_router_*), ported 1:1 from xiom.router 0.1.0.
//
// Every route is also reachable through the `/v1` alias prefix (v1_path
// strips it before matching).
module xiom.pulse.router

use xiom.string;

/// PulseRoute - PULSE's route outcome: kind 0 = not found, 1 = matched,
/// 2 = method not allowed (allow holds "GET, POST"). Query parameters are
/// split off the target and exposed decoded.
pub type PulseRoute = {
  kind: Int;
  route_id: Int;
  allow: Str;
  param_names: Vec[Str];
  param_values: Vec[Str];
  query_names: Vec[Str];
  query_values: Vec[Str];
}

/// split_target splits "/path?query" into (path, query). Pure.
pub fn split_target(target: Str) -> (Str, Str) {
  let qo = string.str_index_of(target, "?");
  if qo.is_none {
    return (target, "");
  }
  let q = qo.value;
  return (string.str_slice(target, 0, q), string.str_slice(target, q + 1, target.len()));
}

/// v1_path maps a versioned `/v1/<rest>` alias onto the canonical
/// `<rest>` path, query preserved: `/v1/api/events?limit=1` ->
/// `/api/events?limit=1`; `/v1` and `/v1/` map to `/`; anything else
/// passes through untouched. Complexity: O(n). Pure.
pub fn v1_path(target: Str) -> Str {
  let parts = split_target(target);
  let p = parts.0;
  let q = parts.1;
  if p == "/v1" {
    if q.len() > 0 { return "/?" + q; }
    return "/";
  }
  if string.str_starts_with(p, "/v1/") {
    let rest = string.str_slice(p, 3, p.len());
    if q.len() > 0 { return rest + "?" + q; }
    return rest;
  }
  return target;
}

fn hex_val(b: UInt8) -> Int {
  if b >= 48u8 && b <= 57u8 { return (b as Int) - 48; }
  if b >= 65u8 && b <= 70u8 { return (b as Int) - 55; }
  if b >= 97u8 && b <= 102u8 { return (b as Int) - 87; }
  return -1;
}

/// url_decode decodes %XX and '+' in a query component. Pure.
pub fn url_decode(s: Str) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b == 37u8 && i + 2 < s.len() {
      let h1 = hex_val(s.byte_at(i + 1));
      let h2 = hex_val(s.byte_at(i + 2));
      if h1 >= 0 && h2 >= 0 {
        out.push(((h1 * 16 + h2) as UInt8));
        i = i + 3;
      } else {
        out.push(b);
        i = i + 1;
      }
    } else if b == 43u8 {
      out.push(32u8);
      i = i + 1;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

/// parse_query parses "a=1&b=x%20y&c" into name/value lists (decoded). Pure.
pub fn parse_query(qs: Str) -> (Vec[Str], Vec[Str]) {
  var names: Vec[Str] = Vec[Str].new();
  var values: Vec[Str] = Vec[Str].new();
  if qs.len() == 0 {
    return (names, values);
  }
  let pairs = string.str_split(qs, "&");
  var i: Int = 0;
  while i < pairs.len() {
    let p = pairs[i];
    if p.len() > 0 {
      let eo = string.str_index_of(p, "=");
      if eo.is_none {
        names.push(url_decode(p));
        values.push("");
      } else {
        let e = eo.value;
        names.push(url_decode(string.str_slice(p, 0, e)));
        values.push(url_decode(string.str_slice(p, e + 1, p.len())));
      }
    }
    i = i + 1;
  }
  return (names, values);
}

fn join_methods(ms: &Vec[Str]) -> Str {
  var out: Str = "";
  var i: Int = 0;
  while i < ms.len() {
    if i > 0 { out = out + ", "; }
    let s = ms[i];
    out = out + s;
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Local router shim (was registry xiom.router 0.1.0; see the header note).
// Matching semantics ported 1:1: a pattern segment is either a literal,
// compared byte-for-byte, or a `:name` parameter matching exactly one
// non-empty path segment and capturing its raw text; the first registered
// route whose pattern matches the path shape AND whose method matches wins
// (registration order, no specificity); a shape-only match yields 405 with
// the registration-order deduplicated Allow-list; otherwise 404. No
// percent-decoding and no query handling here (the caller strips the query;
// split_target/parse_query own the query side).
// ---------------------------------------------------------------------------

type LocalRouteParam = {
  name: Str;
  value: Str;
}

type LocalRouteMatch = {
  code: Int;
  index: Int;
  params: Vec[LocalRouteParam];
}

type LocalRouter = {
  methods: Vec[Str];
  patterns: Vec[Str];
}

fn local_router_new() -> LocalRouter {
  return LocalRouter{ methods: Vec[Str].new(); patterns: Vec[Str].new() };
}

fn local_router_add(r: &mut LocalRouter, method: Str, pattern: Str) -> Result[Int, Str] {
  if method.len() == 0 {
    return Err("pulse.router: empty method");
  }
  if pattern.len() == 0 || pattern.byte_at(0) != 47u8 {
    return Err("pulse.router: pattern must start with '/'");
  }
  let segs = local_split_path(pattern);
  var i: Int = 0;
  while i < segs.len() {
    let seg = segs[i];
    if seg.len() == 1 && seg.byte_at(0) == 58u8 {
      return Err("pulse.router: empty parameter name");
    }
    i = i + 1;
  }
  r.methods.push(method);
  r.patterns.push(pattern);
  return Ok(r.methods.len() - 1);
}

fn local_split_path(p: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  let n = p.len();
  if n == 0 {
    return out;
  }
  var start: Int = 0;
  if p.byte_at(0) == 47u8 {
    start = 1;
  }
  if start >= n {
    return out;
  }
  var seg_start: Int = start;
  var i: Int = start;
  while i < n {
    if p.byte_at(i) == 47u8 {
      out.push(string.str_slice(p, seg_start, i));
      seg_start = i + 1;
    }
    i = i + 1;
  }
  out.push(string.str_slice(p, seg_start, n));
  return out;
}

fn local_is_param_segment(seg: Str) -> Bool {
  if seg.len() < 2 {
    return false;
  }
  return seg.byte_at(0) == 58u8;
}

fn local_path_shape_matches(pattern: Str, path: Str) -> Bool {
  let ps = local_split_path(pattern);
  let xs = local_split_path(path);
  if ps.len() != xs.len() {
    return false;
  }
  var i: Int = 0;
  while i < ps.len() {
    let pseg = ps[i];
    let xseg = xs[i];
    if local_is_param_segment(pseg) {
      if xseg.len() == 0 {
        return false;
      }
    } else {
      if pseg != xseg {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

fn local_capture(pattern: Str, path: Str) -> Vec[LocalRouteParam] {
  var params: Vec[LocalRouteParam] = Vec[LocalRouteParam].new();
  let ps = local_split_path(pattern);
  let xs = local_split_path(path);
  var i: Int = 0;
  while i < ps.len() {
    let pseg = ps[i];
    if local_is_param_segment(pseg) {
      let xseg = xs[i];
      let name = string.str_slice(pseg, 1, pseg.len());
      params.push(LocalRouteParam{ name: name; value: xseg });
    }
    i = i + 1;
  }
  return params;
}

fn local_contains(v: &Vec[Str], s: Str) -> Bool {
  var i: Int = 0;
  while i < v.len() {
    let cur = v[i];
    if cur == s {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn local_router_match(r: &LocalRouter, method: Str, path: Str) -> LocalRouteMatch {
  var shape_hit: Bool = false;
  var i: Int = 0;
  while i < r.patterns.len() {
    let pat = r.patterns[i];
    if local_path_shape_matches(pat, path) {
      shape_hit = true;
      let reg = r.methods[i];
      if reg == method {
        let captured = local_capture(pat, path);
        return LocalRouteMatch{ code: 200; index: i; params: captured };
      }
    }
    i = i + 1;
  }
  if shape_hit {
    return LocalRouteMatch{ code: 405; index: -1; params: Vec[LocalRouteParam].new() };
  }
  return LocalRouteMatch{ code: 404; index: -1; params: Vec[LocalRouteParam].new() };
}

fn local_router_allowed_methods(r: &LocalRouter, path: Str) -> Vec[Str] {
  var out: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < r.patterns.len() {
    let pat = r.patterns[i];
    if local_path_shape_matches(pat, path) {
      let meth = r.methods[i];
      if !local_contains(&out, meth) {
        out.push(meth);
      }
    }
    i = i + 1;
  }
  return out;
}

/// route_match matches (method, target) against `defs` -- the caller's
/// (method, pattern) list in registration order -- maps the registration
/// index to the route id (index + 1) and returns the PULSE-shaped outcome.
/// The table is rebuilt per call (negligible at current load and avoids
/// module-global mutable state). Complexity: O(routes).
pub fn route_match(method: Str, target: Str, defs: &Vec[(Str, Str)]) -> PulseRoute {
  var m: PulseRoute = PulseRoute{
    kind: 0;
    route_id: 0;
    allow: "";
    param_names: Vec[Str].new();
    param_values: Vec[Str].new();
    query_names: Vec[Str].new();
    query_values: Vec[Str].new();
  };
  let parts = split_target(target);
  let path = parts.0;
  let qp = parse_query(parts.1);
  m.query_names = qp.0;
  m.query_values = qp.1;

  var t = local_router_new();
  var di: Int = 0;
  while di < defs.len() {
    let d = defs[di];
    let _r = local_router_add(&mut t, d.0, d.1);
    di = di + 1;
  }

  let rm = local_router_match(&t, method, path);
  if rm.code == 404 {
    return m;
  }
  if rm.code == 405 {
    m.kind = 2;
    let allowed = local_router_allowed_methods(&t, path);
    m.allow = join_methods(&allowed);
    return m;
  }
  m.kind = 1;
  if rm.index >= 0 && rm.index < defs.len() {
    m.route_id = rm.index + 1;
  }
  var i: Int = 0;
  while i < rm.params.len() {
    let p = rm.params[i];
    m.param_names.push(p.name);
    m.param_values.push(p.value);
    i = i + 1;
  }
  return m;
}
