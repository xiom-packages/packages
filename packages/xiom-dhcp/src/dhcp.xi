// XIOM -- xiom.dhcp: DHCPv4 packet codec (BOOTP fixed header + options TLV)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the RFC 2131/2132 wire subset -- the fixed 236-byte BOOTP header,
// the 99.130.83.99 magic cookie and the options area as TLV entries. The
// codec parses any DHCPv4 packet (OFFER and ACK being the interesting server
// replies) and builds BOOTREQUEST client messages (DISCOVER and REQUEST).
// Option values stay in the source buffer and are located by absolute
// offsets, following the xiom.tlv / xiom.pcap index precedent;
// dhcp_option_value copies a value out on demand.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; a byte
//     value is never compared to an Int constant without that widening.
//   * multi-byte fields are read and packed with arithmetic only (v0.61.3
//     miscompiles `& 0xFF` on values with bit 31 set; see xiom.tlv).
//   * DhcpPacket is constructed inside dhcp_parse only and crosses function
//     boundaries by reference or through _ok_packet (xiom.pcap precedent).
//   * Vec[Int] element reads are bound to typed locals before use; no `==`
//     is ever applied to a Str read from a Vec (BUG 17) -- the module has
//     no Str fields at all.
// See SPEC.md for the byte layout tables, error catalog and test matrix.

module xiom.dhcp

/// Parsed DHCPv4 packet. The fixed header fields are decoded; `broadcast` is
/// bit 15 (0x8000) of `flags`. `chaddr`, `sname` and `file` are copied raw
/// (16/64/128 bytes). `option_codes`, `option_offsets` and `option_lengths`
/// are parallel vectors, one entry per non-pad option in wire order,
/// excluding the end option; `option_offsets[i]` is the absolute index of
/// the value bytes inside the parsed buffer. Fields are implementation
/// details; callers should go through the free functions below.
pub type DhcpPacket = {
  op: Int;
  htype: Int;
  hlen: Int;
  hops: Int;
  xid: Int;
  secs: Int;
  flags: Int;
  broadcast: Bool;
  ciaddr: Int;
  yiaddr: Int;
  siaddr: Int;
  giaddr: Int;
  chaddr: Vec[UInt8];
  sname: Vec[UInt8];
  file: Vec[UInt8];
  option_codes: Vec[Int];
  option_offsets: Vec[Int];
  option_lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[DhcpPacket, Str].
fn _ok_packet(v: DhcpPacket) -> Result[DhcpPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[DhcpPacket, Str].
fn _err_packet(m: Str) -> Result[DhcpPacket, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned 16-bit integer at [pos, pos+2), big-endian. The caller guarantees
// the two bytes are in bounds.
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  return b0 * 256 + b1;
}

// Unsigned 32-bit integer at [pos, pos+4), big-endian, returned in an Int
// (0..4294967295). The caller guarantees the four bytes are in bounds.
fn _u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0: Int = _byte(data, pos);
  let b1: Int = _byte(data, pos + 1);
  let b2: Int = _byte(data, pos + 2);
  let b3: Int = _byte(data, pos + 3);
  return b0 * 16777216 + b1 * 65536 + b2 * 256 + b3;
}

// Big-endian byte `shift_bytes` of `v` (0 = least significant byte).
// Arithmetic only: `& 0xFF` on values with bit 31 set miscompiles in
// v0.61.3, and this form is exact for negative two's-complement values.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in big-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_be_byte(v, i));
    i = i - 1;
  }
}

// --------------------------------------------------
//  Option shape rules
// --------------------------------------------------

