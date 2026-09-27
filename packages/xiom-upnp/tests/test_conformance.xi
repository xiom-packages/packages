// XIOM -- xiom.upnp conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.upnp SSDP/UPnP discovery codec on
// synthetic buffers built entirely in-test (no external fixtures). The
// fixtures are canonical M-SEARCH requests, ssdp:alive/byebye/update NOTIFY
// notifications and HTTP/1.1 200 search responses, plus hand-built malformed
// buffers. Every error is checked by exact message and byte offset; every
// Str comparison goes through xiom.string.compare.str_compare (BUG 17) and
// every Vec element read is bound to a typed local first.

module upnp_tests
use xiom.io; use xiom.test;
use xiom.upnp;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Fixture helpers
// --------------------------------------------------

// Bytes of a Str (one byte per string byte).
fn bs(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < string.str_len(s) {
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

fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// head + one byte + tail, for buffers a Str literal cannot express (NUL,
// raw control bytes).
fn insert_byte(head: Vec[UInt8], b: Int, tail: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < head.len() {
    v.push(head[i]);
    i = i + 1;
  }
  v.push(b as UInt8);
  var j = 0;
  while j < tail.len() {
    v.push(tail[j]);
    j = j + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Result inspectors
// --------------------------------------------------

fn msg_err_is(r: Result[SsdpMessage, SsdpError], want: Str, want_off: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SsdpError = r.error;
  if !str_eq(e.message, want) {
    return false;
  }
  return e.offset == want_off;
}

fn bytes_err_is(r: Result[Vec[UInt8], SsdpError], want: Str, want_off: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SsdpError = r.error;
  if !str_eq(e.message, want) {
    return false;
  }
  return e.offset == want_off;
}

fn target_err_is(r: Result[SsdpTarget, SsdpError], want: Str, want_off: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SsdpError = r.error;
  if !str_eq(e.message, want) {
    return false;
  }
  return e.offset == want_off;
}

fn usn_err_is(r: Result[UsnSplit, SsdpError], want: Str, want_off: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SsdpError = r.error;
  if !str_eq(e.message, want) {
    return false;
  }
  return e.offset == want_off;
}

// --------------------------------------------------
//  Synthetic buffer builders
// --------------------------------------------------

// M-SEARCH with a selectable header set; an empty argument omits that line.
fn msearch_parts(host: Str, man_line: Str, mx_line: Str, st_line: Str, ua_line: Str) -> Vec[UInt8] {
  var s = "M-SEARCH * HTTP/1.1\r\n";
  if string.str_len(host) > 0 { s = s + "HOST: " + host + "\r\n"; }
  if string.str_len(man_line) > 0 { s = s + "MAN: " + man_line + "\r\n"; }
  if string.str_len(mx_line) > 0 { s = s + "MX: " + mx_line + "\r\n"; }
  if string.str_len(st_line) > 0 { s = s + "ST: " + st_line + "\r\n"; }
  if string.str_len(ua_line) > 0 { s = s + "USER-AGENT: " + ua_line + "\r\n"; }
  s = s + "\r\n";
  return bs(s);
}

// NOTIFY with a selectable header set; an empty argument omits that line.
// `extra` is appended verbatim before the final CRLF (integer headers).
fn notify_parts(host: Str, cache: Str, loc: Str, nt: Str, nts: Str, usn: Str, extra: Str) -> Vec[UInt8] {
  var s = "NOTIFY * HTTP/1.1\r\n";
  if string.str_len(host) > 0 { s = s + "HOST: " + host + "\r\n"; }
  if string.str_len(cache) > 0 { s = s + "CACHE-CONTROL: " + cache + "\r\n"; }
  if string.str_len(loc) > 0 { s = s + "LOCATION: " + loc + "\r\n"; }
  if string.str_len(nt) > 0 { s = s + "NT: " + nt + "\r\n"; }
  if string.str_len(nts) > 0 { s = s + "NTS: " + nts + "\r\n"; }
  if string.str_len(usn) > 0 { s = s + "USN: " + usn + "\r\n"; }
  if string.str_len(extra) > 0 { s = s + extra; }
  s = s + "\r\n";
  return bs(s);
}

const _HOST: Str = "239.255.255.250:1900";
const _UUID: Str = "uuid:2fac1234-31f8-11b4-a222-08002b34c003";
const _DEVTYPE: Str = "urn:schemas-upnp-org:device:MediaRenderer:1";
const _USN_DEV: Str = "uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:schemas-upnp-org:device:MediaRenderer:1";
const _LOC: Str = "http://192.168.1.10:8200/desc.xml";

fn fx_msearch() -> Vec[UInt8] {
  return bs("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\nUSER-AGENT: test/1.0\r\n\r\n");
}

fn fx_notify_alive() -> Vec[UInt8] {
  return bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\nNT: urn:schemas-upnp-org:device:MediaRenderer:1\r\nNTS: ssdp:alive\r\nSERVER: Linux/6.1 UPnP/1.1 test/1.0\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:schemas-upnp-org:device:MediaRenderer:1\r\nBOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 7\r\n\r\n");
}

fn fx_response() -> Vec[UInt8] {
  return bs("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nDATE: Sun, 27 Sep 2026 23:00:00 GMT\r\nEXT:\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\nSERVER: Linux/6.1 UPnP/1.1 test/1.0\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:schemas-upnp-org:device:MediaRenderer:1\r\nBOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 7\r\n\r\n");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let msg = fx_msearch();
  let r = upnp_parse(&msg);
  if !r.is_ok { return assert(false, "canonical M-SEARCH must parse"); }
  let m: SsdpMessage = r.value;
  var ok = m.kind == UPNP_KIND_MSEARCH;
  if m.status != -1 { ok = false; }
  if string.str_len(m.reason) != 0 { ok = false; }
  if !str_eq(m.method, "M-SEARCH") { ok = false; }
  if !str_eq(m.target, "*") { ok = false; }
  if !str_eq(m.version, "HTTP/1.1") { ok = false; }
  if !str_eq(m.host, "239.255.255.250:1900") { ok = false; }
  if !str_eq(m.man, "\"ssdp:discover\"") { ok = false; }
  if m.mx != 3 { ok = false; }
  if !str_eq(m.st, "ssdp:all") { ok = false; }
  if !str_eq(m.user_agent, "test/1.0") { ok = false; }
  if upnp_header_count(&m) != 5 { ok = false; }
  if !str_eq(upnp_header(&m, "host"), "239.255.255.250:1900") { ok = false; }
  if !str_eq(upnp_header(&m, "USER-agent"), "test/1.0") { ok = false; }
  if upnp_has_header(&m, "LOCATION") { ok = false; }
  if !upnp_has_header(&m, "ST") { ok = false; }
  let off0 = string.str_len("M-SEARCH * HTTP/1.1\r\n");
  if upnp_header_offset(&m, 0) != off0 { ok = false; }
  if !str_eq(upnp_header_name(&m, 0), "HOST") { ok = false; }
  if !str_eq(upnp_header_value(&m, 4), "test/1.0") { ok = false; }
  if upnp_header_name(&m, 9) != "" { ok = false; }
  if upnp_header_value(&m, -1) != "" { ok = false; }
  if upnp_header_offset(&m, 9) != -1 { ok = false; }
  let pt = upnp_parse_text("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\n\r\n");
  if !pt.is_ok { ok = false; }
  return assert(ok, "M-SEARCH: typed fields, case-insensitive header lookup, wire offsets");
}

fn t2() -> TestResult {
  let msg = bs("M-SEARCH * HTTP/1.1\r\nHost: 239.255.255.250:1900\r\nman: \"ssdp:discover\"\r\nMx: 5\r\nsT: upnp:rootdevice\r\nUser-Agent: t/1\r\n\r\n");
  let r = upnp_parse(&msg);
  if !r.is_ok { return assert(false, "M-SEARCH with lower-case header names must parse"); }
  let m: SsdpMessage = r.value;
  var ok = m.mx == 5;
  if !str_eq(m.host, "239.255.255.250:1900") { ok = false; }
  if !str_eq(m.man, "\"ssdp:discover\"") { ok = false; }
  if !str_eq(m.st, "upnp:rootdevice") { ok = false; }
  if !str_eq(m.user_agent, "t/1") { ok = false; }
  if !str_eq(upnp_header_name(&m, 0), "Host") { ok = false; }
  if !str_eq(upnp_header_name(&m, 4), "User-Agent") { ok = false; }
  if !str_eq(upnp_header(&m, "ST"), "upnp:rootdevice") { ok = false; }
  return assert(ok, "M-SEARCH: header names are case-insensitive while casing is preserved");
}

fn t3() -> TestResult {
  var ok = true;
  let m1 = msearch_parts(_HOST, "\"ssdp:discover\"", "1", "ssdp:all", "");
  let r1 = upnp_parse(&m1);
  if !r1.is_ok { ok = false; } else {
    let x1: SsdpMessage = r1.value;
    if x1.mx != 1 { ok = false; }
  }
  let m5 = msearch_parts(_HOST, "\"ssdp:discover\"", "5", "ssdp:all", "");
  let r5 = upnp_parse(&m5);
  if !r5.is_ok { ok = false; } else {
    let x5: SsdpMessage = r5.value;
    if x5.mx != 5 { ok = false; }
  }
  let off_mx = string.str_len("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\n");
  let m0 = msearch_parts(_HOST, "\"ssdp:discover\"", "0", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&m0), "upnp: bad MX", off_mx) { ok = false; }
  let m6 = msearch_parts(_HOST, "\"ssdp:discover\"", "6", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&m6), "upnp: bad MX", off_mx) { ok = false; }
  let ma = msearch_parts(_HOST, "\"ssdp:discover\"", "abc", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&ma), "upnp: bad MX", off_mx) { ok = false; }
  return assert(ok, "M-SEARCH MX accepts 1..5 and rejects 0, 6 and non-numeric at the header offset");
}

fn t4() -> TestResult {
  var ok = true;
  let no_man = msearch_parts(_HOST, "", "3", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&no_man), "upnp: missing required header MAN", no_man.len() - 2) { ok = false; }
  let no_st = msearch_parts(_HOST, "\"ssdp:discover\"", "3", "", "");
  if !msg_err_is(upnp_parse(&no_st), "upnp: missing required header ST", no_st.len() - 2) { ok = false; }
  let no_host = msearch_parts("", "\"ssdp:discover\"", "3", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&no_host), "upnp: missing required header HOST", no_host.len() - 2) { ok = false; }
  let off_man = string.str_len("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n");
  let bad_man = msearch_parts(_HOST, "discover", "3", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&bad_man), "upnp: bad MAN", off_man) { ok = false; }
  let empty_man = msearch_parts(_HOST, "\"\"", "3", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&empty_man), "upnp: bad MAN", off_man) { ok = false; }
  let off_host = string.str_len("M-SEARCH * HTTP/1.1\r\n");
  let bad_host = msearch_parts("not a host", "\"ssdp:discover\"", "3", "ssdp:all", "");
  if !msg_err_is(upnp_parse(&bad_host), "upnp: bad HOST", off_host) { ok = false; }
  let bad_st = msearch_parts(_HOST, "\"ssdp:discover\"", "3", "banana", "");
  let off_st = string.str_len("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\n");
  if !msg_err_is(upnp_parse(&bad_st), "upnp: bad ST", off_st) { ok = false; }
  return assert(ok, "M-SEARCH required headers and their values are validated with offsets");
}

