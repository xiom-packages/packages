// XIOM -- xiom.ntp conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented xiom.ntp API: a pinned 48-byte NTPv4 server packet
// decoded and re-encoded byte-for-byte; truncation vs. trailing bytes;
// version (3/4) and mode (1..6) validation on decode and encode; the
// LI/VN/Mode bit packing sweep; two's-complement signed poll, precision
// and root delay; unsigned root dispersion and reference id bounds;
// stratum, poll and precision ranges; 32.32 timestamp boundaries; the
// all-zero unsynchronized marker; integer-only fraction <-> microsecond and
// nanosecond conversions with pinned rounding; RFC 5905 offset/delay in
// microseconds including negative and floor-rounded cases; and the
// ntp_packet_valid / ntp_version_valid / ntp_mode_valid predicates.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison); error messages go
// through compare.str_compare. No table-driven dispatch: every tN() is
// called directly from main.

module ntp_tests
use xiom.io; use xiom.test;
use xiom.ntp;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
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

fn err_packet_is(r: Result[NtpPacket, Str], want: Str) -> Bool {
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

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn int_ok_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

// Raw timestamp constructor for test data.
fn ts(s: Int, f: Int) -> NtpTimestamp {
  return NtpTimestamp{ seconds: s; fraction: f; };
}

fn ts_eq(a: &NtpTimestamp, b: &NtpTimestamp) -> Bool {
  return a.seconds == b.seconds && a.fraction == b.fraction;
}

// An all-zero (unsynchronized) but otherwise valid NTPv4 server packet.
fn base_packet() -> NtpPacket {
  return NtpPacket{
    li: 0;
    vn: 4;
    mode: 4;
    stratum: 1;
    poll: 6;
    precision: -20;
    root_delay: 65536;
    root_dispersion: 32768;
    reference_id: 167772161;
    reference: ts(0, 0);
    origin: ts(0, 0);
    receive: ts(0, 0);
    transmit: ts(0, 0);
  };
}

fn pk_eq(a: &NtpPacket, b: &NtpPacket) -> Bool {
  if a.li != b.li { return false; }
  if a.vn != b.vn { return false; }
  if a.mode != b.mode { return false; }
  if a.stratum != b.stratum { return false; }
  if a.poll != b.poll { return false; }
  if a.precision != b.precision { return false; }
  if a.root_delay != b.root_delay { return false; }
  if a.root_dispersion != b.root_dispersion { return false; }
  if a.reference_id != b.reference_id { return false; }
  let ar: NtpTimestamp = a.reference;
  let br: NtpTimestamp = b.reference;
  if !ts_eq(&ar, &br) { return false; }
  let ao: NtpTimestamp = a.origin;
  let bo: NtpTimestamp = b.origin;
  if !ts_eq(&ao, &bo) { return false; }
  let ac: NtpTimestamp = a.receive;
  let bc: NtpTimestamp = b.receive;
  if !ts_eq(&ac, &bc) { return false; }
  let at: NtpTimestamp = a.transmit;
  let bt: NtpTimestamp = b.transmit;
  if !ts_eq(&at, &bt) { return false; }
  return true;
}

// A 48-byte buffer whose byte 0 is `b0` and every other byte is zero.
fn packet_with_header(b0: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 48 {
    v.push(0 as UInt8);
    i = i + 1;
  }
  v[0] = b0 as UInt8;
  return v;
}

// The first `n` bytes of `v` (a short source buffer).
fn prefix(v: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// `v` followed by one extra byte.
fn with_suffix(v: &Vec[UInt8], b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  out.push(b as UInt8);
  return out;
}

// The pinned server packet used by t1/t2:
//   LI=0 VN=4 Mode=4, stratum=2, poll=6, precision=-20,
//   root delay 0x00010000 (1.0 s), root dispersion 0x00008000 (0.5 s),
//   reference id 0x0a000001, and four distinct 32.32 timestamps.
fn pinned_packet() -> Vec[UInt8] {
  return hb("240206ec00010000000080000a0000010102030405060708112233445566778899aabbccddeeff00123456789abcdef0");
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = pinned_packet();
  let r = ntp_decode(&data);
  if !r.is_ok { return assert(false, "pinned packet must decode"); }
  let p: NtpPacket = r.value;
  var ok = p.li == 0;
  if p.vn != 4 { ok = false; }
  if p.mode != 4 { ok = false; }
  if p.stratum != 2 { ok = false; }
  if p.poll != 6 { ok = false; }
  if p.precision != -20 { ok = false; }
  if p.root_delay != 65536 { ok = false; }
  if p.root_dispersion != 32768 { ok = false; }
  if p.reference_id != 167772161 { ok = false; }
  let rts: NtpTimestamp = p.reference;
  if rts.seconds != 16909060 { ok = false; }
  if rts.fraction != 84281096 { ok = false; }
  let ots: NtpTimestamp = p.origin;
  if ots.seconds != 287454020 { ok = false; }
  if ots.fraction != 1432778632 { ok = false; }
  let cts: NtpTimestamp = p.receive;
  if cts.seconds != 2578103244 { ok = false; }
  if cts.fraction != 3723427584 { ok = false; }
  let tts: NtpTimestamp = p.transmit;
  if tts.seconds != 305419896 { ok = false; }
  if tts.fraction != 2596069104 { ok = false; }
  let er = ntp_encode(&p);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    if !bytes_equal(out, data) { ok = false; }
  }
  return assert(ok, "pinned NTPv4 server packet round-trips byte-for-byte");
}

fn t2() -> TestResult {
  let full = pinned_packet();
  let short = prefix(&full, 47);
  var ok = err_packet_is(ntp_decode(&short), "ntp: truncated packet");
  var empty = Vec[UInt8].new();
  if !err_packet_is(ntp_decode(&empty), "ntp: truncated packet") { ok = false; }
  let padded = with_suffix(&full, 0);
  let padded2 = with_suffix(&padded, 255);
  let pr = ntp_decode(&padded2);
  if !pr.is_ok { ok = false; } else {
    let p: NtpPacket = pr.value;
    if p.mode != 4 { ok = false; }
    if p.transmit.fraction != 2596069104 { ok = false; }
  }
  if !ntp_decode(&full).is_ok { ok = false; }
  return assert(ok, "shorter than 48 bytes is Err; 48 and longer decode");
}

fn t3() -> TestResult {
  let v2 = packet_with_header(20);
  let v5 = packet_with_header(44);
  var ok = err_packet_is(ntp_decode(&v2), "ntp: unsupported version");
  if !err_packet_is(ntp_decode(&v5), "ntp: unsupported version") { ok = false; }
  let v3 = packet_with_header(28);
  let r3 = ntp_decode(&v3);
  if !r3.is_ok { ok = false; } else {
    let p3: NtpPacket = r3.value;
    if p3.vn != 3 { ok = false; }
  }
  let v4 = packet_with_header(36);
  let r4 = ntp_decode(&v4);
  if !r4.is_ok { ok = false; } else {
    let p4: NtpPacket = r4.value;
    if p4.vn != 4 { ok = false; }
  }
  var bp = base_packet();
  bp.vn = 2;
  if !err_bytes_is(ntp_encode(&bp), "ntp: unsupported version") { ok = false; }
  bp.vn = 5;
  if !err_bytes_is(ntp_encode(&bp), "ntp: unsupported version") { ok = false; }
  bp.vn = 3;
  if !ntp_encode(&bp).is_ok { ok = false; }
  return assert(ok, "versions 3 and 4 accepted; others are Err");
}

fn t4() -> TestResult {
  let m0 = packet_with_header(32);
  let m7 = packet_with_header(39);
  var ok = err_packet_is(ntp_decode(&m0), "ntp: invalid mode");
  if !err_packet_is(ntp_decode(&m7), "ntp: invalid mode") { ok = false; }
  var m = 1;
  while m <= 6 {
    let raw = packet_with_header(32 + m);
    let r = ntp_decode(&raw);
    if !r.is_ok { ok = false; } else {
      let p: NtpPacket = r.value;
      if p.mode != m { ok = false; }
    }
    m = m + 1;
  }
  var bp = base_packet();
  bp.mode = 0;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid mode") { ok = false; }
  bp.mode = 7;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid mode") { ok = false; }
  return assert(ok, "modes 1..6 accepted; 0 and 7 are Err");
}

fn t5() -> TestResult {
  var ok = true;
  var li = 0;
  while li <= 3 {
    let raw = packet_with_header(li * 64 + 35);
    let r = ntp_decode(&raw);
    if !r.is_ok { ok = false; } else {
      let p: NtpPacket = r.value;
      if p.li != li { ok = false; }
      if p.mode != 3 { ok = false; }
      if p.vn != 4 { ok = false; }
    }
    li = li + 1;
  }
  var bp = base_packet();
  bp.li = 4;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid leap indicator") { ok = false; }
  bp.li = -1;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid leap indicator") { ok = false; }
  bp.li = 3;
  let er = ntp_encode(&bp);
  if !er.is_ok { ok = false; } else {
    let out: Vec[UInt8] = er.value;
    let b0: UInt8 = out[0];
    if ((b0 as Int) & 0xFF) != 228 { ok = false; }
  }
  return assert(ok, "LI occupies the top two bits and round-trips");
}

fn t6() -> TestResult {
  var bp = base_packet();
  bp.poll = -128;
  bp.precision = -1;
  let r1 = ntp_encode(&bp);
  if !r1.is_ok { return assert(false, "signed fields must encode"); }
  let b1: Vec[UInt8] = r1.value;
  var ok = ((b1[2] as Int) & 0xFF) == 128;
  if ((b1[3] as Int) & 0xFF) != 255 { ok = false; }
  let d1 = ntp_decode(&b1);
  if !d1.is_ok { ok = false; } else {
    let p1: NtpPacket = d1.value;
    if p1.poll != -128 { ok = false; }
    if p1.precision != -1 { ok = false; }
  }
  bp.poll = 127;
  bp.precision = 127;
  let r2 = ntp_encode(&bp);
  if !r2.is_ok { ok = false; } else {
    let b2: Vec<UInt8> = r2.value;
    if ((b2[2] as Int) & 0xFF) != 127 { ok = false; }
    if ((b2[3] as Int) & 0xFF) != 127 { ok = false; }
  }
  bp.poll = 0;
  bp.precision = 0;
  bp.root_delay = 0 - 1;
  let r3 = ntp_encode(&bp);
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if ((b3[4] as Int) & 0xFF) != 255 { ok = false; }
    if ((b3[7] as Int) & 0xFF) != 255 { ok = false; }
    let d3 = ntp_decode(&b3);
    if !d3.is_ok { ok = false; } else {
      let p3: NtpPacket = d3.value;
      if p3.root_delay != -1 { ok = false; }
    }
  }
  bp.root_delay = -2147483648;
  let r4 = ntp_encode(&bp);
  if !r4.is_ok { ok = false; } else {
    let b4: Vec[UInt8] = r4.value;
    if ((b4[4] as Int) & 0xFF) != 128 { ok = false; }
    let d4 = ntp_decode(&b4);
    if !d4.is_ok { ok = false; } else {
      let p4: NtpPacket = d4.value;
      if p4.root_delay != -2147483648 { ok = false; }
    }
  }
  bp.root_delay = 2147483647;
  let r5 = ntp_encode(&bp);
  if !r5.is_ok { ok = false; } else {
    let b5: Vec<UInt8> = r5.value;
    if ((b5[4] as Int) & 0xFF) != 127 { ok = false; }
    let d5 = ntp_decode(&b5);
    if !d5.is_ok { ok = false; } else {
      let p5: NtpPacket = d5.value;
      if p5.root_delay != 2147483647 { ok = false; }
    }
  }
  return assert(ok, "signed poll/precision/root delay use two's complement");
}

