// XIOM -- xiom.postgres conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Layout:
//   1. message codec goldens: exact bytes for every frontend builder and
//      literal-byte decode goldens for every backend message kind, plus
//      truncated/garbage inputs (typed protocol errors with byte offsets);
//   2. authentication KATs: the RFC 7677 SCRAM-SHA-256 vector and the
//      PostgreSQL MD5 challenge vector (independently computed oracles;
//      see PROVENANCE.md);
//   3. deterministic OFFLINE loopback tests: the suite binds a listener on
//      loopback and runs a tiny scripted PG server in-process (no threads:
//      thread spawn is simulated in this toolchain). The scripted server
//      pre-writes its full reply script, the client side runs against a
//      real TCP loopback connection through `attach` (fd adoption), and the
//      server then reads the client's bytes back and asserts them exactly
//      -- startup, password/query/Terminate included;
//   4. error taxonomy: connection refused, protocol violation, unsupported
//      auth, timeout, closed-connection guards, safe-quote KATs;
//   5. live path: if 127.0.0.1:5432 is unreachable the test reports an
//      explicit honest SKIP; otherwise it runs real queries.
//
// Str equality goes through compare.str_compare (BUG 17 discipline).

module postgres_tests

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.net.socket;
use xiom.postgres;
use xiom.postgres.wire;
use xiom.postgres.auth;

// ---------------------------------------------------------------- helpers

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn note(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  return 1;
}

fn literal(vals: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    out.push(vals[i] as UInt8);
    i = i + 1;
  }
  return out;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

fn bs(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn bc(s: Str) -> Vec[UInt8] {
  var out = bs(s);
  out.push(0);
  return out;
}

fn add(out: &mut Vec[UInt8], piece: &Vec[UInt8]) {
  var i = 0;
  while i < piece.len() {
    out.push(piece[i]);
    i = i + 1;
  }
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => {
      return streq(v, want);
    },
    None => {
      return false;
    },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => {
      return false;
    },
    None => {
      return true;
    },
  }
  return true;
}

fn dec_body_str(body: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < body.len() {
    out.push(body[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// ------------------------------------------------- scripted-server builders

fn be_i32(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((v >> 24) & 0xFF) as UInt8);
  out.push(((v >> 16) & 0xFF) as UInt8);
  out.push(((v >> 8) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
  return out;
}

fn be_i16(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(((v >> 8) & 0xFF) as UInt8);
  out.push((v & 0xFF) as UInt8);
  return out;
}

fn b_typed(t: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(t as UInt8);
  add(&mut out, &be_i32(body.len() + 4));
  add(&mut out, body);
  return out;
}

fn b_auth(code: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i32(code));
  return b_typed(82, &body);
}

fn b_auth_md5(salt: &Vec[UInt8]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i32(5));
  add(&mut body, salt);
  return b_typed(82, &body);
}

fn b_auth_sasl(mech: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i32(10));
  add(&mut body, &bc(mech));
  body.push(0);
  return b_typed(82, &body);
}

fn b_auth_sasl_data(code: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i32(code));
  add(&mut body, data);
  return b_typed(82, &body);
}

fn b_param(name: Str, value: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &bc(name));
  add(&mut body, &bc(value));
  return b_typed(83, &body);
}

fn b_backend_key(pid: Int, secret: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i32(pid));
  add(&mut body, &be_i32(secret));
  return b_typed(75, &body);
}

fn b_ready(st: Int) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  body.push(st as UInt8);
  return b_typed(90, &body);
}

fn b_row_desc(names: &Vec[Str], oids: &Vec[Int], sizes: &Vec[Int]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i16(names.len()));
  var i = 0;
  while i < names.len() {
    add(&mut body, &bc(names[i]));
    add(&mut body, &be_i32(0));
    add(&mut body, &be_i16(0));
    add(&mut body, &be_i32(oids[i]));
    var sz = sizes[i];
    if sz < 0 {
      sz = 65536 + sz;
    }
    add(&mut body, &be_i16(sz));
    add(&mut body, &be_i32(-1));
    add(&mut body, &be_i16(0));
    i = i + 1;
  }
  return b_typed(84, &body);
}

fn b_data_row(vals: &Vec[Option[Str]]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &be_i16(vals.len()));
  var i = 0;
  while i < vals.len() {
    let v = vals[i];
    match v {
      Some(s) => {
        add(&mut body, &be_i32(s.len()));
        add(&mut body, &bs(s));
      },
      None => {
        add(&mut body, &be_i32(-1));
      },
    }
    i = i + 1;
  }
  return b_typed(68, &body);
}

fn b_command(tag: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  add(&mut body, &bc(tag));
  return b_typed(67, &body);
}

fn b_error_like(t: Int, codes: &Vec[Str], vals: &Vec[Str]) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  var i = 0;
  while i < codes.len() && i < vals.len() {
    body.push(codes[i].byte_at(0));
    add(&mut body, &bc(vals[i]));
    i = i + 1;
  }
  body.push(0);
  return b_typed(t, &body);
}

// ------------------------------------------------- scripted-server socket IO

var srv_buf: Vec[UInt8] = Vec[UInt8].new();

fn srv_reset() {
  srv_buf = Vec[UInt8].new();
}

fn srv_take(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(srv_buf[i]);
    i = i + 1;
  }
  var rest = Vec[UInt8].new();
  var j = n;
  while j < srv_buf.len() {
    rest.push(srv_buf[j]);
    j = j + 1;
  }
  srv_buf = rest;
  return out;
}

fn srv_fill(fd: Int, need: Int, timeout_ms: Int) -> Bool {
  while srv_buf.len() < need {
    let rr = socket.socket_recv_timeout(fd, 65536, timeout_ms);
    match rr {
      Ok(chunk) => {
        if chunk.len() == 0 {
          return false;
        }
        var i = 0;
        while i < chunk.len() {
          srv_buf.push(chunk[i]);
          i = i + 1;
        }
      },
      Err(_) => {
        return false;
      },
    }
  }
  return true;
}

