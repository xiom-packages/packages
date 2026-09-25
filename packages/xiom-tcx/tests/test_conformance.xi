// XIOM -- xiom.tcx conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.tcx module against the documented TCX subset:
// happy paths, record ranges, optional and required elements, numeric token
// validation, entities, canonical build output, round-trips and the full
// error catalog. All Str equality goes through xiom.string.compare.str_compare
// (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison).

module tcx_tests
use xiom.io; use xiom.test; use xiom.tcx;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn parse_fails(text: Str) -> Bool {
  let r = tcx_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return true;
}

fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = tcx_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

fn same_str_vec(a: &Vec[Str], b: &Vec[Str]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Str = a[i];
    let y: Str = b[i];
    if compare.str_compare(x, y) != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn same_int_vec(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

// Structural and textual equality of two documents.
fn same_doc(a: &TcxDoc, b: &TcxDoc) -> Bool {
  let a1 = &a.act_sport;
  let b1 = &b.act_sport;
  if !same_str_vec(a1, b1) { return false; }
  let a2 = &a.act_id;
  let b2 = &b.act_id;
  if !same_str_vec(a2, b2) { return false; }
  let a3 = &a.act_lap_start;
  let b3 = &b.act_lap_start;
  if !same_int_vec(a3, b3) { return false; }
  let a4 = &a.lap_start_time;
  let b4 = &b.lap_start_time;
  if !same_str_vec(a4, b4) { return false; }
  let a5 = &a.lap_total_time;
  let b5 = &b.lap_total_time;
  if !same_str_vec(a5, b5) { return false; }
  let a6 = &a.lap_distance;
  let b6 = &b.lap_distance;
  if !same_str_vec(a6, b6) { return false; }
  let a7 = &a.lap_max_speed;
  let b7 = &b.lap_max_speed;
  if !same_str_vec(a7, b7) { return false; }
  let a8 = &a.lap_calories;
  let b8 = &b.lap_calories;
  if !same_str_vec(a8, b8) { return false; }
  let a9 = &a.lap_avg_hr;
  let b9 = &b.lap_avg_hr;
  if !same_str_vec(a9, b9) { return false; }
  let a10 = &a.lap_tp_start;
  let b10 = &b.lap_tp_start;
  if !same_int_vec(a10, b10) { return false; }
  let a11 = &a.tp_time;
  let b11 = &b.tp_time;
  if !same_str_vec(a11, b11) { return false; }
  let a12 = &a.tp_lat;
  let b12 = &b.tp_lat;
  if !same_str_vec(a12, b12) { return false; }
  let a13 = &a.tp_lon;
  let b13 = &b.tp_lon;
  if !same_str_vec(a13, b13) { return false; }
  let a14 = &a.tp_alt;
  let b14 = &b.tp_alt;
  if !same_str_vec(a14, b14) { return false; }
  let a15 = &a.tp_distance;
  let b15 = &b.tp_distance;
  if !same_str_vec(a15, b15) { return false; }
  let a16 = &a.tp_hr;
  let b16 = &b.tp_hr;
  if !same_str_vec(a16, b16) { return false; }
  let a17 = &a.tp_cadence;
  let b17 = &b.tp_cadence;
  if !same_str_vec(a17, b17) { return false; }
  let a18 = &a.tp_sensor;
  let b18 = &b.tp_sensor;
  if !same_str_vec(a18, b18) { return false; }
  return true;
}

fn src_full() -> Str {
  return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TrainingCenterDatabase xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\n  <Activities>\n    <Activity Sport=\"Running\">\n      <Id>2026-01-01T00:00:00Z</Id>\n      <Lap StartTime=\"2026-01-01T00:00:00Z\">\n        <TotalTimeSeconds>2400.0</TotalTimeSeconds>\n        <DistanceMeters>10000.0</DistanceMeters>\n        <MaximumSpeed>5.5</MaximumSpeed>\n        <Calories>700</Calories>\n        <AverageHeartRateBpm><Value>140</Value></AverageHeartRateBpm>\n        <Track>\n          <Trackpoint>\n            <Time>2026-01-01T00:00:01Z</Time>\n            <Position><LatitudeDegrees>37.5</LatitudeDegrees><LongitudeDegrees>-122.4</LongitudeDegrees></Position>\n            <AltitudeMeters>12.5</AltitudeMeters>\n            <DistanceMeters>1.0</DistanceMeters>\n            <HeartRateBpm><Value>141</Value></HeartRateBpm>\n            <Cadence>90</Cadence>\n            <SensorState>Present</SensorState>\n          </Trackpoint>\n        </Track>\n      </Lap>\n    </Activity>\n  </Activities>\n</TrainingCenterDatabase>\n";
}

fn canon_full() -> Str {
  return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TrainingCenterDatabase>\n  <Activities>\n    <Activity Sport=\"Running\">\n      <Id>2026-01-01T00:00:00Z</Id>\n      <Lap StartTime=\"2026-01-01T00:00:00Z\">\n        <TotalTimeSeconds>2400.0</TotalTimeSeconds>\n        <DistanceMeters>10000.0</DistanceMeters>\n        <MaximumSpeed>5.5</MaximumSpeed>\n        <Calories>700</Calories>\n        <AverageHeartRateBpm>\n          <Value>140</Value>\n        </AverageHeartRateBpm>\n        <Track>\n          <Trackpoint>\n            <Time>2026-01-01T00:00:01Z</Time>\n            <Position>\n              <LatitudeDegrees>37.5</LatitudeDegrees>\n              <LongitudeDegrees>-122.4</LongitudeDegrees>\n            </Position>\n            <AltitudeMeters>12.5</AltitudeMeters>\n            <DistanceMeters>1.0</DistanceMeters>\n            <HeartRateBpm>\n              <Value>141</Value>\n            </HeartRateBpm>\n            <Cadence>90</Cadence>\n            <SensorState>Present</SensorState>\n          </Trackpoint>\n        </Track>\n      </Lap>\n    </Activity>\n  </Activities>\n</TrainingCenterDatabase>\n";
}

fn src_multi() -> Str {
  return "<TrainingCenterDatabase><Activities><Activity Sport=\"Biking\"><Id>a1</Id><Lap StartTime=\"t1\"><TotalTimeSeconds>10</TotalTimeSeconds><DistanceMeters>1</DistanceMeters><Calories>2</Calories><Track><Trackpoint><Time>p1</Time></Trackpoint><Trackpoint><Time>p2</Time></Trackpoint></Track></Lap><Lap StartTime=\"t2\"><TotalTimeSeconds>20</TotalTimeSeconds><DistanceMeters>3</DistanceMeters><Calories>4</Calories></Lap></Activity><Activity Sport=\"Running\"><Id>a2</Id><Lap StartTime=\"t3\"><TotalTimeSeconds>30</TotalTimeSeconds><DistanceMeters>5</DistanceMeters><Calories>6</Calories><Track><Trackpoint><Time>p3</Time></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>";
}

fn t1() -> TestResult {
  let r = tcx_parse(src_full());
  var ok = false;
  match r {
    Ok(d) => {
      ok = tcx_activity_count(&d) == 1;
      if tcx_lap_count(&d) != 1 { ok = false; }
      if tcx_trackpoint_count(&d) != 1 { ok = false; }
      if !streq(tcx_activity_sport(&d, 0), "Running") { ok = false; }
      if !streq(tcx_activity_id(&d, 0), "2026-01-01T00:00:00Z") { ok = false; }
      if tcx_activity_lap_count(&d, 0) != 1 { ok = false; }
      if tcx_lap_activity(&d, 0) != 0 { ok = false; }
      if !streq(tcx_lap_start_time(&d, 0), "2026-01-01T00:00:00Z") { ok = false; }
      if !streq(tcx_lap_total_time(&d, 0), "2400.0") { ok = false; }
      if !streq(tcx_lap_distance(&d, 0), "10000.0") { ok = false; }
      if !streq(tcx_lap_max_speed(&d, 0), "5.5") { ok = false; }
      if !streq(tcx_lap_calories(&d, 0), "700") { ok = false; }
      if !streq(tcx_lap_avg_hr(&d, 0), "140") { ok = false; }
      if !tcx_lap_has_track(&d, 0) { ok = false; }
      if tcx_lap_trackpoint_count(&d, 0) != 1 { ok = false; }
      if tcx_trackpoint_lap(&d, 0) != 0 { ok = false; }
      if !streq(tcx_trackpoint_time(&d, 0), "2026-01-01T00:00:01Z") { ok = false; }
      if !streq(tcx_trackpoint_lat(&d, 0), "37.5") { ok = false; }
      if !streq(tcx_trackpoint_lon(&d, 0), "-122.4") { ok = false; }
      if !tcx_trackpoint_has_position(&d, 0) { ok = false; }
      if !streq(tcx_trackpoint_alt(&d, 0), "12.5") { ok = false; }
      if !streq(tcx_trackpoint_distance(&d, 0), "1.0") { ok = false; }
      if !streq(tcx_trackpoint_hr(&d, 0), "141") { ok = false; }
      if !streq(tcx_trackpoint_cadence(&d, 0), "90") { ok = false; }
      if !streq(tcx_trackpoint_sensor(&d, 0), "Present") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full document model and accessors");
}

fn t2() -> TestResult {
  let r = tcx_parse(src_full());
  var ok = false;
  match r {
    Ok(d) => {
      let built = tcx_build(&d);
      ok = streq(built, canon_full());
      let r2 = tcx_parse(built);
      match r2 {
        Ok(d2) => {
          if !streq(tcx_build(&d2), built) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical build is exact and stable");
}

fn t3() -> TestResult {
  let r = tcx_parse(src_multi());
  var ok = false;
  match r {
    Ok(d) => {
      ok = tcx_activity_count(&d) == 2;
      if tcx_lap_count(&d) != 3 { ok = false; }
      if tcx_trackpoint_count(&d) != 3 { ok = false; }
      if tcx_activity_lap_count(&d, 0) != 2 { ok = false; }
      if tcx_activity_lap_count(&d, 1) != 1 { ok = false; }
      if tcx_lap_activity(&d, 0) != 0 { ok = false; }
      if tcx_lap_activity(&d, 1) != 0 { ok = false; }
      if tcx_lap_activity(&d, 2) != 1 { ok = false; }
      if tcx_lap_trackpoint_count(&d, 0) != 2 { ok = false; }
      if tcx_lap_trackpoint_count(&d, 1) != 0 { ok = false; }
      if tcx_lap_trackpoint_count(&d, 2) != 1 { ok = false; }
      if tcx_lap_has_track(&d, 1) { ok = false; }
      if tcx_trackpoint_lap(&d, 0) != 0 { ok = false; }
      if tcx_trackpoint_lap(&d, 1) != 0 { ok = false; }
      if tcx_trackpoint_lap(&d, 2) != 2 { ok = false; }
      if !streq(tcx_trackpoint_time(&d, 2), "p3") { ok = false; }
      if !streq(tcx_lap_start_time(&d, 2), "t3") { ok = false; }
      if !streq(tcx_activity_id(&d, 1), "a2") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multi activity, lap and trackpoint ranges");
}

fn t4() -> TestResult {
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"X\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(tcx_lap_max_speed(&d, 0), "");
      if !streq(tcx_lap_avg_hr(&d, 0), "") { ok = false; }
      if tcx_lap_has_track(&d, 0) { ok = false; }
      if tcx_lap_trackpoint_count(&d, 0) != 0 { ok = false; }
      if tcx_trackpoint_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"X\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>");
  match r2 {
    Ok(d2) => {
      if !streq(tcx_trackpoint_alt(&d2, 0), "") { ok = false; }
      if !streq(tcx_trackpoint_distance(&d2, 0), "") { ok = false; }
      if !streq(tcx_trackpoint_hr(&d2, 0), "") { ok = false; }
      if !streq(tcx_trackpoint_cadence(&d2, 0), "") { ok = false; }
      if !streq(tcx_trackpoint_sensor(&d2, 0), "") { ok = false; }
      if !streq(tcx_trackpoint_lat(&d2, 0), "") { ok = false; }
      if tcx_trackpoint_has_position(&d2, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "optional lap and trackpoint elements are absent");
}

fn t5() -> TestResult {
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id> i </Id><Lap StartTime=\" t \"><TotalTimeSeconds>+1.5</TotalTimeSeconds><DistanceMeters>-0.0</DistanceMeters><MaximumSpeed>0</MaximumSpeed><Calories>0</Calories><AverageHeartRateBpm><Value>255</Value></AverageHeartRateBpm><Track><Trackpoint><Time>t</Time><Position><LatitudeDegrees>-90.000001</LatitudeDegrees><LongitudeDegrees>180.0</LongitudeDegrees></Position><AltitudeMeters>-3.5</AltitudeMeters><DistanceMeters>5</DistanceMeters><HeartRateBpm><Value>0</Value></HeartRateBpm><Cadence>0</Cadence><SensorState>Absent</SensorState></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(tcx_activity_id(&d, 0), "i");
      if !streq(tcx_lap_start_time(&d, 0), "t") { ok = false; }
      if !streq(tcx_lap_total_time(&d, 0), "+1.5") { ok = false; }
      if !streq(tcx_lap_distance(&d, 0), "-0.0") { ok = false; }
      if !streq(tcx_lap_max_speed(&d, 0), "0") { ok = false; }
      if !streq(tcx_lap_calories(&d, 0), "0") { ok = false; }
      if !streq(tcx_lap_avg_hr(&d, 0), "255") { ok = false; }
      if !streq(tcx_trackpoint_lat(&d, 0), "-90.000001") { ok = false; }
      if !streq(tcx_trackpoint_lon(&d, 0), "180.0") { ok = false; }
      if !streq(tcx_trackpoint_alt(&d, 0), "-3.5") { ok = false; }
      if !streq(tcx_trackpoint_distance(&d, 0), "5") { ok = false; }
      if !streq(tcx_trackpoint_hr(&d, 0), "0") { ok = false; }
      if !streq(tcx_trackpoint_cadence(&d, 0), "0") { ok = false; }
      if !streq(tcx_trackpoint_sensor(&d, 0), "Absent") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "valid numeric tokens are accepted and trimmed");
}

fn t6() -> TestResult {
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"A &amp; B\"><Id>&amp;&lt;&gt;&quot;&apos;&#65;&#x42;&#x2603;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(tcx_activity_sport(&d, 0), "A & B");
      let id = tcx_activity_id(&d, 0);
      if !string.str_starts_with(id, "&<>\"'AB") { ok = false; }
      let b0: Int = (string.byte_at(id, 7) as Int) & 0xFF;
      let b1: Int = (string.byte_at(id, 8) as Int) & 0xFF;
      let b2: Int = (string.byte_at(id, 9) as Int) & 0xFF;
      if b0 != 226 { ok = false; }
      if b1 != 152 { ok = false; }
      if b2 != 131 { ok = false; }
      let built = tcx_build(&d);
      if !string.str_contains(built, "Sport=\"A &amp; B\"") { ok = false; }
      if !string.str_contains(built, "&amp;&lt;&gt;\"'AB") { ok = false; }
      let r2 = tcx_parse(built);
      match r2 {
        Ok(d2) => {
          if !same_doc(&d, &d2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "entities decode, re-escape and round-trip");
}

fn t7() -> TestResult {
  let r = tcx_parse("  <?xml version=\"1.0\"?>\n\t<TrainingCenterDatabase>\n  <Activities>\n    <Activity Sport='Run'>\n      <Id>\n        abc\n      </Id>\n      <Lap StartTime='2026-01-01T00:00:00Z'>\n        <TotalTimeSeconds> 2400 </TotalTimeSeconds>\n        <DistanceMeters>1</DistanceMeters>\n        <Calories>2</Calories>\n      </Lap>\n    </Activity>\n  </Activities>\n</TrainingCenterDatabase>\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(tcx_activity_sport(&d, 0), "Run");
      if !streq(tcx_activity_id(&d, 0), "abc") { ok = false; }
      if !streq(tcx_lap_start_time(&d, 0), "2026-01-01T00:00:00Z") { ok = false; }
      if !streq(tcx_lap_total_time(&d, 0), "2400") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "whitespace, single quotes and trimming");
}

fn t8() -> TestResult {
  let d = tcx_new();
  var ok = streq(tcx_build(&d), "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TrainingCenterDatabase>\n  <Activities/>\n</TrainingCenterDatabase>\n");
  if tcx_activity_count(&d) != 0 { ok = false; }
  if tcx_lap_count(&d) != 0 { ok = false; }
  if tcx_trackpoint_count(&d) != 0 { ok = false; }
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  match r {
    Ok(p) => {
      let want = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<TrainingCenterDatabase>\n  <Activities>\n    <Activity Sport=\"S\">\n      <Id>i</Id>\n      <Lap StartTime=\"t\">\n        <TotalTimeSeconds>1</TotalTimeSeconds>\n        <DistanceMeters>2</DistanceMeters>\n        <Calories>3</Calories>\n      </Lap>\n    </Activity>\n  </Activities>\n</TrainingCenterDatabase>\n";
      if !streq(tcx_build(&p), want) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical skeleton and minimal document");
}

fn t9() -> TestResult {
  let r1 = tcx_parse(src_full());
  var ok = false;
  match r1 {
    Ok(d1) => {
      let built = tcx_build(&d1);
      let r2 = tcx_parse(built);
      match r2 {
        Ok(d2) => {
          ok = same_doc(&d1, &d2);
          if !streq(tcx_build(&d2), built) { ok = false; }
          if tcx_trackpoint_count(&d2) != 1 { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse, build, parse preserves the document");
}

fn t10() -> TestResult {
  let d = tcx_new();
  var ok = tcx_activity_count(&d) == 0;
  if tcx_lap_count(&d) != 0 { ok = false; }
  if tcx_trackpoint_count(&d) != 0 { ok = false; }
  if !streq(tcx_activity_sport(&d, 0), "") { ok = false; }
  if !streq(tcx_activity_id(&d, -1), "") { ok = false; }
  if !streq(tcx_lap_start_time(&d, 5), "") { ok = false; }
  if !streq(tcx_lap_total_time(&d, 5), "") { ok = false; }
  if !streq(tcx_lap_distance(&d, 5), "") { ok = false; }
  if !streq(tcx_lap_max_speed(&d, 5), "") { ok = false; }
  if !streq(tcx_lap_calories(&d, 5), "") { ok = false; }
  if !streq(tcx_lap_avg_hr(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_time(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_lat(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_lon(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_alt(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_distance(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_hr(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_cadence(&d, 5), "") { ok = false; }
  if !streq(tcx_trackpoint_sensor(&d, 5), "") { ok = false; }
  if tcx_lap_activity(&d, 0) != -1 { ok = false; }
  if tcx_trackpoint_lap(&d, 0) != -1 { ok = false; }
  if tcx_activity_lap_count(&d, 0) != 0 { ok = false; }
  if tcx_lap_trackpoint_count(&d, 0) != 0 { ok = false; }
  if tcx_lap_has_track(&d, 0) { ok = false; }
  if tcx_trackpoint_has_position(&d, 0) { ok = false; }
  return assert(ok, "accessors are safe out of range");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Id");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Lap") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities></Activities></TrainingCenterDatabase>", "tcx: missing required element: Activity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase></TrainingCenterDatabase>", "tcx: missing required element: Activities") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Trackpoint") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><Position><LatitudeDegrees>1</LatitudeDegrees></Position></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: LongitudeDegrees") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><AverageHeartRateBpm></AverageHeartRateBpm></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Value") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><HeartRateBpm></HeartRateBpm></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Value") { ok = false; }
  return assert(ok, "missing required elements are reported");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: TotalTimeSeconds");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: DistanceMeters") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Calories") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required element: Time") { ok = false; }
  return assert(ok, "missing required lap and trackpoint tokens");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required attribute: Sport");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: missing required attribute: StartTime") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"\"><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: empty attribute: Sport") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: empty attribute: StartTime") { ok = false; }
  return assert(ok, "required and empty attributes");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Foo/></TrainingCenterDatabase>", "tcx: unknown element: <Foo>");
  if !parse_err_prefix("<TrainingCenterDatabase><Lap StartTime=\"t\"/></TrainingCenterDatabase>", "tcx: element not allowed here: <Lap>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Trackpoint/></Activities></TrainingCenterDatabase>", "tcx: element not allowed here: <Trackpoint>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><Id>x</Id></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: element not allowed here: <Id>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Time>x</Time></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: element not allowed here: <Time>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id><Value>1</Value></Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: element not allowed here: <Value>") { ok = false; }
  return assert(ok, "unknown and misplaced elements");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities></Activity></Activities></TrainingCenterDatabase>", "tcx: mismatched closing tag");
  if !parse_err_prefix("<TrainingCenterDatabase></Foo>", "tcx: mismatched closing tag") { ok = false; }
  if !parse_err_prefix("</Lap>", "tcx: unexpected closing tag: </Lap>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities></activities></TrainingCenterDatabase>", "tcx: mismatched closing tag") { ok = false; }
  if !parse_err_prefix("</Lap x>", "tcx: malformed tag") { ok = false; }
  return assert(ok, "mismatched and unexpected closing tags");
}

fn t16() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>a</Id><Id>b</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <Id>");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><TotalTimeSeconds>2</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <TotalTimeSeconds>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p1</Time></Trackpoint></Track><Track><Trackpoint><Time>p2</Time></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <Track>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><Position><LatitudeDegrees>1</LatitudeDegrees><LongitudeDegrees>2</LongitudeDegrees></Position><Position><LatitudeDegrees>3</LatitudeDegrees><LongitudeDegrees>4</LongitudeDegrees></Position></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <Position>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><HeartRateBpm><Value>1</Value><Value>2</Value></HeartRateBpm></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <Value>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>a</Time><Time>b</Time></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate element: <Time>") { ok = false; }
  return assert(ok, "duplicate single-instance elements");
}

fn t17() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>abc</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed TotalTimeSeconds: abc");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1e2</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed TotalTimeSeconds: 1e2") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1.5.5</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed TotalTimeSeconds: 1.5.5") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>.</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed TotalTimeSeconds: .") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>1.</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed DistanceMeters: 1.") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>12.5</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed Calories: 12.5") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><Cadence>-1</Cadence></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed Cadence: -1") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><HeartRateBpm><Value>140.5</Value></HeartRateBpm></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed Value: 140.5") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><SensorState>Maybe</SensorState></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed SensorState: Maybe") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><Position><LatitudeDegrees>1e2</LatitudeDegrees><LongitudeDegrees>2</LongitudeDegrees></Position></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed LatitudeDegrees: 1e2") { ok = false; }
  return assert(ok, "malformed numeric tokens are rejected");
}

fn t18() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id/></Activity></Activities></TrainingCenterDatabase>", "tcx: empty element: Id");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds></TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: empty element: TotalTimeSeconds") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><Cadence>   </Cadence></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: empty element: Cadence") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><Track><Trackpoint><Time>p</Time><SensorState/></Trackpoint></Track></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: empty element: SensorState") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories><AverageHeartRateBpm><Value/></AverageHeartRateBpm></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: empty element: Value") { ok = false; }
  return assert(ok, "empty required and optional elements");
}

fn t19() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=S><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: unquoted attribute value: Sport");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed attribute") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"a<b\"><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: malformed attribute") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"a\" Sport=\"b\"><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: duplicate attribute: Sport") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=t><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: unquoted attribute value: StartTime") { ok = false; }
  let r = tcx_parse("<TrainingCenterDatabase><Activities><Activity Sport=\"S\" Note=\"keep\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  match r {
    Ok(d) => {
      let built = tcx_build(&d);
      if string.str_contains(built, "Note") { ok = false; }
      if !streq(tcx_activity_sport(&d, 0), "S") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "attribute quoting, duplicates and ignored attributes");
}

fn t20() -> TestResult {
  var ok = parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&bogus;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity: &bogus;");
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&amp</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: unterminated entity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&#;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&#0;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&#x110000;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>&#xD800;</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"&nope;\"><Id>i</Id></Activity></Activities></TrainingCenterDatabase>", "tcx: bad entity") { ok = false; }
  return assert(ok, "bad and unterminated entities are rejected");
}

fn t21() -> TestResult {
  var ok = parse_fails("");
  if !parse_err_prefix("<TrainingCenterDatabase>", "tcx: premature end of input") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities>", "tcx: premature end of input") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\">", "tcx: premature end of input") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>x</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity>", "tcx: premature end of input") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S", "tcx: premature end of input") { ok = false; }
  return assert(ok, "premature end of input is rejected");
}

fn t22() -> TestResult {
  var ok = parse_err_prefix("<Activities/>", "tcx: wrong root element: <Activities>");
  if !parse_err_prefix("<gpx/>", "tcx: unknown element: <gpx>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase><TrainingCenterDatabase/>", "tcx: multiple root elements") { ok = false; }
  if !parse_err_prefix("hello", "tcx: text outside elements") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase>hi</TrainingCenterDatabase>", "tcx: unexpected text in <TrainingCenterDatabase>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities>x</Activities></TrainingCenterDatabase>", "tcx: unexpected text in <Activities>") { ok = false; }
  if !parse_err_prefix("<TrainingCenterDatabase><Activities><Activity Sport=\"S\">x</Activity></Activities></TrainingCenterDatabase>", "tcx: unexpected text in <Activity>") { ok = false; }
  if !parse_err_prefix("<!-- c --><TrainingCenterDatabase/>", "tcx: unsupported markup") { ok = false; }
  if !parse_err_prefix("<?pi?><TrainingCenterDatabase/>", "tcx: malformed declaration") { ok = false; }
  let r = tcx_parse("  \n<TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>\n  ");
  match r {
    Ok(_) => {},
    Err(_) => { ok = false; },
  }
  return assert(ok, "wrong root, text placement and unsupported markup");
}

fn t23() -> TestResult {
  var ok = parse_err_prefix("<?xmlversion=\"1.0\"?><TrainingCenterDatabase/>", "tcx: malformed declaration");
  if !parse_err_prefix("<?xml version=\"1.0\"", "tcx: malformed declaration") { ok = false; }
  if !parse_err_prefix("<?xml", "tcx: malformed declaration") { ok = false; }
  let r = tcx_parse("<?xml?><TrainingCenterDatabase><Activities><Activity Sport=\"S\"><Id>i</Id><Lap StartTime=\"t\"><TotalTimeSeconds>1</TotalTimeSeconds><DistanceMeters>2</DistanceMeters><Calories>3</Calories></Lap></Activity></Activities></TrainingCenterDatabase>");
  match r {
    Ok(d) => {
      if tcx_activity_count(&d) != 1 { ok = false; }
      if !streq(tcx_activity_sport(&d, 0), "S") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "declaration validation");
}

fn main() -> Int {
  io.println("=== xiom.tcx conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.tcx: all tests passed");
  } else {
    io.println("xiom.tcx: tests failed");
  }
  return failed;
}
