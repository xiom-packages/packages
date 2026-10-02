// XIOM -- xiom.puppet: pure Puppet-style declarative configuration model
// Port task: promote the xiom.puppet placeholder to a real, tested, pure-XIOM
// package: a manifest-parsing subset (class and resource declarations,
// attributes, ->/require/before/notify/subscribe relationships), a module
// layout and metadata model, hiera-style hierarchical lookup (first / unique /
// hash merge with %{...} interpolation), a catalog builder with dependency
// ordering, a deterministic apply / change simulation and a run report with
// applied / changed / failed / skipped accounting.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: MODEL ONLY. There is no network, no shell-out, no FFI and no file
// I/O. A catalog apply is a pure function of the parsed manifest and an
// in-memory host state: the same inputs always produce the same run order,
// the same report counts and the same event log. A host that really applies a
// catalog supplies the current state and uses the report to drive real
// providers.
//
// Model (Vec[StructType] is unsupported in this compiler, so every collection
// is a set of index-aligned parallel vectors):
//   Manifest    class declarations plus resource rows (res_*) each owned by a
//               class index, attribute rows (at_*) each owned by a resource
//               index, and relationship rows (rel_*) for the metaparams
//               require / before / notify / subscribe and for chaining
//               statements (A -> B). Parsed from a manifest string by
//               puppet_manifest_parse.
//   ModuleMeta  a module's name, version, manifest list and dependency list,
//               built immutably (puppet_module_add_* copies) and validated by
//               puppet_module_validate (all errors at once).
//   Hiera       hierarchy level names (highest priority first) plus data rows
//               (h_level / h_key / h_value). Lookup modes: first (first
//               matching level wins), unique (union across levels, deduped in
//               hierarchy order) and hash (all descendants of a key prefix,
//               first level wins per subkey, first-insertion order).
//   Scope       index-aligned key/value vector used both as the hiera hash
//               result and as the interpolation variable scope.
//   Catalog     one class's resources with attributes re-owned by catalog
//               index, a deterministic topological run order (smallest index
//               first on ties) and dependency / refresh edge lists.
//   State       host state: "type[title]" -> current ensure value.
//   Report      apply counters (total/applied/changed/unchanged/skipped/
//               failed/provider_calls/refreshed) plus an ordered event log.
//
// Manifest grammar subset (see SPEC.md section 3):
//   manifest     = *( ws / comment / class_decl )
//   class_decl   = "class" ws+ ident ws* "{" body "}"
//   body         = *( ws / comment / resource_decl / chain )
//   resource_decl= ident ws* "{" ws* title ws* ":" attrs "}"
//   attrs        = *( attr ws* [ "," ] )        ; trailing comma allowed
//   attr         = ident ws* "=>" ws* value
//   value        = quoted / bare / ref
//   ref          = ident ws* "[" ws* title ws* "]"
//   chain        = ref ws* "->" ws* ref *( ws* "->" ws* ref )
//   title        = quoted / ident
//   quoted       = "'" *( byte except "'", LF, CR ) "'"
//   comment      = "#" *( byte except LF )
// Quoted strings have no escape sequences; a NUL byte anywhere in the input is
// rejected (so no rendered value can carry a NUL sentinel).
//
// v0.62.2 notes that shaped this module:
//   * Free functions only; every walk is index-based over parallel vectors.
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     _manifest_ok/_manifest_err, _catalog_ok/_catalog_err, _str_ok/_str_err,
//     _strs_ok/_strs_err, _int_ok/_int_err, _bool_ok/_bool_err, _ref_ok/
//     _ref_err, _val_ok/_val_err and _scope_ok/_scope_err (constructing
//     Results directly inside larger functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Every Vec[Str] / Vec[Int] element read is bound to a typed local first;
//     no &mut scalar parameters are used (the parser cursor lives in the
//     Parser struct, apply state in local Vecs).

module xiom.puppet

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[Manifest, Str].
fn _manifest_ok(m: Manifest) -> Result[Manifest, Str] {
  return Ok(m);
}

// Err(m) for Result[Manifest, Str].
fn _manifest_err(m: Str) -> Result[Manifest, Str] {
  return Err(m);
}

// Ok(c) for Result[Catalog, Str].
fn _catalog_ok(c: Catalog) -> Result[Catalog, Str] {
  return Ok(c);
}

