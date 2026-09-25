// XIOM -- xiom.socks: SOCKS5 protocol codec (RFC 1928 + RFC 1929 subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: greenfield pure-XIOM port (no FFI) of the xiom.socks placeholder.
//
// Scope: the SOCKS5 wire messages a CONNECT client and server exchange --
// greeting (VER, NMETHODS, METHODS), method selection (VER, METHOD, including
// 0xFF "no acceptable methods"), CONNECT request (VER, CMD, RSV, ATYP,
// address, port), reply (REP 0x00..0x08, ATYP, BND.ADDR, BND.PORT) and the
// RFC 1929 username/password sub-negotiation (VER=1, ULEN, UNAME, PLEN,
// PASSWD and the status reply). Addresses are raw bytes in the parsed
// structs: 4 bytes for IPv4, 16 for IPv6, and the name bytes (no length
// prefix) for a domain. See SPEC.md for the byte layout tables, the error
// catalog and the documented limitations (no sockets, no SOCKS4, no
// BIND/UDP ASSOCIATE flows).
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; Ok/Err construction is confined
//     to the tiny leaf helpers below (constructing Results inside other
//     functions miscompiles).
//   * every Vec[UInt8] byte read is widened with `(data[pos] as Int) & 0xFF`
//     before entering Int arithmetic or comparisons.
//   * Vec elements are bound to typed locals (`let m: Int = methods[i]`)
//     before use; no `==` is applied to Str values read from a Vec.
//   * builders validate the whole message before writing a single byte, so
//     an Err leaves `out` untouched (atomic failure).

module xiom.socks

use xiom.string;

// --------------------------------------------------
//  Protocol constants (RFC 1928 / RFC 1929)
// --------------------------------------------------

/// SOCKS protocol version carried by every SOCKS5 message header.
pub const SOCKS5_VERSION: Int = 5;

/// Version byte of the RFC 1929 username/password sub-negotiation.
pub const AUTH_VERSION: Int = 1;

/// CMD 0x01: establish a TCP CONNECT stream.
pub const CMD_CONNECT: Int = 1;

/// CMD 0x02: BIND (structural only; no flow is implemented).
pub const CMD_BIND: Int = 2;

/// CMD 0x03: UDP ASSOCIATE (structural only; no flow is implemented).
pub const CMD_UDP_ASSOCIATE: Int = 3;

/// ATYP 0x01: the address is a 4-byte IPv4 address.
pub const ATYP_IPV4: Int = 1;

/// ATYP 0x03: the address is a length-prefixed domain name.
pub const ATYP_DOMAIN: Int = 3;

/// ATYP 0x04: the address is a 16-byte IPv6 address.
pub const ATYP_IPV6: Int = 4;

/// METHOD 0x00: no authentication required.
pub const METHOD_NO_AUTH: Int = 0;

/// METHOD 0x01: GSSAPI.
pub const METHOD_GSSAPI: Int = 1;

/// METHOD 0x02: username/password (RFC 1929).
pub const METHOD_USERPASS: Int = 2;

/// METHOD 0xFF: no acceptable methods (server refuses the greeting).
pub const METHOD_NO_ACCEPTABLE: Int = 255;

/// REP 0x00: succeeded.
pub const REP_SUCCEEDED: Int = 0;

/// REP 0x01: general SOCKS server failure.
pub const REP_GENERAL_FAILURE: Int = 1;

/// REP 0x02: connection not allowed by ruleset.
pub const REP_NOT_ALLOWED: Int = 2;

/// REP 0x03: network unreachable.
pub const REP_NETWORK_UNREACHABLE: Int = 3;

/// REP 0x04: host unreachable.
pub const REP_HOST_UNREACHABLE: Int = 4;

/// REP 0x05: connection refused.
pub const REP_CONNECTION_REFUSED: Int = 5;

/// REP 0x06: TTL expired.
pub const REP_TTL_EXPIRED: Int = 6;

