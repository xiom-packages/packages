// XIOM -- xiom.uart conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API against the xiom.uart SPEC.md: the parameter
// codes and names, the default line, configuration validation order, frame
// geometry, parity computation, the exact encode/decode bit layout with
// idle-high framing, every framing error (false start, invalid bit value,
// parity mismatch, invalid stop, truncation, bad position), whole-stream
// codecs, bit helpers, oversampling ticks and the baud divisor math with
// fractional error.
//
// Bit streams are written as strings of '0'/'1' digits and widened in-test
// (`bits`); values above 1 are possible on purpose for the invalid-bit
// tests. Str values in the error checks go through
// xiom.string.compare.str_compare (BUG 17: `==` on a Str read from a Vec
// lowers to a pointer comparison); every Vec element read is bound to a
// typed local.

module uart_tests
use xiom.io; use xiom.test;
use xiom.uart;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Fixture helpers (independent of src/uart.xi)
// --------------------------------------------------

// Bit stream from a digit string: each character (minus '0') becomes one
// stream element, so "0101" is start, one data bit, parity, stop, and
// "12" is a deliberately malformed stream.
fn bits(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let d: Int = (string.byte_at(s, i) as Int) & 0xFF;
    v.push((d - 48) as UInt8);
    i = i + 1;
  }
  return v;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bits_eq(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  return uart_bits_equal(&a, &b);
}

