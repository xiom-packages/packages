// XIOM -- xiom.router: deterministic HTTP route table
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, stdlib-only route table: methods and path patterns are registered
// in order (router_add) and looked up by method + path (router_match). A
// pattern segment is either a literal, compared byte-for-byte, or a `:name`
// parameter that matches exactly one non-empty path segment and captures its
// raw text. The first registered route whose pattern matches the path shape
// AND whose method matches is the result (registration order, no
// specificity); when only the path shape matches, the result is 405 and
// router_allowed_methods reports the Allow-list; otherwise the result is 404.
// See SPEC.md for the matching rules, API contract, error catalog and test
// plan.
//
// What is covered:
//   * router_new / router_add / router_count: ordered route registration
//     with validation (empty method, pattern leading slash, empty parameter
//     name);
//   * router_match: RouteMatch{code, index, params} with 200/404/405 and the
//     captured :name segments in path order;
//   * router_allowed_methods: every matching pattern's method, registration
//     order, deduplicated;
//   * router_method / router_pattern: index accessors in registration order.
//
// Deliberate boundaries: no percent-decoding, no query handling (the caller
// strips the query string before calling), no wildcards, no regex, no
// specificity ranking, no method normalization (byte-exact, case-sensitive),
// no I/O and no global state.
//
// v0.63.1 notes that shaped this module:
//   * free functions only; route tables travel by reference (`&mut` to add,
//     `&` to look up), state lives in two parallel Vec[Str] fields.
//   * every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison (_byte_at_i).
//   * no `==` on Str anywhere: every string comparison goes through
//     xiom.string.compare.str_compare.
//   * every Vec element read is bound to a typed local first.

module xiom.router

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One captured path parameter: the pattern's parameter name (the text after
/// the leading ':' of a pattern segment) and the raw path segment it matched.
/// Fields are public for direct reads; router_match returns them in path
/// order.
pub type RouteParam = { name: Str; value: Str; }

/// The result of a single lookup.
/// code: 200 = the returned index is the route that matched method and path
/// shape; 404 = no registered pattern matches the path shape; 405 = at least
/// one pattern matches the path shape but no registered method equals the
/// queried method.
/// index: route index of the first (registration-order) 200 match, else -1.
/// params: captured :name segments in path order; empty for 404 and 405.
pub type RouteMatch = { code: Int; index: Int; params: Vec[RouteParam]; }

/// An ordered route table. methods[i] and patterns[i] describe route i;
/// both vectors are pushed together, so they always have the same length.
/// Fields are public; router_add / router_match / router_allowed_methods are
/// the intended entry points.
pub type Router = { methods: Vec[Str]; patterns: Vec[Str]; }

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so comparisons never touch raw UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when a pattern segment is a `:name` parameter: at least two bytes
// whose first byte is ':' (58). The single-byte ":" segment is not a
// parameter; router_add rejects it as an empty parameter name.
fn _is_param_segment(seg: Str) -> Bool {
  if seg.len() < 2 {
    return false;
  }
  return _byte_at_i(seg, 0) == 58;
}

// --------------------------------------------------
//  Path splitting and shape matching
// --------------------------------------------------

// Split a path or pattern into segments: strip one leading '/', then split on
// '/'. "" and "/" yield zero segments (the root); trailing and interior
// slashes are significant, so "/a/" is ["a", ""] and "/a//b" is ["a", "",
// "b"]. A path without a leading slash is split as-is.
fn _split_path(p: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = p.len();
  if n == 0 {
    return out;
  }
  var start = 0;
  if _byte_at_i(p, 0) == 47 {
    start = 1;
  }
  if start >= n {
    return out;
  }
  var seg_start = start;
  var i = start;
  while i < n {
    if _byte_at_i(p, i) == 47 {
      out.push(string.str_slice(p, seg_start, i));
      seg_start = i + 1;
    }
    i = i + 1;
  }
  out.push(string.str_slice(p, seg_start, n));
  return out;
}