fn t7() -> TestResult {
  var bp = base_packet();
  bp.root_dispersion = 4294967295;
  bp.reference_id = 4294967295;
  let r1 = ntp_encode(&bp);
  if !r1.is_ok { return assert(false, "max unsigned fields must encode"); }
  let b1: Vec<UInt8> = r1.value;
  var ok = ((b1[8] as Int) & 0xFF) == 255;
  if ((b1[11] as Int) & 0xFF) != 255 { ok = false; }
  if ((b1[12] as Int) & 0xFF) != 255 { ok = false; }
  if ((b1[15] as Int) & 0xFF) != 255 { ok = false; }
  let d1 = ntp_decode(&b1);
  if !d1.is_ok { ok = false; } else {
    let p1: NtpPacket = d1.value;
    if p1.root_dispersion != 4294967295 { ok = false; }
    if p1.reference_id != 4294967295 { ok = false; }
  }
  bp.root_dispersion = -1;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid root dispersion") { ok = false; }
  bp.root_dispersion = 4294967296;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid root dispersion") { ok = false; }
  bp.root_dispersion = 0;
  bp.reference_id = -1;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid reference id") { ok = false; }
  bp.reference_id = 4294967296;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid reference id") { ok = false; }
  bp.reference_id = 0;
  bp.root_delay = 2147483648;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid root delay") { ok = false; }
  bp.root_delay = -2147483649;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid root delay") { ok = false; }
  return assert(ok, "unsigned 32-bit fields and signed root delay are range-checked");
}