fn t5() -> TestResult {
  var ok = true;
  if !msg_err_is(upnp_parse(&bs("GET * HTTP/1.1\r\n\r\n")), "upnp: bad start line", 0) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.0\r\n\r\n")), "upnp: bad version", 11) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH 239.255.255.250:1900 HTTP/1.1\r\n\r\n")), "upnp: bad target", 9) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1 extra\r\n\r\n")), "upnp: bad start line", 0) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("HTTP/1.1 404 Not Found\r\n\r\n")), "upnp: bad status", 9) { ok = false; }
  let bare = bs("M-SEARCH * HTTP/1.1\r\n");
  if !msg_err_is(upnp_parse(&bare), "upnp: missing required header HOST", 21) { ok = false; }
  let eof = bs("M-SEARCH * HTTP/1.1");
  if !msg_err_is(upnp_parse(&eof), "upnp: missing required header HOST", 19) { ok = false; }
  let resp = bs("HTTP/1.1 200\r\n\r\n");
  if !msg_err_is(upnp_parse(&resp), "upnp: missing required header CACHE-CONTROL", resp.len() - 2) { ok = false; }
  return assert(ok, "bad methods, targets, versions and statuses are rejected at their offsets");
}

fn t6() -> TestResult {
  let msg = fx_notify_alive();
  let r = upnp_parse(&msg);
  if !r.is_ok { return assert(false, "canonical NOTIFY ssdp:alive must parse"); }
  let m: SsdpMessage = r.value;
  var ok = m.kind == UPNP_KIND_NOTIFY;
  if !str_eq(m.method, "NOTIFY") { ok = false; }
  if !str_eq(m.host, _HOST) { ok = false; }
  if m.max_age != 1800 { ok = false; }
  if !str_eq(m.cache_control, "max-age=1800") { ok = false; }
  if !str_eq(m.location, _LOC) { ok = false; }
  if !str_eq(m.nt, _DEVTYPE) { ok = false; }
  if !str_eq(m.nts, "ssdp:alive") { ok = false; }
  if m.nts_kind != UPNP_NTS_ALIVE { ok = false; }
  if !str_eq(m.server, "Linux/6.1 UPnP/1.1 test/1.0") { ok = false; }
  if !str_eq(m.usn, _USN_DEV) { ok = false; }
  if m.bootid != 42 { ok = false; }
  if m.configid != 7 { ok = false; }
  if m.searchport != -1 { ok = false; }
  if !str_eq(upnp_header(&m, "bootid.upnp.org"), "42") { ok = false; }
  let tr = upnp_classify_target(m.nt);
  if !tr.is_ok { ok = false; } else {
    let t: SsdpTarget = tr.value;
    if t.kind != UPNP_TARGET_DEVICE { ok = false; }
    if !str_eq(t.dev_type, "MediaRenderer") { ok = false; }
    if t.major != 1 { ok = false; }
  }
  let ur = usn_split(m.usn);
  if !ur.is_ok { ok = false; } else {
    let u: UsnSplit = ur.value;
    if u.kind != UPNP_USN_UUID_URN { ok = false; }
    if !str_eq(u.device_uuid, "2fac1234-31f8-11b4-a222-08002b34c003") { ok = false; }
  }
  return assert(ok, "NOTIFY ssdp:alive: typed fields, NT/USN classification, max-age and BOOTID/CONFIGID");
}