// True when `pattern` and `path` have the same segment count and every pair
// is either a byte-for-byte literal equality or a `:name` parameter against
// a non-empty path segment. An empty path segment only satisfies a literal
// empty segment, never a parameter.
fn _path_shape_matches(pattern: Str, path: Str) -> Bool {
  let ps = _split_path(pattern);
  let xs = _split_path(path);
  if ps.len() != xs.len() {
    return false;
  }
  var i = 0;
  while i < ps.len() {
    let pseg: Str = ps[i];
    let xseg: Str = xs[i];
    if _is_param_segment(pseg) {
      if xseg.len() == 0 {
        return false;
      }
    } else {
      if compare.str_compare(pseg, xseg) != 0 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// Captured :name segments of a pattern/path pair that is already known to
// shape-match, in path order. Parameter names are the pattern segment text
// after the leading ':'; values are the raw path segments (no decoding).
fn _capture(pattern: Str, path: Str) -> Vec[RouteParam] {
  var params = Vec[RouteParam].new();
  let ps = _split_path(pattern);
  let xs = _split_path(path);
  var i = 0;
  while i < ps.len() {
    let pseg: Str = ps[i];
    if _is_param_segment(pseg) {
      let xseg: Str = xs[i];
      let name = string.str_slice(pseg, 1, pseg.len());
      params.push(RouteParam{ name: name; value: xseg; });
    }
    i = i + 1;
  }
  return params;
}

// True when `v` already holds `s` (byte-exact, case-sensitive).
fn _contains_str(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let cur: Str = v[i];
    if compare.str_compare(cur, s) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Registration
// --------------------------------------------------

/// Create an empty route table.
/// Returns: a Router with zero registered routes.
/// Error case: none.
/// Complexity: O(1).
pub fn router_new() -> Router {
  return Router{ methods: Vec[Str].new(); patterns: Vec[Str].new(); };
}

/// Register one route and return its index (the current route count before
/// the push, so indices are consecutive from 0 in registration order).
/// Params: r - the table to mutate; method - the HTTP method string, matched
/// byte-exactly and case-sensitively at lookup time; pattern - the path
/// pattern, which must start with '/'.
/// Returns: Ok(index) with the new route's registration index.
/// Error case: Err("router: empty method") when method is ""; Err("router:
/// pattern must start with '/'") when pattern is "" or does not begin with
/// '/'; Err("router: empty parameter name") when a pattern segment is a bare
/// ':' with no name after it. On Err nothing is registered.
/// Complexity: O(pattern length).
pub fn router_add(r: &mut Router, method: Str, pattern: Str) -> Result[Int, Str] {
  if method.len() == 0 {
    return Err("router: empty method");
  }
  if pattern.len() == 0 || _byte_at_i(pattern, 0) != 47 {
    return Err("router: pattern must start with '/'");
  }
  let segs = _split_path(pattern);
  var i = 0;
  while i < segs.len() {
    let seg: Str = segs[i];
    if seg.len() == 1 && _byte_at_i(seg, 0) == 58 {
      return Err("router: empty parameter name");
    }
    i = i + 1;
  }
  r.methods.push(method);
  r.patterns.push(pattern);
  return Ok(r.methods.len() - 1);
}

// --------------------------------------------------
//  Lookup
// --------------------------------------------------

/// Look up a method + path pair in registration order.
/// Params: r - the route table; method - the method string to match
/// (byte-exact, case-sensitive); path - the request path without the query
/// string (the caller strips it; there is no percent-decoding).
/// Returns: a RouteMatch. code 200 with index = the first route whose
/// pattern matches the path shape and whose method equals `method`, and
/// params = its captured :name segments in path order; code 405 with
/// index = -1 and empty params when at least one pattern matches the path
/// shape but no registered method equals `method`; code 404 with index = -1
/// and empty params when no pattern matches the path shape.
/// Error case: none (errors travel in the result struct).
/// Complexity: O(routes * (pattern + path length)).
pub fn router_match(r: &Router, method: Str, path: Str) -> RouteMatch {
  var shape_hit = false;
  var i = 0;
  while i < r.patterns.len() {
    let pat: Str = r.patterns[i];
    if _path_shape_matches(pat, path) {
      shape_hit = true;
      let reg: Str = r.methods[i];
      if compare.str_compare(reg, method) == 0 {
        let captured = _capture(pat, path);
        return RouteMatch{ code: 200; index: i; params: captured; };
      }
    }
    i = i + 1;
  }
  if shape_hit {
    return RouteMatch{ code: 405; index: -1; params: Vec[RouteParam].new(); };
  }
  return RouteMatch{ code: 404; index: -1; params: Vec[RouteParam].new(); };
}

/// Methods of every registered pattern whose path shape matches `path`, in
/// registration order and deduplicated (byte-exact compares). This is the
/// Allow-list input for 405 responses.
/// Params: r - the route table; path - the request path without the query
/// string.
/// Returns: the matching methods in first-registration order, with later
/// duplicates dropped; empty when no pattern matches the path shape.
/// Error case: none.
/// Complexity: O(routes * (pattern + path length) + matches^2).
pub fn router_allowed_methods(r: &Router, path: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < r.patterns.len() {
    let pat: Str = r.patterns[i];
    if _path_shape_matches(pat, path) {
      let m: Str = r.methods[i];
      if !_contains_str(&out, m) {
        out.push(m);
      }
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of registered routes.
/// Params: r - the route table.
/// Returns: the route count.
/// Error case: none.
/// Complexity: O(1).
pub fn router_count(r: &Router) -> Int {
  return r.methods.len();
}

/// Method of route `i` in registration order.
/// Params: r - the route table; i - route index.
/// Returns: Ok(method) for 0 <= i < router_count(r).
/// Error case: Err("router: index out of range") when i < 0 or i >=
/// router_count(r).
/// Complexity: O(1).
pub fn router_method(r: &Router, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= r.methods.len() {
    return Err("router: index out of range");
  }
  let m: Str = r.methods[i];
  return Ok(m);
}

/// Pattern of route `i` in registration order.
/// Params: r - the route table; i - route index.
/// Returns: Ok(pattern) for 0 <= i < router_count(r).
/// Error case: Err("router: index out of range") when i < 0 or i >=
/// router_count(r).
/// Complexity: O(1).
pub fn router_pattern(r: &Router, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= r.patterns.len() {
    return Err("router: index out of range");
  }
  let p: Str = r.patterns[i];
  return Ok(p);
}
