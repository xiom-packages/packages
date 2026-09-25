// XIOM -- xiom.gpx conformance tests (29 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.gpx module against the documented GPX subset:
// happy paths, coordinate boundaries and rounding, entity handling, canonical
// build output, round-trips and the full error catalog. All Str equality goes
// through xiom.string.compare.str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison).

module gpx_tests
use xiom.io; use xiom.test; use xiom.gpx;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn int_at(v: &Vec[Int], i: Int, want: Int) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  let x: Int = v[i];
  return x == want;
}

fn parse_fails(text: Str) -> Bool {
  let r = gpx_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = gpx_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// Structural and textual equality of two documents.
fn same_doc(a: &GpxDoc, b: &GpxDoc) -> Bool {
  if a.kinds.len() != b.kinds.len() { return false; }
  if a.field_owners.len() != b.field_owners.len() { return false; }
  let va: Str = a.version;
  let vb: Str = b.version;
  if compare.str_compare(va, vb) != 0 { return false; }
  let ca: Str = a.creator;
  let cb: Str = b.creator;
  if compare.str_compare(ca, cb) != 0 { return false; }
  var i = 0;
  while i < a.kinds.len() {
    let ka: Int = a.kinds[i];
    let kb: Int = b.kinds[i];
    if ka != kb { return false; }
    let pa: Int = a.parents[i];
    let pb: Int = b.parents[i];
    if pa != pb { return false; }
    if ka == 1 || ka == 5 {
      let la: Int = a.lat_udeg[i];
      let lb: Int = b.lat_udeg[i];
      if la != lb { return false; }
      let oa: Int = a.lon_udeg[i];
      let ob: Int = b.lon_udeg[i];
      if oa != ob { return false; }
    }
    i = i + 1;
  }
  var j = 0;
  while j < a.field_owners.len() {
    let fa: Int = a.field_owners[j];
    let fb: Int = b.field_owners[j];
    if fa != fb { return false; }
    let fka: Int = a.field_kinds[j];
    let fkb: Int = b.field_kinds[j];
    if fka != fkb { return false; }
    let fa_v: Str = a.field_values[j];
    let fb_v: Str = b.field_values[j];
    if compare.str_compare(fa_v, fb_v) != 0 { return false; }
    j = j + 1;
  }
  return true;
}

fn t1() -> TestResult {
  let r = gpx_parse("<gpx version=\"1.1\" creator=\"unit test\"></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 1;
      if gpx_kind(&d, 0) != 0 { ok = false; }
      if gpx_parent(&d, 0) != -1 { ok = false; }
      if !streq(gpx_version(&d), "1.1") { ok = false; }
      if !streq(gpx_creator(&d), "unit test") { ok = false; }
      if gpx_children(&d, 0).len() != 0 { ok = false; }
      if !opt_str_none(gpx_field(&d, 0, 0)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "root element with version and creator");
}

fn t2() -> TestResult {
  let r = gpx_parse("<gpx><wpt lat=\"37.5\" lon=\"-122.4\"><name>Start</name></wpt></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 2;
      if gpx_kind(&d, 1) != 1 { ok = false; }
      if gpx_parent(&d, 1) != 0 { ok = false; }
      if !opt_int_is(gpx_lat_udeg(&d, 1), 37500000) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 1), -122400000) { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 0), "Start") { ok = false; }
      if !opt_str_none(gpx_field(&d, 1, 1)) { ok = false; }
      if !gpx_has_field(&d, 1, 0) { ok = false; }
      if gpx_has_field(&d, 0, 0) { ok = false; }
      if gpx_field_count(&d, 1) != 1 { ok = false; }
      let kids = gpx_children(&d, 0);
      if kids.len() != 1 { ok = false; }
      if !int_at(&kids, 0, 1) { ok = false; }
      if gpx_children(&d, 1).len() != 0 { ok = false; }
      let wp = gpx_nodes_of_kind(&d, 1);
      if wp.len() != 1 { ok = false; }
      if !int_at(&wp, 0, 1) { ok = false; }
      if gpx_nodes_of_kind(&d, 5).len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "waypoint coordinates, name and child queries");
}