fn t7() -> TestResult {
  let msg = bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: upnp:rootdevice\r\nNTS: ssdp:byebye\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\n\r\n");
  let r = upnp_parse(&msg);
  if !r.is_ok { return assert(false, "minimal NOTIFY ssdp:byebye must parse"); }
  let m: SsdpMessage = r.value;
  var ok = m.kind == UPNP_KIND_NOTIFY;
  if !str_eq(m.nts, "ssdp:byebye") { ok = false; }
  if m.nts_kind != UPNP_NTS_BYEBYE { ok = false; }
  if !str_eq(m.nt, "upnp:rootdevice") { ok = false; }
  if string.str_len(m.location) != 0 { ok = false; }
  if string.str_len(m.server) != 0 { ok = false; }
  if m.max_age != -1 { ok = false; }
  if m.bootid != -1 { ok = false; }
  if m.configid != -1 { ok = false; }
  if !str_eq(upnp_header(&m, "USN"), "uuid:2fac1234-31f8-11b4-a222-08002b34c003") { ok = false; }
  if !str_eq(upnp_nts_name(m.nts_kind), "ssdp:byebye") { ok = false; }
  return assert(ok, "NOTIFY ssdp:byebye parses without CACHE-CONTROL/LOCATION and leaves optionals at -1");
}