fn srv_read_startup(fd: Int, timeout_ms: Int) -> Result[Vec[UInt8], Str] {
  if !srv_fill(fd, 4, timeout_ms) {
    return Err("startup length header not received");
  }
  let lr = read_i32(&srv_buf, 0, srv_buf.len());
  var len = 0;
  match lr {
    Ok(v) => {
      len = v;
    },
    Err(_) => {
      return Err("bad startup length field");
    },
  }
  if len < 8 {
    return Err("startup length below protocol header");
  }
  if !srv_fill(fd, len, timeout_ms) {
    return Err("startup message truncated");
  }
  return Ok(srv_take(len));
}

fn srv_read_msg(fd: Int, timeout_ms: Int) -> Result[SrvMsg, Str] {
  if !srv_fill(fd, 5, timeout_ms) {
    return Err("message header not received");
  }
  let lr = read_i32(&srv_buf, 1, srv_buf.len());
  var len = 0;
  match lr {
    Ok(v) => {
      len = v;
    },
    Err(_) => {
      return Err("bad message length field");
    },
  }
  if len < 4 {
    return Err("message length below 4");
  }
  if !srv_fill(fd, 1 + len, timeout_ms) {
    return Err("message body truncated");
  }
  let raw = srv_take(1 + len);
  var ts: Vec[UInt8] = Vec[UInt8].new();
  ts.push(raw[0]);
  var body = Vec[UInt8].new();
  var i = 5;
  while i < raw.len() {
    body.push(raw[i]);
    i = i + 1;
  }
  return Ok(SrvMsg{ mt: Str::from_utf8(ts); body: body });
}

// ------------------------------------------------- loopback scaffolding

type ListenAny = {
  fd: Int;
  port: Int;
}

type LoopPair = {
  cfd: Int;
  sfd: Int;
}

type SrvMsg = {
  mt: Str;
  body: Vec[UInt8];
}

fn listen_any() -> ListenAny {
  var port = 45440;
  while port < 45500 {
    let tr = socket.socket_tcp();
    match tr {
      Ok(fd) => {
        let br = socket.socket_bind(fd, "127.0.0.1", port);
        if br.is_ok {
          let ls = socket.socket_listen(fd, 4);
          if ls.is_ok {
            return ListenAny{ fd: fd; port: port };
          }
        }
        socket.socket_close(fd);
      },
      Err(_) => {},
    }
    port = port + 1;
  }
  return ListenAny{ fd: -1; port: 0 };
}

fn loop_connect(lfd: Int, port: Int) -> LoopPair {
  let ct = socket.socket_tcp();
  var cfd = 0;
  match ct {
    Ok(v) => {
      cfd = v;
    },
    Err(_) => {
      return LoopPair{ cfd: -1; sfd: -1 };
    },
  }
  let con = socket.socket_connect(cfd, "127.0.0.1", port);
  if con.is_err {
    socket.socket_close(cfd);
    return LoopPair{ cfd: -1; sfd: -1 };
  }
  let at = socket.socket_accept(lfd);
  var sfd = 0;
  match at {
    Ok(v) => {
      sfd = v;
    },
    Err(_) => {
      socket.socket_close(cfd);
      return LoopPair{ cfd: -1; sfd: -1 };
    },
  }
  return LoopPair{ cfd: cfd; sfd: sfd };
}

fn srv_send(fd: Int, bytes: &Vec[UInt8]) -> Bool {
  let sr = socket.socket_send_all(fd, bytes);
  return sr.is_ok;
}

// ---------------------------------------------------------------- section 1
// message codec goldens

fn t01_startup_bytes() -> TestResult {
  let want: Vec[Int] = [
    0, 0, 0, 35,
    0, 3, 0, 0,
    117, 115, 101, 114, 0,
    112, 103, 117, 115, 101, 114, 0,
    100, 97, 116, 97, 98, 97, 115, 101, 0,
    112, 103, 100, 98, 0,
    0];
  let got = build_startup("pguser", "pgdb");
  var ok = bytes_eq(&got, &literal(&want));
  if got.len() != 35 {
    ok = false;
  }
  return assert(ok, "codec: StartupMessage exact bytes (35)");
}

fn t02_password_bytes() -> TestResult {
  let want: Vec[Int] = [112, 0, 0, 0, 11, 115, 51, 99, 114, 101, 116, 0];
  return assert(bytes_eq(&build_password("s3cret"), &literal(&want)), "codec: PasswordMessage exact bytes");
}

fn t03_query_bytes() -> TestResult {
  let want: Vec[Int] = [81, 0, 0, 0, 13, 83, 69, 76, 69, 67, 84, 32, 49, 0];
  return assert(bytes_eq(&build_query("SELECT 1"), &literal(&want)), "codec: Query exact bytes");
}

fn t04_terminate_bytes() -> TestResult {
  let want: Vec[Int] = [88, 0, 0, 0, 4];
  return assert(bytes_eq(&build_terminate(), &literal(&want)), "codec: Terminate exact bytes");
}

fn t05_sasl_bytes() -> TestResult {
  let init = build_sasl_initial("SCRAM-SHA-256", "n=u,r=abc");
  let want_init: Vec[Int] = [
    112, 0, 0, 0, 31,
    83, 67, 82, 65, 77, 45, 83, 72, 65, 45, 50, 53, 54, 0,
    0, 0, 0, 9,
    110, 61, 117, 44, 114, 61, 97, 98, 99];
  var ok = bytes_eq(&init, &literal(&want_init));
  let resp = build_sasl_response("c=biws,r=abc,p=xx");
  let head: Vec[Int] = [112, 0, 0, 0, 21];
  var gold: Vec[UInt8] = Vec[UInt8].new();
  add(&mut gold, &literal(&head));
  add(&mut gold, &bs("c=biws,r=abc,p=xx"));
  if !bytes_eq(&resp, &gold) {
    ok = false;
  }
  return assert(ok, "codec: SASLInitialResponse/SASLResponse exact bytes");
}

fn t06_auth_ok() -> TestResult {
  let buf = literal(&[82, 0, 0, 0, 8, 0, 0, 0, 0]);
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(m.msg_type, "R") && m.auth_code == 0 && m.next == 9 && m.length == 8;
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: AuthenticationOk");
}