fn t3() -> TestResult {
  let r = gpx_parse("<gpx><wpt lat=\"90\" lon=\"-180\"/><wpt lat=\"-90.0\" lon=\"180.0\"/><wpt lat=\"1.0000005\" lon=\"0.0000004\"/><wpt lat=\"+12.5\" lon=\"12.500001\"/></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 5;
      if !opt_int_is(gpx_lat_udeg(&d, 1), 90000000) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 1), -180000000) { ok = false; }
      if !opt_int_is(gpx_lat_udeg(&d, 2), -90000000) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 2), 180000000) { ok = false; }
      if !opt_int_is(gpx_lat_udeg(&d, 3), 1000001) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 3), 0) { ok = false; }
      if !opt_int_is(gpx_lat_udeg(&d, 4), 12500000) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 4), 12500001) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "coordinate boundaries and half-away rounding");
}

fn t4() -> TestResult {
  var ok = streq(gpx_coord_text(0), "0.0");
  if !streq(gpx_coord_text(1), "0.000001") { ok = false; }
  if !streq(gpx_coord_text(-1), "-0.000001") { ok = false; }
  if !streq(gpx_coord_text(90000000), "90.0") { ok = false; }
  if !streq(gpx_coord_text(-122400000), "-122.4") { ok = false; }
  if !streq(gpx_coord_text(12345678), "12.345678") { ok = false; }
  if !streq(gpx_coord_text(12345600), "12.3456") { ok = false; }
  if !streq(gpx_coord_text(37500000), "37.5") { ok = false; }
  if !opt_int_is(gpx_coord_parse("37.5"), 37500000) { ok = false; }
  if !opt_int_is(gpx_coord_parse("+37.5"), 37500000) { ok = false; }
  if !opt_int_is(gpx_coord_parse("-180"), -180000000) { ok = false; }
  if !opt_int_is(gpx_coord_parse("180"), 180000000) { ok = false; }
  if !opt_int_is(gpx_coord_parse("90.000001"), 90000001) { ok = false; }
  if !opt_int_none(gpx_coord_parse("180.000001")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("1000000")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("abc")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("")) { ok = false; }
  if !opt_int_none(gpx_coord_parse(".5")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("1.")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("1e2")) { ok = false; }
  if !opt_int_none(gpx_coord_parse(" 1")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("1 ")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("12.34.5")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("+")) { ok = false; }
  if !opt_int_none(gpx_coord_parse("-")) { ok = false; }
  return assert(ok, "coordinate text and parse helpers");
}

fn t5() -> TestResult {
  let r = gpx_parse("<gpx><wpt lat=\"0\" lon=\"0\"><name>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;</name><desc>&#x2603;</desc></wpt></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = opt_str_is(gpx_field(&d, 1, 0), "&<>\"'AB");
      let snow = gpx_field(&d, 1, 1);
      match snow {
        Some(v) => {
          if v.len() != 3 { ok = false; }
          let b0: Int = string.byte_at(v, 0) as Int;
          let b1: Int = string.byte_at(v, 1) as Int;
          let b2: Int = string.byte_at(v, 2) as Int;
          if b0 != 226 { ok = false; }
          if b1 != 152 { ok = false; }
          if b2 != 131 { ok = false; }
        },
        None => { ok = false; },
      }
      let built = gpx_build(&d);
      if !string.str_contains(built, "&amp;&lt;&gt;\"'AB") { ok = false; }
      let r2 = gpx_parse(built);
      match r2 {
        Ok(d2) => {
          if !opt_str_is(gpx_field(&d2, 1, 0), "&<>\"'AB") { ok = false; }
          let snow2 = gpx_field(&d2, 1, 1);
          match snow2 {
            Some(w) => {
              if w.len() != 3 { ok = false; }
              let c0: Int = string.byte_at(w, 0) as Int;
              let c1: Int = string.byte_at(w, 1) as Int;
              let c2: Int = string.byte_at(w, 2) as Int;
              if c0 != 226 { ok = false; }
              if c1 != 152 { ok = false; }
              if c2 != 131 { ok = false; }
            },
            None => { ok = false; },
          }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "predefined and numeric entities decode and re-escape");
}

fn t6() -> TestResult {
  let r = gpx_parse("<gpx><rte><name>R</name><desc>d&amp;d</desc><sym>Flag</sym><type>road</type></rte></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 2;
      if gpx_kind(&d, 1) != 2 { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 0), "R") { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 1), "d&d") { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 2), "Flag") { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 3), "road") { ok = false; }
      if !opt_str_none(gpx_field(&d, 1, 4)) { ok = false; }
      if gpx_field_count(&d, 1) != 4 { ok = false; }
      if !opt_int_none(gpx_lat_udeg(&d, 1)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "route metadata fields");
}