fn t8() -> TestResult {
  var ok = true;
  let upd_no = notify_parts(_HOST, "", "", _UUID, "ssdp:update", _UUID, "");
  if !msg_err_is(upnp_parse(&upd_no), "upnp: missing required header BOOTID.UPNP.ORG", upd_no.len() - 2) { ok = false; }
  let upd = notify_parts(_HOST, "", "", _UUID, "ssdp:update", _UUID, "BOOTID.UPNP.ORG: 9\r\n");
  let ur = upnp_parse(&upd);
  if !ur.is_ok { ok = false; } else {
    let um: SsdpMessage = ur.value;
    if um.nts_kind != UPNP_NTS_UPDATE { ok = false; }
    if um.bootid != 9 { ok = false; }
  }
  let off_nts = string.str_len("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: urn:schemas-upnp-org:device:MediaRenderer:1\r\n");
  let bad_nts = notify_parts(_HOST, "", "", _DEVTYPE, "ssdp:later", _USN_DEV, "");
  if !msg_err_is(upnp_parse(&bad_nts), "upnp: bad NTS", off_nts) { ok = false; }
  let no_loc = notify_parts(_HOST, "max-age=1800", "", _DEVTYPE, "ssdp:alive", _USN_DEV, "");
  if !msg_err_is(upnp_parse(&no_loc), "upnp: missing required header LOCATION", no_loc.len() - 2) { ok = false; }
  let off_cc = string.str_len("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n");
  let bad_cc = notify_parts(_HOST, "max-age=abc", _LOC, _DEVTYPE, "ssdp:alive", _USN_DEV, "");
  if !msg_err_is(upnp_parse(&bad_cc), "upnp: bad CACHE-CONTROL", off_cc) { ok = false; }
  let off_loc = string.str_len("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\n");
  let bad_loc = notify_parts(_HOST, "max-age=1800", "not-a-url", _DEVTYPE, "ssdp:alive", _USN_DEV, "");
  if !msg_err_is(upnp_parse(&bad_loc), "upnp: bad LOCATION", off_loc) { ok = false; }
  let bad_nt = notify_parts(_HOST, "max-age=1800", _LOC, "banana", "ssdp:alive", _USN_DEV, "");
  let off_nt = string.str_len("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\n");
  if !msg_err_is(upnp_parse(&bad_nt), "upnp: bad NT", off_nt) { ok = false; }
  let bad_usn = notify_parts(_HOST, "max-age=1800", _LOC, _DEVTYPE, "ssdp:alive", "nope", "");
  let off_usn = string.str_len("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\nNT: urn:schemas-upnp-org:device:MediaRenderer:1\r\nNTS: ssdp:alive\r\n");
  if !msg_err_is(upnp_parse(&bad_usn), "upnp: bad USN", off_usn) { ok = false; }
  return assert(ok, "NOTIFY ssdp:update requires BOOTID; bad NTS/CC/LOCATION/NT/USN carry offsets");
}

fn t9() -> TestResult {
  let msg = fx_response();
  let r = upnp_parse(&msg);
  if !r.is_ok { return assert(false, "canonical HTTP/1.1 200 search response must parse"); }
  let m: SsdpMessage = r.value;
  var ok = m.kind == UPNP_KIND_RESPONSE;
  if m.status != 200 { ok = false; }
  if !str_eq(m.reason, "OK") { ok = false; }
  if !str_eq(m.method, "HTTP/1.1") { ok = false; }
  if !str_eq(m.date, "Sun, 27 Sep 2026 23:00:00 GMT") { ok = false; }
  if !upnp_has_header(&m, "EXT") { ok = false; }
  if string.str_len(m.ext) != 0 { ok = false; }
  if !str_eq(m.cache_control, "max-age=1800") { ok = false; }
  if m.max_age != 1800 { ok = false; }
  if !str_eq(m.location, _LOC) { ok = false; }
  if !str_eq(m.st, _DEVTYPE) { ok = false; }
  if !str_eq(m.usn, _USN_DEV) { ok = false; }
  if !str_eq(m.server, "Linux/6.1 UPnP/1.1 test/1.0") { ok = false; }
  if m.bootid != 42 { ok = false; }
  if m.configid != 7 { ok = false; }
  if m.nts_kind != -1 { ok = false; }
  if string.str_len(m.nt) != 0 { ok = false; }
  let no_srv = bs("HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=60\r\nDATE: Sun, 27 Sep 2026 23:00:00 GMT\r\nEXT:\r\nLOCATION: http://h:1900/d.xml\r\nST: upnp:rootdevice\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\n\r\n");
  let nr = upnp_parse(&no_srv);
  if !nr.is_ok { ok = false; } else {
    let nm: SsdpMessage = nr.value;
    if string.str_len(nm.server) != 0 { ok = false; }
  }
  return assert(ok, "HTTP/1.1 200 response: DATE/EXT/LOCATION/ST/USN typed and SERVER optional");
}