fn t8() -> TestResult {
  var bp = base_packet();
  bp.stratum = 255;
  let r1 = ntp_encode(&bp);
  var ok = r1.is_ok;
  if r1.is_ok {
    let b1: Vec<UInt8> = r1.value;
    if ((b1[1] as Int) & 0xFF) != 255 { ok = false; }
  }
  bp.stratum = 256;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid stratum") { ok = false; }
  bp.stratum = -1;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid stratum") { ok = false; }
  bp.stratum = 0;
  bp.poll = 128;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid poll") { ok = false; }
  bp.poll = -129;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid poll") { ok = false; }
  bp.poll = 0;
  bp.precision = 128;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid precision") { ok = false; }
  bp.precision = -129;
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid precision") { ok = false; }
  return assert(ok, "stratum/poll/precision ranges are enforced on encode");
}

fn t9() -> TestResult {
  var bp = base_packet();
  bp.transmit = ts(4294967295, 4294967295);
  bp.origin = ts(0, 1);
  let r1 = ntp_encode(&bp);
  if !r1.is_ok { return assert(false, "timestamp boundaries must encode"); }
  let b1: Vec<UInt8> = r1.value;
  var ok = ((b1[40] as Int) & 0xFF) == 255;
  if ((b1[47] as Int) & 0xFF) != 255 { ok = false; }
  let d1 = ntp_decode(&b1);
  if !d1.is_ok { ok = false; } else {
    let p1: NtpPacket = d1.value;
    if p1.transmit.seconds != 4294967295 { ok = false; }
    if p1.transmit.fraction != 4294967295 { ok = false; }
    if p1.origin.fraction != 1 { ok = false; }
    if p1.origin.seconds != 0 { ok = false; }
  }
  bp.transmit = ts(4294967296, 0);
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid timestamp") { ok = false; }
  bp.transmit = ts(0, 4294967296);
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid timestamp") { ok = false; }
  bp.transmit = ts(0 - 1, 0);
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid timestamp") { ok = false; }
  bp.transmit = ts(0, 0 - 1);
  if !err_bytes_is(ntp_encode(&bp), "ntp: invalid timestamp") { ok = false; }
  return assert(ok, "32.32 timestamp halves are 0..2^32-1 and round-trip");
}

