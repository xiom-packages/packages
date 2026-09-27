// XIOM -- xiom.spi conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pins the documented API against the xiom.spi SPEC.md: the mode/CPOL/CPHA
// table, bit order, word sizes and masks, chip-select semantics, the
// 16-entry prescaler table and clock selection, the event stream vocabulary,
// the pinned event-stream encodings for tx-only and full-duplex transfers,
// the full decode error catalog with byte offsets, word extraction in both
// bit orders, round-trips across 24 mode/word-size/bit-order combinations
// and encode/decode determinism.
//
// All buffers are built inside the tests (hex literals through
// xiom.encoding.hex or explicit pushes). Str values in the error checks go
// through xiom.string.compare.str_compare (BUG 17: `==` on a Str read from a
// Vec lowers to a pointer comparison).

module spi_tests
use xiom.io; use xiom.test;
use xiom.spi;
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

fn err_t_is(r: Result[SpiTransfer, SpiError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SpiError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_b_is(r: Result[Vec[UInt8], SpiError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SpiError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_c_is(r: Result[SpiConfig, SpiError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SpiError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

fn err_u_is(r: Result[Unit, SpiError], off: Int, msg: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: SpiError = r.error;
  let o: Int = e.offset;
  let m: Str = e.message;
  if o != off {
    return false;
  }
  return str_eq(m, msg);
}

// decode -> encode must reproduce the stream byte-for-byte.
fn decodes_to(stream: Vec[UInt8]) -> Bool {
  let d = spi_decode(&stream);
  if !d.is_ok {
    return false;
  }
  let x: SpiTransfer = d.value;
  let e = spi_encode(&x);
  if !e.is_ok {
    return false;
  }
  let out: Vec[UInt8] = e.value;
  return bytes_equal(out, stream);
}

// Full round-trip check: build, encode, decode, compare transfers, re-encode
// and compare bytes.
fn round_trip(cfg: SpiConfig, cs: Int, tx: Vec[UInt8], rx: Vec[UInt8]) -> Bool {
  let tr = spi_transfer_new(&cfg, cs, &tx, &rx);
  if !tr.is_ok {
    return false;
  }
  let x: SpiTransfer = tr.value;
  let e1 = spi_encode(&x);
  if !e1.is_ok {
    return false;
  }
  let s1: Vec[UInt8] = e1.value;
  let d1 = spi_decode(&s1);
  if !d1.is_ok {
    return false;
  }
  let y: SpiTransfer = d1.value;
  if !spi_equal(&x, &y) {
    return false;
  }
  let e2 = spi_encode(&y);
  if !e2.is_ok {
    return false;
  }
  let s2: Vec[UInt8] = e2.value;
  return bytes_equal(s1, s2);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = spi_mode_valid(0) && spi_mode_valid(1) && spi_mode_valid(2) && spi_mode_valid(3);
  if spi_mode_valid(-1) { ok = false; }
  if spi_mode_valid(4) { ok = false; }
  if spi_cpol(0) != 0 { ok = false; }
  if spi_cpol(1) != 0 { ok = false; }
  if spi_cpol(2) != 1 { ok = false; }
  if spi_cpol(3) != 1 { ok = false; }
  if spi_cpha(0) != 0 { ok = false; }
  if spi_cpha(1) != 1 { ok = false; }
  if spi_cpha(2) != 0 { ok = false; }
  if spi_cpha(3) != 1 { ok = false; }
  if spi_cpol(-1) != -1 { ok = false; }
  if spi_cpha(4) != -1 { ok = false; }
  if spi_mode_of(0, 0) != 0 { ok = false; }
  if spi_mode_of(0, 1) != 1 { ok = false; }
  if spi_mode_of(1, 0) != 2 { ok = false; }
  if spi_mode_of(1, 1) != 3 { ok = false; }
  if spi_mode_of(2, 0) != -1 { ok = false; }
  if spi_mode_of(0, -1) != -1 { ok = false; }
  return assert(ok, "mode 0..3 map to CPOL/CPHA and back");
}

fn t2() -> TestResult {
  var ok = str_eq(spi_mode_name(0), "CPOL=0 CPHA=0");
  if !str_eq(spi_mode_name(1), "CPOL=0 CPHA=1") { ok = false; }
  if !str_eq(spi_mode_name(2), "CPOL=1 CPHA=0") { ok = false; }
  if !str_eq(spi_mode_name(3), "CPOL=1 CPHA=1") { ok = false; }
  if !str_eq(spi_mode_name(9), "invalid mode") { ok = false; }
  let tab = spi_mode_table();
  if tab.len() != 8 { ok = false; }
  var m = 0;
  while m < 4 {
    let cpol: Int = tab[m * 2];
    let cpha: Int = tab[m * 2 + 1];
    if cpol != spi_cpol(m) { ok = false; }
    if cpha != spi_cpha(m) { ok = false; }
    m = m + 1;
  }
  return assert(ok, "mode names and the mode table are consistent");
}

fn t3() -> TestResult {
  var ok = spi_bit_order_valid(0) && spi_bit_order_valid(1);
  if spi_bit_order_valid(2) { ok = false; }
  if spi_bit_order_valid(-1) { ok = false; }
  if !str_eq(spi_bit_order_name(0), "MSB-first") { ok = false; }
  if !str_eq(spi_bit_order_name(1), "LSB-first") { ok = false; }
  if !str_eq(spi_bit_order_name(7), "invalid") { ok = false; }
  return assert(ok, "bit order 0/1 are MSB/LSB-first");
}

fn t4() -> TestResult {
  var ok = spi_word_size_valid(4) && spi_word_size_valid(8) && spi_word_size_valid(16);
  if spi_word_size_valid(3) { ok = false; }
  if spi_word_size_valid(17) { ok = false; }
  if spi_word_mask(4) != 15 { ok = false; }
  if spi_word_mask(8) != 255 { ok = false; }
  if spi_word_mask(12) != 4095 { ok = false; }
  if spi_word_mask(16) != 65535 { ok = false; }
  if spi_word_mask(3) != -1 { ok = false; }
  return assert(ok, "word size 4..16 with matching masks");
}

fn t5() -> TestResult {
  var ok = spi_cs_valid(-1) && spi_cs_valid(0) && spi_cs_valid(7);
  if spi_cs_valid(-2) { ok = false; }
  if spi_cs_valid(8) { ok = false; }
  if !str_eq(spi_cs_name(-1), "none") { ok = false; }
  if !str_eq(spi_cs_name(0), "cs0") { ok = false; }
  if !str_eq(spi_cs_name(7), "cs7") { ok = false; }
  if !str_eq(spi_cs_name(8), "invalid") { ok = false; }
  if spi_cs_line_level(3, true) != 0 { ok = false; }
  if spi_cs_line_level(3, false) != 1 { ok = false; }
  if spi_cs_line_level(-1, true) != -1 { ok = false; }
  if spi_cs_line_level(9, false) != -1 { ok = false; }
  if spi_cs_assert_level() != 0 { ok = false; }
  if spi_cs_idle_level() != 1 { ok = false; }
  return assert(ok, "chip select is active-low on lines 0..7 or none (-1)");
}

fn t6() -> TestResult {
  let tab = spi_prescaler_table();
  var ok = tab.len() == 16;
  if spi_prescaler_count() != 16 { ok = false; }
  var i = 0;
  var want = 2;
  while i < 16 {
    let d: Int = tab[i];
    if d != want { ok = false; }
    if spi_clock_divider(i) != want { ok = false; }
    if spi_divider_index(want) != i { ok = false; }
    want = want * 2;
    i = i + 1;
  }
  if tab[0] != 2 { ok = false; }
  if tab[15] != 65536 { ok = false; }
  if spi_clock_divider(-1) != -1 { ok = false; }
  if spi_clock_divider(16) != -1 { ok = false; }
  if spi_divider_index(3) != -1 { ok = false; }
  if spi_divider_index(131072) != -1 { ok = false; }
  return assert(ok, "prescaler table is 2^1..2^16 with index round-trip");
}

fn t7() -> TestResult {
  var ok = spi_clock_hz(16000000, 0) == 8000000;
  if spi_clock_hz(16000000, 1) != 4000000 { ok = false; }
  if spi_clock_hz(16000000, 2) != 2000000 { ok = false; }
  if spi_clock_hz(16000000, 3) != 1000000 { ok = false; }
  if spi_clock_hz(16000000, 15) != 244 { ok = false; }
  if spi_clock_hz(16000000, 16) != -1 { ok = false; }
  if spi_clock_hz(0, 0) != -1 { ok = false; }
  if spi_clock_hz(-1, 0) != -1 { ok = false; }
  return assert(ok, "clock = bus / divider with floor division");
}

fn t8() -> TestResult {
  var ok = spi_prescaler_for(16000000, 5000000) == 1;
  if spi_prescaler_for(16000000, 8000000) != 0 { ok = false; }
  if spi_prescaler_for(16000000, 2000000) != 2 { ok = false; }
  if spi_prescaler_for(16000000, 300) != 15 { ok = false; }
  if spi_prescaler_for(16000000, 100) != -1 { ok = false; }
  if spi_prescaler_for(0, 1000) != -1 { ok = false; }
  if spi_prescaler_for(16000000, 0) != -1 { ok = false; }
  if spi_prescaler_for(16000000, 16000000) != 0 { ok = false; }
  return assert(ok, "smallest prescaler that keeps the clock <= max_hz");
}

fn t9() -> TestResult {
  var ok = str_eq(spi_event_name(1), "CONFIG");
  if spi_event_size(1) != 4 { ok = false; }
  if !str_eq(spi_event_name(2), "CS_ASSERT") { ok = false; }
  if spi_event_size(2) != 2 { ok = false; }
  if !str_eq(spi_event_name(3), "CS_DEASSERT") { ok = false; }
  if spi_event_size(3) != 2 { ok = false; }
  if !str_eq(spi_event_name(4), "TX") { ok = false; }
  if spi_event_size(4) != 2 { ok = false; }
  if !str_eq(spi_event_name(5), "RX") { ok = false; }
  if spi_event_size(5) != 2 { ok = false; }
  if !str_eq(spi_event_name(6), "END") { ok = false; }
  if spi_event_size(6) != 1 { ok = false; }
  if !str_eq(spi_event_name(0), "unknown") { ok = false; }
  if spi_event_size(7) != -1 { ok = false; }
  return assert(ok, "event types have stable names and sizes");
}

fn t10() -> TestResult {
  let tx = hb("dead");
  let tr = spi_transfer(0, 2, &tx);
  var ok = tr.is_ok;
  if ok {
    let x: SpiTransfer = tr.value;
    if spi_transfer_mode(&x) != 0 { ok = false; }
    if spi_transfer_word_size(&x) != 8 { ok = false; }
    if spi_transfer_bit_order(&x) != 0 { ok = false; }
    if spi_transfer_cs(&x) != 2 { ok = false; }
    if spi_tx_len(&x) != 2 { ok = false; }
    if spi_rx_len(&x) != 0 { ok = false; }
    if spi_word_count(&x) != 2 { ok = false; }
    if spi_is_full_duplex(&x) { ok = false; }
    let e = spi_encode(&x);
    if !e.is_ok { ok = false; } else {
      let s: Vec[UInt8] = e.value;
      if !bytes_equal(s, hb("01000800020204de04ad030206")) { ok = false; }
      let d = spi_decode(&s);
      if !d.is_ok { ok = false; } else {
        let y: SpiTransfer = d.value;
        if !spi_equal(&x, &y) { ok = false; }
      }
    }
  }
  return assert(ok, "mode 0 / cs 2 / tx 2 bytes encodes to pinned bytes and back");
}

fn t11() -> TestResult {
  let cfg = SpiConfig{ mode: 3; word_size: 8; bit_order: 1; };
  let tx = hb("010203");
  let z = empty();
  let tr = spi_transfer_new(&cfg, 0, &tx, &z);
  var ok = tr.is_ok;
  if ok {
    let x: SpiTransfer = tr.value;
    let e = spi_encode(&x);
    if !e.is_ok { ok = false; } else {
      let s: Vec[UInt8] = e.value;
      if !bytes_equal(s, hb("010308010200040104020403030006")) { ok = false; }
      let d = spi_decode(&s);
      if !d.is_ok { ok = false; } else {
        let y: SpiTransfer = d.value;
        if !spi_equal(&x, &y) { ok = false; }
      }
    }
  }
  return assert(ok, "LSB-first mode 3 / cs 0 encodes to pinned bytes and back");
}

fn t12() -> TestResult {
  let tx = hb("1234");
  let z = empty();
  let cm = SpiConfig{ mode: 0; word_size: 4; bit_order: 0; };
  let cl = SpiConfig{ mode: 0; word_size: 4; bit_order: 1; };
  let trm = spi_transfer_new(&cm, -1, &tx, &z);
  let trl = spi_transfer_new(&cl, -1, &tx, &z);
  var ok = trm.is_ok && trl.is_ok;
  if ok {
    let x: SpiTransfer = trm.value;
    let y: SpiTransfer = trl.value;
    if spi_word_count(&x) != 4 { ok = false; }
    if spi_word_at(&x, 0) != 1 { ok = false; }
    if spi_word_at(&x, 1) != 2 { ok = false; }
    if spi_word_at(&x, 2) != 3 { ok = false; }
    if spi_word_at(&x, 3) != 4 { ok = false; }
    if spi_word_at(&x, 4) != -1 { ok = false; }
    if spi_word_at(&x, -1) != -1 { ok = false; }
    if spi_word_count(&y) != 4 { ok = false; }
    if spi_word_at(&y, 0) != 2 { ok = false; }
    if spi_word_at(&y, 1) != 1 { ok = false; }
    if spi_word_at(&y, 2) != 4 { ok = false; }
    if spi_word_at(&y, 3) != 3 { ok = false; }
  }
  return assert(ok, "4-bit words split MSB-first 1,2,3,4 and LSB-first 2,1,4,3");
}

fn t13() -> TestResult {
  let tx = hb("1234");
  let z = empty();
  let cm = SpiConfig{ mode: 0; word_size: 16; bit_order: 0; };
  let cl = SpiConfig{ mode: 0; word_size: 16; bit_order: 1; };
  let trm = spi_transfer_new(&cm, -1, &tx, &z);
  let trl = spi_transfer_new(&cl, -1, &tx, &z);
  var ok = trm.is_ok && trl.is_ok;
  if ok {
    let a: SpiTransfer = trm.value;
    let b: SpiTransfer = trl.value;
    if spi_word_count(&a) != 1 { ok = false; }
    if spi_word_at(&a, 0) != 4660 { ok = false; }
    if spi_word_at(&a, 1) != -1 { ok = false; }
    if spi_word_count(&b) != 1 { ok = false; }
    if spi_word_at(&b, 0) != 13330 { ok = false; }
    if spi_word_at(&b, 1) != -1 { ok = false; }
  }
  return assert(ok, "16-bit word is 0x1234 MSB-first and 0x3412 LSB-first");
}

fn t14() -> TestResult {
  let z = empty();
  let tx3 = hb("010203");
  let tx2 = hb("0102");
  let c12 = SpiConfig{ mode: 0; word_size: 12; bit_order: 0; };
  var ok = spi_transfer_new(&c12, -1, &tx3, &z).is_ok;
  if !err_t_is(spi_transfer_new(&c12, -1, &tx2, &z), -1, "spi: length mismatch") { ok = false; }
  let c5 = SpiConfig{ mode: 0; word_size: 5; bit_order: 0; };
  let tx5 = hb("0102030405");
  if !spi_transfer_new(&c5, -1, &tx5, &z).is_ok { ok = false; }
  if !err_t_is(spi_transfer_new(&c5, -1, &tx2, &z), -1, "spi: length mismatch") { ok = false; }
  let c8 = SpiConfig{ mode: 0; word_size: 8; bit_order: 0; };
  let rx1 = hb("aa");
  if !err_t_is(spi_transfer_new(&c8, 0, &tx3, &rx1), -1, "spi: length mismatch") { ok = false; }
  let rx3 = hb("aabbcc");
  if !spi_transfer_new(&c8, 0, &tx3, &rx3).is_ok { ok = false; }
  if !spi_transfer_new(&c8, 0, &tx3, &z).is_ok { ok = false; }
  return assert(ok, "word-size divisibility and rx/tx length rules");
}

fn t15() -> TestResult {
  var ok = err_t_is(spi_decode(&empty()), 0, "spi: truncated stream");
  if !err_t_is(spi_decode(&hb("00")), 0, "spi: missing config") { ok = false; }
  if !err_t_is(spi_decode(&hb("01")), 1, "spi: truncated stream") { ok = false; }
  if !err_t_is(spi_decode(&hb("0100")), 2, "spi: truncated stream") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008")), 3, "spi: truncated stream") { ok = false; }
  if !err_t_is(spi_decode(&hb("01040800")), 1, "spi: invalid mode") { ok = false; }
  if !err_t_is(spi_decode(&hb("01000300")), 2, "spi: invalid word size") { ok = false; }
  if !err_t_is(spi_decode(&hb("01001100")), 2, "spi: invalid word size") { ok = false; }
  if !err_t_is(spi_decode(&hb("01000802")), 3, "spi: invalid bit order") { ok = false; }
  return assert(ok, "decode header errors carry field offsets 0..3");
}

fn t16() -> TestResult {
  var ok = err_t_is(spi_decode(&hb("0100080007")), 4, "spi: unknown event");
  if !err_t_is(spi_decode(&hb("0100080001")), 4, "spi: unexpected event") { ok = false; }
  if !err_t_is(spi_decode(&hb("0100080002")), 5, "spi: truncated stream") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008000208")), 5, "spi: invalid chip select") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008000300")), 4, "spi: chip select not asserted") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008000500")), 4, "spi: length mismatch") { ok = false; }
  return assert(ok, "event-level decode errors carry the event offset");
}

fn t17() -> TestResult {
  var ok = err_t_is(spi_decode(&hb("010008000201030206")), 7, "spi: chip select mismatch");
  if !err_t_is(spi_decode(&hb("010008000201040906")), 8, "spi: cs left asserted") { ok = false; }
  if !err_t_is(spi_decode(&hb("0100080004010402050306")), 10, "spi: length mismatch") { ok = false; }
  if !err_t_is(spi_decode(&hb("01000500040106")), 6, "spi: length mismatch") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008000600")), 5, "spi: trailing bytes") { ok = false; }
  if !err_t_is(spi_decode(&hb("01000800020104090301040206")), 10, "spi: unexpected event") { ok = false; }
  if !err_t_is(spi_decode(&hb("010008000201020206")), 6, "spi: unexpected event") { ok = false; }
  return assert(ok, "cs pairing, word-count and trailing-byte errors at END");
}

fn t18() -> TestResult {
  let a = hb("0100080004ab06");
  let b = hb("010008000200030006");
  let c = hb("0100080006");
  let d = hb("01010800020304aa0555030306");
  var ok = decodes_to(a);
  if !decodes_to(b) { ok = false; }
  if !decodes_to(c) { ok = false; }
  if !decodes_to(d) { ok = false; }
  let da = spi_decode(&a);
  if !da.is_ok { ok = false; } else {
    let x: SpiTransfer = da.value;
    if x.cs != -1 { ok = false; }
    if spi_tx_len(&x) != 1 { ok = false; }
    let b0: Int = (x.tx[0] as Int) & 0xFF;
    if b0 != 171 { ok = false; }
  }
  let dd = spi_decode(&d);
  if !dd.is_ok { ok = false; } else {
    let y: SpiTransfer = dd.value;
    if y.cs != 3 { ok = false; }
    if !spi_is_full_duplex(&y) { ok = false; }
    if spi_rx_len(&y) != 1 { ok = false; }
    let r0: Int = (y.rx[0] as Int) & 0xFF;
    if r0 != 85 { ok = false; }
  }
  return assert(ok, "3-wire, empty and full-duplex streams decode and re-encode");
}

fn t19() -> TestResult {
  let tx = hb("aa");
  let cm = SpiConfig{ mode: 4; word_size: 8; bit_order: 0; };
  let tm = SpiTransfer{ config: cm; cs: 0; tx: tx; rx: empty() };
  var ok = err_b_is(spi_encode(&tm), -1, "spi: invalid mode");
  let cw = SpiConfig{ mode: 0; word_size: 17; bit_order: 0; };
  let tw = SpiTransfer{ config: cw; cs: 0; tx: tx; rx: empty() };
  if !err_b_is(spi_encode(&tw), -1, "spi: invalid word size") { ok = false; }
  let cb = SpiConfig{ mode: 0; word_size: 8; bit_order: 2; };
  let tb = SpiTransfer{ config: cb; cs: 0; tx: tx; rx: empty() };
  if !err_b_is(spi_encode(&tb), -1, "spi: invalid bit order") { ok = false; }
  let ck = SpiConfig{ mode: 0; word_size: 8; bit_order: 0; };
  let tc = SpiTransfer{ config: ck; cs: 8; tx: tx; rx: empty() };
  if !err_b_is(spi_encode(&tc), -1, "spi: invalid chip select") { ok = false; }
  if !err_u_is(spi_validate(&tc), -1, "spi: invalid chip select") { ok = false; }
  let rx2 = hb("aabb");
  let tl = SpiTransfer{ config: ck; cs: 0; tx: tx; rx: rx2 };
  if !err_b_is(spi_encode(&tl), -1, "spi: length mismatch") { ok = false; }
  let c5 = SpiConfig{ mode: 0; word_size: 5; bit_order: 0; };
  let t5 = SpiTransfer{ config: c5; cs: 0; tx: tx; rx: empty() };
  if !err_b_is(spi_encode(&t5), -1, "spi: length mismatch") { ok = false; }
  if !err_u_is(spi_validate(&t5), -1, "spi: length mismatch") { ok = false; }
  if !err_t_is(spi_transfer(4, 0, &tx), -1, "spi: invalid mode") { ok = false; }
  if !err_t_is(spi_transfer(0, 8, &tx), -1, "spi: invalid chip select") { ok = false; }
  return assert(ok, "encode and validate report input errors with offset -1");
}

fn t20() -> TestResult {
  let r = spi_config_new(2, 12, 1);
  var ok = r.is_ok;
  if ok {
    let c: SpiConfig = r.value;
    if c.mode != 2 { ok = false; }
    if c.word_size != 12 { ok = false; }
    if c.bit_order != 1 { ok = false; }
  }
  if !err_c_is(spi_config_new(4, 8, 0), -1, "spi: invalid mode") { ok = false; }
  if !err_c_is(spi_config_new(0, 3, 0), -1, "spi: invalid word size") { ok = false; }
  if !err_c_is(spi_config_new(0, 8, 3), -1, "spi: invalid bit order") { ok = false; }
  return assert(ok, "config constructor accepts valid fields and reports invalid ones");
}

fn t21() -> TestResult {
  let tx = hb("0f1e2d3c4b5a6978");
  var ok = true;
  var m = 0;
  while m < 4 {
    var bo = 0;
    while bo < 2 {
      let c8 = SpiConfig{ mode: m; word_size: 8; bit_order: bo; };
      if !round_trip(c8, 3, tx, empty()) { ok = false; }
      let c4 = SpiConfig{ mode: m; word_size: 4; bit_order: bo; };
      if !round_trip(c4, -1, tx, empty()) { ok = false; }
      let c16 = SpiConfig{ mode: m; word_size: 16; bit_order: bo; };
      if !round_trip(c16, 7, tx, empty()) { ok = false; }
      bo = bo + 1;
    }
    m = m + 1;
  }
  let tx3 = hb("0f1e2d");
  let rx3 = hb("a1b2c3");
  let cf = SpiConfig{ mode: 1; word_size: 12; bit_order: 1; };
  if !round_trip(cf, 5, tx3, rx3) { ok = false; }
  return assert(ok, "mode/word-size/bit-order combinations round-trip byte-for-byte");
}

fn t22() -> TestResult {
  let tx = hb("cafebabe");
  let tr = spi_transfer(3, 7, &tx);
  var ok = tr.is_ok;
  if ok {
    let x: SpiTransfer = tr.value;
    let e1 = spi_encode(&x);
    let e2 = spi_encode(&x);
    if !e1.is_ok || !e2.is_ok { ok = false; } else {
      let a: Vec[UInt8] = e1.value;
      let b: Vec[UInt8] = e2.value;
      if !bytes_equal(a, b) { ok = false; }
      let d1 = spi_decode(&a);
      let d2 = spi_decode(&a);
      if !d1.is_ok || !d2.is_ok { ok = false; } else {
        let p: SpiTransfer = d1.value;
        let q: SpiTransfer = d2.value;
        if !spi_equal(&p, &q) { ok = false; }
        if !spi_equal(&x, &p) { ok = false; }
      }
    }
  }
  return assert(ok, "repeated encode/decode calls agree byte for byte");
}

fn main() -> Int {
  io.println("=== xiom.spi conformance tests ===");
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
    io.println("xiom.spi: all tests passed");
  } else {
    io.println("xiom.spi: tests failed");
  }
  return failed;
}