// True when option `code`'s RFC 2132 shape accepts a value of `len` bytes:
// 1 subnet mask 4; 3 router >= 4 and a multiple of 4; 6 DNS >= 4 and a
// multiple of 4; 12 hostname >= 1; 50 requested IP 4; 51 lease time 4;
// 53 message type 1; 54 server id 4; 55 parameter request list >= 1;
// 61 client id >= 2. Unknown codes accept any length.
fn _option_len_ok(code: Int, len: Int) -> Bool {
  if code == 1 {
    return len == 4;
  }
  if code == 3 {
    if len < 4 {
      return false;
    }
    return len % 4 == 0;
  }
  if code == 6 {
    if len < 4 {
      return false;
    }
    return len % 4 == 0;
  }
  if code == 12 {
    return len >= 1;
  }
  if code == 50 {
    return len == 4;
  }
  if code == 51 {
    return len == 4;
  }
  if code == 53 {
    return len == 1;
  }
  if code == 54 {
    return len == 4;
  }
  if code == 55 {
    return len >= 1;
  }
  if code == 61 {
    return len >= 2;
  }
  return true;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Cheap sniff: `data` is at least the 240 fixed bytes (236-byte header plus
/// the magic cookie) and the cookie at offset 236 is 99.130.83.99. Option
/// bytes are not inspected, so this can be true for a packet `dhcp_parse`
/// later rejects. Complexity: O(1).
pub fn dhcp_is_packet(data: &Vec[UInt8]) -> Bool {
  if data.len() < 240 {
    return false;
  }
  if _byte(data, 236) != 99 { return false; }
  if _byte(data, 237) != 130 { return false; }
  if _byte(data, 238) != 83 { return false; }
  if _byte(data, 239) != 99 { return false; }
  return true;
}

/// Parse one DHCPv4 packet.
///
/// `data` must hold the whole packet: the 236-byte BOOTP header, the magic
/// cookie 99.130.83.99 at offset 236, and the options area from offset 240
/// to the end option (255). Pad bytes (0) are skipped; bytes after the end
/// option are ignored. Every non-pad option is indexed by code, absolute
/// value offset and declared length.
///
/// Errors (all stable):
///   * `dhcp: short packet` -- fewer than 240 bytes;
///   * `dhcp: bad cookie` -- the four bytes at 236 are not 99.130.83.99;
///   * `dhcp: truncated option` -- an option code with no length byte, or a
///     declared value that runs past the buffer end;
///   * `dhcp: bad option length` -- a documented option whose length its
///     RFC 2132 shape does not allow (see SPEC.md);
///   * `dhcp: missing end` -- the options end without the 255 end marker.
/// Precedence is: length, cookie, option walk in wire order, end marker.
/// The whole call is Err on the first malformed option; no partial packet
/// is returned. Complexity: O(data.len()).
pub fn dhcp_parse(data: &Vec[UInt8]) -> Result[DhcpPacket, Str] {
  let n = data.len();
  if n < 240 {
    return _err_packet("dhcp: short packet");
  }
  if _byte(data, 236) != 99 { return _err_packet("dhcp: bad cookie"); }
  if _byte(data, 237) != 130 { return _err_packet("dhcp: bad cookie"); }
  if _byte(data, 238) != 83 { return _err_packet("dhcp: bad cookie"); }
  if _byte(data, 239) != 99 { return _err_packet("dhcp: bad cookie"); }
  let op = _byte(data, 0);
  let htype = _byte(data, 1);
  let hlen = _byte(data, 2);
  let hops = _byte(data, 3);
  let xid = _u32(data, 4);
  let secs = _u16(data, 8);
  let flags = _u16(data, 10);
  var bcast = false;
  if flags >= 32768 {
    bcast = true;
  }
  let ciaddr = _u32(data, 12);
  let yiaddr = _u32(data, 16);
  let siaddr = _u32(data, 20);
  let giaddr = _u32(data, 24);
  var chaddr = Vec[UInt8].new();
  var sname = Vec[UInt8].new();
  var file = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    chaddr.push(data[28 + i]);
    i = i + 1;
  }
  i = 0;
  while i < 64 {
    sname.push(data[44 + i]);
    i = i + 1;
  }
  i = 0;
  while i < 128 {
    file.push(data[108 + i]);
    i = i + 1;
  }
  var codes = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var pos = 240;
  var ended = false;
  while pos < n {
    let code: Int = _byte(data, pos);
    if code == 0 {
      pos = pos + 1;
    } elif code == 255 {
      ended = true;
      pos = n;
    } else {
      if pos + 1 >= n {
        return _err_packet("dhcp: truncated option");
      }
      let len: Int = _byte(data, pos + 1);
      if pos + 2 + len > n {
        return _err_packet("dhcp: truncated option");
      }
      if !_option_len_ok(code, len) {
        return _err_packet("dhcp: bad option length");
      }
      codes.push(code);
      offsets.push(pos + 2);
      lengths.push(len);
      pos = pos + 2 + len;
    }
  }
  if !ended {
    return _err_packet("dhcp: missing end");
  }
  let p = DhcpPacket{
    op: op;
    htype: htype;
    hlen: hlen;
    hops: hops;
    xid: xid;
    secs: secs;
    flags: flags;
    broadcast: bcast;
    ciaddr: ciaddr;
    yiaddr: yiaddr;
    siaddr: siaddr;
    giaddr: giaddr;
    chaddr: chaddr;
    sname: sname;
    file: file;
    option_codes: codes;
    option_offsets: offsets;
    option_lengths: lengths;
  };
  return _ok_packet(p);
}

// --------------------------------------------------
//  Option index accessors
// --------------------------------------------------

/// Number of indexed non-pad options (the end option is not indexed).
/// Complexity: O(1).
pub fn dhcp_option_count(p: &DhcpPacket) -> Int {
  return p.option_codes.len();
}

/// Option code at index `i`, or -1 when `i` is negative or >= count.
/// Complexity: O(1).
pub fn dhcp_option_code(p: &DhcpPacket, i: Int) -> Int {
  if i < 0 || i >= p.option_codes.len() {
    return -1;
  }
  let c: Int = p.option_codes[i];
  return c;
}

/// Declared value length (bytes) of option `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn dhcp_option_length(p: &DhcpPacket, i: Int) -> Int {
  if i < 0 || i >= p.option_lengths.len() {
    return -1;
  }
  let l: Int = p.option_lengths[i];
  return l;
}