fn t7() -> TestResult {
  let r = gpx_parse("<gpx><trk><name>T</name><trkseg><trkpt lat=\"1\" lon=\"2\"><ele>3.5</ele><time>t1</time></trkpt><trkpt lat=\"3\" lon=\"4\"/></trkseg><trkseg/></trk></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 6;
      if gpx_kind(&d, 1) != 3 { ok = false; }
      if gpx_kind(&d, 2) != 4 { ok = false; }
      if gpx_kind(&d, 3) != 5 { ok = false; }
      if gpx_kind(&d, 4) != 5 { ok = false; }
      if gpx_kind(&d, 5) != 4 { ok = false; }
      if gpx_parent(&d, 2) != 1 { ok = false; }
      if gpx_parent(&d, 3) != 2 { ok = false; }
      if gpx_parent(&d, 4) != 2 { ok = false; }
      if gpx_parent(&d, 5) != 1 { ok = false; }
      if gpx_children(&d, 1).len() != 2 { ok = false; }
      if gpx_children(&d, 2).len() != 2 { ok = false; }
      if gpx_children(&d, 5).len() != 0 { ok = false; }
      if !opt_int_is(gpx_lat_udeg(&d, 3), 1000000) { ok = false; }
      if !opt_int_is(gpx_lon_udeg(&d, 4), 4000000) { ok = false; }
      if !opt_str_is(gpx_field(&d, 3, 4), "3.5") { ok = false; }
      if !opt_str_is(gpx_field(&d, 3, 5), "t1") { ok = false; }
      if !opt_str_none(gpx_field(&d, 4, 4)) { ok = false; }
      let segs = gpx_nodes_of_kind(&d, 4);
      if segs.len() != 2 { ok = false; }
      if !int_at(&segs, 0, 2) { ok = false; }
      if !int_at(&segs, 1, 5) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "track, segment and trackpoint structure");
}

fn t8() -> TestResult {
  let r = gpx_parse("<gpx version=\"1\" creator=\"c\"><wpt lat=\"1\" lon=\"2\"/><trk><trkseg/></trk><rte><name/></rte></gpx>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 5;
      if gpx_field_count(&d, 1) != 0 { ok = false; }
      if !opt_str_none(gpx_field(&d, 1, 0)) { ok = false; }
      if gpx_kind(&d, 2) != 3 { ok = false; }
      if gpx_kind(&d, 3) != 4 { ok = false; }
      if gpx_children(&d, 2).len() != 1 { ok = false; }
      if gpx_children(&d, 3).len() != 0 { ok = false; }
      if gpx_kind(&d, 4) != 2 { ok = false; }
      if !opt_str_is(gpx_field(&d, 4, 0), "") { ok = false; }
      if gpx_field_count(&d, 4) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "self-closing and empty metadata elements");
}

fn t9() -> TestResult {
  let r = gpx_parse("  <?xml version=\"1.0\"?>\n\t<gpx\n  version = \"1.1\"\n  creator='c'\n>\n  <wpt lat='0' lon='0'>\n    <name>  spaced  </name>\n  </wpt>\n</gpx>\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(gpx_version(&d), "1.1");
      if !streq(gpx_creator(&d), "c") { ok = false; }
      if !opt_str_is(gpx_field(&d, 1, 0), "  spaced  ") { ok = false; }
      if gpx_node_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "declaration, whitespace and single-quoted values");
}

