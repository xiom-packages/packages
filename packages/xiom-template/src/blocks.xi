// XIOM -- xiom.template.blocks: Mustache-style block rendering with
// {{#section}} / {{^inverted}} / {{/close}}, dotted paths, a context stack
// and optional HTML auto-escaping, over a conservative flat data model.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Companion module: xiom.template (src/template.xi) keeps the v0.1.x
// placeholder-only surface (template_render / template_render_lenient /
// template_keys / template_needs_keys); this module adds the v0.2.0 block
// surface without changing any existing signature.
//
// Data model (SPEC.md section 10; deliberately non-recursive):
//   TemplateData is a flat, ordered vector of TemplateEntry records. An
//   entry value is exactly one of Str / Bool / Str-list (TEMPLATE_VALUE_*).
//   Dotted names ("user.address.city") are plain entry names: a name that
//   has no exact entry but has dotted children acts as a context group.
//   The compiler probe for this shape (flat order, no recursion, no
//   struct-with-self) is recorded in SPEC.md section 14.
//
// Grammar and semantics (full table in SPEC.md section 11):
//   * "{{name}}"     interpolates (HTML-escaped when escape_html is true)
//   * "{{{name}}}"   interpolates raw; "{{&name}}" is the same
//   * "{{! ... }}"   comment, removed entirely
//   * "{{#key}}...{{/key}}"    section: iterate a Str list ({{.}} is the
//     item; other names resolve against the PARENT context), render once
//     for a truthy Bool or non-empty Str, or render once for a dotted
//     group; push the resolved name as a context prefix
//   * "{{^key}}...{{/key}}"    inverted: render once when falsy/empty/
//     missing, skip when truthy; never pushes a context prefix
//   * "{{{{"         emits one literal "{{"
//   * lookups try the innermost context prefix first, then each ancestor,
//     then the root; dotted paths resolve against the same chain
//
// Error catalog (strict mode; byte offsets are 0-based template offsets;
// full table in SPEC.md section 12):
//   * "template: unclosed interpolation at byte <off>"
//   * "template: unknown key: <name> at byte <off>"
//   * "template: unterminated section '<name>' at byte <off>"
//   * "template: mismatched close '<name>' at byte <off>" (with
//     " (expected '<open>')" when a section is open)
//   * "template: nesting exceeds 64 at byte <off>"
//   * "template: output exceeds 8388608 bytes at byte <off>"
//   The lenient twin never fails (SPEC.md section 13).
//
// Compiler idioms (proven on v0.64.5 by the probes recorded in SPEC.md
// section 14, and carried over from xiom.template):
//   * Ok/Err for Result[Str, Str] are constructed only in the leaf helpers
//     _ok_str / _err_str.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); `Vec.pop()` returns Option, so frames are mutated by
//     whole-element assignment instead of pop-modify-push.
//   * Bytes are read through a cached raw pointer (Str.c_str() + unsafe
//     deref, the xiom.string.builder idiom): string.byte_at re-scans the
//     string per call and its runtime clamps reads at 1 MiB, so it is
//     quadratic on large templates and wrong past 1 MiB. The output is
//     collected in one xiom.string.builder buffer; error offsets are
//     formatted with builder.sb_push_int (no Int-to-Str dependency).

module xiom.template.blocks

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// TemplateEntry.kind values.
pub const TEMPLATE_VALUE_STR: Int = 0;
pub const TEMPLATE_VALUE_BOOL: Int = 1;
pub const TEMPLATE_VALUE_LIST: Int = 2;

// Hard caps. TEMPLATE_MAX_DEPTH: section nesting beyond this is a strict
// Err / a suppressed section in lenient mode. TEMPLATE_MAX_OUTPUT: the
// rendered output never exceeds this many bytes (the cap is checked before
// every append, so a strict render can never exceed it and the lenient
// twin truncates at it).
pub const TEMPLATE_MAX_DEPTH: Int = 64;
pub const TEMPLATE_MAX_OUTPUT: Int = 8388608;

// --------------------------------------------------
//  Internal constants
// --------------------------------------------------

// _Frame.mode values.
const _MODE_ONCE: Int = 0;      // truthy Str/Bool/group: render body once
const _MODE_LIST: Int = 1;      // Str list: iterate the body per item
const _MODE_INVERTED: Int = 2;  // render body once, no prefix pushed
const _MODE_SKIP: Int = 3;      // falsy/unknown: consume the body silently