fn t10() -> TestResult {
  var ok = true;
  let a = usn_split("uuid:2fac1234-31f8-11b4-a222-08002b34c003");
  if !a.is_ok { ok = false; } else {
    let u: UsnSplit = a.value;
    if u.kind != UPNP_USN_UUID { ok = false; }
    if !str_eq(u.device_uuid, "2fac1234-31f8-11b4-a222-08002b34c003") { ok = false; }
    if string.str_len(u.urn) != 0 { ok = false; }
  }
  let b = usn_split(_USN_DEV);
  if !b.is_ok { ok = false; } else {
    let u: UsnSplit = b.value;
    if u.kind != UPNP_USN_UUID_URN { ok = false; }
    if !str_eq(u.urn, _DEVTYPE) { ok = false; }
  }
  let c = usn_split("uuid:2fac1234-31f8-11b4-a222-08002b34c003::upnp:rootdevice");
  if !c.is_ok { ok = false; } else {
    let u: UsnSplit = c.value;
    if u.kind != UPNP_USN_UUID_ROOTDEVICE { ok = false; }
    if !str_eq(u.suffix, "upnp:rootdevice") { ok = false; }
  }
  let d = usn_split("urn:schemas-upnp-org:service:WANIPConnection:2");
  if !d.is_ok { ok = false; } else {
    let u: UsnSplit = d.value;
    if u.kind != UPNP_USN_URN { ok = false; }
    if !str_eq(u.urn, "urn:schemas-upnp-org:service:WANIPConnection:2") { ok = false; }
  }
  if !usn_err_is(usn_split(""), "upnp: empty USN", 0) { ok = false; }
  if !usn_err_is(usn_split("uuid:bad"), "upnp: bad uuid in USN", 5) { ok = false; }
  if !usn_err_is(usn_split("hello"), "upnp: bad USN", 0) { ok = false; }
  if !usn_err_is(usn_split("urn:only"), "upnp: bad urn in USN", 0) { ok = false; }
  if !usn_err_is(usn_split("uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:a::b"), "upnp: bad USN", 48) { ok = false; }
  if !usn_err_is(usn_split("uuid:2fac1234-31f8-11b4-a222-08002b34c003::what"), "upnp: bad USN", 43) { ok = false; }
  if !str_eq(upnp_usn_kind_name(UPNP_USN_UUID_ROOTDEVICE), "uuid+rootdevice") { ok = false; }
  return assert(ok, "usn_split: uuid, uuid::urn, uuid::rootdevice, bare urn and malformed forms");
}

fn t11() -> TestResult {
  var ok = true;
  let a = upnp_classify_target("ssdp:all");
  if !a.is_ok { ok = false; } else {
    let t: SsdpTarget = a.value;
    if t.kind != UPNP_TARGET_SSDP_ALL { ok = false; }
  }
  let ac = upnp_classify_target("SSDP:ALL");
  if !ac.is_ok { ok = false; } else {
    let t: SsdpTarget = ac.value;
    if t.kind != UPNP_TARGET_SSDP_ALL { ok = false; }
  }
  let b = upnp_classify_target("upnp:rootdevice");
  if !b.is_ok { ok = false; } else {
    let t: SsdpTarget = b.value;
    if t.kind != UPNP_TARGET_ROOTDEVICE { ok = false; }
  }
  let c = upnp_classify_target("uuid:2fac1234-31f8-11b4-a222-08002b34c003");
  if !c.is_ok { ok = false; } else {
    let t: SsdpTarget = c.value;
    if t.kind != UPNP_TARGET_UUID { ok = false; }
    if !str_eq(t.uuid, "2fac1234-31f8-11b4-a222-08002b34c003") { ok = false; }
  }
  let d = upnp_classify_target(_DEVTYPE);
  if !d.is_ok { ok = false; } else {
    let t: SsdpTarget = d.value;
    if t.kind != UPNP_TARGET_DEVICE { ok = false; }
    if !str_eq(t.domain, "schemas-upnp-org") { ok = false; }
    if !str_eq(t.class_word, "device") { ok = false; }
    if !str_eq(t.dev_type, "MediaRenderer") { ok = false; }
    if !str_eq(t.version, "1") { ok = false; }
    if t.major != 1 { ok = false; }
    if t.minor != -1 { ok = false; }
  }
  let e = upnp_classify_target("urn:schemas-upnp-org:service:WANIPConnection:2.0");
  if !e.is_ok { ok = false; } else {
    let t: SsdpTarget = e.value;
    if t.kind != UPNP_TARGET_SERVICE { ok = false; }
    if t.major != 2 { ok = false; }
    if t.minor != 0 { ok = false; }
  }
  let f = upnp_classify_target("urn:ietf:params:xml:ns:foo");
  if !f.is_ok { ok = false; } else {
    let t: SsdpTarget = f.value;
    if t.kind != UPNP_TARGET_OTHER_URN { ok = false; }
  }
  if !target_err_is(upnp_classify_target(""), "upnp: empty target", 0) { ok = false; }
  if !target_err_is(upnp_classify_target("uuid:xyz"), "upnp: bad uuid in target", 5) { ok = false; }
  if !target_err_is(upnp_classify_target("banana"), "upnp: bad target", 0) { ok = false; }
  if !target_err_is(upnp_classify_target("urn:schemas-upnp-org:device:MediaRenderer"), "upnp: bad urn in target", 4) { ok = false; }
  if !target_err_is(upnp_classify_target("urn:schemas-upnp-org:device::1"), "upnp: bad type in target", 28) { ok = false; }
  if !target_err_is(upnp_classify_target("urn:schemas-upnp-org:device:X:1.2.3"), "upnp: bad version in target", 30) { ok = false; }
  if !str_eq(upnp_target_name(UPNP_TARGET_SERVICE), "service") { ok = false; }
  return assert(ok, "ST/NT classification: ssdp:all, rootdevice, uuid, device/service urns, bad forms");
}

