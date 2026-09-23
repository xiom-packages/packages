// XIOM -- xiom.template: Mustache-style {{name}} template rendering
// Port task: replace the xiom.template placeholder with a real, tested,
// documented, pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (full grammar, semantics and error catalog in SPEC.md):
//   * "{{name}}" substitutes a value looked up by name in the parallel
//     keys/values vectors. When a name is duplicated in `keys`, the first
//     index that also has a value wins.
//   * ASCII spaces directly inside the braces are ignored: "{{ name }}"
//     matches the key "name". The empty name ("{{}}" / "{{  }}") is legal
//     and matches the empty-string key.
//   * "{{! comment }}" removes everything up to the first "}}"; comments are
//     never treated as key references.
//   * "{{{{" emits one literal "{{". A lone "{" or "}}" outside a
//     placeholder is copied verbatim.
//   * Rendering is a single left-to-right pass: substituted values are copied
//     into the output as-is and are never re-scanned, so a value that contains
//     "{{" is emitted literally.
//   * template_render is strict: a missing key or an unterminated "{{" is an
//     Err. template_render_lenient renders missing keys as "" and drops the
//     unterminated tail (the prefix before the "{{" is kept).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[Str, Str] are constructed only in the tiny leaf
//     helpers _ok_str/_err_str (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; output is collected in a xiom.string.builder buffer
//     (one allocation per rendered Str).

module xiom.template

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

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

// --------------------------------------------------
//  Byte constants and low-level helpers
// --------------------------------------------------