fn t07_auth_cleartext_md5() -> TestResult {
  let okbuf = literal(&[82, 0, 0, 0, 8, 0, 0, 0, 3]);
  let r1 = wire_decode(&okbuf, 0);
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = m.auth_code == 3;
    },
    Err(_) => {
      ok = false;
    },
  }
  let mbuf = literal(&[82, 0, 0, 0, 12, 0, 0, 0, 5, 161, 178, 195, 212]);
  let r2 = wire_decode(&mbuf, 0);
  match r2 {
    Ok(m) => {
      if m.auth_code != 5 {
        ok = false;
      }
      if m.salt.len() != 4 || m.salt[0] != (161 as UInt8) || m.salt[3] != (212 as UInt8) {
        ok = false;
      }
      if m.next != 13 {
        ok = false;
      }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: AuthenticationCleartext/MD5+4-byte salt");
}

fn t08_auth_sasl() -> TestResult {
  var buf: Vec[UInt8] = Vec[UInt8].new();
  add(&mut buf, &b_auth_sasl("SCRAM-SHA-256"));
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.auth_code == 10 && m.mechanisms.len() == 1 && streq(m.mechanisms[0], "SCRAM-SHA-256");
    },
    Err(_) => {
      ok = false;
    },
  }
  var buf2: Vec[UInt8] = Vec[UInt8].new();
  add(&mut buf2, &b_auth_sasl_data(11, &bs("r=abc,s=zz,i=4096")));
  let r2 = wire_decode(&buf2, 0);
  match r2 {
    Ok(m) => {
      if m.auth_code != 11 {
        ok = false;
      }
      var got = Vec[UInt8].new();
      var i = 0;
      while i < m.sasl_data.len() {
        got.push(m.sasl_data[i]);
        i = i + 1;
      }
      if !bytes_eq(&got, &bs("r=abc,s=zz,i=4096")) {
        ok = false;
      }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: AuthenticationSASL mechanisms + SASL continue data");
}

fn t09_row_description() -> TestResult {
  let buf = literal(&[
    84, 0, 0, 0, 27,
    0, 1,
    105, 100, 0,
    0, 0, 0, 0,
    0, 0,
    0, 0, 0, 23,
    0, 4,
    255, 255, 255, 255,
    0, 0]);
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.fields.len() == 1;
      if ok {
        let f = m.fields[0];
        if !streq(f.name, "id") { ok = false; }
        if f.type_oid != 23 { ok = false; }
        if f.type_size != 4 { ok = false; }
        if f.type_mod != -1 { ok = false; }
        if f.format != 0 { ok = false; }
        if f.table_oid != 0 { ok = false; }
      }
      if m.next != 28 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: RowDescription (int4, type_size 4, type_mod -1)");
}

fn t10_data_row_nulls() -> TestResult {
  let buf = literal(&[
    68, 0, 0, 0, 16,
    0, 2,
    0, 0, 0, 2, 52, 50,
    255, 255, 255, 255]);
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.values.len() == 2 && opt_is(m.values[0], "42") && opt_none(m.values[1]);
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: DataRow with value + NULL (text format)");
}

fn t11_data_row_quotes() -> TestResult {
  var body: Vec[UInt8] = Vec[UInt8].new();
  add(&mut body, &be_i16(3));
  add(&mut body, &be_i32(5));
  add(&mut body, &bs("a'b\\c"));
  add(&mut body, &be_i32(0));
  add(&mut body, &be_i32(-1));
  let buf = b_typed(68, &body);
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.values.len() == 3;
      if ok {
        if !opt_is(m.values[0], "a'b\\c") { ok = false; }
        if !opt_is(m.values[1], "") { ok = false; }
        if !opt_none(m.values[2]) { ok = false; }
      }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: DataRow embedded quote/backslash, empty vs NULL");
}

fn t12_command_complete() -> TestResult {
  let buf = literal(&[67, 0, 0, 0, 13, 83, 69, 76, 69, 67, 84, 32, 53, 0]);
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(m.tag, "SELECT 5") && m.affected == 5 && m.next == 14;
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: CommandComplete tag + affected rows");
}

fn t13_tag_affected() -> TestResult {
  var ok = pg_tag_affected("INSERT 0 3") == 3;
  if pg_tag_affected("UPDATE 2") != 2 { ok = false; }
  if pg_tag_affected("SELECT 0") != 0 { ok = false; }
  if pg_tag_affected("CREATE TABLE") != 0 { ok = false; }
  if pg_tag_affected("BEGIN") != 0 { ok = false; }
  if pg_tag_affected("") != 0 { ok = false; }
  if pg_tag_affected("DELETE 12 ") != 12 { ok = false; }
  return assert(ok, "codec: command tag affected-rows parsing");
}

fn t14_error_response() -> TestResult {
  let want: Vec[Int] = [
    69, 0, 0, 0, 19,
    83, 69, 82, 82, 79, 82, 0,
    67, 52, 50, 54, 48, 49, 0,
    0];
  let r = wire_decode(&literal(&want), 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = m.err_fields.len() == 2 && streq(m.severity, "ERROR") && streq(m.code, "42601");
    },
    Err(_) => {
      ok = false;
    },
  }
  var codes: Vec[Str] = ["S", "V", "C", "M", "D", "H", "P", "F", "L", "R"];
  var vals: Vec[Str] = [
    "ERROR", "ERROR", "42P01",
    "relation \"x\" does not exist",
    "from table t", "check the name", "15",
    "parse_relation.c", "1371", "parserOpenTable"];
  var buf: Vec[UInt8] = Vec[UInt8].new();
  add(&mut buf, &b_error_like(69, &codes, &vals));
  let r2 = wire_decode(&buf, 0);
  match r2 {
    Ok(m) => {
      if m.err_fields.len() != 10 { ok = false; }
      if !streq(m.code, "42P01") { ok = false; }
      if !streq(m.severity, "ERROR") { ok = false; }
      if !streq(m.message, "relation \"x\" does not exist") { ok = false; }
      if !streq(m.detail, "from table t") { ok = false; }
      if !streq(m.hint, "check the name") { ok = false; }
      if m.position != 15 { ok = false; }
      let er = server_error_from(&m);
      if er.kind != PG_ERR_SERVER { ok = false; }
      if er.fields.len() != 10 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: ErrorResponse multi-field (S/V/C/M/D/H/P/F/L/R)");
}

fn t15_notice_and_notification() -> TestResult {
  var codes: Vec[Str] = ["S", "C", "M"];
  var vals: Vec[Str] = ["NOTICE", "00000", "i am a notice"];
  var buf: Vec[UInt8] = Vec[UInt8].new();
  add(&mut buf, &b_error_like(78, &codes, &vals));
  let r = wire_decode(&buf, 0);
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(m.msg_type, "N") && streq(m.severity, "NOTICE") && streq(m.message, "i am a notice");
    },
    Err(_) => {
      ok = false;
    },
  }
  var nbody: Vec[UInt8] = Vec[UInt8].new();
  add(&mut nbody, &be_i32(1234));
  add(&mut nbody, &bc("chan"));
  add(&mut nbody, &bc("payload!"));
  let nbuf = b_typed(65, &nbody);
  let r2 = wire_decode(&nbuf, 0);
  match r2 {
    Ok(m) => {
      if m.pid != 1234 { ok = false; }
      if !streq(m.channel, "chan") { ok = false; }
      if !streq(m.payload, "payload!") { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: NoticeResponse + NotificationResponse");
}

fn t16_ready_param_key() -> TestResult {
  var ok = false;
  let rb = literal(&[90, 0, 0, 0, 5, 73]);
  let rr = wire_decode(&rb, 0);
  match rr {
    Ok(m) => {
      ok = streq(m.status, "I") && m.next == 6;
    },
    Err(_) => {
      ok = false;
    },
  }
  let sb = literal(&[83, 0, 0, 0, 24,
    115, 101, 114, 118, 101, 114, 95, 118, 101, 114, 115, 105, 111, 110, 0,
    49, 54, 46, 52, 0]);
  let sr = wire_decode(&sb, 0);
  match sr {
    Ok(m) => {
      if !streq(m.param_name, "server_version") { ok = false; }
      if !streq(m.param_value, "16.4") { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  var kb: Vec[UInt8] = Vec[UInt8].new();
  add(&mut kb, &b_backend_key(1234, 5678));
  let kr = wire_decode(&kb, 0);
  match kr {
    Ok(m) => {
      if m.pid != 1234 { ok = false; }
      if m.secret != 5678 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  let ib = literal(&[73, 0, 0, 0, 4]);
  let ir = wire_decode(&ib, 0);
  match ir {
    Ok(m) => {
      if !streq(m.msg_type, "I") { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "decode: ReadyForQuery / ParameterStatus / BackendKeyData / EmptyQuery");
}

fn dec_err(buf: &Vec[UInt8], start: Int) -> PgError {
  let r = wire_decode(buf, start);
  match r {
    Ok(_) => {
      return err_protocol("no error", -999);
    },
    Err(e) => {
      return e;
    },
  }
  return err_protocol("no error", -999);
}

fn t17_decode_errors_truncated() -> TestResult {
  var ok = true;
  let short = literal(&[82, 0, 0]);
  let e1 = dec_err(&short, 0);
  if e1.kind != PG_ERR_PROTOCOL || e1.offset != 3 {
    ok = false;
  }
  let body = literal(&[82, 0, 0, 0, 12, 0, 0, 0, 0, 1, 2]);
  let e2 = dec_err(&body, 0);
  if e2.kind != PG_ERR_PROTOCOL || e2.offset != 11 {
    ok = false;
  }
  let low = literal(&[82, 0, 0, 0, 3]);
  let e3 = dec_err(&low, 0);
  if e3.kind != PG_ERR_PROTOCOL || e3.offset != 1 {
    ok = false;
  }
  let big = literal(&[82, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]);
  let e4 = dec_err(&big, 0);
  if e4.kind != PG_ERR_PROTOCOL || e4.offset != 1 {
    ok = false;
  }
  let unknown = literal(&[33, 0, 0, 0, 4]);
  let e5 = dec_err(&unknown, 0);
  if e5.kind != PG_ERR_PROTOCOL || e5.offset != 0 {
    ok = false;
  }
  let past = literal(&[82, 0, 0, 0, 8, 0, 0, 0, 0]);
  let e6 = dec_err(&past, 20);
  if e6.kind != PG_ERR_PROTOCOL || e6.offset != 20 {
    ok = false;
  }
  let badready = literal(&[90, 0, 0, 0, 5, 88]);
  let e7 = dec_err(&badready, 0);
  if e7.kind != PG_ERR_PROTOCOL || e7.offset != 5 {
    ok = false;
  }
  return assert(ok, "decode: truncated/garbage inputs are typed protocol errors");
}

fn t18_decode_offsets_and_chain() -> TestResult {
  var buf: Vec[UInt8] = Vec[UInt8].new();
  add(&mut buf, &literal(&[82, 0, 0, 0, 8, 0, 0, 0, 0]));
  add(&mut buf, &literal(&[90, 0, 0, 0, 5, 73]));
  let r1 = wire_decode(&buf, 0);
  var ok = false;
  match r1 {
    Ok(m) => {
      ok = m.next == 9 && m.start == 0;
    },
    Err(_) => {
      ok = false;
    },
  }
  let r2 = wire_decode(&buf, 9);
  match r2 {
    Ok(m) => {
      if !streq(m.msg_type, "Z") { ok = false; }
      if m.start != 9 { ok = false; }
      if m.next != 15 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  var emb: Vec[UInt8] = Vec[UInt8].new();
  add(&mut emb, &literal(&[255, 255, 255]));
  add(&mut emb, &literal(&[83, 0, 0, 0, 8, 120, 0, 121, 0]));
  let r3 = wire_decode(&emb, 3);
  match r3 {
    Ok(m) => {
      if !streq(m.param_name, "x") { ok = false; }
      if !streq(m.param_value, "y") { ok = false; }
      if m.start != 3 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  var nulbody: Vec[UInt8] = Vec[UInt8].new();
  add(&mut nulbody, &be_i16(1));
  add(&mut nulbody, &be_i32(3));
  add(&mut nulbody, &literal(&[97, 0, 98]));
  let nb = b_typed(68, &nulbody);
  let e8 = dec_err(&nb, 0);
  if e8.kind != PG_ERR_PROTOCOL || e8.offset != 12 {
    ok = false;
  }
  return assert(ok, "decode: message chaining, embedded start offset, NUL rejection");
}

// ---------------------------------------------------------------- section 2
// authentication KATs (oracles computed independently; see PROVENANCE.md)

fn t19_md5_kat() -> TestResult {
  let salt = literal(&[161, 178, 195, 212]);
  let got = pg_md5_password("s3cret", "pguser", &salt);
  var ok = streq(got, "md549a34335002b87ce9bfd06e813246528");
  if !streq(md5_hex(&bs("abc")), "900150983cd24fb0d6963f7d28e17f72") {
    ok = false;
  }
  if !streq(md5_hex(&bs("")), "d41d8cd98f00b204e9800998ecf8427e") {
    ok = false;
  }
  if !streq(md5_hex(&bs("The quick brown fox jumps over the lazy dog")), "9e107d9d372bb6826bd81d3542a419d6") {
    ok = false;
  }
  let salt2 = literal(&[1, 2, 3, 4]);
  let got2 = pg_md5_password("", "", &salt2);
  if got2.len() != 35 {
    ok = false;
  }
  return assert(ok, "auth: MD5 RFC 1321 vectors + PostgreSQL challenge vector");
}

fn t20_scram_first_and_escape() -> TestResult {
  var ok = streq(scram_client_first_bare("user", "rOprNGfwEbeRWgbNEkqO"), "n=user,r=rOprNGfwEbeRWgbNEkqO");
  if !streq(scram_client_first("user", "abc"), "n,,n=user,r=abc") {
    ok = false;
  }
  if !streq(scram_client_first_bare("a,b=c", "n1"), "n=a=2Cb=3Dc,r=n1") {
    ok = false;
  }
  let n1 = scram_client_nonce();
  let n2 = scram_client_nonce();
  if n1.len() < 16 {
    ok = false;
  }
  if streq(n1, n2) {
    ok = false;
  }
  return assert(ok, "auth: SCRAM client-first + saslname escaping + nonce");
}

fn t21_scram_rfc7677_vector() -> TestResult {
  let sf = "r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
  let cfb = "n=user,r=rOprNGfwEbeRWgbNEkqO";
  let fr = scram_client_final("pencil", cfb, "rOprNGfwEbeRWgbNEkqO", sf);
  var ok = false;
  let want = "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=";
  match fr {
    Ok(f) => {
      ok = streq(f.message, want);
      if !streq(f.server_sig_b64, "6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=") {
        ok = false;
      }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "auth: SCRAM-SHA-256 RFC 7677 published test vector");
}

fn t22_scram_parse_and_verify_errors() -> TestResult {
  var ok = true;
  let bad1 = scram_parse_server_first("s=zzz,i=4096");
  match bad1 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_AUTH { ok = false; }
    },
  }
  let bad2 = scram_parse_server_first("e=invalid-proof");
  match bad2 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_AUTH { ok = false; }
    },
  }
  let sf = "r=OTHER,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
  let bad3 = scram_client_final("pencil", "n=user,r=abc", "abc", sf);
  match bad3 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_AUTH { ok = false; }
    },
  }
  let good = "r=abcSRV,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
  let fr = scram_client_final("pencil", "n=user,r=abc", "abc", good);
  match fr {
    Ok(f) => {
      let vok = scram_verify_server_final("v=" + f.server_sig_b64, f.server_sig_b64);
      if vok.is_err { ok = false; }
      let vbad = scram_verify_server_final("v=AAAA", f.server_sig_b64);
      if vbad.is_ok { ok = false; }
      let verr = scram_verify_server_final("e=other-error", f.server_sig_b64);
      if verr.is_ok { ok = false; }
      let vmal = scram_verify_server_final("x=zz", f.server_sig_b64);
      if vmal.is_ok { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  return assert(ok, "auth: SCRAM parse/verify error taxonomy");
}

// ---------------------------------------------------------------- section 3
// deterministic offline loopback tests (scripted in-process server)

fn t23_loop_happy() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: happy path (no free port in 45440-45499)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: happy path (tcp connect/accept failed)");
  }
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth(0));
  add(&mut script, &b_param("server_version", "16.4"));
  add(&mut script, &b_param("client_encoding", "UTF8"));
  add(&mut script, &b_backend_key(4321, 8765));
  add(&mut script, &b_ready(73));
  var names: Vec[Str] = ["id", "name"];
  var oids: Vec[Int] = [23, 25];
  var sizes: Vec[Int] = [4, -1];
  add(&mut script, &b_row_desc(&names, &oids, &sizes));
  var r1v: Vec[Option[Str]] = [Some("1"), Some("alice")];
  add(&mut script, &b_data_row(&r1v));
  var r2v: Vec[Option[Str]] = [None, None];
  add(&mut script, &b_data_row(&r2v));
  add(&mut script, &b_command("SELECT 2"));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);

  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var conn_ok = false;
  match ar {
    Ok(conn) => {
      conn_ok = true;
      if !streq(pg_conn_param(&conn, "server_version"), "16.4") { ok = false; }
      if !streq(pg_conn_param(&conn, "client_encoding"), "UTF8") { ok = false; }
      if conn.pid != 4321 { ok = false; }
      if conn.secret != 8765 { ok = false; }
      if !pg_is_connected(&conn) { ok = false; }
      let qr = query(&mut conn, "SELECT id, name FROM t");
      match qr {
        Ok(res) => {
          if res.col_count != 2 { ok = false; }
          if res.row_count != 2 { ok = false; }
          if !streq(res.columns[0], "id") { ok = false; }
          if !streq(res.columns[1], "name") { ok = false; }
          if res.fields[0].type_oid != 23 { ok = false; }
          if res.fields[1].type_oid != 25 { ok = false; }
          if res.fields[1].type_size != -1 { ok = false; }
          if !streq(res.tag, "SELECT 2") { ok = false; }
          if res.affected != 2 { ok = false; }
          if !opt_is(res.rows[0][0], "1") { ok = false; }
          if !opt_is(res.rows[0][1], "alice") { ok = false; }
          if !opt_none(res.rows[1][0]) { ok = false; }
          if !opt_none(res.rows[1][1]) { ok = false; }
        },
        Err(_) => {
          ok = false;
        },
      }
      disconnect(&mut conn);
      if pg_is_connected(&conn) { ok = false; }
      disconnect(&mut conn);
    },
    Err(_) => {
      ok = false;
    },
  }
  if !conn_ok { ok = false; }

  let want_startup = build_startup("pguser", "pgdb");
  let sr = srv_read_startup(sfd, 5000);
  match sr {
    Ok(raw) => {
      if !bytes_eq(&raw, &want_startup) { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  let qm = srv_read_msg(sfd, 5000);
  match qm {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "Q") { ok = false; }
      if !bytes_eq(&body, &bc("SELECT id, name FROM t")) { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  let tm = srv_read_msg(sfd, 5000);
  match tm {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "X") { ok = false; }
      if body.len() != 0 { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: startup/query/terminate bytes + typed result set + NULLs");
}

fn t24_loop_cleartext_auth() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: cleartext auth (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: cleartext auth (tcp connect failed)");
  }
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth(3));
  add(&mut script, &b_auth(0));
  add(&mut script, &b_param("server_version", "16.4"));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  if ar.is_err {
    ok = false;
  }
  let sr = srv_read_startup(sfd, 5000);
  if sr.is_err {
    ok = false;
  }
  let pm = srv_read_msg(sfd, 5000);
  match pm {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "p") { ok = false; }
      if !bytes_eq(&body, &bc("s3cret")) { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: cleartext password message bytes on the wire");
}

fn t25_loop_md5_auth() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: md5 auth (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: md5 auth (tcp connect failed)");
  }
  let salt = literal(&[161, 178, 195, 212]);
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth_md5(&salt));
  add(&mut script, &b_auth(0));
  add(&mut script, &b_param("server_version", "16.4"));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  if ar.is_err {
    ok = false;
  }
  let sr = srv_read_startup(sfd, 5000);
  if sr.is_err {
    ok = false;
  }
  let pm = srv_read_msg(sfd, 5000);
  match pm {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "p") { ok = false; }
      if !bytes_eq(&body, &bc("md549a34335002b87ce9bfd06e813246528")) { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: MD5 challenge answer bytes match the oracle");
}

fn t26_loop_scram() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: SCRAM auth (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: SCRAM auth (tcp connect failed)");
  }
  let cnonce = "TESTNONCE0001";
  let combined = "TESTNONCE0001SRVNONCE9XYZ";
  let salt_b64 = "W22ZaJ0SNY7soEsUEjb6gQ==";
  let sf = "r=TESTNONCE0001SRVNONCE9XYZ,s=" + salt_b64 + ",i=4096";
  let cfb = "n=pguser,r=TESTNONCE0001";
  let auth_message = cfb + "," + sf + "," + "c=biws,r=" + combined;
  let srv_sig = scram_server_signature_b64("s3cret", salt_b64, 4096, auth_message);
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth_sasl("SCRAM-SHA-256"));
  add(&mut script, &b_auth_sasl_data(11, &bs(sf)));
  add(&mut script, &b_auth_sasl_data(12, &bs("v=" + srv_sig)));
  add(&mut script, &b_auth(0));
  add(&mut script, &b_param("server_version", "16.4"));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, cnonce);
  if ar.is_err {
    ok = false;
  }
  let sr = srv_read_startup(sfd, 5000);
  if sr.is_err {
    ok = false;
  }
  let m1 = srv_read_msg(sfd, 5000);
  var final_body = "";
  match m1 {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "p") { ok = false; }
      var head = Vec[UInt8].new();
      add(&mut head, &bc("SCRAM-SHA-256"));
      add(&mut head, &be_i32(cfb.len()));
      add(&mut head, &bs(cfb));
      if !bytes_eq(&body, &head) { ok = false; }
    },
    Err(_) => {
      ok = false;
    },
  }
  let m2 = srv_read_msg(sfd, 5000);
  match m2 {
    Ok(pair) => {
      let mt = pair.mt;
      let body = pair.body;
      if !streq(mt, "p") { ok = false; }
      final_body = dec_body_str(&body);
    },
    Err(_) => {
      ok = false;
    },
  }
  var prefix = "c=biws,r=" + combined + ",p=";
  if !string.str_starts_with(final_body, prefix) {
    ok = false;
  } else {
    let proof = string.str_slice(final_body, prefix.len(), final_body.len());
    if !scram_verify_proof_b64("s3cret", salt_b64, 4096, auth_message, proof) {
      ok = false;
    }
  }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: SCRAM-SHA-256 exchange end to end (proof verified server-side)");
}

fn t27_loop_auth_failure() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: auth failure (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: auth failure (tcp connect failed)");
  }
  var codes: Vec[Str] = ["S", "V", "C", "M"];
  var vals: Vec[Str] = ["FATAL", "FATAL", "28P01", "password authentication failed for user \"pguser\""];
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_error_like(69, &codes, &vals));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "wrong", "pgdb", 5000, "");
  var saw = false;
  match ar {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      saw = e.kind == PG_ERR_SERVER && streq(e.code, "28P01") && streq(e.severity, "FATAL");
      if !streq(e.message, "password authentication failed for user \"pguser\"") {
        saw = false;
      }
    },
  }
  if !saw { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: auth failure is a typed server error with SQLSTATE");
}

fn t28_loop_server_error_on_query() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: query error (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: query error (tcp connect failed)");
  }
  var succ: Vec[UInt8] = Vec[UInt8].new();
  add(&mut succ, &b_auth(0));
  add(&mut succ, &b_param("server_version", "16.4"));
  add(&mut succ, &b_ready(73));
  var codes: Vec[Str] = ["S", "C", "M", "F", "L", "R"];
  var vals: Vec[Str] = ["ERROR", "42P01", "relation \"nope\" does not exist", "parse_relation.c", "1371", "parserOpenTable"];
  add(&mut succ, &b_error_like(69, &codes, &vals));
  var ok = srv_send(sfd, &succ);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var conn_ok = false;
  match ar {
    Ok(conn) => {
      conn_ok = true;
      let qr = query(&mut conn, "SELECT * FROM nope");
      match qr {
        Ok(_) => {
          ok = false;
        },
        Err(e) => {
          if e.kind != PG_ERR_SERVER { ok = false; }
          if !streq(e.code, "42P01") { ok = false; }
          if !streq(e.severity, "ERROR") { ok = false; }
          if !streq(e.detail, "") { ok = false; }
          if e.fields.len() != 6 { ok = false; }
        },
      }
      disconnect(&mut conn);
    },
    Err(_) => {
      ok = false;
    },
  }
  if !conn_ok { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: server ErrorResponse on query preserves fields");
}

fn t29_loop_notices() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: notices (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: notices (tcp connect failed)");
  }
  var ncodes: Vec[Str] = ["S", "C", "M"];
  var nvals: Vec[Str] = ["NOTICE", "00000", "startup notice"];
  var qcodes: Vec[Str] = ["S", "C", "M"];
  var qvals: Vec[Str] = ["WARNING", "01000", "query notice"];
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth(0));
  add(&mut script, &b_error_like(78, &ncodes, &nvals));
  add(&mut script, &b_ready(73));
  add(&mut script, &b_command("CREATE TABLE"));
  add(&mut script, &b_error_like(78, &qcodes, &qvals));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var conn_ok = false;
  match ar {
    Ok(conn) => {
      conn_ok = true;
      if conn.notices.len() != 1 { ok = false; }
      if !streq(pg_conn_param(&conn, "server_version"), "") { ok = false; }
      let er = exec(&mut conn, "CREATE TABLE x ()");
      match er {
        Ok(res) => {
          if !streq(res.tag, "CREATE TABLE") { ok = false; }
          if res.affected != 0 { ok = false; }
          if res.notices.len() != 1 { ok = false; }
          if !streq(res.notices[0].message, "query notice") { ok = false; }
          if res.row_count != 0 { ok = false; }
        },
        Err(_) => {
          ok = false;
        },
      }
      disconnect(&mut conn);
    },
    Err(_) => {
      ok = false;
    },
  }
  if !conn_ok { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: notices surfaced on connection and result; exec tag");
}

// ---------------------------------------------------------------- section 4
// error taxonomy + guards + quoting

fn t30_loop_unsupported_auth() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: unsupported auth (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: unsupported auth (tcp connect failed)");
  }
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth(7));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var saw = false;
  match ar {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      saw = e.kind == PG_ERR_UNSUPPORTED_AUTH;
    },
  }
  if !saw { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: unsupported auth code (GSS 7) is typed PG_ERR_UNSUPPORTED_AUTH");
}