fn t12() -> TestResult {
  let r = upnp_build_msearch(_HOST, 3, "ssdp:all", "test/1.0");
  if !r.is_ok { return assert(false, "M-SEARCH build must succeed"); }
  let built: Vec[UInt8] = r.value;
  let want = bs("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: ssdp:all\r\nUSER-AGENT: test/1.0\r\n\r\n");
  var ok = bytes_equal(built, want);
  let pr = upnp_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let m: SsdpMessage = pr.value;
    if !str_eq(m.host, _HOST) { ok = false; }
    if m.mx != 3 { ok = false; }
    if !str_eq(m.st, "ssdp:all") { ok = false; }
    if !str_eq(m.user_agent, "test/1.0") { ok = false; }
    if !str_eq(m.man, "\"ssdp:discover\"") { ok = false; }
  }
  let no_ua = upnp_build_msearch(_HOST, 1, "upnp:rootdevice", "");
  if !no_ua.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = no_ua.value;
    if !bytes_equal(b2, bs("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: upnp:rootdevice\r\n\r\n")) { ok = false; }
  }
  if !bytes_err_is(upnp_build_msearch("", 3, "ssdp:all", ""), "upnp: empty HOST", -1) { ok = false; }
  if !bytes_err_is(upnp_build_msearch(_HOST, 0, "ssdp:all", ""), "upnp: bad MX", -1) { ok = false; }
  if !bytes_err_is(upnp_build_msearch(_HOST, 3, "banana", ""), "upnp: bad ST", -1) { ok = false; }
  return assert(ok, "M-SEARCH serialises canonically and round-trips; bad arguments are rejected");
}

