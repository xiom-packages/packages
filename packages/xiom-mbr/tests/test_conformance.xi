// XIOM -- xiom.mbr conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.mbr codec against the rules pinned in
// SPEC.md: the 512-byte sector, the raw boot code span, the four 16-byte
// partition entries, the boot flag policy, the packed raw CHS triples with
// their documented decoded form, the partial type-name table, the type 0 /
// LBA consistency policy, the optional disk-size bound, the pairwise
// overlap helper, the documented error catalog and build/parse round trips
// (including the one-Linux-partition + unused-entry fixture).
//
// Fixtures are assembled byte by byte in this file, so mbr_parse is
// exercised against bytes the test controls rather than only against
// mbr_build. Str comparisons go through xiom.string.compare's str_compare
// (BUG 17: `==` on Str values read from Vec elements lowers to a pointer
// comparison); every Vec element read is bound to an explicitly typed local
// and every `&` argument is a local binding (never a field or call result).

module mbr_tests
use xiom.io; use xiom.test;
use xiom.mbr;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Byte helpers (independent of src/mbr.xi)
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

fn push_le32(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 16777216) % 256) as UInt8);
}

// Append a CHS triple as the three raw bytes: head, then
// sector | (cylinder high 2 bits << 6), then cylinder low byte.
fn push_chs(v: &mut Vec[UInt8], head: Int, sector: Int, cyl: Int) {
  v.push((head % 256) as UInt8);
  v.push((sector % 64 + (cyl / 256) * 64) as UInt8);
  v.push((cyl % 256) as UInt8);
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

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn all_zero(v: Vec[UInt8], start: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let b: Int = (v[start + i] as Int) & 0xFF;
    if b != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn le32_at(v: Vec[UInt8], pos: Int) -> Int {
  let b0: Int = (v[pos] as Int) & 0xFF;
  let b1: Int = (v[pos + 1] as Int) & 0xFF;
  let b2: Int = (v[pos + 2] as Int) & 0xFF;
  let b3: Int = (v[pos + 3] as Int) & 0xFF;
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// --------------------------------------------------
//  Byte-level fixtures
// --------------------------------------------------

// The 440-byte boot code pattern: byte i is (i * 7 + 3) mod 256, so any
// dropped, shifted or rewritten byte changes the comparison.
fn boot_pattern() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < 440 {
    v.push(((i * 7 + 3) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// The six bytes at 0x1B8..0x1BD: disk signature 0x12345678 followed by two
// reserved zero bytes (non-zero on purpose, to prove raw preservation).
fn disk_area_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(120 as UInt8);
  v.push(86 as UInt8);
  v.push(52 as UInt8);
  v.push(18 as UInt8);
  v.push(0 as UInt8);
  v.push(0 as UInt8);
  return v;
}

// Append one 16-byte entry: flag, start CHS, type, end CHS, LBA start, LBA
// count.
fn push_entry(v: &mut Vec[UInt8], flag: Int, sh: Int, ss: Int, sc: Int, ty: Int, eh: Int, es: Int, ec: Int, lba_start: Int, lba_count: Int) {
  v.push(flag as UInt8);
  push_chs(v, sh, ss, sc);
  v.push(ty as UInt8);
  push_chs(v, eh, es, ec);
  push_le32(v, lba_start);
  push_le32(v, lba_count);
}

// One Linux partition (type 0x83, bootable, LBA [2048, 3072)) in slot 0 and
// three zeroed unused slots; the boot code and disk area are non-trivial.
fn fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  let bp = boot_pattern();
  var i = 0;
  while i < bp.len() {
    v.push(bp[i]);
    i = i + 1;
  }
  let da = disk_area_bytes();
  i = 0;
  while i < da.len() {
    v.push(da[i]);
    i = i + 1;
  }
  push_entry(&mut v, 128, 1, 1, 0, 131, 254, 63, 1023, 2048, 1024);
  push_zeros(&mut v, 48);
  v.push(85 as UInt8);
  v.push(170 as UInt8);
  return v;
}

// A sector with zeroed boot code and disk area and one caller-controlled
// entry in slot 0.
fn one_entry(flag: Int, sh: Int, ss: Int, sc: Int, ty: Int, eh: Int, es: Int, ec: Int, lba_start: Int, lba_count: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, 446);
  push_entry(&mut v, flag, sh, ss, sc, ty, eh, es, ec, lba_start, lba_count);
  push_zeros(&mut v, 48);
  v.push(85 as UInt8);
  v.push(170 as UInt8);
  return v;
}

// --------------------------------------------------
//  Mbr fixtures
// --------------------------------------------------

fn no_ints() -> Vec[Int] {
  return Vec[Int].new();
}

fn one_int(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn two_ints(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn four_ints(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn five_ints(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var k = 0;
  while k < 5 {
    v.push(a);
    k = k + 1;
  }
  return v;
}

fn mbr_of(boot: Vec[UInt8], area: Vec[UInt8], flags: Vec[Int], starts: Vec[Int], tys: Vec[Int], ends: Vec[Int], ls: Vec[Int], lc: Vec[Int]) -> Mbr {
  let t = Mbr{
    boot_code: boot;
    disk_area: area;
    boot_flags: flags;
    start_chs: starts;
    types: tys;
    end_chs: ends;
    lba_starts: ls;
    lba_counts: lc;
  };
  return t;
}

// The same one-Linux-partition content as fixture(), as a table: entry 0
// bootable Linux at head 1 / sector 1 / cylinder 0 and end 254 / 63 / 1023,
// LBA [2048, 3072). mbr_build on this table must reproduce fixture().
fn linux_table() -> Mbr {
  return mbr_of(boot_pattern(), disk_area_bytes(),
    one_int(128), one_int(65792), one_int(131), one_int(16711679),
    one_int(2048), one_int(1024));
}

// Four provided slots: Linux, unused, NTFS/exFAT, unused.
fn complete_table() -> Mbr {
  return mbr_of(boot_pattern(), disk_area_bytes(),
    four_ints(128, 0, 128, 0),
    four_ints(65792, 0, 0, 0),
    four_ints(131, 0, 7, 0),
    four_ints(16711679, 0, 0, 0),
    four_ints(2048, 0, 4096, 0),
    four_ints(1024, 0, 2048, 0));
}

// Entry 0 is the Linux partition [2048, 3072); entry 1 is caller-controlled.
fn overlap_table(ty1: Int, ls1: Int, lc1: Int) -> Mbr {
  return mbr_of(boot_pattern(), disk_area_bytes(),
    two_ints(128, 128),
    two_ints(65792, 0),
    two_ints(131, ty1),
    two_ints(16711679, 0),
    two_ints(2048, ls1),
    two_ints(1024, lc1));
}

// boot_flags has two elements while the other five vectors have one.
fn drifted_table() -> Mbr {
  return mbr_of(boot_pattern(), disk_area_bytes(),
    two_ints(128, 0), one_int(65792), one_int(131), one_int(16711679),
    one_int(2048), one_int(1024));
}

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn err_mbr_is(r: Result[Mbr, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// A one-entry build from six scalars (boot flag, start CHS packed, type,
// end CHS packed, LBA start, LBA count).
fn build_one(flag: Int, sc: Int, ty: Int, ec: Int, ls: Int, lc: Int) -> Result[Vec[UInt8], Str] {
  let t = mbr_of(boot_pattern(), disk_area_bytes(), one_int(flag), one_int(sc), one_int(ty), one_int(ec), one_int(ls), one_int(lc));
  return mbr_build(&t);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture();
  var ok = mbr_signature_ok(&data);
  if mbr_signature(&data) != 43605 { ok = false; }
  let swapped = set_byte(set_byte(data, 510, 170), 511, 85);
  if mbr_signature_ok(&swapped) { ok = false; }
  if mbr_signature(&swapped) != 21930 { ok = false; }
  let low = set_byte(data, 511, 85);
  if mbr_signature_ok(&low) { ok = false; }
  let short = prefix(data, 511);
  if mbr_signature_ok(&short) { ok = false; }
  if mbr_signature(&short) != -1 { ok = false; }
  let empty = Vec[UInt8].new();
  if mbr_signature_ok(&empty) { ok = false; }
  if mbr_signature(&empty) != -1 { ok = false; }
  return assert(ok, "signature bytes 55 AA, raw LE16 reading and short buffers");
}

fn t2() -> TestResult {
  let data = fixture();
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let m = pr.value;
  var ok = mbr_entry_count(&m) == 4;
  let bc = mbr_boot_code_span(&m);
  if bc.len() != 440 { ok = false; }
  let bp = boot_pattern();
  if !bytes_equal(bc, bp) { ok = false; }
  let da = mbr_disk_area_span(&m);
  if da.len() != 6 { ok = false; }
  let dab = disk_area_bytes();
  if !bytes_equal(da, dab) { ok = false; }
  if ((data[440] as Int) & 0xFF) != 120 { ok = false; }
  if ((data[443] as Int) & 0xFF) != 18 { ok = false; }
  if ((data[445] as Int) & 0xFF) != 0 { ok = false; }
  return assert(ok, "parse preserves the 440-byte boot code span and the 6-byte disk area");
}

fn t3() -> TestResult {
  let data = fixture();
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let m = pr.value;
  var ok = mbr_entry_boot_flag(&m, 0) == 128;
  if !mbr_entry_bootable(&m, 0) { ok = false; }
  if mbr_entry_boot_flag(&m, 1) != 0 { ok = false; }
  if mbr_entry_bootable(&m, 1) { ok = false; }
  if mbr_entry_type(&m, 0) != 131 { ok = false; }
  if mbr_entry_type(&m, 1) != 0 { ok = false; }
  if !streq(mbr_entry_type_name(&m, 0), "Linux") { ok = false; }
  if !streq(mbr_entry_type_name(&m, 1), "unused") { ok = false; }
  if !mbr_entry_in_use(&m, 0) { ok = false; }
  if mbr_entry_in_use(&m, 1) { ok = false; }
  if mbr_entry_in_use(&m, 3) { ok = false; }
  return assert(ok, "boot flags, bootable predicate, raw type, in-use predicate and type name");
}

fn t4() -> TestResult {
  let data = fixture();
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let m = pr.value;
  var ok = mbr_entry_start_chs(&m, 0) == 65792;
  if mbr_entry_start_chs_head(&m, 0) != 1 { ok = false; }
  if mbr_entry_start_chs_sector(&m, 0) != 1 { ok = false; }
  if mbr_entry_start_chs_cylinder(&m, 0) != 0 { ok = false; }
  if mbr_entry_end_chs(&m, 0) != 16711679 { ok = false; }
  if mbr_entry_end_chs_head(&m, 0) != 254 { ok = false; }
  if mbr_entry_end_chs_sector(&m, 0) != 63 { ok = false; }
  if mbr_entry_end_chs_cylinder(&m, 0) != 1023 { ok = false; }
  let hi = one_entry(128, 2, 5, 683, 131, 3, 40, 1000, 63, 1);
  let hp = mbr_parse(&hi);
  if !hp.is_ok { return assert(false, "high-cylinder fixture must parse"); }
  let hm = hp.value;
  if mbr_entry_start_chs_head(&hm, 0) != 2 { ok = false; }
  if mbr_entry_start_chs_sector(&hm, 0) != 5 { ok = false; }
  if mbr_entry_start_chs_cylinder(&hm, 0) != 683 { ok = false; }
  if mbr_entry_end_chs_head(&hm, 0) != 3 { ok = false; }
  if mbr_entry_end_chs_sector(&hm, 0) != 40 { ok = false; }
  if mbr_entry_end_chs_cylinder(&hm, 0) != 1000 { ok = false; }
  return assert(ok, "packed raw CHS triple and decoded head/sector/cylinder, including high cylinders");
}

fn t5() -> TestResult {
  let data = fixture();
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let m = pr.value;
  var ok = mbr_entry_lba_start(&m, 0) == 2048;
  if mbr_entry_lba_count(&m, 0) != 1024 { ok = false; }
  if mbr_entry_lba_start(&m, 1) != 0 { ok = false; }
  if mbr_entry_lba_count(&m, 1) != 0 { ok = false; }
  let big = one_entry(128, 0, 0, 0, 131, 0, 0, 0, 4294967295, 4294967295);
  let bp = mbr_parse(&big);
  if !bp.is_ok { return assert(false, "u32 fixture must parse"); }
  let bm = bp.value;
  if mbr_entry_lba_start(&bm, 0) != 4294967295 { ok = false; }
  if mbr_entry_lba_count(&bm, 0) != 4294967295 { ok = false; }
  return assert(ok, "LBA start/count accessors including the u32 maximum");
}

fn t6() -> TestResult {
  var ok = streq(mbr_type_name(0), "unused");
  if !streq(mbr_type_name(7), "NTFS/exFAT") { ok = false; }
  if !streq(mbr_type_name(11), "FAT32 (CHS)") { ok = false; }
  if !streq(mbr_type_name(12), "FAT32 (LBA)") { ok = false; }
  if !streq(mbr_type_name(130), "Linux swap") { ok = false; }
  if !streq(mbr_type_name(131), "Linux") { ok = false; }
  if !streq(mbr_type_name(142), "Linux LVM") { ok = false; }
  if !streq(mbr_type_name(238), "GPT protective") { ok = false; }
  if !streq(mbr_type_name(239), "EFI system") { ok = false; }
  if !streq(mbr_type_name(153), "unknown") { ok = false; }
  if !streq(mbr_type_name(-1), "") { ok = false; }
  if !streq(mbr_type_name(256), "") { ok = false; }
  let u = one_entry(128, 0, 0, 0, 153, 0, 0, 0, 100, 10);
  let up = mbr_parse(&u);
  if !up.is_ok { return assert(false, "unknown-type fixture must parse"); }
  let um = up.value;
  if mbr_entry_type(&um, 0) != 153 { ok = false; }
  if !streq(mbr_entry_type_name(&um, 0), "unknown") { ok = false; }
  if !mbr_entry_in_use(&um, 0) { ok = false; }
  return assert(ok, "partial type-name table, unknown pass-through and out-of-byte codes");
}

fn t7() -> TestResult {
  let short = prefix(fixture(), 511);
  var ok = err_mbr_is(mbr_parse(&short), "mbr: truncated sector");
  let empty = Vec[UInt8].new();
  if !err_mbr_is(mbr_parse(&empty), "mbr: truncated sector") { ok = false; }
  let badsig = set_byte(fixture(), 510, 0);
  if !err_mbr_is(mbr_parse(&badsig), "mbr: bad signature") { ok = false; }
  let badsig2 = set_byte(fixture(), 511, 170 + 1);
  if !err_mbr_is(mbr_parse(&badsig2), "mbr: bad signature") { ok = false; }
  let badflag = set_byte(fixture(), 446 + 16, 127);
  if !err_mbr_is(mbr_parse(&badflag), "mbr: bad boot flag") { ok = false; }
  let badflag2 = set_byte(fixture(), 446 + 2 * 16, 1);
  if !err_mbr_is(mbr_parse(&badflag2), "mbr: bad boot flag") { ok = false; }
  let unused_count = set_byte(fixture(), 446 + 16 + 12, 5);
  if !err_mbr_is(mbr_parse(&unused_count), "mbr: unused entry not zero") { ok = false; }
  let unused_start = set_byte(fixture(), 446 + 16 + 8, 3);
  if !err_mbr_is(mbr_parse(&unused_start), "mbr: unused entry not zero") { ok = false; }
  let unused_high = set_byte(fixture(), 446 + 16 + 15, 1);
  if !err_mbr_is(mbr_parse(&unused_high), "mbr: unused entry not zero") { ok = false; }
  return assert(ok, "parse errors: truncation, signature, boot flag, type 0 with LBA");
}

fn t8() -> TestResult {
  // An in-use entry with all-zero CHS is legal because the LBA fields are
  // set: CHS is never cross-checked against LBA.
  let z = one_entry(128, 0, 0, 0, 131, 0, 0, 0, 4096, 512);
  let zp = mbr_parse(&z);
  if !zp.is_ok { return assert(false, "zero-CHS fixture must parse"); }
  let zm = zp.value;
  var ok = mbr_entry_start_chs_head(&zm, 0) == 0;
  if mbr_entry_start_chs_sector(&zm, 0) != 0 { ok = false; }
  if mbr_entry_start_chs_cylinder(&zm, 0) != 0 { ok = false; }
  if mbr_entry_end_chs_cylinder(&zm, 0) != 0 { ok = false; }
  if !mbr_entry_in_use(&zm, 0) { ok = false; }
  // An unused entry's CHS bytes are not constrained; only the LBA policy
  // applies, and they are zero.
  let uc = set_byte(fixture(), 446 + 16 + 1, 9);
  let up = mbr_parse(&uc);
  if !up.is_ok { ok = false; }
  let um = up.value;
  if mbr_entry_start_chs_head(&um, 1) != 9 { ok = false; }
  return assert(ok, "zero CHS tolerated when LBA is set; unused-entry CHS unconstrained");
}

fn t9() -> TestResult {
  // The fixture's Linux entry is [2048, 3072).
  let data = fixture();
  var ok = mbr_parse_sized(&data, 3072).is_ok;
  let beyond = mbr_parse_sized(&data, 3071);
  if !err_mbr_is(beyond, "mbr: entry beyond disk") { ok = false; }
  let zero = mbr_parse_sized(&data, 0);
  if !err_mbr_is(zero, "mbr: bad disk size") { ok = false; }
  let neg = mbr_parse_sized(&data, -1);
  if !err_mbr_is(neg, "mbr: bad disk size") { ok = false; }
  let short = prefix(data, 100);
  if !err_mbr_is(mbr_parse_sized(&short, 100), "mbr: truncated sector") { ok = false; }
  if !mbr_parse_sized(&data, 4294967295).is_ok { ok = false; }
  // A zero-length in-use extent passes exactly when its start fits.
  let zl = one_entry(128, 0, 0, 0, 131, 0, 0, 0, 5000, 0);
  if !mbr_parse_sized(&zl, 5000).is_ok { ok = false; }
  if !err_mbr_is(mbr_parse_sized(&zl, 4999), "mbr: entry beyond disk") { ok = false; }
  return assert(ok, "sized parse bounds in-use entries only; bad disk sizes rejected");
}

fn t10() -> TestResult {
  let t = linux_table();
  let b = mbr_build(&t);
  if !b.is_ok { return assert(false, "build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = data.len() == 512;
  let f = fixture();
  if !bytes_equal(data, f) { ok = false; }
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "built MBR must parse"); }
  let m = pr.value;
  if mbr_entry_count(&m) != 4 { ok = false; }
  if mbr_entry_type(&m, 0) != 131 { ok = false; }
  if mbr_entry_lba_start(&m, 0) != 2048 { ok = false; }
  if mbr_entry_lba_count(&m, 0) != 1024 { ok = false; }
  if mbr_entry_in_use(&m, 1) { ok = false; }
  if !streq(mbr_entry_type_name(&m, 2), "unused") { ok = false; }
  let b2 = mbr_build(&m);
  if !b2.is_ok { ok = false; }
  else {
    let data2: Vec[UInt8] = b2.value;
    if !bytes_equal(data2, data) { ok = false; }
  }
  return assert(ok, "one-Linux + unused fixture: build is canonical and parse->build is byte-stable");
}

fn t11() -> TestResult {
  let t = linux_table();
  let b = mbr_build(&t);
  if !b.is_ok { return assert(false, "build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = ((data[446] as Int) & 0xFF) == 128;
  if ((data[447] as Int) & 0xFF) != 1 { ok = false; }
  if ((data[448] as Int) & 0xFF) != 1 { ok = false; }
  if ((data[449] as Int) & 0xFF) != 0 { ok = false; }
  if ((data[450] as Int) & 0xFF) != 131 { ok = false; }
  if ((data[451] as Int) & 0xFF) != 254 { ok = false; }
  if ((data[452] as Int) & 0xFF) != 255 { ok = false; }
  if ((data[453] as Int) & 0xFF) != 255 { ok = false; }
  if le32_at(data, 454) != 2048 { ok = false; }
  if le32_at(data, 458) != 1024 { ok = false; }
  if !all_zero(data, 462, 48) { ok = false; }
  if ((data[510] as Int) & 0xFF) != 85 { ok = false; }
  if ((data[511] as Int) & 0xFF) != 170 { ok = false; }
  let bp = boot_pattern();
  var i = 0;
  while i < 440 {
    if data[i] != bp[i] { ok = false; }
    i = i + 1;
  }
  if ((data[440] as Int) & 0xFF) != 120 { ok = false; }
  if ((data[441] as Int) & 0xFF) != 86 { ok = false; }
  if ((data[442] as Int) & 0xFF) != 52 { ok = false; }
  if ((data[443] as Int) & 0xFF) != 18 { ok = false; }
  if ((data[444] as Int) & 0xFF) != 0 { ok = false; }
  if ((data[445] as Int) & 0xFF) != 0 { ok = false; }
  return assert(ok, "builder layout: entry bytes, zero-filled slots, raw spans and recomputed signature");
}

fn t12() -> TestResult {
  let t = complete_table();
  let b = mbr_build(&t);
  if !b.is_ok { return assert(false, "complete build must succeed"); }
  let data: Vec[UInt8] = b.value;
  var ok = data.len() == 512;
  let pr = mbr_parse(&data);
  if !pr.is_ok { return assert(false, "complete MBR must parse"); }
  let m = pr.value;
  if mbr_entry_count(&m) != 4 { ok = false; }
  if !mbr_entry_in_use(&m, 0) { ok = false; }
  if mbr_entry_in_use(&m, 1) { ok = false; }
  if !mbr_entry_in_use(&m, 2) { ok = false; }
  if mbr_entry_in_use(&m, 3) { ok = false; }
  if mbr_entry_lba_start(&m, 2) != 4096 { ok = false; }
  if mbr_entry_lba_count(&m, 2) != 2048 { ok = false; }
  if !streq(mbr_entry_type_name(&m, 2), "NTFS/exFAT") { ok = false; }
  let b2 = mbr_build(&m);
  if !b2.is_ok { ok = false; }
  else {
    let data2: Vec[UInt8] = b2.value;
    if !bytes_equal(data2, data) { ok = false; }
  }
  // A two-entry table zero-fills slots 2 and 3.
  let p = mbr_of(boot_pattern(), disk_area_bytes(),
    two_ints(128, 128), two_ints(65792, 0), two_ints(131, 7), two_ints(16711679, 0),
    two_ints(2048, 4096), two_ints(1024, 2048));
  let pb = mbr_build(&p);
  if !pb.is_ok { return assert(false, "two-entry build must succeed"); }
  let pd: Vec[UInt8] = pb.value;
  if !all_zero(pd, 446 + 2 * 16, 32) { ok = false; }
  return assert(ok, "four-slot build with an unused middle slot; short input zero-fills the tail");
}

fn t13() -> TestResult {
  let bad_boot = mbr_of(prefix(boot_pattern(), 439), disk_area_bytes(), no_ints(), no_ints(), no_ints(), no_ints(), no_ints(), no_ints());
  var ok = err_bytes_is(mbr_build(&bad_boot), "mbr: bad boot code");
  let bad_area = mbr_of(boot_pattern(), prefix(disk_area_bytes(), 5), no_ints(), no_ints(), no_ints(), no_ints(), no_ints(), no_ints());
  if !err_bytes_is(mbr_build(&bad_area), "mbr: bad disk area") { ok = false; }
  let mismatch = mbr_of(boot_pattern(), disk_area_bytes(), one_int(128), no_ints(), no_ints(), no_ints(), no_ints(), no_ints());
  if !err_bytes_is(mbr_build(&mismatch), "mbr: entry vector mismatch") { ok = false; }
  let f5 = five_ints(128);
  let many = mbr_of(boot_pattern(), disk_area_bytes(), f5, f5, f5, f5, f5, f5);
  if !err_bytes_is(mbr_build(&many), "mbr: bad entry count") { ok = false; }
  return assert(ok, "builder shape errors: boot code, disk area, vector mismatch, entry count");
}

fn t14() -> TestResult {
  var ok = err_bytes_is(build_one(127, 65792, 131, 16711679, 2048, 1024), "mbr: bad boot flag");
  if !err_bytes_is(build_one(128, 65792, -1, 16711679, 2048, 1024), "mbr: bad entry type") { ok = false; }
  if !err_bytes_is(build_one(128, 65792, 256, 16711679, 2048, 1024), "mbr: bad entry type") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 0, 0, 0, 1), "mbr: unused entry not zero") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 0, 0, 1, 0), "mbr: unused entry not zero") { ok = false; }
  if !err_bytes_is(build_one(128, -1, 131, 0, 2048, 1024), "mbr: bad CHS") { ok = false; }
  if !err_bytes_is(build_one(128, 16777216, 131, 0, 2048, 1024), "mbr: bad CHS") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 131, 16777216, 2048, 1024), "mbr: bad CHS") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 131, 0, -1, 1024), "mbr: bad LBA") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 131, 0, 4294967296, 1024), "mbr: bad LBA") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 131, 0, 2048, -1), "mbr: bad LBA") { ok = false; }
  if !err_bytes_is(build_one(128, 0, 131, 0, 2048, 4294967296), "mbr: bad LBA") { ok = false; }
  return assert(ok, "builder value errors: flag, type, unused LBA policy, CHS and LBA ranges");
}

