// XIOM -- xiom.robots: robots.txt parsing, canonical emitting and rule matching
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Greenfield package: pure XIOM, no FFI, no file I/O, no network fetching.
//
// Model: one parsed robots.txt document is a flat record of parallel vectors
// (Vec[StructType] is not usable in this compiler). Groups are stored as
// ranges: group g owns agents[agent_start[g] .. agent_start[g] +
// agent_count[g]) and rules[rule_start[g] .. rule_start[g] + rule_count[g]);
// the rule paths and flags live in the index-aligned rule_path / rule_allow
// vectors, and crawl_delay[g] holds -1 for "unset" or the recorded
// non-negative delay. Sitemap values are document-global and stored
// separately, in source order.
//
// Grammar (see SPEC.md for the full statement):
//   line       = *( byte except LF )                    ; LF or CRLF
//   directive  = ws* name ws* ":" ws* value ws* ( "#" comment )?
//   name       = "user-agent" / "allow" / "disallow" / "crawl-delay" / "sitemap"
//                (ASCII case-insensitive)
// Blank lines and comment-only lines are skipped; "#" starts a comment
// anywhere on a line and runs to the end of the line. Tab and space are
// whitespace; the surrounding whitespace of the name and value is trimmed.
//
// Documented decisions (pinned in SPEC.md and covered by the conformance
// suite):
//   * field names are ASCII case-insensitive; the emitted canonical spelling
//     is "User-agent", "Allow", "Disallow", "Crawl-delay", "Sitemap";
//   * a User-agent line appends to the current group while that group has no
//     recorded rule and otherwise starts a new group; Allow, Disallow and
//     Crawl-delay before any User-agent line are errors;
//   * empty Disallow (and Allow) patterns are stored and match nothing, so
//     an empty Disallow is allow-all;
//   * Crawl-delay is a non-negative canonical decimal: one or more ASCII
//     digits, leading zeros accepted, value <= 2147483647; the last
//     Crawl-delay in a group wins;
//   * Sitemap values must be absolute http/https URLs (scheme matched
//     ASCII case-insensitively; at least one byte after "://") and are
//     recorded document-globally;
//   * unknown fields and control bytes are rejected ("#" comments and
//     whitespace are the only non-printable bytes accepted).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every byte read from a Str goes through
//     xiom.string.byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF`
//     before any comparison (raw UInt8 values compared against constants can
//     miscompile).
//   * Ok/Err for Result[Robots, Str] are constructed only in the leaf helpers
//     _rb_ok/_rb_err; constructing a Result inside a struct-returning
//     function miscompiles in this compiler.
//   * Str equality between values read from Vec[Str] elements goes through
//     xiom.string.compare.str_compare (BUG 17: `==` on such values lowers to
//     a pointer comparison); every element read is bound to a typed local
//     before use.
//   * Vec[Int] element reads are bound to typed locals before use (untyped
//     reads can mis-lower).
//   * No Vec[StructType], no methods, no lambdas, no indexed Vec[fn] calls;
//     parallel vectors are only ever extended together (_rb_group_push).
//
// See SPEC.md for the grammar, matching algorithm, error catalog and the
// test plan.

module xiom.robots

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Byte constants (Int space; see the widening helper)
// --------------------------------------------------

const _RB_TAB: Int = 9;
const _RB_LF: Int = 10;
const _RB_CR: Int = 13;
const _RB_HASH: Int = 35;
const _RB_DOLLAR: Int = 36;
const _RB_STAR: Int = 42;
const _RB_COLON: Int = 58;
const _RB_ZERO: Int = 48;
const _RB_NINE: Int = 57;
const _RB_DEL: Int = 127;

// The largest accepted Crawl-delay value (2^31 - 1).
const _RB_MAX_DELAY: Int = 2147483647;

// LF as a UInt8, for the byte builder.
const _RB_LF_BYTE: UInt8 = 10u8;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(r) for Result[Robots, Str].
fn _rb_ok(r: Robots) -> Result[Robots, Str] {
  return Ok(r);
}