fn ints_eq(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_cfg_is(r: Result[UartConfig, Str], want: Str) -> Bool {
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_intvec_is(r: Result[Vec[Int], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Configuration for tests; a sentinel config (all -1) when the constructor
// rejects the arguments, so the calling test fails on its field checks.
fn cfg(baud: Int, db: Int, p: Int, sh: Int, f: Int) -> UartConfig {
  let r = uart_new(baud, db, p, sh, f);
  match r {
    Ok(c) => { return c; },
    Err(_) => {},
  }
  return UartConfig{ baud: -1; data_bits: -1; parity: -1; stop_half: -1; flow: -1; };
}

// Decode helpers that bind the synthetic stream to a local first: a
// `&Vec[UInt8]` argument is never a temporary.
fn dec(s: Str, c: &UartConfig) -> Result[Int, Str] {
  let b = bits(s);
  return uart_decode_byte(&b, c);
}

fn dec_at(s: Str, c: &UartConfig, pos: Int) -> Result[Int, Str] {
  let b = bits(s);
  return uart_decode_byte_at(&b, c, pos);
}

fn dec_stream(s: Str, c: &UartConfig) -> Result[Vec[Int], Str] {
  let b = bits(s);
  return uart_decode_stream(&b, c);
}

// Encode -> decode one value under one configuration and compare.
fn round_trip_value(c: &UartConfig, b: Int) -> Bool {
  let er = uart_encode_byte(c, b);
  if !er.is_ok {
    return false;
  }
  let eb: Vec[UInt8] = er.value;
  let dr = uart_decode_byte(&eb, c);
  if !dr.is_ok {
    return false;
  }
  return dr.value == b;
}

// Every value 0..2^db - 1 under one configuration.
fn round_trip_config(baud: Int, db: Int, p: Int, sh: Int, f: Int) -> Bool {
  let c = cfg(baud, db, p, sh, f);
  if c.baud != baud {
    return false;
  }
  var lim = 1;
  var k = 0;
  while k < db {
    lim = lim * 2;
    k = k + 1;
  }
  let maxb = lim - 1;
  var b = 0;
  while b <= maxb {
    if !round_trip_value(&c, b) {
      return false;
    }
    b = b + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = uart_parity_none() == 0;
  if uart_parity_even() != 1 { ok = false; }
  if uart_parity_odd() != 2 { ok = false; }
  if uart_parity_mark() != 3 { ok = false; }
  if uart_parity_space() != 4 { ok = false; }
  if uart_flow_none() != 0 { ok = false; }
  if uart_flow_rts_cts() != 1 { ok = false; }
  if uart_flow_xon_xoff() != 2 { ok = false; }
  if !str_eq(uart_version(), "0.1.0") { ok = false; }
  if !str_eq(uart_parity_name(0), "none") { ok = false; }
  if !str_eq(uart_parity_name(1), "even") { ok = false; }
  if !str_eq(uart_parity_name(2), "odd") { ok = false; }
  if !str_eq(uart_parity_name(3), "mark") { ok = false; }
  if !str_eq(uart_parity_name(4), "space") { ok = false; }
  if !str_eq(uart_parity_name(5), "invalid") { ok = false; }
  if !str_eq(uart_flow_name(0), "none") { ok = false; }
  if !str_eq(uart_flow_name(1), "rts_cts") { ok = false; }
  if !str_eq(uart_flow_name(2), "xon_xoff") { ok = false; }
  if !str_eq(uart_flow_name(3), "invalid") { ok = false; }
  if !str_eq(uart_stop_name(2), "1") { ok = false; }
  if !str_eq(uart_stop_name(3), "1.5") { ok = false; }
  if !str_eq(uart_stop_name(4), "2") { ok = false; }
  if !str_eq(uart_stop_name(1), "invalid") { ok = false; }
  return assert(ok, "parameter codes, names and version are pinned");
}

fn t2() -> TestResult {
  let d = uart_default();
  var ok = d.baud == 115200;
  if d.data_bits != 8 { ok = false; }
  if d.parity != 0 { ok = false; }
  if d.stop_half != 2 { ok = false; }
  if d.flow != 0 { ok = false; }
  if !uart_config_ok(&d).is_ok { ok = false; }
  let n = cfg(9600, 7, 2, 4, 1);
  if n.baud != 9600 { ok = false; }
  if n.data_bits != 7 { ok = false; }
  if n.parity != 2 { ok = false; }
  if n.stop_half != 4 { ok = false; }
  if n.flow != 1 { ok = false; }
  if !uart_config_equal(&d, &d) { ok = false; }
  if uart_config_equal(&d, &n) { ok = false; }
  return assert(ok, "uart_default and uart_new build the pinned configurations");
}

fn t3() -> TestResult {
  let b0 = UartConfig{ baud: 0; data_bits: 8; parity: 0; stop_half: 2; flow: 0 };
  let b1 = UartConfig{ baud: -1; data_bits: 8; parity: 0; stop_half: 2; flow: 0 };
  var ok = err_unit_is(uart_config_ok(&b0), "uart: invalid baud");
  if !err_unit_is(uart_config_ok(&b1), "uart: invalid baud") { ok = false; }
  let db4 = UartConfig{ baud: 9600; data_bits: 4; parity: 0; stop_half: 2; flow: 0 };
  if !err_unit_is(uart_config_ok(&db4), "uart: invalid data bits") { ok = false; }
  let db10 = UartConfig{ baud: 9600; data_bits: 10; parity: 0; stop_half: 2; flow: 0 };
  if !err_unit_is(uart_config_ok(&db10), "uart: invalid data bits") { ok = false; }
  let pm1 = UartConfig{ baud: 9600; data_bits: 8; parity: -1; stop_half: 2; flow: 0 };
  if !err_unit_is(uart_config_ok(&pm1), "uart: invalid parity") { ok = false; }
  let p5 = UartConfig{ baud: 9600; data_bits: 8; parity: 5; stop_half: 2; flow: 0 };
  if !err_unit_is(uart_config_ok(&p5), "uart: invalid parity") { ok = false; }
  let s1 = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 1; flow: 0 };
  if !err_unit_is(uart_config_ok(&s1), "uart: invalid stop bits") { ok = false; }
  let s5 = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 5; flow: 0 };
  if !err_unit_is(uart_config_ok(&s5), "uart: invalid stop bits") { ok = false; }
  let f3 = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 2; flow: 3 };
  if !err_unit_is(uart_config_ok(&f3), "uart: invalid flow control") { ok = false; }
  let fm1 = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 2; flow: -1 };
  if !err_unit_is(uart_config_ok(&fm1), "uart: invalid flow control") { ok = false; }
  let allbad = UartConfig{ baud: 0; data_bits: 4; parity: 9; stop_half: 9; flow: 9 };
  if !err_unit_is(uart_config_ok(&allbad), "uart: invalid baud") { ok = false; }
  if !err_cfg_is(uart_new(9600, 4, 0, 2, 0), "uart: invalid data bits") { ok = false; }
  if !err_cfg_is(uart_new(0, 8, 0, 2, 0), "uart: invalid baud") { ok = false; }
  let good = uart_new(9600, 8, 0, 4, 2);
  if !good.is_ok { ok = false; }
  return assert(ok, "configuration errors are reported in the documented order");
}

fn t4() -> TestResult {
  let n1 = cfg(115200, 8, 0, 2, 0);
  let e1 = cfg(115200, 8, 1, 2, 0);
  let h15 = cfg(115200, 8, 0, 3, 0);
  let n2 = cfg(115200, 8, 0, 4, 0);
  let n5 = cfg(9600, 5, 0, 2, 0);
  let e2_9 = cfg(9600, 9, 1, 4, 0);
  var ok = uart_has_parity(&e1);
  if uart_has_parity(&n1) { ok = false; }
  if uart_has_parity(&n5) { ok = false; }
  if !uart_has_parity(&e2_9) { ok = false; }
  if uart_stop_bit_times(2) != 1 { ok = false; }
  if uart_stop_bit_times(3) != 2 { ok = false; }
  if uart_stop_bit_times(4) != 2 { ok = false; }
  if uart_frame_len(&n1) != 10 { ok = false; }
  if uart_frame_len(&e1) != 11 { ok = false; }
  if uart_frame_len(&h15) != 11 { ok = false; }
  if uart_frame_len(&n2) != 11 { ok = false; }
  if uart_frame_len(&n5) != 7 { ok = false; }
  if uart_frame_len(&e2_9) != 13 { ok = false; }
  if uart_frame_halves(&n1) != 20 { ok = false; }
  if uart_frame_halves(&e1) != 22 { ok = false; }
  if uart_frame_halves(&h15) != 21 { ok = false; }
  if uart_frame_halves(&n2) != 22 { ok = false; }
  if uart_frame_halves(&n5) != 14 { ok = false; }
  if uart_frame_halves(&e2_9) != 26 { ok = false; }
  return assert(ok, "frame length and half-time geometry are pinned");
}

fn t5() -> TestResult {
  var ok = uart_parity_bit(0, 0, 8) == 0;
  if uart_parity_bit(0, 255, 8) != 0 { ok = false; }
  if uart_parity_bit(1, 0, 8) != 0 { ok = false; }
  if uart_parity_bit(1, 255, 8) != 0 { ok = false; }
  if uart_parity_bit(1, 1, 8) != 1 { ok = false; }
  if uart_parity_bit(1, 3, 8) != 0 { ok = false; }
  if uart_parity_bit(2, 0, 8) != 1 { ok = false; }
  if uart_parity_bit(2, 255, 8) != 1 { ok = false; }
  if uart_parity_bit(2, 1, 8) != 0 { ok = false; }
  if uart_parity_bit(2, 3, 8) != 1 { ok = false; }
  if uart_parity_bit(3, 0, 8) != 1 { ok = false; }
  if uart_parity_bit(3, 255, 8) != 1 { ok = false; }
  if uart_parity_bit(4, 0, 8) != 0 { ok = false; }
  if uart_parity_bit(4, 255, 8) != 0 { ok = false; }
  if uart_parity_bit(1, 129, 7) != 1 { ok = false; }
  if uart_parity_bit(1, 255, 7) != 1 { ok = false; }
  if uart_parity_bit(1, 511, 9) != 1 { ok = false; }
  if uart_parity_bit(2, 511, 9) != 0 { ok = false; }
  if uart_parity_bit(9, 255, 8) != 0 { ok = false; }
  return assert(ok, "parity bits follow the even/odd/mark/space rules");
}

fn t6() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  let r65 = uart_encode_byte(&c, 65);
  var ok = r65.is_ok;
  if ok {
    let b65: Vec[UInt8] = r65.value;
    if !bits_eq(b65, bits("0100000101")) { ok = false; }
  }
  let r66 = uart_encode_byte(&c, 66);
  if !r66.is_ok { ok = false; } else {
    let b66: Vec[UInt8] = r66.value;
    if !bits_eq(b66, bits("0010000101")) { ok = false; }
  }
  let r0 = uart_encode_byte(&c, 0);
  if !r0.is_ok { ok = false; } else {
    let b0: Vec[UInt8] = r0.value;
    if !bits_eq(b0, bits("0000000001")) { ok = false; }
  }
  let r255 = uart_encode_byte(&c, 255);
  if !r255.is_ok { ok = false; } else {
    let b255: Vec[UInt8] = r255.value;
    if !bits_eq(b255, bits("0111111111")) { ok = false; }
  }
  return assert(ok, "8N1 frames are start bit, data LSB-first, one stop bit");
}