/// REP 0x07: command not supported.
pub const REP_COMMAND_NOT_SUPPORTED: Int = 7;

/// REP 0x08: address type not supported.
pub const REP_ADDRESS_TYPE_NOT_SUPPORTED: Int = 8;

// --------------------------------------------------
//  Message types
// --------------------------------------------------

/// Parsed client greeting: the METHOD identifiers offered by the client, in
/// wire order, each 0..255. VER=5 and NMETHODS are validated by the parser
/// and are always 5 and methods.len() respectively. An empty list is
/// accepted (structurally valid, but offers nothing to the server).
pub type Socks5Greeting = {
  methods: Vec[Int];
}

/// Parsed server method selection: the single chosen METHOD, 0..255
/// (0xFF = no acceptable methods). VER=5 is validated by the parser.
pub type Socks5Choice = {
  method: Int;
}

/// Parsed CONNECT/BIND/UDP ASSOCIATE request. `cmd` is 0x01..0x03, `atyp`
/// is 0x01/0x03/0x04, `addr` holds the raw address bytes (4 for IPv4, 16 for
/// IPv6, the name bytes without the length prefix for a domain) and `port`
/// is 0..65535. VER=5 and RSV=0 are validated by the parser.
pub type Socks5Request = {
  cmd: Int;
  atyp: Int;
  addr: Vec[UInt8];
  port: Int;
}

/// Parsed server reply. `rep` is 0x00..0x08, `atyp` is 0x01/0x03/0x04,
/// `addr` holds BND.ADDR raw bytes (same encoding as Socks5Request.addr) and
/// `port` is BND.PORT, 0..65535. VER=5 and RSV=0 are validated by the parser.
pub type Socks5Reply = {
  rep: Int;
  atyp: Int;
  addr: Vec[UInt8];
  port: Int;
}

/// Parsed RFC 1929 username/password request. The credentials are raw bytes;
/// `uname` has 1..255 bytes, `passwd` 0..255 bytes.
pub type Socks5UserPass = {
  uname: Vec[UInt8];
  passwd: Vec[UInt8];
}

/// Parsed RFC 1929 status reply. `status` is 0 on success and nonzero on
/// failure. VER=1 is validated by the parser.
pub type Socks5AuthReply = {
  status: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Socks5Greeting, Str].
fn _ok_greeting(v: Socks5Greeting) -> Result[Socks5Greeting, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5Greeting, Str].
fn _err_greeting(m: Str) -> Result[Socks5Greeting, Str] {
  return Err(m);
}

// Ok(v) for Result[Socks5Choice, Str].
fn _ok_choice(v: Socks5Choice) -> Result[Socks5Choice, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5Choice, Str].
fn _err_choice(m: Str) -> Result[Socks5Choice, Str] {
  return Err(m);
}

// Ok(v) for Result[Socks5Request, Str].
fn _ok_request(v: Socks5Request) -> Result[Socks5Request, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5Request, Str].
fn _err_request(m: Str) -> Result[Socks5Request, Str] {
  return Err(m);
}

// Ok(v) for Result[Socks5Reply, Str].
fn _ok_reply(v: Socks5Reply) -> Result[Socks5Reply, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5Reply, Str].
fn _err_reply(m: Str) -> Result[Socks5Reply, Str] {
  return Err(m);
}

// Ok(v) for Result[Socks5UserPass, Str].
fn _ok_userpass(v: Socks5UserPass) -> Result[Socks5UserPass, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5UserPass, Str].
fn _err_userpass(m: Str) -> Result[Socks5UserPass, Str] {
  return Err(m);
}

// Ok(v) for Result[Socks5AuthReply, Str].
fn _ok_auth_reply(v: Socks5AuthReply) -> Result[Socks5AuthReply, Str] {
  return Ok(v);
}

