// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.macro: a pure, deterministic text macro-expansion processor.
//
// Model (full grammar, semantics and error catalog in SPEC.md):
//   * The input is a sequence of lines separated by '\n'. A line whose first
//     non-space bytes are "define " or "undef " is a directive and is removed
//     from the output (its newline is consumed too); every other line is text
//     and is expanded against the macro table as it stands at that point.
//   * "define NAME[(p1, p2)] body" binds NAME; "undef NAME" removes it. A
//     redefinition replaces the previous binding (trace: "redefine").
//   * In text and in bodies, '$' introduces everything: "$NAME"/"$NAME(args)"
//     invokes NAME, "$1".."$N" is a positional argument reference, "$(name)"
//     a named one, "$$" and "\$" emit a literal '$'. A '$' followed by any
//     other byte is copied literally.
//   * Arguments are trimmed of ASCII spaces, are fully expanded in the
//     caller's frame, and are inserted into the body byte-exact; inserted
//     text is never re-scanned (single substitution pass, no hygiene leak).
//   * A macro is pushed on the active stack before its arguments are
//     expanded, so any re-entry (including through an argument) is a cycle.
//     Nesting beyond the depth limit is a recursion error.
//
// v0.62.1 notes that shaped this module:
//   * Free functions only: no methods, no lambdas, no Vec[fn] dispatch, no
//     Vec[StructType] and no struct types; parallel Vec fields instead.
//   * Ok/Err for Result[Str, Str] are constructed only in the tiny leaf
//     helpers _ok_str/_err_str/_ok_vec.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec[Str] / Vec[Int] elements are read into typed locals.
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; all output is collected in a xiom.string.builder buffer.
//   * Int formatting uses xiom.convert.int_to_string (sb_push_int is unsafe
//     for INT_MIN).
//   * Directives are single-line, so a directive can never be the result of
//     an expansion: expansion output is not re-scanned for directives.