/// First index whose option code equals `code`, or -1 when absent. Duplicate
/// options are preserved in wire order; the first match wins.
/// Complexity: O(options).
pub fn dhcp_find_option(p: &DhcpPacket, code: Int) -> Int {
  var i = 0;
  while i < p.option_codes.len() {
    let c: Int = p.option_codes[i];
    if c == code {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy the value bytes of option `i` out of `data` (the buffer passed to
/// dhcp_parse; offsets are absolute).
///
/// Err("dhcp: option index out of range") when `i` is negative or >= count;
/// Err("dhcp: option out of bounds") when the recorded span does not fit
/// `data` (for example when a shorter buffer is passed). A zero-length value
/// yields an empty Ok. Complexity: O(value length).
pub fn dhcp_option_value(data: &Vec[UInt8], p: &DhcpPacket, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= p.option_codes.len() {
    return _err_bytes("dhcp: option index out of range");
  }
  let off: Int = p.option_offsets[i];
  let len: Int = p.option_lengths[i];
  if off < 0 || len < 0 {
    return _err_bytes("dhcp: option out of bounds");
  }
  if off + len > data.len() {
    return _err_bytes("dhcp: option out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Typed option readers
// --------------------------------------------------

/// Message type (option 53): 1 DISCOVER, 2 OFFER, 3 REQUEST, 4 DECLINE,
/// 5 ACK, 6 NAK, 7 RELEASE, 8 INFORM. The value byte is returned as-is;
/// values outside 1..8 are not rejected (documented limitation). Returns -1
/// when option 53 is absent or malformed. Complexity: O(1) after the index.
pub fn dhcp_message_type(data: &Vec[UInt8], p: &DhcpPacket) -> Int {
  let idx = dhcp_find_option(p, 53);
  if idx < 0 {
    return -1;
  }
  let len: Int = p.option_lengths[idx];
  if len != 1 {
    return -1;
  }
  let off: Int = p.option_offsets[idx];
  if off < 0 || off + 1 > data.len() {
    return -1;
  }
  return _byte(data, off);
}

/// Unsigned big-endian 32-bit value of the single-address option `code`
/// (1, 50, 51, 54, ...), or -1 when absent, not exactly 4 bytes, or out of
/// bounds. For multi-address options (3, 6) use the list accessors.
/// Complexity: O(1) after the index.
pub fn dhcp_option_u32(data: &Vec<UInt8>, p: &DhcpPacket, code: Int) -> Int {
  let idx = dhcp_find_option(p, code);
  if idx < 0 {
    return -1;
  }
  let len: Int = p.option_lengths[idx];
  if len != 4 {
    return -1;
  }
  let off: Int = p.option_offsets[idx];
  if off < 0 || off + 4 > data.len() {
    return -1;
  }
  return _u32(data, off);
}

/// Subnet mask (option 1) as an unsigned 32-bit Int; -1 when absent.
/// Complexity: O(1) after the index.
pub fn dhcp_subnet_mask(data: &Vec<UInt8>, p: &DhcpPacket) -> Int {
  return dhcp_option_u32(data, p, 1);
}

/// Requested IP address (option 50) as an unsigned 32-bit Int; -1 when
/// absent. Complexity: O(1) after the index.
pub fn dhcp_requested_ip(data: &Vec<UInt8>, p: &DhcpPacket) -> Int {
  return dhcp_option_u32(data, p, 50);
}

/// Lease time in seconds (option 51) as an unsigned 32-bit Int; -1 when
/// absent. Complexity: O(1) after the index.
pub fn dhcp_lease_time(data: &Vec[UInt8], p: &DhcpPacket) -> Int {
  return dhcp_option_u32(data, p, 51);
}

/// Server identifier (option 54) as an unsigned 32-bit Int; -1 when absent.
/// Complexity: O(1) after the index.
pub fn dhcp_server_id(data: &Vec[UInt8], p: &DhcpPacket) -> Int {
  return dhcp_option_u32(data, p, 54);
}

// Byte span of option `code` when it holds an IPv4 address list (>= 4 bytes,
// a multiple of 4, inside `data`); 0 when absent or malformed.
fn _ip_list_span(data: &Vec[UInt8], p: &DhcpPacket, code: Int) -> Int {
  let idx = dhcp_find_option(p, code);
  if idx < 0 {
    return 0;
  }
  let len: Int = p.option_lengths[idx];
  if len < 4 || len % 4 != 0 {
    return 0;
  }
  let off: Int = p.option_offsets[idx];
  if off < 0 || off + len > data.len() {
    return 0;
  }
  return len;
}

// k-th IPv4 address (0-based) of option `code`; -1 when out of range.
fn _ip_at(data: &Vec[UInt8], p: &DhcpPacket, code: Int, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  let span = _ip_list_span(data, p, code);
  if span == 0 {
    return -1;
  }
  if k * 4 + 4 > span {
    return -1;
  }
  let idx = dhcp_find_option(p, code);
  let off: Int = p.option_offsets[idx];
  return _u32(data, off + k * 4);
}

/// Number of router addresses in option 3 (0 when absent). The option is a
/// list of 4-byte IPv4 addresses. Complexity: O(1) after the index.
pub fn dhcp_router_count(data: &Vec[UInt8], p: &DhcpPacket) -> Int {
  return _ip_list_span(data, p, 3) / 4;
}

/// k-th router address (0-based) from option 3; -1 when out of range.
/// Complexity: O(1) after the index.
pub fn dhcp_router_at(data: &Vec[UInt8], p: &DhcpPacket, k: Int) -> Int {
  return _ip_at(data, p, 3, k);
}

/// Number of DNS server addresses in option 6 (0 when absent). The option is
/// a list of 4-byte IPv4 addresses. Complexity: O(1) after the index.
pub fn dhcp_dns_count(data: &Vec[UInt8], p: &DhcpPacket) -> Int {
  return _ip_list_span(data, p, 6) / 4;
}

/// k-th DNS server address (0-based) from option 6; -1 when out of range.
/// Complexity: O(1) after the index.
pub fn dhcp_dns_at(data: &Vec[UInt8], p: &DhcpPacket, k: Int) -> Int {
  return _ip_at(data, p, 6, k);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Append one encoded option (code, length, value) to `out`.
///
/// Err("dhcp: bad option code") when `code` is outside 1..254 (0 is pad and
/// 255 is end; the builders append the end byte themselves);
/// Err("dhcp: option value too long") when value.len() > 255;
/// Err("dhcp: bad option length") when a documented code's shape rule
/// rejects the value (same rules as dhcp_parse). All validation happens
/// before any byte is written, so `out` is unchanged on Err.
/// Complexity: O(value length).
pub fn dhcp_append_option(out: &mut Vec[UInt8], code: Int, value: &Vec[UInt8]) -> Result[Unit, Str] {
  if code < 1 || code > 254 {
    return _err_unit("dhcp: bad option code");
  }
  let n = value.len();
  if n > 255 {
    return _err_unit("dhcp: option value too long");
  }
  if !_option_len_ok(code, n) {
    return _err_unit("dhcp: bad option length");
  }
  out.push(code as UInt8);
  out.push(n as UInt8);
  var i = 0;
  while i < n {
    out.push(value[i]);
    i = i + 1;
  }
  return _ok_unit();
}

// Documented client-header error for build_client and the two convenience
// builders, or "" when xid and chaddr are valid. Checked first everywhere so
// the error is deterministic across the builders.
fn _client_header_err(xid: Int, chaddr: &Vec[UInt8]) -> Str {
  if xid < 0 || xid > 4294967295 {
    return "dhcp: bad xid";
  }
  let n = chaddr.len();
  if n < 1 || n > 16 {
    return "dhcp: bad chaddr length";
  }
  return "";
}

/// Build a BOOTREQUEST frame around caller-encoded options.
///
/// The fixed header is op=1 (BOOTREQUEST), htype=1 (Ethernet), hlen =
/// chaddr.len(), hops=0, zero secs, the given `broadcast` bit (0x8000 in
/// `flags`), zero addresses, chaddr padded with zeros to 16 bytes, zeroed
/// sname and file. The magic cookie is written, then `options` verbatim,
/// then the end option (255). `options` must hold complete TLV entries and
/// must NOT contain its own end option.
///
/// Err("dhcp: bad xid") when xid is outside 0..4294967295;
/// Err("dhcp: bad chaddr length") when chaddr is empty or longer than 16.
/// Nothing is written on Err. Complexity: O(chaddr + options).
pub fn dhcp_build_client(xid: Int, chaddr: &Vec<UInt8>, broadcast: Bool, options: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let he = _client_header_err(xid, chaddr);
  if he.len() > 0 {
    return _err_bytes(he);
  }
  let hlen = chaddr.len();
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  out.push(1 as UInt8);
  out.push(hlen as UInt8);
  out.push(0 as UInt8);
  _push_be(&mut out, xid, 4);
  _push_be(&mut out, 0, 2);
  if broadcast {
    _push_be(&mut out, 32768, 2);
  } else {
    _push_be(&mut out, 0, 2);
  }
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  _push_be(&mut out, 0, 4);
  var i = 0;
  while i < 16 {
    if i < hlen {
      out.push(chaddr[i]);
    } else {
      out.push(0 as UInt8);
    }
    i = i + 1;
  }
  i = 0;
  while i < 64 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  i = 0;
  while i < 128 {
    out.push(0 as UInt8);
    i = i + 1;
  }
  out.push(99 as UInt8);
  out.push(130 as UInt8);
  out.push(83 as UInt8);
  out.push(99 as UInt8);
  i = 0;
  while i < options.len() {
    out.push(options[i]);
    i = i + 1;
  }
  out.push(255 as UInt8);
  return _ok_bytes(out);
}

/// Build a DHCPDISCOVER frame (message type 1) for `xid` and `chaddr`.
///
/// The options are, in order: 53 = 1, 61 = client id (htype byte 1 followed
/// by chaddr), 55 = parameter request list {1, 3, 6, 12, 51, 54}. The
/// broadcast bit is set. Errors are the documented client-header errors of
/// dhcp_build_client. Complexity: O(chaddr).
pub fn dhcp_build_discover(xid: Int, chaddr: &Vec<UInt8>) -> Result[Vec[UInt8], Str] {
  let he = _client_header_err(xid, chaddr);
  if he.len() > 0 {
    return _err_bytes(he);
  }
  var opts = Vec[UInt8].new();
  var mt = Vec[UInt8].new();
  mt.push(1 as UInt8);
  let r1 = dhcp_append_option(&mut opts, 53, &mt);
  if !r1.is_ok {
    return _err_bytes(r1.error);
  }
  var cid = Vec[UInt8].new();
  cid.push(1 as UInt8);
  var i = 0;
  while i < chaddr.len() {
    cid.push(chaddr[i]);
    i = i + 1;
  }
  let r2 = dhcp_append_option(&mut opts, 61, &cid);
  if !r2.is_ok {
    return _err_bytes(r2.error);
  }
  var prl = Vec[UInt8].new();
  prl.push(1 as UInt8);
  prl.push(3 as UInt8);
  prl.push(6 as UInt8);
  prl.push(12 as UInt8);
  prl.push(51 as UInt8);
  prl.push(54 as UInt8);
  let r3 = dhcp_append_option(&mut opts, 55, &prl);
  if !r3.is_ok {
    return _err_bytes(r3.error);
  }
  return dhcp_build_client(xid, chaddr, true, &opts);
}

/// Build a DHCPREQUEST frame (message type 3) for `xid` and `chaddr`.
///
/// The options are, in order: 53 = 3, 61 = client id (htype byte 1 followed
/// by chaddr), 50 = requested IP when `requested_ip >= 0`, 54 = server id
/// when `server_id >= 0`, 55 = parameter request list {1, 3, 6, 12, 51, 54}.
/// The broadcast bit is set and ciaddr stays zero: this builds the SELECTING
/// and INIT-REBOOT forms, not a RENEWING/REBINDING request.
///
/// Err("dhcp: bad ip address") when `requested_ip` or `server_id` exceeds
/// 4294967295 (negative values mean "omit the option"); otherwise the
/// documented client-header errors of dhcp_build_client.
/// Complexity: O(chaddr).
pub fn dhcp_build_request(xid: Int, chaddr: &Vec<UInt8>, requested_ip: Int, server_id: Int) -> Result[Vec[UInt8], Str] {
  let he = _client_header_err(xid, chaddr);
  if he.len() > 0 {
    return _err_bytes(he);
  }
  if requested_ip > 4294967295 {
    return _err_bytes("dhcp: bad ip address");
  }
  if server_id > 4294967295 {
    return _err_bytes("dhcp: bad ip address");
  }
  var opts = Vec[UInt8].new();
  var mt = Vec[UInt8].new();
  mt.push(3 as UInt8);
  let r1 = dhcp_append_option(&mut opts, 53, &mt);
  if !r1.is_ok {
    return _err_bytes(r1.error);
  }
  var cid = Vec[UInt8].new();
  cid.push(1 as UInt8);
  var i = 0;
  while i < chaddr.len() {
    cid.push(chaddr[i]);
    i = i + 1;
  }
  let r2 = dhcp_append_option(&mut opts, 61, &cid);
  if !r2.is_ok {
    return _err_bytes(r2.error);
  }
  if requested_ip >= 0 {
    var ip = Vec[UInt8].new();
    _push_be(&mut ip, requested_ip, 4);
    let r3 = dhcp_append_option(&mut opts, 50, &ip);
    if !r3.is_ok {
      return _err_bytes(r3.error);
    }
  }
  if server_id >= 0 {
    var sid = Vec[UInt8].new();
    _push_be(&mut sid, server_id, 4);
    let r4 = dhcp_append_option(&mut opts, 54, &sid);
    if !r4.is_ok {
      return _err_bytes(r4.error);
    }
  }
  var prl = Vec[UInt8].new();
  prl.push(1 as UInt8);
  prl.push(3 as UInt8);
  prl.push(6 as UInt8);
  prl.push(12 as UInt8);
  prl.push(51 as UInt8);
  prl.push(54 as UInt8);
  let r5 = dhcp_append_option(&mut opts, 55, &prl);
  if !r5.is_ok {
    return _err_bytes(r5.error);
  }
  return dhcp_build_client(xid, chaddr, true, &opts);
}