fn t10() -> TestResult {
  let z = ntp_timestamp_zero();
  var ok = ntp_timestamp_is_zero(&z);
  let one = ts(1, 0);
  if ntp_timestamp_is_zero(&one) { ok = false; }
  let tiny = ts(0, 1);
  if ntp_timestamp_is_zero(&tiny) { ok = false; }
  let bp = base_packet();
  let er = ntp_encode(&bp);
  if !er.is_ok { ok = false; } else {
    let out: Vec<UInt8> = er.value;
    var k = 16;
    while k < 48 {
      if ((out[k] as Int) & 0xFF) != 0 { ok = false; }
      k = k + 1;
    }
    let dr = ntp_decode(&out);
    if !dr.is_ok { ok = false; } else {
      let p: NtpPacket = dr.value;
      let pt: NtpTimestamp = p.transmit;
      if !ntp_timestamp_is_zero(&pt) { ok = false; }
      if !ntp_packet_valid(&p) { ok = false; }
    }
  }
  let t1 = ts(1000, 0);
  let t2 = ts(1000, 2147483648);
  let t3 = ts(1000, 3221225472);
  let t4 = ts(1001, 0);
  let zs = ntp_timestamp_zero();
  if !err_int_is(ntp_offset_micros(&zs, &t2, &t3, &t4), "ntp: zero timestamp") { ok = false; }
  if !err_int_is(ntp_delay_micros(&t1, &t2, &zs, &t4), "ntp: zero timestamp") { ok = false; }
  if !ntp_offset_micros(&t1, &t2, &t3, &t4).is_ok { ok = false; }
  return assert(ok, "zero timestamps mark unsynchronized data and are rejected by offset/delay");
}