fn t7() -> TestResult {
  var ok = true;
  let e = uart_encode_byte(&cfg(115200, 8, 1, 2, 0), 65);
  if !e.is_ok { ok = false; } else {
    let v: Vec[UInt8] = e.value;
    if !bits_eq(v, bits("01000001001")) { ok = false; }
  }
  let o = uart_encode_byte(&cfg(115200, 8, 2, 2, 0), 65);
  if !o.is_ok { ok = false; } else {
    let v: Vec[UInt8] = o.value;
    if !bits_eq(v, bits("01000001011")) { ok = false; }
  }
  let m = uart_encode_byte(&cfg(115200, 8, 3, 2, 0), 0);
  if !m.is_ok { ok = false; } else {
    let v: Vec[UInt8] = m.value;
    if !bits_eq(v, bits("00000000011")) { ok = false; }
  }
  let s = uart_encode_byte(&cfg(115200, 8, 4, 2, 0), 0);
  if !s.is_ok { ok = false; } else {
    let v: Vec[UInt8] = s.value;
    if !bits_eq(v, bits("00000000001")) { ok = false; }
  }
  let n2 = uart_encode_byte(&cfg(115200, 8, 0, 4, 0), 65);
  if !n2.is_ok { ok = false; } else {
    let v: Vec[UInt8] = n2.value;
    if !bits_eq(v, bits("01000001011")) { ok = false; }
  }
  let h15 = uart_encode_byte(&cfg(115200, 8, 0, 3, 0), 65);
  if !h15.is_ok { ok = false; } else {
    let v: Vec[UInt8] = h15.value;
    if !bits_eq(v, bits("01000001011")) { ok = false; }
  }
  let n5 = uart_encode_byte(&cfg(9600, 5, 0, 2, 0), 31);
  if !n5.is_ok { ok = false; } else {
    let v: Vec[UInt8] = n5.value;
    if !bits_eq(v, bits("0111111")) { ok = false; }
  }
  let e72 = uart_encode_byte(&cfg(9600, 7, 1, 4, 0), 85);
  if !e72.is_ok { ok = false; } else {
    let v: Vec[UInt8] = e72.value;
    if !bits_eq(v, bits("01010101011")) { ok = false; }
  }
  let n9 = uart_encode_byte(&cfg(9600, 9, 0, 2, 0), 427);
  if !n9.is_ok { ok = false; } else {
    let v: Vec[UInt8] = n9.value;
    if !bits_eq(v, bits("01101010111")) { ok = false; }
  }
  return assert(ok, "parity, stop-bit and 5..9 data-bit layouts are pinned");
}

