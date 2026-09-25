// XIOM -- xiom.vcf: RFC 6350-subset vCard text codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact grammar, error catalog and test
// plan):
//   * content lines with an optional group: "group.NAME;PARAM=VAL:value";
//   * CRLF folding/unfolding: a physical line that starts with SPACE or TAB
//     continues the previous logical line; the terminator and that one
//     leading whitespace byte are removed when the line is rebuilt;
//   * text-value escaping: "\\", "\;", "\,", "\n" / "\N" (and tolerant
//     decoding of any other "\\X" as "X");
//   * BEGIN:VCARD / VERSION:3.0 or 4.0 / END:VCARD card envelopes, one card
//     per BEGIN..END sequence, with VERSION required as the first property;
//   * multi-card streams (vcf_parse_stream), kept flat because Vec[StructType]
//     is not usable in this compiler;
//   * building a card from FN / N / ORG / TEL / EMAIL / ADR fields and
//     re-serializing a parsed card (vcf_write / vcf_write_stream).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no self methods, no inline lambdas, no Vec[fn]
//     dispatch, no Vec[StructType].
//   * A card is a struct of parallel Vec[Str] fields; a stream is one flat
//     property list plus per-card index/count vectors (VCard / VCardStream).
//   * Ok/Err for every Result are constructed only in the tiny leaf helpers
//     _vcf_ok_* / _vcf_err_*.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec elements are read into explicitly typed locals first.
//   * Every byte read is widened once: (string.byte_at(s, i) as Int) & 0xFF,
//     so no UInt8 value is ever compared against an integer literal.

module xiom.vcf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[VCard, Str].
fn _vcf_ok_card(c: VCard) -> Result[VCard, Str] {
  return Ok(c);
}

// Err(m) for Result[VCard, Str].
fn _vcf_err_card(m: Str) -> Result[VCard, Str] {
  return Err(m);
}

// Ok(s) for Result[VCardStream, Str].
fn _vcf_ok_stream(s: VCardStream) -> Result[VCardStream, Str] {
  return Ok(s);
}

// Err(m) for Result[VCardStream, Str].
fn _vcf_err_stream(m: Str) -> Result[VCardStream, Str] {
  return Err(m);
}

// Ok(t) for Result[Str, Str].
fn _vcf_ok_text(t: Str) -> Result[Str, Str] {
  return Ok(t);
}