// Byte constants.
const _B_BANG: Int = 33;     // !
const _B_DQUOTE: Int = 34;   // "
const _B_HASH: Int = 35;     // #
const _B_AMP: Int = 38;      // &
const _B_SQUOTE: Int = 39;   // '
const _B_DOT: Int = 46;      // .
const _B_SLASH: Int = 47;    // /
const _B_SPACE: Int = 32;    // (ASCII space)
const _B_LT: Int = 60;       // <
const _B_GT: Int = 62;       // >
const _B_CARET: Int = 94;    // ^
const _B_LBRACE: Int = 123;  // {
const _B_RBRACE: Int = 125;  // }

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One ordered data entry: `name` is the lookup name (plain or dotted,
/// e.g. "user.address.city"); `kind` is TEMPLATE_VALUE_STR / _BOOL / _LIST;
/// `text` is the Str value, `flag` the Bool value and `items` the Str-list
/// value of the respective kinds (unused fields stay empty/false).
pub type TemplateEntry = {
  name: Str;
  kind: Int;
  text: Str;
  flag: Bool;
  items: Vec[Str];
}

/// The flat, ordered template data: a vector of entries. There is no
/// nesting and no recursion; dotted names express structure and a name
/// with dotted children but no entry of its own is a context group.
pub type TemplateData = {
  entries: Vec[TemplateEntry];
}

// One open section frame (the renderer's context stack).
type _Frame = {
  tag_name: Str;      // raw name from the opening tag (close-tag matching)
  entry: Int;         // data entry index for _MODE_LIST, else -1
  mode: Int;          // _MODE_*
  item: Int;          // current list item index for _MODE_LIST, else -1
  body_start: Int;    // template offset just after the opening tag
  open_offset: Int;   // template offset of the opening "{{" (errors)
  prefix: Str;        // context prefix pushed by this frame ("" when none)
}

// Section evaluation outcome (see _eval_section).
type _Section = {
  known: Bool;   // the key resolves (entry or group); dot: inside a list
  act: Int;      // 0 = skip body, 1 = render once, 2 = iterate the list
  entry: Int;    // data entry index when act == 2, else -1
  prefix: Str;   // context prefix to push when act == 1
}

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
//  Byte and string helpers
// --------------------------------------------------

// Raw byte at `i` over a cached string pointer (the same idiomatic unsafe
// read xiom.string.builder uses). string.byte_at re-scans the whole string
// per call (runtime strnlen) and clamps reads at 1 MiB (xiom_runtime.c:
// strnlen(str, 1 << 20)), so it is quadratic on large templates and wrong
// past 1 MiB; the raw read is O(1) and exact for any size. Callers bound
// `i` against the cached length.
fn _raw_byte(base: *UInt8, i: Int) -> UInt8
  requires: true  // raw byte read; callers bound i against the cached len (T007)
{
  unsafe { return *(base + i); }
}

// Byte value at `i` (0..255) over a cached pointer (callers bound i).
fn _byte(base: *UInt8, i: Int) -> Int {
  return (_raw_byte(base, i) as Int) & 0xFF;
}

// True when `a` and `b` are byte-equal (str_compare, never `==`; BUG 17).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Index of the first "}}" at or after `start`, or -1 when there is none.
fn _find_close(s: Str, start: Int) -> Int {
  let len = s.len();
  let base = s.c_str();
  var i = start;
  while i + 1 < len {
    if _byte(base, i) == _B_RBRACE && _byte(base, i + 1) == _B_RBRACE {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first "}}}" at or after `start`, or -1 when there is none.
fn _find_close3(s: Str, start: Int) -> Int {
  let len = s.len();
  let base = s.c_str();
  var i = start;
  while i + 2 < len {
    if _byte(base, i) == _B_RBRACE && _byte(base, i + 1) == _B_RBRACE && _byte(base, i + 2) == _B_RBRACE {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Slice of `s` from `start` to `end` with ASCII spaces trimmed on both sides.
fn _trim_spaces(s: Str, start: Int, end: Int) -> Str {
  let base = s.c_str();
  var a = start;
  var b = end;
  while a < b && _byte(base, a) == _B_SPACE {
    a = a + 1;
  }
  while b > a && _byte(base, b - 1) == _B_SPACE {
    b = b - 1;
  }
  return string.str_slice(s, a, b);
}

// Dotted-path join: "" + name is name, otherwise prefix + "." + name.
fn _join(prefix: Str, name: Str) -> Str {
  if prefix.len() == 0 {
    return name;
  }
  return prefix + "." + name;
}

// --------------------------------------------------
//  Data model builders and accessors
// --------------------------------------------------

/// Create an empty TemplateData.
/// Params: none.
/// Returns: an empty data set (no entries).
/// Error case: none.
/// Complexity: O(1).
pub fn template_data_new() -> TemplateData {
  return TemplateData { entries: Vec[TemplateEntry].new() };
}

// Index of the entry named exactly `name`, or -1.
fn _find_entry(data: &TemplateData, name: Str) -> Int {
  var i = 0;
  while i < data.entries.len() {
    let e = data.entries[i];
    if _streq(e.name, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when some entry name is a dotted child of `full` ("full.child...").
// The empty name has no children (full.len() == 0 => false).
fn _group_exists(data: &TemplateData, full: Str) -> Bool {
  if full.len() == 0 {
    return false;
  }
  var i = 0;
  while i < data.entries.len() {
    let e = data.entries[i];
    let n = e.name;
    if n.len() > full.len() {
      let nb = n.c_str();
      let fb = full.c_str();
      var k = 0;
      var hit = true;
      while k < full.len() {
        if _byte(nb, k) != _byte(fb, k) {
          hit = false;
        }
        k = k + 1;
      }
      if hit && _byte(nb, full.len()) == _B_DOT {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

// Fresh Str entry.
fn _entry_str(name: Str, value: Str) -> TemplateEntry {
  return TemplateEntry { name: name, kind: TEMPLATE_VALUE_STR, text: value, flag: false, items: Vec[Str].new() };
}

// Fresh Bool entry.
fn _entry_bool(name: Str, value: Bool) -> TemplateEntry {
  return TemplateEntry { name: name, kind: TEMPLATE_VALUE_BOOL, text: "", flag: value, items: Vec[Str].new() };
}

// Fresh list entry: the items are copied so the caller keeps ownership.
fn _entry_list(name: Str, items: &Vec[Str]) -> TemplateEntry {
  var copy = Vec[Str].new();
  var i = 0;
  while i < items.len() {
    let it: Str = items[i];
    copy.push(it);
    i = i + 1;
  }
  return TemplateEntry { name: name, kind: TEMPLATE_VALUE_LIST, text: "", flag: false, items: copy };
}

/// Set a Str value under `name`. An existing entry is replaced in place
/// (its position in the ordered data is kept); otherwise the entry is
/// appended.
/// Params: d - the data set; name - the lookup name (plain or dotted);
/// value - the Str value.
/// Error case: none.
/// Complexity: O(|entries|).
pub fn template_data_set_str(d: &mut TemplateData, name: Str, value: Str) {
  let idx = _find_entry(d, name);
  if idx >= 0 {
    d.entries[idx] = _entry_str(name, value);
    return;
  }
  d.entries.push(_entry_str(name, value));
}

/// Set a Bool value under `name` (replace in place, else append).
/// Params: d - the data set; name - the lookup name; value - the flag.
/// Error case: none.
/// Complexity: O(|entries|).
pub fn template_data_set_bool(d: &mut TemplateData, name: Str, value: Bool) {
  let idx = _find_entry(d, name);
  if idx >= 0 {
    d.entries[idx] = _entry_bool(name, value);
    return;
  }
  d.entries.push(_entry_bool(name, value));
}

/// Set a Str-list value under `name` (replace in place, else append).
/// The items are copied into the data set.
/// Params: d - the data set; name - the lookup name; items - the items.
/// Error case: none.
/// Complexity: O(|entries| + |items|).
pub fn template_data_set_list(d: &mut TemplateData, name: Str, items: &Vec[Str]) {
  let idx = _find_entry(d, name);
  if idx >= 0 {
    d.entries[idx] = _entry_list(name, items);
    return;
  }
  d.entries.push(_entry_list(name, items));
}

/// Number of entries in `d`.
/// Params: d - the data set.
/// Returns: the entry count.
/// Error case: none.
/// Complexity: O(1).
pub fn template_data_len(d: &TemplateData) -> Int {
  return d.entries.len();
}

/// True when an entry named exactly `name` exists (groups excluded).
/// Params: d - the data set; name - the lookup name.
/// Error case: none.
/// Complexity: O(|entries|).
pub fn template_data_has(d: &TemplateData, name: Str) -> Bool {
  return _find_entry(d, name) >= 0;
}

/// Kind of the entry named exactly `name`.
/// Params: d - the data set; name - the lookup name.
/// Returns: TEMPLATE_VALUE_STR / _BOOL / _LIST, or -1 when absent.
/// Error case: none.
/// Complexity: O(|entries|).
pub fn template_data_kind(d: &TemplateData, name: Str) -> Int {
  let ei = _find_entry(d, name);
  if ei < 0 {
    return -1;
  }
  let e = d.entries[ei];
  return e.kind;
}

// --------------------------------------------------
//  Context-stack helpers
// --------------------------------------------------

// Mode of the innermost open frame (callers guarantee a non-empty stack).
fn _top_mode(stack: &Vec[_Frame]) -> Int {
  let f = stack[stack.len() - 1];
  return f.mode;
}

// Context prefix of the innermost open frame ("" when the stack is empty).
fn _current_prefix(stack: &Vec[_Frame]) -> Str {
  if stack.len() == 0 {
    return "";
  }
  let f = stack[stack.len() - 1];
  return f.prefix;
}

// Inside a suppressed region: beyond the depth cap (over > 0) or inside a
// skipped section (_MODE_SKIP). Suppressed regions emit and evaluate nothing.
fn _suppressed(stack: &Vec[_Frame], over: Int) -> Bool {
  if over > 0 {
    return true;
  }
  if stack.len() == 0 {
    return false;
  }
  return _top_mode(stack) == _MODE_SKIP;
}

// Push one section frame.
fn _push(stack: &mut Vec[_Frame], tag_name: Str, entry: Int, mode: Int, item: Int, body_start: Int, open_offset: Int, prefix: Str) {
  stack.push(_Frame { tag_name: tag_name, entry: entry, mode: mode, item: item, body_start: body_start, open_offset: open_offset, prefix: prefix });
}

// Advance the innermost list frame to the next item (whole-element
// assignment: Vec.pop() returns Option and is not used for mutation).
fn _advance_list(stack: &mut Vec[_Frame], next_item: Int) {
  let top = stack[stack.len() - 1];
  stack[stack.len() - 1] = _Frame {
    tag_name: top.tag_name,
    entry: top.entry,
    mode: top.mode,
    item: next_item,
    body_start: top.body_start,
    open_offset: top.open_offset,
    prefix: top.prefix
  };
}

// True when some open frame is a list iteration ({{.}} has a value).
fn _has_dot(stack: &Vec[_Frame]) -> Bool {
  var i = stack.len();
  while i > 0 {
    i = i - 1;
    let f = stack[i];
    if f.mode == _MODE_LIST {
      return true;
    }
  }
  return false;
}

// The innermost list item ("" when no list frame is open).
fn _resolve_dot(data: &TemplateData, stack: &Vec[_Frame]) -> Str {
  var i = stack.len();
  while i > 0 {
    i = i - 1;
    let f = stack[i];
    if f.mode == _MODE_LIST {
      let e = data.entries[f.entry];
      return e.items[f.item];
    }
  }
  return "";
}

// Item count of the list entry `ei`.
fn _list_len(data: &TemplateData, ei: Int) -> Int {
  let e = data.entries[ei];
  return e.items.len();
}

// --------------------------------------------------
//  Name resolution (context stack, dotted paths)
// --------------------------------------------------

// Resolve `name` against the context stack (innermost prefix first, then
// each ancestor frame, then the root) and return the full name of the
// first candidate that is an entry or a dotted group; "" when nothing
// matches. A resolved candidate is "" only for the empty name.
fn _resolve_full(data: &TemplateData, stack: &Vec[_Frame], name: Str) -> Str {
  var i = stack.len();
  while i > 0 {
    i = i - 1;
    let f = stack[i];
    let cand = _join(f.prefix, name);
    if _find_entry(data, cand) >= 0 || _group_exists(data, cand) {
      return cand;
    }
  }
  if _find_entry(data, name) >= 0 || _group_exists(data, name) {
    return name;
  }
  return "";
}

// True when `name` resolves. The only resolution that yields the sentinel
// "" is the empty name (an entry literally named ""), handled here.
fn _resolve_known(data: &TemplateData, stack: &Vec[_Frame], name: Str) -> Bool {
  if _resolve_full(data, stack, name).len() > 0 {
    return true;
  }
  return name.len() == 0 && _find_entry(data, "") >= 0;
}

// Evaluate a "{{#key}}" / "{{^key}}" tag: known/act/entry/prefix (see
// _Section). "." evaluates the innermost list item (truthy = non-empty).
fn _eval_section(data: &TemplateData, stack: &Vec[_Frame], name: Str) -> _Section {
  var out = _Section { known: false, act: 0, entry: -1, prefix: "" };
  if _streq(name, ".") {
    out.known = _has_dot(stack);
    if out.known && _resolve_dot(data, stack).len() > 0 {
      out.act = 1;
    }
    out.prefix = _current_prefix(stack);
    return out;
  }
  let rn = _resolve_full(data, stack, name);
  out.known = _resolve_known(data, stack, name);
  if !out.known {
    return out;
  }
  let ei = _find_entry(data, rn);
  if ei < 0 {
    // Dotted group: truthy once, pushing the group name as the prefix.
    out.act = 1;
    out.prefix = rn;
    return out;
  }
  let e = data.entries[ei];
  if e.kind == TEMPLATE_VALUE_LIST {
    if e.items.len() > 0 {
      out.act = 2;
      out.entry = ei;
    }
  } elif e.kind == TEMPLATE_VALUE_BOOL {
    if e.flag {
      out.act = 1;
      out.prefix = rn;
    }
  } else {
    if e.text.len() > 0 {
      out.act = 1;
      out.prefix = rn;
    }
  }
  return out;
}

// True when the interpolation `name` resolves ("." included).
fn _interp_known(data: &TemplateData, stack: &Vec[_Frame], name: Str) -> Bool {
  if _streq(name, ".") {
    return _has_dot(stack);
  }
  return _resolve_known(data, stack, name);
}

// The interpolation value of `name`. Only TEMPLATE_VALUE_STR entries carry
// text; Bool, list and group interpolations render "" (sections are the
// way to consume those). "." returns the innermost list item.
fn _interp_value(data: &TemplateData, stack: &Vec[_Frame], name: Str) -> Str {
  if _streq(name, ".") {
    return _resolve_dot(data, stack);
  }
  let rn = _resolve_full(data, stack, name);
  let ei = _find_entry(data, rn);
  if ei < 0 {
    return "";
  }
  let e = data.entries[ei];
  if e.kind == TEMPLATE_VALUE_STR {
    return e.text;
  }
  return "";
}

// --------------------------------------------------
//  HTML escaping (auto-escape mode)
// --------------------------------------------------

// Number of output bytes `value` occupies when escaped (identity when not).
fn _value_len(value: Str, escape: Bool) -> Int {
  if !escape {
    return value.len();
  }
  var n = value.len();
  let base = value.c_str();
  var k = 0;
  while k < value.len() {
    let b = _byte(base, k);
    if b == _B_AMP {
      n = n + 4;       // & -> &amp;
    } elif b == _B_LT {
      n = n + 3;       // < -> &lt;
    } elif b == _B_GT {
      n = n + 3;       // > -> &gt;
    } elif b == _B_DQUOTE {
      n = n + 5;       // " -> &quot;
    } elif b == _B_SQUOTE {
      n = n + 4;       // ' -> &#39;
    }
    k = k + 1;
  }
  return n;
}

// Append `value`, escaping &, <, >, ", ' when `escape` is set; every other
// byte (including all multi-byte UTF-8) is copied verbatim.
fn _push_value(sb: &mut Vec[UInt8], value: Str, escape: Bool) {
  if !escape {
    builder.sb_push_str(sb, value);
    return;
  }
  let base = value.c_str();
  var k = 0;
  while k < value.len() {
    let b = _byte(base, k);
    if b == _B_AMP {
      builder.sb_push_str(sb, "&amp;");
    } elif b == _B_LT {
      builder.sb_push_str(sb, "&lt;");
    } elif b == _B_GT {
      builder.sb_push_str(sb, "&gt;");
    } elif b == _B_DQUOTE {
      builder.sb_push_str(sb, "&quot;");
    } elif b == _B_SQUOTE {
      builder.sb_push_str(sb, "&#39;");
    } else {
      builder.sb_push_byte(sb, b as UInt8);
    }
    k = k + 1;
  }
}

// Emit one interpolation under the output cap. Returns 0 when the value
// was appended, 1 when the cap would be exceeded (the caller maps that to
// the strict Err / the lenient truncation).
fn _emit_interp(sb: &mut Vec[UInt8], value: Str, escape: Bool) -> Int {
  let add = _value_len(value, escape);
  if sb.len() + add > TEMPLATE_MAX_OUTPUT {
    return 1;
  }
  _push_value(sb, value, escape);
  return 0;
}

// --------------------------------------------------
//  Error text (offsets formatted with the builder)
// --------------------------------------------------

// "template: <lead><name><tail><off>".
fn _msg_name_off(lead: Str, name: Str, tail: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "template: ");
  builder.sb_push_str(&mut sb, lead);
  builder.sb_push_str(&mut sb, name);
  builder.sb_push_str(&mut sb, tail);
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// Mismatched close with an open section: "mismatched close '<name>' at byte
// <off> (expected '<open>')".
fn _msg_mismatch(name: Str, expected: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "template: mismatched close '");
  builder.sb_push_str(&mut sb, name);
  builder.sb_push_str(&mut sb, "' at byte ");
  builder.sb_push_int(&mut sb, off);
  builder.sb_push_str(&mut sb, " (expected '");
  builder.sb_push_str(&mut sb, expected);
  builder.sb_push_str(&mut sb, "')");
  return builder.sb_to_str(&sb);
}

// "template: nesting exceeds <cap> at byte <off>".
fn _msg_depth(off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "template: nesting exceeds ");
  builder.sb_push_int(&mut sb, TEMPLATE_MAX_DEPTH);
  builder.sb_push_str(&mut sb, " at byte ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// "template: output exceeds <cap> bytes at byte <off>".
fn _msg_output(off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "template: output exceeds ");
  builder.sb_push_int(&mut sb, TEMPLATE_MAX_OUTPUT);
  builder.sb_push_str(&mut sb, " bytes at byte ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Block renderer
// --------------------------------------------------

// Shared block renderer. Strict mode returns Err on the first problem and
// discards the output; lenient mode never fails:
//   * unknown interpolation -> ""; unknown section -> skipped (inverted ->
//     rendered);
//   * an unclosed "{{" drops the rest of the template (prefix kept);
//   * unterminated sections are completed as if closed at end of template
//     (list sections iterate all remaining items);
//   * a mismatched close is ignored;
//   * sections beyond TEMPLATE_MAX_DEPTH are suppressed;
//   * output beyond TEMPLATE_MAX_OUTPUT is truncated.
// Sections are scanned left to right with an explicit stack: a non-empty
// list section re-scans its body from body_start at every close tag, so no
// template text is ever copied per iteration and no recursion is used.
fn _render_blocks(tmpl: Str, data: &TemplateData, escape: Bool, strict: Bool) -> Result[Str, Str] {
  var sb = builder.sb_new();
  let len = tmpl.len();
  let tbase = tmpl.c_str();
  var stack = Vec[_Frame].new();
  var over = 0;
  var i = 0;
  var running = true;
  while running {
    while i < len {
      let b = _byte(tbase, i);
      if b == _B_LBRACE && i + 1 < len && _byte(tbase, i + 1) == _B_LBRACE {
        let quiet = _suppressed(&stack, over);
        if i + 2 < len && _byte(tbase, i + 2) == _B_LBRACE && i + 3 < len && _byte(tbase, i + 3) == _B_LBRACE {
          // "{{{{" emits one literal "{{" (v0.1.2 rule, kept).
          if !quiet {
            if sb.len() + 2 > TEMPLATE_MAX_OUTPUT {
              if strict {
                return _err_str(_msg_output(i));
              }
              return _ok_str(builder.sb_to_str(&sb));
            }
            builder.sb_push_str(&mut sb, "{{");
          }
          i = i + 4;
        } elif i + 2 < len && _byte(tbase, i + 2) == _B_LBRACE {
          // "{{{name}}}" raw interpolation.
          let c3 = _find_close3(tmpl, i + 3);
          if c3 < 0 {
            if strict {
              return _err_str(_msg_name_off("", "unclosed interpolation", " at byte ", i));
            }
            return _ok_str(builder.sb_to_str(&sb));
          }
          let name = _trim_spaces(tmpl, i + 3, c3);
          if !quiet {
            if !_interp_known(data, &stack, name) {
              if strict {
                return _err_str(_msg_name_off("unknown key: ", name, " at byte ", i));
              }
            } else if _emit_interp(&mut sb, _interp_value(data, &stack, name), false) == 1 {
              if strict {
                return _err_str(_msg_output(i));
              }
              return _ok_str(builder.sb_to_str(&sb));
            }
          }
          i = c3 + 3;
        } else {
          let close = _find_close(tmpl, i + 2);
          if close < 0 {
            if strict {
              return _err_str(_msg_name_off("", "unclosed interpolation", " at byte ", i));
            }
            return _ok_str(builder.sb_to_str(&sb));
          }
          var k = i + 2;
          while k < close && _byte(tbase, k) == _B_SPACE {
            k = k + 1;
          }
          var marker = -1;
          if k < close {
            marker = _byte(tbase, k);
          }
          let next = close + 2;
          if marker == _B_BANG {
            // Comment: removed entirely (never a key reference).
            i = next;
          } elif marker == _B_HASH || marker == _B_CARET {
            let name = _trim_spaces(tmpl, k + 1, close);
            if quiet {
              if over > 0 {
                over = over + 1;
              } elif stack.len() >= TEMPLATE_MAX_DEPTH {
                if strict {
                  return _err_str(_msg_depth(i));
                }
                over = 1;
              } else {
                _push(&mut stack, name, -1, _MODE_SKIP, -1, next, i, "");
              }
            } else {
              let sec = _eval_section(data, &stack, name);
              var want = sec.act;
              if !sec.known {
                if strict {
                  return _err_str(_msg_name_off("unknown key: ", name, " at byte ", i));
                }
                if marker == _B_CARET {
                  want = 1;
                } else {
                  want = 0;
                }
              } elif marker == _B_CARET {
                if sec.act == 0 {
                  want = 1;
                } else {
                  want = 0;
                }
              }
              if stack.len() + over >= TEMPLATE_MAX_DEPTH {
                if strict {
                  return _err_str(_msg_depth(i));
                }
                over = over + 1;
              } elif want == 2 {
                _push(&mut stack, name, sec.entry, _MODE_LIST, 0, next, i, _current_prefix(&stack));
              } elif want == 1 {
                if marker == _B_HASH {
                  _push(&mut stack, name, -1, _MODE_ONCE, -1, next, i, sec.prefix);
                } else {
                  _push(&mut stack, name, -1, _MODE_INVERTED, -1, next, i, _current_prefix(&stack));
                }
              } else {
                _push(&mut stack, name, -1, _MODE_SKIP, -1, next, i, "");
              }
            }
            i = next;
          } elif marker == _B_SLASH {
            let name = _trim_spaces(tmpl, k + 1, close);
            if over > 0 {
              over = over - 1;
              i = next;
            } elif stack.len() == 0 {
              if strict {
                return _err_str(_msg_name_off("mismatched close '", name, "' at byte ", i));
              }
              i = next;
            } else {
              let top = stack[stack.len() - 1];
              if _streq(top.tag_name, name) {
                if top.mode == _MODE_LIST && top.item + 1 < _list_len(data, top.entry) {
                  // Next iteration: rescan the body, no output copy.
                  _advance_list(&mut stack, top.item + 1);
                  i = top.body_start;
                } else {
                  stack.pop();
                  i = next;
                }
              } else {
                if strict {
                  return _err_str(_msg_mismatch(name, top.tag_name, i));
                }
                i = next;
              }
            }
          } elif marker == _B_AMP {
            // "{{&name}}" raw interpolation.
            let name = _trim_spaces(tmpl, k + 1, close);
            if !quiet {
              if !_interp_known(data, &stack, name) {
                if strict {
                  return _err_str(_msg_name_off("unknown key: ", name, " at byte ", i));
                }
              } else if _emit_interp(&mut sb, _interp_value(data, &stack, name), false) == 1 {
                if strict {
                  return _err_str(_msg_output(i));
                }
                return _ok_str(builder.sb_to_str(&sb));
              }
            }
            i = next;
          } else {
            // Plain interpolation (escaped in auto-escape mode).
            let name = _trim_spaces(tmpl, i + 2, close);
            if !quiet {
              if !_interp_known(data, &stack, name) {
                if strict {
                  return _err_str(_msg_name_off("unknown key: ", name, " at byte ", i));
                }
              } else if _emit_interp(&mut sb, _interp_value(data, &stack, name), escape) == 1 {
                if strict {
                  return _err_str(_msg_output(i));
                }
                return _ok_str(builder.sb_to_str(&sb));
              }
            }
            i = next;
          }
        }
      } else {
        // Literal byte.
        if !_suppressed(&stack, over) {
          if sb.len() + 1 > TEMPLATE_MAX_OUTPUT {
            if strict {
              return _err_str(_msg_output(i));
            }
            return _ok_str(builder.sb_to_str(&sb));
          }
          builder.sb_push_byte(&mut sb, b as UInt8);
        }
        i = i + 1;
      }
    }

    // End of template.
    if strict && stack.len() > 0 {
      let top = stack[stack.len() - 1];
      return _err_str(_msg_name_off("unterminated section '", top.tag_name, "' at byte ", top.open_offset));
    }
    if over > 0 {
      over = 0;
    }
    // Lenient virtual closes: complete open sections as if they were closed
    // at end of template (list sections iterate their remaining items).
    var resumed = false;
    while stack.len() > 0 && !resumed {
      let top = stack[stack.len() - 1];
      if top.mode == _MODE_LIST && top.item + 1 < _list_len(data, top.entry) {
        _advance_list(&mut stack, top.item + 1);
        i = top.body_start;
        resumed = true;
      } else {
        stack.pop();
      }
    }
    if !resumed {
      running = false;
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Public render entry points
// --------------------------------------------------

/// Render `tmpl` with the block surface, substituting `{{name}}` from `data`
/// with HTML auto-escaping when `escape_html` is set.
/// Params: tmpl - the template text; data - the flat TemplateData;
/// escape_html - true escapes &, <, >, ", ' in every "{{name}}" and "{{.}}"
/// substitution ({{{name}}} and {{&name}} stay raw); false copies every
/// value verbatim.
/// Returns: Ok(rendered text). "{{! ... }}" comments and "{{{{" (one
/// literal "{{") behave as in template_render; "{{#key}}...{{/key}}" renders
/// or iterates a section; "{{^key}}" is the inverted form; lookups try the
/// innermost section context first, then ancestors, then the root.
/// Error case: Err("template: unknown key: <name> at byte <off>") for an
/// unknown name in strict mode; Err("template: unclosed interpolation at
/// byte <off>") for a "{{" without a close; Err("template: unterminated
/// section '<name>' at byte <off>"); Err("template: mismatched close
/// '<name>' at byte <off>"); Err("template: nesting exceeds 64 at byte
/// <off>"); Err("template: output exceeds 8388608 bytes at byte <off>").
/// Complexity: O(n * depth * entries) for the lookups plus O(output).
pub fn template_render_blocks(tmpl: Str, data: &TemplateData, escape_html: Bool) -> Result[Str, Str]
  ensures: tmpl.len() == 0 => result is Ok;
  ensures: result is Err => tmpl.len() > 0;
{
  return _render_blocks(tmpl, data, escape_html, true);
}

/// Render `tmpl` with the block surface like template_render_blocks, but
/// never fail.
/// Params: tmpl - the template text; data - the flat TemplateData;
/// escape_html - as in template_render_blocks.
/// Returns: the rendered text. Unknown interpolation keys render "" and
/// unknown sections are skipped (inverted sections render); a mismatched
/// close is ignored; unterminated sections are completed as if closed at
/// end of template; an unclosed "{{" drops the rest of the template (the
/// prefix is kept); sections beyond TEMPLATE_MAX_DEPTH are suppressed and
/// the output is truncated at TEMPLATE_MAX_OUTPUT bytes.
/// Error case: none.
/// Complexity: O(n * depth * entries) for the lookups plus O(output).
pub fn template_render_blocks_lenient(tmpl: Str, data: &TemplateData, escape_html: Bool) -> Str
  ensures: tmpl.len() == 0 => result.len() == 0;
  ensures: result.len() <= TEMPLATE_MAX_OUTPUT;
{
  let r = _render_blocks(tmpl, data, escape_html, false);
  if r.is_ok {
    return r.value;
  }
  return "";
}
