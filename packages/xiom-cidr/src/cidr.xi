// XIOM -- xiom.cidr: IPv4 addresses and CIDR blocks (parse, format,
// containment and range math over 32-bit Ints)
// Port task: create the greenfield xiom.cidr package as a real, tested,
// pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: an IPv4 address is a non-negative 32-bit Int in host byte order --
// 0.0.0.0 is 0 and 255.255.255.255 is 4294967295. A CIDR block is the pair
// (network, prefix) where `network` has all host bits zero. Every function is
// a free-standing function (no methods, no lambdas, no Vec allocations) and
// treats the low 32 bits of an Int as the address, so out-of-range inputs are
// masked rather than rejected; only the two parsers return Result.
//
// Documented rules (see SPEC.md for the full specification):
//   * leading zeros in an octet are rejected ("01.2.3.4" is invalid, "0" is
//     valid) and so are leading zeros in a prefix length ("/024" is invalid);
//   * cidr_parse masks host bits off ("192.168.1.77/24" -> 192.168.1.0/24);
//   * a prefix outside 0..32 is treated as prefix 0 (mask 0) by every
//     prefix-taking function except cidr_mask itself, which returns 0;
//   * cidr_first_host/cidr_last_host return the network address itself for
//     /31 and /32 and otherwise exclude the network and broadcast addresses.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     xiom.string.byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF`
//     before any comparison or arithmetic (a raw UInt8 compared against a
//     constant >= 128 miscompiles);
//   * Ok/Err values are constructed only in the tiny leaf helpers
//     (_ip_ok/_ip_err/_cidr_ok/_cidr_err); constructing a Result inside a
//     larger function miscompiles;
//   * no Vec values, no lambdas, no match arms and no struct returns here;
//   * all arithmetic is masked to 32 bits or bounded by 2^32, so exact values
//     survive the 64-bit signed range (4294967296 is representable).
//
// See SPEC.md for the model, the masking rules, the error catalog and the
// test plan.

module xiom.cidr

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

// 255.255.255.255: the largest 32-bit address and the full 32-bit mask.
const _CIDR_MAX32: Int = 4294967295;

const _CIDR_DOT: Int = 46;
const _CIDR_SLASH: Int = 47;
const _CIDR_ZERO: Int = 48;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _cidr_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Index of the first byte equal to `ch` in s, or -1 when absent.
fn _cidr_index_of(s: Str, ch: Int) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    if _cidr_byte_at(s, i) == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Scan s[start..stop) as a dotted quad.
// Returns: the 32-bit address value; -1 when the octet count is not four
// (including an empty slice); -2 for a malformed octet -- an empty part, a
// non-digit byte, more than three digits, a value above 255, or a leading
// zero on a multi-digit part.
fn _cidr_scan_ip(s: Str, start: Int, stop: Int) -> Int {
  if start >= stop {
    return -1;
  }
  var value = 0;
  var parts = 0;
  var octet = 0;
  var digits = 0;
  var lead_zero = false;
  var i = start;
  while i < stop {
    let c = _cidr_byte_at(s, i);
    if c == _CIDR_DOT {
      if digits == 0 {
        return -2;
      }
      if digits > 1 && lead_zero {
        return -2;
      }
      value = (value << 8) | octet;
      parts = parts + 1;
      if parts > 3 {
        return -1;
      }
      octet = 0;
      digits = 0;
      lead_zero = false;
    } else {
      if c < _CIDR_ZERO || c > 57 {
        return -2;
      }
      if digits == 0 && c == _CIDR_ZERO {
        lead_zero = true;
      }
      octet = octet * 10 + (c - _CIDR_ZERO);
      if octet > 255 {
        return -2;
      }
      digits = digits + 1;
      if digits > 3 {
        return -2;
      }
    }
    i = i + 1;
  }
  if digits == 0 {
    return -2;
  }
  if digits > 1 && lead_zero {
    return -2;
  }
  parts = parts + 1;
  if parts != 4 {
    return -1;
  }
  value = (value << 8) | octet;
  return value;
}