fn t11() -> TestResult {
  var ok = int_ok_is(ntp_fraction_to_micros(0), 0);
  if !int_ok_is(ntp_fraction_to_micros(1073741824), 250000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_micros(2147483648), 500000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_micros(3221225472), 750000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_micros(4294967294), 999999) { ok = false; }
  if !int_ok_is(ntp_fraction_to_micros(4294967295), 999999) { ok = false; }
  if !int_ok_is(ntp_fraction_to_micros(4295), 1) { ok = false; }
  if !err_int_is(ntp_fraction_to_micros(0 - 1), "ntp: invalid timestamp") { ok = false; }
  if !err_int_is(ntp_fraction_to_micros(4294967296), "ntp: invalid timestamp") { ok = false; }
  return assert(ok, "fraction to microseconds truncates to whole microseconds");
}

fn t12() -> TestResult {
  var ok = int_ok_is(ntp_fraction_to_nanos(0), 0);
  if !int_ok_is(ntp_fraction_to_nanos(1073741824), 250000000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_nanos(2147483648), 500000000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_nanos(3221225472), 750000000) { ok = false; }
  if !int_ok_is(ntp_fraction_to_nanos(4294967294), 999999999) { ok = false; }
  if !int_ok_is(ntp_fraction_to_nanos(4294967295), 999999999) { ok = false; }
  if !int_ok_is(ntp_fraction_to_nanos(4295), 1000) { ok = false; }
  if !err_int_is(ntp_fraction_to_nanos(0 - 1), "ntp: invalid timestamp") { ok = false; }
  if !err_int_is(ntp_fraction_to_nanos(4294967296), "ntp: invalid timestamp") { ok = false; }
  return assert(ok, "fraction to nanoseconds truncates to whole nanoseconds");
}

fn t13() -> TestResult {
  var ok = int_ok_is(ntp_micros_to_fraction(0), 0);
  if !int_ok_is(ntp_micros_to_fraction(1), 4295) { ok = false; }
  if !int_ok_is(ntp_micros_to_fraction(2), 8590) { ok = false; }
  if !int_ok_is(ntp_micros_to_fraction(250000), 1073741824) { ok = false; }
  if !int_ok_is(ntp_micros_to_fraction(500000), 2147483648) { ok = false; }
  if !int_ok_is(ntp_micros_to_fraction(750000), 3221225472) { ok = false; }
  if !int_ok_is(ntp_micros_to_fraction(999999), 4294963001) { ok = false; }
  if !err_int_is(ntp_micros_to_fraction(0 - 1), "ntp: micros out of range") { ok = false; }
  if !err_int_is(ntp_micros_to_fraction(1000000), "ntp: micros out of range") { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(0), 0) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(1), 4) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(250000000), 1073741824) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(500000000), 2147483648) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(750000000), 3221225472) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(999999998), 4294967287) { ok = false; }
  if !int_ok_is(ntp_nanos_to_fraction(999999999), 4294967292) { ok = false; }
  if !err_int_is(ntp_nanos_to_fraction(0 - 1), "ntp: nanos out of range") { ok = false; }
  if !err_int_is(ntp_nanos_to_fraction(1000000000), "ntp: nanos out of range") { ok = false; }
  return assert(ok, "micros/nanos to fraction round to the nearest 2^-32 unit");
}

fn t14() -> TestResult {
  let t1 = ts(1000, 0);
  let t2 = ts(1000, 2147483648);
  let t3 = ts(1000, 3221225472);
  let t4 = ts(1001, 0);
  var ok = int_ok_is(ntp_offset_micros(&t1, &t2, &t3, &t4), 125000);
  if !int_ok_is(ntp_delay_micros(&t1, &t2, &t3, &t4), 750000) { ok = false; }
  let u2 = ts(1000, 2147483648);
  let u3 = ts(1000, 2147483648);
  if !int_ok_is(ntp_offset_micros(&t1, &u2, &u3, &t4), 0) { ok = false; }
  if !int_ok_is(ntp_delay_micros(&t1, &u2, &u3, &t4), 1000000) { ok = false; }
  return assert(ok, "offset and delay match the RFC 5905 formulas in microseconds");
}