fn t8() -> TestResult {
  var ok = uart_byte_ok(0);
  if !uart_byte_ok(511) { ok = false; }
  if uart_byte_ok(512) { ok = false; }
  if uart_byte_ok(-1) { ok = false; }
  let c8 = cfg(115200, 8, 0, 2, 0);
  let c7 = cfg(115200, 7, 1, 2, 0);
  let c9 = cfg(115200, 9, 0, 2, 0);
  if !uart_byte_fits(&c8, 255) { ok = false; }
  if uart_byte_fits(&c8, 256) { ok = false; }
  if !uart_byte_fits(&c7, 127) { ok = false; }
  if uart_byte_fits(&c7, 128) { ok = false; }
  if !uart_byte_fits(&c9, 511) { ok = false; }
  if uart_byte_fits(&c9, -1) { ok = false; }
  if !err_bytes_is(uart_encode_byte(&c8, 256), "uart: byte exceeds data bits") { ok = false; }
  if !err_bytes_is(uart_encode_byte(&c8, -1), "uart: byte out of range") { ok = false; }
  if !err_bytes_is(uart_encode_byte(&c7, 128), "uart: byte exceeds data bits") { ok = false; }
  let bad = UartConfig{ baud: 0; data_bits: 8; parity: 0; stop_half: 2; flow: 0 };
  if !err_bytes_is(uart_encode_byte(&bad, 0), "uart: invalid baud") { ok = false; }
  var tmp8 = bits("");
  if !err_unit_is(uart_encode_byte_into(&mut tmp8, &c8, 256), "uart: byte exceeds data bits") { ok = false; }
  return assert(ok, "byte range and configuration errors are pinned");
}