fn t13() -> TestResult {
  let r = upnp_build_notify_alive(_HOST, 1800, _LOC, _DEVTYPE, _USN_DEV, "test/1.0", 42, 7);
  if !r.is_ok { return assert(false, "NOTIFY alive build must succeed"); }
  let built: Vec[UInt8] = r.value;
  let want = bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\nNT: urn:schemas-upnp-org:device:MediaRenderer:1\r\nNTS: ssdp:alive\r\nSERVER: test/1.0\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003::urn:schemas-upnp-org:device:MediaRenderer:1\r\nBOOTID.UPNP.ORG: 42\r\nCONFIGID.UPNP.ORG: 7\r\n\r\n");
  var ok = bytes_equal(built, want);
  let pr = upnp_parse(&built);
  if !pr.is_ok { ok = false; } else {
    let m: SsdpMessage = pr.value;
    if m.nts_kind != UPNP_NTS_ALIVE { ok = false; }
    if m.max_age != 1800 { ok = false; }
    if m.bootid != 42 { ok = false; }
    if m.configid != 7 { ok = false; }
    if !str_eq(m.nt, _DEVTYPE) { ok = false; }
    if !str_eq(m.usn, _USN_DEV) { ok = false; }
    if !str_eq(m.location, _LOC) { ok = false; }
    if !str_eq(m.server, "test/1.0") { ok = false; }
  }
  let minimal = upnp_build_notify_alive(_HOST, 60, _LOC, _UUID, _UUID, "", -1, -1);
  if !minimal.is_ok { ok = false; } else {
    let b2: Vec[UInt8] = minimal.value;
    if !bytes_equal(b2, bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=60\r\nLOCATION: http://192.168.1.10:8200/desc.xml\r\nNT: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\nNTS: ssdp:alive\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\n\r\n")) { ok = false; }
  }
  if !bytes_err_is(upnp_build_notify_alive(_HOST, 0, _LOC, _DEVTYPE, _USN_DEV, "", -1, -1), "upnp: bad CACHE-CONTROL", -1) { ok = false; }
  if !bytes_err_is(upnp_build_notify_alive(_HOST, 1800, "ftp://x", _DEVTYPE, _USN_DEV, "", -1, -1), "upnp: bad LOCATION", -1) { ok = false; }
  if !bytes_err_is(upnp_build_notify_alive(_HOST, 1800, _LOC, _DEVTYPE, "nope", "", -1, -1), "upnp: bad USN", -1) { ok = false; }
  if !bytes_err_is(upnp_build_notify_alive(_HOST, 1800, _LOC, _DEVTYPE, _USN_DEV, "", 4294967296, -1), "upnp: bad BOOTID.UPNP.ORG", -1) { ok = false; }
  if !bytes_err_is(upnp_build_notify_alive(_HOST, 1800, _LOC, _DEVTYPE, _USN_DEV, "", -1, 16777216), "upnp: bad CONFIGID.UPNP.ORG", -1) { ok = false; }
  return assert(ok, "NOTIFY ssdp:alive serialises canonically and round-trips; bad arguments are rejected");
}

fn t14() -> TestResult {
  var ok = true;
  if !str_eq(upnp_canonical_header_name("host"), "HOST") { ok = false; }
  if !str_eq(upnp_canonical_header_name("man"), "MAN") { ok = false; }
  if !str_eq(upnp_canonical_header_name("mx"), "MX") { ok = false; }
  if !str_eq(upnp_canonical_header_name("st"), "ST") { ok = false; }
  if !str_eq(upnp_canonical_header_name("user-agent"), "USER-AGENT") { ok = false; }
  if !str_eq(upnp_canonical_header_name("CACHE-control"), "CACHE-CONTROL") { ok = false; }
  if !str_eq(upnp_canonical_header_name("Date"), "DATE") { ok = false; }
  if !str_eq(upnp_canonical_header_name("ext"), "EXT") { ok = false; }
  if !str_eq(upnp_canonical_header_name("Location"), "LOCATION") { ok = false; }
  if !str_eq(upnp_canonical_header_name("nt"), "NT") { ok = false; }
  if !str_eq(upnp_canonical_header_name("nts"), "NTS") { ok = false; }
  if !str_eq(upnp_canonical_header_name("server"), "SERVER") { ok = false; }
  if !str_eq(upnp_canonical_header_name("usn"), "USN") { ok = false; }
  if !str_eq(upnp_canonical_header_name("bootid.upnp.org"), "BOOTID.UPNP.ORG") { ok = false; }
  if !str_eq(upnp_canonical_header_name("ConfigID.Upnp.Org"), "CONFIGID.UPNP.ORG") { ok = false; }
  if !str_eq(upnp_canonical_header_name("searchport.upnp.org"), "SEARCHPORT.UPNP.ORG") { ok = false; }
  if !str_eq(upnp_canonical_header_name("X-Custom"), "X-Custom") { ok = false; }
  if !str_eq(upnp_msg_kind_name(UPNP_KIND_RESPONSE), "response") { ok = false; }
  if !str_eq(upnp_msg_kind_name(9), "unknown") { ok = false; }
  if !str_eq(upnp_nts_name(UPNP_NTS_ALIVE), "ssdp:alive") { ok = false; }
  return assert(ok, "canonical header-name casing and kind names are stable");
}

fn t15() -> TestResult {
  var ok = true;
  if !msg_err_is(upnp_parse(&Vec[UInt8].new()), "upnp: empty message", 0) { ok = false; }
  let big = repeat_byte(97, 8193);
  if !msg_err_is(upnp_parse(&big), "upnp: message too large", 8193) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\nHOST: x\r\n\r\n")), "upnp: bare LF", 19) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\rX")), "upnp: bare CR", 19) { ok = false; }
  let head = bs("M-SEARCH * HTTP/1.1\r\nHOST: a");
  let ctl = insert_byte(head, 1, bs("b\r\n\r\n"));
  if !msg_err_is(upnp_parse(&ctl), "upnp: control character", 28) { ok = false; }
  let nulbuf = insert_byte(head, 0, bs("b\r\n\r\n"));
  if !msg_err_is(upnp_parse(&nulbuf), "upnp: control character", 28) { ok = false; }
  let delbuf = insert_byte(head, 127, bs("b\r\n\r\n"));
  if !msg_err_is(upnp_parse(&delbuf), "upnp: control character", 28) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\r\nHOST x\r\n\r\n")), "upnp: missing colon in header", 27) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\r\n: x\r\n\r\n")), "upnp: empty header name", 21) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\r\nHO ST: x\r\n\r\n")), "upnp: bad header name", 23) { ok = false; }
  return assert(ok, "empty/oversized messages and CRLF/control/header-line violations are rejected");
}

fn t16() -> TestResult {
  var ok = true;
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP")), "upnp: bad version", 11) { ok = false; }
  if !msg_err_is(upnp_parse(&bs("M-SEARCH * HTTP/1.1\r\nHOST")), "upnp: missing colon in header", 25) { ok = false; }
  let trunc = bs("M-SEARCH * HTTP/1.1\r\nHOST: 239");
  if !msg_err_is(upnp_parse(&trunc), "upnp: missing required header MAN", trunc.len()) { ok = false; }
  let cr_eof = bs("M-SEARCH * HTTP/1.1\r\nHOST: a\r");
  if !msg_err_is(upnp_parse(&cr_eof), "upnp: bare CR", cr_eof.len() - 1) { ok = false; }
  if !msg_err_is(upnp_parse(&Vec[UInt8].new()), "upnp: empty message", 0) { ok = false; }
  return assert(ok, "truncated buffers report the offset where the input ran out");
}

