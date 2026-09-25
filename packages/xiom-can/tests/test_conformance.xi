// XIOM -- xiom.can conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API against the xiom.can SPEC.md: the exact 16-byte
// container for standard and extended data frames, remote frames and the
// identifier/DLC boundaries; hand-built containers decoded field by field;
// the strict decode errors (truncation, error-frame flag, standard
// identifier overflow, DLC range, reserved bytes, padding, RTR data);
// validate/constructor errors in the documented order; the equality helper;
// can_encode_into atomicity; every accessor; and byte-exact
// encode -> decode -> encode round-trips.
//
// Str values in the error checks go through xiom.string.compare.str_compare
// (BUG 17: `==` on a Str read from a Vec lowers to a pointer comparison).

module can_tests
use xiom.io; use xiom.test;
use xiom.can;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string (empty on malformed input, so the test
// then fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn empty() -> Vec[UInt8] {
  return Vec[UInt8].new();
}

fn err_frame_is(r: Result[CanFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// One 16-byte container from raw parts: four ID-word bytes, the DLC byte,
// three zero reserved bytes and `data` zero-padded to eight bytes.
fn seg(b0: Int, b1: Int, b2: Int, b3: Int, dlc: Int, data: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(b0 as UInt8);
  v.push(b1 as UInt8);
  v.push(b2 as UInt8);
  v.push(b3 as UInt8);
  v.push(dlc as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  var i = 0;
  while i < 8 {
    if i < data.len() {
      v.push(data[i]);
    } else {
      v.push(0 as UInt8);
    }
    i = i + 1;
  }
  return v;
}

// Copy of `v` with byte `pos` set to `val`.
fn with_byte(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(val as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Prefix of a byte vector, for truncation tests.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Concatenation of two byte vectors, for the trailing-bytes test.
fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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

// Data frame for tests. On constructor failure this returns an impossible
// frame (id -1, dlc -1) so the checks in the calling test fail.
fn df(id: Int, extended: Bool, data: Vec[UInt8]) -> CanFrame {
  let r = can_data_frame(id, extended, &data);
  match r {
    Ok(f) => { return f; },
    Err(_) => {},
  }
  let z = empty();
  return CanFrame{ id: -1; extended: false; rtr: false; dlc: -1; data: z };
}

// Remote frame for tests; same failure sentinel as df.
fn rf(id: Int, extended: Bool, dlc: Int) -> CanFrame {
  let r = can_remote_frame(id, extended, dlc);
  match r {
    Ok(f) => { return f; },
    Err(_) => {},
  }
  let z = empty();
  return CanFrame{ id: -1; extended: false; rtr: false; dlc: -1; data: z };
}

// Field pin.
fn shape_is(f: &CanFrame, id: Int, extended: Bool, rtr: Bool, dlc: Int) -> Bool {
  if f.id != id { return false; }
  if f.extended != extended { return false; }
  if f.rtr != rtr { return false; }
  if f.dlc != dlc { return false; }
  return true;
}

// Payload pin.
fn payload_is(f: &CanFrame, want: Vec[UInt8]) -> Bool {
  let d: Vec[UInt8] = f.data;
  return bytes_equal(d, want);
}

// encode helper: frame -> bytes, with an empty fallback (the calling test
// fails on the byte comparison).
fn enc(f: &CanFrame) -> Vec[UInt8] {
  let r = can_encode(f);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// Full round-trip check: encode, decode, compare fields, re-encode and
// compare bytes.
fn round_trip_ok(f: &CanFrame) -> Bool {
  let r1 = can_encode(f);
  if !r1.is_ok {
    return false;
  }
  let e1: Vec[UInt8] = r1.value;
  let d1 = can_decode(&e1);
  if !d1.is_ok {
    return false;
  }
  let g: CanFrame = d1.value;
  if !can_equal(f, &g) {
    return false;
  }
  let r2 = can_encode(&g);
  if !r2.is_ok {
    return false;
  }
  let e2: Vec[UInt8] = r2.value;
  return bytes_equal(e1, e2);
}

// decode -> encode must reproduce the container byte-for-byte.
fn recodes_to(bytes: Vec[UInt8], want: Vec[UInt8]) -> Bool {
  let r = can_decode(&bytes);
  if !r.is_ok {
    return false;
  }
  let f: CanFrame = r.value;
  let e = can_encode(&f);
  if !e.is_ok {
    return false;
  }
  let out: Vec[UInt8] = e.value;
  return bytes_equal(out, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let f = df(291, false, hb("dead"));
  var ok = shape_is(&f, 291, false, false, 2);
  if !payload_is(&f, hb("dead")) { ok = false; }
  if !bytes_equal(enc(&f), hb("0000012302000000dead000000000000")) { ok = false; }
  return assert(ok, "standard data frame encodes to the pinned 16 bytes");
}

fn t2() -> TestResult {
  let f = df(305419896, true, hb("0102030405060708"));
  var ok = shape_is(&f, 305419896, true, false, 8);
  if !payload_is(&f, hb("0102030405060708")) { ok = false; }
  if !bytes_equal(enc(&f), hb("92345678080000000102030405060708")) { ok = false; }
  return assert(ok, "extended data frame with a full payload encodes exactly");
}

fn t3() -> TestResult {
  let a = rf(2047, false, 8);
  let b = rf(536870911, true, 0);
  var ok = shape_is(&a, 2047, false, true, 8);
  if !shape_is(&b, 536870911, true, true, 0) { ok = false; }
  if !bytes_equal(enc(&a), hb("400007ff080000000000000000000000")) { ok = false; }
  if !bytes_equal(enc(&b), hb("dfffffff000000000000000000000000")) { ok = false; }
  return assert(ok, "standard and extended remote frames encode exactly");
}

fn t4() -> TestResult {
  let a = df(0, false, empty());
  let b = df(2047, false, empty());
  let c = df(536870911, true, empty());
  var ok = shape_is(&a, 0, false, false, 0);
  if !shape_is(&b, 2047, false, false, 0) { ok = false; }
  if !shape_is(&c, 536870911, true, false, 0) { ok = false; }
  if !bytes_equal(enc(&a), hb("00000000000000000000000000000000")) { ok = false; }
  if !bytes_equal(enc(&b), hb("000007ff000000000000000000000000")) { ok = false; }
  if !bytes_equal(enc(&c), hb("9fffffff000000000000000000000000")) { ok = false; }
  return assert(ok, "identifier and DLC boundaries encode to pinned bytes");
}

fn t5() -> TestResult {
  let a = hb("0000012302000000dead000000000000");
  let ra = can_decode(&a);
  var ok = ra.is_ok;
  if ok {
    let f: CanFrame = ra.value;
    if !shape_is(&f, 291, false, false, 2) { ok = false; }
    if !payload_is(&f, hb("dead")) { ok = false; }
  }
  let b = hb("92345678080000000102030405060708");
  let rb = can_decode(&b);
  if !rb.is_ok { ok = false; } else {
    let g: CanFrame = rb.value;
    if !shape_is(&g, 305419896, true, false, 8) { ok = false; }
    if !payload_is(&g, hb("0102030405060708")) { ok = false; }
  }
  return assert(ok, "hand-built data containers decode field by field");
}

fn t6() -> TestResult {
  let a = hb("400007ff080000000000000000000000");
  let ra = can_decode(&a);
  var ok = ra.is_ok;
  if ok {
    let f: CanFrame = ra.value;
    if !shape_is(&f, 2047, false, true, 8) { ok = false; }
    if can_payload_len(&f) != 0 { ok = false; }
  }
  let b = hb("dfffffff000000000000000000000000");
  let rb = can_decode(&b);
  if !rb.is_ok { ok = false; } else {
    let g: CanFrame = rb.value;
    if !shape_is(&g, 536870911, true, true, 0) { ok = false; }
    if !payload_is(&g, empty()) { ok = false; }
  }
  return assert(ok, "remote frames decode with an empty payload and kept DLC");
}

fn t7() -> TestResult {
  let base = seg(0, 0, 1, 35, 2, hb("dead"));
  var ok = can_decode(&base).is_ok;
  let pad = with_byte(base, 10, 238);
  if !err_frame_is(can_decode(&pad), "can: nonzero padding byte") { ok = false; }
  let zero = seg(0, 0, 0, 0, 0, empty());
  let pad0 = with_byte(zero, 8, 1);
  if !err_frame_is(can_decode(&pad0), "can: nonzero padding byte") { ok = false; }
  let rtrframe = seg(64, 0, 7, 255, 8, empty());
  if !can_decode(&rtrframe).is_ok { ok = false; }
  let rtr8 = with_byte(rtrframe, 8, 1);
  if !err_frame_is(can_decode(&rtr8), "can: nonzero rtr data byte") { ok = false; }
  let rtr15 = with_byte(rtrframe, 15, 255);
  if !err_frame_is(can_decode(&rtr15), "can: nonzero rtr data byte") { ok = false; }
  return assert(ok, "nonzero padding beyond DLC and RTR data bytes are Err");
}

fn t8() -> TestResult {
  let d9 = seg(0, 0, 1, 35, 9, empty());
  var ok = err_frame_is(can_decode(&d9), "can: invalid dlc");
  let d15 = seg(0, 0, 1, 35, 15, empty());
  if !err_frame_is(can_decode(&d15), "can: invalid dlc") { ok = false; }
  let d16 = seg(0, 0, 1, 35, 16, empty());
  if !err_frame_is(can_decode(&d16), "can: invalid dlc") { ok = false; }
  let d255 = seg(0, 0, 1, 35, 255, empty());
  if !err_frame_is(can_decode(&d255), "can: invalid dlc") { ok = false; }
  let full = seg(0, 0, 1, 35, 8, empty());
  let rf8 = can_decode(&full);
  if !rf8.is_ok { ok = false; } else {
    let f: CanFrame = rf8.value;
    if !shape_is(&f, 291, false, false, 8) { ok = false; }
    if can_payload_len(&f) != 8 { ok = false; }
  }
  return assert(ok, "DLC bytes above 8 are Err; DLC 8 with zero data is valid");
}

fn t9() -> TestResult {
  let base = seg(0, 0, 1, 35, 2, hb("dead"));
  var ok = can_decode(&base).is_ok;
  let r5 = with_byte(base, 5, 1);
  if !err_frame_is(can_decode(&r5), "can: nonzero reserved byte") { ok = false; }
  let r6 = with_byte(base, 6, 128);
  if !err_frame_is(can_decode(&r6), "can: nonzero reserved byte") { ok = false; }
  let r7 = with_byte(base, 7, 255);
  if !err_frame_is(can_decode(&r7), "can: nonzero reserved byte") { ok = false; }
  return assert(ok, "nonzero reserved bytes 5..7 are Err");
}

fn t10() -> TestResult {
  let full = hb("0000012302000000dead000000000000");
  var ok = true;
  var n = 0;
  while n < 16 {
    let cut = prefix(full, n);
    if !err_frame_is(can_decode(&cut), "can: truncated frame") { ok = false; }
    n = n + 1;
  }
  let exact = prefix(full, 16);
  if !can_decode(&exact).is_ok { ok = false; }
  return assert(ok, "every buffer shorter than 16 bytes is Err; 16 is not");
}

fn t11() -> TestResult {
  let v0 = seg(0, 0, 0, 0, 0, empty());
  var ok = can_decode(&v0).is_ok;
  let vext0 = seg(128, 0, 0, 0, 0, empty());
  if !can_decode(&vext0).is_ok { ok = false; }
  let vmax = seg(159, 255, 255, 255, 0, empty());
  if !can_decode(&vmax).is_ok { ok = false; }
  let s1 = seg(0, 0, 8, 0, 0, empty());
  if !err_frame_is(can_decode(&s1), "can: identifier exceeds standard range") { ok = false; }
  let s2 = seg(0, 1, 0, 0, 0, empty());
  if !err_frame_is(can_decode(&s2), "can: identifier exceeds standard range") { ok = false; }
  let s3 = seg(31, 255, 255, 255, 0, empty());
  if !err_frame_is(can_decode(&s3), "can: identifier exceeds standard range") { ok = false; }
  let e1 = seg(32, 0, 0, 0, 0, empty());
  if !err_frame_is(can_decode(&e1), "can: error frame flag set") { ok = false; }
  let e2 = seg(96, 0, 0, 0, 0, empty());
  if !err_frame_is(can_decode(&e2), "can: error frame flag set") { ok = false; }
  let e3 = seg(160, 0, 0, 0, 0, empty());
  if !err_frame_is(can_decode(&e3), "can: error frame flag set") { ok = false; }
  let e4 = seg(224, 0, 0, 0, 0, empty());
  if !err_frame_is(can_decode(&e4), "can: error frame flag set") { ok = false; }
  return assert(ok, "identifier range, error-flag and flag-bit precedence");
}

fn t12() -> TestResult {
  let z = empty();
  let a = CanFrame{ id: -1; extended: false; rtr: false; dlc: 0; data: z };
  var ok = err_unit_is(can_validate(&a), "can: negative identifier");
  let b = CanFrame{ id: 2048; extended: false; rtr: false; dlc: 0; data: z };
  if !err_unit_is(can_validate(&b), "can: identifier exceeds standard range") { ok = false; }
  let c = CanFrame{ id: 536870912; extended: true; rtr: false; dlc: 0; data: z };
  if !err_unit_is(can_validate(&c), "can: identifier exceeds extended range") { ok = false; }
  let d = CanFrame{ id: 1; extended: false; rtr: false; dlc: -1; data: z };
  if !err_unit_is(can_validate(&d), "can: invalid dlc") { ok = false; }
  let e = CanFrame{ id: 1; extended: false; rtr: false; dlc: 9; data: z };
  if !err_unit_is(can_validate(&e), "can: invalid dlc") { ok = false; }
  let p3 = hb("aabbcc");
  let g = CanFrame{ id: 1; extended: false; rtr: false; dlc: 2; data: p3 };
  if !err_unit_is(can_validate(&g), "can: data length does not match dlc") { ok = false; }
  let p2 = hb("aabb");
  let h = CanFrame{ id: 1; extended: false; rtr: true; dlc: 2; data: p2 };
  if !err_unit_is(can_validate(&h), "can: remote frame carries data") { ok = false; }
  let p9 = hb("010203040506070809");
  let i = CanFrame{ id: 1; extended: false; rtr: false; dlc: 9; data: p9 };
  if !err_unit_is(can_validate(&i), "can: payload exceeds 8 bytes") { ok = false; }
  let v = CanFrame{ id: 2047; extended: false; rtr: false; dlc: 0; data: z };
  if !can_validate(&v).is_ok { ok = false; }
  let w = CanFrame{ id: 536870911; extended: true; rtr: true; dlc: 8; data: z };
  if !can_validate(&w).is_ok { ok = false; }
  return assert(ok, "validate reports identifier, payload, DLC and data errors");
}

fn t13() -> TestResult {
  let dd = hb("dead");
  let r1 = can_data_frame(291, false, &dd);
  var ok = r1.is_ok;
  if ok {
    let f: CanFrame = r1.value;
    if !shape_is(&f, 291, false, false, 2) { ok = false; }
    if !payload_is(&f, hb("dead")) { ok = false; }
  }
  let big = hb("010203040506070809");
  let r2 = can_data_frame(1, false, &big);
  if !err_frame_is(r2, "can: payload exceeds 8 bytes") { ok = false; }
  let r3 = can_remote_frame(1, false, -1);
  if !err_frame_is(r3, "can: invalid dlc") { ok = false; }
  let r4 = can_remote_frame(1, true, 9);
  if !err_frame_is(r4, "can: invalid dlc") { ok = false; }
  let r5 = can_remote_frame(2048, false, 0);
  if !err_frame_is(r5, "can: identifier exceeds standard range") { ok = false; }
  let r6 = can_data_frame(536870912, true, &dd);
  if !err_frame_is(r6, "can: identifier exceeds extended range") { ok = false; }
  let r7 = can_data_frame(-1, false, &dd);
  if !err_frame_is(r7, "can: negative identifier") { ok = false; }
  let z = empty();
  let r8 = can_new(1, false, true, 8, &z);
  if !r8.is_ok { ok = false; } else {
    let f8: CanFrame = r8.value;
    if !shape_is(&f8, 1, false, true, 8) { ok = false; }
    if !payload_is(&f8, empty()) { ok = false; }
  }
  let r9 = can_new(1, false, false, 3, &z);
  if !err_frame_is(r9, "can: data length does not match dlc") { ok = false; }
  let r10 = can_new(1, false, true, 2, &dd);
  if !err_frame_is(r10, "can: remote frame carries data") { ok = false; }
  return assert(ok, "constructors accept canonical frames and report the catalog");
}

fn t14() -> TestResult {
  let p = hb("dead");
  let a = df(291, false, p);
  let b = df(291, false, p);
  var ok = can_equal(&a, &b);
  if !can_equal(&b, &a) { ok = false; }
  let c = df(292, false, p);
  if can_equal(&a, &c) { ok = false; }
  let d = df(291, true, p);
  if can_equal(&a, &d) { ok = false; }
  let e = rf(291, false, 2);
  if can_equal(&a, &e) { ok = false; }
  let f2 = df(291, false, hb("beef"));
  if can_equal(&a, &f2) { ok = false; }
  return assert(ok, "can_equal compares id, type, RTR, DLC and payload");
}

fn t15() -> TestResult {
  let f1 = df(0, false, empty());
  let f2 = df(8, false, hb("aa"));
  let f3 = df(2047, false, hb("0102030405060708"));
  let f4 = df(291, true, hb("aabbcc"));
  let f5 = rf(0, false, 0);
  let f6 = rf(536870911, true, 8);
  let f7 = df(536870911, true, hb("ff"));
  var ok = round_trip_ok(&f1);
  if !round_trip_ok(&f2) { ok = false; }
  if !round_trip_ok(&f3) { ok = false; }
  if !round_trip_ok(&f4) { ok = false; }
  if !round_trip_ok(&f5) { ok = false; }
  if !round_trip_ok(&f6) { ok = false; }
  if !round_trip_ok(&f7) { ok = false; }
  return assert(ok, "encode -> decode round-trips preserve every frame field");
}

fn t16() -> TestResult {
  let f = df(291, false, hb("dead"));
  var out = hb("aabb");
  let ar = can_encode_into(&mut out, &f);
  var ok = ar.is_ok;
  if !bytes_equal(out, hb("aabb0000012302000000dead000000000000")) { ok = false; }
  let z = empty();
  let bad = CanFrame{ id: 3000; extended: false; rtr: false; dlc: 0; data: z };
  var out2 = hb("aabb");
  let br = can_encode_into(&mut out2, &bad);
  if !err_unit_is(br, "can: identifier exceeds standard range") { ok = false; }
  if !bytes_equal(out2, hb("aabb")) { ok = false; }
  let er = can_encode(&bad);
  if !err_bytes_is(er, "can: identifier exceeds standard range") { ok = false; }
  return assert(ok, "can_encode_into appends exactly and leaves out untouched on Err");
}

fn t17() -> TestResult {
  var ok = can_max_id(false) == 2047;
  if can_max_id(true) != 536870911 { ok = false; }
  if can_encoded_size() != 16 { ok = false; }
  if !can_id_ok(0, false) { ok = false; }
  if !can_id_ok(2047, false) { ok = false; }
  if can_id_ok(2048, false) { ok = false; }
  if can_id_ok(-1, true) { ok = false; }
  if !can_id_ok(536870911, true) { ok = false; }
  if can_id_ok(536870912, true) { ok = false; }
  let f = df(291, false, hb("dead"));
  if can_id_word(&f) != 291 { ok = false; }
  let g = df(291, true, hb("dead"));
  if can_id_word(&g) != 2147483939 { ok = false; }
  let h = rf(291, false, 2);
  if can_id_word(&h) != 1073742115 { ok = false; }
  let i = rf(291, true, 2);
  if can_id_word(&i) != 3221225763 { ok = false; }
  if !can_is_extended(&g) { ok = false; }
  if can_is_extended(&f) { ok = false; }
  if !can_is_remote(&h) { ok = false; }
  if can_is_remote(&f) { ok = false; }
  if can_payload_len(&f) != 2 { ok = false; }
  if can_payload_len(&h) != 0 { ok = false; }
  if can_data_get(&f, 0) != 222 { ok = false; }
  if can_data_get(&f, 1) != 173 { ok = false; }
  if can_data_get(&f, 2) != -1 { ok = false; }
  if can_data_get(&f, -1) != -1 { ok = false; }
  if can_data_get(&h, 0) != -1 { ok = false; }
  return assert(ok, "accessors pin identifier words, lengths and payload bytes");
}

fn t18() -> TestResult {
  let a = hb("0000012302000000dead000000000000");
  let b = hb("92345678080000000102030405060708");
  let c = hb("400007ff080000000000000000000000");
  let d = hb("dfffffff000000000000000000000000");
  let e = hb("00000000000000000000000000000000");
  let f = hb("9fffffff080000000102030405060708");
  var ok = recodes_to(a, a);
  if !recodes_to(b, b) { ok = false; }
  if !recodes_to(c, c) { ok = false; }
  if !recodes_to(d, d) { ok = false; }
  if !recodes_to(e, e) { ok = false; }
  if !recodes_to(f, f) { ok = false; }
  return assert(ok, "decode -> encode reproduces every canonical container exactly");
}

fn t19() -> TestResult {
  let f = df(291, true, hb("aabbcc"));
  var ok = shape_is(&f, 291, true, false, 3);
  let e = enc(&f);
  if !bytes_equal(e, hb("8000012303000000aabbcc0000000000")) { ok = false; }
  let d = can_decode(&e);
  if !d.is_ok { ok = false; } else {
    let g: CanFrame = d.value;
    if !shape_is(&g, 291, true, false, 3) { ok = false; }
    if !payload_is(&g, hb("aabbcc")) { ok = false; }
  }
  return assert(ok, "a small identifier marked extended round-trips as 2.0B");
}

fn t20() -> TestResult {
  let base = hb("0000012302000000dead000000000000");
  let longbuf = concat2(base, hb("deadbeef"));
  var ok = longbuf.len() == 20;
  let r = can_decode(&longbuf);
  if !r.is_ok { ok = false; } else {
    let f: CanFrame = r.value;
    if !shape_is(&f, 291, false, false, 2) { ok = false; }
    if !payload_is(&f, hb("dead")) { ok = false; }
  }
  return assert(ok, "bytes after the first 16 are ignored");
}

fn t21() -> TestResult {
  let e = hb("9fffffff080000000102030405060708");
  let r = can_decode(&e);
  var ok = r.is_ok;
  if ok {
    let f: CanFrame = r.value;
    if !shape_is(&f, 536870911, true, false, 8) { ok = false; }
    if !payload_is(&f, hb("0102030405060708")) { ok = false; }
  }
  if !recodes_to(e, e) { ok = false; }
  return assert(ok, "the 29-bit identifier maximum decodes and re-encodes");
}

fn t22() -> TestResult {
  var ok = true;
  var n = 0;
  while n <= 8 {
    var p = Vec[UInt8].new();
    var i = 0;
    while i < n {
      p.push((i + 1) as UInt8);
      i = i + 1;
    }
    let f = df(131071, true, p);
    if !shape_is(&f, 131071, true, false, n) { ok = false; }
    if !round_trip_ok(&f) { ok = false; }
    n = n + 1;
  }
  return assert(ok, "extended frames with payload lengths 0..8 all round-trip");
}

fn main() -> Int {
  io.println("=== xiom.can conformance tests ===");
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
    io.println("xiom.can: all tests passed");
  } else {
    io.println("xiom.can: tests failed");
  }
  return failed;
}