fn t9() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var out = bits("10");
  let r = uart_encode_byte_into(&mut out, &c, 65);
  var ok = r.is_ok;
  if !bits_eq(out, bits("100100000101")) { ok = false; }
  var out2 = bits("1010");
  let bad = uart_encode_byte_into(&mut out2, &c, 256);
  if !err_unit_is(bad, "uart: byte exceeds data bits") { ok = false; }
  if !bits_eq(out2, bits("1010")) { ok = false; }
  return assert(ok, "uart_encode_byte_into appends exactly and is atomic on Err");
}

fn t10() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  let r = dec("0100000101", &c);
  var ok = r.is_ok;
  if ok {
    if r.value != 65 { ok = false; }
  }
  let r2 = dec("0100000101111", &c);
  if !r2.is_ok { ok = false; } else {
    if r2.value != 65 { ok = false; }
  }
  let r3 = dec_at("111110100000101", &c, 5);
  if !r3.is_ok { ok = false; } else {
    if r3.value != 65 { ok = false; }
  }
  let r4 = dec("0000000001", &c);
  if !r4.is_ok { ok = false; } else {
    if r4.value != 0 { ok = false; }
  }
  let r5 = dec("0111111111", &c);
  if !r5.is_ok { ok = false; } else {
    if r5.value != 255 { ok = false; }
  }
  return assert(ok, "decode extracts the byte and ignores bits after the frame");
}

fn t11() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var ok = err_int_is(dec("010000010", &c), "uart: truncated frame");
  if !err_int_is(dec("", &c), "uart: truncated frame") { ok = false; }
  if !err_int_is(dec_at("0100000101", &c, 5), "uart: truncated frame") { ok = false; }
  if !err_int_is(dec("1100000101", &c), "uart: false start bit") { ok = false; }
  if !err_int_is(dec("11111111111", &c), "uart: false start bit") { ok = false; }
  if !err_int_is(dec("0200000101", &c), "uart: invalid bit value") { ok = false; }
  if !err_int_is(dec("0100000102", &c), "uart: invalid bit value") { ok = false; }
  if !err_int_is(dec_at("0100000101", &c, -1), "uart: bad position") { ok = false; }
  let bad = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 2; flow: 7 };
  if !err_int_is(dec("0100000101", &bad), "uart: invalid flow control") { ok = false; }
  return assert(ok, "framing errors: truncation, false start, invalid bits, bad position");
}

