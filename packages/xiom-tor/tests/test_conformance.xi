// XIOM -- xiom.tor conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: size constants, the variable-command rule,
// link/relay/END-reason/RESOLVED-type tables, narrow (2-byte CircID, 512)
// and wide (4-byte CircID, 514) fixed-cell framing, the nonzero-high-bytes
// auto-detection, tor_parse_cell_v, VERSIONS bodies and version choice,
// variable-length cells (VERSIONS, VPADDING, zero-length), consumed-count
// streams of concatenated cells, truncation and impossible-width errors,
// the 11-byte RELAY envelope with an unverified digest, typed BEGIN
// (hostname/IPv4/IPv6 + flags), CONNECTED (empty/IPv4/IPv6), END (reason
// table, EXITPOLICY address block, absent-TTL default), SENDME (legacy
// empty body, version 1 digest, structural errors), RESOLVE/RESOLVED
// (hostname/IPv4/error answers, multiple answers) and NETINFO bodies.
//
// All synthetic cells are built in-test from byte pushes. Str values are
// compared with xiom.string.compare.str_compare (BUG 17 discipline), every
// Vec read is bound to a typed local, every byte is pushed masked, and
// Result values are unwrapped through .is_ok/.value or match-free helpers.

module tor_tests
use xiom.io; use xiom.test;
use xiom.tor;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; a caller's byte
// comparison then fails).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn addb(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Concatenate the parts in order (byte-exact).
fn cat(parts: &Vec[Vec[UInt8]]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < parts.len() {
    let p: Vec[UInt8] = parts[i];
    addb(&mut out, &p);
    i = i + 1;
  }
  return out;
}