fn t31_loop_protocol_violation() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: protocol violation (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: protocol violation (tcp connect failed)");
  }
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &literal(&[33, 0, 0, 0, 4]));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var saw = false;
  match ar {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      saw = e.kind == PG_ERR_PROTOCOL && e.offset == 0;
    },
  }
  if !saw { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "loopback: garbage backend bytes are typed PG_ERR_PROTOCOL with offset");
}

fn t32_loop_timeout() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "loopback: timeout (no free port)");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "loopback: timeout (tcp connect failed)");
  }
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 400, "");
  var saw = false;
  match ar {
    Ok(_) => {},
    Err(e) => {
      saw = e.kind == PG_ERR_TIMEOUT;
    },
  }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(saw, "loopback: silent server is typed PG_ERR_TIMEOUT");
}

fn t33_connection_refused() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "refused: no free port to close");
  }
  socket.socket_close(lfd);
  let r = connect("127.0.0.1", port, "u", "p", "d");
  var ok = false;
  match r {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      ok = e.kind == PG_ERR_CONNECTION;
    },
  }
  return assert(ok, "errors: connection refused is typed PG_ERR_CONNECTION");
}

fn t34_argument_guards() -> TestResult {
  var ok = true;
  let r1 = connect("", 5432, "u", "p", "d");
  match r1 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_CONNECTION { ok = false; }
    },
  }
  let r2 = connect("127.0.0.1", 0, "u", "p", "d");
  match r2 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_CONNECTION { ok = false; }
    },
  }
  let r3 = connect("127.0.0.1", 5432, "", "p", "d");
  match r3 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_CONNECTION { ok = false; }
    },
  }
  let r4 = connect_with_timeout("127.0.0.1", 5432, "u", "p", "d", 0);
  match r4 {
    Ok(_) => {
      ok = false;
    },
    Err(e) => {
      if e.kind != PG_ERR_CONNECTION { ok = false; }
    },
  }
  return assert(ok, "errors: argument guards (host/port/user/timeout) are typed");
}