fn t12() -> TestResult {
  let c = cfg(115200, 8, 1, 2, 0);
  let good = dec("01000001001", &c);
  var ok = good.is_ok;
  if ok {
    if good.value != 65 { ok = false; }
  }
  if !err_int_is(dec("01000001011", &c), "uart: parity mismatch") { ok = false; }
  if !err_int_is(dec("01000001000", &c), "uart: invalid stop bit") { ok = false; }
  let n2 = cfg(115200, 8, 0, 4, 0);
  let g2 = dec("01000001011", &n2);
  if !g2.is_ok { ok = false; } else {
    if g2.value != 65 { ok = false; }
  }
  if !err_int_is(dec("01000001010", &n2), "uart: invalid stop bit") { ok = false; }
  let m1 = cfg(115200, 8, 3, 2, 0);
  let gm = dec("00000000011", &m1);
  if !gm.is_ok { ok = false; } else {
    if gm.value != 0 { ok = false; }
  }
  if !err_int_is(dec("00000000001", &m1), "uart: parity mismatch") { ok = false; }
  let s1 = cfg(115200, 8, 4, 2, 0);
  let gs = dec("00000000001", &s1);
  if !gs.is_ok { ok = false; } else {
    if gs.value != 0 { ok = false; }
  }
  if !err_int_is(dec("00000000011", &s1), "uart: parity mismatch") { ok = false; }
  return assert(ok, "parity mismatch and invalid stop bits are detected");
}

fn t13() -> TestResult {
  let c9 = cfg(9600, 9, 0, 2, 0);
  let r = dec("01101010111", &c9);
  var ok = r.is_ok;
  if ok {
    if r.value != 427 { ok = false; }
  }
  let rmax = dec("01111111111", &c9);
  if !rmax.is_ok { ok = false; } else {
    if rmax.value != 511 { ok = false; }
  }
  let c5 = cfg(9600, 5, 0, 2, 0);
  let r5 = dec("0111111", &c5);
  if !r5.is_ok { ok = false; } else {
    if r5.value != 31 { ok = false; }
  }
  let r5z = dec("0000001", &c5);
  if !r5z.is_ok { ok = false; } else {
    if r5z.value != 0 { ok = false; }
  }
  return assert(ok, "9-bit and 5-bit data values decode exactly");
}

fn t14() -> TestResult {
  var ok = round_trip_config(115200, 8, 0, 2, 0);
  if !round_trip_config(115200, 8, 1, 2, 0) { ok = false; }
  if !round_trip_config(115200, 8, 2, 2, 0) { ok = false; }
  if !round_trip_config(115200, 8, 3, 2, 0) { ok = false; }
  if !round_trip_config(115200, 8, 4, 2, 0) { ok = false; }
  if !round_trip_config(9600, 7, 1, 4, 0) { ok = false; }
  if !round_trip_config(9600, 5, 0, 2, 0) { ok = false; }
  if !round_trip_config(9600, 9, 0, 2, 0) { ok = false; }
  if !round_trip_config(115200, 8, 0, 4, 0) { ok = false; }
  return assert(ok, "encode -> decode round-trips every value for nine configurations");
}

fn t15() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var vals = Vec[Int].new();
  vals.push(65);
  vals.push(0);
  let er = uart_encode_stream(&c, &vals);
  var ok = er.is_ok;
  if ok {
    let eb: Vec[UInt8] = er.value;
    if !bits_eq(eb, bits("1010000010100000000011")) { ok = false; }
  }
  let dr = dec_stream("1010000010100000000011", &c);
  if !dr.is_ok { ok = false; } else {
    if !ints_eq(dr.value, vals) { ok = false; }
  }
  return assert(ok, "stream encode pins idle + frames + idle and decodes back");
}

fn t16() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var all = Vec[Int].new();
  var i = 0;
  while i < 256 {
    all.push(i);
    i = i + 1;
  }
  let er = uart_encode_stream(&c, &all);
  var ok = er.is_ok;
  if ok {
    let eb_s: Vec[UInt8] = er.value;
    let dr = uart_decode_stream(&eb_s, &c);
    if !dr.is_ok { ok = false; } else {
      if !ints_eq(dr.value, all) { ok = false; }
    }
  }
  return assert(ok, "a 256-byte stream round-trips through encode_stream/decode_stream");
}

