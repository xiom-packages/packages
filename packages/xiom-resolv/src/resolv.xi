// XIOM -- xiom.resolv: resolv.conf codec (directives, lexical address/mask
// validation, flat document model and canonical emitter)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed resolv.conf document is the flat ResolvConf struct:
// `nameservers` (document order), `domain` (one string, "" when absent),
// `search` (the last search list), `options` (every option token in document
// order), the parallel pair `sortlist_addrs`/`sortlist_masks` (entry i has
// address sortlist_addrs[i] and mask sortlist_masks[i], where -1 means "no
// /mask was written"), and `unknown` (preserved raw logical lines).
// Vec[StructType] is unsupported in this compiler, so the document is
// deliberately flat instead of a vector of directive structs.
//
// Documented subset (see SPEC.md for the exact grammar):
//   * directives are whitespace-separated tokens on a logical line:
//     `nameserver <addr>`, `domain <name>`, `search <name> [<name> ...]`,
//     `options <opt> [<opt> ...]` and `sortlist <entry> [<entry> ...]`;
//   * `nameserver` takes exactly one address and every line appends to the
//     document, so more than the classic three nameservers is accepted;
//     resolv_nameserver_over_limit is a purely informational predicate;
//   * `domain` and `search` are last-directive-wins: each new directive
//     replaces the stored value/list (this library attaches no lookup
//     semantics to them);
//   * `options` tokens are `name` or `name:value` with a non-empty name and
//     a non-empty value and at most one colon; they are preserved verbatim
//     and resolv_option_index implements first-match-by-name lookup;
//   * `sortlist` entries are `addr` or `addr/n` where n is a canonical
//     decimal mask with no leading zeros, 0..32 for an IPv4 address and
//     0..128 for an IPv6 address;
//   * addresses use the documented lexical subset: IPv4 is four decimal
//     octets 0..255 with no leading zeros; IPv6 is at most one `::`, exactly
//     eight groups after expansion (the `::` stands for at least one group),
//     1..4 hex digits per group, no empty group, no zone ID, and an embedded
//     dotted quad only as the final 32 bits; storage/emission is the input
//     text lowercased ("0:0:0:0:0:0:0:1" stays uncompressed);
//   * comments start at the first `#` or `;` byte (there is no quoting, so
//     they cut even mid-token); blank lines and both LF and CRLF endings are
//     accepted, and a missing final newline is fine;
//   * a physical line whose comment-stripped text ends with a backslash is
//     joined directly (no inserted separator) with the next physical line;
//     a backslash on the final physical line of the input is an error;
//   * `lookup` and `family` are legacy directives, and any other keyword is
//     unrecognized; neither is an error: their logical lines are preserved
//     verbatim (comments removed, ends trimmed) in the `unknown` pool and
//     re-emitted in document order;
//   * a physical line longer than 4096 bytes (excluding the terminator) and
//     any control byte other than TAB (and the CR of a CRLF pair) are errors.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     _rv_byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF` before
//     any comparison (a raw UInt8 compared against a constant >= 128
//     miscompiles);
//   * no `==` on Str values read from Vec[Str] elements; each is bound to a
//     typed local first and compared with compare.str_compare (BUG 17);
//   * Ok/Err for the struct-payload Result are constructed only in the leaf
//     helpers _rv_ok/_rv_err; _rv_process returns an error message string
//     instead of building a Result of its own;
//   * every push on the parallel sortlist vectors happens in one place, so
//     they cannot drift; accessors clamp against mismatched lengths.
//
// See SPEC.md for the model, grammar, error catalog and test plan.

module xiom.resolv

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed resolv.conf document. `nameservers`, `search`, `options` and
/// `unknown` are flat pools in document order; `domain` is "" when no
/// `domain` directive was present (the last one wins); sortlist entry i is
/// the pair (sortlist_addrs[i], sortlist_masks[i]) where a mask of -1 means
/// the entry was written without `/n`. Vec[StructType] is unsupported in
/// this compiler, so the model is deliberately flat.
pub type ResolvConf = {
  nameservers: Vec[Str];
  domain: Str;
  search: Vec[Str];
  options: Vec[Str];
  sortlist_addrs: Vec[Str];
  sortlist_masks: Vec[Int];
  unknown: Vec[Str];
}

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