// Scan s[start..stop) as a canonical decimal prefix length: at least one
// digit, "0" allowed, no leading zero on a multi-digit value. Accumulation
// stops once the value exceeds 32, so arbitrarily long digit runs cannot
// overflow; the caller only distinguishes "<= 32" from "> 32".
// Returns: the value (possibly > 32), or -1 for an empty slice, a non-digit
// byte, or a leading zero.
fn _cidr_scan_prefix(s: Str, start: Int, stop: Int) -> Int {
  if start >= stop {
    return -1;
  }
  if stop - start > 1 && _cidr_byte_at(s, start) == _CIDR_ZERO {
    return -1;
  }
  var v = 0;
  var i = start;
  while i < stop {
    let c = _cidr_byte_at(s, i);
    if c < _CIDR_ZERO || c > 57 {
      return -1;
    }
    if v <= 32 {
      v = v * 10 + (c - _CIDR_ZERO);
    }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 miscompiles Ok/Err constructed inside larger functions, so every
// Result value in this module is built by one of these tiny wrappers.

fn _ip_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _ip_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _cidr_ok(network: Int, prefix: Int) -> Result[(Int, Int), Str] {
  return Ok((network, prefix));
}

fn _cidr_err(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// --------------------------------------------------
//  Address parsing and formatting
// --------------------------------------------------

/// Parse a dotted-quad IPv4 address into a non-negative 32-bit Int.
/// Params: s - candidate address text.
/// Returns: Ok(v) with 0 <= v <= 4294967295 for exactly four dot-separated
/// decimal octets, each 0..255; a multi-digit octet must not have a leading
/// zero ("0" itself is valid, "01" is not).
/// Error case: Err("cidr: empty address") for ""; Err("cidr: expected four
/// octets") when the part count is not four; Err("cidr: invalid octet") for
/// an empty part (leading/trailing/doubled dot), a non-digit byte, more than
/// three digits, a value above 255, or a leading zero.
/// Examples: "1.2.3.4" -> Ok(16909060); "192.168.1.1" -> Ok(3232235777);
/// "01.2.3.4" -> Err; "1.2.3" -> Err.
/// Complexity: O(s.len()).
pub fn cidr_ip_parse(s: Str) -> Result[Int, Str] {
  let n = s.len();
  if n == 0 {
    return _ip_err("cidr: empty address");
  }
  let v = _cidr_scan_ip(s, 0, n);
  if v == -1 {
    return _ip_err("cidr: expected four octets");
  }
  if v == -2 {
    return _ip_err("cidr: invalid octet");
  }
  return _ip_ok(v);
}

/// Format the low 32 bits of `ip` as a dotted quad.
/// Params: ip - address value; only the low 32 bits are used (the value is
/// taken modulo 2^32), so -1 formats as 255.255.255.255 and 4294967296
/// formats as 0.0.0.0.
/// Returns: "a.b.c.d" with a,b,c,d in 0..255 and no leading zeros.
/// Error case: none.
/// Examples: 3232235777 -> "192.168.1.1"; 0 -> "0.0.0.0".
/// Complexity: O(1).
pub fn cidr_ip_format(ip: Int) -> Str {
  let v = ip & _CIDR_MAX32;
  let a = (v >> 24) & 255;
  let b = (v >> 16) & 255;
  let c = (v >> 8) & 255;
  let d = v & 255;
  return convert.int_to_string(a) + "." + convert.int_to_string(b) + "." + convert.int_to_string(c) + "." + convert.int_to_string(d);
}

/// Parse "a.b.c.d/len" into a canonical (network, prefix) pair.
/// Params: s - candidate CIDR text.
/// Returns: Ok((network, prefix)) where the address is parsed exactly like
/// cidr_ip_parse and then masked to the prefix, so host bits are cleared
/// ("192.168.1.77/24" -> Ok((3232235776, 24))); prefix is 0..32 and its
/// decimal form is canonical: "0" is valid, a leading zero ("/024") is not.
/// Error case: Err("cidr: empty input") for ""; Err("cidr: missing prefix
/// length") when no '/' is present; the cidr_ip_parse messages for a bad
/// address; Err("cidr: invalid prefix length") for an empty prefix, a
/// non-digit byte (including a second '/'), or a leading zero; and
/// Err("cidr: prefix length out of range") for a numeric prefix above 32.
/// Examples: "10.0.0.0/8" -> Ok((167772160, 8)); "1.2.3.4/32" ->
/// Ok((16909060, 32)); "1.2.3.4" -> Err; "1.2.3.4/33" -> Err.
/// Complexity: O(s.len()).
pub fn cidr_parse(s: Str) -> Result[(Int, Int), Str] {
  let n = s.len();
  if n == 0 {
    return _cidr_err("cidr: empty input");
  }
  let slash = _cidr_index_of(s, _CIDR_SLASH);
  if slash < 0 {
    return _cidr_err("cidr: missing prefix length");
  }
  let addr = _cidr_scan_ip(s, 0, slash);
  if addr == -1 {
    return _cidr_err("cidr: expected four octets");
  }
  if addr == -2 {
    return _cidr_err("cidr: invalid octet");
  }
  let plen = _cidr_scan_prefix(s, slash + 1, n);
  if plen < 0 {
    return _cidr_err("cidr: invalid prefix length");
  }
  if plen > 32 {
    return _cidr_err("cidr: prefix length out of range");
  }
  return _cidr_ok(addr & cidr_mask(plen), plen);
}

/// Format a (network, prefix) pair as "a.b.c.d/len".
/// Params: network - address value; prefix - block length.
/// Returns: cidr_ip_format(network & cidr_mask(prefix)) + "/" + prefix, so
/// host bits in `network` are cleared first. The prefix is echoed verbatim;
/// canonical callers pass 0..32.
/// Error case: none.
/// Examples: (3232235776, 24) -> "192.168.1.0/24"; (0, 0) -> "0.0.0.0/0".
/// Complexity: O(1).
pub fn cidr_format(network: Int, prefix: Int) -> Str {
  let net = (network & _CIDR_MAX32) & cidr_mask(prefix);
  return cidr_ip_format(net) + "/" + convert.int_to_string(prefix);
}

// --------------------------------------------------
//  Masking and range math
// --------------------------------------------------

/// Prefix mask: the top `prefix` bits set, all lower bits zero.
/// Params: prefix - block length.
/// Returns: for 0..32 the 32-bit mask (0 for /0, 4278190080 for /8,
/// 4294967295 for /32); 0 for every prefix outside 0..32. Because mask 0 is
/// the /0 mask, every other prefix-taking function treats such a prefix as
/// /0.
/// Error case: none.
/// Examples: (24) -> 4294967040; (32) -> 4294967295; (33) -> 0.
/// Complexity: O(1).
pub fn cidr_mask(prefix: Int) -> Int {
  if prefix < 0 || prefix > 32 {
    return 0;
  }
  let host_bits = 32 - prefix;
  let host_mask = (1 << host_bits) - 1;
  return _CIDR_MAX32 - host_mask;
}

/// Network address of the block that contains `ip`.
/// Params: ip - address value (low 32 bits); prefix - block length.
/// Returns: ip & cidr_mask(prefix). A prefix outside 0..32 behaves like /0,
/// so the result is 0.
/// Error case: none.
/// Examples: (3232235777, 24) -> 3232235776; (3232235777, 16) ->
/// 3232235520; (16909060, 32) -> 16909060; (16909060, 33) -> 0.
/// Complexity: O(1).
pub fn cidr_network(ip: Int, prefix: Int) -> Int {
  return (ip & _CIDR_MAX32) & cidr_mask(prefix);
}

/// Highest address in the block: the network address with every host bit
/// set.
/// Params: network - address value; prefix - block length.
/// Returns: (network & mask) | (4294967295 - mask). /32 gives back the
/// network itself; a prefix outside 0..32 behaves like /0, so the result is
/// 4294967295.
/// Error case: none.
/// Examples: (3232235776, 24) -> 3232236031; (0, 0) -> 4294967295.
/// Complexity: O(1).
pub fn cidr_broadcast(network: Int, prefix: Int) -> Int {
  let m = cidr_mask(prefix);
  return ((network & _CIDR_MAX32) & m) | (_CIDR_MAX32 - m);
}

/// True when `ip` is inside the block (network, prefix).
/// Params: network - network address (host bits are ignored); prefix - block
/// length; ip - address to test.
/// Returns: true when masking both `network` and `ip` to the prefix yields
/// the same value. Containment is inclusive: the network address and the
/// broadcast address are inside. A prefix outside 0..32 behaves like /0, so
/// every address is contained.
/// Error case: none.
/// Examples: (3232235776, 24, 3232235777) -> true;
/// (3232235776, 24, 3232236032) -> false; (3232235776, 31, 3232235777) ->
/// true.
/// Complexity: O(1).
pub fn cidr_contains(network: Int, prefix: Int, ip: Int) -> Bool {
  let m = cidr_mask(prefix);
  let net = (network & _CIDR_MAX32) & m;
  let target = (ip & _CIDR_MAX32) & m;
  return net == target;
}

/// True when two CIDR blocks share at least one address.
/// Params: a_net, a_prefix - first block; b_net, b_prefix - second block.
/// Returns: true when the inclusive address ranges [network, broadcast] of
/// the two blocks intersect, which covers partial overlap, containment in
/// either direction and equality. Blocks with different prefixes are
/// compared directly, without canonicalising either one. A prefix outside
/// 0..32 behaves like /0, so such a block overlaps everything.
/// Error case: none.
/// Examples: (10.0.0.0/8, 10.1.0.0/16) -> true (containment);
/// (10.0.0.0/8, 11.0.0.0/8) -> false (disjoint).
/// Complexity: O(1).
pub fn cidr_overlap(a_net: Int, a_prefix: Int, b_net: Int, b_prefix: Int) -> Bool {
  let a_lo = cidr_network(a_net, a_prefix);
  let a_hi = cidr_broadcast(a_net, a_prefix);
  let b_lo = cidr_network(b_net, b_prefix);
  let b_hi = cidr_broadcast(b_net, b_prefix);
  return a_lo <= b_hi && b_lo <= a_hi;
}

/// Number of addresses in the block: 2^(32 - prefix).
/// Params: prefix - block length.
/// Returns: for 0..32 the exact address count -- 4294967296 for /0 (the
/// value is a 64-bit Int and does not wrap), 256 for /24, 4 for /30,
/// 1 for /32. A prefix outside 0..32 behaves like /0 and also returns
/// 4294967296.
/// Error case: none.
/// Examples: (0) -> 4294967296; (24) -> 256; (32) -> 1.
/// Complexity: O(1).
pub fn cidr_host_count(prefix: Int) -> Int {
  return _CIDR_MAX32 - cidr_mask(prefix) + 1;
}

/// First usable host address of the block.
/// Params: network - network address (host bits are ignored); prefix - block
/// length.
/// Returns: network + 1 for prefixes 0..30; for /31 and /32 the network
/// address itself, because those blocks have no separate host range under
/// this library's convention. A prefix outside 0..32 behaves like /0, so the
/// result is 1 (0.0.0.1).
/// Error case: none.
/// Examples: (3232235776, 24) -> 3232235777; (16909060, 32) -> 16909060.
/// Complexity: O(1).
pub fn cidr_first_host(network: Int, prefix: Int) -> Int {
  let net = (network & _CIDR_MAX32) & cidr_mask(prefix);
  if prefix == 31 || prefix == 32 {
    return net;
  }
  return net + 1;
}

/// Last usable host address of the block.
/// Params: network - network address (host bits are ignored); prefix - block
/// length.
/// Returns: broadcast - 1 for prefixes 0..30, i.e. net + 2^(32-prefix) - 2
/// (so a /24 ends at .254 and a /30 at net+2); the network and broadcast
/// addresses are excluded because they are not usable host addresses. For
/// /31 and /32 the network address itself, following cidr_first_host. A
/// prefix outside 0..32 behaves like /0, so the result is 4294967294
/// (255.255.255.254).
/// Error case: none.
/// Examples: (3232235776, 24) -> 3232236030; (16909060, 32) -> 16909060.
/// Complexity: O(1).
pub fn cidr_last_host(network: Int, prefix: Int) -> Int {
  let net = (network & _CIDR_MAX32) & cidr_mask(prefix);
  if prefix == 31 || prefix == 32 {
    return net;
  }
  return net + cidr_host_count(prefix) - 2;
}