// Err(m) for Result[Catalog, Str].
fn _catalog_err(m: Str) -> Result[Catalog, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _str_ok(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _strs_ok(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _strs_err(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _int_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _int_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _bool_ok(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _bool_err(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(r) for Result[Ref, Str].
fn _ref_ok(r: Ref) -> Result[Ref, Str] {
  return Ok(r);
}

// Err(m) for Result[Ref, Str].
fn _ref_err(m: Str) -> Result[Ref, Str] {
  return Err(m);
}

// Ok(v) for Result[Val, Str].
fn _val_ok(v: Val) -> Result[Val, Str] {
  return Ok(v);
}

// Err(m) for Result[Val, Str].
fn _val_err(m: Str) -> Result[Val, Str] {
  return Err(m);
}

// Ok(s) for Result[Scope, Str].
fn _scope_ok(s: Scope) -> Result[Scope, Str] {
  return Ok(s);
}

// Err(m) for Result[Scope, Str].
fn _scope_err(m: Str) -> Result[Scope, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (widened Int values; see _byte)
// --------------------------------------------------

const _PP_TAB: Int = 9;
const _PP_LF: Int = 10;
const _PP_CR: Int = 13;
const _PP_SPACE: Int = 32;
const _PP_HASH: Int = 35;
const _PP_PERCENT: Int = 37;
const _PP_DASH: Int = 45;
const _PP_DOT: Int = 46;
const _PP_ZERO: Int = 48;
const _PP_NINE: Int = 57;
const _PP_COLON: Int = 58;
const _PP_EQ: Int = 61;
const _PP_GT: Int = 62;
const _PP_LBRACKET: Int = 91;
const _PP_RBRACKET: Int = 93;
const _PP_LBRACE: Int = 123;
const _PP_RBRACE: Int = 125;
const _PP_SQUOTE: Int = 39;
const _PP_LOWER_A: Int = 97;
const _PP_LOWER_Z: Int = 122;
const _PP_UPPER_A: Int = 65;
const _PP_UPPER_Z: Int = 90;
const _PP_USCORE: Int = 95;
const _PP_NUL: Int = 0;

// Lookup / apply bounds (trap D: bounded loops).
const _PP_MAX_INTERP: Int = 8;

// Apply status of one resource.
const _PP_ST_PENDING: Int = 0;
const _PP_ST_CHANGED: Int = 1;
const _PP_ST_UNCHANGED: Int = 2;
const _PP_ST_SKIPPED: Int = 3;
const _PP_ST_FAILED: Int = 4;

// --------------------------------------------------
//  Byte and Str primitives
// --------------------------------------------------

// Widen and mask one byte of `s`. byte_at returns UInt8 and comparisons on
// bytes >= 128 miscompile unless widened to Int and masked first, so every
// byte read in this module goes through here.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Byte-exact Str equality through str_compare (BUG 17: `==` on Str values
// read from Vec[Str] elements lowers to a pointer comparison).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII lowercase fold of a widened byte value: A-Z -> a-z, everything else
// unchanged.
fn _fold_ascii(c: Int) -> Int {
  if c >= _PP_UPPER_A && c <= _PP_UPPER_Z {
    return c + 32;
  }
  return c;
}

// Case-insensitive (ASCII) Str equality: resource references write types
// capitalized ("Package['x']") while declarations use the lowercase type
// name, so reference resolution compares types through this helper.
fn _streq_ci(a: Str, b: Str) -> Bool {
  if str_len(a) != str_len(b) {
    return false;
  }
  var i = 0;
  while i < str_len(a) {
    let ca = _fold_ascii(_byte(a, i));
    let cb = _fold_ascii(_byte(b, i));
    if ca != cb {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `v` contains `s` (byte-exact, through _streq). Scans the vector;
// every element read is bound to a typed local first.
fn _vec_has(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Str = v[i];
    if _streq(x, s) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Index of the first element of `v` equal to `s`, or -1.
fn _vec_index(v: &Vec[Str], s: Str) -> Int {
  var i = 0;
  while i < v.len() {
    let x: Str = v[i];
    if _streq(x, s) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True for an ASCII space or horizontal tab.
fn _is_ws(c: Int) -> Bool {
  return c == _PP_SPACE || c == _PP_TAB;
}

// True for an ASCII line feed or carriage return.
fn _is_eol(c: Int) -> Bool {
  return c == _PP_LF || c == _PP_CR;
}

// True for an ASCII lowercase letter.
fn _is_lower(c: Int) -> Bool {
  return c >= _PP_LOWER_A && c <= _PP_LOWER_Z;
}

// True for an ASCII uppercase letter.
fn _is_upper(c: Int) -> Bool {
  return c >= _PP_UPPER_A && c <= _PP_UPPER_Z;
}

// True for an ASCII decimal digit.
fn _is_digit(c: Int) -> Bool {
  return c >= _PP_ZERO && c <= _PP_NINE;
}

// True for the first byte of a parser identifier (letter or underscore).
fn _is_ident_start(c: Int) -> Bool {
  if _is_lower(c) || _is_upper(c) {
    return true;
  }
  return c == _PP_USCORE;
}

// True for a following parser identifier byte (letter, digit, underscore).
fn _is_ident_char(c: Int) -> Bool {
  if _is_ident_start(c) {
    return true;
  }
  return _is_digit(c);
}

// True for a byte accepted inside a bare attribute value: anything above
// space except the structural bytes ',', '}', '{', '[', ']', ':', '=', '>',
// '#', "'" and '"'.
fn _is_value_char(c: Int) -> Bool {
  if c <= _PP_SPACE {
    return false;
  }
  if c == _PP_LF || c == _PP_CR {
    return false;
  }
  if c == _PP_DOT || c == _PP_DASH || c == _PP_USCORE || c == _PP_PERCENT {
    return true;
  }
  if c == _PP_COLON || c == _PP_EQ || c == _PP_GT {
    return false;
  }
  if c == _PP_LBRACKET || c == _PP_RBRACKET || c == _PP_LBRACE || c == _PP_RBRACE {
    return false;
  }
  if c == _PP_SQUOTE || c == 44 || c == _PP_HASH {
    return false;
  }
  return true;
}

// True for a byte accepted in a hiera interpolation variable name (after an
// optional leading "::"): letter, digit, underscore, dot, dash.
fn _is_interp_char(c: Int) -> Bool {
  if _is_ident_char(c) {
    return true;
  }
  return c == _PP_DOT || c == _PP_DASH;
}

// True when `s` contains a NUL byte. Parse rejects such input so no rendered
// value can ever carry a NUL sentinel.
fn _has_nul(s: Str) -> Bool {
  var i = 0;
  while i < str_len(s) {
    if _byte(s, i) == _PP_NUL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Left-trim ASCII space/tab.
fn _ltrim_ws(s: Str) -> Str {
  var i = 0;
  while i < str_len(s) && _is_ws(_byte(s, i)) {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, str_len(s));
}

// Right-trim ASCII space/tab.
fn _rtrim_ws(s: Str) -> Str {
  var n = str_len(s);
  while n > 0 && _is_ws(_byte(s, n - 1)) {
    n = n - 1;
  }
  if n == str_len(s) {
    return s;
  }
  return string.str_slice(s, 0, n);
}

// Trim ASCII space/tab from both ends.
fn _trim_ws(s: Str) -> Str {
  return _rtrim_ws(_ltrim_ws(s));
}

// "type[title]" reference text.
fn _ref_text(typ: Str, title: Str) -> Str {
  return typ + "[" + title + "]";
}

// True for one of the seven supported resource types.
fn _known_type(t: Str) -> Bool {
  if _streq(t, "package") {
    return true;
  }
  if _streq(t, "service") {
    return true;
  }
  if _streq(t, "file") {
    return true;
  }
  if _streq(t, "exec") {
    return true;
  }
  if _streq(t, "user") {
    return true;
  }
  if _streq(t, "group") {
    return true;
  }
  return _streq(t, "notify");
}

// True for one of the four relationship metaparams.
fn _is_metaparam(k: Str) -> Bool {
  if _streq(k, "require") {
    return true;
  }
  if _streq(k, "before") {
    return true;
  }
  if _streq(k, "notify") {
    return true;
  }
  return _streq(k, "subscribe");
}

// Safe accessors: "" / -1 out of range.
fn _safe_str(v: &Vec[Str], i: Int) -> Str {
  if i < 0 || i >= v.len() {
    return "";
  }
  let s: Str = v[i];
  return s;
}

// Safe accessor: -1 out of range.
fn _safe_int(v: &Vec[Int], i: Int) -> Int {
  if i < 0 || i >= v.len() {
    return -1;
  }
  let n: Int = v[i];
  return n;
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed manifest: class declarations, resource rows, attribute rows and
/// relationship rows. Every row family is a parallel vector; see the module
/// header for ownership rules. Build one with puppet_manifest_parse.
pub type Manifest = {
  classes: Vec[Str];        // class names, declaration order
  cls_owner: Vec[Int];      // resource row -> class index
  res_type: Vec[Str];       // resource type, e.g. "package"
  res_title: Vec[Str];      // resource title, e.g. "nginx"
  rel_owner: Vec[Int];      // metaparam row -> declaring resource index; -1 for chain rows
  rel_kind: Vec[Str];       // "require" / "before" / "notify" / "subscribe" / "chain"
  rel_src_type: Vec[Str];   // chain row source type (metaparam rows copy the owner type)
  rel_src_title: Vec[Str];  // chain row source title (metaparam rows copy the owner title)
  rel_type: Vec[Str];       // target reference type
  rel_title: Vec[Str];      // target reference title
  at_owner: Vec[Int];       // attribute row -> resource index
  at_key: Vec[Str];
  at_value: Vec[Str];
}

/// A Puppet-style module's metadata: name ("author-name"), version
/// ("major.minor.patch"), manifest base names and dependency module names.
/// Built immutably with puppet_module_add_manifest / puppet_module_add_dep;
/// validated with puppet_module_validate.
pub type ModuleMeta = {
  name: Str;
  version: Str;
  deps: Vec[Str];
  manifests: Vec[Str];
}

/// A hiera hierarchy: level names in priority order (index 0 is consulted
/// first) plus index-aligned data rows. Row `i` assigns h_value[i] to
/// h_key[i] inside level h_level[i].
pub type Hiera = {
  levels: Vec[Str];
  h_level: Vec[Int];
  h_key: Vec[Str];
  h_value: Vec[Str];
}

/// An ordered key/value store: index-aligned parallel vectors. Used as the
/// interpolation variable scope and as the hiera hash-merge result. A
/// duplicate key replaces its value in place (first position kept).
pub type Scope = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// A catalog for one class: resources in declaration order with attributes
/// re-owned by catalog index, a deterministic run order (`order[position]` is
/// a resource index) and dependency / refresh edge lists. Produced by
/// puppet_catalog; consumed by puppet_apply.
pub type Catalog = {
  res_type: Vec[Str];
  res_title: Vec[Str];
  at_owner: Vec[Int];
  at_key: Vec[Str];
  at_value: Vec[Str];
  order: Vec[Int];          // run order: position -> resource index
  edge_from: Vec[Int];      // dependency edge: from must run before to
  edge_to: Vec[Int];
  rf_from: Vec[Int];        // refresh edge: a change of from refreshes to
  rf_to: Vec[Int];
}

/// Host state: "type[title]" -> current ensure value. A missing key means the
/// resource is in its default (absent) state.
pub type State = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// The deterministic apply report. `total` always equals applied + skipped +
/// failed, and `applied` always equals changed + unchanged.
pub type Report = {
  total: Int;
  applied: Int;
  changed: Int;
  unchanged: Int;
  skipped: Int;
  failed: Int;
  provider_calls: Int;
  refreshed: Int;
  events: Vec[Str];
}

// Parser cursor (module-internal). The position lives in a struct field so no
// &mut Int scalar parameter is ever needed.
type Parser = {
  text: Str;
  pos: Int;
  len: Int;
}

// A parsed resource reference ("type[title]").
type Ref = {
  typ: Str;
  title: Str;
}

// A parsed attribute value: either a scalar (scalar holds the text) or a
// reference (ref_type / ref_title hold the parts; scalar holds "type[title]").
type Val = {
  is_ref: Int;
  scalar: Str;
  ref_type: Str;
  ref_title: Str;
}

// Mutable edge accumulator used while building a catalog (module-internal).
type Edges = {
  from: Vec[Int];
  to: Vec[Int];
  refresh: Vec[Int];
}

// --------------------------------------------------
//  Manifest parser
// --------------------------------------------------

// Parse error message at a captured offset: "puppet: parse error at <pos>:
// <detail>".
fn _emsg_at(pos: Int, detail: Str) -> Str {
  return "puppet: parse error at " + convert.int_to_string(pos) + ": " + detail;
}

// Parse error message at the current cursor.
fn _pp_emsg(p: &Parser, detail: Str) -> Str {
  return _emsg_at(p.pos, detail);
}

// Cursor byte, or -1 at end of input.
fn _pp_peek(p: &Parser) -> Int {
  if p.pos >= p.len {
    return -1;
  }
  return _byte(p.text, p.pos);
}

// Skip whitespace and '#' comments.
fn _pp_skip_ws(p: &mut Parser) {
  while p.pos < p.len {
    let c = _pp_peek(p);
    if _is_ws(c) || _is_eol(c) {
      p.pos = p.pos + 1;
    } elif c == _PP_HASH {
      while p.pos < p.len {
        let hc = _pp_peek(p);
        if _is_eol(hc) {
          break;
        }
        p.pos = p.pos + 1;
      }
    } else {
      return;
    }
  }
}

// True when the literal `word` (ASCII, no whitespace) matches at the cursor.
fn _pp_at(p: &Parser, word: Str) -> Bool {
  let n = str_len(word);
  if p.pos + n > p.len {
    return false;
  }
  let got = string.str_slice(p.text, p.pos, p.pos + n);
  return _streq(got, word);
}

// Consume one identifier: [A-Za-z_][A-Za-z0-9_]*.
fn _pp_ident(p: &mut Parser) -> Result[Str, Str] {
  let start = p.pos;
  if p.pos >= p.len {
    return _str_err(_emsg_at(start, "expected identifier"));
  }
  let c0 = _pp_peek(p);
  if !_is_ident_start(c0) {
    return _str_err(_emsg_at(start, "expected identifier"));
  }
  p.pos = p.pos + 1;
  while p.pos < p.len {
    let c = _pp_peek(p);
    if _is_ident_char(c) {
      p.pos = p.pos + 1;
    } else {
      break;
    }
  }
  let s = string.str_slice(p.text, start, p.pos);
  return _str_ok(s);
}

// Consume a bare token of value characters (at least one byte).
fn _pp_bare(p: &mut Parser) -> Result[Str, Str] {
  let start = p.pos;
  while p.pos < p.len {
    let c = _pp_peek(p);
    if _is_value_char(c) {
      p.pos = p.pos + 1;
    } else {
      break;
    }
  }
  if p.pos == start {
    return _str_err(_emsg_at(start, "expected attribute value"));
  }
  let s = string.str_slice(p.text, start, p.pos);
  return _str_ok(s);
}

// Consume a single-quoted string (no escape sequences; a newline before the
// closing quote is an error).
fn _pp_quoted(p: &mut Parser) -> Result[Str, Str] {
  let open = p.pos;
  p.pos = p.pos + 1;
  let start = p.pos;
  while p.pos < p.len {
    let c = _pp_peek(p);
    if c == _PP_SQUOTE {
      let s = string.str_slice(p.text, start, p.pos);
      p.pos = p.pos + 1;
      return _str_ok(s);
    }
    if _is_eol(c) {
      return _str_err(_emsg_at(open, "unterminated string"));
    }
    p.pos = p.pos + 1;
  }
  return _str_err(_emsg_at(open, "unterminated string"));
}

// Consume a title: quoted string or identifier; the result must be non-empty.
fn _pp_title(p: &mut Parser) -> Result[Str, Str] {
  _pp_skip_ws(p);
  let start = p.pos;
  if p.pos >= p.len {
    return _str_err(_emsg_at(start, "expected resource title"));
  }
  let c = _pp_peek(p);
  if c == _PP_SQUOTE {
    let q = _pp_quoted(p);
    match q {
      Ok(s) => {
        if str_len(s) == 0 {
          return _str_err(_emsg_at(start, "empty resource title"));
        }
        return _str_ok(s);
      },
      Err(e) => { return _str_err(e); },
    }
    return _str_err(_emsg_at(start, "expected resource title"));
  }
  if !_is_ident_start(c) {
    return _str_err(_emsg_at(start, "expected resource title"));
  }
  return _pp_ident(p);
}

// Consume a resource reference: type '[' title ']'.
fn _pp_ref(p: &mut Parser) -> Result[Ref, Str] {
  let start = p.pos;
  let tr = _pp_ident(p);
  match tr {
    Ok(typ) => {
      _pp_skip_ws(p);
      if _pp_peek(p) != _PP_LBRACKET {
        return _ref_err(_emsg_at(p.pos, "expected '[' after '" + typ + "'"));
      }
      p.pos = p.pos + 1;
      let ttl = _pp_title(p);
      match ttl {
        Ok(title) => {
          _pp_skip_ws(p);
          if _pp_peek(p) != _PP_RBRACKET {
            return _ref_err(_emsg_at(p.pos, "expected ']'"));
          }
          p.pos = p.pos + 1;
          return _ref_ok(Ref{ typ: typ; title: title; });
        },
        Err(e) => { return _ref_err(e); },
      }
      return _ref_err(_emsg_at(start, "expected resource reference"));
    },
    Err(e) => { return _ref_err(e); },
  }
  return _ref_err(_emsg_at(start, "expected resource reference"));
}

// Consume an attribute value: quoted string, bare token, or resource ref.
fn _pp_value(p: &mut Parser) -> Result[Val, Str] {
  _pp_skip_ws(p);
  let start = p.pos;
  if p.pos >= p.len {
    return _val_err(_emsg_at(start, "expected attribute value"));
  }
  let c = _pp_peek(p);
  if c == _PP_SQUOTE {
    let q = _pp_quoted(p);
    match q {
      Ok(s) => { return _val_ok(Val{ is_ref: 0; scalar: s; ref_type: ""; ref_title: ""; }); },
      Err(e) => { return _val_err(e); },
    }
    return _val_err(_emsg_at(start, "expected attribute value"));
  }
  if !_is_value_char(c) {
    return _val_err(_emsg_at(start, "expected attribute value"));
  }
  let br = _pp_bare(p);
  match br {
    Ok(tok) => {
      _pp_skip_ws(p);
      if _pp_peek(p) == _PP_LBRACKET {
        p.pos = p.pos + 1;
        let ttl = _pp_title(p);
        match ttl {
          Ok(title) => {
            _pp_skip_ws(p);
            if _pp_peek(p) != _PP_RBRACKET {
              return _val_err(_emsg_at(p.pos, "expected ']'"));
            }
            p.pos = p.pos + 1;
            return _val_ok(Val{ is_ref: 1; scalar: _ref_text(tok, title); ref_type: tok; ref_title: title; });
          },
          Err(e) => { return _val_err(e); },
        }
        return _val_err(_emsg_at(start, "expected attribute value"));
      }
      return _val_ok(Val{ is_ref: 0; scalar: tok; ref_type: ""; ref_title: ""; });
    },
    Err(e) => { return _val_err(e); },
  }
  return _val_err(_emsg_at(start, "expected attribute value"));
}

// Append one relationship row. Metaparam rows carry the declaring resource
// index as owner and copy its type/title as the source; chain rows use owner
// -1 and the left-hand reference as the source.
fn _push_rel(m: &mut Manifest, owner: Int, kind: Str, stype: Str, stitle: Str, ttype: Str, ttitle: Str) {
  m.rel_owner.push(owner);
  m.rel_kind.push(kind);
  m.rel_src_type.push(stype);
  m.rel_src_title.push(stitle);
  m.rel_type.push(ttype);
  m.rel_title.push(ttitle);
}

// Parse one resource declaration. `typ` is already consumed; the cursor is at
// the '{'. Appends the resource and its attribute / relationship rows.
fn _pp_resource(p: &mut Parser, m: &mut Manifest, ci: Int, typ: Str) -> Result[Bool, Str] {
  if _pp_peek(p) != _PP_LBRACE {
    return _bool_err(_emsg_at(p.pos, "expected '{'"));
  }
  p.pos = p.pos + 1;
  let ttl = _pp_title(p);
  match ttl {
    Ok(title) => {
      let ri = m.res_type.len();
      _pp_skip_ws(p);
      if _pp_peek(p) != _PP_COLON {
        return _bool_err(_emsg_at(p.pos, "expected ':' after title"));
      }
      p.pos = p.pos + 1;
      m.cls_owner.push(ci);
      m.res_type.push(typ);
      m.res_title.push(title);
      loop {
        _pp_skip_ws(p);
        let c = _pp_peek(p);
        if c == _PP_RBRACE {
          p.pos = p.pos + 1;
          return _bool_ok(true);
        }
        if c < 0 {
          return _bool_err(_emsg_at(p.pos, "unterminated resource body"));
        }
        let akey = _pp_ident(p);
        match akey {
          Ok(key) => {
            _pp_skip_ws(p);
            if !_pp_at(p, "=>") {
              return _bool_err(_emsg_at(p.pos, "expected '=>'"));
            }
            p.pos = p.pos + 2;
            let vr = _pp_value(p);
            match vr {
              Ok(val) => {
                if _is_metaparam(key) {
                  if val.is_ref == 0 {
                    return _bool_err(_emsg_at(p.pos, "expected resource reference for metaparam: " + key));
                  }
                  _push_rel(m, ri, key, typ, title, val.ref_type, val.ref_title);
                } else {
                  m.at_owner.push(ri);
                  m.at_key.push(key);
                  m.at_value.push(val.scalar);
                }
                _pp_skip_ws(p);
                let c2 = _pp_peek(p);
                if c2 == 44 {
                  p.pos = p.pos + 1;
                } elif c2 == _PP_RBRACE {
                  p.pos = p.pos + 1;
                  return _bool_ok(true);
                } else {
                  return _bool_err(_emsg_at(p.pos, "expected ',' or '}'"));
                }
              },
              Err(e) => { return _bool_err(e); },
            }
          },
          Err(e) => { return _bool_err(e); },
        }
      }
      return _bool_err(_emsg_at(p.pos, "unterminated resource body"));
    },
    Err(e) => { return _bool_err(e); },
  }
  return _bool_err(_emsg_at(p.pos, "unterminated resource body"));
}

// Parse a chain statement (first type already consumed): ref ("->" ref)*.
fn _pp_chain(p: &mut Parser, m: &mut Manifest, first_type: Str) -> Result[Bool, Str] {
  if _pp_peek(p) != _PP_LBRACKET {
    return _bool_err(_emsg_at(p.pos, "expected '['"));
  }
  p.pos = p.pos + 1;
  let fttl = _pp_title(p);
  match fttl {
    Ok(ft) => {
      _pp_skip_ws(p);
      if _pp_peek(p) != _PP_RBRACKET {
        return _bool_err(_emsg_at(p.pos, "expected ']'"));
      }
      p.pos = p.pos + 1;
      var stype = first_type;
      var stitle = ft;
      loop {
        _pp_skip_ws(p);
        if !_pp_at(p, "->") {
          return _bool_ok(true);
        }
        p.pos = p.pos + 2;
        _pp_skip_ws(p);
        let rr = _pp_ref(p);
        match rr {
          Ok(r) => {
            _push_rel(m, -1, "chain", stype, stitle, r.typ, r.title);
            stype = r.typ;
            stitle = r.title;
          },
          Err(e) => { return _bool_err(e); },
        }
      }
      return _bool_err(_emsg_at(p.pos, "unterminated chain"));
    },
    Err(e) => { return _bool_err(e); },
  }
  return _bool_err(_emsg_at(p.pos, "expected resource title"));
}

// Parse one class declaration. The "class" keyword is already consumed.
fn _pp_class(p: &mut Parser, m: &mut Manifest) -> Result[Bool, Str] {
  _pp_skip_ws(p);
  let nr = _pp_ident(p);
  match nr {
    Ok(name) => {
      if _vec_has(&m.classes, name) {
        return _bool_err("puppet: duplicate class: " + name);
      }
      let ci = m.classes.len();
      m.classes.push(name);
      _pp_skip_ws(p);
      if _pp_peek(p) != _PP_LBRACE {
        return _bool_err(_emsg_at(p.pos, "expected '{'"));
      }
      p.pos = p.pos + 1;
      loop {
        _pp_skip_ws(p);
        let c = _pp_peek(p);
        if c == _PP_RBRACE {
          p.pos = p.pos + 1;
          return _bool_ok(true);
        }
        if c < 0 {
          return _bool_err(_emsg_at(p.pos, "unterminated class body"));
        }
        let tr = _pp_ident(p);
        match tr {
          Ok(typ) => {
            _pp_skip_ws(p);
            let c2 = _pp_peek(p);
            if c2 == _PP_LBRACE {
              let rr = _pp_resource(p, m, ci, typ);
              match rr {
                Ok(_) => {},
                Err(e) => { return _bool_err(e); },
              }
            } elif c2 == _PP_LBRACKET {
              let cr = _pp_chain(p, m, typ);
              match cr {
                Ok(_) => {},
                Err(e) => { return _bool_err(e); },
              }
            } else {
              return _bool_err(_emsg_at(p.pos, "expected '{' or '[' after '" + typ + "'"));
            }
          },
          Err(e) => { return _bool_err(e); },
        }
      }
      return _bool_err(_emsg_at(p.pos, "unterminated class body"));
    },
    Err(e) => { return _bool_err(e); },
  }
  return _bool_err(_emsg_at(p.pos, "expected class name"));
}

/// An empty manifest.
pub fn puppet_manifest_new() -> Manifest {
  return Manifest{
    classes: Vec[Str].new();
    cls_owner: Vec[Int].new();
    res_type: Vec[Str].new();
    res_title: Vec[Str].new();
    rel_owner: Vec[Int].new();
    rel_kind: Vec[Str].new();
    rel_src_type: Vec[Str].new();
    rel_src_title: Vec[Str].new();
    rel_type: Vec[Str].new();
    rel_title: Vec[Str].new();
    at_owner: Vec[Int].new();
    at_key: Vec[Str].new();
    at_value: Vec[Str].new();
  };
}

/// Parse one in-memory manifest string (grammar subset: see SPEC.md section
/// 3). Returns Ok(Manifest) for a valid input (including an empty one) and
/// Err with a "puppet: ..." message on the first problem. Every parse error
/// except "duplicate class" is reported as
/// "puppet: parse error at <offset>: <detail>". A NUL byte anywhere in the
/// input is rejected up front. Complexity: O(input length * resource count)
/// for duplicate-class checks; linear otherwise.
pub fn puppet_manifest_parse(text: Str) -> Result[Manifest, Str] {
  if _has_nul(text) {
    return _manifest_err("puppet: NUL byte in input");
  }
  var p = Parser{ text: text; pos: 0; len: str_len(text); };
  var m = puppet_manifest_new();
  _pp_skip_ws(&mut p);
  while p.pos < p.len {
    let start = p.pos;
    let kr = _pp_ident(&mut p);
    match kr {
      Ok(kw) => {
        if !_streq(kw, "class") {
          return _manifest_err(_emsg_at(start, "expected class declaration"));
        }
        let cr = _pp_class(&mut p, &mut m);
        match cr {
          Ok(_) => {},
          Err(e) => { return _manifest_err(e); },
        }
      },
      Err(e) => { return _manifest_err(e); },
    }
    _pp_skip_ws(&mut p);
  }
  return _manifest_ok(m);
}

// --------------------------------------------------
//  Manifest accessors
// --------------------------------------------------

/// Number of classes.
pub fn puppet_manifest_class_count(m: &Manifest) -> Int {
  return m.classes.len();
}

/// Class name at index `i`, or "" out of range.
pub fn puppet_manifest_class_name(m: &Manifest, i: Int) -> Str {
  return _safe_str(&m.classes, i);
}

/// Index of class `name`, or -1.
pub fn puppet_manifest_class_index(m: &Manifest, name: Str) -> Int {
  return _vec_index(&m.classes, name);
}

/// Number of resources (all classes).
pub fn puppet_manifest_resource_count(m: &Manifest) -> Int {
  return m.res_type.len();
}

/// Class index owning resource `i`, or -1 out of range.
pub fn puppet_manifest_resource_class(m: &Manifest, i: Int) -> Int {
  return _safe_int(&m.cls_owner, i);
}

/// Resource type at index `i` ("" out of range).
pub fn puppet_manifest_resource_type(m: &Manifest, i: Int) -> Str {
  return _safe_str(&m.res_type, i);
}

/// Resource title at index `i` ("" out of range).
pub fn puppet_manifest_resource_title(m: &Manifest, i: Int) -> Str {
  return _safe_str(&m.res_title, i);
}

/// "type[title]" text of resource `i`.
pub fn puppet_manifest_resource_ref(m: &Manifest, i: Int) -> Str {
  return _ref_text(_safe_str(&m.res_type, i), _safe_str(&m.res_title, i));
}

/// First value of attribute `key` on resource `res`, or None.
pub fn puppet_manifest_attr(m: &Manifest, res: Int, key: Str) -> Option[Str] {
  var i = 0;
  while i < m.at_owner.len() {
    let o: Int = m.at_owner[i];
    if o == res {
      let k: Str = m.at_key[i];
      if _streq(k, key) {
        let v: Str = m.at_value[i];
        return Some(v);
      }
    }
    i = i + 1;
  }
  return None;
}

/// Number of attribute rows.
pub fn puppet_manifest_attr_count(m: &Manifest) -> Int {
  return m.at_key.len();
}

/// Attribute key at row `j` ("" out of range).
pub fn puppet_manifest_attr_key_at(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.at_key, j);
}

/// Number of relationship rows.
pub fn puppet_manifest_rel_count(m: &Manifest) -> Int {
  return m.rel_kind.len();
}

/// Relationship row owner (declaring resource index; -1 for chain rows).
pub fn puppet_manifest_rel_owner(m: &Manifest, j: Int) -> Int {
  return _safe_int(&m.rel_owner, j);
}

/// Relationship row kind ("require" / "before" / "notify" / "subscribe" /
/// "chain"), or "" out of range.
pub fn puppet_manifest_rel_kind(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.rel_kind, j);
}

/// Relationship row source type ("" out of range).
pub fn puppet_manifest_rel_src_type(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.rel_src_type, j);
}

/// Relationship row source title ("" out of range).
pub fn puppet_manifest_rel_src_title(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.rel_src_title, j);
}

/// Relationship row target type ("" out of range).
pub fn puppet_manifest_rel_type(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.rel_type, j);
}

/// Relationship row target title ("" out of range).
pub fn puppet_manifest_rel_title(m: &Manifest, j: Int) -> Str {
  return _safe_str(&m.rel_title, j);
}

// --------------------------------------------------
//  Module metadata model
// --------------------------------------------------

/// A module with the given name and version, no manifests and no deps.
pub fn puppet_module_new(name: Str, version: Str) -> ModuleMeta {
  return ModuleMeta{ name: name; version: version; deps: Vec[Str].new(); manifests: Vec[Str].new(); };
}

// Deep copy of the manifest and dep lists.
fn _copy_module(mm: &ModuleMeta) -> ModuleMeta {
  var out = ModuleMeta{ name: mm.name; version: mm.version; deps: Vec[Str].new(); manifests: Vec[Str].new(); };
  var i = 0;
  while i < mm.deps.len() {
    let d: Str = mm.deps[i];
    out.deps.push(d);
    i = i + 1;
  }
  var j = 0;
  while j < mm.manifests.len() {
    let mn: Str = mm.manifests[j];
    out.manifests.push(mn);
    j = j + 1;
  }
  return out;
}

/// A copy of `mm` with manifest `name` appended (the input is untouched).
pub fn puppet_module_add_manifest(mm: &ModuleMeta, name: Str) -> ModuleMeta {
  var out = _copy_module(mm);
  out.manifests.push(name);
  return out;
}

/// A copy of `mm` with dependency `dep` appended (the input is untouched).
pub fn puppet_module_add_dep(mm: &ModuleMeta, dep: Str) -> ModuleMeta {
  var out = _copy_module(mm);
  out.deps.push(dep);
  return out;
}

/// Number of declared manifests.
pub fn puppet_module_manifest_count(mm: &ModuleMeta) -> Int {
  return mm.manifests.len();
}

/// Number of declared dependencies.
pub fn puppet_module_dep_count(mm: &ModuleMeta) -> Int {
  return mm.deps.len();
}

/// True when `name` is a declared manifest.
pub fn puppet_module_has_manifest(mm: &ModuleMeta, name: Str) -> Bool {
  return _vec_index(&mm.manifests, name) >= 0;
}

/// True when `name` is a declared dependency.
pub fn puppet_module_has_dep(mm: &ModuleMeta, name: Str) -> Bool {
  return _vec_index(&mm.deps, name) >= 0;
}

// True for one lowercase word: a lowercase letter followed by lowercase
// letters, digits or underscores (a module name segment or manifest token).
fn _word_ok(s: Str) -> Bool {
  let n = str_len(s);
  if n == 0 {
    return false;
  }
  if !_is_lower(_byte(s, 0)) {
    return false;
  }
  var i = 1;
  while i < n {
    let c = _byte(s, i);
    if !_is_lower(c) && !_is_digit(c) && c != _PP_USCORE {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for "author-name": exactly one dash, two non-empty lowercase words.
fn _module_name_ok(n: Str) -> Bool {
  let ln = str_len(n);
  var dashes = 0;
  var seg_start = 0;
  var i = 0;
  while i < ln {
    let c = _byte(n, i);
    if c == _PP_DASH {
      if !_word_ok(string.str_slice(n, seg_start, i)) {
        return false;
      }
      dashes = dashes + 1;
      seg_start = i + 1;
    }
    i = i + 1;
  }
  if !_word_ok(string.str_slice(n, seg_start, ln)) {
    return false;
  }
  return dashes == 1;
}

// True for one non-empty run of ASCII digits.
fn _digits_ok(s: Str) -> Bool {
  let n = str_len(s);
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_digit(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for "major.minor.patch": exactly three non-empty digit runs.
fn _version_ok(v: Str) -> Bool {
  let ln = str_len(v);
  var dots = 0;
  var seg_start = 0;
  var i = 0;
  while i < ln {
    let c = _byte(v, i);
    if c == _PP_DOT {
      if !_digits_ok(string.str_slice(v, seg_start, i)) {
        return false;
      }
      dots = dots + 1;
      seg_start = i + 1;
    } elif !_is_digit(c) {
      return false;
    }
    i = i + 1;
  }
  if !_digits_ok(string.str_slice(v, seg_start, ln)) {
    return false;
  }
  return dots == 2;
}

/// Validate `mm`, returning ALL errors in order (name format, version format,
/// manifest tokens and duplicates, dependency name format, self-dependency,
/// dependency duplicates); an empty vector means valid.
pub fn puppet_module_validate(mm: &ModuleMeta) -> Vec[Str] {
  var errs = Vec[Str].new();
  if !_module_name_ok(mm.name) {
    errs.push("puppet: malformed module name: " + mm.name);
  }
  if !_version_ok(mm.version) {
    errs.push("puppet: malformed module version: " + mm.version);
  }
  var i = 0;
  while i < mm.manifests.len() {
    let mn: Str = mm.manifests[i];
    if !_word_ok(mn) {
      errs.push("puppet: malformed manifest name: " + mn);
    } elif _vec_index(&mm.manifests, mn) != i {
      errs.push("puppet: duplicate manifest: " + mn);
    }
    i = i + 1;
  }
  var j = 0;
  while j < mm.deps.len() {
    let d: Str = mm.deps[j];
    if !_module_name_ok(d) {
      errs.push("puppet: malformed dependency name: " + d);
    } elif _streq(d, mm.name) {
      errs.push("puppet: module depends on itself: " + d);
    } elif _vec_index(&mm.deps, d) != j {
      errs.push("puppet: duplicate dependency: " + d);
    }
    j = j + 1;
  }
  return errs;
}

/// True when puppet_module_validate finds no error.
pub fn puppet_module_valid(mm: &ModuleMeta) -> Bool {
  let errs = puppet_module_validate(mm);
  return errs.len() == 0;
}

/// Canonical relative file list for the module: "metadata.json",
/// "manifests/init.pp", then one "manifests/<name>.pp" per declared manifest
/// (a declared "init" is not duplicated).
pub fn puppet_module_files(mm: &ModuleMeta) -> Vec[Str] {
  var out = Vec[Str].new();
  out.push("metadata.json");
  out.push("manifests/init.pp");
  var i = 0;
  while i < mm.manifests.len() {
    let mn: Str = mm.manifests[i];
    if !_streq(mn, "init") {
      out.push("manifests/" + mn + ".pp");
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Scope (ordered key/value store)
// --------------------------------------------------

/// An empty scope.
pub fn puppet_scope_new() -> Scope {
  return Scope{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

/// Set `key = value`: an existing key is replaced in place (first position
/// kept), a new key is appended.
pub fn puppet_scope_set(s: &mut Scope, key: Str, value: Str) {
  let i = _vec_index(&s.keys, key);
  if i >= 0 {
    s.values[i] = value;
    return;
  }
  s.keys.push(key);
  s.values.push(value);
}

/// Value of `key`, or None.
pub fn puppet_scope_get(s: &Scope, key: Str) -> Option[Str] {
  let i = _vec_index(&s.keys, key);
  if i < 0 {
    return None;
  }
  let v: Str = s.values[i];
  return Some(v);
}

/// Number of entries.
pub fn puppet_scope_len(s: &Scope) -> Int {
  return s.keys.len();
}

/// Key at index `i` ("" out of range).
pub fn puppet_scope_key_at(s: &Scope, i: Int) -> Str {
  return _safe_str(&s.keys, i);
}

/// Value at index `i` ("" out of range).
pub fn puppet_scope_value_at(s: &Scope, i: Int) -> Str {
  return _safe_str(&s.values, i);
}

// --------------------------------------------------
//  Interpolation
// --------------------------------------------------

// Strip a leading "::" from an interpolation variable name.
fn _strip_colons(s: Str) -> Str {
  if str_len(s) >= 2 {
    if _byte(s, 0) == _PP_COLON && _byte(s, 1) == _PP_COLON {
      return string.str_slice(s, 2, str_len(s));
    }
  }
  return s;
}

// True for a valid interpolation variable name: non-empty, first byte a
// letter or underscore, remaining bytes letters, digits, underscore, dot or
// dash.
fn _interp_name_ok(s: Str) -> Bool {
  let n = str_len(s);
  if n == 0 {
    return false;
  }
  if !_is_ident_start(_byte(s, 0)) {
    return false;
  }
  var i = 1;
  while i < n {
    if !_is_interp_char(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Recursive interpolation: expand %{var} / %{::var} against `scope` (at most
// _PP_MAX_INTERP levels deep) and translate %%{ to a literal %{.
fn _interp(s: Str, scope: &Scope, depth: Int) -> Result[Str, Str] {
  if depth > _PP_MAX_INTERP {
    return _str_err("puppet: interpolation: depth exceeded in: " + s);
  }
  var out = "";
  let n = str_len(s);
  var i = 0;
  while i < n {
    let c = _byte(s, i);
    if c == _PP_PERCENT {
      if i + 1 < n && _byte(s, i + 1) == _PP_PERCENT {
        if i + 2 < n && _byte(s, i + 2) == _PP_LBRACE {
          out = out + "%{";
          i = i + 3;
          continue;
        }
      }
      if i + 1 < n && _byte(s, i + 1) == _PP_LBRACE {
        var j = i + 2;
        while j < n && _byte(s, j) != _PP_RBRACE {
          j = j + 1;
        }
        if j >= n {
          return _str_err("puppet: interpolation: unterminated variable reference in: " + s);
        }
        let raw = string.str_slice(s, i + 2, j);
        let name = _strip_colons(raw);
        if !_interp_name_ok(name) {
          return _str_err("puppet: interpolation: malformed variable name: " + raw);
        }
        let got = puppet_scope_get(scope, name);
        match got {
          Some(v) => {
            let r = _interp(v, scope, depth + 1);
            match r {
              Ok(rv) => { out = out + rv; },
              Err(e) => { return _str_err(e); },
            }
          },
          None => { return _str_err("puppet: interpolation: unknown variable: " + name); },
        }
        i = j + 1;
        continue;
      }
    }
    out = out + string.str_slice(s, i, i + 1);
    i = i + 1;
  }
  return _str_ok(out);
}

/// Interpolate `text` against `scope`: %{name} and %{::name} substitute the
/// scope value of `name` recursively (at most 8 levels deep) and %%{ yields a
/// literal %{. Error catalog: "puppet: interpolation: unknown variable:
/// <name>", "puppet: interpolation: malformed variable name: <raw>",
/// "puppet: interpolation: unterminated variable reference in: <text>",
/// "puppet: interpolation: depth exceeded in: <text>".
pub fn puppet_interpolate(text: Str, scope: &Scope) -> Result[Str, Str] {
  return _interp(text, scope, 0);
}

// --------------------------------------------------
//  Hiera
// --------------------------------------------------

/// An empty hierarchy.
pub fn puppet_hiera_new() -> Hiera {
  return Hiera{ levels: Vec[Str].new(); h_level: Vec[Int].new(); h_key: Vec[Str].new(); h_value: Vec[Str].new(); };
}

/// Append hierarchy level `name`; levels are consulted in index order (index
/// 0 is the highest priority). Returns the new index, or -1 when the name
/// already exists.
pub fn puppet_hiera_add_level(h: &mut Hiera, name: Str) -> Int {
  if _vec_index(&h.levels, name) >= 0 {
    return -1;
  }
  h.levels.push(name);
  return h.levels.len() - 1;
}

/// Number of hierarchy levels.
pub fn puppet_hiera_level_count(h: &Hiera) -> Int {
  return h.levels.len();
}

/// Level name at index `i` ("" out of range).
pub fn puppet_hiera_level_name(h: &Hiera, i: Int) -> Str {
  return _safe_str(&h.levels, i);
}

/// Set `key = value` at hierarchy level `level` (the last write at a level
/// wins). Returns false when `level` is not a declared level (nothing is
/// stored).
pub fn puppet_hiera_set(h: &mut Hiera, level: Str, key: Str, value: Str) -> Bool {
  let li = _vec_index(&h.levels, level);
  if li < 0 {
    return false;
  }
  var i = 0;
  while i < h.h_level.len() {
    let lv: Int = h.h_level[i];
    if lv == li {
      let k: Str = h.h_key[i];
      if _streq(k, key) {
        h.h_value[i] = value;
        return true;
      }
    }
    i = i + 1;
  }
  h.h_level.push(li);
  h.h_key.push(key);
  h.h_value.push(value);
  return true;
}

/// First lookup: the value of `key` from the first hierarchy level that
/// defines it (index order), interpolated against `scope`.
/// Err("puppet: hiera: no value for key: <key>") when no level defines it;
/// interpolation errors propagate.
pub fn puppet_hiera_lookup_first(h: &Hiera, key: Str, scope: &Scope) -> Result[Str, Str] {
  var l = 0;
  while l < h.levels.len() {
    var i = 0;
    while i < h.h_level.len() {
      let lv: Int = h.h_level[i];
      let k: Str = h.h_key[i];
      if lv == l && _streq(k, key) {
        let v: Str = h.h_value[i];
        return _interp(v, scope, 0);
      }
      i = i + 1;
    }
    l = l + 1;
  }
  return _str_err("puppet: hiera: no value for key: " + key);
}

/// Unique merge: every value of `key` across all hierarchy levels in index
/// order, each interpolated and deduplicated byte-exactly (first occurrence
/// kept).
/// Err("puppet: hiera: no value for key: <key>") when no level defines it.
pub fn puppet_hiera_lookup_unique(h: &Hiera, key: Str, scope: &Scope) -> Result[Vec[Str], Str] {
  var out = Vec[Str].new();
  var l = 0;
  while l < h.levels.len() {
    var i = 0;
    while i < h.h_level.len() {
      let lv: Int = h.h_level[i];
      let k: Str = h.h_key[i];
      if lv == l && _streq(k, key) {
        let v: Str = h.h_value[i];
        let ir = _interp(v, scope, 0);
        match ir {
          Ok(rv) => {
            if !_vec_has(&out, rv) {
              out.push(rv);
            }
          },
          Err(e) => { return _strs_err(e); },
        }
      }
      i = i + 1;
    }
    l = l + 1;
  }
  if out.len() == 0 {
    return _strs_err("puppet: hiera: no value for key: " + key);
  }
  return _strs_ok(out);
}

// True when `k` starts with `prefix + "."`.
fn _starts_dot(k: Str, prefix: Str) -> Bool {
  let plen = str_len(prefix);
  if str_len(k) < plen + 1 {
    return false;
  }
  let head = string.str_slice(k, 0, plen);
  if !_streq(head, prefix) {
    return false;
  }
  return _byte(k, plen) == _PP_DOT;
}

/// Hash merge: every data key that is a strict descendant of `prefix`
/// ("<prefix>.<sub>", nested descendants included). The first hierarchy level
/// defining a full key wins (index order = priority); entries keep their
/// first-insertion order and the returned keys are the subkey suffixes
/// (prefix stripped), each interpolated.
/// Err("puppet: hiera: no hash values for key: <prefix>") when no descendant
/// exists.
pub fn puppet_hiera_lookup_hash(h: &Hiera, prefix: Str, scope: &Scope) -> Result[Scope, Str] {
  var out = puppet_scope_new();
  let plen = str_len(prefix);
  var l = 0;
  while l < h.levels.len() {
    var i = 0;
    while i < h.h_level.len() {
      let lv: Int = h.h_level[i];
      let k: Str = h.h_key[i];
      if lv == l {
        if _starts_dot(k, prefix) {
          let sub = string.str_slice(k, plen + 1, str_len(k));
          if !_vec_has(&out.keys, sub) {
            let v: Str = h.h_value[i];
            let ir = _interp(v, scope, 0);
            match ir {
              Ok(rv) => { puppet_scope_set(&mut out, sub, rv); },
              Err(e) => { return _scope_err(e); },
            }
          }
        }
      }
      i = i + 1;
    }
    l = l + 1;
  }
  if out.keys.len() == 0 {
    return _scope_err("puppet: hiera: no hash values for key: " + prefix);
  }
  return _scope_ok(out);
}

// --------------------------------------------------
//  Catalog
// --------------------------------------------------

// Append a dependency edge, deduplicating by (from, to) and OR-ing the
// refresh flag.
fn _edge_add(e: &mut Edges, from: Int, to: Int, refresh: Int) {
  var i = 0;
  while i < e.from.len() {
    let f: Int = e.from[i];
    let t: Int = e.to[i];
    if f == from && t == to {
      if refresh != 0 {
        e.refresh[i] = 1;
      }
      return;
    }
    i = i + 1;
  }
  e.from.push(from);
  e.to.push(to);
  e.refresh.push(refresh);
}

// Index of "type[title]" in catalog `c`, or -1. The type comparison is
// ASCII case-insensitive (references write "Package['x']" for a declared
// `package` resource); titles are byte-exact.
fn _cat_index(c: &Catalog, typ: Str, title: Str) -> Int {
  var i = 0;
  while i < c.res_type.len() {
    let t: Str = c.res_type[i];
    let ti: Str = c.res_title[i];
    if _streq_ci(t, typ) && _streq(ti, title) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Attribute lookup on a catalog resource: first row owned by `res` with key
// `key`, or None.
fn _cat_attr(c: &Catalog, res: Int, key: Str) -> Option[Str] {
  var i = 0;
  while i < c.at_owner.len() {
    let o: Int = c.at_owner[i];
    if o == res {
      let k: Str = c.at_key[i];
      if _streq(k, key) {
        let v: Str = c.at_value[i];
        return Some(v);
      }
    }
    i = i + 1;
  }
  return None;
}

/// Build the catalog for one class: copy the class's resources in declaration
/// order with attributes re-owned by catalog index, validate resource types
/// and duplicate resources, resolve every relationship row into dependency /
/// refresh edges, and topologically sort the resources (the smallest catalog
/// index wins ties, so the order is deterministic).
/// Errors: "puppet: unknown class: <name>", "puppet: unknown resource type:
/// <t>", "puppet: duplicate resource: <type>[<title>]",
/// "puppet: unresolved reference: <type>[<title>]",
/// "puppet: dependency cycle: <type>[<title>]".
/// Relationship references resolve inside the selected class only: a
/// metaparam on an in-class resource must resolve in-class, and a chain row is
/// ignored only when neither endpoint resolves in-class.
pub fn puppet_catalog(m: &Manifest, class_name: Str) -> Result[Catalog, Str] {
  let ci = _vec_index(&m.classes, class_name);
  if ci < 0 {
    return _catalog_err("puppet: unknown class: " + class_name);
  }
  var c = Catalog{
    res_type: Vec[Str].new();
    res_title: Vec[Str].new();
    at_owner: Vec[Int].new();
    at_key: Vec[Str].new();
    at_value: Vec[Str].new();
    order: Vec[Int].new();
    edge_from: Vec[Int].new();
    edge_to: Vec[Int].new();
    rf_from: Vec[Int].new();
    rf_to: Vec[Int].new();
  };
  let n = m.res_type.len();
  var map = Vec[Int].new();
  var z = 0;
  while z < n {
    map.push(-1);
    z = z + 1;
  }
  var i = 0;
  while i < n {
    let owner: Int = m.cls_owner[i];
    if owner == ci {
      let typ: Str = m.res_type[i];
      let title: Str = m.res_title[i];
      if !_known_type(typ) {
        return _catalog_err("puppet: unknown resource type: " + typ);
      }
      if _cat_index(&c, typ, title) >= 0 {
        return _catalog_err("puppet: duplicate resource: " + _ref_text(typ, title));
      }
      let cix = c.res_type.len();
      map[i] = cix;
      c.res_type.push(typ);
      c.res_title.push(title);
      var a = 0;
      while a < m.at_owner.len() {
        let ao: Int = m.at_owner[a];
        if ao == i {
          let ak: Str = m.at_key[a];
          let av: Str = m.at_value[a];
          c.at_owner.push(cix);
          c.at_key.push(ak);
          c.at_value.push(av);
        }
        a = a + 1;
      }
    }
    i = i + 1;
  }
  var edges = Edges{ from: Vec[Int].new(); to: Vec[Int].new(); refresh: Vec[Int].new(); };
  var j = 0;
  while j < m.rel_kind.len() {
    let owner: Int = m.rel_owner[j];
    let kind: Str = m.rel_kind[j];
    if owner >= 0 {
      let cls: Int = m.cls_owner[owner];
      if cls == ci {
        let src: Int = map[owner];
        let tt: Str = m.rel_type[j];
        let ttl: Str = m.rel_title[j];
        let tgt = _cat_index(&c, tt, ttl);
        if tgt < 0 {
          return _catalog_err("puppet: unresolved reference: " + _ref_text(tt, ttl));
        }
        if _streq(kind, "require") {
          _edge_add(&mut edges, tgt, src, 0);
        } elif _streq(kind, "before") {
          _edge_add(&mut edges, src, tgt, 0);
        } elif _streq(kind, "notify") {
          _edge_add(&mut edges, src, tgt, 1);
        } elif _streq(kind, "subscribe") {
          _edge_add(&mut edges, tgt, src, 1);
        } else {
          return _catalog_err("puppet: unknown relationship kind: " + kind);
        }
      }
    } else {
      let st: Str = m.rel_src_type[j];
      let stl: Str = m.rel_src_title[j];
      let tt2: Str = m.rel_type[j];
      let ttl2: Str = m.rel_title[j];
      let sres = _cat_index(&c, st, stl);
      let tres = _cat_index(&c, tt2, ttl2);
      if sres < 0 && tres < 0 {
        // The chain is entirely outside the selected class: ignore it.
      } elif sres < 0 {
        return _catalog_err("puppet: unresolved reference: " + _ref_text(st, stl));
      } elif tres < 0 {
        return _catalog_err("puppet: unresolved reference: " + _ref_text(tt2, ttl2));
      } else {
        _edge_add(&mut edges, sres, tres, 0);
      }
    }
    j = j + 1;
  }
  let cn = c.res_type.len();
  var indeg = Vec[Int].new();
  z = 0;
  while z < cn {
    indeg.push(0);
    z = z + 1;
  }
  var k = 0;
  while k < edges.to.len() {
    let t2: Int = edges.to[k];
    indeg[t2] = indeg[t2] + 1;
    k = k + 1;
  }
  var placed = Vec[Int].new();
  z = 0;
  while z < cn {
    placed.push(0);
    z = z + 1;
  }
  var count = 0;
  while count < cn {
    var pick = -1;
    var q = 0;
    while q < cn {
      let d: Int = indeg[q];
      let pl: Int = placed[q];
      if d == 0 && pl == 0 {
        pick = q;
        break;
      }
      q = q + 1;
    }
    if pick < 0 {
      var u = 0;
      while u < cn {
        let pl2: Int = placed[u];
        if pl2 == 0 {
          let ct: Str = c.res_type[u];
          let ctl: Str = c.res_title[u];
          return _catalog_err("puppet: dependency cycle: " + _ref_text(ct, ctl));
        }
        u = u + 1;
      }
      return _catalog_err("puppet: dependency cycle");
    }
    placed[pick] = 1;
    c.order.push(pick);
    count = count + 1;
    var m2 = 0;
    while m2 < edges.from.len() {
      let f2: Int = edges.from[m2];
      if f2 == pick {
        let t3: Int = edges.to[m2];
        indeg[t3] = indeg[t3] - 1;
      }
      m2 = m2 + 1;
    }
  }
  var r = 0;
  while r < edges.from.len() {
    let f3: Int = edges.from[r];
    let t4: Int = edges.to[r];
    c.edge_from.push(f3);
    c.edge_to.push(t4);
    let rf: Int = edges.refresh[r];
    if rf != 0 {
      c.rf_from.push(f3);
      c.rf_to.push(t4);
    }
    r = r + 1;
  }
  return _catalog_ok(c);
}

/// Number of catalog resources.
pub fn puppet_catalog_len(c: &Catalog) -> Int {
  return c.res_type.len();
}

/// Resource type at index `i` ("" out of range).
pub fn puppet_catalog_type(c: &Catalog, i: Int) -> Str {
  return _safe_str(&c.res_type, i);
}

/// Resource title at index `i` ("" out of range).
pub fn puppet_catalog_title(c: &Catalog, i: Int) -> Str {
  return _safe_str(&c.res_title, i);
}

/// "type[title]" text of catalog resource `i`.
pub fn puppet_catalog_ref(c: &Catalog, i: Int) -> Str {
  return _ref_text(_safe_str(&c.res_type, i), _safe_str(&c.res_title, i));
}

/// Resource index at run position `pos`, or -1 out of range.
pub fn puppet_catalog_order(c: &Catalog, pos: Int) -> Int {
  return _safe_int(&c.order, pos);
}

/// First value of attribute `key` on catalog resource `i`, or None.
pub fn puppet_catalog_attr(c: &Catalog, i: Int, key: Str) -> Option[Str] {
  return _cat_attr(c, i, key);
}

/// Number of dependency edges.
pub fn puppet_catalog_edge_count(c: &Catalog) -> Int {
  return c.edge_from.len();
}

/// Dependency edge source / target (resource indices; -1 out of range).
pub fn puppet_catalog_edge_from(c: &Catalog, e: Int) -> Int {
  return _safe_int(&c.edge_from, e);
}

/// Dependency edge target (resource index; -1 out of range).
pub fn puppet_catalog_edge_to(c: &Catalog, e: Int) -> Int {
  return _safe_int(&c.edge_to, e);
}

/// Number of refresh edges.
pub fn puppet_catalog_refresh_count(c: &Catalog) -> Int {
  return c.rf_from.len();
}

/// Refresh edge source / target (resource indices; -1 out of range).
pub fn puppet_catalog_refresh_from(c: &Catalog, e: Int) -> Int {
  return _safe_int(&c.rf_from, e);
}

/// Refresh edge target (resource index; -1 out of range).
pub fn puppet_catalog_refresh_to(c: &Catalog, e: Int) -> Int {
  return _safe_int(&c.rf_to, e);
}

/// True for one of the seven supported resource types (package, service,
/// file, exec, user, group, notify).
pub fn puppet_known_type(t: Str) -> Bool {
  return _known_type(t);
}

// --------------------------------------------------
//  Host state and apply
// --------------------------------------------------

/// An empty host state.
pub fn puppet_state_new() -> State {
  return State{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

/// Current value of "type[title]" reference `ref`, or None.
pub fn puppet_state_get(s: &State, ref: Str) -> Option[Str] {
  let i = _vec_index(&s.keys, ref);
  if i < 0 {
    return None;
  }
  let v: Str = s.values[i];
  return Some(v);
}

/// Set "type[title]" reference `ref` to `value` (an existing entry is
/// replaced in place, a new one appended).
pub fn puppet_state_set(s: &mut State, ref: Str, value: Str) {
  let i = _vec_index(&s.keys, ref);
  if i >= 0 {
    s.values[i] = value;
    return;
  }
  s.keys.push(ref);
  s.values.push(value);
}

/// Number of known state entries.
pub fn puppet_state_len(s: &State) -> Int {
  return s.keys.len();
}

/// Apply catalog `c` to `state`, which is updated in place, and return the
/// run report. Resources run in catalog order, each at most once.
/// Classification per resource: a resource with a failed or skipped
/// dependency is skipped; the attribute fail == "true" fails it (simulated
/// provider failure, no state change); otherwise the desired ensure value
/// (attribute "ensure", default "present") is compared with the current
/// state: a mismatch, or a pending refresh from a changed notify / subscribe
/// partner, changes it and sets the state; a match leaves it unchanged.
/// A changed resource marks the targets of its refresh edges as pending.
pub fn puppet_apply(c: &Catalog, state: &mut State) -> Report {
  let n = c.res_type.len();
  var status = Vec[Int].new();
  var pending = Vec[Int].new();
  var z = 0;
  while z < n {
    status.push(_PP_ST_PENDING);
    pending.push(0);
    z = z + 1;
  }
  var events = Vec[Str].new();
  var provider_calls = 0;
  var refreshed = 0;
  var pos = 0;
  while pos < n {
    let ri: Int = c.order[pos];
    var blocked = false;
    var e = 0;
    while e < c.edge_from.len() {
      let t: Int = c.edge_to[e];
      if t == ri {
        let f: Int = c.edge_from[e];
        let st: Int = status[f];
        if st == _PP_ST_FAILED || st == _PP_ST_SKIPPED {
          blocked = true;
        }
      }
      e = e + 1;
    }
    let typ: Str = c.res_type[ri];
    let title: Str = c.res_title[ri];
    let ref = _ref_text(typ, title);
    if blocked {
      status[ri] = _PP_ST_SKIPPED;
      events.push("skipped: " + ref + " (dependency failed)");
    } else {
      var is_fail = false;
      let fo = _cat_attr(c, ri, "fail");
      match fo {
        Some(fv) => {
          if _streq(fv, "true") {
            is_fail = true;
          }
        },
        None => {},
      }
      if is_fail {
        status[ri] = _PP_ST_FAILED;
        events.push("failed: " + ref);
      } else {
        var desired = "present";
        let eo = _cat_attr(c, ri, "ensure");
        match eo {
          Some(ev) => { desired = ev; },
          None => {},
        }
        var cur = "";
        let co = puppet_state_get(state, ref);
        match co {
          Some(cv) => { cur = cv; },
          None => {},
        }
        if !_streq(cur, desired) {
          puppet_state_set(state, ref, desired);
          provider_calls = provider_calls + 1;
          status[ri] = _PP_ST_CHANGED;
          events.push("changed: " + ref);
        } elif pending[ri] != 0 {
          provider_calls = provider_calls + 1;
          refreshed = refreshed + 1;
          status[ri] = _PP_ST_CHANGED;
          events.push("refreshed: " + ref);
        } else {
          status[ri] = _PP_ST_UNCHANGED;
          events.push("unchanged: " + ref);
        }
        let after: Int = status[ri];
        if after == _PP_ST_CHANGED {
          var r = 0;
          while r < c.rf_from.len() {
            let f2: Int = c.rf_from[r];
            if f2 == ri {
              let t2: Int = c.rf_to[r];
              pending[t2] = 1;
            }
            r = r + 1;
          }
        }
      }
    }
    pos = pos + 1;
  }
  var changed = 0;
  var unchanged = 0;
  var skipped = 0;
  var failed = 0;
  var s = 0;
  while s < n {
    let st2: Int = status[s];
    if st2 == _PP_ST_CHANGED {
      changed = changed + 1;
    } elif st2 == _PP_ST_UNCHANGED {
      unchanged = unchanged + 1;
    } elif st2 == _PP_ST_SKIPPED {
      skipped = skipped + 1;
    } elif st2 == _PP_ST_FAILED {
      failed = failed + 1;
    }
    s = s + 1;
  }
  return Report{
    total: n;
    applied: changed + unchanged;
    changed: changed;
    unchanged: unchanged;
    skipped: skipped;
    failed: failed;
    provider_calls: provider_calls;
    refreshed: refreshed;
    events: events;
  };
}

/// Render a report: two header lines plus one "event: <e>" line per event,
/// LF separated, no trailing LF.
pub fn puppet_report_render(r: &Report) -> Str {
  var out = "puppet report: total=" + convert.int_to_string(r.total);
  out = out + " applied=" + convert.int_to_string(r.applied);
  out = out + " changed=" + convert.int_to_string(r.changed);
  out = out + " unchanged=" + convert.int_to_string(r.unchanged);
  out = out + " skipped=" + convert.int_to_string(r.skipped);
  out = out + " failed=" + convert.int_to_string(r.failed);
  out = out + "\nprovider_calls=" + convert.int_to_string(r.provider_calls);
  out = out + " refreshed=" + convert.int_to_string(r.refreshed);
  var i = 0;
  while i < r.events.len() {
    let ev: Str = r.events[i];
    out = out + "\nevent: " + ev;
    i = i + 1;
  }
  return out;
}