fn t15() -> TestResult {
  let a1 = ts(1, 0);
  let a2 = ts(1, 12888);
  let a3 = ts(5, 0);
  let a4 = ts(5, 0);
  var ok = int_ok_is(ntp_offset_micros(&a1, &a2, &a3, &a4), 1);
  if !int_ok_is(ntp_delay_micros(&a1, &a2, &a3, &a4), 3) { ok = false; }
  let b1 = ts(1, 0);
  let b2 = ts(1, 12888);
  let b3 = ts(1, 0);
  let b4 = ts(2, 0);
  if !int_ok_is(ntp_offset_micros(&b1, &b2, &b3, &b4), -499999) { ok = false; }
  if !int_ok_is(ntp_delay_micros(&b1, &b2, &b3, &b4), 1000003) { ok = false; }
  let c1 = ts(1000, 0);
  let c2 = ts(999, 2147483648);
  let c3 = ts(999, 2147483648);
  let c4 = ts(1001, 0);
  if !int_ok_is(ntp_offset_micros(&c1, &c2, &c3, &c4), -1000000) { ok = false; }
  if !int_ok_is(ntp_delay_micros(&c1, &c2, &c3, &c4), 1000000) { ok = false; }
  return assert(ok, "offset rounds toward negative infinity; delay is exact");
}

fn t16() -> TestResult {
  let z = ntp_timestamp_zero();
  var ok = int_ok_is(ntp_timestamp_to_micros(&z), 0);
  let half = ts(1, 2147483648);
  if !int_ok_is(ntp_timestamp_to_micros(&half), 1500000) { ok = false; }
  let full = ts(4294967295, 4294967295);
  if !int_ok_is(ntp_timestamp_to_micros(&full), 4294967295999999) { ok = false; }
  let sub = ts(0, 4294967295);
  if !int_ok_is(ntp_timestamp_to_micros(&sub), 999999) { ok = false; }
  let bad_s = ts(0 - 1, 0);
  if !err_int_is(ntp_timestamp_to_micros(&bad_s), "ntp: invalid timestamp") { ok = false; }
  let bad_f = ts(0, 4294967296);
  if !err_int_is(ntp_timestamp_to_micros(&bad_f), "ntp: invalid timestamp") { ok = false; }
  return assert(ok, "32.32 timestamps convert to microseconds since the NTP epoch");
}

fn t17() -> TestResult {
  let good = base_packet();
  var ok = ntp_packet_valid(&good);
  var bad = base_packet();
  bad.vn = 5;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.mode = 0;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.li = 4;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.stratum = 256;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.poll = 128;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.precision = -129;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.root_delay = 2147483648;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.root_dispersion = 0 - 1;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.reference_id = 0 - 1;
  if ntp_packet_valid(&bad) { ok = false; }
  bad = base_packet();
  bad.transmit = ts(0, 4294967296);
  if ntp_packet_valid(&bad) { ok = false; }
  if !ntp_version_valid(3) { ok = false; }
  if !ntp_version_valid(4) { ok = false; }
  if ntp_version_valid(2) { ok = false; }
  if ntp_version_valid(5) { ok = false; }
  var m = 1;
  while m <= 6 {
    if !ntp_mode_valid(m) { ok = false; }
    m = m + 1;
  }
  if ntp_mode_valid(0) { ok = false; }
  if ntp_mode_valid(7) { ok = false; }
  return assert(ok, "packet/version/mode predicates accept valid data and reject out-of-range fields");
}

fn t18() -> TestResult {
  var ok = true;
  var li = 0;
  while li <= 3 {
    var vn = 3;
    while vn <= 4 {
      var mode = 1;
      while mode <= 6 {
        let b0 = li * 64 + vn * 8 + mode;
        let raw = packet_with_header(b0);
        let r = ntp_decode(&raw);
        if !r.is_ok { ok = false; } else {
          let p: NtpPacket = r.value;
          if p.li != li || p.vn != vn || p.mode != mode { ok = false; }
          let er = ntp_encode(&p);
          if !er.is_ok { ok = false; } else {
            let out: Vec[UInt8] = er.value;
            if out.len() != 48 { ok = false; }
            let ob: UInt8 = out[0];
            if ((ob as Int) & 0xFF) != b0 { ok = false; }
          }
        }
        mode = mode + 1;
      }
      vn = vn + 1;
    }
    li = li + 1;
  }
  return assert(ok, "all 48 LI/VN/Mode combinations round-trip through 48 bytes");
}

fn main() -> Int {
  io.println("=== xiom.ntp conformance tests ===");
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
    io.println("xiom.ntp: all tests passed");
  } else {
    io.println("xiom.ntp: tests failed");
  }
  return failed;
}