// Err(m) for Result[Str, Str].
fn _vcf_err_text(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _VCF_TAB: Int = 9;
const _VCF_LF: Int = 10;
const _VCF_CR: Int = 13;
const _VCF_SPACE: Int = 32;
const _VCF_DQUOTE: Int = 34;
const _VCF_COMMA: Int = 44;
const _VCF_HYPHEN: Int = 45;
const _VCF_DOT: Int = 46;
const _VCF_COLON: Int = 58;
const _VCF_SEMI: Int = 59;
const _VCF_BACKSLASH: Int = 92;
const _VCF_EQ: Int = 61;
const _VCF_n: Int = 110;
const _VCF_N: Int = 78;

// Maximum length of one physical line, in bytes (RFC 6350 recommends folding
// content lines longer than 75 octets).
const _VCF_FOLD: Int = 75;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One content line: optional `group`, uppercased `name`, the raw parameter
/// section `params` (e.g. `TYPE=WORK,VOICE`; "" when the line has none), the
/// unescaped `value`, and the original logical `raw` line.
pub type VcfProperty = {
  group: Str;
  name: Str;
  params: Str;
  value: Str;
  raw: Str;
}

/// One parsed vCard. `version` is "3.0" or "4.0"; the five vectors are
/// index-aligned and hold every property between VERSION and END:VCARD
/// (BEGIN, VERSION and END are structural and are not stored). `groups`,
/// `params` and `raws` are "" / "" / the logical line when not applicable.
pub type VCard = {
  version: Str;
  groups: Vec[Str];
  names: Vec[Str];
  params: Vec[Str];
  values: Vec[Str];
  raws: Vec[Str];
}

/// A parsed multi-card stream: `versions`, `firsts` and `counts` are
/// index-aligned per card (`firsts[i]` is the index of card i's first
/// property inside the shared property vectors, `counts[i]` how many
/// properties it has); the remaining vectors hold every property of every
/// card in document order.
pub type VCardStream = {
  versions: Vec[Str];
  firsts: Vec[Int];
  counts: Vec[Int];
  groups: Vec[Str];
  names: Vec[Str];
  params: Vec[Str];
  values: Vec[Str];
  raws: Vec[Str];
}

// The all-empty property returned for out-of-range access.
fn _vcf_empty_prop() -> VcfProperty {
  return VcfProperty{ group: ""; name: ""; params: ""; value: ""; raw: ""; };
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Read byte i of s widened to 0..255. Every byte read in this module goes
// through here.
fn _vcf_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII space or horizontal tab.
fn _vcf_is_ws(b: Int) -> Bool {
  return b == _VCF_SPACE || b == _VCF_TAB;
}

// True for the ASCII property/group/parameter-name alphabet: A-Z, a-z, 0-9
// and "-".
fn _vcf_is_token(b: Int) -> Bool {
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 97 && b <= 122 {
    return true;
  }
  if b >= 48 && b <= 57 {
    return true;
  }
  return b == _VCF_HYPHEN;
}

// ASCII uppercase of byte b; every other byte passes through untouched.
fn _vcf_upper_byte(b: Int) -> Int {
  if b >= 97 && b <= 122 {
    return b - 32;
  }
  return b;
}

// Byte-wise ASCII uppercase copy of s (bytes >= 0x80 pass through, so the
// byte length is preserved).
fn _vcf_upper(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(_vcf_upper_byte(_vcf_byte_at(s, i)) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// True when a and b are byte-equal (BUG 17: go through str_compare, never
// `==`).
fn _vcf_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when a and b are equal under ASCII case folding.
fn _vcf_streq_ci(a: Str, b: Str) -> Bool {
  return compare.str_compare_ignore_case(a, b) == 0;
}

// Index of the first occurrence of byte ch in s at or after `from`, or -1.
fn _vcf_find_byte(s: Str, from: Int, ch: Int) -> Int {
  let n = s.len();
  var i = from;
  while i < n {
    if _vcf_byte_at(s, i) == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Strip a leading UTF-8 byte-order mark, if present (tolerance for VCF files
// exported by tools that prepend EF BB BF).
fn _vcf_strip_bom(s: Str) -> Str {
  if s.len() >= 3 && _vcf_byte_at(s, 0) == 239 && _vcf_byte_at(s, 1) == 187 && _vcf_byte_at(s, 2) == 191 {
    return string.str_slice(s, 3, s.len());
  }
  return s;
}

// --------------------------------------------------
//  Fold / unfold
// --------------------------------------------------

// Split text into physical lines. A line ends at LF, CRLF or a lone CR; a
// final line without a terminator is still a line, and a trailing terminator
// does not produce an extra empty line.
fn _vcf_split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = text.len();
  if n == 0 {
    return out;
  }
  var start = 0;
  var i = 0;
  while i < n {
    let b = _vcf_byte_at(text, i);
    if b == _VCF_LF || b == _VCF_CR {
      out.push(string.str_slice(text, start, i));
      if b == _VCF_CR && i + 1 < n && _vcf_byte_at(text, i + 1) == _VCF_LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
      start = i;
    } else {
      i = i + 1;
    }
  }
  if start < n {
    out.push(string.str_slice(text, start, n));
  }
  return out;
}

// Unfold physical lines into logical lines: a line whose first byte is SPACE
// or TAB is appended to the previous logical line with its terminator and
// that one leading whitespace byte removed. A BOM on the very first line is
// ignored. A folding-whitespace-only continuation contributes nothing.
fn _vcf_unfold(phys: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < phys.len() {
    let raw: Str = phys[i];
    var merged = false;
    if out.len() > 0 && raw.len() > 0 && _vcf_is_ws(_vcf_byte_at(raw, 0)) {
      let last = out.len() - 1;
      let prev: Str = out[last];
      out[last] = prev + string.str_slice(raw, 1, raw.len());
      merged = true;
    }
    if !merged {
      if out.len() == 0 {
        out.push(_vcf_strip_bom(raw));
      } else {
        out.push(raw);
      }
    }
    i = i + 1;
  }
  return out;
}

// Fold one logical line into physical lines, each at most 75 bytes and
// terminated by CRLF; continuations start with one SPACE, so they carry at
// most 74 content bytes. Folding is byte-based and may split a multi-byte
// UTF-8 sequence (documented in SPEC.md).
fn _vcf_fold(line: Str) -> Str {
  let n = line.len();
  if n <= _VCF_FOLD {
    return line + "\r\n";
  }
  var out = "";
  var i = 0;
  var first = true;
  while i < n {
    var width = _VCF_FOLD;
    if !first {
      width = _VCF_FOLD - 1;
    }
    var end = i + width;
    if end > n {
      end = n;
    }
    if !first {
      out = out + " ";
    }
    out = out + string.str_slice(line, i, end) + "\r\n";
    first = false;
    i = end;
  }
  return out;
}

// --------------------------------------------------
//  Escaping
// --------------------------------------------------

// Append the escaped form of `value` to `out`. Always escapes backslash, CR
// and LF (with a canonical single "\n" per line break); `escape_semi` also
// escapes ";" and `escape_comma` also escapes ",". CRLF and lone CR are both
// encoded as "\n".
fn _vcf_escape_into(out: &mut Vec[UInt8], value: Str, escape_semi: Bool, escape_comma: Bool) {
  let n = value.len();
  var i = 0;
  while i < n {
    let b = _vcf_byte_at(value, i);
    if b == _VCF_BACKSLASH {
      out.push(_VCF_BACKSLASH as UInt8);
      out.push(_VCF_BACKSLASH as UInt8);
      i = i + 1;
    } elif b == _VCF_LF {
      out.push(_VCF_BACKSLASH as UInt8);
      out.push(_VCF_n as UInt8);
      i = i + 1;
    } elif b == _VCF_CR {
      out.push(_VCF_BACKSLASH as UInt8);
      out.push(_VCF_n as UInt8);
      if i + 1 < n && _vcf_byte_at(value, i + 1) == _VCF_LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
    } elif b == _VCF_SEMI && escape_semi {
      out.push(_VCF_BACKSLASH as UInt8);
      out.push(_VCF_SEMI as UInt8);
      i = i + 1;
    } elif b == _VCF_COMMA && escape_comma {
      out.push(_VCF_BACKSLASH as UInt8);
      out.push(_VCF_COMMA as UInt8);
      i = i + 1;
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
}

/// Escape a decoded text value for a content line: backslash, CR/LF (as
/// "\n") and the delimiters ";" and "," are backslash-escaped; every other
/// byte, including ":", passes through. Inverse of `vcf_unescape` on its
/// canonical output.
/// Error case: none.
/// Complexity: O(value.len()).
pub fn vcf_escape(value: Str) -> Str {
  var out = Vec[UInt8].new();
  _vcf_escape_into(&mut out, value, true, true);
  return builder.sb_to_str(&out);
}

/// Escape one component of a structured value (N, ADR): backslash, CR/LF (as
/// "\n") and "," are escaped, while ";" passes through because it is the
/// component separator. Use it (or `vcf_build_n` / `vcf_build_adr`) to build
/// structured values.
/// Error case: none.
/// Complexity: O(value.len()).
pub fn vcf_escape_component(value: Str) -> Str {
  var out = Vec[UInt8].new();
  _vcf_escape_into(&mut out, value, false, true);
  return builder.sb_to_str(&out);
}

/// Decode a content-line value: "\\" -> "\", "\n" and "\N" -> LF, "\;" ->
/// ";", "\," -> ",". Tolerant: any other "\X" decodes to X, and a trailing
/// lone "\" is kept verbatim.
/// Error case: none.
/// Complexity: O(value.len()).
pub fn vcf_unescape(value: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = value.len();
  var i = 0;
  while i < n {
    let b = _vcf_byte_at(value, i);
    if b == _VCF_BACKSLASH && i + 1 < n {
      let e = _vcf_byte_at(value, i + 1);
      if e == _VCF_n || e == _VCF_N {
        out.push(_VCF_LF as UInt8);
      } elif e == _VCF_SEMI {
        out.push(_VCF_SEMI as UInt8);
      } elif e == _VCF_COMMA {
        out.push(_VCF_COMMA as UInt8);
      } elif e == _VCF_BACKSLASH {
        out.push(_VCF_BACKSLASH as UInt8);
      } else {
        out.push(e as UInt8);
      }
      i = i + 2;
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Content-line scanning
// --------------------------------------------------

// Index of the value-separating ":" of a content line, found outside quoted
// parameter strings; -1 when there is none.
fn _vcf_value_colon(line: Str, from: Int) -> Int {
  let n = line.len();
  var i = from;
  var in_quote = false;
  while i < n {
    let b = _vcf_byte_at(line, i);
    if b == _VCF_DQUOTE {
      in_quote = !in_quote;
      i = i + 1;
    } elif b == _VCF_COLON && !in_quote {
      return i;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Scan one logical content line. Returns the parsed property, or the empty
// property (name == "") when the line is malformed: no name, an empty name
// after a group, a missing value colon, or unbalanced parameter quotes.
fn _vcf_scan_line(line: Str) -> VcfProperty {
  let n = line.len();
  if n == 0 {
    return _vcf_empty_prop();
  }
  var i = 0;
  while i < n && _vcf_is_token(_vcf_byte_at(line, i)) {
    i = i + 1;
  }
  if i == 0 {
    return _vcf_empty_prop();
  }
  var group = "";
  var name_start = 0;
  if i < n && _vcf_byte_at(line, i) == _VCF_DOT {
    group = string.str_slice(line, 0, i);
    i = i + 1;
    name_start = i;
    while i < n && _vcf_is_token(_vcf_byte_at(line, i)) {
      i = i + 1;
    }
    if i == name_start {
      return _vcf_empty_prop();
    }
  }
  let name = _vcf_upper(string.str_slice(line, name_start, i));
  var params = "";
  if i < n && _vcf_byte_at(line, i) == _VCF_SEMI {
    let colon = _vcf_value_colon(line, i);
    if colon < 0 {
      return _vcf_empty_prop();
    }
    params = string.str_slice(line, i + 1, colon);
    i = colon;
  }
  if i >= n || _vcf_byte_at(line, i) != _VCF_COLON {
    return _vcf_empty_prop();
  }
  let raw_value = string.str_slice(line, i + 1, n);
  return VcfProperty{ group: group; name: name; params: params; value: vcf_unescape(raw_value); raw: line; };
}

// True when p is a bare BEGIN:VCARD line (no group, no parameters).
fn _vcf_is_begin(p: VcfProperty) -> Bool {
  if p.group.len() != 0 || p.params.len() != 0 {
    return false;
  }
  if !_vcf_streq(p.name, "BEGIN") {
    return false;
  }
  return _vcf_streq_ci(p.value, "VCARD");
}

// True when p is a bare END:VCARD line (no group, no parameters).
fn _vcf_is_end(p: VcfProperty) -> Bool {
  if p.group.len() != 0 || p.params.len() != 0 {
    return false;
  }
  if !_vcf_streq(p.name, "END") {
    return false;
  }
  return _vcf_streq_ci(p.value, "VCARD");
}

// True when p is a bare VERSION property (no group, no parameters).
fn _vcf_is_version(p: VcfProperty) -> Bool {
  if p.group.len() != 0 || p.params.len() != 0 {
    return false;
  }
  return _vcf_streq(p.name, "VERSION");
}

// True for the supported version values "3.0" and "4.0".
fn _vcf_version_supported(v: Str) -> Bool {
  return _vcf_streq(v, "3.0") || _vcf_streq(v, "4.0");
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Parse unfolded logical lines into a stream. With `single`, exactly one card
// is accepted and any non-blank content after END:VCARD is an error; without
// it, one or more cards separated by blank lines are accepted.
fn _vcf_parse_lines(logical: &Vec[Str], single: Bool) -> Result[VCardStream, Str] {
  var s = VCardStream{
    versions: Vec[Str].new();
    firsts: Vec[Int].new();
    counts: Vec[Int].new();
    groups: Vec[Str].new();
    names: Vec[Str].new();
    params: Vec[Str].new();
    values: Vec[Str].new();
    raws: Vec[Str].new();
  };
  let nl = logical.len();
  var i = 0;
  var in_card = false;
  var seen_any = false;
  while i < nl {
    let line: Str = logical[i];
    if line.len() == 0 {
      i = i + 1;
    } elif !in_card {
      let p = _vcf_scan_line(line);
      if p.name.len() == 0 {
        return _vcf_err_stream("vcf: malformed content line: " + line);
      }
      if !_vcf_is_begin(p) {
        return _vcf_err_stream("vcf: expected BEGIN:VCARD, got: " + line);
      }
      s.versions.push("");
      s.firsts.push(s.names.len());
      s.counts.push(0);
      in_card = true;
      seen_any = true;
      i = i + 1;
    } else {
      let p = _vcf_scan_line(line);
      if p.name.len() == 0 {
        return _vcf_err_stream("vcf: malformed content line: " + line);
      }
      if _vcf_is_begin(p) {
        return _vcf_err_stream("vcf: nested BEGIN:VCARD");
      }
      if _vcf_is_end(p) {
        let ci = s.versions.len() - 1;
        let vv: Str = s.versions[ci];
        if vv.len() == 0 {
          return _vcf_err_stream("vcf: missing VERSION");
        }
        in_card = false;
        i = i + 1;
        if single {
          var j = i;
          while j < nl {
            let rest: Str = logical[j];
            if rest.len() > 0 {
              return _vcf_err_stream("vcf: unexpected content after END:VCARD: " + rest);
            }
            j = j + 1;
          }
          i = nl;
        }
      } elif _vcf_is_version(p) {
        let ci = s.versions.len() - 1;
        let prev: Str = s.versions[ci];
        if prev.len() != 0 {
          return _vcf_err_stream("vcf: duplicate VERSION");
        }
        if !_vcf_version_supported(p.value) {
          return _vcf_err_stream("vcf: unsupported version: " + p.value);
        }
        s.versions[ci] = p.value;
        i = i + 1;
      } else {
        let ci = s.counts.len() - 1;
        let vv: Str = s.versions[ci];
        if vv.len() == 0 {
          return _vcf_err_stream("vcf: missing VERSION");
        }
        let cnt: Int = s.counts[ci];
        s.groups.push(p.group);
        s.names.push(p.name);
        s.params.push(p.params);
        s.values.push(p.value);
        s.raws.push(line);
        s.counts[ci] = cnt + 1;
        i = i + 1;
      }
    }
  }
  if in_card {
    return _vcf_err_stream("vcf: missing END:VCARD");
  }
  if !seen_any {
    return _vcf_err_stream("vcf: empty input");
  }
  return _vcf_ok_stream(s);
}

// Copy card `card` of a stream into a standalone VCard (empty when the index
// is out of range).
fn _vcf_card_at(s: &VCardStream, card: Int) -> VCard {
  var c = VCard{
    version: "";
    groups: Vec[Str].new();
    names: Vec[Str].new();
    params: Vec[Str].new();
    values: Vec[Str].new();
    raws: Vec[Str].new();
  };
  if card < 0 || card >= s.versions.len() {
    return c;
  }
  let v: Str = s.versions[card];
  c.version = v;
  let first: Int = s.firsts[card];
  let count: Int = s.counts[card];
  var j = 0;
  while j < count {
    let k = first + j;
    let g: Str = s.groups[k];
    let nm: Str = s.names[k];
    let pp: Str = s.params[k];
    let vv: Str = s.values[k];
    let rr: Str = s.raws[k];
    c.groups.push(g);
    c.names.push(nm);
    c.params.push(pp);
    c.values.push(vv);
    c.raws.push(rr);
    j = j + 1;
  }
  return c;
}

/// Parse exactly one vCard from text, ignoring blank lines before and after
/// it. End-of-line tolerance: CRLF, LF and lone CR all terminate lines; a BOM
/// on the first line is ignored.
/// Params: text - the card text (BEGIN:VCARD ... END:VCARD).
/// Returns: Ok(VCard) when the text holds one well-formed card with
/// VERSION:3.0 or VERSION:4.0 as its first property; Err("vcf: ...")
/// otherwise (see SPEC.md's error catalog).
/// Complexity: O(text length).
pub fn vcf_parse_card(text: Str) -> Result[VCard, Str] {
  let logical = _vcf_unfold(_vcf_split_lines(text));
  let r = _vcf_parse_lines(&logical, true);
  match r {
    Ok(s) => { return _vcf_ok_card(_vcf_card_at(&s, 0)); },
    Err(m) => { return _vcf_err_card(m); },
  }
  return _vcf_err_card("vcf: empty input");
}

/// Parse a stream of one or more vCards, in order, separated by any number of
/// blank lines.
/// Params: text - the whole stream.
/// Returns: Ok(VCardStream) when every card is well-formed; Err("vcf: ...")
/// otherwise. The stream keeps all cards in one flat property list plus
/// per-card `firsts` / `counts` vectors; use `vcf_stream_*` to read it.
/// Complexity: O(text length).
pub fn vcf_parse_stream(text: Str) -> Result[VCardStream, Str] {
  let logical = _vcf_unfold(_vcf_split_lines(text));
  return _vcf_parse_lines(&logical, false);
}

// --------------------------------------------------
//  Model accessors
// --------------------------------------------------

/// Number of stored properties of a card (BEGIN, VERSION and END are not
/// counted).
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_property_count(v: &VCard) -> Int {
  return v.names.len();
}

/// Property i of a card, in document order.
/// Params: v - the card; i - zero-based property index.
/// Returns: the property; the all-empty property when i is out of range
/// (check `name`).
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_property(v: &VCard, i: Int) -> VcfProperty {
  if i < 0 || i >= v.names.len() {
    return _vcf_empty_prop();
  }
  let g: Str = v.groups[i];
  let nm: Str = v.names[i];
  let pp: Str = v.params[i];
  let vv: Str = v.values[i];
  let rr: Str = v.raws[i];
  return VcfProperty{ group: g; name: nm; params: pp; value: vv; raw: rr; };
}

/// Index of the first property whose uppercased name equals the uppercased
/// `name`; -1 when absent.
/// Error case: none.
/// Complexity: O(property count).
pub fn vcf_prop_index(v: &VCard, name: Str) -> Int {
  let want = _vcf_upper(name);
  var i = 0;
  while i < v.names.len() {
    let k: Str = v.names[i];
    if _vcf_streq(k, want) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// First value of the first property named `name` (case-insensitive), or
/// None when the card has no such property.
/// Error case: none.
/// Complexity: O(property count).
pub fn vcf_prop_value(v: &VCard, name: Str) -> Option[Str] {
  let i = vcf_prop_index(v, name);
  if i < 0 {
    return None;
  }
  let val: Str = v.values[i];
  return Some(val);
}

/// Every value of the properties named `name` (case-insensitive), in document
/// order; an empty vector when there are none.
/// Error case: none.
/// Complexity: O(property count).
pub fn vcf_props_all(v: &VCard, name: Str) -> Vec[Str] {
  let want = _vcf_upper(name);
  var out = Vec[Str].new();
  var i = 0;
  while i < v.names.len() {
    let k: Str = v.names[i];
    if _vcf_streq(k, want) {
      let val: Str = v.values[i];
      out.push(val);
    }
    i = i + 1;
  }
  return out;
}

// Index of the first "," in s at or after `from` that is outside quoted
// strings, or s.len().
fn _vcf_comma_outside_quotes(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  var in_quote = false;
  while i < n {
    let b = _vcf_byte_at(s, i);
    if b == _VCF_DQUOTE {
      in_quote = !in_quote;
      i = i + 1;
    } elif b == _VCF_COMMA && !in_quote {
      return i;
    } else {
      i = i + 1;
    }
  }
  return n;
}

/// First value of parameter `pname` on property i (case-insensitive). A
/// quoted parameter value loses its surrounding double quotes; for a
/// comma-separated value list only the first value is returned. Each
/// `;`-separated parameter segment is scanned tolerantly: a segment without
/// "=" is skipped, and an empty parameter section yields None.
/// Params: v - the card; i - property index; pname - parameter name.
/// Returns: Some(value) on a hit, None when the property or parameter is
/// absent.
/// Error case: none.
/// Complexity: O(parameter text length).
pub fn vcf_param_value(v: &VCard, i: Int, pname: Str) -> Option[Str] {
  if i < 0 || i >= v.params.len() {
    return None;
  }
  let text: Str = v.params[i];
  let n = text.len();
  var seg_start = 0;
  var j = 0;
  var in_quote = false;
  while j <= n {
    let at_end = j == n;
    var is_sep = false;
    if !at_end {
      let b = _vcf_byte_at(text, j);
      if b == _VCF_DQUOTE {
        in_quote = !in_quote;
      } elif b == _VCF_SEMI && !in_quote {
        is_sep = true;
      }
    }
    if at_end || is_sep {
      let seg = string.str_slice(text, seg_start, j);
      let eq = _vcf_find_byte(seg, 0, _VCF_EQ);
      if eq > 0 {
        let key = string.str_slice(seg, 0, eq);
        if _vcf_streq_ci(key, pname) {
          let rest = string.str_slice(seg, eq + 1, seg.len());
          let cut = _vcf_comma_outside_quotes(rest, 0);
          let first = string.str_slice(rest, 0, cut);
          if first.len() >= 2 && _vcf_byte_at(first, 0) == _VCF_DQUOTE && _vcf_byte_at(first, first.len() - 1) == _VCF_DQUOTE {
            return Some(string.str_slice(first, 1, first.len() - 1));
          }
          return Some(first);
        }
      }
      seg_start = j + 1;
    }
    j = j + 1;
  }
  return None;
}

/// Version of card `i` of a stream ("3.0" or "4.0"), or "" when the index is
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_stream_version(s: &VCardStream, i: Int) -> Str {
  if i < 0 || i >= s.versions.len() {
    return "";
  }
  let v: Str = s.versions[i];
  return v;
}

/// Number of cards in a stream.
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_stream_count(s: &VCardStream) -> Int {
  return s.versions.len();
}

/// Number of stored properties of card `i`, or 0 when the index is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_stream_property_count(s: &VCardStream, i: Int) -> Int {
  if i < 0 || i >= s.counts.len() {
    return 0;
  }
  let c: Int = s.counts[i];
  return c;
}

/// Property `idx` of card `i` of a stream.
/// Params: s - the stream; card - zero-based card index; idx - zero-based
/// property index inside that card.
/// Returns: the property; the all-empty property when either index is out of
/// range (check `name`).
/// Error case: none.
/// Complexity: O(1).
pub fn vcf_stream_property(s: &VCardStream, card: Int, idx: Int) -> VcfProperty {
  if card < 0 || card >= s.versions.len() {
    return _vcf_empty_prop();
  }
  if idx < 0 {
    return _vcf_empty_prop();
  }
  let count: Int = s.counts[card];
  if idx >= count {
    return _vcf_empty_prop();
  }
  let k = s.firsts[card] + idx;
  let g: Str = s.groups[k];
  let nm: Str = s.names[k];
  let pp: Str = s.params[k];
  let vv: Str = s.values[k];
  let rr: Str = s.raws[k];
  return VcfProperty{ group: g; name: nm; params: pp; value: vv; raw: rr; };
}

// --------------------------------------------------
//  Building and writing
// --------------------------------------------------

/// Join the five decoded N components (family, given, additional, prefix,
/// suffix) with ";" after escaping each one with `vcf_escape_component`.
/// Error case: none.
/// Complexity: O(total component length).
pub fn vcf_build_n(family: Str, given: Str, additional: Str, prefix: Str, suffix: Str) -> Str {
  return vcf_escape_component(family) + ";" + vcf_escape_component(given) + ";" + vcf_escape_component(additional) + ";" + vcf_escape_component(prefix) + ";" + vcf_escape_component(suffix);
}

/// Join the seven decoded ADR components (post office box, extended address,
/// street, locality, region, postal code, country) with ";" after escaping
/// each one with `vcf_escape_component`.
/// Error case: none.
/// Complexity: O(total component length).
pub fn vcf_build_adr(pobox: Str, ext: Str, street: Str, locality: Str, region: Str, code: Str, country: Str) -> Str {
  return vcf_escape_component(pobox) + ";" + vcf_escape_component(ext) + ";" + vcf_escape_component(street) + ";" + vcf_escape_component(locality) + ";" + vcf_escape_component(region) + ";" + vcf_escape_component(code) + ";" + vcf_escape_component(country);
}

/// Build a complete vCard text (CRLF line endings, folded at 75 bytes) from
/// the common contact fields. FN, ORG, TEL and EMAIL are decoded text values
/// and are escaped with `vcf_escape`; N and ADR are already-escaped structured
/// values emitted verbatim, so build them with `vcf_build_n` /
/// `vcf_build_adr`. ORG, TEL, EMAIL, N and ADR are omitted when empty.
/// Params: version - "3.0" or "4.0"; formatted_name - the FN value
/// (required).
/// Returns: Ok(card text) with BEGIN:VCARD, VERSION, the present fields in
/// FN/N/ORG/TEL/EMAIL/ADR order and END:VCARD, each line CRLF-terminated.
/// Err("vcf: unsupported version: <version>") when version is neither "3.0"
/// nor "4.0"; Err("vcf: FN is required") when formatted_name is empty.
/// Complexity: O(total field length).
pub fn vcf_build_card(version: Str, formatted_name: Str, n: Str, org: Str, tel: Str, email: Str, adr: Str) -> Result[Str, Str] {
  if !_vcf_version_supported(version) {
    return _vcf_err_text("vcf: unsupported version: " + version);
  }
  if formatted_name.len() == 0 {
    return _vcf_err_text("vcf: FN is required");
  }
  var out = _vcf_fold("BEGIN:VCARD");
  out = out + _vcf_fold("VERSION:" + version);
  out = out + _vcf_fold("FN:" + vcf_escape(formatted_name));
  if n.len() > 0 {
    out = out + _vcf_fold("N:" + n);
  }
  if org.len() > 0 {
    out = out + _vcf_fold("ORG:" + vcf_escape(org));
  }
  if tel.len() > 0 {
    out = out + _vcf_fold("TEL:" + vcf_escape(tel));
  }
  if email.len() > 0 {
    out = out + _vcf_fold("EMAIL:" + vcf_escape(email));
  }
  if adr.len() > 0 {
    out = out + _vcf_fold("ADR:" + adr);
  }
  out = out + _vcf_fold("END:VCARD");
  return _vcf_ok_text(out);
}

// Escape one property value for writing: N and ADR keep their ";" component
// separators (component escaping), every other property uses full text
// escaping.
fn _vcf_write_value(name: Str, value: Str) -> Str {
  if _vcf_streq(name, "N") || _vcf_streq(name, "ADR") {
    return vcf_escape_component(value);
  }
  return vcf_escape(value);
}

/// Serialize a parsed card back to vCard text: BEGIN:VCARD, VERSION from
/// `v.version`, every stored property in document order, then END:VCARD.
/// Lines are folded at 75 bytes and terminated by CRLF. Values are
/// re-escaped; N and ADR are treated as structured values (their ";" bytes
/// are preserved, embedded "," and "\" are escaped), all other properties get
/// full text escaping. Property names are written uppercased.
/// Params: v - the card (typically from `vcf_parse_card`).
/// Returns: the card text.
/// Error case: none.
/// Complexity: O(total text length).
pub fn vcf_write(v: &VCard) -> Str {
  var out = _vcf_fold("BEGIN:VCARD");
  out = out + _vcf_fold("VERSION:" + v.version);
  var i = 0;
  while i < v.names.len() {
    let nm: Str = v.names[i];
    let g: Str = v.groups[i];
    let pp: Str = v.params[i];
    let val: Str = v.values[i];
    var head = "";
    if g.len() > 0 {
      head = g + ".";
    }
    head = head + nm;
    if pp.len() > 0 {
      head = head + ";" + pp;
    }
    out = out + _vcf_fold(head + ":" + _vcf_write_value(nm, val));
    i = i + 1;
  }
  out = out + _vcf_fold("END:VCARD");
  return out;
}

/// Serialize every card of a stream, in order (the concatenation of
/// `vcf_write` over the cards).
/// Error case: none.
/// Complexity: O(total text length).
pub fn vcf_write_stream(s: &VCardStream) -> Str {
  var out = "";
  var c = 0;
  let cards = s.versions.len();
  while c < cards {
    let card = _vcf_card_at(s, c);
    out = out + vcf_write(&card);
    c = c + 1;
  }
  return out;
}
