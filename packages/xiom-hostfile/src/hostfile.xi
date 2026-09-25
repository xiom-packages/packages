// XIOM -- xiom.hostfile: hosts-file parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed hosts file is five parallel vectors owned by HostsFile:
// `addresses` holds entry i's canonical address text, `lines` its 1-based
// source line, and `host_starts`/`host_counts` slice the shared flat
// `hosts` pool that holds every hostname in document order. Vec[StructType]
// is unsupported in this compiler, so the document is deliberately flat
// instead of a vector of entries.
//
// Documented subset (see SPEC.md for the exact grammar):
//   * each entry line is `address hostname [hostname ...]`;
//   * inline comments start at an unquoted `#` (there is no quoting in hosts
//     syntax, so `#` always starts a comment, even mid-token);
//   * leading/trailing whitespace, blank lines, spaces and tabs between
//     tokens, and both LF and CRLF line endings are accepted; a missing
//     final newline is accepted;
//   * addresses are either IPv4 dotted quads (four decimal octets 0..255,
//     no leading zeros) or the documented IPv6 subset: 1..4 lowercase or
//     uppercase hex digits per group, at most one `::`, exactly eight groups
//     after expansion, and an optional trailing dotted quad that counts as
//     the final two groups (no zone IDs); canonical storage/emission is
//     lowercase with the longest leftmost zero run compressed;
//   * hostnames use letters, digits, hyphen and dot only; every label is
//     1..63 bytes, starts and ends with a letter or digit, and the whole
//     name is at most 253 bytes; hostnames are stored lowercased (DNS is
//     case-insensitive);
//   * a physical line longer than 4096 bytes and any control byte other
//     than TAB (and the CR of a CRLF pair) are errors.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     _hf_byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF` before
//     any comparison (a raw UInt8 compared against a constant >= 128
//     miscompiles);
//   * no `==` on Str values read from Vec[Str] elements; each is bound to a
//     typed local first and compared with compare.str_compare (BUG 17);
//   * Ok/Err for the struct-payload Result are constructed only in the leaf
//     helpers _hf_ok/_hf_err;
//   * every push on one parallel vector is mirrored in _hf_push_entry, and
//     accessors/emit clamp against mismatched lengths so a corrupted
//     document cannot drive out-of-range reads.
//
// See SPEC.md for the model, grammar, error catalog and test plan.

module xiom.hostfile

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed hosts file. `addresses`, `host_starts`, `host_counts` and `lines`
/// are parallel per-entry vectors: entry i has the canonical address
/// addresses[i], the 1-based source line lines[i], and owns the hostname
/// slice hosts[host_starts[i] .. host_starts[i] + host_counts[i]] of the
/// shared flat pool `hosts` (document order, lowercased, count >= 1).
/// Vec[StructType] is unsupported in this compiler, so the model is
/// deliberately flat instead of a vector of entry structs.
pub type HostsFile = {
  addresses: Vec[Str];
  hosts: Vec[Str];
  host_starts: Vec[Int];
  host_counts: Vec[Int];
  lines: Vec[Int];
}

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

// ASCII codes used by the scanners (all compared in Int space).
const _HF_TAB: Int = 9;
const _HF_LF: Int = 10;
const _HF_CR: Int = 13;
const _HF_SPACE: Int = 32;
const _HF_HASH: Int = 35;
const _HF_DOT: Int = 46;
const _HF_COLON: Int = 58;
const _HF_DEL: Int = 127;

// Longest accepted physical line, excluding the line terminator.
const _HF_MAX_LINE: Int = 4096;
// Longest accepted hostname (RFC 1035 name limit).
const _HF_MAX_HOSTNAME: Int = 253;
// Longest accepted hostname label (RFC 1035 label limit).
const _HF_MAX_LABEL: Int = 63;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _hf_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _hf_is_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

fn _hf_is_lower(c: Int) -> Bool {
  return c >= 97 && c <= 122;
}