// ASCII codes used by the scanners (all compared in Int space).
const _RV_TAB: Int = 9;
const _RV_LF: Int = 10;
const _RV_CR: Int = 13;
const _RV_SPACE: Int = 32;
const _RV_HASH: Int = 35;
const _RV_DOT: Int = 46;
const _RV_SLASH: Int = 47;
const _RV_ZERO: Int = 48;
const _RV_COLON: Int = 58;
const _RV_SEMI: Int = 59;
const _RV_BS: Int = 92;
const _RV_DEL: Int = 127;

// Longest accepted physical line, excluding the line terminator.
const _RV_MAX_LINE: Int = 4096;
// Classic (informational) nameserver limit; parsing never enforces it.
const _RV_CLASSIC_NS_LIMIT: Int = 3;
// Mask caps per address family.
const _RV_MAX_MASK4: Int = 32;
const _RV_MAX_MASK6: Int = 128;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _rv_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _rv_is_space(c: Int) -> Bool {
  return c == _RV_SPACE || c == _RV_TAB;
}

fn _rv_is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

fn _rv_hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// True when s[start, stop) contains at least one '.'.
fn _rv_has_dot(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    if _rv_byte_at(s, i) == _RV_DOT { return true; }
    i = i + 1;
  }
  return false;
}

// True when s contains at least one ':'.
fn _rv_has_colon(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _rv_byte_at(s, i) == _RV_COLON { return true; }
    i = i + 1;
  }
  return false;
}

// Byte index of the first '/' in s, or -1.
fn _rv_slash_index(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _rv_byte_at(s, i) == _RV_SLASH { return i; }
    i = i + 1;
  }
  return -1;
}

// Byte index of the first ':' in s, or -1.
fn _rv_colon_index(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _rv_byte_at(s, i) == _RV_COLON { return i; }
    i = i + 1;
  }
  return -1;
}