module xiom.macro

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_vec(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// --------------------------------------------------
//  Byte constants and low-level helpers
// --------------------------------------------------

const _MAC_LF: Int = 10;      // '\n'
const _MAC_CR: Int = 13;      // '\r'
const _MAC_SP: Int = 32;      // ' '
const _MAC_DOLLAR: Int = 36;  // '$'
const _MAC_LPAREN: Int = 40;  // '('
const _MAC_RPAREN: Int = 41;  // ')'
const _MAC_COMMA: Int = 44;   // ','
const _MAC_BACKSLASH: Int = 92; // '\'
const _MAC_UNDERSCORE: Int = 95; // '_'
const _MAX_DEPTH: Int = 16;

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

fn _is_alpha(c: Int) -> Bool {
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

fn _is_ident_start(c: Int) -> Bool {
  return _is_alpha(c) || c == _MAC_UNDERSCORE;
}

fn _is_ident_char(c: Int) -> Bool {
  return _is_alpha(c) || _is_digit(c) || c == _MAC_UNDERSCORE;
}

// True when `a` and `b` are byte-identical (BUG 17: never `==` on Str).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `items` contains `name`.
fn _contains_str(items: &Vec[Str], name: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    if _streq(item, name) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when the bytes of `w` occur in `s` starting exactly at `at` and ending
// at or before `limit`.
fn _match_word(s: Str, at: Int, limit: Int, w: Str) -> Bool {
  let wn = string.str_len(w);
  if at + wn > limit {
    return false;
  }
  var i = 0;
  while i < wn {
    if _byte(s, at + i) != _byte(w, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// `s` with ASCII spaces trimmed on both sides.
fn _trim(s: Str) -> Str {
  let n = string.str_len(s);
  var a = 0;
  var b = n;
  while a < b && _byte(s, a) == _MAC_SP {
    a = a + 1;
  }
  while b > a && _byte(s, b - 1) == _MAC_SP {
    b = b - 1;
  }
  return string.str_slice(s, a, b);
}

// Number of ',' bytes in `s`.
fn _count_commas(s: Str) -> Int {
  let n = string.str_len(s);
  var i = 0;
  var c = 0;
  while i < n {
    if _byte(s, i) == _MAC_COMMA {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// Index of the ')' matching the '(' at `open`, or -1. Parentheses nest;
// there is no nesting escape other than balance.
fn _find_close(text: Str, open: Int, n: Int) -> Int {
  var depth = 0;
  var i = open;
  while i < n {
    let c = _byte(text, i);
    if c == _MAC_LPAREN {
      depth = depth + 1;
    } elif c == _MAC_RPAREN {
      depth = depth - 1;
      if depth == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Macro table (parallel vectors, mirrored on every mutation)
// --------------------------------------------------

// Index of `name` in `names`, or -1.
fn _table_find(names: &Vec[Str], name: Str) -> Int {
  var i = 0;
  while i < names.len() {
    let n: Str = names[i];
    if _streq(n, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Bind `name` to (arity, encoded params, body), replacing any previous
// binding in place. All four parallel vectors stay the same length.
fn _table_put(names: &mut Vec[Str], arities: &mut Vec[Int], params: &mut Vec[Str],
              bodies: &mut Vec[Str], name: Str, arity: Int, param_list: Str, body: Str) {
  let idx = _table_find(names, name);
  if idx >= 0 {
    arities[idx] = arity;
    params[idx] = param_list;
    bodies[idx] = body;
  } else {
    names.push(name);
    arities.push(arity);
    params.push(param_list);
    bodies.push(body);
  }
}

// Remove `name`; returns true when a binding existed. All four parallel
// vectors are compacted together so order of the survivors is preserved.
fn _table_remove(names: &mut Vec[Str], arities: &mut Vec[Int], params: &mut Vec[Str],
                 bodies: &mut Vec[Str], name: Str) -> Bool {
  let idx = _table_find(names, name);
  if idx < 0 {
    return false;
  }
  var k = idx;
  while k + 1 < names.len() {
    let nn: Str = names[k + 1];
    let aa: Int = arities[k + 1];
    let pp: Str = params[k + 1];
    let bb: Str = bodies[k + 1];
    names[k] = nn;
    arities[k] = aa;
    params[k] = pp;
    bodies[k] = bb;
    k = k + 1;
  }
  names.pop();
  arities.pop();
  params.pop();
  bodies.pop();
  return true;
}

// --------------------------------------------------
//  Parameters
// --------------------------------------------------

// Encode the parameter region of a define (between the parentheses) as the
// comma-joined names with a trailing comma ("a,b,"), or "" for zero params.
// Trailing-comma encoding lets _param_index terminate every segment without
// needing the string length. Returns Err on a malformed or duplicate name.
fn _encode_params(region: Str) -> Result[Str, Str] {
  let n = string.str_len(region);
  var enc = "";
  var seen = Vec[Str].new();
  var any = false;
  var i = 0;
  var start = 0;
  while i <= n {
    if i == n || _byte(region, i) == _MAC_COMMA {
      let seg = _trim(string.str_slice(region, start, i));
      if string.str_len(seg) == 0 {
        if any || i < n {
          return Err("macro: malformed define directive");
        }
      } else {
        if !_is_ident_start(_byte(seg, 0)) {
          return Err("macro: malformed define directive");
        }
        var k = 1;
        while k < string.str_len(seg) {
          if !_is_ident_char(_byte(seg, k)) {
            return Err("macro: malformed define directive");
          }
          k = k + 1;
        }
        if _contains_str(&seen, seg) {
          return _err_str("macro: duplicate parameter: " + seg);
        }
        seen.push(seg);
        enc = enc + seg + ",";
        any = true;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return _ok_str(enc);
}

// Index of parameter `name` in the encoded list, or -1 (empty list -> -1).
fn _param_index(enc: Str, name: Str) -> Int {
  let n = string.str_len(enc);
  if n == 0 {
    return -1;
  }
  var start = 0;
  var k = 0;
  var i = 0;
  while i <= n {
    if i == n || _byte(enc, i) == _MAC_COMMA {
      let seg = string.str_slice(enc, start, i);
      if _streq(seg, name) {
        return k;
      }
      k = k + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Invocation argument parsing
// --------------------------------------------------

// Split the argument region [from, to) at top-level commas, trimming each
// argument of ASCII spaces. A region that is empty or all spaces yields zero
// arguments; empty segments between commas are legal empty arguments.
fn _split_args(text: Str, from: Int, to: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if from >= to {
    return out;
  }
  if string.str_len(_trim(string.str_slice(text, from, to))) == 0 {
    return out;
  }
  var start = from;
  var i = from;
  var depth = 0;
  while i < to {
    let c = _byte(text, i);
    if c == _MAC_LPAREN {
      depth = depth + 1;
    } elif c == _MAC_RPAREN {
      if depth > 0 {
        depth = depth - 1;
      }
    } elif c == _MAC_COMMA && depth == 0 {
      out.push(_trim(string.str_slice(text, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  out.push(_trim(string.str_slice(text, start, to)));
  return out;
}

// --------------------------------------------------
//  Expansion
// --------------------------------------------------

// Expand `text` in the frame (fp = encoded parameter list, fa = argument
// values). Handles '$' escapes, substitutions and invocations left to right
// over a single pass; inserted text is appended byte-exact and never
// re-scanned. The macro table is read-only here; only `stack`/`trace` mutate.
fn _expand(text: Str, fp: Str, fa: &Vec[Str], names: &mut Vec[Str], arities: &mut Vec[Int],
           params: &mut Vec[Str], bodies: &mut Vec[Str], stack: &mut Vec[Str],
           trace: &mut Vec[Str], max_depth: Int) -> Result[Str, Str] {
  var sb = builder.sb_new();
  let n = string.str_len(text);
  var i = 0;
  while i < n {
    let c = _byte(text, i);
    if c == _MAC_BACKSLASH {
      if i + 1 < n {
        let d = _byte(text, i + 1);
        if d == _MAC_BACKSLASH || d == _MAC_DOLLAR {
          builder.sb_push_byte(&mut sb, d as UInt8);
        } else {
          builder.sb_push_byte(&mut sb, _MAC_BACKSLASH as UInt8);
          builder.sb_push_byte(&mut sb, d as UInt8);
        }
        i = i + 2;
      } else {
        builder.sb_push_byte(&mut sb, _MAC_BACKSLASH as UInt8);
        i = i + 1;
      }
    } elif c == _MAC_DOLLAR {
      if i + 1 >= n {
        builder.sb_push_byte(&mut sb, _MAC_DOLLAR as UInt8);
        i = i + 1;
      } else {
        let d = _byte(text, i + 1);
        if d == _MAC_DOLLAR {
          builder.sb_push_byte(&mut sb, _MAC_DOLLAR as UInt8);
          i = i + 2;
        } elif d == _MAC_LPAREN {
          var j = i + 2;
          while j < n && _byte(text, j) != _MAC_RPAREN {
            j = j + 1;
          }
          if j >= n {
            return _err_str("macro: unterminated parameter reference");
          }
          let pname = _trim(string.str_slice(text, i + 2, j));
          let idx = _param_index(fp, pname);
          if idx < 0 {
            return _err_str("macro: unknown parameter: " + pname);
          }
          let av: Str = fa[idx];
          builder.sb_push_str(&mut sb, av);
          i = j + 1;
        } elif _is_digit(d) {
          var j = i + 1;
          var val = 0;
          while j < n && _is_digit(_byte(text, j)) {
            val = val * 10 + (_byte(text, j) - 48);
            j = j + 1;
          }
          if val < 1 || val > fa.len() {
            return _err_str("macro: no such argument: $" + convert.int_to_string(val));
          }
          let av: Str = fa[val - 1];
          builder.sb_push_str(&mut sb, av);
          i = j;
        } elif _is_ident_start(d) {
          var j = i + 1;
          while j < n && _is_ident_char(_byte(text, j)) {
            j = j + 1;
          }
          let mname = string.str_slice(text, i + 1, j);
          var argvec = Vec[Str].new();
          var after = j;
          if j < n && _byte(text, j) == _MAC_LPAREN {
            let close = _find_close(text, j, n);
            if close < 0 {
              return _err_str("macro: unterminated call: " + mname);
            }
            argvec = _split_args(text, j + 1, close);
            after = close + 1;
          }
          let idx = _table_find(names, mname);
          if idx < 0 {
            return _err_str("macro: unknown macro: " + mname);
          }
          let ar: Int = arities[idx];
          if argvec.len() != ar {
            return _err_str("macro: arity mismatch: " + mname + " expects " +
                            convert.int_to_string(ar) + ", got " + convert.int_to_string(argvec.len()));
          }
          if _contains_str(stack, mname) {
            return _err_str("macro: cycle detected: " + mname);
          }
          let depth = stack.len() + 1;
          if depth > max_depth {
            return _err_str("macro: recursion limit exceeded: " + mname);
          }
          trace.push("expand " + mname + "/" + convert.int_to_string(argvec.len()) +
                     " depth=" + convert.int_to_string(depth));
          let penc: Str = params[idx];
          let body: Str = bodies[idx];
          stack.push(mname);
          var eargs = Vec[Str].new();
          var k = 0;
          while k < argvec.len() {
            let a: Str = argvec[k];
            let er = _expand(a, fp, fa, names, arities, params, bodies, stack, trace, max_depth);
            if !er.is_ok {
              return er;
            }
            let ev: Str = er.value;
            eargs.push(ev);
            k = k + 1;
          }
          let br = _expand(body, penc, &eargs, names, arities, params, bodies, stack, trace, max_depth);
          stack.pop();
          if !br.is_ok {
            return br;
          }
          let bv: Str = br.value;
          builder.sb_push_str(&mut sb, bv);
          i = after;
        } else {
          builder.sb_push_byte(&mut sb, _MAC_DOLLAR as UInt8);
          i = i + 1;
        }
      }
    } else {
      builder.sb_push_byte(&mut sb, c as UInt8);
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Line processing
// --------------------------------------------------

// Process one source line [start, end). A directive mutates the table and is
// dropped; a text line is expanded (only when `want_text`) and appended to
// `out` followed by '\n' when `has_newline`. Ok value is unused.
fn _process_line(src: Str, start: Int, end: Int, has_newline: Bool, want_text: Bool,
                 names: &mut Vec[Str], arities: &mut Vec[Int], params: &mut Vec[Str],
                 bodies: &mut Vec[Str], stack: &mut Vec[Str], trace: &mut Vec[Str],
                 max_depth: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  var dend = end;
  if dend > start && _byte(src, dend - 1) == _MAC_CR {
    dend = dend - 1;
  }
  var p = start;
  while p < dend && _byte(src, p) == _MAC_SP {
    p = p + 1;
  }
  let is_define = _match_word(src, p, dend, "define") && (p + 6 >= dend || _byte(src, p + 6) == _MAC_SP);
  let is_undef = _match_word(src, p, dend, "undef") && (p + 5 >= dend || _byte(src, p + 5) == _MAC_SP);
  if is_define {
    var q = p + 6;
    while q < dend && _byte(src, q) == _MAC_SP {
      q = q + 1;
    }
    var e = q;
    while e < dend && _is_ident_char(_byte(src, e)) {
      e = e + 1;
    }
    if e == q || !_is_ident_start(_byte(src, q)) {
      return Err("macro: malformed define directive");
    }
    let mname = string.str_slice(src, q, e);
    var q2 = e;
    var enc = "";
    if e < dend && _byte(src, e) == _MAC_LPAREN {
      let close = _find_close(src, e, dend);
      if close < 0 {
        return Err("macro: malformed define directive");
      }
      let region = string.str_slice(src, e + 1, close);
      let encr = _encode_params(region);
      if !encr.is_ok {
        return Err(encr.error);
      }
      let ev: Str = encr.value;
      enc = ev;
      q2 = close + 1;
    }
    if q2 >= dend || _byte(src, q2) != _MAC_SP {
      return Err("macro: malformed define directive");
    }
    var b = q2;
    while b < dend && _byte(src, b) == _MAC_SP {
      b = b + 1;
    }
    let body = string.str_slice(src, b, dend);
    let arity = _count_commas(enc);
    if _table_find(names, mname) >= 0 {
      trace.push("redefine " + mname + "/" + convert.int_to_string(arity));
    } else {
      trace.push("define " + mname + "/" + convert.int_to_string(arity));
    }
    _table_put(names, arities, params, bodies, mname, arity, enc, body);
    return Ok(0);
  }
  if is_undef {
    var q = p + 5;
    while q < dend && _byte(src, q) == _MAC_SP {
      q = q + 1;
    }
    var e = q;
    while e < dend && _is_ident_char(_byte(src, e)) {
      e = e + 1;
    }
    if e == q || !_is_ident_start(_byte(src, q)) {
      return Err("macro: malformed undef directive");
    }
    let mname = string.str_slice(src, q, e);
    var k = e;
    while k < dend && _byte(src, k) == _MAC_SP {
      k = k + 1;
    }
    if k != dend {
      return Err("macro: malformed undef directive");
    }
    if _table_remove(names, arities, params, bodies, mname) {
      trace.push("undef " + mname);
    } else {
      trace.push("undef-missing " + mname);
    }
    return Ok(0);
  }
  if !want_text {
    return Ok(0);
  }
  let line = string.str_slice(src, start, end);
  var noargs = Vec[Str].new();
  let r = _expand(line, "", &noargs, names, arities, params, bodies, stack, trace, max_depth);
  if !r.is_ok {
    return Err(r.error);
  }
  let expanded: Str = r.value;
  builder.sb_push_str(out, expanded);
  if has_newline {
    builder.sb_push_byte(out, _MAC_LF as UInt8);
  }
  return Ok(0);
}

// Scan `src` line by line. Directives mutate the table; text lines are
// expanded when `want_text` and appended to `out`.
fn _run_lines(src: Str, want_text: Bool, names: &mut Vec[Str], arities: &mut Vec[Int],
              params: &mut Vec[Str], bodies: &mut Vec[Str], stack: &mut Vec[Str],
              trace: &mut Vec[Str], max_depth: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  let n = string.str_len(src);
  var i = 0;
  var ls = 0;
  while i < n {
    if _byte(src, i) == _MAC_LF {
      let r = _process_line(src, ls, i, true, want_text, names, arities, params, bodies,
                            stack, trace, max_depth, out);
      if !r.is_ok {
        return r;
      }
      ls = i + 1;
    }
    i = i + 1;
  }
  if ls < n {
    let r = _process_line(src, ls, n, false, want_text, names, arities, params, bodies,
                          stack, trace, max_depth, out);
    if !r.is_ok {
      return r;
    }
  }
  return Ok(0);
}

// Shared driver for the text-producing entry points.
fn _process(src: Str, trace: &mut Vec[Str], max_depth: Int) -> Result[Str, Str] {
  var names = Vec[Str].new();
  var arities = Vec[Int].new();
  var params = Vec[Str].new();
  var bodies = Vec[Str].new();
  var stack = Vec[Str].new();
  var out = builder.sb_new();
  let r = _run_lines(src, true, &mut names, &mut arities, &mut params, &mut bodies,
                     &mut stack, trace, max_depth, &mut out);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Expand a macro program: process its `define`/`undef` directives and
/// substitute every invocation in the remaining text.
/// Params: src - the whole program text (lines separated by '\n').
/// Returns: Ok(the expanded text). Directives and their newlines are removed;
/// text lines are expanded and keep their line endings; `$$` and `\$` emit a
/// literal '$'; `$NAME` / `$NAME(args)` expand NAME with positional (`$1`) and
/// named (`$(p)`) arguments substituted byte-exact and never re-scanned.
/// Error case: the first problem in scan order, one of the precise messages
/// "macro: unknown macro: <name>", "macro: arity mismatch: <name> expects N,
/// got M", "macro: cycle detected: <name>", "macro: recursion limit exceeded:
/// <name>", "macro: unterminated call: <name>", "macro: unterminated
/// parameter reference", "macro: unknown parameter: <name>", "macro: no such
/// argument: $N", "macro: duplicate parameter: <name>", "macro: malformed
/// define directive" or "macro: malformed undef directive".
/// The expansion trace is computed but discarded; use macro_expand_traced.
/// Complexity: O(total bytes) plus O(invocations x table size) for lookups.
pub fn macro_expand(src: Str) -> Result[Str, Str] {
  var trace = Vec[Str].new();
  return _process(src, &mut trace, _MAX_DEPTH);
}

/// Expand `src` like macro_expand and append one record per directive and
/// expansion to `trace` (records are appended, never cleared).
/// Params: src - the program text; trace - the record sink.
/// Returns: Ok(the expanded text), exactly as macro_expand.
/// Trace records (stable, one line each, fields separated by single spaces):
/// "define <name>/<arity>", "redefine <name>/<arity>", "undef <name>",
/// "undef-missing <name>" and "expand <name>/<argc> depth=<d>" where depth
/// starts at 1 for a top-level invocation.
/// Error case: as macro_expand; on Err, records already emitted are kept.
/// Complexity: as macro_expand plus O(records).
pub fn macro_expand_traced(src: Str, trace: &mut Vec[Str]) -> Result[Str, Str] {
  return _process(src, trace, _MAX_DEPTH);
}

/// Expand `src` like macro_expand with an explicit nesting limit.
/// Params: src - the program text; max_depth - the maximum expansion nesting
/// depth (an invocation at depth max_depth is allowed; deeper is an error);
/// trace - the record sink (as macro_expand_traced).
/// Returns: Ok(the expanded text).
/// Error case: Err("macro: bad depth limit: <n>") when max_depth < 1, else the
/// macro_expand catalog, with "macro: recursion limit exceeded: <name>" when
/// the nesting limit is reached.
/// Complexity: as macro_expand_traced.
pub fn macro_expand_with_limit(src: Str, max_depth: Int, trace: &mut Vec[Str]) -> Result[Str, Str] {
  if max_depth < 1 {
    return _err_str("macro: bad depth limit: " + convert.int_to_string(max_depth));
  }
  return _process(src, trace, max_depth);
}

/// List the macros defined by a program without expanding any text.
/// Params: src - the program text.
/// Returns: Ok(the live macro names in definition order). Directives are
/// validated exactly as by macro_expand, but text lines are ignored entirely,
/// so invocation errors are not raised here.
/// Error case: directive errors the same as macro_expand (malformed define,
/// malformed undef, duplicate parameter); no expansion is attempted.
/// Complexity: O(total bytes) plus O(directives x table size).
pub fn macro_names(src: Str) -> Result[Vec[Str], Str] {
  var names = Vec[Str].new();
  var arities = Vec[Int].new();
  var params = Vec[Str].new();
  var bodies = Vec[Str].new();
  var stack = Vec[Str].new();
  var trace = Vec[Str].new();
  var out = builder.sb_new();
  let r = _run_lines(src, false, &mut names, &mut arities, &mut params, &mut bodies,
                     &mut stack, &mut trace, _MAX_DEPTH, &mut out);
  if !r.is_ok {
    let m: Str = r.error;
    return _err_str(m);
  }
  return _ok_vec(names);
}