fn t15() -> TestResult {
  let t = overlap_table(7, 3000, 500);
  var ok = mbr_has_overlap(&t);
  if !mbr_entries_overlap(&t, 0, 1) { ok = false; }
  if !mbr_entries_overlap(&t, 1, 0) { ok = false; }
  let adj = overlap_table(7, 3072, 100);
  if mbr_has_overlap(&adj) { ok = false; }
  if mbr_entries_overlap(&adj, 0, 1) { ok = false; }
  let zero_len = overlap_table(7, 2048, 0);
  if mbr_has_overlap(&zero_len) { ok = false; }
  let unused = overlap_table(0, 2048, 500);
  if mbr_has_overlap(&unused) { ok = false; }
  if mbr_entries_overlap(&t, 0, 0) { ok = false; }
  if mbr_entries_overlap(&t, -1, 1) { ok = false; }
  if mbr_entries_overlap(&t, 0, 4) { ok = false; }
  if mbr_has_overlap(&linux_table()) { ok = false; }
  return assert(ok, "pairwise overlap: intersection yes, adjacency no, unused/zero-length ignored");
}

fn t16() -> TestResult {
  // Protective MBR (0xEE) and a Linux LVM entry (0x8E) round-trip.
  let pe = one_entry(128, 0, 2, 0, 238, 255, 255, 1023, 1, 4294967294);
  let pp = mbr_parse(&pe);
  if !pp.is_ok { return assert(false, "protective fixture must parse"); }
  let pm = pp.value;
  var ok = streq(mbr_entry_type_name(&pm, 0), "GPT protective");
  if mbr_entry_lba_start(&pm, 0) != 1 { ok = false; }
  if mbr_entry_lba_count(&pm, 0) != 4294967294 { ok = false; }
  if !mbr_parse_sized(&pe, 4294967295).is_ok { ok = false; }
  let lvm = one_entry(0, 0, 0, 0, 142, 0, 0, 0, 63, 1024);
  let lp = mbr_parse(&lvm);
  if !lp.is_ok { return assert(false, "LVM fixture must parse"); }
  let lm = lp.value;
  if !streq(mbr_entry_type_name(&lm, 0), "Linux LVM") { ok = false; }
  if mbr_entry_bootable(&lm, 0) { ok = false; }
  if !mbr_entry_in_use(&lm, 0) { ok = false; }
  let b = mbr_build(&lm);
  if !b.is_ok { ok = false; }
  else {
    let bd: Vec[UInt8] = b.value;
    if !mbr_signature_ok(&bd) { ok = false; }
    if ((bd[450] as Int) & 0xFF) != 142 { ok = false; }
  }
  return assert(ok, "protective 0xEE and Linux LVM 0x8E entries parse and rebuild");
}

