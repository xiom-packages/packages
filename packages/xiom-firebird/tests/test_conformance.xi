// XIOM -- xiom.firebird conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.firebird structural codec
// against the documented canonical-XDR subset, with byte-exact vectors and
// round trips.
//
// The wire constants are pinned to the Firebird master sources
// (src/remote/protocol.h opcodes, src/remote/protocol.cpp field layouts);
// every expected hex string is hand-assembled from the documented encoding.

module firebird_tests
use xiom.io; use xiom.test; use xiom.firebird;
use xiom.encoding.hex; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Lowercase hex of a byte vector.
fn hexs(v: &Vec[UInt8]) -> Str {
  return hex.hex_encode(v);
}

// Bytes decoded from a hex string (empty on a malformed literal).
fn bytes_of(h: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(h);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// True when an emitter fails with exactly `want`.
fn emit_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when a connect parse fails with exactly `want`.
fn connect_err_is(r: Result[FbConnect, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when an accept parse fails with exactly `want`.
fn accept_err_is(r: Result[FbAccept, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when an attach parse fails with exactly `want`.
fn attach_err_is(r: Result[FbAttach, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when a data parse fails with exactly `want`.
fn data_err_is(r: Result[FbData, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when an object parse fails with exactly `want`.
fn object_err_is(r: Result[FbObject, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when a transaction parse fails with exactly `want`.
fn tran_err_is(r: Result[FbTransaction, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Structural equality of two connect blocks.
fn connect_eq(a: &FbConnect, b: &FbConnect) -> Bool {
  if a.operation != b.operation { return false; }
  if a.cversion != b.cversion { return false; }
  if a.client_arch != b.client_arch { return false; }
  if !streq(a.file, b.file) { return false; }
  if !streq(a.user_id, b.user_id) { return false; }
  if a.protocols.len() != b.protocols.len() { return false; }
  if a.archs.len() != b.archs.len() { return false; }
  if a.weights.len() != b.weights.len() { return false; }
  var i = 0;
  while i < a.protocols.len() {
    let pa: Int = a.protocols[i];
    let pb: Int = b.protocols[i];
    if pa != pb { return false; }
    i = i + 1;
  }
  i = 0;
  while i < a.archs.len() {
    let aa: Int = a.archs[i];
    let ab: Int = b.archs[i];
    if aa != ab { return false; }
    i = i + 1;
  }
  i = 0;
  while i < a.weights.len() {
    let wa: Int = a.weights[i];
    let wb: Int = b.weights[i];
    if wa != wb { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let ping = bytes_of("0000005d");
  let empty = Vec[UInt8].new();
  var ok = firebird_packet_opcode(&ping) == 93;
  if firebird_packet_opcode(&empty) != -1 { ok = false; }
  let short = bytes_of("000000");
  if firebird_packet_opcode(&short) != -1 { ok = false; }
  return assert(ok, "the packet opcode is the first big-endian word");
}

fn t2() -> TestResult {
  var ok = firebird_opcode_of("connect") == 1;
  if firebird_opcode_of("ping") != 93 { ok = false; }
  if firebird_opcode_of("attach") != 19 { ok = false; }
  if firebird_opcode_of("nope") != -1 { ok = false; }
  if !streq(firebird_opcode_name(19), "attach") { ok = false; }
  if !streq(firebird_opcode_name(5), "") { ok = false; }
  if !firebird_opcode_known(1) { ok = false; }
  if firebird_opcode_known(5) { ok = false; }
  if firebird_opcode_count() != 75 { ok = false; }
  return assert(ok, "the opcode registry matches the pinned upstream values");
}

fn t3() -> TestResult {
  var ok = false;
  let ping = firebird_empty_packet_emit(93);
  match ping {
    Ok(v) => { ok = streq(hexs(&v), "0000005d"); },
    Err(_) => { ok = false; },
  }
  let dummy = firebird_empty_packet_emit(71);
  match dummy {
    Ok(v) => { if !streq(hexs(&v), "00000047") { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !emit_err_is(firebird_empty_packet_emit(25), "firebird: not a fieldless opcode 25") { ok = false; }
  return assert(ok, "fieldless packets are exactly one opcode word");
}

fn t4() -> TestResult {
  let c = firebird_connect_new();
  let r = firebird_connect_emit(&c);
  var ok = false;
  match r {
    Ok(v) => { ok = streq(hexs(&v), "00000001000000000000000300000001000000000000000000000000"); },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a fresh connect block encodes the documented default header");
}

fn t5() -> TestResult {
  var c = firebird_connect_new();
  c.file = "test.fdb";
  firebird_connect_add_version(&mut c, 32783, 1, 0, 5, 1);
  let r = firebird_connect_emit(&c);
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(hexs(&v), "0000000100000000000000030000000100000008746573742e66646200000001000000000000800f00000001000000000000000500000001");
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the connect block encodes file, count and one version entry");
}

fn t6() -> TestResult {
  var c = firebird_connect_new();
  c.file = "db.fdb";
  c.user_id = "SYSDBA";
  firebird_connect_add_version(&mut c, 32783, 1, 0, 5, 1);
  firebird_connect_add_version(&mut c, 32782, 1, 0, 5, 2);
  let er = firebird_connect_emit(&c);
  var ok = false;
  match er {
    Ok(bytes) => {
      let pr = firebird_connect_parse(bytes);
      match pr {
        Ok(p) => {
          ok = connect_eq(&c, &p);
          if !streq(p.user_id, "SYSDBA") { ok = false; }
          if p.protocols.len() != 2 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "connect blocks round-trip through emit and parse");
}

fn t7() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = connect_err_is(firebird_connect_parse(empty), "firebird: truncated packet");
  if !connect_err_is(firebird_connect_parse(bytes_of("000000030000800f0000000100000005")), "firebird: unexpected opcode 3") { ok = false; }
  if !connect_err_is(firebird_connect_parse(bytes_of("00000001000000000000000300000001000000000000000c00000000")), "firebird: too many connect versions 12") { ok = false; }
  return assert(ok, "connect parse rejects short packets, wrong opcodes and oversized counts");
}

fn t8() -> TestResult {
  var bad_cv = firebird_connect_new();
  bad_cv.cversion = 70000;
  var ok = emit_err_is(firebird_connect_emit(&bad_cv), "firebird: field out of range 70000");
  var mis = firebird_connect_new();
  mis.protocols.push(1);
  if !emit_err_is(firebird_connect_emit(&mis), "firebird: misaligned connect versions") { ok = false; }
  var many = firebird_connect_new();
  var i = 0;
  while i < 12 {
    firebird_connect_add_version(&mut many, 1, 1, 0, 5, 1);
    i = i + 1;
  }
  if !emit_err_is(firebird_connect_emit(&many), "firebird: too many connect versions 12") { ok = false; }
  return assert(ok, "connect emit validates widths, alignment and the version cap");
}

fn t9() -> TestResult {
  let r = firebird_accept_emit(32783, 1, 5);
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(hexs(&v), "000000030000800f0000000100000005");
      let pr = firebird_accept_parse(v);
      match pr {
        Ok(a) => {
          if a.version != 32783 { ok = false; }
          if a.architecture != 1 { ok = false; }
          if a.ptype != 5 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  if !accept_err_is(firebird_accept_parse(bytes_of("00000001000000000000000300000001")), "firebird: unexpected opcode 1") { ok = false; }
  return assert(ok, "accept blocks round-trip with their three fields");
}

fn t10() -> TestResult {
  let r = firebird_attach_emit(19, 7, "abc", "");
  var ok = false;
  match r {
    Ok(v) => { ok = streq(hexs(&v), "0000001300000007000000036162630000000000"); },
    Err(_) => { ok = false; },
  }
  return assert(ok, "counted strings pad to the 4-byte boundary");
}

fn t11() -> TestResult {
  let r = firebird_attach_emit(20, 42, "db.fdb", "x");
  var ok = false;
  match r {
    Ok(bytes) => {
      let pr = firebird_attach_parse(bytes);
      match pr {
        Ok(a) => {
          ok = a.op == 20;
          if a.database != 42 { ok = false; }
          if !streq(a.file, "db.fdb") { ok = false; }
          if !streq(a.dpb, "x") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let svc = firebird_attach_emit(82, 1, "f", "");
  match svc {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  return assert(ok, "attach blocks round-trip and accept service_attach");
}

fn t12() -> TestResult {
  var ok = emit_err_is(firebird_attach_emit(30, 1, "f", ""), "firebird: not an attach opcode 30");
  if !attach_err_is(firebird_attach_parse(bytes_of("0000001e00000001")), "firebird: not an attach opcode 30") { ok = false; }
  return assert(ok, "attach blocks reject non-attach opcodes");
}

fn t13() -> TestResult {
  let r = firebird_data_emit(25, 1, 2, 3, 4, 5);
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(hexs(&v), "000000190000000100000002000000030000000400000005");
      let pr = firebird_data_parse(v);
      match pr {
        Ok(d) => {
          if d.op != 25 { ok = false; }
          if d.request != 1 { ok = false; }
          if d.incarnation != 2 { ok = false; }
          if d.transaction != 3 { ok = false; }
          if d.message_number != 4 { ok = false; }
          if d.messages != 5 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "data blocks encode five words after the opcode");
}

fn t14() -> TestResult {
  var ops = Vec[Int].new();
  ops.push(23);
  ops.push(24);
  ops.push(25);
  ops.push(26);
  ops.push(73);
  ops.push(74);
  var ok = true;
  var i = 0;
  while i < ops.len() {
    let op: Int = ops[i];
    let r = firebird_data_emit(op, 1, 1, 1, 1, 1);
    match r {
      Ok(_) => {},
      Err(_) => { ok = false; },
    }
    i = i + 1;
  }
  if !emit_err_is(firebird_data_emit(30, 1, 1, 1, 1, 1), "firebird: not a data opcode 30") { ok = false; }
  if !data_err_is(firebird_data_parse(bytes_of("0000001e00000001")), "firebird: not a data opcode 30") { ok = false; }
  return assert(ok, "only the six start/send/receive opcodes carry data blocks");
}

fn t15() -> TestResult {
  let r = firebird_object_emit(30, 7);
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(hexs(&v), "0000001e00000007");
      let pr = firebird_object_parse(v);
      match pr {
        Ok(o) => {
          if o.op != 30 { ok = false; }
          if o.object != 7 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  var ops = Vec[Int].new();
  ops.push(21);
  ops.push(28);
  ops.push(30);
  ops.push(31);
  ops.push(32);
  ops.push(38);
  ops.push(39);
  ops.push(50);
  ops.push(62);
  ops.push(81);
  ops.push(83);
  ops.push(86);
  ops.push(102);
  ops.push(109);
  var i = 0;
  while i < ops.len() {
    let op: Int = ops[i];
    let e = firebird_object_emit(op, 1);
    match e {
      Ok(_) => {},
      Err(_) => { ok = false; },
    }
    i = i + 1;
  }
  return assert(ok, "single-object blocks cover the release-opcode family");
}

fn t16() -> TestResult {
  var ok = emit_err_is(firebird_object_emit(25, 1), "firebird: not a release opcode 25");
  if !object_err_is(firebird_object_parse(bytes_of("0000001900000001")), "firebird: not a release opcode 25") { ok = false; }
  return assert(ok, "single-object blocks reject non-release opcodes");
}

fn t17() -> TestResult {
  let r = firebird_transaction_emit(29, 9, "tpb");
  var ok = false;
  match r {
    Ok(v) => {
      ok = streq(hexs(&v), "0000001d000000090000000374706200");
      let pr = firebird_transaction_parse(v);
      match pr {
        Ok(t) => {
          if t.op != 29 { ok = false; }
          if t.database != 9 { ok = false; }
          if !streq(t.tpb, "tpb") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  let rec = firebird_transaction_emit(33, 1, "");
  match rec {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  if !emit_err_is(firebird_transaction_emit(30, 1, ""), "firebird: not a transaction opcode 30") { ok = false; }
  if !tran_err_is(firebird_transaction_parse(bytes_of("0000001e00000001")), "firebird: not a transaction opcode 30") { ok = false; }
  return assert(ok, "transaction blocks round-trip and accept reconnect");
}

fn t18() -> TestResult {
  let empty = Vec[UInt8].new();
  let tiny = bytes_of("0000");
  var ok = connect_err_is(firebird_connect_parse(empty), "firebird: truncated packet");
  if !accept_err_is(firebird_accept_parse(tiny), "firebird: truncated packet") { ok = false; }
  if !attach_err_is(firebird_attach_parse(empty), "firebird: truncated packet") { ok = false; }
  if !data_err_is(firebird_data_parse(tiny), "firebird: truncated packet") { ok = false; }
  if !object_err_is(firebird_object_parse(empty), "firebird: truncated packet") { ok = false; }
  if !tran_err_is(firebird_transaction_parse(tiny), "firebird: truncated packet") { ok = false; }
  return assert(ok, "short packets are truncated, never misread");
}

fn t19() -> TestResult {
  var ok = attach_err_is(firebird_attach_parse(bytes_of("000000130000000700000064")), "firebird: truncated packet");
  if !tran_err_is(firebird_transaction_parse(bytes_of("0000001d0000000900000064")), "firebird: truncated packet") { ok = false; }
  var c = firebird_connect_new();
  c.file = "abc";
  let er = firebird_connect_emit(&c);
  match er {
    Ok(bytes) => {
      // cut the packet in the middle of the file string
      var cut = Vec[UInt8].new();
      var i = 0;
      while i < bytes.len() - 2 {
        let b: UInt8 = bytes[i];
        cut.push(b);
        i = i + 1;
      }
      if !connect_err_is(firebird_connect_parse(cut), "firebird: truncated packet") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "counted strings that run past the packet are truncated");
}

fn t20() -> TestResult {
  var c = firebird_connect_new();
  c.file = "x";
  let er = firebird_connect_emit(&c);
  var ok = false;
  match er {
    Ok(bytes) => {
      var padded = Vec[UInt8].new();
      var i = 0;
      while i < bytes.len() {
        let b: UInt8 = bytes[i];
        padded.push(b);
        i = i + 1;
      }
      padded.push(222u8);
      padded.push(173u8);
      padded.push(190u8);
      padded.push(239u8);
      let pr = firebird_connect_parse(padded);
      match pr {
        Ok(p) => { ok = streq(p.file, "x"); },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "bytes after a known block are ignored");
}

fn t21() -> TestResult {
  var ok = emit_err_is(firebird_attach_emit(19, -1, "f", ""), "firebird: field out of range -1");
  if !emit_err_is(firebird_accept_emit(65536, 1, 5), "firebird: field out of range 65536") { ok = false; }
  if !emit_err_is(firebird_object_emit(30, -5), "firebird: field out of range -5") { ok = false; }
  if !emit_err_is(firebird_data_emit(25, 1, 1, 1, 1, 4294967296), "firebird: field out of range 4294967296") { ok = false; }
  return assert(ok, "emitters reject fields beyond their wire width");
}

fn t22() -> TestResult {
  var ok = true;
  var c = 0;
  while c < 256 {
    if firebird_opcode_known(c) {
      let n = firebird_opcode_name(c);
      if n.len() == 0 { ok = false; }
      if firebird_opcode_of(n) != c { ok = false; }
    }
    c = c + 1;
  }
  if firebird_opcode_known(0) { ok = false; }
  if firebird_opcode_known(200) { ok = false; }
  return assert(ok, "every registered opcode round-trips through name and lookup");
}

fn main() -> Int {
  io.println("=== xiom.firebird conformance tests ===");
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
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.firebird: all tests passed");
  } else {
    io.println("xiom.firebird: tests failed");
  }
  return failed;
}
