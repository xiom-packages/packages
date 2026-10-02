// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.helm.tmpl: bounded Go-template-ish manifest renderer
// Port task: pure-XIOM renderer for the documented template subset:
// plain text, {{ .Values.a.b }}, {{ .Release.Name }}, {{ if }}/{{ else }}/{{ end }}.
// One deterministic left-to-right pass with an explicit if-clause stack; no
// token vectors, no recursion, no lambdas. See SPEC.md section 7 for the
// grammar, truthiness rule and error catalog. No Kubernetes API, no I/O.

module xiom.helm.tmpl

use xiom.string;
use xiom.convert;
use xiom.helm.base;

// --------------------------------------------------
//  Limits and byte constants
// --------------------------------------------------

/// Maximum accepted template text length, in bytes.
pub const TMPL_MAX_INPUT: Int = 65536;
/// Maximum nesting depth of {{ if }} clauses.
pub const TMPL_MAX_DEPTH: Int = 32;

const _LBRACE: Int = 123;
const _RBRACE: Int = 125;
const _DOT: Int = 46;
const _SPACE: Int = 32;
const _TAB: Int = 9;
const _DASH: Int = 45;
const _USCORE: Int = 95;
const _SLASH: Int = 47;
const _DIGIT0: Int = 48;
const _DIGIT9: Int = 57;
const _UPPER_A: Int = 65;
const _UPPER_Z: Int = 90;
const _LOWER_A: Int = 97;
const _LOWER_Z: Int = 122;

// --------------------------------------------------
//  Render context
// --------------------------------------------------

/// Everything a template can see. `vkeys`/`vvals` are index-aligned copies of
/// a Values map (flat dotted paths, as returned by values_entries); the
/// remaining fields expose the release and chart context. Build with
/// tmpl_context_new / tmpl_context_basic or assign fields directly.
pub type RenderContext = {
  vkeys: Vec[Str];
  vvals: Vec[Str];
  release_name: Str;
  release_namespace: Str;
  release_revision: Int;
  chart_api_version: Str;
  chart_name: Str;
  chart_version: Str;
  chart_app_version: Str;
  chart_description: Str;
}