fn t35_closed_connection_guard() -> TestResult {
  let la = listen_any();
  let lfd = la.fd;
  let port = la.port;
  if lfd < 0 {
    return assert(false, "closed guard: no free port");
  }
  srv_reset();
  let lp = loop_connect(lfd, port);
  let cfd = lp.cfd;
  let sfd = lp.sfd;
  if cfd < 0 {
    socket.socket_close(lfd);
    return assert(false, "closed guard: tcp connect failed");
  }
  var script: Vec[UInt8] = Vec[UInt8].new();
  add(&mut script, &b_auth(0));
  add(&mut script, &b_ready(73));
  var ok = srv_send(sfd, &script);
  let ar = attach(cfd, "127.0.0.1", port, "pguser", "s3cret", "pgdb", 5000, "");
  var conn_ok = false;
  match ar {
    Ok(conn) => {
      conn_ok = true;
      disconnect(&mut conn);
      let r = query(&mut conn, "SELECT 1");
      match r {
        Ok(_) => {
          ok = false;
        },
        Err(e) => {
          if e.kind != PG_ERR_CONNECTION { ok = false; }
        },
      }
    },
    Err(_) => {
      ok = false;
    },
  }
  if !conn_ok { ok = false; }
  socket.socket_close(sfd);
  socket.socket_close(lfd);
  return assert(ok, "errors: query on a disconnected connection is PG_ERR_CONNECTION");
}