fn t10() -> TestResult {
  var d = gpx_new("1.1", "xiom-gpx-tests");
  let w = gpx_add_waypoint(&mut d, 37500000, -122400000);
  let set_ok = gpx_set_field(&mut d, w, 0, "A&B <x>");
  var ok = w == 1;
  if !set_ok { ok = false; }
  let built = gpx_build(&d);
  let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"xiom-gpx-tests\">\n  <wpt lat=\"37.5\" lon=\"-122.4\">\n    <name>A&amp;B &lt;x&gt;</name>\n  </wpt>\n</gpx>\n";
  if !streq(built, want) { ok = false; }
  return assert(ok, "canonical build of a waypoint");
}

fn t11() -> TestResult {
  var d = gpx_new("1.1", "c");
  let w = gpx_add_waypoint(&mut d, 0, 0);
  gpx_set_field(&mut d, w, 5, "t");
  gpx_set_field(&mut d, w, 4, "e");
  gpx_set_field(&mut d, w, 0, "n");
  let built = gpx_build(&d);
  let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"c\">\n  <wpt lat=\"0.0\" lon=\"0.0\">\n    <name>n</name>\n    <ele>e</ele>\n    <time>t</time>\n  </wpt>\n</gpx>\n";
  var ok = streq(built, want);
  if gpx_field_count(&d, w) != 3 { ok = false; }
  return assert(ok, "canonical field order name, ele, time");
}

fn t12() -> TestResult {
  var d = gpx_new("1.1", "c");
  let trk = gpx_add_track(&mut d);
  gpx_set_field(&mut d, trk, 0, "T");
  let seg = gpx_add_segment(&mut d, trk);
  let p1 = gpx_add_trackpoint(&mut d, seg, 1000000, -2000000);
  gpx_set_field(&mut d, p1, 5, "t");
  let seg2 = gpx_add_segment(&mut d, trk);
  let built = gpx_build(&d);
  let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"c\">\n  <trk>\n    <name>T</name>\n    <trkseg>\n      <trkpt lat=\"1.0\" lon=\"-2.0\">\n        <time>t</time>\n      </trkpt>\n    </trkseg>\n    <trkseg/>\n  </trk>\n</gpx>\n";
  var ok = streq(built, want);
  if trk != 1 { ok = false; }
  if seg != 2 { ok = false; }
  if p1 != 3 { ok = false; }
  if seg2 != 4 { ok = false; }
  return assert(ok, "canonical build of tracks, segments and points");
}

fn t13() -> TestResult {
  var d = gpx_new("", "");
  var ok = gpx_add_segment(&mut d, 0) == -1;
  if gpx_add_trackpoint(&mut d, 0, 0, 0) != -1 { ok = false; }
  if gpx_add_waypoint(&mut d, 90000001, 0) != -1 { ok = false; }
  if gpx_add_waypoint(&mut d, 0, 180000001) != -1 { ok = false; }
  if gpx_set_field(&mut d, 0, 0, "x") { ok = false; }
  if gpx_set_field(&mut d, 1, 0, "x") { ok = false; }
  if gpx_set_field(&mut d, 0, 6, "x") { ok = false; }
  let w = gpx_add_waypoint(&mut d, -90000000, 180000000);
  if w != 1 { ok = false; }
  if !gpx_set_field(&mut d, w, 0, "a") { ok = false; }
  if !gpx_set_field(&mut d, w, 0, "b") { ok = false; }
  if gpx_field_count(&d, w) != 1 { ok = false; }
  if !opt_str_is(gpx_field(&d, w, 0), "b") { ok = false; }
  if gpx_kind(&d, w) != 1 { ok = false; }
  if gpx_parent(&d, w) != 0 { ok = false; }
  return assert(ok, "builder validates parents, ranges and replaces fields");
}