// Deterministic binary stream of n bytes.
fn bin(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 7 + 3) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// First n bytes of v (fewer when v is shorter).
fn trunc(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Bytes of v from index n to the end (empty when n >= len).
fn from_off(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = n;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when v is printable ASCII and equals want.
fn vec_str_eq(v: &Vec[UInt8], want: Str) -> Bool {
  let r = tor_ascii_to_str(v);
  if !r.is_ok {
    return false;
  }
  let t: Str = r.value;
  return str_eq(t, want);
}

// --------------------------------------------------
//  Synthetic wire builders
// --------------------------------------------------

fn push_u16(out: &mut Vec[UInt8], v: Int) {
  out.push(((v >> 8) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
}

fn push_u32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v >> 24) & 0xFF) as UInt8);
  out.push(((v >> 16) & 0xFF) as UInt8);
  out.push(((v >> 8) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
}

fn pad_to(out: &mut Vec[UInt8], n: Int) {
  while out.len() < n {
    out.push(0 as UInt8);
  }
}

// 2-byte CircID + command + body padded with zeros to 512 bytes.
fn cell_narrow(circ: Int, cmd: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_u16(&mut out, circ);
  out.push(cmd as UInt8);
  addb(&mut out, body);
  pad_to(&mut out, 512);
  return out;
}

// 4-byte CircID + command + body padded with zeros to 514 bytes.
fn cell_wide(circ: Int, cmd: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_u32(&mut out, circ);
  out.push(cmd as UInt8);
  addb(&mut out, body);
  pad_to(&mut out, 514);
  return out;
}

// 2-byte CircID + command + u16 length + body (narrow variable cell).
fn cell_var_n(circ: Int, cmd: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_u16(&mut out, circ);
  out.push(cmd as UInt8);
  push_u16(&mut out, body.len());
  addb(&mut out, body);
  return out;
}

// 4-byte CircID + command + u16 length + body (wide variable cell).
fn cell_var_w(circ: Int, cmd: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_u32(&mut out, circ);
  out.push(cmd as UInt8);
  push_u16(&mut out, body.len());
  addb(&mut out, body);
  return out;
}

// RELAY envelope: cmd(1) + recognized(2) + streamID(2) + digest(4) +
// length(2) + data.
fn relay_body(cmd: Int, rec: Int, sid: Int, dig: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(cmd as UInt8);
  push_u16(&mut out, rec);
  push_u16(&mut out, sid);
  addb(&mut out, dig);
  push_u16(&mut out, data.len());
  addb(&mut out, data);
  return out;
}

// RELAY envelope with recognized 0 and an all-zero digest.
fn relay_data(cmd: Int, sid: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  let dg = hb("00000000");
  return relay_body(cmd, 0, sid, &dg, data);
}

// --------------------------------------------------
//  Unwrap helpers (sentinels make the caller's checks fail deterministically)
// --------------------------------------------------

fn cell_ok(data: &Vec[UInt8], off: Int) -> TorCell {
  let r = tor_parse_cell(data, off);
  if r.is_ok {
    return r.value;
  }
  return TorCell{ wide: false; variable: false; circ_id: -1; command: -1; payload: Vec[UInt8].new(); consumed: 0; };
}

fn cellv_ok(data: &Vec[UInt8], off: Int, v: Int) -> TorCell {
  let r = tor_parse_cell_v(data, off, v);
  if r.is_ok {
    return r.value;
  }
  return TorCell{ wide: false; variable: false; circ_id: -1; command: -1; payload: Vec[UInt8].new(); consumed: 0; };
}

fn versions_ok(p: &Vec[UInt8], off: Int) -> TorVersions {
  let r = tor_parse_versions(p, off);
  if r.is_ok {
    return r.value;
  }
  return TorVersions{ versions: Vec[Int].new(); consumed: -1; };
}

fn relay_ok(p: &Vec[UInt8], off: Int) -> TorRelay {
  let r = tor_parse_relay(p, off);
  if r.is_ok {
    return r.value;
  }
  return TorRelay{
    cmd: -1;
    recognized: -1;
    stream_id: -1;
    digest: Vec[UInt8].new();
    length: -1;
    data: Vec[UInt8].new();
    consumed: -1;
  };
}

fn begin_ok(d: &Vec[UInt8]) -> TorBegin {
  let r = tor_relay_decode_begin(d);
  if r.is_ok {
    return r.value;
  }
  return TorBegin{ addr: Vec[UInt8].new(); port: -1; flags: -1; has_flags: false; };
}

fn connected_ok(d: &Vec[UInt8]) -> TorConnected {
  let r = tor_relay_decode_connected(d);
  if r.is_ok {
    return r.value;
  }
  return TorConnected{ kind: -1; addr: Vec[UInt8].new(); ttl: -1; };
}

fn end_ok(d: &Vec[UInt8]) -> TorEnd {
  let r = tor_relay_decode_end(d);
  if r.is_ok {
    return r.value;
  }
  return TorEnd{ reason: -1; has_addr: false; addr: Vec[UInt8].new(); ttl: -1; };
}

fn sendme_ok(d: &Vec[UInt8]) -> TorSendme {
  let r = tor_relay_decode_sendme(d);
  if r.is_ok {
    return r.value;
  }
  return TorSendme{ version: -1; legacy: false; data_len: -1; digest: Vec[UInt8].new(); };
}

fn resolve_ok(d: &Vec[UInt8]) -> TorResolve {
  let r = tor_relay_decode_resolve(d);
  if r.is_ok {
    return r.value;
  }
  return TorResolve{ name: Vec[UInt8].new() };
}

fn resolved_ok(d: &Vec[UInt8]) -> TorResolved {
  let r = tor_relay_decode_resolved(d);
  if r.is_ok {
    return r.value;
  }
  return TorResolved{ atype: -1; value: Vec[UInt8].new(); ttl: -1; consumed: -1 };
}

fn netinfo_ok(d: &Vec[UInt8], off: Int) -> TorNetinfo {
  let r = tor_decode_netinfo(d, off);
  if r.is_ok {
    return r.value;
  }
  return TorNetinfo{
    time: -1;
    other_atype: -1;
    other_addr: Vec[UInt8].new();
    n_my_addr: -1;
    my_atypes: Vec[Int].new();
    my_addrs: Vec[Vec[UInt8]].new();
    consumed: -1;
  };
}

// --------------------------------------------------
//  Error-text helpers
// --------------------------------------------------

fn err_cell_is(r: Result[TorCell, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_versions_is(r: Result[TorVersions, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_relay_is(r: Result[TorRelay, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_begin_is(r: Result[TorBegin, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_connected_is(r: Result[TorConnected, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_end_is(r: Result[TorEnd, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_sendme_is(r: Result[TorSendme, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_resolve_is(r: Result[TorResolve, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_resolved_is(r: Result[TorResolved, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_netinfo_is(r: Result[TorNetinfo, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return str_eq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if tor_cell_body_len() != 509 { ok = false; }
  if tor_cell_narrow_len() != 512 { ok = false; }
  if tor_cell_wide_len() != 514 { ok = false; }
  if tor_relay_header_len() != 11 { ok = false; }
  if tor_relay_max_data_fixed() != 498 { ok = false; }
  if tor_sendme_digest_len() != 20 { ok = false; }
  if tor_max_variable_len() != 65535 { ok = false; }
  if TOR_CELL_BODY_LEN != 509 { ok = false; }
  if TOR_CELL_NARROW_LEN != 512 { ok = false; }
  if TOR_CELL_WIDE_LEN != 514 { ok = false; }
  if !tor_cell_is_variable_cmd(TOR_LINK_CMD_VERSIONS) { ok = false; }
  if !tor_cell_is_variable_cmd(128) { ok = false; }
  if !tor_cell_is_variable_cmd(255) { ok = false; }
  if tor_cell_is_variable_cmd(TOR_LINK_CMD_PADDING) { ok = false; }
  if tor_cell_is_variable_cmd(TOR_LINK_CMD_RELAY) { ok = false; }
  if tor_cell_is_variable_cmd(TOR_LINK_CMD_PADDING_NEGOTIATE) { ok = false; }
  if !tor_link_version_valid(TOR_MIN_LINK_VERSION) { ok = false; }
  if !tor_link_version_valid(5) { ok = false; }
  if tor_link_version_valid(2) { ok = false; }
  if tor_link_version_valid(0) { ok = false; }
  return assert(ok, "sizes, variable-command rule and link version gate");
}

fn t2() -> TestResult {
  var ok = true;
  if TOR_LINK_CMD_PADDING != 0 { ok = false; }
  if TOR_LINK_CMD_CREATE != 1 { ok = false; }
  if TOR_LINK_CMD_CREATED != 2 { ok = false; }
  if TOR_LINK_CMD_RELAY != 3 { ok = false; }
  if TOR_LINK_CMD_DESTROY != 4 { ok = false; }
  if TOR_LINK_CMD_CREATE_FAST != 5 { ok = false; }
  if TOR_LINK_CMD_CREATED_FAST != 6 { ok = false; }
  if TOR_LINK_CMD_VERSIONS != 7 { ok = false; }
  if TOR_LINK_CMD_NETINFO != 8 { ok = false; }
  if TOR_LINK_CMD_RELAY_EARLY != 9 { ok = false; }
  if TOR_LINK_CMD_CREATE2 != 10 { ok = false; }
  if TOR_LINK_CMD_CREATED2 != 11 { ok = false; }
  if TOR_LINK_CMD_PADDING_NEGOTIATE != 12 { ok = false; }
  if !str_eq(tor_link_cmd_name(0), "PADDING") { ok = false; }
  if !str_eq(tor_link_cmd_name(1), "CREATE") { ok = false; }
  if !str_eq(tor_link_cmd_name(2), "CREATED") { ok = false; }
  if !str_eq(tor_link_cmd_name(3), "RELAY") { ok = false; }
  if !str_eq(tor_link_cmd_name(4), "DESTROY") { ok = false; }
  if !str_eq(tor_link_cmd_name(5), "CREATE_FAST") { ok = false; }
  if !str_eq(tor_link_cmd_name(6), "CREATED_FAST") { ok = false; }
  if !str_eq(tor_link_cmd_name(7), "VERSIONS") { ok = false; }
  if !str_eq(tor_link_cmd_name(8), "NETINFO") { ok = false; }
  if !str_eq(tor_link_cmd_name(9), "RELAY_EARLY") { ok = false; }
  if !str_eq(tor_link_cmd_name(10), "CREATE2") { ok = false; }
  if !str_eq(tor_link_cmd_name(11), "CREATED2") { ok = false; }
  if !str_eq(tor_link_cmd_name(12), "PADDING_NEGOTIATE") { ok = false; }
  if !str_eq(tor_link_cmd_name(13), "UNKNOWN") { ok = false; }
  if !str_eq(tor_link_cmd_name(255), "UNKNOWN") { ok = false; }
  return assert(ok, "link command table: 13 ids and names");
}

fn t3() -> TestResult {
  var ok = true;
  if TOR_RELAY_CMD_BEGIN != 1 { ok = false; }
  if TOR_RELAY_CMD_DATA != 2 { ok = false; }
  if TOR_RELAY_CMD_END != 3 { ok = false; }
  if TOR_RELAY_CMD_CONNECTED != 4 { ok = false; }
  if TOR_RELAY_CMD_SENDME != 5 { ok = false; }
  if TOR_RELAY_CMD_EXTEND != 6 { ok = false; }
  if TOR_RELAY_CMD_EXTENDED != 7 { ok = false; }
  if TOR_RELAY_CMD_TRUNCATE != 8 { ok = false; }
  if TOR_RELAY_CMD_TRUNCATED != 9 { ok = false; }
  if TOR_RELAY_CMD_DROP != 10 { ok = false; }
  if TOR_RELAY_CMD_RESOLVE != 11 { ok = false; }
  if TOR_RELAY_CMD_RESOLVED != 12 { ok = false; }
  if TOR_RELAY_CMD_BEGIN_DIR != 13 { ok = false; }
  if TOR_RELAY_CMD_EXTEND2 != 14 { ok = false; }
  if TOR_RELAY_CMD_EXTENDED2 != 15 { ok = false; }
  if !str_eq(tor_relay_cmd_name(1), "BEGIN") { ok = false; }
  if !str_eq(tor_relay_cmd_name(2), "DATA") { ok = false; }
  if !str_eq(tor_relay_cmd_name(3), "END") { ok = false; }
  if !str_eq(tor_relay_cmd_name(4), "CONNECTED") { ok = false; }
  if !str_eq(tor_relay_cmd_name(5), "SENDME") { ok = false; }
  if !str_eq(tor_relay_cmd_name(6), "EXTEND") { ok = false; }
  if !str_eq(tor_relay_cmd_name(7), "EXTENDED") { ok = false; }
  if !str_eq(tor_relay_cmd_name(8), "TRUNCATE") { ok = false; }
  if !str_eq(tor_relay_cmd_name(9), "TRUNCATED") { ok = false; }
  if !str_eq(tor_relay_cmd_name(10), "DROP") { ok = false; }
  if !str_eq(tor_relay_cmd_name(11), "RESOLVE") { ok = false; }
  if !str_eq(tor_relay_cmd_name(12), "RESOLVED") { ok = false; }
  if !str_eq(tor_relay_cmd_name(13), "BEGIN_DIR") { ok = false; }
  if !str_eq(tor_relay_cmd_name(14), "EXTEND2") { ok = false; }
  if !str_eq(tor_relay_cmd_name(15), "EXTENDED2") { ok = false; }
  if !str_eq(tor_relay_cmd_name(0), "UNKNOWN") { ok = false; }
  if !str_eq(tor_relay_cmd_name(16), "UNKNOWN") { ok = false; }
  return assert(ok, "relay command table: 15 ids and names");
}

fn t4() -> TestResult {
  var ok = true;
  if TOR_END_REASON_NONE != 0 { ok = false; }
  if !str_eq(tor_end_reason_name(0), "NONE") { ok = false; }
  if !str_eq(tor_end_reason_name(1), "MISC") { ok = false; }
  if !str_eq(tor_end_reason_name(2), "RESOLVEFAILED") { ok = false; }
  if !str_eq(tor_end_reason_name(3), "CONNECTREFUSED") { ok = false; }
  if !str_eq(tor_end_reason_name(4), "EXITPOLICY") { ok = false; }
  if !str_eq(tor_end_reason_name(5), "DESTROY") { ok = false; }
  if !str_eq(tor_end_reason_name(6), "DONE") { ok = false; }
  if !str_eq(tor_end_reason_name(7), "TIMEOUT") { ok = false; }
  if !str_eq(tor_end_reason_name(8), "NOROUTE") { ok = false; }
  if !str_eq(tor_end_reason_name(9), "HIBERNATING") { ok = false; }
  if !str_eq(tor_end_reason_name(10), "INTERNAL") { ok = false; }
  if !str_eq(tor_end_reason_name(11), "RESOURCELIMIT") { ok = false; }
  if !str_eq(tor_end_reason_name(12), "CONNRESET") { ok = false; }
  if !str_eq(tor_end_reason_name(13), "TORPROTOCOL") { ok = false; }
  if !str_eq(tor_end_reason_name(14), "NOTDIRECTORY") { ok = false; }
  if !str_eq(tor_end_reason_name(15), "UNKNOWN") { ok = false; }
  if !str_eq(tor_end_reason_name(255), "UNKNOWN") { ok = false; }
  if TOR_RESOLVED_TYPE_HOSTNAME != 0 { ok = false; }
  if TOR_RESOLVED_TYPE_IPV4 != 4 { ok = false; }
  if TOR_RESOLVED_TYPE_IPV6 != 6 { ok = false; }
  if TOR_RESOLVED_TYPE_ERROR_TRANSIENT != 240 { ok = false; }
  if TOR_RESOLVED_TYPE_ERROR_NONTRANSIENT != 241 { ok = false; }
  if !str_eq(tor_resolved_type_name(0), "HOSTNAME") { ok = false; }
  if !str_eq(tor_resolved_type_name(4), "IPV4") { ok = false; }
  if !str_eq(tor_resolved_type_name(6), "IPV6") { ok = false; }
  if !str_eq(tor_resolved_type_name(240), "ERROR_TRANSIENT") { ok = false; }
  if !str_eq(tor_resolved_type_name(241), "ERROR_NONTRANSIENT") { ok = false; }
  if !str_eq(tor_resolved_type_name(1), "UNKNOWN") { ok = false; }
  if !str_eq(tor_resolved_type_name(255), "UNKNOWN") { ok = false; }
  return assert(ok, "END reason and RESOLVED type tables");
}

fn t5() -> TestResult {
  var ok = true;
  let body = bin(509);
  let data = cell_narrow(0, TOR_LINK_CMD_PADDING, &body);
  let c = cell_ok(&data, 0);
  if c.wide { ok = false; }
  if c.variable { ok = false; }
  if c.circ_id != 0 { ok = false; }
  if c.command != TOR_LINK_CMD_PADDING { ok = false; }
  if c.consumed != 512 { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  if cp.len() != 509 { ok = false; }
  if !bytes_equal(cp, body) { ok = false; }
  let body2 = bin(509);
  let data2 = cell_narrow(0x1234, TOR_LINK_CMD_RELAY, &body2);
  let c2 = cellv_ok(&data2, 0, 3);
  if c2.wide { ok = false; }
  if c2.variable { ok = false; }
  if c2.circ_id != 0x1234 { ok = false; }
  if c2.command != TOR_LINK_CMD_RELAY { ok = false; }
  if c2.consumed != 512 { ok = false; }
  let cp2: Vec[UInt8] = c2.payload;
  if !bytes_equal(cp2, body2) { ok = false; }
  let c3 = cellv_ok(&data, 0, 0);
  if c3.wide { ok = false; }
  if c3.consumed != 512 { ok = false; }
  return assert(ok, "narrow fixed cell: 2-byte CircID, 509-byte body, 512 consumed");
}

fn t6() -> TestResult {
  var ok = true;
  let body = bin(509);
  let data = cell_wide(0x01020304, TOR_LINK_CMD_CREATE2, &body);
  let c = cell_ok(&data, 0);
  if !c.wide { ok = false; }
  if c.variable { ok = false; }
  if c.circ_id != 0x01020304 { ok = false; }
  if c.command != TOR_LINK_CMD_CREATE2 { ok = false; }
  if c.consumed != 514 { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  if cp.len() != 509 { ok = false; }
  if !bytes_equal(cp, body) { ok = false; }
  let data2 = cell_wide(0x00010001, TOR_LINK_CMD_DESTROY, &body);
  let c2 = cell_ok(&data2, 0);
  if !c2.wide { ok = false; }
  if c2.circ_id != 0x00010001 { ok = false; }
  if c2.command != TOR_LINK_CMD_DESTROY { ok = false; }
  if c2.consumed != 514 { ok = false; }
  let data3 = cell_wide(0, TOR_LINK_CMD_NETINFO, &body);
  let c3 = cellv_ok(&data3, 0, 5);
  if !c3.wide { ok = false; }
  if c3.circ_id != 0 { ok = false; }
  if c3.command != TOR_LINK_CMD_NETINFO { ok = false; }
  if c3.consumed != 514 { ok = false; }
  return assert(ok, "wide fixed cell: 4-byte CircID, 509-byte body, 514 consumed");
}

fn t7() -> TestResult {
  var ok = true;
  let vb = hb("000300040005");
  let data = cell_var_n(0, TOR_LINK_CMD_VERSIONS, &vb);
  if data.len() != 11 { ok = false; }
  let c = cell_ok(&data, 0);
  if c.wide { ok = false; }
  if !c.variable { ok = false; }
  if c.circ_id != 0 { ok = false; }
  if c.command != TOR_LINK_CMD_VERSIONS { ok = false; }
  if c.consumed != 11 { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  if cp.len() != 6 { ok = false; }
  let v = versions_ok(&cp, 0);
  if v.consumed != 6 { ok = false; }
  let vv: Vec[Int] = v.versions;
  if vv.len() != 3 { ok = false; }
  let v0: Int = vv[0];
  let v1: Int = vv[1];
  let v2: Int = vv[2];
  if v0 != 3 { ok = false; }
  if v1 != 4 { ok = false; }
  if v2 != 5 { ok = false; }
  let dataw = cell_var_w(0, TOR_LINK_CMD_VERSIONS, &vb);
  let cw = cellv_ok(&dataw, 0, 5);
  if !cw.wide { ok = false; }
  if !cw.variable { ok = false; }
  if cw.consumed != 13 { ok = false; }
  var sent = Vec[Int].new();
  sent.push(3);
  sent.push(4);
  sent.push(5);
  var recv = Vec[Int].new();
  recv.push(4);
  recv.push(5);
  recv.push(6);
  if tor_versions_choose(&sent, &recv) != 5 { ok = false; }
  var old = Vec[Int].new();
  old.push(1);
  old.push(2);
  old.push(3);
  var oldpeer = Vec[Int].new();
  oldpeer.push(1);
  oldpeer.push(2);
  oldpeer.push(3);
  if tor_versions_choose(&old, &oldpeer) != 3 { ok = false; }
  var only3 = Vec[Int].new();
  only3.push(3);
  var only4 = Vec[Int].new();
  only4.push(4);
  if tor_versions_choose(&only3, &only4) != 0 { ok = false; }
  var fwd = Vec[Int].new();
  fwd.push(7);
  if tor_versions_choose(&fwd, &fwd) != 7 { ok = false; }
  let odd = hb("0004ff");
  if !err_versions_is(tor_parse_versions(&odd, 0), "tor: versions body has odd length at 0") { ok = false; }
  let empty = Vec[UInt8].new();
  let ve = versions_ok(&empty, 0);
  if ve.consumed != 0 { ok = false; }
  if !err_versions_is(tor_parse_versions(&empty, 1), "tor: versions offset out of range at 1") { ok = false; }
  return assert(ok, "VERSIONS handshake: parse, consumed, choose highest common");
}

fn t8() -> TestResult {
  var ok = true;
  let body = bin(100);
  let data = cell_var_w(0x00020003, 128, &body);
  if data.len() != 107 { ok = false; }
  let c = cell_ok(&data, 0);
  if !c.wide { ok = false; }
  if !c.variable { ok = false; }
  if c.circ_id != 0x00020003 { ok = false; }
  if c.command != 128 { ok = false; }
  if c.consumed != 107 { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  if !bytes_equal(cp, body) { ok = false; }
  let empty = Vec[UInt8].new();
  let d2 = cell_var_w(0x00010005, 128, &empty);
  if d2.len() != 7 { ok = false; }
  let c2 = cellv_ok(&d2, 0, 5);
  if !c2.wide { ok = false; }
  if !c2.variable { ok = false; }
  if c2.consumed != 7 { ok = false; }
  let cp2: Vec[UInt8] = c2.payload;
  if cp2.len() != 0 { ok = false; }
  let d3 = cell_var_n(0, 128, &body);
  let c3 = cell_ok(&d3, 0);
  if c3.wide { ok = false; }
  if !c3.variable { ok = false; }
  if c3.consumed != 105 { ok = false; }
  return assert(ok, "wide variable cell: VPADDING framing, zero-length body, narrow variable");
}

fn t9() -> TestResult {
  var ok = true;
  let body = bin(509);
  let full = cell_narrow(0, TOR_LINK_CMD_PADDING, &body);
  let cut1 = trunc(&full, 511);
  if !err_cell_is(tor_parse_cell(&cut1, 0), "tor: fixed cell truncated at 0") { ok = false; }
  let fullw = cell_wide(0x01020304, TOR_LINK_CMD_CREATE2, &body);
  let cut2 = trunc(&fullw, 513);
  if !err_cell_is(tor_parse_cell(&cut2, 0), "tor: fixed cell truncated at 0") { ok = false; }
  let two = hb("0000");
  if !err_cell_is(tor_parse_cell(&two, 0), "tor: cell truncated at 0") { ok = false; }
  let four = hb("01000000");
  if !err_cell_is(tor_parse_cell(&four, 0), "tor: wide cell header truncated at 0") { ok = false; }
  if !err_cell_is(tor_parse_cell(&full, 600), "tor: cell offset out of range at 600") { ok = false; }
  if !err_cell_is(tor_parse_cell(&full, -1), "tor: cell offset out of range at -1") { ok = false; }
  if !err_cell_is(tor_parse_cell_v(&full, 0, -1), "tor: negative link version at 0") { ok = false; }
  let threew = hb("010203");
  if !err_cell_is(tor_parse_cell(&threew, 0), "tor: wide cell header truncated at 0") { ok = false; }
  return assert(ok, "truncation and impossible-width errors carry byte offsets");
}

fn t10() -> TestResult {
  var ok = true;
  var bad = Vec[UInt8].new();
  push_u32(&mut bad, 0x00020003);
  bad.push(128 as UInt8);
  push_u16(&mut bad, 10);
  bad.push(1 as UInt8);
  bad.push(2 as UInt8);
  bad.push(3 as UInt8);
  if !err_cell_is(tor_parse_cell(&bad, 0), "tor: variable cell body truncated at 0") { ok = false; }
  var bad2 = Vec[UInt8].new();
  push_u32(&mut bad2, 0x00010005);
  bad2.push(128 as UInt8);
  bad2.push(0 as UInt8);
  if !err_cell_is(tor_parse_cell(&bad2, 0), "tor: variable cell length truncated at 0") { ok = false; }
  let short = hb("0102030405060708090a");
  if !err_relay_is(tor_parse_relay(&short, 0), "tor: relay header truncated at 0") { ok = false; }
  let dig0 = hb("00000000");
  var rb = Vec[UInt8].new();
  rb.push(2 as UInt8);
  push_u16(&mut rb, 0);
  push_u16(&mut rb, 7);
  addb(&mut rb, &dig0);
  push_u16(&mut rb, 5);
  rb.push(0xAA as UInt8);
  rb.push(0xBB as UInt8);
  if !err_relay_is(tor_parse_relay(&rb, 0), "tor: relay length overrun at 0") { ok = false; }
  let rdata = relay_data(TOR_RELAY_CMD_DATA, 3, &bin(4));
  if !err_relay_is(tor_parse_relay(&rdata, 99), "tor: relay offset out of range at 99") { ok = false; }
  return assert(ok, "bad variable lengths and bad relay lengths are rejected");
}

fn t11() -> TestResult {
  var ok = true;
  let pad = cell_narrow(0, TOR_LINK_CMD_PADDING, &bin(10));
  let wide = cell_wide(0x01020304, TOR_LINK_CMD_CREATE2, &bin(10));
  let vb = hb("00030004");
  let vers = cell_var_n(0, TOR_LINK_CMD_VERSIONS, &vb);
  let vpad = cell_var_w(0x00020003, 128, &bin(20));
  var parts = Vec[Vec[UInt8]].new();
  parts.push(pad);
  parts.push(wide);
  parts.push(vers);
  parts.push(vpad);
  let buf = cat(&parts);
  if buf.len() != 1062 { ok = false; }
  let c1 = cell_ok(&buf, 0);
  if c1.command != TOR_LINK_CMD_PADDING { ok = false; }
  if c1.consumed != 512 { ok = false; }
  let o2 = c1.consumed;
  let c2 = cell_ok(&buf, o2);
  if c2.command != TOR_LINK_CMD_CREATE2 { ok = false; }
  if !c2.wide { ok = false; }
  if c2.consumed != 514 { ok = false; }
  let o3 = o2 + c2.consumed;
  let c3 = cell_ok(&buf, o3);
  if c3.command != TOR_LINK_CMD_VERSIONS { ok = false; }
  if !c3.variable { ok = false; }
  if c3.consumed != 9 { ok = false; }
  let o4 = o3 + c3.consumed;
  let c4 = cell_ok(&buf, o4);
  if c4.command != 128 { ok = false; }
  if !c4.variable { ok = false; }
  if c4.consumed != 27 { ok = false; }
  if o4 + c4.consumed != buf.len() { ok = false; }
  return assert(ok, "consumed counts walk four concatenated cells exactly");
}

fn t12() -> TestResult {
  var ok = true;
  let data = bytes_of("hello tor");
  let dg = hb("deadbeef");
  let env = relay_body(TOR_RELAY_CMD_DATA, 0x1234, 0x0042, &dg, &data);
  let r = relay_ok(&env, 0);
  if r.cmd != TOR_RELAY_CMD_DATA { ok = false; }
  if r.recognized != 0x1234 { ok = false; }
  if r.stream_id != 0x42 { ok = false; }
  if r.length != 9 { ok = false; }
  if r.consumed != 20 { ok = false; }
  let rd: Vec[UInt8] = r.digest;
  if !bytes_equal(rd, dg) { ok = false; }
  let rr: Vec[UInt8] = r.data;
  if !vec_str_eq(&rr, "hello tor") { ok = false; }
  let cellbytes = cell_narrow(0, TOR_LINK_CMD_RELAY, &env);
  let c = cell_ok(&cellbytes, 0);
  if c.command != TOR_LINK_CMD_RELAY { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  let r2 = relay_ok(&cp, 0);
  if r2.cmd != TOR_RELAY_CMD_DATA { ok = false; }
  if r2.stream_id != 0x42 { ok = false; }
  if r2.recognized != 0x1234 { ok = false; }
  let rr2: Vec[UInt8] = r2.data;
  if !vec_str_eq(&rr2, "hello tor") { ok = false; }
  let no = Vec[UInt8].new();
  let env2 = relay_data(TOR_RELAY_CMD_SENDME, 0, &no);
  let r3 = relay_ok(&env2, 0);
  if r3.cmd != TOR_RELAY_CMD_SENDME { ok = false; }
  if r3.length != 0 { ok = false; }
  if r3.consumed != 11 { ok = false; }
  let zero_digest: Vec[UInt8] = r3.digest;
  if !bytes_equal(zero_digest, hb("00000000")) { ok = false; }
  return assert(ok, "RELAY envelope: fields, unverified digest copy, consumed counts");
}

fn t13() -> TestResult {
  var ok = true;
  var b1 = bytes_of("example.com:443");
  b1.push(0 as UInt8);
  let f1 = hb("00000003");
  addb(&mut b1, &f1);
  let r1 = begin_ok(&b1);
  if r1.port != 443 { ok = false; }
  if !r1.has_flags { ok = false; }
  if r1.flags != 3 { ok = false; }
  let a1: Vec[UInt8] = r1.addr;
  if !vec_str_eq(&a1, "example.com") { ok = false; }
  var b2 = bytes_of("example.com:80");
  b2.push(0 as UInt8);
  let r2 = begin_ok(&b2);
  if r2.port != 80 { ok = false; }
  if r2.has_flags { ok = false; }
  if r2.flags != 0 { ok = false; }
  let a2: Vec[UInt8] = r2.addr;
  if !vec_str_eq(&a2, "example.com") { ok = false; }
  var b3 = bytes_of("1.2.3.4:9001");
  b3.push(0 as UInt8);
  let r3 = begin_ok(&b3);
  if r3.port != 9001 { ok = false; }
  let a3: Vec[UInt8] = r3.addr;
  if !vec_str_eq(&a3, "1.2.3.4") { ok = false; }
  var b4 = bytes_of("host:65535");
  b4.push(0 as UInt8);
  let f4 = hb("80000001");
  addb(&mut b4, &f4);
  let r4 = begin_ok(&b4);
  if r4.port != 65535 { ok = false; }
  if !r4.has_flags { ok = false; }
  if r4.flags != 2147483649 { ok = false; }
  let a4: Vec[UInt8] = r4.addr;
  if !vec_str_eq(&a4, "host") { ok = false; }
  return assert(ok, "BEGIN decode: hostname, IPv4, port bounds, flags high bit");
}

fn t14() -> TestResult {
  var ok = true;
  var v6 = bytes_of("[::1]:443");
  v6.push(0 as UInt8);
  let r6 = begin_ok(&v6);
  if r6.port != 443 { ok = false; }
  let a6: Vec[UInt8] = r6.addr;
  if !vec_str_eq(&a6, "::1") { ok = false; }
  let e0 = Vec[UInt8].new();
  if !err_begin_is(tor_relay_decode_begin(&e0), "tor: begin empty body") { ok = false; }
  let noNul = bytes_of("abc");
  if !err_begin_is(tor_relay_decode_begin(&noNul), "tor: begin address not terminated") { ok = false; }
  let justNul = hb("00");
  if !err_begin_is(tor_relay_decode_begin(&justNul), "tor: begin empty address") { ok = false; }
  var noColon = bytes_of("abc");
  noColon.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&noColon), "tor: begin port missing") { ok = false; }
  var emptyHost = bytes_of(":80");
  emptyHost.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&emptyHost), "tor: begin empty address") { ok = false; }
  var bigPort = bytes_of("host:99999");
  bigPort.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&bigPort), "tor: begin bad port") { ok = false; }
  var bigPort2 = bytes_of("host:65536");
  bigPort2.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&bigPort2), "tor: begin bad port") { ok = false; }
  var nonDigit = bytes_of("host:12a");
  nonDigit.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&nonDigit), "tor: begin bad port") { ok = false; }
  var noPort = bytes_of("host:");
  noPort.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&noPort), "tor: begin port missing") { ok = false; }
  var unclosed = bytes_of("[::1");
  unclosed.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&unclosed), "tor: begin ipv6 address not closed") { ok = false; }
  var emptyV6 = bytes_of("[]:80");
  emptyV6.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&emptyV6), "tor: begin empty address") { ok = false; }
  var v6NoPort = bytes_of("[::1]:");
  v6NoPort.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&v6NoPort), "tor: begin port missing") { ok = false; }
  var shortFlags = bytes_of("host:443");
  shortFlags.push(0 as UInt8);
  shortFlags.push(0 as UInt8);
  shortFlags.push(0 as UInt8);
  shortFlags.push(0 as UInt8);
  if !err_begin_is(tor_relay_decode_begin(&shortFlags), "tor: begin flags must be 4 bytes") { ok = false; }
  return assert(ok, "BEGIN decode: IPv6 brackets and malformed bodies");
}

fn t15() -> TestResult {
  var ok = true;
  let e = Vec[UInt8].new();
  let r0 = connected_ok(&e);
  if r0.kind != TOR_CONNECTED_NONE { ok = false; }
  let a0: Vec[UInt8] = r0.addr;
  if a0.len() != 0 { ok = false; }
  if r0.ttl != 0 { ok = false; }
  var b1 = hb("01020304");
  push_u32(&mut b1, 3600);
  let r1 = connected_ok(&b1);
  if r1.kind != TOR_CONNECTED_IPV4 { ok = false; }
  if r1.ttl != 3600 { ok = false; }
  let a1: Vec[UInt8] = r1.addr;
  if !bytes_equal(a1, hb("01020304")) { ok = false; }
  var b2 = Vec[UInt8].new();
  push_u32(&mut b2, 0);
  b2.push(6 as UInt8);
  let ip6 = bin(16);
  addb(&mut b2, &ip6);
  push_u32(&mut b2, 65535);
  if b2.len() != 25 { ok = false; }
  let r2 = connected_ok(&b2);
  if r2.kind != TOR_CONNECTED_IPV6 { ok = false; }
  if r2.ttl != 65535 { ok = false; }
  let a2: Vec[UInt8] = r2.addr;
  if !bytes_equal(a2, ip6) { ok = false; }
  let nine = hb("010203040506070809");
  if !err_connected_is(tor_relay_decode_connected(&nine), "tor: connected bad body length") { ok = false; }
  var badMarker = Vec[UInt8].new();
  push_u32(&mut badMarker, 1);
  badMarker.push(6 as UInt8);
  addb(&mut badMarker, &ip6);
  push_u32(&mut badMarker, 0);
  if !err_connected_is(tor_relay_decode_connected(&badMarker), "tor: connected bad ipv6 marker") { ok = false; }
  var badType = Vec[UInt8].new();
  push_u32(&mut badType, 0);
  badType.push(4 as UInt8);
  addb(&mut badType, &ip6);
  push_u32(&mut badType, 0);
  if !err_connected_is(tor_relay_decode_connected(&badType), "tor: connected bad ipv6 type") { ok = false; }
  return assert(ok, "CONNECTED decode: empty, IPv4, IPv6 and malformed bodies");
}

fn t16() -> TestResult {
  var ok = true;
  let e = Vec[UInt8].new();
  let r0 = end_ok(&e);
  if r0.reason != TOR_END_REASON_MISC { ok = false; }
  if r0.has_addr { ok = false; }
  if r0.ttl != 0 { ok = false; }
  let timeout = hb("07");
  let r1 = end_ok(&timeout);
  if r1.reason != TOR_END_REASON_TIMEOUT { ok = false; }
  if r1.has_addr { ok = false; }
  let policyOnly = hb("04");
  let r2 = end_ok(&policyOnly);
  if r2.reason != TOR_END_REASON_EXITPOLICY { ok = false; }
  if r2.has_addr { ok = false; }
  var v4 = hb("04");
  let a4 = hb("01020304");
  addb(&mut v4, &a4);
  let r3 = end_ok(&v4);
  if !r3.has_addr { ok = false; }
  if r3.ttl != 4294967295 { ok = false; }
  let ea3: Vec[UInt8] = r3.addr;
  if !bytes_equal(ea3, a4) { ok = false; }
  var v4t = hb("04");
  addb(&mut v4t, &a4);
  push_u32(&mut v4t, 300);
  let r4 = end_ok(&v4t);
  if !r4.has_addr { ok = false; }
  if r4.ttl != 300 { ok = false; }
  var v6 = hb("04");
  let addr6 = bin(16);
  addb(&mut v6, &addr6);
  push_u32(&mut v6, 60);
  let r5 = end_ok(&v6);
  if !r5.has_addr { ok = false; }
  if r5.ttl != 60 { ok = false; }
  let ea5: Vec[UInt8] = r5.addr;
  if !bytes_equal(ea5, addr6) { ok = false; }
  let unknown = hb("c8");
  let r6 = end_ok(&unknown);
  if r6.reason != 200 { ok = false; }
  let trailing = hb("07ff");
  if !err_end_is(tor_relay_decode_end(&trailing), "tor: end body has trailing bytes") { ok = false; }
  let badPolicy = hb("04aabbcc");
  if !err_end_is(tor_relay_decode_end(&badPolicy), "tor: end bad exitpolicy body") { ok = false; }
  return assert(ok, "END decode: reason table, EXITPOLICY block, absent TTL default");
}

fn t17() -> TestResult {
  var ok = true;
  let e = Vec[UInt8].new();
  let r0 = sendme_ok(&e);
  if !r0.legacy { ok = false; }
  if r0.version != 0 { ok = false; }
  if r0.data_len != 0 { ok = false; }
  let d0: Vec[UInt8] = r0.digest;
  if d0.len() != 0 { ok = false; }
  var v1 = Vec[UInt8].new();
  v1.push(1 as UInt8);
  push_u16(&mut v1, 20);
  let dig20 = bin(20);
  addb(&mut v1, &dig20);
  let r1 = sendme_ok(&v1);
  if r1.legacy { ok = false; }
  if r1.version != 1 { ok = false; }
  if r1.data_len != 20 { ok = false; }
  let d1: Vec[UInt8] = r1.digest;
  if !bytes_equal(d1, dig20) { ok = false; }
  var v1b = Vec[UInt8].new();
  v1b.push(1 as UInt8);
  push_u16(&mut v1b, 24);
  let dig24 = bin(24);
  addb(&mut v1b, &dig24);
  let r2 = sendme_ok(&v1b);
  if r2.data_len != 24 { ok = false; }
  let d2: Vec[UInt8] = r2.digest;
  let want20 = trunc(&dig24, 20);
  if !bytes_equal(d2, want20) { ok = false; }
  var v0 = Vec[UInt8].new();
  v0.push(0 as UInt8);
  push_u16(&mut v0, 0);
  let r3 = sendme_ok(&v0);
  if r3.legacy { ok = false; }
  if r3.version != 0 { ok = false; }
  let d3: Vec[UInt8] = r3.digest;
  if d3.len() != 0 { ok = false; }
  var v2 = Vec[UInt8].new();
  v2.push(2 as UInt8);
  push_u16(&mut v2, 3);
  v2.push(0xAA as UInt8);
  v2.push(0xBB as UInt8);
  v2.push(0xCC as UInt8);
  let r4 = sendme_ok(&v2);
  if r4.version != 2 { ok = false; }
  if r4.data_len != 3 { ok = false; }
  let d4: Vec[UInt8] = r4.digest;
  if d4.len() != 0 { ok = false; }
  let one = hb("01");
  if !err_sendme_is(tor_relay_decode_sendme(&one), "tor: sendme header truncated") { ok = false; }
  let zeroDigest = hb("010000");
  if !err_sendme_is(tor_relay_decode_sendme(&zeroDigest), "tor: sendme digest too short") { ok = false; }
  var overrun = Vec[UInt8].new();
  overrun.push(1 as UInt8);
  push_u16(&mut overrun, 10);
  overrun.push(0 as UInt8);
  overrun.push(0 as UInt8);
  overrun.push(0 as UInt8);
  overrun.push(0 as UInt8);
  overrun.push(0 as UInt8);
  if !err_sendme_is(tor_relay_decode_sendme(&overrun), "tor: sendme data overrun") { ok = false; }
  let env = relay_data(TOR_RELAY_CMD_SENDME, 42, &v1);
  let rel = relay_ok(&env, 0);
  if rel.cmd != TOR_RELAY_CMD_SENDME { ok = false; }
  if rel.stream_id != 42 { ok = false; }
  let rd: Vec[UInt8] = rel.data;
  let rs = sendme_ok(&rd);
  if rs.version != 1 { ok = false; }
  return assert(ok, "SENDME decode: legacy v0, v1 digest, unknown version, errors");
}

fn t18() -> TestResult {
  var ok = true;
  var q = bytes_of("www.example.com");
  q.push(0 as UInt8);
  let rq = resolve_ok(&q);
  let name: Vec[UInt8] = rq.name;
  if !vec_str_eq(&name, "www.example.com") { ok = false; }
  let e = Vec[UInt8].new();
  if !err_resolve_is(tor_relay_decode_resolve(&e), "tor: resolve empty body") { ok = false; }
  let noNul = bytes_of("abc");
  if !err_resolve_is(tor_relay_decode_resolve(&noNul), "tor: resolve name not terminated") { ok = false; }
  let justNul = hb("00");
  if !err_resolve_is(tor_relay_decode_resolve(&justNul), "tor: resolve empty name") { ok = false; }
  let trailing = hb("610000");
  if !err_resolve_is(tor_relay_decode_resolve(&trailing), "tor: resolve trailing bytes") { ok = false; }
  var ans1 = Vec[UInt8].new();
  ans1.push(0 as UInt8);
  ans1.push(15 as UInt8);
  let hostb = bytes_of("www.example.com");
  addb(&mut ans1, &hostb);
  push_u32(&mut ans1, 120);
  let ra1 = resolved_ok(&ans1);
  if ra1.atype != TOR_RESOLVED_TYPE_HOSTNAME { ok = false; }
  if ra1.ttl != 120 { ok = false; }
  if ra1.consumed != 21 { ok = false; }
  let v1: Vec[UInt8] = ra1.value;
  if !vec_str_eq(&v1, "www.example.com") { ok = false; }
  var ans2 = Vec[UInt8].new();
  ans2.push(4 as UInt8);
  ans2.push(4 as UInt8);
  let ip4 = hb("5db8d822");
  addb(&mut ans2, &ip4);
  push_u32(&mut ans2, 60);
  let ra2 = resolved_ok(&ans2);
  if ra2.atype != TOR_RESOLVED_TYPE_IPV4 { ok = false; }
  if ra2.ttl != 60 { ok = false; }
  if ra2.consumed != 10 { ok = false; }
  let v2: Vec[UInt8] = ra2.value;
  if !bytes_equal(v2, ip4) { ok = false; }
  var ans3 = Vec[UInt8].new();
  ans3.push(240 as UInt8);
  ans3.push(3 as UInt8);
  let errb = bytes_of("err");
  addb(&mut ans3, &errb);
  push_u32(&mut ans3, 0);
  let ra3 = resolved_ok(&ans3);
  if ra3.atype != TOR_RESOLVED_TYPE_ERROR_TRANSIENT { ok = false; }
  if ra3.consumed != 9 { ok = false; }
  var buf = Vec[UInt8].new();
  addb(&mut buf, &ans1);
  addb(&mut buf, &ans2);
  let rb1 = resolved_ok(&buf);
  if rb1.atype != TOR_RESOLVED_TYPE_HOSTNAME { ok = false; }
  if rb1.consumed != 21 { ok = false; }
  let off2 = rb1.consumed;
  let rest = from_off(&buf, off2);
  let rb2 = resolved_ok(&rest);
  if rb2.atype != TOR_RESOLVED_TYPE_IPV4 { ok = false; }
  if rb2.consumed != 10 { ok = false; }
  if off2 + rb2.consumed != buf.len() { ok = false; }
  let tooShort = hb("04");
  if !err_resolved_is(tor_relay_decode_resolved(&tooShort), "tor: resolved answer truncated") { ok = false; }
  var badV4 = Vec[UInt8].new();
  badV4.push(4 as UInt8);
  badV4.push(6 as UInt8);
  addb(&mut badV4, &bin(6));
  push_u32(&mut badV4, 0);
  if !err_resolved_is(tor_relay_decode_resolved(&badV4), "tor: resolved ipv4 length") { ok = false; }
  var badV6 = Vec[UInt8].new();
  badV6.push(6 as UInt8);
  badV6.push(4 as UInt8);
  addb(&mut badV6, &bin(4));
  push_u32(&mut badV6, 0);
  if !err_resolved_is(tor_relay_decode_resolved(&badV6), "tor: resolved ipv6 length") { ok = false; }
  return assert(ok, "RESOLVE and RESOLVED decode: hostname, IPv4, error, walk");
}

fn t19() -> TestResult {
  var ok = true;
  var body = Vec[UInt8].new();
  push_u32(&mut body, 1000000);
  body.push(4 as UInt8);
  body.push(4 as UInt8);
  let oaddr = hb("09090909");
  addb(&mut body, &oaddr);
  body.push(1 as UInt8);
  body.push(4 as UInt8);
  body.push(4 as UInt8);
  let maddr = hb("01010101");
  addb(&mut body, &maddr);
  if body.len() != 17 { ok = false; }
  let n1 = netinfo_ok(&body, 0);
  if n1.time != 1000000 { ok = false; }
  if n1.other_atype != 4 { ok = false; }
  if n1.n_my_addr != 1 { ok = false; }
  if n1.consumed != 17 { ok = false; }
  let oa: Vec[UInt8] = n1.other_addr;
  if !bytes_equal(oa, oaddr) { ok = false; }
  let ta: Vec[Int] = n1.my_atypes;
  if ta.len() != 1 { ok = false; }
  let t0: Int = ta[0];
  if t0 != 4 { ok = false; }
  let ma: Vec[Vec[UInt8]] = n1.my_addrs;
  if ma.len() != 1 { ok = false; }
  let m0: Vec[UInt8] = ma[0];
  if !bytes_equal(m0, maddr) { ok = false; }
  let junk = hb("aabbcc");
  var bodyj = Vec[UInt8].new();
  addb(&mut bodyj, &body);
  addb(&mut bodyj, &junk);
  let n2 = netinfo_ok(&bodyj, 0);
  if n2.consumed != 17 { ok = false; }
  var short = Vec[UInt8].new();
  push_u32(&mut short, 0);
  short.push(4 as UInt8);
  short.push(4 as UInt8);
  push_u32(&mut short, 0);
  short.push(0 as UInt8);
  let n3 = netinfo_ok(&short, 0);
  if n3.n_my_addr != 0 { ok = false; }
  if n3.consumed != 11 { ok = false; }
  let nta: Vec[Int] = n3.my_atypes;
  if nta.len() != 0 { ok = false; }
  let five = hb("0000000004");
  if !err_netinfo_is(tor_decode_netinfo(&five, 0), "tor: netinfo header truncated at 0") { ok = false; }
  var otherCut = Vec[UInt8].new();
  push_u32(&mut otherCut, 0);
  otherCut.push(4 as UInt8);
  otherCut.push(4 as UInt8);
  otherCut.push(0 as UInt8);
  otherCut.push(0 as UInt8);
  if !err_netinfo_is(tor_decode_netinfo(&otherCut, 0), "tor: netinfo other address truncated at 0") { ok = false; }
  var noCount = Vec[UInt8].new();
  push_u32(&mut noCount, 0);
  noCount.push(4 as UInt8);
  noCount.push(4 as UInt8);
  addb(&mut noCount, &oaddr);
  if noCount.len() != 10 { ok = false; }
  if !err_netinfo_is(tor_decode_netinfo(&noCount, 0), "tor: netinfo address count missing at 0") { ok = false; }
  var myCut = Vec[UInt8].new();
  push_u32(&mut myCut, 0);
  myCut.push(4 as UInt8);
  myCut.push(0 as UInt8);
  myCut.push(1 as UInt8);
  myCut.push(4 as UInt8);
  myCut.push(4 as UInt8);
  myCut.push(0 as UInt8);
  myCut.push(0 as UInt8);
  if !err_netinfo_is(tor_decode_netinfo(&myCut, 0), "tor: netinfo my address truncated at 0") { ok = false; }
  let cellbytes = cell_wide(0, TOR_LINK_CMD_NETINFO, &body);
  let c = cellv_ok(&cellbytes, 0, 5);
  if !c.wide { ok = false; }
  if c.command != TOR_LINK_CMD_NETINFO { ok = false; }
  if c.consumed != 514 { ok = false; }
  let cp: Vec[UInt8] = c.payload;
  if cp.len() != 509 { ok = false; }
  let n4 = netinfo_ok(&cp, 0);
  if n4.time != 1000000 { ok = false; }
  if n4.consumed != 17 { ok = false; }
  return assert(ok, "NETINFO decode: time, addresses, trailing bytes, errors");
}

fn t20() -> TestResult {
  var ok = true;
  let txt = bytes_of("host.example");
  let r1 = tor_ascii_to_str(&txt);
  if !r1.is_ok { ok = false; } else {
    let s1: Str = r1.value;
    if !str_eq(s1, "host.example") { ok = false; }
  }
  let e = Vec[UInt8].new();
  let r2 = tor_ascii_to_str(&e);
  if !r2.is_ok { ok = false; } else {
    let s2: Str = r2.value;
    if !str_eq(s2, "") { ok = false; }
  }
  let withNul = hb("61620063");
  if !err_str_is(tor_ascii_to_str(&withNul), "tor: not printable ascii") { ok = false; }
  let withHigh = hb("61ff");
  if !err_str_is(tor_ascii_to_str(&withHigh), "tor: not printable ascii") { ok = false; }
  let no = Vec[UInt8].new();
  let env = relay_data(TOR_RELAY_CMD_DATA, 5, &no);
  let rel = relay_ok(&env, 0);
  if rel.length != 0 { ok = false; }
  if rel.consumed != 11 { ok = false; }
  let rd: Vec[UInt8] = rel.data;
  if rd.len() != 0 { ok = false; }
  let vb = versions_ok(&no, 0);
  if vb.consumed != 0 { ok = false; }
  let vv: Vec[Int] = vb.versions;
  if vv.len() != 0 { ok = false; }
  if !str_eq(tor_link_cmd_name(TOR_LINK_CMD_VERSIONS), "VERSIONS") { ok = false; }
  if !str_eq(tor_relay_cmd_name(TOR_RELAY_CMD_BEGIN_DIR), "BEGIN_DIR") { ok = false; }
  if !str_eq(tor_resolved_type_name(TOR_RESOLVED_TYPE_ERROR_NONTRANSIENT), "ERROR_NONTRANSIENT") { ok = false; }
  return assert(ok, "ASCII conversion boundaries and zero-length variable bodies");
}

fn main() -> Int {
  io.println("=== xiom.tor conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.tor: all tests passed");
  } else {
    io.println("xiom.tor: tests failed");
  }
  return failed;
}