fn t17() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var bad = Vec[Int].new();
  bad.push(-1);
  var ok = err_bytes_is(uart_encode_stream(&c, &bad), "uart: byte out of range");
  var one = Vec[Int].new();
  one.push(256);
  if !err_bytes_is(uart_encode_stream(&c, &one), "uart: byte exceeds data bits") { ok = false; }
  let badc = UartConfig{ baud: 9600; data_bits: 8; parity: 0; stop_half: 2; flow: 7 };
  if !err_bytes_is(uart_encode_stream(&badc, &one), "uart: invalid flow control") { ok = false; }
  let c8e = cfg(115200, 8, 1, 2, 0);
  if !err_intvec_is(dec_stream("01000001011", &c8e), "uart: parity mismatch") { ok = false; }
  if !err_intvec_is(dec_stream("01000001000", &c8e), "uart: invalid stop bit") { ok = false; }
  if !err_intvec_is(dec_stream("010000010", &c8e), "uart: truncated frame") { ok = false; }
  if !err_intvec_is(dec_stream("12", &c8e), "uart: invalid bit value") { ok = false; }
  if !err_intvec_is(dec_stream("0", &c8e), "uart: truncated frame") { ok = false; }
  if !err_intvec_is(dec_stream("0100000101", &badc), "uart: invalid flow control") { ok = false; }
  return assert(ok, "stream codecs validate every frame and report the first error");
}

fn t18() -> TestResult {
  let c = cfg(115200, 8, 0, 2, 0);
  var empty = Vec[Int].new();
  let e0 = uart_encode_stream(&c, &empty);
  var ok = e0.is_ok;
  if ok {
    let eb0: Vec[UInt8] = e0.value;
    if !bits_eq(eb0, bits("11")) { ok = false; }
  }
  let d0 = dec_stream("11", &c);
  if !d0.is_ok { ok = false; } else {
    if d0.value.len() != 0 { ok = false; }
  }
  let d1 = dec_stream("111111", &c);
  if !d1.is_ok { ok = false; } else {
    if d1.value.len() != 0 { ok = false; }
  }
  let d2 = dec_stream("010000010100000000010100000101", &c);
  if !d2.is_ok { ok = false; } else {
    let got: Vec[Int] = d2.value;
    if got.len() != 3 { ok = false; } else {
      let g0: Int = got[0];
      let g1: Int = got[1];
      let g2: Int = got[2];
      if g0 != 65 { ok = false; }
      if g1 != 0 { ok = false; }
      if g2 != 65 { ok = false; }
    }
  }
  let d3 = dec_stream("1110100000101111", &c);
  if !d3.is_ok { ok = false; } else {
    let got3: Vec[Int] = d3.value;
    if got3.len() != 1 { ok = false; } else {
      let g: Int = got3[0];
      if g != 65 { ok = false; }
    }
  }
  return assert(ok, "idle-only and back-to-back streams decode; empty encodes to idle");
}

fn t19() -> TestResult {
  let b = bits("101");
  var ok = uart_bit_get(&b, 0) == 1;
  if uart_bit_get(&b, 1) != 0 { ok = false; }
  if uart_bit_get(&b, 2) != 1 { ok = false; }
  if uart_bit_get(&b, 3) != -1 { ok = false; }
  if uart_bit_get(&b, -1) != -1 { ok = false; }
  if uart_idle_bit() != 1 { ok = false; }
  let i0 = uart_idle_bits(0);
  if i0.len() != 0 { ok = false; }
  let i3 = uart_idle_bits(3);
  if !bits_eq(i3, bits("111")) { ok = false; }
  let im = uart_idle_bits(-1);
  if im.len() != 0 { ok = false; }
  let a = bits("0101");
  let b2 = bits("0101");
  let d = bits("0100");
  let e = bits("01011");
  if !uart_bits_equal(&a, &b2) { ok = false; }
  if uart_bits_equal(&a, &d) { ok = false; }
  if uart_bits_equal(&a, &e) { ok = false; }
  var raw = Vec[UInt8].new();
  raw.push(255);
  if uart_bit_get(&raw, 0) != 255 { ok = false; }
  return assert(ok, "bit accessors, idle helpers and bit equality are pinned");
}

