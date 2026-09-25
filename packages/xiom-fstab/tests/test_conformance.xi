// XIOM -- xiom.fstab conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 8. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// No Vec[fn] dispatch and no `==` on Str values read from Vec[Str] elements
// (BUG 17: that lowers to a pointer comparison); every string comparison goes
// through compare.str_compare and every element read binds a typed local
// first. Expected values that contain TAB or LF are built with mk_ctrl so the
// test source keeps no raw control bytes.

module fstab_tests
use xiom.io; use xiom.test; use xiom.fstab;
use xiom.string;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when v[i] equals `want`.
fn str_at(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let got: Str = v[i];
  return streq(got, want);
}

// True when v[i] equals `want`.
fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let x: Int = v[i];
  return x == want;
}

// True when the Option[Str] is Some with exactly `want`.
fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

// True when the Option[Str] is None.
fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when the Option[Int] is Some with exactly `want`.
fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

// True when the Option[Int] is None.
fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when two Option[Str] values are equal (None == None).
fn opt_str_eq(a: Option[Str], b: Option[Str]) -> Bool {
  match a {
    Some(x) => {
      match b {
        Some(y) => { return streq(x, y); },
        None => { return false; },
      }
    },
    None => {
      match b {
        Some(_) => { return false; },
        None => { return true; },
      }
    },
  }
  return false;
}

// True when two Option[Int] values are equal (None == None).
fn opt_int_eq(a: Option[Int], b: Option[Int]) -> Bool {
  match a {
    Some(x) => {
      match b {
        Some(y) => { return x == y; },
        None => { return false; },
      }
    },
    None => {
      match b {
        Some(_) => { return false; },
        None => { return true; },
      }
    },
  }
  return false;
}

// True when fstab_parse(text) is Err with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = fstab_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// A Str containing `prefix`, one raw byte `c` and `suffix` (test inputs only;
// the parser must reject control bytes before they are ever emitted, and
// mk_ctrl builds expected decoded TAB/LF values).
fn mk_ctrl(prefix: Str, c: Int, suffix: Str) -> Str {
  var b = Vec[UInt8].new();
  var i = 0;
  while i < prefix.len() {
    b.push(string.byte_at(prefix, i));
    i = i + 1;
  }
  b.push(c as UInt8);
  i = 0;
  while i < suffix.len() {
    b.push(string.byte_at(suffix, i));
    i = i + 1;
  }
  return Str::from_utf8(b);
}

// True when entries i of x and j of y have equal option lists.
fn options_eq(x: &Fstab, i: Int, y: &Fstab, j: Int) -> Bool {
  let a = fstab_options(x, i);
  let b = fstab_options(y, j);
  if a.len() != b.len() { return false; }
  var k = 0;
  while k < a.len() {
    let u: Str = a[k];
    let v: Str = b[k];
    if !streq(u, v) { return false; }
    k = k + 1;
  }
  return true;
}