fn t17() -> TestResult {
  var ok = true;
  if !upnp_validate_authority("239.255.255.250:1900") { ok = false; }
  if !upnp_validate_authority("host") { ok = false; }
  if !upnp_validate_authority("host:1") { ok = false; }
  if !upnp_validate_authority("host:65535") { ok = false; }
  if !upnp_validate_authority("[fe80::1]:1900") { ok = false; }
  if !upnp_validate_authority("[fe80::1]") { ok = false; }
  if upnp_validate_authority("host:0") { ok = false; }
  if upnp_validate_authority("host:65536") { ok = false; }
  if upnp_validate_authority(":80") { ok = false; }
  if upnp_validate_authority("host:12a") { ok = false; }
  if upnp_validate_authority("[fe80::1:1900") { ok = false; }
  if upnp_validate_authority("a b:1") { ok = false; }
  if !upnp_validate_location("http://192.168.1.10:8200/desc.xml") { ok = false; }
  if !upnp_validate_location("https://host/x") { ok = false; }
  if !upnp_validate_location("http://host") { ok = false; }
  if !upnp_validate_location("HTTP://HOST:80/x") { ok = false; }
  if !upnp_validate_location("http://[fe80::1]:1900/d") { ok = false; }
  if upnp_validate_location("") { ok = false; }
  if upnp_validate_location("ftp://host/x") { ok = false; }
  if upnp_validate_location("http://") { ok = false; }
  if upnp_validate_location("http://:80/x") { ok = false; }
  if upnp_validate_location("http://host:0/x") { ok = false; }
  if upnp_validate_location("http://host:70000/x") { ok = false; }
  if upnp_validate_location("http://ho st/x") { ok = false; }
  if upnp_validate_location("http://[fe80::1/x") { ok = false; }
  if upnp_validate_location("//host/x") { ok = false; }
  return assert(ok, "authority and LOCATION validation: schemes, hosts, ports and brackets");
}

fn t18() -> TestResult {
  var ok = true;
  let base = bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: upnp:rootdevice\r\nNTS: ssdp:byebye\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\n");
  let ok_int = cat(base, bs("BOOTID.UPNP.ORG: 4294967295\r\nSEARCHPORT.UPNP.ORG: 1900\r\n\r\n"));
  let ir = upnp_parse(&ok_int);
  if !ir.is_ok { ok = false; } else {
    let m: SsdpMessage = ir.value;
    if m.bootid != 4294967295 { ok = false; }
    if m.searchport != 1900 { ok = false; }
    if m.configid != -1 { ok = false; }
  }
  let off_bo = base.len();
  let bad_bo = cat(base, bs("BOOTID.UPNP.ORG: 4294967296\r\n\r\n"));
  if !msg_err_is(upnp_parse(&bad_bo), "upnp: bad BOOTID.UPNP.ORG", off_bo) { ok = false; }
  let bad_bo2 = cat(base, bs("BOOTID.UPNP.ORG: 99999999999\r\n\r\n"));
  if !msg_err_is(upnp_parse(&bad_bo2), "upnp: bad BOOTID.UPNP.ORG", off_bo) { ok = false; }
  let off_sp = base.len() + string.str_len("BOOTID.UPNP.ORG: 1\r\n");
  let bad_sp = cat(base, bs("BOOTID.UPNP.ORG: 1\r\nSEARCHPORT.UPNP.ORG: 0\r\n\r\n"));
  if !msg_err_is(upnp_parse(&bad_sp), "upnp: bad SEARCHPORT.UPNP.ORG", off_sp) { ok = false; }
  let bad_sp2 = cat(base, bs("SEARCHPORT.UPNP.ORG: 65536\r\n\r\n"));
  if !msg_err_is(upnp_parse(&bad_sp2), "upnp: bad SEARCHPORT.UPNP.ORG", base.len()) { ok = false; }
  let off_ci = base.len() + string.str_len("CONFIGID.UPNP.ORG: 16777215\r\n");
  let ok_ci = cat(base, bs("CONFIGID.UPNP.ORG: 16777215\r\n\r\n"));
  let cir = upnp_parse(&ok_ci);
  if !cir.is_ok { ok = false; } else {
    let cm: SsdpMessage = cir.value;
    if cm.configid != 16777215 { ok = false; }
  }
  let bad_ci = cat(base, bs("CONFIGID.UPNP.ORG: 16777216\r\n\r\n"));
  if !msg_err_is(upnp_parse(&bad_ci), "upnp: bad CONFIGID.UPNP.ORG", base.len()) { ok = false; }
  if off_ci <= 0 { ok = false; }
  let acc = bs("NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nNT: upnp:rootdevice\r\nNTS: ssdp:byebye\r\nUSN: uuid:2fac1234-31f8-11b4-a222-08002b34c003\r\nX-TEST: one\r\n\r\n");
  let ar = upnp_parse(&acc);
  if !ar.is_ok { ok = false; } else {
    let am: SsdpMessage = ar.value;
    if upnp_header_count(&am) != 5 { ok = false; }
    if !str_eq(upnp_header(&am, "x-test"), "one") { ok = false; }
    if !str_eq(upnp_header(&am, "X-Test"), "one") { ok = false; }
    if !str_eq(upnp_header(&am, "absent"), "") { ok = false; }
    if upnp_has_header(&am, "absent") { ok = false; }
    if !str_eq(upnp_header_name(&am, 6), "") { ok = false; }
    if !str_eq(upnp_header_value(&am, 6), "") { ok = false; }
    if upnp_header_offset(&am, 6) != -1 { ok = false; }
    if upnp_header_offset(&am, 4) <= 0 { ok = false; }
  }
  return assert(ok, "integer headers enforce 32/24/16-bit bounds; accessors guard ranges");
}

fn main() -> Int {
  io.println("=== xiom.upnp conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.upnp: all tests passed");
  } else {
    io.println("xiom.upnp: tests failed");
  }
  return failed;
}