fn t20() -> TestResult {
  var ok = uart_oversample_ok(4);
  if !uart_oversample_ok(8) { ok = false; }
  if !uart_oversample_ok(16) { ok = false; }
  if !uart_oversample_ok(32) { ok = false; }
  if uart_oversample_ok(3) { ok = false; }
  if uart_oversample_ok(64) { ok = false; }
  if uart_oversample_ok(0) { ok = false; }
  if uart_oversample_ok(-1) { ok = false; }
  if uart_sample_offset(16) != 8 { ok = false; }
  if uart_sample_offset(8) != 4 { ok = false; }
  if uart_sample_offset(4) != 2 { ok = false; }
  if uart_sample_offset(0) != -1 { ok = false; }
  if uart_bit_tick(3, 16) != 48 { ok = false; }
  if uart_mid_tick(3, 16) != 56 { ok = false; }
  if uart_mid_tick(0, 16) != 8 { ok = false; }
  if uart_tick_bit(55, 16) != 3 { ok = false; }
  if uart_tick_bit(48, 16) != 3 { ok = false; }
  if uart_tick_bit(47, 16) != 2 { ok = false; }
  if uart_tick_bit(-1, 16) != -1 { ok = false; }
  if uart_tick_bit(8, 0) != -1 { ok = false; }
  return assert(ok, "oversampling factors and sample ticks are pinned");
}

fn t21() -> TestResult {
  let d = uart_divisor(29491200, 115200, 16);
  var ok = d.is_ok;
  if ok {
    if d.value != 16 { ok = false; }
  }
  let dn = uart_divisor_nearest(29491200, 115200, 16);
  if !dn.is_ok { ok = false; } else {
    if dn.value != 16 { ok = false; }
  }
  let f = uart_divisor(16000000, 115200, 16);
  if !f.is_ok { ok = false; } else {
    if f.value != 8 { ok = false; }
  }
  let fn2 = uart_divisor_nearest(16000000, 115200, 16);
  if !fn2.is_ok { ok = false; } else {
    if fn2.value != 9 { ok = false; }
  }
  let exact = uart_baud_error_ppm(29491200, 115200, 16);
  if !exact.is_ok { ok = false; } else {
    if exact.value != 0 { ok = false; }
  }
  if !uart_baud_ok(29491200, 115200, 16, 0) { ok = false; }
  let nf = uart_baud_error_ppm(16000000, 115200, 16);
  if !nf.is_ok { ok = false; } else {
    if nf.value != -35493 { ok = false; }
  }
  let pf = uart_baud_error_ppm(4000000, 9600, 16);
  if !pf.is_ok { ok = false; } else {
    if pf.value != 1602 { ok = false; }
  }
  if !uart_baud_ok(16000000, 115200, 16, 40000) { ok = false; }
  if uart_baud_ok(16000000, 115200, 16, 1000) { ok = false; }
  if !uart_baud_ok(16000000, 115200, 16, 35493) { ok = false; }
  if !err_int_is(uart_divisor(0, 115200, 16), "uart: invalid clock") { ok = false; }
  if !err_int_is(uart_divisor(16000000, 0, 16), "uart: invalid baud") { ok = false; }
  if !err_int_is(uart_divisor(16000000, 115200, 3), "uart: invalid oversampling") { ok = false; }
  if !err_int_is(uart_divisor_nearest(16000000, 115200, 0), "uart: invalid oversampling") { ok = false; }
  if !err_int_is(uart_divisor(1000, 115200, 16), "uart: clock too slow") { ok = false; }
  if !err_int_is(uart_divisor_nearest(1000, 115200, 16), "uart: clock too slow") { ok = false; }
  if !err_int_is(uart_baud_error_ppm(1000, 115200, 16), "uart: clock too slow") { ok = false; }
  if uart_baud_ok(0, 115200, 16, 100000) { ok = false; }
  if uart_baud_ok(16000000, 115200, 16, -1) { ok = false; }
  return assert(ok, "baud divisors and fractional error in ppm are pinned");
}

fn main() -> Int {
  io.println("=== xiom.uart conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.uart: all tests passed");
  } else {
    io.println("xiom.uart: tests failed");
  }
  return failed;
}