// Err(m) for Result[Socks5AuthReply, Str].
fn _err_auth_reply(m: Str) -> Result[Socks5AuthReply, Str] {
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
//  Internal byte and validation helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Append one byte; the caller guarantees 0 <= v <= 255.
fn _push_byte(out: &mut Vec[UInt8], v: Int) {
  out.push(v as UInt8);
}

// Append a 16-bit big-endian value; the caller guarantees 0 <= v <= 65535.
fn _push_be16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append every byte of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// True when `cmd` is one of the three RFC 1928 commands.
fn _cmd_ok(cmd: Int) -> Bool {
  if cmd < CMD_CONNECT {
    return false;
  }
  if cmd > CMD_UDP_ASSOCIATE {
    return false;
  }
  return true;
}

// True when `rep` is one of the nine defined reply codes 0x00..0x08.
fn _rep_ok(rep: Int) -> Bool {
  if rep < REP_SUCCEEDED {
    return false;
  }
  if rep > REP_ADDRESS_TYPE_NOT_SUPPORTED {
    return false;
  }
  return true;
}

// True when `addr_len` is a well-formed address length for `atyp`: exactly 4
// bytes for IPv4, exactly 16 for IPv6, and 1..255 for a domain.
fn _addr_ok(atyp: Int, addr_len: Int) -> Bool {
  if atyp == ATYP_IPV4 {
    return addr_len == 4;
  }
  if atyp == ATYP_DOMAIN {
    return addr_len >= 1 && addr_len <= 255;
  }
  if atyp == ATYP_IPV6 {
    return addr_len == 16;
  }
  return false;
}

// Error for the first invalid address field (atyp before address length).
// Only called when _addr_ok(atyp, addr_len) is false.
fn _addr_err(atyp: Int, addr_len: Int) -> Str {
  if atyp == ATYP_IPV4 {
    return "socks: bad IPv4 length";
  }
  if atyp == ATYP_DOMAIN {
    if addr_len == 0 {
      return "socks: empty domain";
    }
    return "socks: domain too long";
  }
  if atyp == ATYP_IPV6 {
    return "socks: bad IPv6 length";
  }
  return "socks: unknown address type";
}

// Copy the `alen` address bytes at `apos` out of `data`. The caller
// guarantees the span is in bounds.
fn _read_addr(data: &Vec[UInt8], apos: Int, alen: Int) -> Vec[UInt8] {
  var addr = Vec[UInt8].new();
  var i = 0;
  while i < alen {
    addr.push(data[apos + i]);
    i = i + 1;
  }
  return addr;
}

// --------------------------------------------------
//  Greeting (client -> server)
// --------------------------------------------------

/// Append a SOCKS5 greeting to `out`: VER (5), NMETHODS (1 byte), then one
/// byte per method.
///
/// `methods` may be empty (a degenerate greeting that offers nothing) and
/// holds at most 255 entries; every method must be 0..255.
/// Err("socks: too many methods") when `methods.len() > 255`;
/// Err("socks: method out of range") when a method is negative or > 255.
/// All validation happens before any byte is written, so `out` is
/// byte-for-byte unchanged on Err (atomic failure).
/// Complexity: O(methods.len()).
pub fn socks5_greeting_build(out: &mut Vec[UInt8], methods: &Vec[Int]) -> Result[Unit, Str] {
  let n = methods.len();
  if n > 255 {
    return _err_unit("socks: too many methods");
  }
  var i = 0;
  while i < n {
    let m: Int = methods[i];
    if m < 0 || m > 255 {
      return _err_unit("socks: method out of range");
    }
    i = i + 1;
  }
  _push_byte(out, SOCKS5_VERSION);
  _push_byte(out, n);
  var k = 0;
  while k < n {
    let m2: Int = methods[k];
    _push_byte(out, m2);
    k = k + 1;
  }
  return _ok_unit();
}

/// Parse the first SOCKS5 greeting in `data`. The returned methods are in
/// wire order and each is 0..255; an empty METHODS list is accepted.
///
/// Errors (all stable):
///   * `socks: truncated greeting` -- fewer than 2 bytes;
///   * `socks: bad version` -- VER is not 5;
///   * `socks: truncated methods` -- fewer than NMETHODS method bytes
///     remain.
/// Bytes after the greeting are ignored (the caller frames the stream).
/// Complexity: O(NMETHODS).
pub fn socks5_greeting_parse(data: &Vec[UInt8]) -> Result[Socks5Greeting, Str] {
  let n = data.len();
  if n < 2 {
    return _err_greeting("socks: truncated greeting");
  }
  if _byte(data, 0) != SOCKS5_VERSION {
    return _err_greeting("socks: bad version");
  }
  let nmethods: Int = _byte(data, 1);
  if n - 2 < nmethods {
    return _err_greeting("socks: truncated methods");
  }
  var methods = Vec[Int].new();
  var i = 0;
  while i < nmethods {
    methods.push(_byte(data, 2 + i));
    i = i + 1;
  }
  return _ok_greeting(Socks5Greeting{ methods: methods; });
}

// --------------------------------------------------
//  Method selection (server -> client)
// --------------------------------------------------

/// Append a SOCKS5 method selection to `out`: VER (5) and METHOD.
///
/// Err("socks: method out of range") when `method` is negative or > 255
/// (0xFF = no acceptable methods is valid). `out` is unchanged on Err.
/// Complexity: O(1).
pub fn socks5_choice_build(out: &mut Vec[UInt8], method: Int) -> Result[Unit, Str] {
  if method < 0 || method > 255 {
    return _err_unit("socks: method out of range");
  }
  _push_byte(out, SOCKS5_VERSION);
  _push_byte(out, method);
  return _ok_unit();
}

/// Parse the first SOCKS5 method selection in `data`. The METHOD is returned
/// as-is (0..255), including 0xFF "no acceptable methods".
///
/// Errors (all stable):
///   * `socks: truncated choice` -- fewer than 2 bytes;
///   * `socks: bad version` -- VER is not 5.
/// Bytes after the selection are ignored.
/// Complexity: O(1).
pub fn socks5_choice_parse(data: &Vec[UInt8]) -> Result[Socks5Choice, Str] {
  if data.len() < 2 {
    return _err_choice("socks: truncated choice");
  }
  if _byte(data, 0) != SOCKS5_VERSION {
    return _err_choice("socks: bad version");
  }
  let method: Int = _byte(data, 1);
  return _ok_choice(Socks5Choice{ method: method; });
}

// --------------------------------------------------
//  Request (client -> server)
// --------------------------------------------------

/// Append a SOCKS5 request to `out`: VER (5), CMD, RSV (0), ATYP, ADDR and
/// PORT (2 bytes, big-endian). For ATYP=3 a one-byte domain length is
/// written before the name bytes; `addr` never carries that prefix.
///
/// Validation order (first failure wins):
///   1. `cmd` in 0x01..0x03          -> Err("socks: unknown command");
///   2. `atyp` in {1,3,4} and `addr` length valid for it
///      -> Err("socks: unknown address type") / Err("socks: bad IPv4
///      length") / Err("socks: empty domain") / Err("socks: domain too
///      long") (more than 255 bytes) / Err("socks: bad IPv6 length");
///   3. `port` in 0..65535           -> Err("socks: port out of range").
/// All validation happens before any byte is written, so `out` is
/// byte-for-byte unchanged on Err (atomic failure).
/// Complexity: O(addr.len()).
pub fn socks5_request_build(out: &mut Vec[UInt8], cmd: Int, atyp: Int, addr: &Vec[UInt8], port: Int) -> Result[Unit, Str] {
  if !_cmd_ok(cmd) {
    return _err_unit("socks: unknown command");
  }
  let alen = addr.len();
  if !_addr_ok(atyp, alen) {
    return _err_unit(_addr_err(atyp, alen));
  }
  if port < 0 || port > 65535 {
    return _err_unit("socks: port out of range");
  }
  _push_byte(out, SOCKS5_VERSION);
  _push_byte(out, cmd);
  _push_byte(out, 0);
  _push_byte(out, atyp);
  if atyp == ATYP_DOMAIN {
    _push_byte(out, alen);
  }
  _push_bytes(out, addr);
  _push_be16(out, port);
  return _ok_unit();
}

/// Parse the first SOCKS5 request in `data`.
///
/// Layout: VER, CMD, RSV, ATYP, ADDR, PORT; for ATYP=3 the address is a
/// length byte (1..255) followed by that many name bytes. The returned
/// `addr` holds the raw address bytes without the domain length prefix.
///
/// Errors (all stable, in check order):
///   * `socks: truncated request` -- fewer than 4 bytes;
///   * `socks: bad version` -- VER is not 5;
///   * `socks: unknown command` -- CMD is not 0x01..0x03;
///   * `socks: bad reserved byte` -- RSV is not 0;
///   * `socks: unknown address type` -- ATYP is not 1, 3 or 4;
///   * `socks: truncated address` -- the address does not fit;
///   * `socks: empty domain` -- a domain length of 0;
///   * `socks: truncated port` -- fewer than 2 port bytes remain.
/// Bytes after the request are ignored. Complexity: O(addr bytes).
pub fn socks5_request_parse(data: &Vec[UInt8]) -> Result[Socks5Request, Str] {
  let n = data.len();
  if n < 4 {
    return _err_request("socks: truncated request");
  }
  if _byte(data, 0) != SOCKS5_VERSION {
    return _err_request("socks: bad version");
  }
  let cmd: Int = _byte(data, 1);
  if !_cmd_ok(cmd) {
    return _err_request("socks: unknown command");
  }
  if _byte(data, 2) != 0 {
    return _err_request("socks: bad reserved byte");
  }
  let atyp: Int = _byte(data, 3);
  if atyp != ATYP_IPV4 && atyp != ATYP_DOMAIN && atyp != ATYP_IPV6 {
    return _err_request("socks: unknown address type");
  }
  var alen = 0;
  var apos = 4;
  if atyp == ATYP_IPV4 {
    alen = 4;
  } elif atyp == ATYP_IPV6 {
    alen = 16;
  } else {
    if n - 4 < 1 {
      return _err_request("socks: truncated address");
    }
    let dlen: Int = _byte(data, 4);
    if dlen == 0 {
      return _err_request("socks: empty domain");
    }
    alen = dlen;
    apos = 5;
  }
  if n - apos < alen {
    return _err_request("socks: truncated address");
  }
  let addr = _read_addr(data, apos, alen);
  let ppos = apos + alen;
  if n - ppos < 2 {
    return _err_request("socks: truncated port");
  }
  let port: Int = _byte(data, ppos) * 256 + _byte(data, ppos + 1);
  return _ok_request(Socks5Request{ cmd: cmd; atyp: atyp; addr: addr; port: port; });
}

// --------------------------------------------------
//  Reply (server -> client)
// --------------------------------------------------

/// Append a SOCKS5 reply to `out`: VER (5), REP, RSV (0), ATYP, BND.ADDR and
/// BND.PORT (2 bytes, big-endian). ATYP 3 writes the domain length prefix
/// like a request.
///
/// Validation order (first failure wins):
///   1. `rep` in 0x00..0x08         -> Err("socks: unknown reply code");
///   2. `atyp` and `addr` length as in socks5_request_build;
///   3. `port` in 0..65535          -> Err("socks: port out of range").
/// All validation happens before any byte is written, so `out` is
/// byte-for-byte unchanged on Err (atomic failure).
/// Complexity: O(addr.len()).
pub fn socks5_reply_build(out: &mut Vec[UInt8], rep: Int, atyp: Int, addr: &Vec[UInt8], port: Int) -> Result[Unit, Str] {
  if !_rep_ok(rep) {
    return _err_unit("socks: unknown reply code");
  }
  let alen = addr.len();
  if !_addr_ok(atyp, alen) {
    return _err_unit(_addr_err(atyp, alen));
  }
  if port < 0 || port > 65535 {
    return _err_unit("socks: port out of range");
  }
  _push_byte(out, SOCKS5_VERSION);
  _push_byte(out, rep);
  _push_byte(out, 0);
  _push_byte(out, atyp);
  if atyp == ATYP_DOMAIN {
    _push_byte(out, alen);
  }
  _push_bytes(out, addr);
  _push_be16(out, port);
  return _ok_unit();
}

/// Parse the first SOCKS5 reply in `data`, same layout as a request but with
/// REP in place of CMD and BND.ADDR/BND.PORT as the address fields.
///
/// Errors (all stable, in check order):
///   * `socks: truncated reply` -- fewer than 4 bytes;
///   * `socks: bad version` -- VER is not 5;
///   * `socks: unknown reply code` -- REP is not 0x00..0x08;
///   * `socks: bad reserved byte` -- RSV is not 0;
///   * `socks: unknown address type` / `socks: truncated address` /
///     `socks: empty domain` / `socks: truncated port` -- as in
///     socks5_request_parse.
/// Bytes after the reply are ignored. Complexity: O(addr bytes).
pub fn socks5_reply_parse(data: &Vec<UInt8>) -> Result[Socks5Reply, Str] {
  let n = data.len();
  if n < 4 {
    return _err_reply("socks: truncated reply");
  }
  if _byte(data, 0) != SOCKS5_VERSION {
    return _err_reply("socks: bad version");
  }
  let rep: Int = _byte(data, 1);
  if !_rep_ok(rep) {
    return _err_reply("socks: unknown reply code");
  }
  if _byte(data, 2) != 0 {
    return _err_reply("socks: bad reserved byte");
  }
  let atyp: Int = _byte(data, 3);
  if atyp != ATYP_IPV4 && atyp != ATYP_DOMAIN && atyp != ATYP_IPV6 {
    return _err_reply("socks: unknown address type");
  }
  var alen = 0;
  var apos = 4;
  if atyp == ATYP_IPV4 {
    alen = 4;
  } elif atyp == ATYP_IPV6 {
    alen = 16;
  } else {
    if n - 4 < 1 {
      return _err_reply("socks: truncated address");
    }
    let dlen: Int = _byte(data, 4);
    if dlen == 0 {
      return _err_reply("socks: empty domain");
    }
    alen = dlen;
    apos = 5;
  }
  if n - apos < alen {
    return _err_reply("socks: truncated address");
  }
  let addr = _read_addr(data, apos, alen);
  let ppos = apos + alen;
  if n - ppos < 2 {
    return _err_reply("socks: truncated port");
  }
  let port: Int = _byte(data, ppos) * 256 + _byte(data, ppos + 1);
  return _ok_reply(Socks5Reply{ rep: rep; atyp: atyp; addr: addr; port: port; });
}

// --------------------------------------------------
//  Username/password authentication (RFC 1929)
// --------------------------------------------------

/// Append an RFC 1929 username/password request to `out`: VER (1), ULEN
/// (1 byte), UNAME, PLEN (1 byte), PASSWD.
///
/// `uname` must have 1..255 bytes and `passwd` 0..255 bytes (an empty
/// password is accepted; an empty username is rejected).
/// Err("socks: empty username") / Err("socks: username too long") /
/// Err("socks: password too long"). All validation happens before any byte
/// is written, so `out` is unchanged on Err. Complexity: O(credentials).
pub fn socks5_auth_build(out: &mut Vec[UInt8], uname: &Vec[UInt8], passwd: &Vec[UInt8]) -> Result[Unit, Str] {
  let ulen = uname.len();
  if ulen == 0 {
    return _err_unit("socks: empty username");
  }
  if ulen > 255 {
    return _err_unit("socks: username too long");
  }
  let plen = passwd.len();
  if plen > 255 {
    return _err_unit("socks: password too long");
  }
  _push_byte(out, AUTH_VERSION);
  _push_byte(out, ulen);
  _push_bytes(out, uname);
  _push_byte(out, plen);
  _push_bytes(out, passwd);
  return _ok_unit();
}

/// Parse the first RFC 1929 username/password request in `data`.
///
/// Layout: VER (1), ULEN, UNAME, PLEN, PASSWD; both credentials are returned
/// as raw bytes. An empty password is accepted; an empty username is not.
///
/// Errors (all stable):
///   * `socks: truncated auth request` -- fewer than 2 bytes;
///   * `socks: bad auth version` -- VER is not 1;
///   * `socks: empty username` -- ULEN is 0;
///   * `socks: truncated username` -- UNAME does not fit;
///   * `socks: truncated password` -- the PLEN byte or PASSWD is missing.
/// Bytes after the request are ignored. Complexity: O(credential bytes).
pub fn socks5_auth_parse(data: &Vec<UInt8>) -> Result[Socks5UserPass, Str] {
  let n = data.len();
  if n < 2 {
    return _err_userpass("socks: truncated auth request");
  }
  if _byte(data, 0) != AUTH_VERSION {
    return _err_userpass("socks: bad auth version");
  }
  let ulen: Int = _byte(data, 1);
  if ulen == 0 {
    return _err_userpass("socks: empty username");
  }
  if n - 2 < ulen {
    return _err_userpass("socks: truncated username");
  }
  let plen_pos = 2 + ulen;
  if n - plen_pos < 1 {
    return _err_userpass("socks: truncated password");
  }
  let plen: Int = _byte(data, plen_pos);
  let ppos = plen_pos + 1;
  if n - ppos < plen {
    return _err_userpass("socks: truncated password");
  }
  var uname = Vec[UInt8].new();
  var i = 0;
  while i < ulen {
    uname.push(data[2 + i]);
    i = i + 1;
  }
  var passwd = Vec[UInt8].new();
  var j = 0;
  while j < plen {
    passwd.push(data[ppos + j]);
    j = j + 1;
  }
  return _ok_userpass(Socks5UserPass{ uname: uname; passwd: passwd; });
}

/// Append an RFC 1929 status reply to `out`: VER (1) and STATUS.
///
/// Err("socks: status out of range") when `status` is negative or > 255
/// (0 = success, nonzero = failure). `out` is unchanged on Err.
/// Complexity: O(1).
pub fn socks5_auth_reply_build(out: &mut Vec[UInt8], status: Int) -> Result[Unit, Str] {
  if status < 0 || status > 255 {
    return _err_unit("socks: status out of range");
  }
  _push_byte(out, AUTH_VERSION);
  _push_byte(out, status);
  return _ok_unit();
}

/// Parse the first RFC 1929 status reply in `data`: VER (1) and STATUS
/// (0 = success, nonzero = failure; any byte value is accepted).
///
/// Errors (all stable):
///   * `socks: truncated auth reply` -- fewer than 2 bytes;
///   * `socks: bad auth version` -- VER is not 1.
/// Bytes after the reply are ignored. Complexity: O(1).
pub fn socks5_auth_reply_parse(data: &Vec[UInt8]) -> Result[Socks5AuthReply, Str] {
  if data.len() < 2 {
    return _err_auth_reply("socks: truncated auth reply");
  }
  if _byte(data, 0) != AUTH_VERSION {
    return _err_auth_reply("socks: bad auth version");
  }
  let status: Int = _byte(data, 1);
  return _ok_auth_reply(Socks5AuthReply{ status: status; });
}

/// Copy the raw bytes of `name` into a fresh address vector usable as the
/// `addr` argument of socks5_request_build / socks5_reply_build with
/// ATYP=3. The one-byte length prefix is added by the builders; validation
/// (1..255 bytes) happens there. Complexity: O(name.len()).
pub fn socks5_domain_bytes(name: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < name.len() {
    v.push(string.byte_at(name, i));
    i = i + 1;
  }
  return v;
}