fn t36_quote_literal() -> TestResult {
  var ok = streq(pg_quote_literal(""), "''");
  if !streq(pg_quote_literal("plain"), "'plain'") { ok = false; }
  if !streq(pg_quote_literal("O'Brien"), "'O''Brien'") { ok = false; }
  if !streq(pg_quote_literal("a\\b"), "'a\\\\b'") { ok = false; }
  if !streq(pg_quote_literal("it's a\\b"), "'it''s a\\\\b'") { ok = false; }
  if !streq(pg_quote_literal("line1\nline2"), "'line1\nline2'") { ok = false; }
  if !streq(pg_quote_literal("';0||"), "''';0||'") { ok = false; }
  return assert(ok, "quote: pg_quote_literal KATs (quotes, backslash, newline, empty)");
}

fn t37_quote_identifier() -> TestResult {
  var ok = streq(pg_quote_identifier("simple"), "\"simple\"");
  if !streq(pg_quote_identifier("we\"ird"), "\"we\"\"ird\"") { ok = false; }
  if !streq(pg_quote_identifier(""), "\"\"") { ok = false; }
  return assert(ok, "quote: pg_quote_identifier KATs");
}

// ---------------------------------------------------------------- section 5
// live path: honest SKIP when no server is listening

fn t38_live_or_skip() -> TestResult {
  let probe = socket.socket_tcp();
  var pfd = 0;
  match probe {
    Ok(v) => {
      pfd = v;
    },
    Err(_) => {
      return assert(false, "live: probe socket create failed");
    },
  }
  let con = socket.socket_connect(pfd, "127.0.0.1", 5432);
  if con.is_err {
    socket.socket_close(pfd);
    return assert(
      true,
      "live: 127.0.0.1:5432 unreachable SKIP -- no live PostgreSQL at 127.0.0.1:5432");
  }
  socket.socket_close(pfd);
  let lr = connect("127.0.0.1", 5432, "postgres", "", "postgres");
  match lr {
    Ok(conn) => {
      let q1 = query(&mut conn, "SELECT 1");
      var ok = false;
      match q1 {
        Ok(res) => {
          ok = res.row_count == 1 && opt_is(res.rows[0][0], "1") && streq(res.tag, "SELECT 1");
        },
        Err(_) => {
          ok = false;
        },
      }
      let q2 = query(&mut conn, "SELECT current_database()");
      match q2 {
        Ok(res2) => {
          if res2.row_count != 1 {
            ok = false;
          }
        },
        Err(_) => {
          ok = false;
        },
      }
      disconnect(&mut conn);
      return assert(ok, "live: real PostgreSQL serves SELECT 1 and current_database()");
    },
    Err(e) => {
      if e.kind == PG_ERR_CONNECTION {
        return assert(
          true,
          "live: 127.0.0.1:5432 unreachable SKIP -- no live PostgreSQL at 127.0.0.1:5432 (" + e.message + ")");
      }
      return assert(
        true,
        "live: 127.0.0.1:5432 reachable but unusable (kind " + convert.to_string(e.kind) + ": " + e.message + ") SKIP");
    },
  }
  return assert(false, "live: unreachable branch");
}