const _TPL_LBRACE: Int = 123;  // {
const _TPL_RBRACE: Int = 125;  // }
const _TPL_SPACE: Int = 32;    // space
const _TPL_BANG: Int = 33;     // !

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Index of the first "}}" at or after `start`, or -1 when there is none.
fn _find_close(s: Str, start: Int) -> Int {
  let len = s.len();
  var i = start;
  while i + 1 < len {
    if _byte(s, i) == _TPL_RBRACE && _byte(s, i + 1) == _TPL_RBRACE {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Slice of `s` from `start` to `end` with ASCII spaces trimmed on both sides.
fn _trim_spaces(s: Str, start: Int, end: Int) -> Str {
  var a = start;
  var b = end;
  while a < b && _byte(s, a) == _TPL_SPACE {
    a = a + 1;
  }
  while b > a && _byte(s, b - 1) == _TPL_SPACE {
    b = b - 1;
  }
  return string.str_slice(s, a, b);
}

// True when `items` holds `name`. Comparison uses str_compare, never `==`
// (BUG 17).
fn _contains(items: &Vec[Str], name: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    if compare.str_compare(item, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Index of the first key that matches `name` and also has a parallel value,
// or -1. Keys without a value do not match (the renderer reports them as
// missing); duplicates resolve to the first match.
fn _lookup_index(keys: &Vec[Str], values: &Vec[Str], name: Str) -> Int {
  var lim = keys.len();
  if values.len() < lim {
    lim = values.len();
  }
  var i = 0;
  while i < lim {
    let key: Str = keys[i];
    if compare.str_compare(key, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Rendering
// --------------------------------------------------

// Shared left-to-right renderer. In strict mode a missing key or an
// unterminated "{{" is Err; in lenient mode the key renders empty and the
// unterminated tail (from "{{" to EOF) is dropped.
fn _render(tmpl: Str, keys: &Vec[Str], values: &Vec[Str], strict: Bool) -> Result[Str, Str] {
  var sb = builder.sb_new();
  let len = tmpl.len();
  var i = 0;
  while i < len {
    let b = _byte(tmpl, i);
    if b == _TPL_LBRACE && i + 1 < len && _byte(tmpl, i + 1) == _TPL_LBRACE {
      if i + 3 < len && _byte(tmpl, i + 2) == _TPL_LBRACE && _byte(tmpl, i + 3) == _TPL_LBRACE {
        builder.sb_push_str(&mut sb, "{{");
        i = i + 4;
      } else {
        let close = _find_close(tmpl, i + 2);
        if close < 0 {
          if strict {
            return _err_str("template: unterminated placeholder");
          }
          return _ok_str(builder.sb_to_str(&sb));
        }
        var k = i + 2;
        while k < close && _byte(tmpl, k) == _TPL_SPACE {
          k = k + 1;
        }
        if k < close && _byte(tmpl, k) == _TPL_BANG {
          i = close + 2;
        } else {
          let name = _trim_spaces(tmpl, i + 2, close);
          let idx = _lookup_index(keys, values, name);
          if idx >= 0 {
            let value: Str = values[idx];
            builder.sb_push_str(&mut sb, value);
          } elif strict {
            return _err_str("template: missing key: " + name);
          }
          i = close + 2;
        }
      }
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Render `tmpl`, substituting every "{{name}}" from `keys`/`values`.
/// Params: tmpl - the template text; keys, values - parallel vectors; a key
/// matches only when it also has a value at the same index, and the first
/// match wins for duplicated keys.
/// Returns: Ok(rendered text). "{{name}}", "{{ name }}" and "{{name  }}" all
/// match the key "name"; "{{! ... }}" comments are removed; "{{{{" emits a
/// literal "{{"; substituted values are not re-scanned.
/// Error case: Err("template: missing key: <name>") when a referenced name
/// has no matching key/value; Err("template: unterminated placeholder") when
/// a "{{" has no closing "}}" (including unterminated comments).
/// Complexity: O(n) over the template plus O(placeholders * keys).
pub fn template_render(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str] {
  return _render(tmpl, keys, values, true);
}

/// Render `tmpl` like template_render, but never fail.
/// Params: tmpl - the template text; keys, values - parallel vectors.
/// Returns: the rendered text; a missing key renders as "" and an
/// unterminated "{{" drops the rest of the template (the prefix before the
/// "{{" is kept).
/// Error case: none.
/// Complexity: O(n) over the template plus O(placeholders * keys).
pub fn template_render_lenient(tmpl: Str, keys: &Vec[Str], values: &Vec[Str]) -> Str {
  let r = _render(tmpl, keys, values, false);
  if r.is_ok {
    return r.value;
  }
  return "";
}

// --------------------------------------------------
//  Key inspection
// --------------------------------------------------

// Distinct placeholder names in `tmpl`, first-seen order; comments excluded;
// an unterminated tail contributes nothing.
fn _collect_names(tmpl: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = tmpl.len();
  var i = 0;
  while i < len {
    let b = _byte(tmpl, i);
    if b == _TPL_LBRACE && i + 1 < len && _byte(tmpl, i + 1) == _TPL_LBRACE {
      if i + 3 < len && _byte(tmpl, i + 2) == _TPL_LBRACE && _byte(tmpl, i + 3) == _TPL_LBRACE {
        i = i + 4;
      } else {
        let close = _find_close(tmpl, i + 2);
        if close < 0 {
          return out;
        }
        var k = i + 2;
        while k < close && _byte(tmpl, k) == _TPL_SPACE {
          k = k + 1;
        }
        if k < close && _byte(tmpl, k) == _TPL_BANG {
          i = close + 2;
        } else {
          let name = _trim_spaces(tmpl, i + 2, close);
          if !_contains(&out, name) {
            out.push(name);
          }
          i = close + 2;
        }
      }
    } else {
      i = i + 1;
    }
  }
  return out;
}

/// Distinct key names referenced by `tmpl`, first-seen order.
/// Params: tmpl - the template text.
/// Returns: the referenced names with duplicates removed; "{{! ... }}"
/// comments are excluded; an unterminated "{{" stops the scan (names seen
/// before it are still reported).
/// Error case: none.
/// Complexity: O(n * names).
pub fn template_keys(tmpl: Str) -> Vec[Str] {
  return _collect_names(tmpl);
}

/// Names referenced by `tmpl` that are absent from `keys`.
/// Params: tmpl - the template text; keys - the available key names.
/// Returns: referenced-but-absent names in first-seen order, deduplicated;
/// only `keys` is consulted (a key without a parallel value is not flagged
/// here but is reported missing by template_render).
/// Error case: none.
/// Complexity: O(n * names * keys).
pub fn template_needs_keys(tmpl: Str, keys: &Vec[Str]) -> Vec[Str] {
  let referenced = _collect_names(tmpl);
  var out = Vec[Str].new();
  var i = 0;
  while i < referenced.len() {
    let name: Str = referenced[i];
    if !_contains(keys, name) {
      out.push(name);
    }
    i = i + 1;
  }
  return out;
}