fn t17() -> TestResult {
  let t = drifted_table();
  var ok = mbr_entry_count(&t) == 1;
  if mbr_entry_boot_flag(&t, 0) != 128 { ok = false; }
  if mbr_entry_boot_flag(&t, 1) != 0 { ok = false; }
  if mbr_entry_type(&t, 1) != -1 { ok = false; }
  if mbr_entry_lba_start(&t, 1) != -1 { ok = false; }
  if mbr_entry_lba_count(&t, 1) != -1 { ok = false; }
  if mbr_entry_start_chs_head(&t, 1) != -1 { ok = false; }
  if mbr_entry_start_chs(&t, 1) != -1 { ok = false; }
  if mbr_entry_end_chs(&t, 1) != -1 { ok = false; }
  if !streq(mbr_entry_type_name(&t, 1), "") { ok = false; }
  if mbr_entry_in_use(&t, 1) { ok = false; }
  if mbr_entry_bootable(&t, 1) { ok = false; }
  if mbr_has_overlap(&t) { ok = false; }
  if !err_bytes_is(mbr_build(&t), "mbr: entry vector mismatch") { ok = false; }
  return assert(ok, "drifted parallel vectors: entry_count is the safe minimum and each accessor guards its vector");
}

fn t18() -> TestResult {
  let t = linux_table();
  var ok = mbr_entry_boot_flag(&t, -1) == -1;
  if mbr_entry_boot_flag(&t, 1) != -1 { ok = false; }
  if mbr_entry_bootable(&t, 1) { ok = false; }
  if mbr_entry_type(&t, -1) != -1 { ok = false; }
  if !streq(mbr_entry_type_name(&t, 1), "") { ok = false; }
  if mbr_entry_start_chs(&t, 1) != -1 { ok = false; }
  if mbr_entry_start_chs_head(&t, 1) != -1 { ok = false; }
  if mbr_entry_start_chs_sector(&t, 1) != -1 { ok = false; }
  if mbr_entry_start_chs_cylinder(&t, 1) != -1 { ok = false; }
  if mbr_entry_end_chs(&t, 1) != -1 { ok = false; }
  if mbr_entry_end_chs_head(&t, 1) != -1 { ok = false; }
  if mbr_entry_end_chs_sector(&t, 1) != -1 { ok = false; }
  if mbr_entry_end_chs_cylinder(&t, 1) != -1 { ok = false; }
  if mbr_entry_lba_start(&t, 1) != -1 { ok = false; }
  if mbr_entry_lba_count(&t, 1) != -1 { ok = false; }
  if mbr_entry_in_use(&t, 1) { ok = false; }
  return assert(ok, "every accessor reports -1/\"\"/false out of range");
}

fn main() -> Int {
  io.println("=== xiom.mbr conformance tests ===");
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
    io.println("xiom.mbr: all tests passed");
  } else {
    io.println("xiom.mbr: tests failed");
  }
  return failed;
}