// String equality through the stdlib comparator (never `==` on Str).
fn _rv_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Index of the first comment byte ('#' or ';') in s[start, stop), or stop
// when the whole slice is content.
fn _rv_find_comment(s: Str, start: Int, stop: Int) -> Int {
  var i = start;
  while i < stop {
    let c = _rv_byte_at(s, i);
    if c == _RV_HASH || c == _RV_SEMI { return i; }
    i = i + 1;
  }
  return stop;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 constructors for the struct-payload Result: Ok/Err are built only
// in these tiny wrappers, never inside a larger function.

fn _rv_ok(d: ResolvConf) -> Result[ResolvConf, Str] {
  return Ok(d);
}

fn _rv_err(m: Str) -> Result[ResolvConf, Str] {
  return Err(m);
}

// --------------------------------------------------
//  IPv4
// --------------------------------------------------

// True when s[start, stop) is exactly four decimal octets 0..255 with no
// leading zero on a multi-digit octet.
fn _rv_quad_ok(s: Str, start: Int, stop: Int) -> Bool {
  if start >= stop { return false; }
  var parts = 0;
  var octet = 0;
  var digits = 0;
  var lead_zero = false;
  var i = start;
  while i < stop {
    let c = _rv_byte_at(s, i);
    if c == _RV_DOT {
      if digits == 0 { return false; }
      if digits > 1 && lead_zero { return false; }
      parts = parts + 1;
      if parts > 3 { return false; }
      octet = 0;
      digits = 0;
      lead_zero = false;
    } else {
      if !_rv_is_digit(c) { return false; }
      if digits == 0 && c == _RV_ZERO { lead_zero = true; }
      octet = octet * 10 + (c - _RV_ZERO);
      if octet > 255 { return false; }
      digits = digits + 1;
      if digits > 3 { return false; }
    }
    i = i + 1;
  }
  if digits == 0 { return false; }
  if digits > 1 && lead_zero { return false; }
  parts = parts + 1;
  return parts == 4;
}

// --------------------------------------------------
//  IPv6
// --------------------------------------------------

// True when s[start, stop) is a hex group of 1..4 digits.
fn _rv_hex_group_ok(s: Str, start: Int, stop: Int) -> Bool {
  let len = stop - start;
  if len < 1 || len > 4 { return false; }
  var i = start;
  while i < stop {
    let h = _rv_hex_value(_rv_byte_at(s, i));
    if h < 0 { return false; }
    i = i + 1;
  }
  return true;
}

// Number of 16-bit groups in s[start, stop): a hex token is one group, an
// embedded dotted quad (only allowed as the last token when `allow_v4_tail`
// is true) is two groups, and an empty slice is zero groups (only legal
// around `::`). Returns -1 when the slice is malformed: an empty token, a
// trailing single ':', an over-long or non-hex group, or a dotted quad in a
// position other than a permitted final tail.
fn _rv_count_groups(v: Str, start: Int, stop: Int, allow_v4_tail: Bool) -> Int {
  if start >= stop { return 0; }
  var count = 0;
  var i = start;
  while i < stop {
    var j = i;
    while j < stop && _rv_byte_at(v, j) != _RV_COLON { j = j + 1; }
    if j == i { return -1; }
    let last = j == stop;
    if _rv_has_dot(v, i, j) {
      if !last || !allow_v4_tail { return -1; }
      if !_rv_quad_ok(v, i, j) { return -1; }
      count = count + 2;
    } else {
      if !_rv_hex_group_ok(v, i, j) { return -1; }
      count = count + 1;
    }
    if last { return count; }
    i = j + 1;
    if i >= stop { return -1; }
  }
  return count;
}

// True when s is an IPv6 address in the documented subset: at most one `::`,
// exactly eight groups after expansion, `::` standing for at least one group,
// no zone ID, and an embedded dotted quad only as the final 32 bits.
fn _rv_ipv6_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var dbl = -1;
  var dbl_count = 0;
  var i = 0;
  while i + 1 < n {
    if _rv_byte_at(s, i) == _RV_COLON && _rv_byte_at(s, i + 1) == _RV_COLON {
      if dbl < 0 { dbl = i; }
      dbl_count = dbl_count + 1;
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  if dbl_count > 1 { return false; }
  if dbl < 0 {
    return _rv_count_groups(s, 0, n, true) == 8;
  }
  let head = _rv_count_groups(s, 0, dbl, false);
  if head < 0 { return false; }
  let tail = _rv_count_groups(s, dbl + 2, n, true);
  if tail < 0 { return false; }
  return head + tail <= 7;
}

// --------------------------------------------------
//  Address normalization
// --------------------------------------------------

/// Canonicalize an IPv4 or IPv6 candidate address.
/// Params: s - candidate address text.
/// Returns: Some(text) with the documented normalization, or None when s is
/// not a valid address. IPv4 ("a.b.c.d", four decimal octets 0..255, no
/// leading zeros) is returned unchanged. IPv6 is returned lowercased; it is
/// not compressed, so "0:0:0:0:0:0:0:1" and "::ffff:192.168.1.1" keep their
/// spelling apart from case. No zone IDs (`%...`) are accepted.
/// Error case: none (the parser turns None into Err("resolv: bad address:
/// ...")).
/// Examples: "2001:DB8:0:0:0:0:0:1" -> Some("2001:db8:0:0:0:0:0:1");
/// "::1" -> Some("::1"); "256.0.0.1" -> None; "" -> None.
/// Complexity: O(s.len()).
pub fn resolv_address_normalize(s: Str) -> Option[Str] {
  if _rv_has_colon(s) {
    if !_rv_ipv6_ok(s) { return None; }
    return Some(string.str_lower(s));
  }
  if _rv_has_dot(s, 0, s.len()) {
    if _rv_quad_ok(s, 0, s.len()) { return Some(s); }
  }
  return None;
}

/// True when s is a valid address in the documented subset.
/// Params: s - candidate address text.
/// Returns: true for a valid IPv4 dotted quad or documented-subset IPv6
/// address; false otherwise. Equivalent to "resolv_address_normalize(s) is
/// Some".
/// Error case: none.
/// Examples: "1.2.3.4" -> true; "::1" -> true; "::ffff:1.2.3.4" -> true;
/// "1.2.3.256" -> false; "1.2.3.4/24" -> false.
/// Complexity: O(s.len()).
pub fn resolv_address_valid(s: Str) -> Bool {
  let o = resolv_address_normalize(s);
  return o.is_some;
}

// --------------------------------------------------
//  Options
// --------------------------------------------------

// True when s is a documented option token: `name` or `name:value` with a
// non-empty name, a non-empty value and at most one colon. Any other
// non-whitespace byte is allowed (comments already cut the token).
fn _rv_option_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  let c = _rv_colon_index(s);
  if c < 0 { return true; }
  if c == 0 { return false; }
  if c == n - 1 { return false; }
  var i = c + 1;
  while i < n {
    if _rv_byte_at(s, i) == _RV_COLON { return false; }
    i = i + 1;
  }
  return true;
}

// Name part of an option token: everything before the first colon, or the
// whole token when there is none.
fn _rv_option_name_of(s: Str) -> Str {
  let c = _rv_colon_index(s);
  if c < 0 { return s; }
  return string.str_slice(s, 0, c);
}

// Value part of an option token: Some(text after the first colon), or None
// when the token has no colon.
fn _rv_option_value_of(s: Str) -> Option[Str] {
  let c = _rv_colon_index(s);
  if c < 0 { return None; }
  return Some(string.str_slice(s, c + 1, s.len()));
}

// --------------------------------------------------
//  Mask scanning
// --------------------------------------------------

// Value of a canonical decimal mask token: at least one digit, "0" allowed,
// no leading zero on a multi-digit value. Accumulation stops once the value
// exceeds 128, so arbitrarily long digit runs cannot overflow; the caller
// range-checks the result against the address family. Returns -1 for an
// empty slice, a leading zero or a non-digit byte.
fn _rv_scan_mask(s: Str) -> Int {
  let n = s.len();
  if n == 0 { return -1; }
  if n > 1 && _rv_byte_at(s, 0) == _RV_ZERO { return -1; }
  var v = 0;
  var i = 0;
  while i < n {
    let c = _rv_byte_at(s, i);
    if !_rv_is_digit(c) { return -1; }
    if v <= _RV_MAX_MASK6 { v = v * 10 + (c - _RV_ZERO); }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Line scanning
// --------------------------------------------------

// True when s[start, stop) contains a byte that is neither printable ASCII
// nor TAB: bytes 0..31 (TAB excepted) and DEL. A CR is only legal as the CR
// of a CRLF pair, which the caller strips before calling this.
fn _rv_line_has_control(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    let c = _rv_byte_at(s, i);
    if c < 32 && c != _RV_TAB { return true; }
    if c == _RV_DEL { return true; }
    i = i + 1;
  }
  return false;
}

// Append the whitespace-separated tokens of s[start, stop) to `out`.
fn _rv_split_tokens(s: Str, start: Int, stop: Int, out: &mut Vec[Str]) {
  var i = start;
  while i < stop {
    while i < stop && _rv_is_space(_rv_byte_at(s, i)) { i = i + 1; }
    if i >= stop { break; }
    var j = i;
    while j < stop && !_rv_is_space(_rv_byte_at(s, j)) { j = j + 1; }
    out.push(string.str_slice(s, i, j));
    i = j;
  }
}

// --------------------------------------------------
//  Logical-line processing
// --------------------------------------------------

// Apply one comment-stripped, continuation-joined logical line to `doc`.
// Returns "" on success (including a blank line, which contributes nothing),
// or the exact error message; the caller wraps it with _rv_err.
//
// Check order inside a directive: argument count first, then the arguments
// left to right. For a sortlist entry the checks run mask syntax, address,
// then mask range against the address family. Unknown or legacy keywords
// (`lookup`, `family`, anything else) never fail: the trimmed line is kept
// verbatim in the unknown pool.
fn _rv_process(doc: &mut ResolvConf, text: Str) -> Str {
  var tokens = Vec[Str].new();
  _rv_split_tokens(text, 0, text.len(), &mut tokens);
  if tokens.len() == 0 { return ""; }
  let kw: Str = tokens[0];

  if _rv_streq(kw, "nameserver") {
    if tokens.len() < 2 {
      return "resolv: empty directive value: " + kw;
    }
    if tokens.len() > 2 {
      let extra: Str = tokens[2];
      return "resolv: unexpected argument: " + extra;
    }
    let raw: Str = tokens[1];
    let norm = resolv_address_normalize(raw);
    var canon = "";
    match norm {
      Some(a) => { canon = a; },
      None => { return "resolv: bad address: " + raw; },
    }
    doc.nameservers.push(canon);
    return "";
  }

  if _rv_streq(kw, "domain") {
    if tokens.len() < 2 {
      return "resolv: empty directive value: " + kw;
    }
    if tokens.len() > 2 {
      let extra: Str = tokens[2];
      return "resolv: unexpected argument: " + extra;
    }
    let nm: Str = tokens[1];
    doc.domain = nm;
    return "";
  }

  if _rv_streq(kw, "search") {
    if tokens.len() < 2 {
      return "resolv: empty directive value: " + kw;
    }
    doc.search = Vec[Str].new();
    var k = 1;
    while k < tokens.len() {
      let nm: Str = tokens[k];
      doc.search.push(nm);
      k = k + 1;
    }
    return "";
  }

  if _rv_streq(kw, "options") {
    if tokens.len() < 2 {
      return "resolv: empty directive value: " + kw;
    }
    var j = 1;
    while j < tokens.len() {
      let tok: Str = tokens[j];
      if !_rv_option_ok(tok) {
        return "resolv: bad option: " + tok;
      }
      doc.options.push(tok);
      j = j + 1;
    }
    return "";
  }

  if _rv_streq(kw, "sortlist") {
    if tokens.len() < 2 {
      return "resolv: empty directive value: " + kw;
    }
    var s = 1;
    while s < tokens.len() {
      let raw: Str = tokens[s];
      let slash = _rv_slash_index(raw);
      var addr_part = raw;
      var mask = -1;
      if slash >= 0 {
        addr_part = string.str_slice(raw, 0, slash);
        let mask_txt = string.str_slice(raw, slash + 1, raw.len());
        mask = _rv_scan_mask(mask_txt);
        if mask < 0 {
          return "resolv: bad mask: " + raw;
        }
      }
      let norm2 = resolv_address_normalize(addr_part);
      var canon2 = "";
      match norm2 {
        Some(a) => { canon2 = a; },
        None => { return "resolv: bad address: " + raw; },
      }
      if mask >= 0 {
        if _rv_has_colon(addr_part) {
          if mask > _RV_MAX_MASK6 {
            return "resolv: bad mask: " + raw;
          }
        } else {
          if mask > _RV_MAX_MASK4 {
            return "resolv: bad mask: " + raw;
          }
        }
      }
      doc.sortlist_addrs.push(canon2);
      doc.sortlist_masks.push(mask);
      s = s + 1;
    }
    return "";
  }

  // Unknown or legacy directive: preserve the trimmed logical line.
  let kept = string.str_trim(text);
  if kept.len() > 0 {
    doc.unknown.push(kept);
  }
  return "";
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a resolv.conf document.
/// Params: text - the whole file (LF or CRLF line endings; a missing final
/// newline is accepted).
/// Returns: Ok(ResolvConf) for a document in the documented subset, including
/// an empty one and one with only comments/blank lines. Directives are
/// applied in document order: nameservers, options and sortlist entries
/// accumulate; `domain` and `search` are last-directive-wins; unknown and
/// legacy keywords are preserved as raw lines.
/// Error case: the first failing physical/logical line in document order,
/// with an exact ASCII message: "resolv: line too long: <n>"; "resolv:
/// control byte in line <n>"; "resolv: backslash at end of input"; "resolv:
/// empty directive value: <keyword>"; "resolv: unexpected argument: <token>";
/// "resolv: bad address: <token>"; "resolv: bad mask: <token>" (the whole
/// sortlist entry is the token); "resolv: bad option: <token>".
/// Examples: "nameserver 1.1.1.1\nsearch a.example\n" -> Ok;
/// "nameserver 256.0.0.1\n" -> Err("resolv: bad address: 256.0.0.1").
/// Complexity: O(text.len()).
pub fn resolv_parse(text: Str) -> Result[ResolvConf, Str] {
  var doc = ResolvConf{
    nameservers: Vec[Str].new();
    domain: "";
    search: Vec[Str].new();
    options: Vec[Str].new();
    sortlist_addrs: Vec[Str].new();
    sortlist_masks: Vec[Int].new();
    unknown: Vec[Str].new();
  };
  let n = text.len();
  var line_no = 1;
  var start = 0;
  var i = 0;
  var logical = "";
  var continuing = false;
  while i <= n {
    if i == n || _rv_byte_at(text, i) == _RV_LF {
      var stop = i;
      if stop > start && _rv_byte_at(text, stop - 1) == _RV_CR {
        stop = stop - 1;
      }
      if stop - start > _RV_MAX_LINE {
        return _rv_err("resolv: line too long: " + convert.int_to_string(line_no));
      }
      if _rv_line_has_control(text, start, stop) {
        return _rv_err("resolv: control byte in line " + convert.int_to_string(line_no));
      }
      let cut = _rv_find_comment(text, start, stop);
      if !continuing {
        logical = "";
      }
      logical = logical + string.str_slice(text, start, cut);
      var ends_bs = false;
      if logical.len() > 0 {
        if _rv_byte_at(logical, logical.len() - 1) == _RV_BS {
          ends_bs = true;
        }
      }
      if ends_bs {
        let final_line = i == n || i == n - 1;
        if final_line {
          return _rv_err("resolv: backslash at end of input");
        }
        logical = string.str_slice(logical, 0, logical.len() - 1);
        continuing = true;
      } else {
        let err = _rv_process(&mut doc, logical);
        if err.len() > 0 {
          return _rv_err(err);
        }
        continuing = false;
        logical = "";
      }
      line_no = line_no + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return _rv_ok(doc);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of nameserver directives in the document.
/// Params: h - parsed document.
/// Returns: the count; more than three is allowed (see
/// resolv_nameserver_over_limit).
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_nameserver_count(h: &ResolvConf) -> Int {
  return h.nameservers.len();
}

/// Nameserver address i, in document order.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(address) for 0 <= i < resolv_nameserver_count(h), else None.
/// The address is the parser's normalized form: IPv4 unchanged, IPv6
/// lowercased but not compressed.
/// Error case: none.
/// Examples: "nameserver 2001:DB8::53" -> Some("2001:db8::53").
/// Complexity: O(1).
pub fn resolv_nameserver(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= h.nameservers.len() { return None; }
  let v: Str = h.nameservers[i];
  return Some(v);
}

/// All nameserver addresses as a fresh list, in document order.
/// Params: h - parsed document.
/// Returns: a fresh Vec (empty for a document without nameservers); mutating
/// it does not change the document.
/// Error case: none.
/// Complexity: O(nameservers).
pub fn resolv_nameservers(h: &ResolvConf) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < h.nameservers.len() {
    let v: Str = h.nameservers[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Informational nameserver-limit predicate.
/// Params: h - parsed document.
/// Returns: true when the document holds more than three nameservers, the
/// classic MAXNS value; false otherwise. This predicate exists only to
/// report the condition: the parser accepts any number of `nameserver`
/// directives and this library never truncates or rejects them.
/// Error case: none.
/// Examples: four nameserver lines -> true; three -> false.
/// Complexity: O(1).
pub fn resolv_nameserver_over_limit(h: &ResolvConf) -> Bool {
  return h.nameservers.len() > _RV_CLASSIC_NS_LIMIT;
}

/// Domain value of the last `domain` directive.
/// Params: h - parsed document.
/// Returns: Some(name) when a `domain` directive was present, else None. The
/// name is stored verbatim (case preserved) and the last directive wins.
/// Error case: none.
/// Examples: "domain a.example\ndomain b.example\n" -> Some("b.example").
/// Complexity: O(1).
pub fn resolv_domain(h: &ResolvConf) -> Option[Str] {
  let d: Str = h.domain;
  if d.len() == 0 { return None; }
  return Some(d);
}

/// Number of domains in the stored search list.
/// Params: h - parsed document.
/// Returns: the count of the last `search` directive (0 when none was
/// present); a later `search` replaces the whole earlier list.
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_search_count(h: &ResolvConf) -> Int {
  return h.search.len();
}

/// Search domain i of the last `search` directive, in written order.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(name) for 0 <= i < resolv_search_count(h), else None. Names
/// are stored verbatim (case preserved).
/// Error case: none.
/// Examples: "search a.example b.example\n" -> i 0 "a.example", i 1
/// "b.example".
/// Complexity: O(1).
pub fn resolv_search_domain(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= h.search.len() { return None; }
  let v: Str = h.search[i];
  return Some(v);
}

/// Number of option tokens in the document.
/// Params: h - parsed document.
/// Returns: the count across every `options` directive, in document order.
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_option_count(h: &ResolvConf) -> Int {
  return h.options.len();
}

/// Option token i exactly as written.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(token) for 0 <= i < resolv_option_count(h), else None. The
/// token is either `name` or `name:value`; no semantics are attached.
/// Error case: none.
/// Examples: "options ndots:5 rotate" -> i 0 "ndots:5", i 1 "rotate".
/// Complexity: O(1).
pub fn resolv_option(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= h.options.len() { return None; }
  let v: Str = h.options[i];
  return Some(v);
}

/// Name part of option token i: everything before the first colon, or the
/// whole token when it has no colon.
/// Params: h - parsed document; i - zero-based index.
/// Returns: the name for 0 <= i < resolv_option_count(h), else "". An empty
/// string is unambiguous because a parsed token always has a non-empty name.
/// Error case: none.
/// Examples: "ndots:5" -> "ndots"; "rotate" -> "rotate".
/// Complexity: O(token length).
pub fn resolv_option_name(h: &ResolvConf, i: Int) -> Str {
  if i < 0 || i >= h.options.len() { return ""; }
  let v: Str = h.options[i];
  return _rv_option_name_of(v);
}

/// Value part of option token i: Some(text after the first colon), or None
/// when the token has no colon.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(value) with a non-empty value for a `name:value` token,
/// None for a bare `name` token or an out-of-range index.
/// Error case: none.
/// Examples: "ndots:5" -> Some("5"); "rotate" -> None.
/// Complexity: O(token length).
pub fn resolv_option_value(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= h.options.len() { return None; }
  let v: Str = h.options[i];
  return _rv_option_value_of(v);
}

/// Zero-based index of the first option whose name part equals `name`.
/// Params: h - parsed document; name - query name without a value.
/// Returns: the index of the first matching option token in document order,
/// or -1 when no option matches. Comparison is byte-exact and case-sensitive
/// against the name part, so a query "ndots" matches "ndots:5" but not
/// "NDOTS:5".
/// Error case: none.
/// Examples: "ndots:5 timeout:2 ndots:9" -> 0 for "ndots", 1 for "timeout",
/// -1 for "attempts" and "NDOTS".
/// Complexity: O(options * name length).
pub fn resolv_option_index(h: &ResolvConf, name: Str) -> Int {
  let n = h.options.len();
  var i = 0;
  while i < n {
    let v: Str = h.options[i];
    let nm = _rv_option_name_of(v);
    if _rv_streq(nm, name) { return i; }
    i = i + 1;
  }
  return -1;
}

/// Number of sortlist entries in the document.
/// Params: h - parsed document.
/// Returns: the count across every `sortlist` directive; a corrupted
/// document reports the smaller of the two parallel vectors.
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_sortlist_count(h: &ResolvConf) -> Int {
  var n = h.sortlist_addrs.len();
  if h.sortlist_masks.len() < n { n = h.sortlist_masks.len(); }
  return n;
}

/// Sortlist address i, in document order.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(address) for 0 <= i < resolv_sortlist_count(h), else None.
/// The address is normalized exactly like a nameserver address.
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_sortlist_addr(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= resolv_sortlist_count(h) { return None; }
  let v: Str = h.sortlist_addrs[i];
  return Some(v);
}

/// Mask of sortlist entry i.
/// Params: h - parsed document; i - zero-based index.
/// Returns: the mask for 0 <= i < resolv_sortlist_count(h) when the entry
/// was written as `addr/n`, and -1 when the entry was written without a mask
/// or when i is out of range. Masks are 0..32 for an IPv4 address and 0..128
/// for an IPv6 address, so a real mask is never negative.
/// Error case: none.
/// Examples: "sortlist 10.0.0.0/8 192.0.2.7" -> mask 8 then -1.
/// Complexity: O(1).
pub fn resolv_sortlist_mask(h: &ResolvConf, i: Int) -> Int {
  if i < 0 || i >= resolv_sortlist_count(h) { return -1; }
  let v: Int = h.sortlist_masks[i];
  return v;
}

/// Number of preserved unknown/legacy directive lines.
/// Params: h - parsed document.
/// Returns: the count of logical lines whose keyword is `lookup`, `family`
/// or anything this version does not model. They are never errors.
/// Error case: none.
/// Complexity: O(1).
pub fn resolv_unknown_count(h: &ResolvConf) -> Int {
  return h.unknown.len();
}

/// Preserved raw line i.
/// Params: h - parsed document; i - zero-based index.
/// Returns: Some(line) for 0 <= i < resolv_unknown_count(h), else None. The
/// line is the logical line (continuations joined) with comments removed and
/// leading/trailing whitespace trimmed; internal whitespace is preserved,
/// and the line is re-emitted verbatim.
/// Error case: none.
/// Examples: "lookup   file bind # note" -> Some("lookup   file bind").
/// Complexity: O(1).
pub fn resolv_unknown_line(h: &ResolvConf, i: Int) -> Option[Str] {
  if i < 0 || i >= h.unknown.len() { return None; }
  let v: Str = h.unknown[i];
  return Some(v);
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

/// Emit a document in the canonical resolv.conf form.
/// Params: h - parsed document.
/// Returns: LF-terminated lines in the documented order: every nameserver in
/// document order, then `domain` (when present), then one `search` line with
/// every domain, then one `options` line with every option token, then one
/// `sortlist` line with every entry (`addr` or `addr/mask`, mask omitted when
/// it is -1), then every preserved unknown/legacy line in document order.
/// Separators are single spaces and an empty document emits "". Comments,
/// blank lines, continuation backslashes and original whitespace are not
/// preserved. Emitting a document produced by resolv_parse and parsing it
/// again yields the same content, so emit(parse(x)) is a fixed point.
/// Error case: none.
/// Examples: parse("search b.example a.example\nnameserver 1.1.1.1\n")
/// emits "nameserver 1.1.1.1\nsearch b.example a.example\n".
/// Complexity: O(total output length).
pub fn resolv_emit(h: &ResolvConf) -> Str {
  var out = "";
  var i = 0;
  while i < h.nameservers.len() {
    let v: Str = h.nameservers[i];
    out = out + "nameserver " + v + "\n";
    i = i + 1;
  }
  let d: Str = h.domain;
  if d.len() > 0 {
    out = out + "domain " + d + "\n";
  }
  if h.search.len() > 0 {
    out = out + "search";
    var j = 0;
    while j < h.search.len() {
      let v2: Str = h.search[j];
      out = out + " " + v2;
      j = j + 1;
    }
    out = out + "\n";
  }
  if h.options.len() > 0 {
    out = out + "options";
    var k = 0;
    while k < h.options.len() {
      let v3: Str = h.options[k];
      out = out + " " + v3;
      k = k + 1;
    }
    out = out + "\n";
  }
  let m = resolv_sortlist_count(h);
  if m > 0 {
    out = out + "sortlist";
    var s = 0;
    while s < m {
      let addr: Str = h.sortlist_addrs[s];
      let mask: Int = h.sortlist_masks[s];
      if mask >= 0 {
        out = out + " " + addr + "/" + convert.int_to_string(mask);
      } else {
        out = out + " " + addr;
      }
      s = s + 1;
    }
    out = out + "\n";
  }
  var u = 0;
  while u < h.unknown.len() {
    let v4: Str = h.unknown[u];
    out = out + v4 + "\n";
    u = u + 1;
  }
  return out;
}