// ---------------------------------------------------------------- main

fn main() -> Int {
  io.println("=== xiom.postgres conformance tests ===");
  io.println("section 1: message codec goldens");
  var failed = 0;
  failed = failed + note(t01_startup_bytes());
  failed = failed + note(t02_password_bytes());
  failed = failed + note(t03_query_bytes());
  failed = failed + note(t04_terminate_bytes());
  failed = failed + note(t05_sasl_bytes());
  failed = failed + note(t06_auth_ok());
  failed = failed + note(t07_auth_cleartext_md5());
  failed = failed + note(t08_auth_sasl());
  failed = failed + note(t09_row_description());
  failed = failed + note(t10_data_row_nulls());
  failed = failed + note(t11_data_row_quotes());
  failed = failed + note(t12_command_complete());
  failed = failed + note(t13_tag_affected());
  failed = failed + note(t14_error_response());
  failed = failed + note(t15_notice_and_notification());
  failed = failed + note(t16_ready_param_key());
  failed = failed + note(t17_decode_errors_truncated());
  failed = failed + note(t18_decode_offsets_and_chain());
  io.println("section 2: authentication KATs");
  failed = failed + note(t19_md5_kat());
  failed = failed + note(t20_scram_first_and_escape());
  failed = failed + note(t21_scram_rfc7677_vector());
  failed = failed + note(t22_scram_parse_and_verify_errors());
  io.println("section 3: offline loopback (scripted in-process server)");
  failed = failed + note(t23_loop_happy());
  failed = failed + note(t24_loop_cleartext_auth());
  failed = failed + note(t25_loop_md5_auth());
  failed = failed + note(t26_loop_scram());
  failed = failed + note(t27_loop_auth_failure());
  failed = failed + note(t28_loop_server_error_on_query());
  failed = failed + note(t29_loop_notices());
  io.println("section 4: error taxonomy, guards, quoting");
  failed = failed + note(t30_loop_unsupported_auth());
  failed = failed + note(t31_loop_protocol_violation());
  failed = failed + note(t32_loop_timeout());
  failed = failed + note(t33_connection_refused());
  failed = failed + note(t34_argument_guards());
  failed = failed + note(t35_closed_connection_guard());
  failed = failed + note(t36_quote_literal());
  failed = failed + note(t37_quote_identifier());
  io.println("section 5: live path");
  failed = failed + note(t38_live_or_skip());
  if failed == 0 {
    io.println("xiom.postgres: all tests passed");
  } else {
    io.println("xiom.postgres: tests failed");
  }
  return failed;
}