fn t14() -> TestResult {
  let r = gpx_parse("<gpx/>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = gpx_node_count(&d) == 1;
      if gpx_kind(&d, -1) != -1 { ok = false; }
      if gpx_kind(&d, 99) != -1 { ok = false; }
      if gpx_parent(&d, 99) != -2 { ok = false; }
      if gpx_parent(&d, 0) != -1 { ok = false; }
      if !opt_int_none(gpx_lat_udeg(&d, 0)) { ok = false; }
      if !opt_int_none(gpx_lat_udeg(&d, 99)) { ok = false; }
      if !opt_int_none(gpx_lon_udeg(&d, 0)) { ok = false; }
      if !opt_str_none(gpx_field(&d, 0, 0)) { ok = false; }
      if !opt_str_none(gpx_field(&d, 0, 9)) { ok = false; }
      if gpx_has_field(&d, 99, 0) { ok = false; }
      if gpx_field_count(&d, 99) != 0 { ok = false; }
      if gpx_children(&d, 99).len() != 0 { ok = false; }
      if gpx_nodes_of_kind(&d, 5).len() != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors are safe out of range");
}

fn t15() -> TestResult {
  let src = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"xiom-gpx-tests\">\n  <wpt lat=\"37.5\" lon=\"-122.4\">\n    <name>Start</name>\n    <desc>first &amp; last</desc>\n    <sym>Flag</sym>\n    <type>wpt</type>\n    <ele>12.5</ele>\n    <time>2026-01-01T00:00:00Z</time>\n  </wpt>\n  <rte>\n    <name>R1</name>\n  </rte>\n  <trk>\n    <name>T1</name>\n    <trkseg>\n      <trkpt lat=\"0\" lon=\"0\"/>\n      <trkpt lat=\"-90.0\" lon=\"180.0\"><ele>-3.5</ele></trkpt>\n    </trkseg>\n  </trk>\n</gpx>\n";
  let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"xiom-gpx-tests\">\n  <wpt lat=\"37.5\" lon=\"-122.4\">\n    <name>Start</name>\n    <desc>first &amp; last</desc>\n    <sym>Flag</sym>\n    <type>wpt</type>\n    <ele>12.5</ele>\n    <time>2026-01-01T00:00:00Z</time>\n  </wpt>\n  <rte>\n    <name>R1</name>\n  </rte>\n  <trk>\n    <name>T1</name>\n    <trkseg>\n      <trkpt lat=\"0.0\" lon=\"0.0\"/>\n      <trkpt lat=\"-90.0\" lon=\"180.0\">\n        <ele>-3.5</ele>\n      </trkpt>\n    </trkseg>\n  </trk>\n</gpx>\n";
  var ok = false;
  let r = gpx_parse(src);
  match r {
    Ok(d) => {
      let built = gpx_build(&d);
      ok = streq(built, want);
      let r2 = gpx_parse(built);
      match r2 {
        Ok(d2) => {
          if !streq(gpx_build(&d2), built) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical build is exact and idempotent");
}

fn t16() -> TestResult {
  let src = "<gpx version=\"1.1\" creator=\"c\"><wpt lat=\"1.5\" lon=\"2.25\"><name>a</name><ele>10</ele></wpt><trk><trkseg><trkpt lat=\"-1\" lon=\"-2\"/><trkpt lat=\"3\" lon=\"4\"><time>t</time></trkpt></trkseg></trk></gpx>";
  var ok = false;
  let r1 = gpx_parse(src);
  match r1 {
    Ok(d1) => {
      let built = gpx_build(&d1);
      let r2 = gpx_parse(built);
      match r2 {
        Ok(d2) => {
          ok = same_doc(&d1, &d2);
          if gpx_node_count(&d2) != 6 { ok = false; }
          if !opt_int_is(gpx_lat_udeg(&d2, 1), 1500000) { ok = false; }
          if !opt_str_none(gpx_field(&d2, 1, 1)) { ok = false; }
          if !opt_str_is(gpx_field(&d2, 1, 4), "10") { ok = false; }
          if !opt_str_is(gpx_field(&d2, 5, 5), "t") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse, build, parse preserves the document");
}

fn t17() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"></rte></gpx>", "gpx: mismatched closing tag");
  if !parse_err_prefix("<gpx></wpt></gpx>", "gpx: mismatched closing tag") { ok = false; }
  if !parse_err_prefix("</gpx>", "gpx: unexpected closing tag") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"></Wpt></gpx>", "gpx: mismatched closing tag") { ok = false; }
  return assert(ok, "mismatched and unexpected closing tags");
}

fn t18() -> TestResult {
  var ok = parse_err_prefix("<gpx><foo/></gpx>", "gpx: unknown element");
  if !parse_err_prefix("<gpx><ns:wpt lat=\"1\" lon=\"2\"/></gpx>", "gpx: unknown element") { ok = false; }
  if !parse_err_prefix("<gpx><rtept lat=\"1\" lon=\"2\"/></gpx>", "gpx: unknown element") { ok = false; }
  return assert(ok, "unknown elements are rejected");
}

fn t19() -> TestResult {
  var ok = parse_err_prefix("<gpx><trkpt lat=\"1\" lon=\"2\"/></gpx>", "gpx: element not allowed here");
  if !parse_err_prefix("<gpx><trk><wpt lat=\"1\" lon=\"2\"/></trk></gpx>", "gpx: element not allowed here") { ok = false; }
  if !parse_err_prefix("<gpx><trk><trkseg><trkseg/></trkseg></trk></gpx>", "gpx: element not allowed here") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><trk/></wpt></gpx>", "gpx: element not allowed here") { ok = false; }
  if !parse_err_prefix("<gpx><name>x</name></gpx>", "gpx: element not allowed here") { ok = false; }
  return assert(ok, "elements are only allowed in their containers");
}

fn t20() -> TestResult {
  var ok = parse_err_prefix("<gpx version=1.1 creator=\"c\"/>", "gpx: unquoted attribute value");
  if !parse_err_prefix("<gpx version=\"1\" creator/>", "gpx: malformed attribute") { ok = false; }
  if !parse_err_prefix("<gpx version=\"1\" creator=\"c\" extra=\"x\"/>", "gpx: unexpected attribute") { ok = false; }
  if !parse_err_prefix("<gpx><trkseg/></gpx>", "gpx: element not allowed here") { ok = false; }
  if !parse_err_prefix("<wpt lat=\"1\" lon=\"2\"/>", "gpx: wrong root element") { ok = false; }
  return assert(ok, "attribute quoting, unknown attributes and root checks");
}

fn t21() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lon=\"1\"/></gpx>", "gpx: missing latitude attribute");
  if !parse_err_prefix("<gpx><wpt lat=\"1\"/></gpx>", "gpx: missing longitude attribute") { ok = false; }
  if !parse_err_prefix("<gpx version=\"1\" version=\"2\"/>", "gpx: duplicate attribute") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\" lat=\"3\"/></gpx>", "gpx: duplicate attribute") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\" extra=\"3\"/></gpx>", "gpx: unexpected attribute") { ok = false; }
  return assert(ok, "missing and duplicate coordinate attributes");
}

fn t22() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lat=\"90.000001\" lon=\"0\"/></gpx>", "gpx: latitude out of range");
  if !parse_err_prefix("<gpx><wpt lat=\"-90.000001\" lon=\"0\"/></gpx>", "gpx: latitude out of range") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"0\" lon=\"180.000001\"/></gpx>", "gpx: longitude out of range") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"0\" lon=\"-180.000001\"/></gpx>", "gpx: longitude out of range") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1000000\" lon=\"0\"/></gpx>", "gpx: latitude out of range") { ok = false; }
  if !parse_err_prefix("<gpx><trkpt lat=\"0\" lon=\"99999\"/></gpx>", "gpx: element not allowed here") { ok = false; }
  return assert(ok, "coordinate ranges are enforced");
}

