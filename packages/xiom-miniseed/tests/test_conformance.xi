// XIOM -- xiom.miniseed conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.miniseed codec against the rules
// pinned in SPEC.md: the fixed 48-byte big-endian header, the caller-supplied
// record size, the payload span, the documented sample-rate interpretation
// and micro-Hz rounding, the sample-count policy, the validation order, the
// error catalog and the canonical header builder.
//
// All fixtures are assembled byte by byte in this file, so miniseed_parse is
// exercised against bytes the test controls rather than only against
// miniseed_build. Str comparisons go through xiom.string.compare's
// str_compare (BUG 17: `==` on Str values read from Vec elements lowers to a
// pointer comparison); every Vec element read is bound to an explicitly
// typed local and every `&` argument is a local binding (never a field or a
// call result).

module miniseed_tests
use xiom.io; use xiom.test;
use xiom.miniseed;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Byte helpers (independent of src/miniseed.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_padded(v: &mut Vec[UInt8], s: Str, width: Int) {
  var i = 0;
  while i < width {
    if i < s.len() {
      v.push(string.byte_at(s, i));
    } else {
      v.push(32 as UInt8);
    }
    i = i + 1;
  }
}

fn push_be16(v: &mut Vec[UInt8], val: Int) {
  v.push(((val / 256) % 256) as UInt8);
  v.push((val % 256) as UInt8);
}

fn push_be32(v: &mut Vec[UInt8], val: Int) {
  v.push(((val / 16777216) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push((val % 256) as UInt8);
}

fn push_be16_signed(v: &mut Vec[UInt8], val: Int) {
  var u = val;
  if u < 0 { u = u + 65536; }
  push_be16(v, u);
}

fn push_be32_signed(v: &mut Vec[UInt8], val: Int) {
  var u = val;
  if u < 0 { u = u + 4294967296; }
  push_be32(v, u);
}

fn signed16(val: Int) -> Int {
  if val < 0 { return val + 65536; }
  return val;
}

fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_be16(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(((val / 256) % 256) as UInt8);
    } elif i == pos + 1 {
      out.push((val % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn slice_of(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < count {
    out.push(v[start + i]);
    i = i + 1;
  }
  return out;
}

// Fill `v` from its current length up to `end` with the byte pattern
// (index * 7 + 3) mod 256, so every payload byte is position-dependent.
fn fill_pattern(v: &mut Vec[UInt8], end: Int) {
  while v.len() < end {
    let b: Int = (v.len() * 7 + 3) % 256;
    v.push(b as UInt8);
  }
}

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn err_header_is(r: Result[MseedHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// --------------------------------------------------
//  Fixtures
//  (assembled byte by byte; every field value is pinned below)
// --------------------------------------------------

// 512-byte record: 48-byte header + 464 payload bytes = 116 samples of 4
// bytes. Sequence 000042, quality D, station ANMO, channel BHZ, network IU,
// location 00, 2026-09-24 12:34:56.1234 (day 267), factor 40, multiplier 1
// (40 Hz), no blockettes, data offset 48.
fn fixture512() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_padded(&mut v, "000042", 6);
  v.push(68 as UInt8);
  v.push(32 as UInt8);
  push_padded(&mut v, "ANMO", 5);
  push_padded(&mut v, "BHZ", 3);
  push_padded(&mut v, "IU", 2);
  push_padded(&mut v, "00", 2);
  push_be16(&mut v, 2026);
  push_be16(&mut v, 267);
  v.push(12 as UInt8);
  v.push(34 as UInt8);
  v.push(56 as UInt8);
  v.push(0 as UInt8);
  push_be16(&mut v, 1234);
  push_be16(&mut v, 40);
  push_be16(&mut v, 1);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  push_be32(&mut v, 0);
  push_be16(&mut v, 48);
  push_be16(&mut v, 0);
  push_be16(&mut v, 0);
  fill_pattern(&mut v, 512);
  return v;
}

// 4096-byte record: 48-byte header + 8-byte blockette 1000 (Steim-2, big
// endian, 2^12 length) + 8 alignment bytes + 4032 payload bytes = 1008
// samples of 4 bytes. Sequence 000007, quality Q, station KMBO, channel LHN,
// network G, empty location, 2024-12-31 23:59:60.9999 (day 366, leap year),
// factor -1, multiplier -100 (1/100 Hz), one blockette at 48, data at 64.
fn fixture4096() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_padded(&mut v, "000007", 6);
  v.push(81 as UInt8);
  v.push(32 as UInt8);
  push_padded(&mut v, "KMBO", 5);
  push_padded(&mut v, "LHN", 3);
  push_padded(&mut v, "G", 2);
  push_padded(&mut v, "", 2);
  push_be16(&mut v, 2024);
  push_be16(&mut v, 366);
  v.push(23 as UInt8);
  v.push(59 as UInt8);
  v.push(60 as UInt8);
  v.push(0 as UInt8);
  push_be16(&mut v, 9999);
  push_be16_signed(&mut v, -1);
  push_be16_signed(&mut v, -100);
  v.push(5 as UInt8);
  v.push(9 as UInt8);
  v.push(17 as UInt8);
  v.push(1 as UInt8);
  push_be32_signed(&mut v, -250);
  push_be16(&mut v, 64);
  push_be16(&mut v, 48);
  push_be16(&mut v, 0);
  v.push(3 as UInt8);
  v.push(232 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  v.push(11 as UInt8);
  v.push(0 as UInt8);
  v.push(12 as UInt8);
  v.push(0 as UInt8);
  push_zeros(&mut v, 8);
  fill_pattern(&mut v, 4096);
  return v;
}

// A copy of the 512 fixture with the first blockette present (offset 48) and
// the data moved to 64, so the blockette-offset policy is exercised.
fn fixture_with_blockette() -> Vec[UInt8] {
  var v = set_be16(fixture512(), 42, 64);
  v = set_be16(v, 44, 48);
  v = set_byte(v, 37, 1);
  return v;
}

// A copy of the 512 fixture with a different factor/multiplier pair; the
// values are written as i16 two's-complement bytes.
fn rate_fixture(f: Int, m: Int) -> Vec[UInt8] {
  let a = set_be16(fixture512(), 30, signed16(f));
  return set_be16(a, 32, signed16(m));
}

// --------------------------------------------------
//  MseedHeader copy helpers (one per field group)
// --------------------------------------------------

fn with_text(h: &MseedHeader, sequence: Str, quality: Int, station: Str, channel: Str, network: Str, location: Str) -> MseedHeader {
  let out = MseedHeader{
    sequence: sequence;
    quality: quality;
    reserved: h.reserved;
    station: station;
    channel: channel;
    network: network;
    location: location;
    year: h.year;
    day: h.day;
    hour: h.hour;
    minute: h.minute;
    second: h.second;
    unused: h.unused;
    tenths: h.tenths;
    sample_rate_factor: h.sample_rate_factor;
    sample_rate_multiplier: h.sample_rate_multiplier;
    activity_flags: h.activity_flags;
    io_flags: h.io_flags;
    data_quality_flags: h.data_quality_flags;
    num_blockettes: h.num_blockettes;
    time_correction: h.time_correction;
    begin_data_offset: h.begin_data_offset;
    begin_blockette_offset: h.begin_blockette_offset;
    reserved2: h.reserved2;
    record_size: h.record_size;
  };
  return out;
}

fn with_reserved(h: &MseedHeader, reserved: Int) -> MseedHeader {
  let out = MseedHeader{
    sequence: h.sequence;
    quality: h.quality;
    reserved: reserved;
    station: h.station;
    channel: h.channel;
    network: h.network;
    location: h.location;
    year: h.year;
    day: h.day;
    hour: h.hour;
    minute: h.minute;
    second: h.second;
    unused: h.unused;
    tenths: h.tenths;
    sample_rate_factor: h.sample_rate_factor;
    sample_rate_multiplier: h.sample_rate_multiplier;
    activity_flags: h.activity_flags;
    io_flags: h.io_flags;
    data_quality_flags: h.data_quality_flags;
    num_blockettes: h.num_blockettes;
    time_correction: h.time_correction;
    begin_data_offset: h.begin_data_offset;
    begin_blockette_offset: h.begin_blockette_offset;
    reserved2: h.reserved2;
    record_size: h.record_size;
  };
  return out;
}

fn with_time(h: &MseedHeader, year: Int, day: Int, hour: Int, minute: Int, second: Int, tenths: Int) -> MseedHeader {
  let out = MseedHeader{
    sequence: h.sequence;
    quality: h.quality;
    reserved: h.reserved;
    station: h.station;
    channel: h.channel;
    network: h.network;
    location: h.location;
    year: year;
    day: day;
    hour: hour;
    minute: minute;
    second: second;
    unused: h.unused;
    tenths: tenths;
    sample_rate_factor: h.sample_rate_factor;
    sample_rate_multiplier: h.sample_rate_multiplier;
    activity_flags: h.activity_flags;
    io_flags: h.io_flags;
    data_quality_flags: h.data_quality_flags;
    num_blockettes: h.num_blockettes;
    time_correction: h.time_correction;
    begin_data_offset: h.begin_data_offset;
    begin_blockette_offset: h.begin_blockette_offset;
    reserved2: h.reserved2;
    record_size: h.record_size;
  };
  return out;
}

fn with_rate(h: &MseedHeader, factor: Int, multiplier: Int) -> MseedHeader {
  let out = MseedHeader{
    sequence: h.sequence;
    quality: h.quality;
    reserved: h.reserved;
    station: h.station;
    channel: h.channel;
    network: h.network;
    location: h.location;
    year: h.year;
    day: h.day;
    hour: h.hour;
    minute: h.minute;
    second: h.second;
    unused: h.unused;
    tenths: h.tenths;
    sample_rate_factor: factor;
    sample_rate_multiplier: multiplier;
    activity_flags: h.activity_flags;
    io_flags: h.io_flags;
    data_quality_flags: h.data_quality_flags;
    num_blockettes: h.num_blockettes;
    time_correction: h.time_correction;
    begin_data_offset: h.begin_data_offset;
    begin_blockette_offset: h.begin_blockette_offset;
    reserved2: h.reserved2;
    record_size: h.record_size;
  };
  return out;
}

fn with_flags(h: &MseedHeader, activity: Int, io_flags: Int, dq_flags: Int, nblk: Int, tc: Int) -> MseedHeader {
  let out = MseedHeader{
    sequence: h.sequence;
    quality: h.quality;
    reserved: h.reserved;
    station: h.station;
    channel: h.channel;
    network: h.network;
    location: h.location;
    year: h.year;
    day: h.day;
    hour: h.hour;
    minute: h.minute;
    second: h.second;
    unused: h.unused;
    tenths: h.tenths;
    sample_rate_factor: h.sample_rate_factor;
    sample_rate_multiplier: h.sample_rate_multiplier;
    activity_flags: activity;
    io_flags: io_flags;
    data_quality_flags: dq_flags;
    num_blockettes: nblk;
    time_correction: tc;
    begin_data_offset: h.begin_data_offset;
    begin_blockette_offset: h.begin_blockette_offset;
    reserved2: h.reserved2;
    record_size: h.record_size;
  };
  return out;
}

fn with_sizes(h: &MseedHeader, bdo: Int, bbo: Int, record_size: Int) -> MseedHeader {
  let out = MseedHeader{
    sequence: h.sequence;
    quality: h.quality;
    reserved: h.reserved;
    station: h.station;
    channel: h.channel;
    network: h.network;
    location: h.location;
    year: h.year;
    day: h.day;
    hour: h.hour;
    minute: h.minute;
    second: h.second;
    unused: h.unused;
    tenths: h.tenths;
    sample_rate_factor: h.sample_rate_factor;
    sample_rate_multiplier: h.sample_rate_multiplier;
    activity_flags: h.activity_flags;
    io_flags: h.io_flags;
    data_quality_flags: h.data_quality_flags;
    num_blockettes: h.num_blockettes;
    time_correction: h.time_correction;
    begin_data_offset: bdo;
    begin_blockette_offset: bbo;
    reserved2: h.reserved2;
    record_size: record_size;
  };
  return out;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = streq(miniseed_sequence(&h), "000042");
  if !streq(miniseed_station(&h), "ANMO") { ok = false; }
  if !streq(miniseed_channel(&h), "BHZ") { ok = false; }
  if !streq(miniseed_network(&h), "IU") { ok = false; }
  if !streq(miniseed_location(&h), "00") { ok = false; }
  if miniseed_quality(&h) != 68 { ok = false; }
  if miniseed_reserved(&h) != 32 { ok = false; }
  if miniseed_record_size(&h) != 512 { ok = false; }
  return assert(ok, "header identity fields decode and text is trimmed");
}

fn t2() -> TestResult {
  var v = fixture512();
  v = set_byte(v, 0, 32);
  v = set_byte(v, 1, 52);
  v = set_byte(v, 2, 50);
  v = set_byte(v, 3, 32);
  v = set_byte(v, 4, 32);
  v = set_byte(v, 5, 32);
  v = set_byte(v, 18, 32);
  v = set_byte(v, 19, 32);
  let pr = miniseed_parse(&v);
  if !pr.is_ok { return assert(false, "padded fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = streq(miniseed_sequence(&h), "42");
  if !streq(miniseed_station(&h), "ANMO") { ok = false; }
  if !streq(miniseed_location(&h), "") { ok = false; }
  if !streq(miniseed_network(&h), "IU") { ok = false; }
  var w = fixture512();
  w = set_byte(w, 0, 32);
  w = set_byte(w, 1, 32);
  w = set_byte(w, 2, 32);
  w = set_byte(w, 3, 32);
  w = set_byte(w, 4, 32);
  w = set_byte(w, 5, 32);
  let pr2 = miniseed_parse(&w);
  if !pr2.is_ok { return assert(false, "blank-sequence fixture must parse"); }
  let h2: MseedHeader = pr2.value;
  if !streq(miniseed_sequence(&h2), "") { ok = false; }
  return assert(ok, "text accessors trim surrounding spaces");
}

fn t3() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_year(&h) == 2026;
  if miniseed_day(&h) != 267 { ok = false; }
  if miniseed_hour(&h) != 12 { ok = false; }
  if miniseed_minute(&h) != 34 { ok = false; }
  if miniseed_second(&h) != 56 { ok = false; }
  if miniseed_unused(&h) != 0 { ok = false; }
  if miniseed_tenths(&h) != 1234 { ok = false; }
  let data2 = fixture4096();
  let pr2 = miniseed_parse(&data2);
  if !pr2.is_ok { return assert(false, "4096 fixture must parse"); }
  let h2: MseedHeader = pr2.value;
  if miniseed_year(&h2) != 2024 { ok = false; }
  if miniseed_day(&h2) != 366 { ok = false; }
  if miniseed_hour(&h2) != 23 { ok = false; }
  if miniseed_minute(&h2) != 59 { ok = false; }
  if miniseed_second(&h2) != 60 { ok = false; }
  if miniseed_tenths(&h2) != 9999 { ok = false; }
  return assert(ok, "start time components decode big-endian");
}

fn t4() -> TestResult {
  var ok = true;
  let a = rate_fixture(40, 1);
  let pa = miniseed_parse(&a);
  if !pa.is_ok { return assert(false, "40/1 must parse"); }
  let ha: MseedHeader = pa.value;
  if miniseed_sample_rate_factor(&ha) != 40 { ok = false; }
  if miniseed_sample_rate_multiplier(&ha) != 1 { ok = false; }
  if miniseed_rate_num(&ha) != 40 { ok = false; }
  if miniseed_rate_den(&ha) != 1 { ok = false; }
  if miniseed_rate_microhz(&ha) != 40000000 { ok = false; }
  let b = rate_fixture(40, -2);
  let pb = miniseed_parse(&b);
  if !pb.is_ok { return assert(false, "40/-2 must parse"); }
  let hb: MseedHeader = pb.value;
  if miniseed_rate_num(&hb) != 40 { ok = false; }
  if miniseed_rate_den(&hb) != 2 { ok = false; }
  if miniseed_rate_microhz(&hb) != 20000000 { ok = false; }
  let c = rate_fixture(-100, 1);
  let pc = miniseed_parse(&c);
  if !pc.is_ok { return assert(false, "-100/1 must parse"); }
  let hc: MseedHeader = pc.value;
  if miniseed_rate_num(&hc) != 1 { ok = false; }
  if miniseed_rate_den(&hc) != 100 { ok = false; }
  if miniseed_rate_microhz(&hc) != 10000 { ok = false; }
  let d = rate_fixture(-1, -100);
  let pd = miniseed_parse(&d);
  if !pd.is_ok { return assert(false, "-1/-100 must parse"); }
  let hd: MseedHeader = pd.value;
  if miniseed_rate_num(&hd) != 1 { ok = false; }
  if miniseed_rate_den(&hd) != 100 { ok = false; }
  if miniseed_rate_microhz(&hd) != 10000 { ok = false; }
  let e = rate_fixture(40, 0);
  let pe = miniseed_parse(&e);
  if !pe.is_ok { return assert(false, "40/0 must parse"); }
  let he: MseedHeader = pe.value;
  if miniseed_rate_num(&he) != 40 { ok = false; }
  if miniseed_rate_den(&he) != 1 { ok = false; }
  if miniseed_rate_microhz(&he) != 40000000 { ok = false; }
  let f = rate_fixture(0, -5);
  let pf = miniseed_parse(&f);
  if !pf.is_ok { return assert(false, "0/-5 must parse"); }
  let hf: MseedHeader = pf.value;
  if miniseed_rate_num(&hf) != 0 { ok = false; }
  if miniseed_rate_den(&hf) != 1 { ok = false; }
  if miniseed_rate_microhz(&hf) != 0 { ok = false; }
  return assert(ok, "sample rate table: Hz, inverse Hz, both-negative, zero cases");
}

fn t5() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_activity_flags(&h) == 0;
  if miniseed_io_flags(&h) != 0 { ok = false; }
  if miniseed_data_quality_flags(&h) != 0 { ok = false; }
  if miniseed_num_blockettes(&h) != 0 { ok = false; }
  if miniseed_time_correction(&h) != 0 { ok = false; }
  if miniseed_begin_data_offset(&h) != 48 { ok = false; }
  if miniseed_begin_blockette_offset(&h) != 0 { ok = false; }
  if miniseed_reserved2(&h) != 0 { ok = false; }
  if miniseed_data_span(&h) != 464 { ok = false; }
  let data2 = fixture4096();
  let pr2 = miniseed_parse(&data2);
  if !pr2.is_ok { return assert(false, "4096 fixture must parse"); }
  let h2: MseedHeader = pr2.value;
  if miniseed_activity_flags(&h2) != 5 { ok = false; }
  if miniseed_io_flags(&h2) != 9 { ok = false; }
  if miniseed_data_quality_flags(&h2) != 17 { ok = false; }
  if miniseed_num_blockettes(&h2) != 1 { ok = false; }
  if miniseed_time_correction(&h2) != -250 { ok = false; }
  if miniseed_begin_data_offset(&h2) != 64 { ok = false; }
  if miniseed_begin_blockette_offset(&h2) != 48 { ok = false; }
  if miniseed_data_span(&h2) != 4032 { ok = false; }
  if miniseed_record_size(&h2) != 4096 { ok = false; }
  return assert(ok, "flags, blockette words, time correction and payload span");
}

fn t6() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_sample_count(&h, 4) == 116;
  let payload = miniseed_data_bytes(&data, &h);
  if !payload.is_ok { return assert(false, "payload copy must succeed"); }
  let got: Vec[UInt8] = payload.value;
  if got.len() != 464 { ok = false; }
  if !bytes_equal(got, slice_of(data, 48, 464)) { ok = false; }
  return assert(ok, "512 record payload span and byte copy");
}

fn t7() -> TestResult {
  let data = fixture4096();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "4096 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_sample_count(&h, 4) == 1008;
  let payload = miniseed_data_bytes(&data, &h);
  if !payload.is_ok { return assert(false, "4096 payload copy must succeed"); }
  let got: Vec[UInt8] = payload.value;
  if got.len() != 4032 { ok = false; }
  if !bytes_equal(got, slice_of(data, 64, 4032)) { ok = false; }
  if miniseed_required_record_size(64, 1008, 4) != 4096 { ok = false; }
  if miniseed_required_record_size(48, 116, 4) != 512 { ok = false; }
  if miniseed_required_record_size(-1, 1, 4) != 0 { ok = false; }
  if miniseed_required_record_size(48, -1, 4) != 0 { ok = false; }
  if miniseed_required_record_size(48, 1, 0) != 0 { ok = false; }
  return assert(ok, "4096 record payload span, byte copy and required size");
}

fn t8() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_sample_count(&h, 4) == 116;
  if miniseed_sample_count(&h, 3) != 154 { ok = false; }
  if miniseed_sample_count(&h, 0) != 0 { ok = false; }
  if miniseed_sample_count(&h, -2) != 0 { ok = false; }
  if !miniseed_samples_fit(&h, 116, 4) { ok = false; }
  if miniseed_samples_fit(&h, 117, 4) { ok = false; }
  if miniseed_samples_fit(&h, -1, 4) { ok = false; }
  if miniseed_samples_fit(&h, 1, 0) { ok = false; }
  if !miniseed_samples_fit(&h, 154, 3) { ok = false; }
  if miniseed_samples_fit(&h, 155, 3) { ok = false; }
  return assert(ok, "sample-count floor policy and samples-vs-span fit");
}

fn t9() -> TestResult {
  let short = slice_of(fixture512(), 0, 47);
  var ok = err_header_is(miniseed_parse(&short), "miniseed: truncated header");
  let empty = Vec[UInt8].new();
  if !err_header_is(miniseed_parse(&empty), "miniseed: truncated header") { ok = false; }
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  let cut = slice_of(data, 0, 500);
  if !err_bytes_is(miniseed_data_bytes(&cut, &h), "miniseed: truncated data") { ok = false; }
  let drift = with_sizes(&h, 600, 0, 512);
  if !err_bytes_is(miniseed_data_bytes(&data, &drift), "miniseed: truncated data") { ok = false; }
  return assert(ok, "truncated header and truncated payload are rejected");
}

fn t10() -> TestResult {
  let base = fixture512();
  var ok = err_header_is(miniseed_parse(&slice_of(base, 0, 47)), "miniseed: truncated header");
  let bad_seq = set_byte(base, 0, 65);
  if !err_header_is(miniseed_parse(&bad_seq), "miniseed: bad sequence number") { ok = false; }
  let bad_qual = set_byte(base, 6, 0);
  if !err_header_is(miniseed_parse(&bad_qual), "miniseed: bad quality indicator") { ok = false; }
  let bad_qual2 = set_byte(base, 6, 88);
  if !err_header_is(miniseed_parse(&bad_qual2), "miniseed: bad quality indicator") { ok = false; }
  let bad_res = set_byte(base, 7, 1);
  if !err_header_is(miniseed_parse(&bad_res), "miniseed: bad reserved byte") { ok = false; }
  let bad_sta = set_byte(base, 8, 31);
  if !err_header_is(miniseed_parse(&bad_sta), "miniseed: bad station") { ok = false; }
  let bad_chan = set_byte(base, 13, 127);
  if !err_header_is(miniseed_parse(&bad_chan), "miniseed: bad channel") { ok = false; }
  let bad_net = set_byte(base, 16, 0);
  if !err_header_is(miniseed_parse(&bad_net), "miniseed: bad network") { ok = false; }
  let bad_loc = set_byte(base, 18, 128);
  if !err_header_is(miniseed_parse(&bad_loc), "miniseed: bad location") { ok = false; }
  return assert(ok, "text, quality and reserved byte validation catalog");
}

fn t11() -> TestResult {
  let base = fixture512();
  var ok = err_header_is(miniseed_parse(&set_be16(base, 22, 0)), "miniseed: bad day");
  if !err_header_is(miniseed_parse(&set_be16(base, 22, 367)), "miniseed: bad day") { ok = false; }
  if !err_header_is(miniseed_parse(&set_be16(base, 22, 366)), "miniseed: bad day") { ok = false; }
  let leap_year = set_be16(base, 20, 2024);
  let leap_bad_day = set_be16(leap_year, 22, 366);
  let lp = miniseed_parse(&leap_bad_day);
  if !lp.is_ok { ok = false; }
  else {
    let lh: MseedHeader = lp.value;
    if miniseed_day(&lh) != 366 { ok = false; }
  }
  let ok_day365 = set_be16(base, 22, 365);
  if !miniseed_parse(&ok_day365).is_ok { ok = false; }
  if !miniseed_is_leap_year(2024) { ok = false; }
  if miniseed_is_leap_year(2026) { ok = false; }
  if !miniseed_is_leap_year(2000) { ok = false; }
  if miniseed_is_leap_year(1900) { ok = false; }
  return assert(ok, "day 1..366 with the proleptic Gregorian leap rule");
}

fn t12() -> TestResult {
  let base = fixture512();
  var ok = err_header_is(miniseed_parse(&set_byte(base, 24, 24)), "miniseed: bad hour");
  if !err_header_is(miniseed_parse(&set_byte(base, 25, 60)), "miniseed: bad minute") { ok = false; }
  if !err_header_is(miniseed_parse(&set_byte(base, 26, 61)), "miniseed: bad second") { ok = false; }
  if !err_header_is(miniseed_parse(&set_be16(base, 28, 10000)), "miniseed: bad tenths") { ok = false; }
  let leap_second = set_byte(base, 26, 60);
  let ls = miniseed_parse(&leap_second);
  if !ls.is_ok { ok = false; }
  else {
    let lh: MseedHeader = ls.value;
    if miniseed_second(&lh) != 60 { ok = false; }
  }
  let max_tenths = set_be16(base, 28, 9999);
  if !miniseed_parse(&max_tenths).is_ok { ok = false; }
  return assert(ok, "hour, minute, second (leap second 60) and tenths ranges");
}

fn t13() -> TestResult {
  let base = fixture512();
  var ok = err_header_is(miniseed_parse(&set_be16(base, 42, 47)), "miniseed: bad data offset");
  if !err_header_is(miniseed_parse(&set_be16(base, 42, 513)), "miniseed: bad data offset") { ok = false; }
  if !err_header_is(miniseed_parse(&set_be16(base, 44, 1)), "miniseed: bad blockette offset") { ok = false; }
  let nblk_no_off = set_byte(base, 37, 1);
  if !err_header_is(miniseed_parse(&nblk_no_off), "miniseed: bad blockette offset") { ok = false; }
  let bbo48 = set_be16(base, 44, 48);
  if !miniseed_parse(&bbo48).is_ok { ok = false; }
  let wb = fixture_with_blockette();
  let wp = miniseed_parse(&wb);
  if !wp.is_ok { ok = false; }
  else {
    let wh: MseedHeader = wp.value;
    if miniseed_begin_blockette_offset(&wh) != 48 { ok = false; }
    if miniseed_begin_data_offset(&wh) != 64 { ok = false; }
    if miniseed_data_span(&wh) != 448 { ok = false; }
    if miniseed_num_blockettes(&wh) != 1 { ok = false; }
  }
  return assert(ok, "data and blockette offset policy");
}

fn t14() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  let built = miniseed_build(&h);
  if !built.is_ok { return assert(false, "header build must succeed"); }
  let out: Vec[UInt8] = built.value;
  var ok = out.len() == 48;
  if !bytes_equal(out, slice_of(data, 0, 48)) { ok = false; }
  if (out[0] as Int) != 48 { ok = false; }
  if (out[4] as Int) != 52 { ok = false; }
  if (out[6] as Int) != 68 { ok = false; }
  if (out[7] as Int) != 32 { ok = false; }
  if (out[20] as Int) != 7 { ok = false; }
  if (out[21] as Int) != 234 { ok = false; }
  if (out[22] as Int) != 1 { ok = false; }
  if (out[23] as Int) != 11 { ok = false; }
  if (out[30] as Int) != 0 { ok = false; }
  if (out[31] as Int) != 40 { ok = false; }
  if (out[42] as Int) != 0 { ok = false; }
  if (out[43] as Int) != 48 { ok = false; }
  return assert(ok, "builder emits the byte-exact canonical 512 header");
}

fn t15() -> TestResult {
  let data = fixture4096();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "4096 fixture must parse"); }
  let h: MseedHeader = pr.value;
  let built = miniseed_build(&h);
  if !built.is_ok { return assert(false, "header build must succeed"); }
  let out: Vec[UInt8] = built.value;
  var ok = out.len() == 48;
  if !bytes_equal(out, slice_of(data, 0, 48)) { ok = false; }
  if (out[30] as Int) != 255 { ok = false; }
  if (out[31] as Int) != 255 { ok = false; }
  if (out[32] as Int) != 255 { ok = false; }
  if (out[33] as Int) != 156 { ok = false; }
  if (out[38] as Int) != 255 { ok = false; }
  if (out[41] as Int) != 6 { ok = false; }
  if (out[42] as Int) != 0 { ok = false; }
  if (out[43] as Int) != 64 { ok = false; }
  if (out[44] as Int) != 0 { ok = false; }
  if (out[45] as Int) != 48 { ok = false; }
  return assert(ok, "builder emits the byte-exact canonical 4096 header");
}

fn t16() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  let custom = with_text(&h, "42", 68, "ANMO", "BHZ", "IU", "");
  let built = miniseed_build(&custom);
  if !built.is_ok { return assert(false, "padded build must succeed"); }
  let out: Vec[UInt8] = built.value;
  var ok = out.len() == 48;
  if (out[0] as Int) != 52 { ok = false; }
  if (out[1] as Int) != 50 { ok = false; }
  if (out[2] as Int) != 32 { ok = false; }
  if (out[5] as Int) != 32 { ok = false; }
  if (out[12] as Int) != 32 { ok = false; }
  if (out[18] as Int) != 32 { ok = false; }
  if (out[19] as Int) != 32 { ok = false; }
  let pr2 = miniseed_parse(&out);
  if !pr2.is_ok { return assert(false, "built header must parse"); }
  let h2: MseedHeader = pr2.value;
  if !streq(miniseed_sequence(&h2), "42") { ok = false; }
  if !streq(miniseed_location(&h2), "") { ok = false; }
  if !streq(miniseed_station(&h2), "ANMO") { ok = false; }
  return assert(ok, "builder space-pads text fields and re-parses trimmed");
}

fn t17() -> TestResult {
  var v = set_byte(fixture512(), 27, 7);
  v = set_be16(v, 46, 4660);
  let pr = miniseed_parse(&v);
  if !pr.is_ok { return assert(false, "unused/reserved fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = miniseed_unused(&h) == 7;
  if miniseed_reserved2(&h) != 4660 { ok = false; }
  let built = miniseed_build(&h);
  if !built.is_ok { return assert(false, "header build must succeed"); }
  let out: Vec[UInt8] = built.value;
  if (out[27] as Int) != 0 { ok = false; }
  if (out[46] as Int) != 0 { ok = false; }
  if (out[47] as Int) != 0 { ok = false; }
  return assert(ok, "unused and reserved bytes are preserved then canonicalised to 0");
}

fn t18() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  var ok = true;
  let bad_qual = with_text(&h, "000042", 0, "ANMO", "BHZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_qual), "miniseed: bad quality indicator") { ok = false; }
  let bad_res = with_reserved(&h, 1);
  if !err_bytes_is(miniseed_build(&bad_res), "miniseed: bad reserved byte") { ok = false; }
  let bad_seq = with_text(&h, "0000042", 68, "ANMO", "BHZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_seq), "miniseed: bad sequence number") { ok = false; }
  let bad_seq2 = with_text(&h, "AB", 68, "ANMO", "BHZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_seq2), "miniseed: bad sequence number") { ok = false; }
  let bad_sta = with_text(&h, "000042", 68, "TOOLONG", "BHZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_sta), "miniseed: bad station") { ok = false; }
  let bad_sta2 = with_text(&h, "000042", 68, "A\u{001F}MO", "BHZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_sta2), "miniseed: bad station") { ok = false; }
  let bad_chan = with_text(&h, "000042", 68, "ANMO", "BHZZ", "IU", "00");
  if !err_bytes_is(miniseed_build(&bad_chan), "miniseed: bad channel") { ok = false; }
  let bad_net = with_text(&h, "000042", 68, "ANMO", "BHZ", "IUX", "00");
  if !err_bytes_is(miniseed_build(&bad_net), "miniseed: bad network") { ok = false; }
  let bad_loc = with_text(&h, "000042", 68, "ANMO", "BHZ", "IU", "000");
  if !err_bytes_is(miniseed_build(&bad_loc), "miniseed: bad location") { ok = false; }
  let bad_year = with_time(&h, 70000, 1, 0, 0, 0, 0);
  if !err_bytes_is(miniseed_build(&bad_year), "miniseed: bad year") { ok = false; }
  let bad_day = with_time(&h, 2026, 367, 0, 0, 0, 0);
  if !err_bytes_is(miniseed_build(&bad_day), "miniseed: bad day") { ok = false; }
  let bad_hour = with_time(&h, 2026, 1, 24, 0, 0, 0);
  if !err_bytes_is(miniseed_build(&bad_hour), "miniseed: bad hour") { ok = false; }
  let bad_min = with_time(&h, 2026, 1, 0, 60, 0, 0);
  if !err_bytes_is(miniseed_build(&bad_min), "miniseed: bad minute") { ok = false; }
  let bad_sec = with_time(&h, 2026, 1, 0, 0, 61, 0);
  if !err_bytes_is(miniseed_build(&bad_sec), "miniseed: bad second") { ok = false; }
  let bad_tenths = with_time(&h, 2026, 1, 0, 0, 0, 10000);
  if !err_bytes_is(miniseed_build(&bad_tenths), "miniseed: bad tenths") { ok = false; }
  let bad_rate = with_rate(&h, 40000, 1);
  if !err_bytes_is(miniseed_build(&bad_rate), "miniseed: bad sample rate") { ok = false; }
  let bad_flags = with_flags(&h, 256, 0, 0, 0, 0);
  if !err_bytes_is(miniseed_build(&bad_flags), "miniseed: bad flags") { ok = false; }
  let bad_flags2 = with_flags(&h, 0, 0, 0, 300, 0);
  if !err_bytes_is(miniseed_build(&bad_flags2), "miniseed: bad flags") { ok = false; }
  let bad_tc = with_flags(&h, 0, 0, 0, 0, 3000000000);
  if !err_bytes_is(miniseed_build(&bad_tc), "miniseed: bad time correction") { ok = false; }
  let bad_bdo = with_sizes(&h, 47, 0, 512);
  if !err_bytes_is(miniseed_build(&bad_bdo), "miniseed: bad data offset") { ok = false; }
  let bad_bbo = with_sizes(&h, 48, 1, 512);
  if !err_bytes_is(miniseed_build(&bad_bbo), "miniseed: bad blockette offset") { ok = false; }
  let h_nblk = with_flags(&h, 0, 0, 0, 1, 0);
  let no_bbo = with_sizes(&h_nblk, 48, 0, 512);
  if !err_bytes_is(miniseed_build(&no_bbo), "miniseed: bad blockette offset") { ok = false; }
  let bad_rs = with_sizes(&h, 48, 0, 47);
  if !err_bytes_is(miniseed_build(&bad_rs), "miniseed: bad record size") { ok = false; }
  return assert(ok, "builder validation error catalog");
}

fn t19() -> TestResult {
  let data = fixture512();
  let pr = miniseed_parse(&data);
  if !pr.is_ok { return assert(false, "512 fixture must parse"); }
  let h: MseedHeader = pr.value;
  let built = miniseed_build(&h);
  if !built.is_ok { return assert(false, "header build must succeed"); }
  let out: Vec[UInt8] = built.value;
  let pr2 = miniseed_parse(&out);
  if !pr2.is_ok { return assert(false, "built header must parse"); }
  let h2: MseedHeader = pr2.value;
  var ok = miniseed_record_size(&h2) == 48;
  if miniseed_data_span(&h2) != 0 { ok = false; }
  if miniseed_sample_count(&h2, 4) != 0 { ok = false; }
  if !streq(miniseed_sequence(&h2), "000042") { ok = false; }
  if !streq(miniseed_station(&h2), "ANMO") { ok = false; }
  if !streq(miniseed_channel(&h2), "BHZ") { ok = false; }
  if !streq(miniseed_network(&h2), "IU") { ok = false; }
  if miniseed_quality(&h2) != 68 { ok = false; }
  if miniseed_year(&h2) != 2026 { ok = false; }
  if miniseed_day(&h2) != 267 { ok = false; }
  if miniseed_hour(&h2) != 12 { ok = false; }
  if miniseed_minute(&h2) != 34 { ok = false; }
  if miniseed_second(&h2) != 56 { ok = false; }
  if miniseed_tenths(&h2) != 1234 { ok = false; }
  if miniseed_sample_rate_factor(&h2) != 40 { ok = false; }
  if miniseed_sample_rate_multiplier(&h2) != 1 { ok = false; }
  if miniseed_begin_data_offset(&h2) != 48 { ok = false; }
  if miniseed_begin_blockette_offset(&h2) != 0 { ok = false; }
  return assert(ok, "build then parse round trip preserves the header fields");
}

fn t20() -> TestResult {
  var ok = true;
  let a = rate_fixture(1, -3);
  let pa = miniseed_parse(&a);
  if !pa.is_ok { return assert(false, "1/-3 must parse"); }
  let ha: MseedHeader = pa.value;
  if miniseed_rate_num(&ha) != 1 { ok = false; }
  if miniseed_rate_den(&ha) != 3 { ok = false; }
  if miniseed_rate_microhz(&ha) != 333333 { ok = false; }
  let b = rate_fixture(250, 1);
  let pb = miniseed_parse(&b);
  if !pb.is_ok { return assert(false, "250/1 must parse"); }
  let hb: MseedHeader = pb.value;
  if miniseed_rate_microhz(&hb) != 250000000 { ok = false; }
  let c = rate_fixture(0, 0);
  let pc = miniseed_parse(&c);
  if !pc.is_ok { return assert(false, "0/0 must parse"); }
  let hc: MseedHeader = pc.value;
  if miniseed_rate_num(&hc) != 0 { ok = false; }
  if miniseed_rate_den(&hc) != 1 { ok = false; }
  if miniseed_rate_microhz(&hc) != 0 { ok = false; }
  let d = rate_fixture(-100, 0);
  let pd = miniseed_parse(&d);
  if !pd.is_ok { return assert(false, "-100/0 must parse"); }
  let hd: MseedHeader = pd.value;
  if miniseed_rate_num(&hd) != 1 { ok = false; }
  if miniseed_rate_den(&hd) != 100 { ok = false; }
  if miniseed_rate_microhz(&hd) != 10000 { ok = false; }
  return assert(ok, "micro-Hz truncation and the zero-multiplier policy");
}

fn main() -> Int {
  io.println("=== xiom.miniseed conformance tests ===");
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
    io.println("xiom.miniseed: all tests passed");
  } else {
    io.println("xiom.miniseed: tests failed");
  }
  return failed;
}