fn _hf_is_upper(c: Int) -> Bool {
  return c >= 65 && c <= 90;
}

fn _hf_is_alpha(c: Int) -> Bool {
  if _hf_is_lower(c) { return true; }
  return _hf_is_upper(c);
}

fn _hf_is_space(c: Int) -> Bool {
  return c == _HF_SPACE || c == _HF_TAB;
}

// Hex value of an ASCII hex digit, or -1.
fn _hf_hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

// True when s[start, stop) contains at least one '.'.
fn _hf_has_dot(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    if _hf_byte_at(s, i) == _HF_DOT { return true; }
    i = i + 1;
  }
  return false;
}

// Byte index of the first ':' in s, or -1.
fn _hf_find_colon(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _hf_byte_at(s, i) == _HF_COLON { return i; }
    i = i + 1;
  }
  return -1;
}

// Byte index of the first '.' in s, or -1.
fn _hf_find_dot(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _hf_byte_at(s, i) == _HF_DOT { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 constructors for the struct-payload Result: Ok/Err are built only
// in these tiny wrappers, never inside a larger function.

fn _hf_ok(d: HostsFile) -> Result[HostsFile, Str] {
  return Ok(d);
}

fn _hf_err(m: Str) -> Result[HostsFile, Str] {
  return Err(m);
}

// --------------------------------------------------
//  IPv4
// --------------------------------------------------

// Scan s[start, stop) as a dotted quad. Returns the 32-bit value, or -1 when
// the slice is not exactly four decimal octets 0..255 without leading zeros.
fn _hf_scan_quad(s: Str, start: Int, stop: Int) -> Int {
  if start >= stop { return -1; }
  var value = 0;
  var parts = 0;
  var octet = 0;
  var digits = 0;
  var lead_zero = false;
  var i = start;
  while i < stop {
    let c = _hf_byte_at(s, i);
    if c == _HF_DOT {
      if digits == 0 { return -1; }
      if digits > 1 && lead_zero { return -1; }
      value = (value << 8) | octet;
      parts = parts + 1;
      if parts > 3 { return -1; }
      octet = 0;
      digits = 0;
      lead_zero = false;
    } else {
      if !_hf_is_digit(c) { return -1; }
      if digits == 0 && c == 48 { lead_zero = true; }
      octet = octet * 10 + (c - 48);
      if octet > 255 { return -1; }
      digits = digits + 1;
      if digits > 3 { return -1; }
    }
    i = i + 1;
  }
  if digits == 0 { return -1; }
  if digits > 1 && lead_zero { return -1; }
  parts = parts + 1;
  if parts != 4 { return -1; }
  value = (value << 8) | octet;
  return value;
}

// --------------------------------------------------
//  IPv6
// --------------------------------------------------

// Value of the hex group s[start, stop): 1..4 hex digits, or -1.
fn _hf_hex_group_value(s: Str, start: Int, stop: Int) -> Int {
  let len = stop - start;
  if len < 1 || len > 4 { return -1; }
  var v = 0;
  var i = start;
  while i < stop {
    let h = _hf_hex_value(_hf_byte_at(s, i));
    if h < 0 { return -1; }
    v = (v << 4) | h;
    i = i + 1;
  }
  return v;
}

// Append the groups of s[start, stop) to `out`. An empty slice contributes
// zero groups (only legal around `::`); otherwise tokens are separated by
// single colons with no empty token and no trailing colon. A final dotted
// quad is accepted when `allow_v4_tail` is true and it is the last token; it
// contributes two groups. Returns false on any malformed slice, possibly
// after pushing some groups (the caller discards `out` on failure).
fn _hf_scan_groups(v: Str, start: Int, stop: Int, out: &mut Vec[Int], allow_v4_tail: Bool) -> Bool {
  if start >= stop { return true; }
  var i = start;
  while i < stop {
    var j = i;
    while j < stop && _hf_byte_at(v, j) != _HF_COLON { j = j + 1; }
    if j == i { return false; }
    let last = j == stop;
    if _hf_has_dot(v, i, j) {
      if !last || !allow_v4_tail { return false; }
      let q = _hf_scan_quad(v, i, j);
      if q < 0 { return false; }
      out.push((q >> 16) & 0xFFFF);
      out.push(q & 0xFFFF);
    } else {
      let g = _hf_hex_group_value(v, i, j);
      if g < 0 { return false; }
      out.push(g);
    }
    if last { return true; }
    i = j + 1;
    if i >= stop { return false; }
  }
  return true;
}

// Lowercase hex text of a 16-bit group value, no leading zeros.
fn _hf_hex_text(v: Int) -> Str {
  if v == 0 { return "0"; }
  var out = "";
  var x = v;
  while x > 0 {
    let d = x & 15;
    out = string.str_slice("0123456789abcdef", d, d + 1) + out;
    x = x >> 4;
  }
  return out;
}

// Canonical text of exactly eight groups: lowercase, no leading zeros, and
// the longest run of two or more zero groups (leftmost on a tie) replaced by
// `::`. A single zero group is written as "0" (RFC 5952).
fn _hf_format_groups(g: &Vec[Int]) -> Str {
  var best_start = -1;
  var best_len = 0;
  var i = 0;
  while i < 8 {
    let x: Int = g[i];
    if x == 0 {
      var j = i;
      while j < 8 {
        let y: Int = g[j];
        if y != 0 { break; }
        j = j + 1;
      }
      let run = j - i;
      if run > best_len {
        best_len = run;
        best_start = i;
      }
      i = j;
    } else {
      i = i + 1;
    }
  }
  if best_len < 2 { best_start = -1; }
  var out = "";
  if best_start < 0 {
    var k = 0;
    while k < 8 {
      if k > 0 { out = out + ":"; }
      out = out + _hf_hex_text(g[k]);
      k = k + 1;
    }
    return out;
  }
  var h = 0;
  while h < best_start {
    if h > 0 { out = out + ":"; }
    out = out + _hf_hex_text(g[h]);
    h = h + 1;
  }
  out = out + "::";
  var t = best_start + best_len;
  var first_tail = true;
  while t < 8 {
    if !first_tail { out = out + ":"; }
    out = out + _hf_hex_text(g[t]);
    first_tail = false;
    t = t + 1;
  }
  return out;
}

// Canonical text of an IPv6 candidate, or None. At most one `::`; exactly
// eight groups after expansion; `::` must stand for at least one group; an
// embedded dotted quad is allowed only as the final 32 bits.
fn _hf_ipv6_canonical(s: Str) -> Option[Str] {
  let n = s.len();
  var dbl = -1;
  var dbl_count = 0;
  var i = 0;
  while i + 1 < n {
    if _hf_byte_at(s, i) == _HF_COLON && _hf_byte_at(s, i + 1) == _HF_COLON {
      if dbl < 0 { dbl = i; }
      dbl_count = dbl_count + 1;
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  if dbl_count > 1 { return None; }
  var groups = Vec[Int].new();
  if dbl < 0 {
    if !_hf_scan_groups(s, 0, n, &mut groups, true) { return None; }
    if groups.len() != 8 { return None; }
    return Some(_hf_format_groups(&groups));
  }
  if !_hf_scan_groups(s, 0, dbl, &mut groups, false) { return None; }
  let head = groups.len();
  if !_hf_scan_groups(s, dbl + 2, n, &mut groups, true) { return None; }
  let explicit = groups.len();
  if explicit > 7 { return None; }
  var all = Vec[Int].new();
  var k = 0;
  while k < head {
    let g: Int = groups[k];
    all.push(g);
    k = k + 1;
  }
  var zeros = 8 - explicit;
  while zeros > 0 {
    all.push(0);
    zeros = zeros - 1;
  }
  while k < explicit {
    let g2: Int = groups[k];
    all.push(g2);
    k = k + 1;
  }
  return Some(_hf_format_groups(&all));
}

// --------------------------------------------------
//  Hostnames
// --------------------------------------------------

/// Validate a hostname in the documented subset: 1..253 bytes, labels of
/// 1..63 bytes separated by single dots, each label made of ASCII letters,
/// digits and hyphens and neither starting nor ending with a hyphen. No
/// trailing dot, no empty label, no underscore and no non-ASCII byte.
/// Params: s - candidate hostname text.
/// Returns: true when s is a valid hostname.
/// Error case: none (a Bool result; the parser turns false into an Err).
/// Examples: "localhost", "a-b.example" and "123" -> true; "" , "-a",
/// "a-", "a..b", "a." and "under_score" -> false.
/// Complexity: O(s.len()).
pub fn hostfile_hostname_valid(s: Str) -> Bool {
  let n = s.len();
  if n == 0 || n > _HF_MAX_HOSTNAME { return false; }
  var label = 0;
  var i = 0;
  while i < n {
    let c = _hf_byte_at(s, i);
    if c == _HF_DOT {
      if label == 0 { return false; }
      if label > _HF_MAX_LABEL { return false; }
      if _hf_byte_at(s, i - 1) == 45 { return false; }
      label = 0;
    } elif c == 45 {
      if label == 0 { return false; }
      label = label + 1;
    } elif _hf_is_alpha(c) || _hf_is_digit(c) {
      label = label + 1;
    } else {
      return false;
    }
    i = i + 1;
  }
  if label == 0 { return false; }
  if label > _HF_MAX_LABEL { return false; }
  if _hf_byte_at(s, n - 1) == 45 { return false; }
  return true;
}

// --------------------------------------------------
//  Address normalization
// --------------------------------------------------

/// Canonicalize an IPv4 or IPv6 candidate address.
/// Params: s - candidate address text.
/// Returns: Some(text) with the canonical form, or None when s is not a
/// valid address. IPv4 ("a.b.c.d", four decimal octets 0..255, no leading
/// zeros) is already canonical and returned unchanged. IPv6 is returned
/// lowercase, without leading zeros in a group, with the longest leftmost
/// run of two or more zero groups compressed to `::` (a lone zero group is
/// written "0"), and with any embedded dotted quad folded into the two hex
/// groups it stands for. No zone IDs (`%...`) are accepted.
/// Error case: none (the parser turns None into Err("hostfile: bad
/// address: ...")).
/// Examples: "0:0:0:0:0:0:0:1" -> Some("::1");
/// "2001:0DB8:0:0:0:0:0:1" -> Some("2001:db8::1");
/// "::ffff:192.168.1.1" -> Some("::ffff:c0a8:101"); "256.0.0.1" -> None.
/// Complexity: O(s.len()).
pub fn hostfile_address_normalize(s: Str) -> Option[Str] {
  if _hf_find_colon(s) >= 0 {
    return _hf_ipv6_canonical(s);
  }
  if _hf_find_dot(s) >= 0 {
    if _hf_scan_quad(s, 0, s.len()) >= 0 { return Some(s); }
  }
  return None;
}

/// True when s is a valid address in the documented subset.
/// Params: s - candidate address text.
/// Returns: true for a valid IPv4 dotted quad or documented-subset IPv6
/// address; false otherwise. Equivalent to "hostfile_address_normalize(s)
/// is Some".
/// Error case: none.
/// Examples: "1.2.3.4" -> true; "::1" -> true; "::ffff:1.2.3.4" -> true;
/// "1.2.3.256" -> false; "1.2.3.4/24" -> false.
/// Complexity: O(s.len()).
pub fn hostfile_address_valid(s: Str) -> Bool {
  let o = hostfile_address_normalize(s);
  return o.is_some;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// True when s[start, stop) contains a byte that is neither printable ASCII
// nor TAB: bytes 0..31 (TAB excepted) and DEL. A CR is only legal as the CR
// of a CRLF pair, which the caller strips before calling this.
fn _hf_line_has_control(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    let c = _hf_byte_at(s, i);
    if c < 32 && c != _HF_TAB { return true; }
    if c == _HF_DEL { return true; }
    i = i + 1;
  }
  return false;
}

// Append the whitespace-separated tokens of s[start, stop) to `out`.
fn _hf_split_tokens(s: Str, start: Int, stop: Int, out: &mut Vec[Str]) {
  var i = start;
  while i < stop {
    while i < stop && _hf_is_space(_hf_byte_at(s, i)) { i = i + 1; }
    if i >= stop { break; }
    var j = i;
    while j < stop && !_hf_is_space(_hf_byte_at(s, j)) { j = j + 1; }
    out.push(string.str_slice(s, i, j));
    i = j;
  }
}

// Append one parsed entry: the address, its hostnames (already validated and
// lowercased) and the source line. This is the only place any of the five
// parallel vectors is pushed, so they cannot drift apart.
fn _hf_push_entry(doc: &mut HostsFile, address: Str, names: &Vec[Str], line: Int) {
  let start = doc.hosts.len();
  doc.addresses.push(address);
  doc.host_starts.push(start);
  doc.host_counts.push(names.len());
  doc.lines.push(line);
  var k = 0;
  while k < names.len() {
    let nm: Str = names[k];
    doc.hosts.push(nm);
    k = k + 1;
  }
}

/// Parse a hosts file.
/// Params: text - the whole file.
/// Returns: Ok(HostsFile) for a document in the documented subset (including
/// an empty one and one with only comments/blank lines); every entry line
/// contributes one address, one or more hostnames and its 1-based source
/// line number, in document order.
/// Error case: Err("hostfile: line too long: <n>") for a physical line
/// longer than 4096 bytes excluding the terminator; Err("hostfile: control
/// byte in line <n>") for a byte 0..31 other than TAB (or CR immediately
/// before LF) or for DEL, comments included; Err("hostfile: bad address:
/// <token>") when the first token is not a valid address; Err("hostfile:
/// entry with no hostname: <token>") when a valid address has no hostnames;
/// Err("hostfile: bad hostname: <token>") for any later token that is not a
/// valid hostname. The first error in document order is returned.
/// Examples: "127.0.0.1 localhost\n" -> Ok with one entry;
/// "10.0.0.1\n" -> Err("hostfile: entry with no hostname: 10.0.0.1").
/// Complexity: O(text.len()).
pub fn hostfile_parse(text: Str) -> Result[HostsFile, Str] {
  var doc = HostsFile{
    addresses: Vec[Str].new();
    hosts: Vec[Str].new();
    host_starts: Vec[Int].new();
    host_counts: Vec[Int].new();
    lines: Vec[Int].new();
  };
  let n = text.len();
  var line_no = 1;
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _hf_byte_at(text, i) == _HF_LF {
      var stop = i;
      if stop > start && _hf_byte_at(text, stop - 1) == _HF_CR {
        stop = stop - 1;
      }
      if stop - start > _HF_MAX_LINE {
        return _hf_err("hostfile: line too long: " + convert.int_to_string(line_no));
      }
      if _hf_line_has_control(text, start, stop) {
        return _hf_err("hostfile: control byte in line " + convert.int_to_string(line_no));
      }
      var send = stop;
      var h = start;
      while h < stop {
        if _hf_byte_at(text, h) == _HF_HASH {
          send = h;
          break;
        }
        h = h + 1;
      }
      var tokens = Vec[Str].new();
      _hf_split_tokens(text, start, send, &mut tokens);
      if tokens.len() > 0 {
        let raw: Str = tokens[0];
        let norm = hostfile_address_normalize(raw);
        var canon = "";
        match norm {
          Some(a) => { canon = a; },
          None => { return _hf_err("hostfile: bad address: " + raw); },
        }
        if tokens.len() < 2 {
          return _hf_err("hostfile: entry with no hostname: " + raw);
        }
        var names = Vec[Str].new();
        var j = 1;
        while j < tokens.len() {
          let tok: Str = tokens[j];
          if !hostfile_hostname_valid(tok) {
            return _hf_err("hostfile: bad hostname: " + tok);
          }
          names.push(string.str_lower(tok));
          j = j + 1;
        }
        _hf_push_entry(&mut doc, canon, &names, line_no);
      }
      line_no = line_no + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return _hf_ok(doc);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of entries in the document.
/// Params: h - parsed document.
/// Returns: the entry count; a corrupted document reports the smallest of
/// the four parallel entry vectors, so trailing rows are ignored rather
/// than read out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn hostfile_entry_count(h: &HostsFile) -> Int {
  var n = h.addresses.len();
  if h.host_starts.len() < n { n = h.host_starts.len(); }
  if h.host_counts.len() < n { n = h.host_counts.len(); }
  if h.lines.len() < n { n = h.lines.len(); }
  return n;
}

/// Canonical address text of entry i.
/// Params: h - parsed document; i - zero-based entry index.
/// Returns: Some(address) for 0 <= i < hostfile_entry_count(h); None when i
/// is out of range. The address is the parser's canonical form: IPv4
/// unchanged, IPv6 lowercase with the longest leftmost zero run compressed.
/// Error case: none.
/// Examples: entry "0:0:0:0:0:0:0:1 lo" -> Some("::1").
/// Complexity: O(1).
pub fn hostfile_address(h: &HostsFile, i: Int) -> Option[Str] {
  if i < 0 || i >= hostfile_entry_count(h) { return None; }
  let a: Str = h.addresses[i];
  return Some(a);
}

/// 1-based source line number of entry i.
/// Params: h - parsed document; i - zero-based entry index.
/// Returns: the line number for 0 <= i < hostfile_entry_count(h), else 0.
/// Error case: none.
/// Complexity: O(1).
pub fn hostfile_line(h: &HostsFile, i: Int) -> Int {
  if i < 0 || i >= hostfile_entry_count(h) { return 0; }
  let v: Int = h.lines[i];
  return v;
}

/// Number of hostnames of entry i.
/// Params: h - parsed document; i - zero-based entry index.
/// Returns: the hostname count for 0 <= i < hostfile_entry_count(h), else 0.
/// The count is clamped to the shared pool, so a corrupted document reports
/// 0 rather than reading past `hosts`.
/// Error case: none.
/// Complexity: O(1).
pub fn hostfile_hostname_count(h: &HostsFile, i: Int) -> Int {
  if i < 0 || i >= hostfile_entry_count(h) { return 0; }
  let start: Int = h.host_starts[i];
  if start < 0 { return 0; }
  var c: Int = h.host_counts[i];
  if c < 0 { c = 0; }
  if start + c > h.hosts.len() { c = h.hosts.len() - start; }
  if c < 0 { c = 0; }
  return c;
}

/// Hostnames of entry i, in document order.
/// Params: h - parsed document; i - zero-based entry index.
/// Returns: a fresh Vec with the entry's hostnames for 0 <= i <
/// hostfile_entry_count(h), else an empty Vec. Stored hostnames are
/// lowercased; mutating the result does not change the document.
/// Error case: none.
/// Complexity: O(hostnames).
pub fn hostfile_hostnames(h: &HostsFile, i: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let count = hostfile_hostname_count(h, i);
  if count == 0 { return out; }
  let start: Int = h.host_starts[i];
  var k = 0;
  while k < count {
    let nm: Str = h.hosts[start + k];
    out.push(nm);
    k = k + 1;
  }
  return out;
}

/// Zero-based index of the first entry whose hostnames contain `hostname`.
/// Params: h - parsed document; hostname - query name.
/// Returns: the first matching entry index in document order, or -1 when no
/// entry matches. The query is lowercased first and compared byte-exactly
/// with the stored (already lowercased) hostnames, so matching is
/// case-insensitive; an invalid hostname simply matches nothing.
/// Error case: none.
/// Examples: "DUP" matches an entry holding "dup".
/// Complexity: O(entries * hostnames * name length).
pub fn hostfile_lookup_index(h: &HostsFile, hostname: Str) -> Int {
  let needle = string.str_lower(hostname);
  let n = hostfile_entry_count(h);
  var i = 0;
  while i < n {
    let count = hostfile_hostname_count(h, i);
    let start: Int = h.host_starts[i];
    var k = 0;
    while k < count {
      let nm: Str = h.hosts[start + k];
      if compare.str_compare(nm, needle) == 0 { return i; }
      k = k + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Canonical address of the first entry whose hostnames contain `hostname`.
/// Params: h - parsed document; hostname - query name.
/// Returns: Some(address) for the first match in document order, or None
/// when no entry matches. Matching follows hostfile_lookup_index.
/// Error case: none.
/// Examples: "LOCALHOST" -> Some("127.0.0.1") when that entry comes first.
/// Complexity: O(entries * hostnames * name length).
pub fn hostfile_lookup(h: &HostsFile, hostname: Str) -> Option[Str] {
  let i = hostfile_lookup_index(h, hostname);
  if i < 0 { return None; }
  let a: Str = h.addresses[i];
  return Some(a);
}

/// Zero-based indexes of every entry whose address is `address`.
/// Params: h - parsed document; address - query address.
/// Returns: a fresh Vec of entry indexes in document order (empty when
/// nothing matches). The query is canonicalized exactly like a parsed
/// address first, so "0:0:0:0:0:0:0:1" matches an entry stored as "::1";
/// an invalid address query matches nothing.
/// Error case: none.
/// Examples: two "10.0.0.1" entries -> [0, 1].
/// Complexity: O(entries * address length).
pub fn hostfile_entries_for_address(h: &HostsFile, address: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var canon = "";
  let norm = hostfile_address_normalize(address);
  match norm {
    Some(a) => { canon = a; },
    None => { return out; },
  }
  let n = hostfile_entry_count(h);
  var i = 0;
  while i < n {
    let a: Str = h.addresses[i];
    if compare.str_compare(a, canon) == 0 { out.push(i); }
    i = i + 1;
  }
  return out;
}

/// Emit a document in the canonical hosts-file form.
/// Params: h - parsed document.
/// Returns: one line per entry, `<address> <hostname>[ <hostname>...]` with
/// single-space separators and a trailing newline after every line; an
/// empty document emits "". Comments, blank lines and original whitespace
/// are not preserved, and every entry is emitted on one line (the source
/// line numbers are not part of the output); addresses and hostnames are
/// emitted in their stored canonical form. Emitting a document produced by
/// hostfile_parse and parsing it again yields the same entries, so
/// emit(parse(x)) is a fixed point.
/// Error case: none.
/// Examples: parse("127.0.0.1  localhost\n\n::1\tip6\n") emits
/// "127.0.0.1 localhost\n::1 ip6\n".
/// Complexity: O(total output length).
pub fn hostfile_emit(h: &HostsFile) -> Str {
  var out = "";
  let n = hostfile_entry_count(h);
  var i = 0;
  while i < n {
    let a: Str = h.addresses[i];
    out = out + a;
    let start: Int = h.host_starts[i];
    let count = hostfile_hostname_count(h, i);
    var k = 0;
    while k < count {
      let nm: Str = h.hosts[start + k];
      out = out + " " + nm;
      k = k + 1;
    }
    out = out + "\n";
    i = i + 1;
  }
  return out;
}