// True when both documents hold the same entries in the same order (all six
// fields and the option lists; line numbers are layout, not content).
fn same_entries(a: &Fstab, b: &Fstab) -> Bool {
  let na = fstab_entry_count(a);
  if na != fstab_entry_count(b) { return false; }
  var i = 0;
  while i < na {
    if !opt_str_eq(fstab_device(a, i), fstab_device(b, i)) { return false; }
    if !opt_str_eq(fstab_mountpoint(a, i), fstab_mountpoint(b, i)) { return false; }
    if !opt_str_eq(fstab_fstype(a, i), fstab_fstype(b, i)) { return false; }
    if !opt_str_eq(fstab_options_string(a, i), fstab_options_string(b, i)) { return false; }
    if !opt_int_eq(fstab_dump(a, i), fstab_dump(b, i)) { return false; }
    if !opt_int_eq(fstab_pass(a, i), fstab_pass(b, i)) { return false; }
    if !options_eq(a, i, b, i) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = fstab_parse("/dev/sda1\t/\text4\trw,noatime\t0\t1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 1;
      if !opt_str_is(fstab_device(&d, 0), "/dev/sda1") { ok = false; }
      if !opt_str_is(fstab_mountpoint(&d, 0), "/") { ok = false; }
      if !opt_str_is(fstab_fstype(&d, 0), "ext4") { ok = false; }
      if !opt_str_is(fstab_options_string(&d, 0), "rw,noatime") { ok = false; }
      if fstab_option_count(&d, 0) != 2 { ok = false; }
      if !opt_str_is(fstab_option(&d, 0, 0), "rw") { ok = false; }
      if !opt_str_is(fstab_option(&d, 0, 1), "noatime") { ok = false; }
      if !opt_int_is(fstab_dump(&d, 0), 0) { ok = false; }
      if !opt_int_is(fstab_pass(&d, 0), 1) { ok = false; }
      if fstab_line(&d, 0) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "single entry: six fields decoded");
}

fn t2() -> TestResult {
  let r = fstab_parse("dev1  /mnt/one\text4\trw,noatime\t1\t2\r\ndev2 /mnt/two xfs defaults 0 0");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 2;
      if !opt_str_is(fstab_device(&d, 0), "dev1") { ok = false; }
      if !opt_str_is(fstab_mountpoint(&d, 0), "/mnt/one") { ok = false; }
      if !opt_int_is(fstab_dump(&d, 0), 1) { ok = false; }
      if !opt_int_is(fstab_pass(&d, 0), 2) { ok = false; }
      if fstab_line(&d, 0) != 1 { ok = false; }
      if !opt_str_is(fstab_device(&d, 1), "dev2") { ok = false; }
      if !opt_str_is(fstab_fstype(&d, 1), "xfs") { ok = false; }
      if fstab_line(&d, 1) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multiple entries: CRLF and missing final newline");
}

fn t3() -> TestResult {
  let r = fstab_parse("# header\n\n   \t \n# another\n/dev/a\t/mnt/a\text4\tdefaults\t0\t0 # trailing\ndev2 /mnt/b ext4 defaults 0 1#tight\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 2;
      if !opt_str_is(fstab_device(&d, 0), "/dev/a") { ok = false; }
      if fstab_line(&d, 0) != 5 { ok = false; }
      if !opt_str_is(fstab_device(&d, 1), "dev2") { ok = false; }
      if !opt_int_is(fstab_pass(&d, 1), 1) { ok = false; }
      if fstab_line(&d, 1) != 6 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let e = fstab_parse("");
  match e {
    Ok(d2) => { if fstab_entry_count(&d2) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let c = fstab_parse("\n\n# only comments\n");
  match c {
    Ok(d3) => { if fstab_entry_count(&d3) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  if !parse_err_is("dev#x mnt ext4 defaults 0 0\n", "fstab: too few fields in line 1") { ok = false; }
  return assert(ok, "comments and blank lines skipped; first # always cuts");
}

fn t4() -> TestResult {
  let r = fstab_parse("/dev/disk\\040one\t/mnt/my\\040disk\tntfs\\0403g\trw\t0\t0\n/dev/ta\\011b\t/mnt/x\\012y\tfs\\134x\tdefaults\t1\t2\n/x\\0400\t/s\\1341\text4\tdefaults\t0\t0\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 3;
      if !opt_str_is(fstab_device(&d, 0), "/dev/disk one") { ok = false; }
      if !opt_str_is(fstab_mountpoint(&d, 0), "/mnt/my disk") { ok = false; }
      if !opt_str_is(fstab_fstype(&d, 0), "ntfs 3g") { ok = false; }
      let want_dev = mk_ctrl("/dev/ta", 9, "b");
      if !opt_str_is(fstab_device(&d, 1), want_dev) { ok = false; }
      let want_mnt = mk_ctrl("/mnt/x", 10, "y");
      if !opt_str_is(fstab_mountpoint(&d, 1), want_mnt) { ok = false; }
      if !opt_str_is(fstab_fstype(&d, 1), "fs\\x") { ok = false; }
      if !opt_str_is(fstab_device(&d, 2), "/x 0") { ok = false; }
      if !opt_str_is(fstab_mountpoint(&d, 2), "/s\\1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "escapes decode in device, mountpoint and fstype");
}

fn t5() -> TestResult {
  let r = fstab_parse("/dev/disk\\040one\t/mnt/a\text4\tdefaults\t0\t0\n/dev/t\\011b\t/mnt/n\\012x\tf\\134s\tdefaults\t1\t1\n");
  var ok = true;
  match r {
    Ok(d) => {
      let s1 = fstab_emit(&d);
      if !streq(s1, "/dev/disk\\040one\t/mnt/a\text4\tdefaults\t0\t0\n/dev/t\\011b\t/mnt/n\\012x\tf\\134s\tdefaults\t1\t1\n") { ok = false; }
      let r2 = fstab_parse(s1);
      match r2 {
        Ok(d2) => {
          if !same_entries(&d, &d2) { ok = false; }
          if !streq(fstab_emit(&d2), s1) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit re-encodes escapes and round-trips");
}

fn t6() -> TestResult {
  let r = fstab_parse("d m ext4 rw,noatime,x-systemd.automount,uid=1000 0 0\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_option_count(&d, 0) == 4;
      if !opt_str_is(fstab_option(&d, 0, 0), "rw") { ok = false; }
      if !opt_str_is(fstab_option(&d, 0, 1), "noatime") { ok = false; }
      if !opt_str_is(fstab_option(&d, 0, 2), "x-systemd.automount") { ok = false; }
      if !opt_str_is(fstab_option(&d, 0, 3), "uid=1000") { ok = false; }
      if !opt_str_is(fstab_options_string(&d, 0), "rw,noatime,x-systemd.automount,uid=1000") { ok = false; }
      if !fstab_has_option(&d, 0, "noatime") { ok = false; }
      if !fstab_has_option(&d, 0, "uid=1000") { ok = false; }
      if fstab_has_option(&d, 0, "atime") { ok = false; }
      if fstab_has_option(&d, 0, "NOATIME") { ok = false; }
      var names = fstab_options(&d, 0);
      if names.len() != 4 { ok = false; }
      if !str_at(&names, 2, "x-systemd.automount") { ok = false; }
      names.push("mutated");
      if fstab_option_count(&d, 0) != 4 { ok = false; }
      if !opt_str_none(fstab_option(&d, 0, 4)) { ok = false; }
      if !opt_str_none(fstab_option(&d, 0, -1)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "options: comma list order, accessors, fresh copy");
}

fn t7() -> TestResult {
  let r = fstab_parse("d1 / ext4 rw 0 1\nd2 /y ext4 ro 0 1\nd3 /z ext4 defaults 0 1\nd4 /w ext4 rw,ro 0 1\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 4;
      if !fstab_has_option(&d, 0, "rw") { ok = false; }
      if fstab_has_option(&d, 0, "ro") { ok = false; }
      if !fstab_has_option(&d, 1, "ro") { ok = false; }
      if fstab_has_option(&d, 1, "rw") { ok = false; }
      if !fstab_has_option(&d, 2, "defaults") { ok = false; }
      if fstab_has_option(&d, 2, "rw") { ok = false; }
      if fstab_has_option(&d, 2, "ro") { ok = false; }
      if !fstab_has_option(&d, 3, "rw") { ok = false; }
      if !fstab_has_option(&d, 3, "ro") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "rw/ro are not enforced, exclusive or implied");
}

fn t8() -> TestResult {
  let r = fstab_parse("d0 m0 f0 defaults 0 0\nd1 m1 f1 defaults 1 1\nd2 m2 f2 defaults 2 2\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 3;
      if !opt_int_is(fstab_dump(&d, 0), 0) { ok = false; }
      if !opt_int_is(fstab_pass(&d, 0), 0) { ok = false; }
      if !opt_int_is(fstab_dump(&d, 1), 1) { ok = false; }
      if !opt_int_is(fstab_pass(&d, 1), 1) { ok = false; }
      if !opt_int_is(fstab_dump(&d, 2), 2) { ok = false; }
      if !opt_int_is(fstab_pass(&d, 2), 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "dump/pass accept exactly 0, 1 and 2");
}

fn t9() -> TestResult {
  var ok = parse_err_is("d m f defaults 3 0\n", "fstab: bad dump: 3");
  if !parse_err_is("d m f defaults 10 0\n", "fstab: bad dump: 10") { ok = false; }
  if !parse_err_is("d m f defaults x 0\n", "fstab: bad dump: x") { ok = false; }
  if !parse_err_is("d m f defaults -1 0\n", "fstab: bad dump: -1") { ok = false; }
  if !parse_err_is("d m f defaults 0 3\n", "fstab: bad pass: 3") { ok = false; }
  if !parse_err_is("d m f defaults 0 00\n", "fstab: bad pass: 00") { ok = false; }
  if !parse_err_is("d m f defaults 2 12\n", "fstab: bad pass: 12") { ok = false; }
  return assert(ok, "bad dump/pass rejected with exact errors");
}

fn t10() -> TestResult {
  var ok = parse_err_is("dev\n", "fstab: too few fields in line 1");
  if !parse_err_is("dev mnt\n", "fstab: too few fields in line 1") { ok = false; }
  if !parse_err_is("dev mnt ext4\n", "fstab: too few fields in line 1") { ok = false; }
  if !parse_err_is("dev mnt ext4 defaults\n", "fstab: too few fields in line 1") { ok = false; }
  if !parse_err_is("dev mnt ext4 defaults 0\n", "fstab: too few fields in line 1") { ok = false; }
  if !parse_err_is("dev mnt ext4 defaults 0 ", "fstab: too few fields in line 1") { ok = false; }
  if !parse_err_is("\n# note\ndev mnt ext4 defaults 0\n", "fstab: too few fields in line 3") { ok = false; }
  let r = fstab_parse("   \n\t\n# c\n\n");
  match r {
    Ok(d) => { if fstab_entry_count(&d) != 0 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "too few fields: exact errors; blanks are not entries");
}

fn t11() -> TestResult {
  var ok = parse_err_is("d m f defaults 0 0 extra\n", "fstab: too many fields in line 1");
  if !parse_err_is("d m f defaults 0 0 0\n", "fstab: too many fields in line 1") { ok = false; }
  if !parse_err_is("# c\nd m f defaults 0 0 x\n", "fstab: too many fields in line 2") { ok = false; }
  return assert(ok, "too many fields: exact errors");
}

fn t12() -> TestResult {
  var ok = parse_err_is("a\\b m f defaults 0 0\n", "fstab: bad escape in device: a\\b");
  if !parse_err_is("x\\07 m f defaults 0 0\n", "fstab: bad escape in device: x\\07") { ok = false; }
  if !parse_err_is("\\ m f defaults 0 0\n", "fstab: bad escape in device: \\") { ok = false; }
  if !parse_err_is("d /mnt\\q f defaults 0 0\n", "fstab: bad escape in mountpoint: /mnt\\q") { ok = false; }
  if !parse_err_is("d m ext\\4 defaults 0 0\n", "fstab: bad escape in fstype: ext\\4") { ok = false; }
  if !parse_err_is("d m f defaults x\\040 0\n", "fstab: bad dump: x\\040") { ok = false; }
  let r = fstab_parse("a\\1340b m f defaults 0 0\n");
  var ok2 = false;
  match r {
    Ok(d) => { ok2 = opt_str_is(fstab_device(&d, 0), "a\\0b"); },
    Err(_) => { ok2 = false; },
  }
  if !ok2 { ok = false; }
  return assert(ok, "bad escapes rejected; \\134 plus a digit round-trips");
}

fn t13() -> TestResult {
  var ok = parse_err_is("\\040 m f defaults 0 0\n", "fstab: empty device: \\040");
  if !parse_err_is("d \\011 f defaults 0 0\n", "fstab: empty mountpoint: \\011") { ok = false; }
  if !parse_err_is("d m \\012 defaults 0 0\n", "fstab: empty fstype: \\012") { ok = false; }
  if !parse_err_is("d \\040\\011 f defaults 0 0\n", "fstab: empty mountpoint: \\040\\011") { ok = false; }
  if !parse_err_is("\\012\\040 m f defaults 0 0\n", "fstab: empty device: \\012\\040") { ok = false; }
  return assert(ok, "whitespace-only word fields are rejected as empty");
}

fn t14() -> TestResult {
  var ok = parse_err_is(mk_ctrl("d", 1, " m f defaults 0 0\n"), "fstab: control byte in line 1");
  if !parse_err_is(mk_ctrl("d m f defaults 0 ", 127, "\n"), "fstab: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("d m f defaults 0 0", 11, "\n"), "fstab: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("d m f defaults 0 ", 31, "\n"), "fstab: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("d m", 13, " f defaults 0 0\n"), "fstab: control byte in line 1") { ok = false; }
  if !parse_err_is(mk_ctrl("# ok", 1, "\n"), "fstab: control byte in line 1") { ok = false; }
  if !parse_err_is("d m f defaults 0 0\n" + mk_ctrl("d2 m2 f2 defaults 0 ", 11, "\n"), "fstab: control byte in line 2") { ok = false; }
  let r = fstab_parse("d\tm\tf\tdefaults\t0\t0\r\nd2 m2 f2 defaults 1 1\n");
  match r {
    Ok(d) => {
      if fstab_entry_count(&d) != 2 { ok = false; }
      if !opt_str_is(fstab_device(&d, 1), "d2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "control bytes rejected; TAB and CRLF accepted");
}

fn t15() -> TestResult {
  let r = fstab_parse("/dev/sda1\t/mnt/dup\text4\tdefaults\t0\t0\n/dev/sdb1\t/mnt/other\txfs\trw\t1\t1\n/dev/sdc1\t/mnt/dup\txfs\tro\t0\t2\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 3;
      if fstab_mountpoint_index(&d, "/mnt/dup") != 0 { ok = false; }
      let all = fstab_entries_for_mountpoint(&d, "/mnt/dup");
      if all.len() != 2 { ok = false; }
      if !int_at(&all, 0, 0) { ok = false; }
      if !int_at(&all, 1, 2) { ok = false; }
      if fstab_mountpoint_index(&d, "/mnt/other") != 1 { ok = false; }
      if fstab_mountpoint_index(&d, "/mnt/absent") != -1 { ok = false; }
      if fstab_entries_for_mountpoint(&d, "/mnt/absent").len() != 0 { ok = false; }
      if !opt_str_is(fstab_device(&d, 2), "/dev/sdc1") { ok = false; }
      if !opt_str_is(fstab_fstype(&d, 2), "xfs") { ok = false; }
      if !opt_int_is(fstab_pass(&d, 2), 2) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate mountpoints preserved; first-match policy");
}

fn t16() -> TestResult {
  let r = fstab_parse("  dev1   /mnt/a\text4 \t defaults 0 0  \n\tdev2\t/mnt/b\txfs\trw\t1\t2\n");
  var ok = false;
  match r {
    Ok(d) => { ok = streq(fstab_emit(&d), "dev1\t/mnt/a\text4\tdefaults\t0\t0\ndev2\t/mnt/b\txfs\trw\t1\t2\n"); },
    Err(_) => { ok = false; },
  }
  let e1 = fstab_parse("");
  match e1 {
    Ok(d2) => { if !streq(fstab_emit(&d2), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  let e2 = fstab_parse("# only comments\n\n");
  match e2 {
    Ok(d3) => { if !streq(fstab_emit(&d3), "") { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emit: single tabs, trailing LF, empty docs");
}

fn t17() -> TestResult {
  let text = "# /etc/fstab\n/dev/sda1  /mnt/one\text4\trw,noatime\t0\t1\n\n/dev/disk\\040two\t/mnt/my\\040disk\tntfs-3g\tdefaults,uid=1000\t0\t2 # data\n";
  let r1 = fstab_parse(text);
  var ok = true;
  match r1 {
    Ok(d1) => {
      let s1 = fstab_emit(&d1);
      if !streq(s1, "/dev/sda1\t/mnt/one\text4\trw,noatime\t0\t1\n/dev/disk\\040two\t/mnt/my\\040disk\tntfs-3g\tdefaults,uid=1000\t0\t2\n") { ok = false; }
      let r2 = fstab_parse(s1);
      match r2 {
        Ok(d2) => {
          if !same_entries(&d1, &d2) { ok = false; }
          if !streq(fstab_emit(&d2), s1) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "round-trip: parse(emit(parse(x))) keeps entries");
}

fn t18() -> TestResult {
  let r = fstab_parse("d m f defaults 0 0\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 1;
      if !opt_str_none(fstab_device(&d, -1)) { ok = false; }
      if !opt_str_none(fstab_device(&d, 1)) { ok = false; }
      if !opt_str_none(fstab_mountpoint(&d, 9)) { ok = false; }
      if !opt_str_none(fstab_fstype(&d, 1)) { ok = false; }
      if !opt_str_none(fstab_options_string(&d, 1)) { ok = false; }
      if fstab_option_count(&d, 1) != 0 { ok = false; }
      if !opt_str_none(fstab_option(&d, 0, -1)) { ok = false; }
      if !opt_str_none(fstab_option(&d, 0, 1)) { ok = false; }
      if fstab_options(&d, 5).len() != 0 { ok = false; }
      if fstab_has_option(&d, 1, "defaults") { ok = false; }
      if !opt_int_none(fstab_dump(&d, 1)) { ok = false; }
      if !opt_int_none(fstab_pass(&d, -1)) { ok = false; }
      if fstab_line(&d, 1) != 0 { ok = false; }
      if fstab_mountpoint_index(&d, "/mnt/x") != -1 { ok = false; }
      if fstab_entries_for_mountpoint(&d, "/mnt/x").len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessor guards: out-of-range and absent queries");
}

fn t19() -> TestResult {
  var ok = parse_err_is("d m f , 0 0\n", "fstab: empty option: ,");
  if !parse_err_is("d m f rw, 0 0\n", "fstab: empty option: rw,") { ok = false; }
  if !parse_err_is("d m f ,rw 0 0\n", "fstab: empty option: ,rw") { ok = false; }
  if !parse_err_is("d m f rw,,ro 0 0\n", "fstab: empty option: rw,,ro") { ok = false; }
  let r = fstab_parse("d m f rw 0 0\nd2 m2 f2 a,b 1 1\n");
  var ok2 = false;
  match r {
    Ok(d) => {
      ok2 = fstab_option_count(&d, 0) == 1;
      if fstab_option_count(&d, 1) != 2 { ok2 = false; }
      if !fstab_has_option(&d, 1, "b") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  if !ok2 { ok = false; }
  return assert(ok, "empty option elements rejected; single options accepted");
}

fn t20() -> TestResult {
  let r = fstab_parse("/dev/café\t/mnt/données\text4\tdefaults\t0\t0 # λ\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = fstab_entry_count(&d) == 1;
      if !opt_str_is(fstab_device(&d, 0), "/dev/café") { ok = false; }
      if !opt_str_is(fstab_mountpoint(&d, 0), "/mnt/données") { ok = false; }
      let s = fstab_emit(&d);
      if !streq(s, "/dev/café\t/mnt/données\text4\tdefaults\t0\t0\n") { ok = false; }
      let r2 = fstab_parse(s);
      match r2 {
        Ok(d2) => { if !same_entries(&d, &d2) { ok = false; } },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "non-ASCII bytes pass through fields and comments");
}

fn main() -> Int {
  io.println("=== xiom.fstab conformance tests ===");
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
    io.println("xiom.fstab: all tests passed");
  } else {
    io.println("xiom.fstab: tests failed");
  }
  return failed;
}