fn t23() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lat=\"abc\" lon=\"0\"/></gpx>", "gpx: malformed latitude");
  if !parse_err_prefix("<gpx><wpt lat=\"1e2\" lon=\"0\"/></gpx>", "gpx: malformed latitude") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"\" lon=\"0\"/></gpx>", "gpx: malformed latitude") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1.\" lon=\"0\"/></gpx>", "gpx: malformed latitude") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\".5\" lon=\"0\"/></gpx>", "gpx: malformed latitude") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\" 1\" lon=\"0\"/></gpx>", "gpx: malformed latitude") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"--1\"/></gpx>", "gpx: malformed longitude") { ok = false; }
  return assert(ok, "malformed coordinate literals are rejected");
}

fn t24() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&foo;</name></wpt></gpx>", "gpx: bad entity");
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&#;</name></wpt></gpx>", "gpx: bad entity") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&#0;</name></wpt></gpx>", "gpx: bad entity") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&#x110000;</name></wpt></gpx>", "gpx: bad entity") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&#xD800;</name></wpt></gpx>", "gpx: bad entity") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>&amp</name></wpt></gpx>", "gpx: unterminated entity") { ok = false; }
  if !parse_err_prefix("<gpx version=\"&nope;\" creator=\"c\"/>", "gpx: bad entity") { ok = false; }
  return assert(ok, "bad and unterminated entities are rejected");
}