fn _str_ok(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

fn _str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

/// A default context: no values, release name "", namespace "default",
/// revision 1, all chart fields "".
pub fn tmpl_context_new() -> RenderContext {
  return RenderContext{
    vkeys: Vec[Str].new();
    vvals: Vec[Str].new();
    release_name: "";
    release_namespace: "default";
    release_revision: 1;
    chart_api_version: "";
    chart_name: "";
    chart_version: "";
    chart_app_version: "";
    chart_description: "";
  };
}

/// A context with the given flat values columns and release name; all other
/// fields keep the tmpl_context_new defaults. The vectors are copied.
pub fn tmpl_context_basic(vkeys: &Vec[Str], vvals: &Vec[Str], release_name: Str) -> RenderContext {
  var ks = Vec[Str].new();
  var vs = Vec[Str].new();
  let n = vkeys.len();
  var i = 0;
  while i < n {
    let k: Str = vkeys[i];
    var x = "";
    if i < vvals.len() {
      x = vvals[i];
    }
    ks.push(k);
    vs.push(x);
    i = i + 1;
  }
  return RenderContext{
    vkeys: ks;
    vvals: vs;
    release_name: release_name;
    release_namespace: "default";
    release_revision: 1;
    chart_api_version: "";
    chart_name: "";
    chart_version: "";
    chart_app_version: "";
    chart_description: "";
  };
}

// --------------------------------------------------
//  Private helpers
// --------------------------------------------------

fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _is_path_char(c: Int) -> Bool {
  if c >= _DIGIT0 && c <= _DIGIT9 {
    return true;
  }
  if c >= _UPPER_A && c <= _UPPER_Z {
    return true;
  }
  if c >= _LOWER_A && c <= _LOWER_Z {
    return true;
  }
  return c == _USCORE || c == _DASH || c == _SLASH;
}

// Template path rule: 1..256 bytes, 1..64 dot-separated non-empty segments of
// ASCII letters, digits, '_', '-' or '/'.
fn _path_ok(path: Str) -> Bool {
  let n = string.str_len(path);
  if n == 0 || n > 256 {
    return false;
  }
  let segs = string.str_split(path, ".");
  let sc = segs.len();
  if sc == 0 || sc > 64 {
    return false;
  }
  var i = 0;
  while i < sc {
    let seg: Str = segs[i];
    let sn = string.str_len(seg);
    if sn == 0 {
      return false;
    }
    var j = 0;
    while j < sn {
      if !_is_path_char(_byte(seg, j)) {
        return false;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

// First '.' in `path`, or -1.
fn _find_dot(path: Str) -> Int {
  var i = 0;
  let n = string.str_len(path);
  while i < n {
    if _byte(path, i) == _DOT {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when an action is `if` followed by whitespace (not the bare "if").
fn _starts_if(content: Str) -> Bool {
  let n = string.str_len(content);
  if n < 3 {
    return false;
  }
  if _byte(content, 0) != 105 || _byte(content, 1) != 102 {
    return false;
  }
  let c = _byte(content, 2);
  return c == _SPACE || c == _TAB;
}

// Context lookup for the flat Values copy in the context.
fn _ctx_get(ctx: &RenderContext, path: Str) -> Option[Str] {
  var n = ctx.vkeys.len();
  if ctx.vvals.len() < n {
    n = ctx.vvals.len();
  }
  var i = 0;
  while i < n {
    let k: Str = ctx.vkeys[i];
    if base.helm_streq(k, path) {
      let x: Str = ctx.vvals[i];
      return Some(x);
    }
    i = i + 1;
  }
  return None;
}

// Truthiness of a resolved scalar: false for "", "false" and "0", true for
// every other text. Returns 1/0 so it can be stored in Vec[Int].
fn _truthy(s: Str) -> Int {
  if string.str_len(s) == 0 {
    return 0;
  }
  if base.helm_streq(s, "false") {
    return 0;
  }
  if base.helm_streq(s, "0") {
    return 0;
  }
  return 1;
}

// Resolve a context path without the leading '.'. Unknown roots and unknown
// non-Values fields are errors; a missing Values path renders as "".
fn _resolve(ctx: &RenderContext, path: Str) -> Result[Str, Str] {
  let dot = _find_dot(path);
  var root = path;
  var rest = "";
  if dot >= 0 {
    root = string.str_slice(path, 0, dot);
    rest = string.str_slice(path, dot + 1, string.str_len(path));
  }
  if base.helm_streq(root, "Values") {
    if string.str_len(rest) == 0 {
      return _str_ok("");
    }
    let o = _ctx_get(ctx, rest);
    match o {
      Some(v) => { return _str_ok(v); },
      None => { return _str_ok(""); },
    }
    return _str_ok("");
  }
  if base.helm_streq(root, "Release") {
    if base.helm_streq(rest, "Name") {
      return _str_ok(ctx.release_name);
    }
    if base.helm_streq(rest, "Namespace") {
      return _str_ok(ctx.release_namespace);
    }
    if base.helm_streq(rest, "Revision") {
      return _str_ok(convert.int_to_string(ctx.release_revision));
    }
    if base.helm_streq(rest, "Service") {
      return _str_ok("Helm");
    }
    if base.helm_streq(rest, "IsInstall") {
      if ctx.release_revision == 1 {
        return _str_ok("true");
      }
      return _str_ok("false");
    }
    if base.helm_streq(rest, "IsUpgrade") {
      if ctx.release_revision == 1 {
        return _str_ok("false");
      }
      return _str_ok("true");
    }
    return _str_err("tmpl: unknown context path: " + path);
  }
  if base.helm_streq(root, "Chart") {
    if base.helm_streq(rest, "ApiVersion") {
      return _str_ok(ctx.chart_api_version);
    }
    if base.helm_streq(rest, "Name") {
      return _str_ok(ctx.chart_name);
    }
    if base.helm_streq(rest, "Version") {
      return _str_ok(ctx.chart_version);
    }
    if base.helm_streq(rest, "AppVersion") {
      return _str_ok(ctx.chart_app_version);
    }
    if base.helm_streq(rest, "Description") {
      return _str_ok(ctx.chart_description);
    }
    return _str_err("tmpl: unknown context path: " + path);
  }
  return _str_err("tmpl: unknown context path: " + path);
}

// --------------------------------------------------
//  Rendering
// --------------------------------------------------

/// Render the documented template subset against `ctx`. One deterministic
/// left-to-right pass: text is copied verbatim, {{ .Path }} emits the resolved
/// scalar, {{ if .Path }}...{{ else }}...{{ end }} gates emission on
/// truthiness. Missing Values paths emit ""; unknown Release/Chart fields and
/// malformed syntax are Err. Suppressed branches are neither resolved nor
/// emitted (unknown paths inside them cannot fail). Cap: TMPL_MAX_DEPTH
/// nested ifs.
pub fn tmpl_render(text: Str, ctx: &RenderContext) -> Result[Str, Str] {
  if base.helm_has_nul(text) {
    return _str_err("tmpl: NUL byte in input");
  }
  let total = string.str_len(text);
  if total > TMPL_MAX_INPUT {
    return _str_err("tmpl: input too large");
  }
  var out = "";
  var emit = 1;
  var sk_cond = Vec[Int].new();
  var sk_saved = Vec[Int].new();
  var i = 0;
  var start = 0;
  while i < total {
    let c = _byte(text, i);
    if c == _LBRACE && i + 1 < total && _byte(text, i + 1) == _LBRACE {
      if emit == 1 && i > start {
        out = out + string.str_slice(text, start, i);
      }
      var j = i + 2;
      var close = -1;
      while j < total {
        if _byte(text, j) == _RBRACE && j + 1 < total && _byte(text, j + 1) == _RBRACE {
          close = j;
          break;
        }
        j = j + 1;
      }
      if close < 0 {
        return _str_err("tmpl: unterminated action at offset " + convert.int_to_string(i));
      }
      let content = string.str_trim(string.str_slice(text, i + 2, close));
      if string.str_len(content) == 0 {
        return _str_err("tmpl: empty action at offset " + convert.int_to_string(i));
      }
      if base.helm_streq(content, "if") {
        return _str_err("tmpl: if requires a path");
      }
      if _starts_if(content) {
        let rest = string.str_trim(string.str_slice(content, 2, string.str_len(content)));
        if string.str_len(rest) == 0 || _byte(rest, 0) != _DOT {
          return _str_err("tmpl: if requires a path starting with '.': " + content);
        }
        let path = string.str_slice(rest, 1, string.str_len(rest));
        if !_path_ok(path) {
          return _str_err("tmpl: malformed path: " + rest);
        }
        let rr = _resolve(ctx, path);
        var cond = 0;
        match rr {
          Ok(v) => { cond = _truthy(v); },
          Err(e) => { return _str_err(e); },
        }
        let saved = emit;
        if emit != 1 || cond != 1 {
          emit = 0;
        }
        sk_cond.push(cond);
        sk_saved.push(saved);
        if sk_cond.len() > TMPL_MAX_DEPTH {
          return _str_err("tmpl: if nesting limit exceeded");
        }
      } elif base.helm_streq(content, "else") {
        if sk_cond.len() == 0 {
          return _str_err("tmpl: unexpected else");
        }
        let cond: Int = sk_cond[sk_cond.len() - 1];
        let saved: Int = sk_saved[sk_saved.len() - 1];
        if cond == 1 {
          emit = 0;
        } else {
          emit = saved;
        }
      } elif base.helm_streq(content, "end") {
        if sk_cond.len() == 0 {
          return _str_err("tmpl: unexpected end");
        }
        let saved: Int = sk_saved[sk_saved.len() - 1];
        let _ = sk_cond.pop();
        let _ = sk_saved.pop();
        emit = saved;
      } elif _byte(content, 0) == _DOT {
        let path = string.str_slice(content, 1, string.str_len(content));
        if !_path_ok(path) {
          return _str_err("tmpl: malformed path: " + content);
        }
        if emit == 1 {
          let rr = _resolve(ctx, path);
          match rr {
            Ok(v) => { out = out + v; },
            Err(e) => { return _str_err(e); },
          }
        }
      } else {
        return _str_err("tmpl: unexpected action: " + content);
      }
      i = close + 2;
      start = i;
    } else {
      i = i + 1;
    }
  }
  if emit == 1 && start < total {
    out = out + string.str_slice(text, start, total);
  }
  if sk_cond.len() > 0 {
    return _str_err("tmpl: unclosed if");
  }
  return _str_ok(out);
}

/// Convenience: render with a minimal context built from flat values columns
/// (as returned by values_entries) and a release name.
pub fn tmpl_render_values(text: Str, vkeys: &Vec[Str], vvals: &Vec[Str], release_name: Str) -> Result[Str, Str] {
  let ctx = tmpl_context_basic(vkeys, vvals, release_name);
  return tmpl_render(text, &ctx);
}