// Err(m) for Result[Robots, Str].
fn _rb_err(m: Str) -> Result[Robots, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed robots.txt document, stored as parallel vectors. Groups are
/// ranges: group g owns agents[agent_start[g] .. +agent_count[g]) and rules
/// [rule_start[g] .. +rule_count[g]); rule_path i is an Allow rule when
/// rule_allow[i] is non-zero, otherwise a Disallow rule. crawl_delay[g] is -1
/// when the group has no Crawl-delay. sitemaps holds the document-global
/// Sitemap URLs in source order. The five group-parallel vectors always have
/// the same length in a parsed document.
pub type Robots = {
  agent_start: Vec[Int];
  agent_count: Vec[Int];
  agents: Vec[Str];
  rule_start: Vec[Int];
  rule_count: Vec[Int];
  rule_path: Vec[Str];
  rule_allow: Vec[Int];
  crawl_delay: Vec[Int];
  sitemaps: Vec[Str];
}

// --------------------------------------------------
//  Byte and scan helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _rb_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when every byte of `text` is acceptable input: LF and TAB anywhere, CR
// only immediately before LF (so lone CR is rejected), and no other C0
// control byte or DEL. The message for a violation carries no payload because
// the offending bytes themselves may be untrustworthy.
fn _rb_scan_clean(text: Str) -> Bool {
  let n = text.len();
  var i = 0;
  while i < n {
    let b = _rb_byte(text, i);
    if b < 32 && b != _RB_LF && b != _RB_TAB {
      if b != _RB_CR {
        return false;
      }
      if i + 1 >= n || _rb_byte(text, i + 1) != _RB_LF {
        return false;
      }
    } elif b == _RB_DEL {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the first '#' in s, or -1 when absent.
fn _rb_hash_index(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _rb_byte(s, i) == _RB_HASH {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first ':' in s, or -1 when absent.
fn _rb_colon_index(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _rb_byte(s, i) == _RB_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Kind of a directive name: 0 user-agent, 1 disallow, 2 allow, 3 crawl-delay,
// 4 sitemap, -1 unknown. Lookup is ASCII case-insensitive.
fn _rb_field_kind(name: Str) -> Int {
  if compare.str_compare_ignore_case(name, "user-agent") == 0 {
    return 0;
  }
  if compare.str_compare_ignore_case(name, "disallow") == 0 {
    return 1;
  }
  if compare.str_compare_ignore_case(name, "allow") == 0 {
    return 2;
  }
  if compare.str_compare_ignore_case(name, "crawl-delay") == 0 {
    return 3;
  }
  if compare.str_compare_ignore_case(name, "sitemap") == 0 {
    return 4;
  }
  return -1;
}

// Scan a Crawl-delay value: one or more ASCII digits, value <= 2147483647.
// Leading zeros are accepted ("007" is 7). Returns the value, or -1 when the
// text is empty, carries a non-digit byte, or exceeds the cap (the cap is
// checked before every multiply, so no overflow occurs).
fn _rb_scan_delay(s: Str) -> Int {
  let n = s.len();
  if n == 0 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let c = _rb_byte(s, i);
    if c < _RB_ZERO || c > _RB_NINE {
      return -1;
    }
    if v > _RB_MAX_DELAY / 10 {
      return -1;
    }
    v = v * 10 + (c - _RB_ZERO);
    if v > _RB_MAX_DELAY {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// True when `value` is an absolute http/https URL: the scheme is matched
// ASCII case-insensitively and at least one byte follows "http://" or
// "https://" (an empty authority is rejected, no other URL validation is
// performed).
fn _rb_is_http_url(value: Str) -> Bool {
  let n = value.len();
  if n >= 7 {
    if compare.str_compare_ignore_case(string.str_slice(value, 0, 7), "http://") == 0 {
      return n > 7;
    }
  }
  if n >= 8 {
    if compare.str_compare_ignore_case(string.str_slice(value, 0, 8), "https://") == 0 {
      return n > 8;
    }
  }
  return false;
}

// --------------------------------------------------
//  Document construction helpers
// --------------------------------------------------

// An empty document (no groups, no sitemaps).
fn _rb_empty() -> Robots {
  return Robots{
    agent_start: Vec[Int].new();
    agent_count: Vec[Int].new();
    agents: Vec[Str].new();
    rule_start: Vec[Int].new();
    rule_count: Vec[Int].new();
    rule_path: Vec[Str].new();
    rule_allow: Vec[Int].new();
    crawl_delay: Vec[Int].new();
    sitemaps: Vec[Str].new();
  };
}

// Append a new empty group. The five group-parallel vectors are extended
// together so they can never drift inside this module.
fn _rb_group_push(r: &mut Robots) {
  r.agent_start.push(r.agents.len());
  r.agent_count.push(0);
  r.rule_start.push(r.rule_path.len());
  r.rule_count.push(0);
  r.crawl_delay.push(-1);
}

// Append one rule (flag 1 = Allow, 0 = Disallow) to the end of group g.
fn _rb_push_rule(r: &mut Robots, g: Int, path: Str, flag: Int) {
  r.rule_path.push(path);
  r.rule_allow.push(flag);
  let c: Int = r.rule_count[g];
  r.rule_count[g] = c + 1;
}

// --------------------------------------------------
//  Range guards (parallel-vector safety)
// --------------------------------------------------

// Number of groups that can be addressed without crossing a vector boundary:
// the minimum length of the five group-parallel vectors. A parsed document
// always has all five equal, so this equals the group count.
fn _rb_group_span(r: &Robots) -> Int {
  var n = r.agent_start.len();
  if r.agent_count.len() < n { n = r.agent_count.len(); }
  if r.rule_start.len() < n { n = r.rule_start.len(); }
  if r.rule_count.len() < n { n = r.rule_count.len(); }
  if r.crawl_delay.len() < n { n = r.crawl_delay.len(); }
  return n;
}

// Number of agents addressable in group g, or 0 when g is out of range or the
// stored range would run past the end of `agents`.
fn _rb_agent_count(r: &Robots, g: Int) -> Int {
  let groups = _rb_group_span(r);
  if g < 0 || g >= groups {
    return 0;
  }
  let start: Int = r.agent_start[g];
  let count: Int = r.agent_count[g];
  if start < 0 || count <= 0 {
    return 0;
  }
  if start + count > r.agents.len() {
    return 0;
  }
  return count;
}

// Number of rules addressable in group g, or 0 when g is out of range or the
// stored range would run past the end of `rule_path` or `rule_allow`.
fn _rb_rule_count(r: &Robots, g: Int) -> Int {
  let groups = _rb_group_span(r);
  if g < 0 || g >= groups {
    return 0;
  }
  let start: Int = r.rule_start[g];
  let count: Int = r.rule_count[g];
  if start < 0 || count <= 0 {
    return 0;
  }
  if start + count > r.rule_path.len() {
    return 0;
  }
  if start + count > r.rule_allow.len() {
    return 0;
  }
  return count;
}

// True when group g already has a recorded rule or a Crawl-delay, i.e. its
// agent list is closed and another User-agent line starts a new group.
fn _rb_group_has_rules(r: &Robots, g: Int) -> Bool {
  if g < 0 || g >= _rb_group_span(r) {
    return false;
  }
  if _rb_rule_count(r, g) > 0 {
    return true;
  }
  let cd: Int = r.crawl_delay[g];
  return cd >= 0;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory robots.txt document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Robots) for a valid document (including an empty one); Err
/// with a "robots: ..." message for a rule before any User-agent line, a bad
/// Crawl-delay, an empty User-agent token, a non-absolute Sitemap URL, an
/// unknown field, a line without ':' or a control byte in the input.
/// Behavior: "#" starts a comment anywhere; blank and comment-only lines are
/// skipped; names are ASCII case-insensitive; an empty Disallow/Allow is
/// stored as an empty pattern that matches nothing (empty Disallow =
/// allow-all); a User-agent line appends to the current group while that
/// group has no recorded rule and otherwise starts a new group; the last
/// Crawl-delay in a group wins.
/// Error case: see the catalog in SPEC.md; messages are deterministic and
/// start with "robots: ".
/// Complexity: O(total input length).
pub fn robots_parse(text: Str) -> Result[Robots, Str] {
  if !_rb_scan_clean(text) {
    return _rb_err("robots: control byte in input");
  }
  var r = _rb_empty();
  var group = -1;
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || _rb_byte(text, i) == _RB_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && _rb_byte(line, raw_len - 1) == _RB_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let hash = _rb_hash_index(line);
      if hash >= 0 {
        line = string.str_slice(line, 0, hash);
      }
      let trimmed = string.str_trim(line);
      let tn = trimmed.len();
      if tn > 0 {
        let colon = _rb_colon_index(trimmed);
        if colon < 0 {
          return _rb_err("robots: missing ':' in line: " + trimmed);
        }
        let name = string.str_trim(string.str_slice(trimmed, 0, colon));
        if name.len() == 0 {
          return _rb_err("robots: missing field name in line: " + trimmed);
        }
        let value = string.str_trim(string.str_slice(trimmed, colon + 1, tn));
        let kind = _rb_field_kind(name);
        if kind == 0 {
          if value.len() == 0 {
            return _rb_err("robots: empty user-agent token: " + trimmed);
          }
          if group < 0 {
            _rb_group_push(&mut r);
            group = 0;
          } elif _rb_group_has_rules(&r, group) {
            _rb_group_push(&mut r);
            group = group + 1;
          }
          r.agents.push(value);
          let c: Int = r.agent_count[group];
          r.agent_count[group] = c + 1;
        } elif kind == 1 || kind == 2 {
          if group < 0 {
            return _rb_err("robots: rule before any user-agent: " + trimmed);
          }
          var flag = 0;
          if kind == 2 {
            flag = 1;
          }
          _rb_push_rule(&mut r, group, value, flag);
        } elif kind == 3 {
          if group < 0 {
            return _rb_err("robots: rule before any user-agent: " + trimmed);
          }
          let delay = _rb_scan_delay(value);
          if delay < 0 {
            return _rb_err("robots: bad crawl-delay: " + value);
          }
          r.crawl_delay[group] = delay;
        } elif kind == 4 {
          if !_rb_is_http_url(value) {
            return _rb_err("robots: sitemap must be an absolute http or https URL: " + value);
          }
          r.sitemaps.push(value);
        } else {
          return _rb_err("robots: unknown field: " + name);
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _rb_ok(r);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Create an empty document: no groups and no sitemaps. `robots_emit` on it
/// returns "".
pub fn robots_new() -> Robots {
  return _rb_empty();
}

/// Number of groups in `r`. Out-of-range accessors in this module never
/// trap: they return "" / false / None and treat bad indexes as absent.
pub fn robots_group_count(r: &Robots) -> Int {
  return _rb_group_span(r);
}

/// Number of User-agent tokens in group `group`; 0 when `group` is out of
/// range.
pub fn robots_agent_count(r: &Robots, group: Int) -> Int {
  return _rb_agent_count(r, group);
}

/// User-agent token `index` of group `group`, verbatim (for example "*").
/// Returns "" when either index is out of range.
pub fn robots_agent(r: &Robots, group: Int, index: Int) -> Str {
  let c = _rb_agent_count(r, group);
  if index < 0 || index >= c {
    return "";
  }
  let start: Int = r.agent_start[group];
  let a: Str = r.agents[start + index];
  return a;
}

/// Number of Allow/Disallow rules in group `group`; 0 when `group` is out of
/// range.
pub fn robots_rule_count(r: &Robots, group: Int) -> Int {
  return _rb_rule_count(r, group);
}

/// Pattern of rule `index` in group `group`, verbatim (may be "" for an
/// empty Allow/Disallow). Returns "" when either index is out of range.
pub fn robots_rule_path(r: &Robots, group: Int, index: Int) -> Str {
  let c = _rb_rule_count(r, group);
  if index < 0 || index >= c {
    return "";
  }
  let start: Int = r.rule_start[group];
  let p: Str = r.rule_path[start + index];
  return p;
}

/// True when rule `index` in group `group` is an Allow rule, false when it is
/// a Disallow rule or either index is out of range.
pub fn robots_rule_allow(r: &Robots, group: Int, index: Int) -> Bool {
  let c = _rb_rule_count(r, group);
  if index < 0 || index >= c {
    return false;
  }
  let start: Int = r.rule_start[group];
  let f: Int = r.rule_allow[start + index];
  return f != 0;
}

/// Crawl-delay of group `group`: Some(value) when recorded, None when the
/// group has none or `group` is out of range. Value is 0..2147483647.
pub fn robots_crawl_delay(r: &Robots, group: Int) -> Option[Int] {
  if group < 0 || group >= _rb_group_span(r) {
    return None;
  }
  let cd: Int = r.crawl_delay[group];
  if cd < 0 {
    return None;
  }
  return Some(cd);
}

/// Number of document-global Sitemap lines recorded in `r`.
pub fn robots_sitemap_count(r: &Robots) -> Int {
  return r.sitemaps.len();
}

/// Sitemap URL `index`, verbatim; "" when `index` is out of range.
pub fn robots_sitemap(r: &Robots, index: Int) -> Str {
  if index < 0 || index >= r.sitemaps.len() {
    return "";
  }
  let u: Str = r.sitemaps[index];
  return u;
}

// --------------------------------------------------
//  Rule matching
// --------------------------------------------------

// Glob core: `*` in `pat` matches any byte run (including empty), every other
// byte must match exactly. When `anchored` is true the whole path must be
// consumed; otherwise a prefix match succeeds as soon as the pattern is
// exhausted. Backtracking is the classic single-star-index scan.
fn _rb_glob(pat: Str, path: Str, anchored: Bool) -> Bool {
  let pn = pat.len();
  let sn = path.len();
  var p = 0;
  var i = 0;
  var star_p = -1;
  var star_i = -1;
  while i < sn {
    if p < pn {
      let c = _rb_byte(pat, p);
      if c == _RB_STAR {
        star_p = p;
        star_i = i;
        p = p + 1;
        continue;
      }
      if c == _rb_byte(path, i) {
        p = p + 1;
        i = i + 1;
        continue;
      }
    } elif !anchored {
      return true;
    }
    if star_p >= 0 {
      star_i = star_i + 1;
      i = star_i;
      p = star_p + 1;
      continue;
    }
    return false;
  }
  while p < pn && _rb_byte(pat, p) == _RB_STAR {
    p = p + 1;
  }
  return p == pn;
}

/// Match one robots.txt path pattern against `path`.
/// Params: pattern - the rule pattern as written (for example "/private/");
/// path - the request path to test (for example "/private/x").
/// Returns: true when the pattern applies. Matching is byte-wise and
/// case-sensitive; `*` matches any byte run (including empty); a trailing `$`
/// anchors the pattern to the end of the path; any other `$` is a literal
/// byte. Without a trailing `$` the pattern is a prefix match. An empty
/// pattern matches nothing (so an empty Disallow is allow-all). A lone "$"
/// matches only the empty path.
/// Error case: none.
/// Complexity: O(|path| * |pattern|) worst case.
pub fn robots_path_matches(pattern: Str, path: Str) -> Bool {
  let n = pattern.len();
  if n == 0 {
    return false;
  }
  var body = pattern;
  var anchored = false;
  if _rb_byte(pattern, n - 1) == _RB_DOLLAR {
    anchored = true;
    body = string.str_slice(pattern, 0, n - 1);
  }
  return _rb_glob(body, path, anchored);
}

/// Match one User-agent token against a crawler user-agent string.
/// Params: token - a User-agent token (for example "googlebot"); user_agent -
/// the crawler's user-agent string (for example "Googlebot/2.1").
/// Returns: true when the token is "*" (matches every crawler) or when the
/// token is a case-insensitive ASCII prefix of `user_agent`. An empty token
/// never matches.
/// Error case: none.
/// Complexity: O(|token|).
pub fn robots_agent_matches(token: Str, user_agent: Str) -> Bool {
  let tn = token.len();
  if tn == 0 {
    return false;
  }
  if tn == 1 && _rb_byte(token, 0) == _RB_STAR {
    return true;
  }
  let un = user_agent.len();
  if tn > un {
    return false;
  }
  var i = 0;
  while i < tn {
    var a = _rb_byte(token, i);
    var b = _rb_byte(user_agent, i);
    if a >= 65 && a <= 90 { a = a + 32; }
    if b >= 65 && b <= 90 { b = b + 32; }
    if a != b {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Index of the group that applies to `user_agent`, or -1 when no group
/// matches.
/// Params: r - the document; user_agent - the crawler's user-agent string.
/// Returns: the group whose longest matching token is longest overall, where
/// a "*" token counts as length 0 (fallback). The earliest group wins ties,
/// so a later duplicate group is inert but preserved.
/// Error case: none.
/// Complexity: O(agent token count * |user_agent|).
pub fn robots_matching_group(r: &Robots, user_agent: Str) -> Int {
  let groups = _rb_group_span(r);
  var best = -1;
  var best_len = -1;
  var g = 0;
  while g < groups {
    let ac = _rb_agent_count(r, g);
    let start: Int = r.agent_start[g];
    var spec = -1;
    var k = 0;
    while k < ac {
      let tok: Str = r.agents[start + k];
      if robots_agent_matches(tok, user_agent) {
        let tl = string.str_len(tok);
        var weight = tl;
        if tl == 1 && _rb_byte(tok, 0) == _RB_STAR {
          weight = 0;
        }
        if weight > spec {
          spec = weight;
        }
      }
      k = k + 1;
    }
    if spec > best_len {
      best_len = spec;
      best = g;
    }
    g = g + 1;
  }
  return best;
}

/// Decide whether `path` is allowed for `user_agent`.
/// Params: r - the document; user_agent - the crawler's user-agent string;
/// path - the request path.
/// Returns: true when the crawler may fetch `path`. The group is selected by
/// `robots_matching_group`; when no group matches the path is allowed. Within
/// the selected group the matching rule with the longest pattern (raw byte
/// length, including "*" and "$") wins; when several rules share the longest
/// matching pattern length, Allow wins; a rule with an empty pattern matches
/// nothing; when no rule matches, the path is allowed.
/// Error case: none.
/// Complexity: O(rules of the selected group * |path| * |pattern|).
pub fn robots_is_allowed(r: &Robots, user_agent: Str, path: Str) -> Bool {
  let g = robots_matching_group(r, user_agent);
  if g < 0 {
    return true;
  }
  let rc = _rb_rule_count(r, g);
  if rc == 0 {
    return true;
  }
  let start: Int = r.rule_start[g];
  var best_len = -1;
  var best_allow = true;
  var k = 0;
  while k < rc {
    let pat: Str = r.rule_path[start + k];
    if robots_path_matches(pat, path) {
      let l = string.str_len(pat);
      let flag: Int = r.rule_allow[start + k];
      if l > best_len {
        best_len = l;
        best_allow = flag != 0;
      } elif l == best_len {
        if flag != 0 {
          best_allow = true;
        }
      }
    }
    k = k + 1;
  }
  return best_allow;
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

// Append one canonical "name:" / "name: value" line plus LF. An empty value
// emits the bare field name with no trailing space.
fn _rb_emit_field(out: &mut Vec[UInt8], name: Str, value: Str) {
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, ":");
  if string.str_len(value) > 0 {
    builder.sb_push_str(out, " ");
    builder.sb_push_str(out, value);
  }
  out.push(_RB_LF_BYTE);
}

/// Emit the canonical robots.txt text of `r`.
/// Params: r - the document to serialize.
/// Returns: the document as LF-separated lines with no trailing LF. Each
/// group is written in order as one "User-agent: token" line per agent, then
/// its rules in order ("Allow: pattern" / "Disallow: pattern"; an empty
/// pattern emits a bare "Disallow:"), then "Crawl-delay: value" when set. Two
/// blank-line-separated blocks follow the groups in order: the groups
/// themselves (one blank line between two groups) and, after one more blank
/// line when groups were written, the Sitemap lines. An empty document emits
/// "".
/// Error case: none. Values are written verbatim, so emit is lossless for
/// documents produced by `robots_parse`; it assumes no value contains a
/// control byte or LF (parse rejects those).
/// Complexity: O(total output length).
pub fn robots_emit(r: &Robots) -> Str {
  var out = Vec[UInt8].new();
  let groups = _rb_group_span(r);
  var wrote = false;
  var g = 0;
  while g < groups {
    if wrote {
      out.push(_RB_LF_BYTE);
    }
    let ac = _rb_agent_count(r, g);
    let astart: Int = r.agent_start[g];
    var k = 0;
    while k < ac {
      let a: Str = r.agents[astart + k];
      _rb_emit_field(&mut out, "User-agent", a);
      k = k + 1;
    }
    let rc = _rb_rule_count(r, g);
    let rstart: Int = r.rule_start[g];
    var j = 0;
    while j < rc {
      let p: Str = r.rule_path[rstart + j];
      let f: Int = r.rule_allow[rstart + j];
      if f != 0 {
        _rb_emit_field(&mut out, "Allow", p);
      } else {
        _rb_emit_field(&mut out, "Disallow", p);
      }
      j = j + 1;
    }
    let cd: Int = r.crawl_delay[g];
    if cd >= 0 {
      _rb_emit_field(&mut out, "Crawl-delay", convert.int_to_string(cd));
    }
    wrote = true;
    g = g + 1;
  }
  let sc = r.sitemaps.len();
  var s = 0;
  while s < sc {
    if wrote {
      out.push(_RB_LF_BYTE);
    }
    let u: Str = r.sitemaps[s];
    _rb_emit_field(&mut out, "Sitemap", u);
    wrote = true;
    s = s + 1;
  }
  if out.len() > 0 {
    out.pop();
  }
  return builder.sb_to_str(&out);
}