fn t25() -> TestResult {
  var ok = parse_fails("");
  if !parse_err_prefix("<gpx", "gpx: premature end of input") { ok = false; }
  if !parse_err_prefix("<gpx>", "gpx: premature end of input") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\">", "gpx: premature end of input") { ok = false; }
  if !parse_err_prefix("<gpx version=\"1", "gpx: premature end of input") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"></wpt>", "gpx: premature end of input") { ok = false; }
  return assert(ok, "premature end of input is rejected");
}

fn t26() -> TestResult {
  var ok = parse_err_prefix("hello", "gpx: text outside elements");
  if !parse_err_prefix("<gpx>x</gpx>", "gpx: unexpected text in <gpx>") { ok = false; }
  if !parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\">x</wpt></gpx>", "gpx: unexpected text in <wpt>") { ok = false; }
  if !parse_fails("<gpx> broken </gpx>") { ok = false; }
  let r = gpx_parse("  \n<gpx/>\n  ");
  match r {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  return assert(ok, "text outside elements and in containers");
}

fn t27() -> TestResult {
  var ok = parse_err_prefix("<gpx><wpt lat=\"1\" lon=\"2\"><name>a</name><name>b</name></wpt></gpx>", "gpx: duplicate element");
  if !parse_err_prefix("<gpx></gpx><gpx/>", "gpx: multiple root elements") { ok = false; }
  if !parse_err_prefix("<gpx/><!-- c -->", "gpx: unsupported markup") { ok = false; }
  if !parse_err_prefix("<gpx/><?pi?>", "gpx: unsupported markup") { ok = false; }
  return assert(ok, "duplicates, multiple roots and unsupported markup");
}

fn t28() -> TestResult {
  var ok = parse_err_prefix("<?xml version=\"1.0\"", "gpx: malformed declaration");
  if !parse_err_prefix("<?pi?>", "gpx: malformed declaration") { ok = false; }
  if !parse_err_prefix("<?xmlversion=\"1.0\"?><gpx/>", "gpx: malformed declaration") { ok = false; }
  if !parse_fails("<?xml version=\"1.0\"?>") { ok = false; }
  return assert(ok, "declaration validation");
}

fn t29() -> TestResult {
  var d = gpx_new("", "");
  let built = gpx_build(&d);
  let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"\" creator=\"\"/>\n";
  var ok = streq(built, want);
  var empty = GpxDoc{
    kinds: Vec[Int].new(); parents: Vec[Int].new();
    lat_udeg: Vec[Int].new(); lon_udeg: Vec[Int].new();
    field_owners: Vec[Int].new(); field_kinds: Vec[Int].new();
    field_values: Vec[Str].new(); version: ""; creator: "";
  };
  if !streq(gpx_build(&empty), "") { ok = false; }
  return assert(ok, "build emits root attributes and handles a rootless document");
}

fn main() -> Int {
  io.println("=== xiom.gpx conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.gpx: all tests passed");
  } else {
    io.println("xiom.gpx: tests failed");
  }
  return failed;
}
