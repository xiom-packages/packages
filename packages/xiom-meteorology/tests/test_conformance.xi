// XIOM -- xiom.meteorology conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.meteorology METAR/TAF decoders against
// SPEC.md: report structure, wind variants, CAVOK and statute-mile visibility,
// RVR, present-weather combinations, sky layers, temperature/dewpoint,
// altimeter forms, the TAF change groups, and the malformed-input catalog with
// byte offsets. Every report string is built in-test; there are no data files.
//
// All Str equality goes through xiom.string.compare.str_compare (BUG 17:
// `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison), and every Vec[Str]/Vec[Int] element read binds a typed local
// first.

module meteorology_tests
use xiom.io; use xiom.test; use xiom.meteorology;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn metar_err_is(s: Str, want: Str) -> Bool {
  let r = metar_decode(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn taf_err_is(s: Str, want: Str) -> Bool {
  let r = taf_decode(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// --- fixtures ---------------------------------------------------------------

fn metar_full() -> Str {
  return "METAR EGLL 121850Z AUTO 24012G22KT 220V260 9999 -RA SCT020 BKN035 12/09 Q1015 NOSIG";
}

fn metar_calm() -> Str {
  return "METAR KJFK 010000Z 00000KT CAVOK M05/M08 A2992";
}

fn metar_speci() -> Str {
  return "SPECI KLAX 282359Z COR VRB03KT 0800 R16L/0400V0800FT/U FG VV002 02/M01 Q1009";
}

fn metar_sm() -> Str {
  return "METAR KORD 121200Z 09005KT 1/2SM -SN FZFG BKN008 M02/M04 A3001";
}

fn metar_mixed_sm() -> Str {
  return "METAR KSFO 121200Z 27008KT 1 1/2SM BR OVC010 15/14 A2999";
}

fn metar_fast() -> Str {
  return "METAR KATL 010000Z 180115G125KT 10SM FEW250 33/22 A3010";
}

fn metar_mps() -> Str {
  return "METAR ENGM 121200Z 18003MPS 2000 RASN SCT005 OVC020 M01/M03 Q0995";
}

fn metar_rmk() -> Str {
  return "METAR KSEA 121200Z 18004KT 10SM BKN020 12/10 A3005 RMK AO2 SLP132 T01230105 Q1013";
}

fn metar_trend() -> Str {
  return "METAR EGKK 121200Z 24008KT 9999 SCT020 10/08 Q1013 BECMG TEMPO XTRATOKEN";
}

fn metar_wx_catalog() -> Str {
  return "METAR EGLL 121850Z 24008KT 9999 -DZ +SHRASN VCTS MIFG BCFG PRFG DRSA BLSN FZDZ GR GS UP IC PL SG VA DU SA HZ PY PO SQ FC SS DS NSW";
}

fn metar_sky_catalog() -> Str {
  return "METAR EGLL 121850Z 24008KT 9999 FEW010 SCT020TCU BKN030CB OVC040 VV/// VV004";
}

fn metar_lower() -> Str {
  return "COR AUTO egll 121850Z 24008KT 9999 SCT020 10/08 Q1013";
}

fn metar_ndv() -> Str {
  return "METAR EGLL 121850Z 24008KT 0800NDV FG VV001 02/01 Q1013";
}

fn metar_msm() -> Str {
  return "METAR EGLL 121850Z 24008KT M1/4SM VV001 02/01 Q1013";
}

fn metar_rvr2() -> Str {
  return "METAR EGLL 121850Z 24008KT R16L/M0400N R24R/1200V2000FT 02/01 Q1013";
}

fn taf_base() -> Str {
  return "TAF EGLL 121700Z 1218/1318 24010KT 9999 SCT030";
}

fn taf_changes() -> Str {
  return "TAF LBBG 041600Z 0418/0518 18008KT 9999 BKN020 TEMPO 0420/0423 20015G25KT 3000 -RA BKN010 BECMG 0502/0504 25006KT 9999 SCT025 FM050600 22010KT";
}

fn taf_amd() -> Str {
  return "TAF AMD EGLL 1217Z 1218/1318 FM0300 TX32/1218Z 22010KT";
}

fn taf_cavok() -> Str {
  return "TAF EGLL 121700Z 1218/1318 BECMG 1220/1222 CAVOK";
}

// --- tests ------------------------------------------------------------------

fn t1() -> TestResult {
  let r = metar_decode(metar_full());
  var ok = false;
  match r {
    Ok(m) => {
      ok = streq(metar_station(&m), "EGLL");
      if metar_report_type(&m) != 1 { ok = false; }
      if !metar_is_auto(&m) { ok = false; }
      if metar_is_cor(&m) { ok = false; }
      if metar_day(&m) != 12 { ok = false; }
      if metar_hour(&m) != 18 { ok = false; }
      if metar_minute(&m) != 50 { ok = false; }
      if metar_wind_dir(&m) != 240 { ok = false; }
      if metar_wind_speed(&m) != 12 { ok = false; }
      if metar_wind_gust(&m) != 22 { ok = false; }
      if metar_wind_unit(&m) != 0 { ok = false; }
      if metar_wind_is_calm(&m) { ok = false; }
      if metar_wind_is_variable(&m) { ok = false; }
      if metar_var_from(&m) != 220 { ok = false; }
      if metar_var_to(&m) != 260 { ok = false; }
      if metar_vis_m(&m) != 9999 { ok = false; }
      if !metar_vis_at_least_10km(&m) { ok = false; }
      if metar_is_cavok(&m) { ok = false; }
      if metar_vis_is_sm(&m) { ok = false; }
      if metar_rvr_count(&m) != 0 { ok = false; }
      if metar_weather_count(&m) != 1 { ok = false; }
      if !streq(metar_weather_raw(&m, 0), "-RA") { ok = false; }
      if metar_weather_intensity(&m, 0) != 1 { ok = false; }
      if !streq(metar_weather_descriptor(&m, 0), "") { ok = false; }
      if !streq(metar_weather_phenomena(&m, 0), "RA") { ok = false; }
      if metar_weather_is_nsw(&m, 0) { ok = false; }
      if metar_sky_count(&m) != 2 { ok = false; }
      if metar_sky_cover(&m, 0) != 1 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 2000 { ok = false; }
      if metar_sky_cover(&m, 1) != 2 { ok = false; }
      if metar_sky_height_ft(&m, 1) != 3500 { ok = false; }
      if !metar_has_temperature(&m) { ok = false; }
      if metar_temperature_tenths(&m) != 120 { ok = false; }
      if metar_dewpoint_tenths(&m) != 90 { ok = false; }
      if metar_altimeter_hpa(&m) != 1015 { ok = false; }
      if metar_altimeter_inhg100(&m) != -1 { ok = false; }
      if !metar_is_nosig(&m) { ok = false; }
      if metar_extra_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "full METAR: station, time, gusting wind, vis, weather, sky, temp, QNH, NOSIG");
}

fn t2() -> TestResult {
  let r = metar_decode(metar_calm());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_wind_is_calm(&m);
      if metar_wind_dir(&m) != 0 { ok = false; }
      if metar_wind_speed(&m) != 0 { ok = false; }
      if metar_wind_gust(&m) != -1 { ok = false; }
      if !metar_is_cavok(&m) { ok = false; }
      if !metar_vis_at_least_10km(&m) { ok = false; }
      if metar_vis_m(&m) != 10000 { ok = false; }
      if metar_temperature_tenths(&m) != -50 { ok = false; }
      if metar_dewpoint_tenths(&m) != -80 { ok = false; }
      if metar_altimeter_inhg100(&m) != 2992 { ok = false; }
      if metar_altimeter_hpa(&m) != -1 { ok = false; }
      if metar_extra_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "calm wind, CAVOK, negative temperatures, A-form altimeter");
}

fn t3() -> TestResult {
  let r = metar_decode(metar_speci());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_report_type(&m) == 2;
      if !metar_is_cor(&m) { ok = false; }
      if metar_is_auto(&m) { ok = false; }
      if !streq(metar_station(&m), "KLAX") { ok = false; }
      if metar_day(&m) != 28 { ok = false; }
      if metar_hour(&m) != 23 { ok = false; }
      if !metar_wind_is_variable(&m) { ok = false; }
      if metar_wind_dir(&m) != -1 { ok = false; }
      if metar_wind_speed(&m) != 3 { ok = false; }
      if metar_vis_m(&m) != 800 { ok = false; }
      if metar_rvr_count(&m) != 1 { ok = false; }
      if !streq(metar_rvr_raw(&m, 0), "R16L/0400V0800FT/U") { ok = false; }
      if !streq(metar_rvr_runway(&m, 0), "16L") { ok = false; }
      if metar_rvr_min_m(&m, 0) != 121 { ok = false; }
      if metar_rvr_max_m(&m, 0) != 243 { ok = false; }
      if !metar_rvr_is_variable(&m, 0) { ok = false; }
      if metar_rvr_unit(&m, 0) != 1 { ok = false; }
      if metar_rvr_trend(&m, 0) != 1 { ok = false; }
      if metar_weather_count(&m) != 1 { ok = false; }
      if !streq(metar_weather_phenomena(&m, 0), "FG") { ok = false; }
      if metar_sky_count(&m) != 1 { ok = false; }
      if metar_sky_cover(&m, 0) != 4 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 200 { ok = false; }
      if metar_temperature_tenths(&m) != 20 { ok = false; }
      if metar_dewpoint_tenths(&m) != -10 { ok = false; }
      if metar_altimeter_hpa(&m) != 1009 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "SPECI/COR, VRB wind, meters vis, FT RVR with trend, FG, VV002");
}

fn t4() -> TestResult {
  let r = metar_decode(metar_sm());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_vis_is_sm(&m);
      if metar_vis_m(&m) != 804 { ok = false; }
      if metar_vis_prefix(&m) != 0 { ok = false; }
      if metar_weather_count(&m) != 2 { ok = false; }
      if !streq(metar_weather_raw(&m, 0), "-SN") { ok = false; }
      if metar_weather_intensity(&m, 0) != 1 { ok = false; }
      if !streq(metar_weather_descriptor(&m, 1), "FZ") { ok = false; }
      if !streq(metar_weather_phenomena(&m, 1), "FG") { ok = false; }
      if metar_sky_cover(&m, 0) != 2 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 800 { ok = false; }
      if metar_temperature_tenths(&m) != -20 { ok = false; }
      if metar_dewpoint_tenths(&m) != -40 { ok = false; }
      if metar_altimeter_inhg100(&m) != 3001 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "1/2SM visibility, -SN, FZFG, BKN008, A-form altimeter");
}

fn t5() -> TestResult {
  let r = metar_decode(metar_mixed_sm());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_vis_is_sm(&m);
      if metar_vis_m(&m) != 2414 { ok = false; }
      if metar_weather_count(&m) != 1 { ok = false; }
      if !streq(metar_weather_phenomena(&m, 0), "BR") { ok = false; }
      if metar_sky_cover(&m, 0) != 3 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 1000 { ok = false; }
      if metar_temperature_tenths(&m) != 150 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "mixed 1 1/2SM visibility and OVC layer");
}

fn t6() -> TestResult {
  let r = metar_decode(metar_fast());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_wind_speed(&m) == 115;
      if metar_wind_gust(&m) != 125 { ok = false; }
      if metar_wind_dir(&m) != 180 { ok = false; }
      if !metar_vis_is_sm(&m) { ok = false; }
      if metar_vis_m(&m) != 16093 { ok = false; }
      if metar_sky_cover(&m, 0) != 0 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 25000 { ok = false; }
      if metar_temperature_tenths(&m) != 330 { ok = false; }
      if metar_dewpoint_tenths(&m) != 220 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "3-digit wind speed and gust, 10SM, FEW250");
}

fn t7() -> TestResult {
  let r = metar_decode(metar_mps());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_wind_unit(&m) == 1;
      if metar_wind_speed(&m) != 3 { ok = false; }
      if metar_vis_m(&m) != 2000 { ok = false; }
      if !streq(metar_weather_phenomena(&m, 0), "RASN") { ok = false; }
      if metar_sky_count(&m) != 2 { ok = false; }
      if metar_temperature_tenths(&m) != -10 { ok = false; }
      if metar_dewpoint_tenths(&m) != -30 { ok = false; }
      if metar_altimeter_hpa(&m) != 995 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "MPS wind unit, RASN, two sky layers, Q-form altimeter");
}

fn t8() -> TestResult {
  let r = metar_decode(metar_rmk());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_altimeter_inhg100(&m) == 3005;
      if metar_altimeter_hpa(&m) != -1 { ok = false; }
      if metar_extra_count(&m) != 5 { ok = false; }
      if !streq(metar_extra(&m, 0), "RMK") { ok = false; }
      if !streq(metar_extra(&m, 1), "AO2") { ok = false; }
      if !streq(metar_extra(&m, 4), "Q1013") { ok = false; }
      if metar_temperature_tenths(&m) != 120 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "RMK tail is opaque: Q1013 after RMK is ignored, kept as extra");
}

fn t9() -> TestResult {
  let r = metar_decode(metar_trend());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_extra_count(&m) == 3;
      if !streq(metar_extra(&m, 0), "BECMG") { ok = false; }
      if !streq(metar_extra(&m, 1), "TEMPO") { ok = false; }
      if !streq(metar_extra(&m, 2), "XTRATOKEN") { ok = false; }
      if metar_vis_m(&m) != 9999 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown tokens land in extra without failing");
}

fn t10() -> TestResult {
  let r = metar_decode(metar_wx_catalog());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_weather_count(&m) == 26;
      if metar_weather_intensity(&m, 0) != 1 { ok = false; }
      if !streq(metar_weather_descriptor(&m, 1), "SH") { ok = false; }
      if !streq(metar_weather_phenomena(&m, 1), "RASN") { ok = false; }
      if metar_weather_intensity(&m, 1) != 2 { ok = false; }
      if metar_weather_intensity(&m, 2) != 3 { ok = false; }
      if !streq(metar_weather_descriptor(&m, 2), "TS") { ok = false; }
      if !streq(metar_weather_descriptor(&m, 3), "MI") { ok = false; }
      if !streq(metar_weather_descriptor(&m, 5), "PR") { ok = false; }
      if !streq(metar_weather_phenomena(&m, 6), "SA") { ok = false; }
      if !streq(metar_weather_descriptor(&m, 7), "BL") { ok = false; }
      if !streq(metar_weather_descriptor(&m, 8), "FZ") { ok = false; }
      if !streq(metar_weather_phenomena(&m, 25), "") { ok = false; }
      if !metar_weather_is_nsw(&m, 25) { ok = false; }
      if metar_sky_count(&m) != 0 { ok = false; }
      if metar_extra_count(&m) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "26 weather groups: descriptors, precip, obscuration, other, NSW");
}

fn t11() -> TestResult {
  let r = metar_decode(metar_sky_catalog());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_sky_count(&m) == 6;
      if metar_sky_cover(&m, 0) != 0 { ok = false; }
      if metar_sky_height_ft(&m, 0) != 1000 { ok = false; }
      if !streq(metar_sky_type(&m, 1), "TCU") { ok = false; }
      if metar_sky_height_ft(&m, 1) != 2000 { ok = false; }
      if !streq(metar_sky_type(&m, 2), "CB") { ok = false; }
      if metar_sky_cover(&m, 3) != 3 { ok = false; }
      if metar_sky_cover(&m, 4) != 4 { ok = false; }
      if metar_sky_height_ft(&m, 4) != -1 { ok = false; }
      if !streq(metar_sky_raw(&m, 4), "VV///") { ok = false; }
      if metar_sky_height_ft(&m, 5) != 400 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "sky layers: FEW/SCT/BKN/OVC, CB/TCU suffix, VV///, VV004");
}

fn t12() -> TestResult {
  let r = metar_decode(metar_lower());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_report_type(&m) == 0;
      if !streq(metar_station(&m), "egll") { ok = false; }
      if !metar_is_cor(&m) { ok = false; }
      if !metar_is_auto(&m) { ok = false; }
      if metar_wind_dir(&m) != 240 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "no report keyword, lower-case station, COR before AUTO");
}

fn t13() -> TestResult {
  var ok = metar_err_is("", "metar: missing station at offset 0");
  if !metar_err_is("METAR EG 121200Z 24008KT", "metar: invalid station at offset 6: EG") { ok = false; }
  if !metar_err_is("METAR EGLL 121850 24008KT", "metar: invalid time at offset 11: 121850") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 1800KT 9999", "metar: invalid wind at offset 19: 1800KT") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z", "metar: missing wind at offset 18") { ok = false; }
  return assert(ok, "malformed station/time/wind and missing wind carry byte offsets");
}

fn t14() -> TestResult {
  var ok = metar_err_is("METAR EGLL 121850Z 24008KT 12/x8", "metar: invalid temperature at offset 27: 12/x8");
  if !metar_err_is("METAR EGLL 121850Z 24008KT 9999 A29x2", "metar: invalid altimeter at offset 32: A29x2") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 24008KT R16L/04x0", "metar: invalid RVR at offset 27: R16L/04x0") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 24008KT 9999 0800", "metar: duplicate visibility at offset 32: 0800") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 24008KT 18004KT", "metar: duplicate wind at offset 27: 18004KT") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 24008KT 220V999", "metar: invalid variable wind at offset 27: 220V999") { ok = false; }
  if !metar_err_is("METAR EGLL 121850Z 24008KT 12/09 15/14", "metar: duplicate temperature at offset 33: 15/14") { ok = false; }
  return assert(ok, "malformed temperature/altimeter/RVR and duplicate groups carry offsets");
}

fn t15() -> TestResult {
  let r = metar_decode(metar_ndv());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_vis_is_ndv(&m);
      if metar_vis_m(&m) != 800 { ok = false; }
      if metar_vis_is_sm(&m) { ok = false; }
      if !streq(metar_weather_phenomena(&m, 0), "FG") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "0800NDV meter visibility keeps the NDV flag");
}

fn t16() -> TestResult {
  let r = metar_decode(metar_msm());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_vis_is_sm(&m);
      if metar_vis_m(&m) != 402 { ok = false; }
      if metar_vis_prefix(&m) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "M1/4SM keeps the M (less than) prefix");
}

fn t17() -> TestResult {
  let r = metar_decode(metar_rvr2());
  var ok = false;
  match r {
    Ok(m) => {
      ok = metar_rvr_count(&m) == 2;
      if !streq(metar_rvr_runway(&m, 0), "16L") { ok = false; }
      if metar_rvr_min_m(&m, 0) != 400 { ok = false; }
      if metar_rvr_max_m(&m, 0) != 400 { ok = false; }
      if metar_rvr_is_variable(&m, 0) { ok = false; }
      if metar_rvr_prefix(&m, 0) != 1 { ok = false; }
      if metar_rvr_trend(&m, 0) != 3 { ok = false; }
      if !streq(metar_rvr_runway(&m, 1), "24R") { ok = false; }
      if metar_rvr_min_m(&m, 1) != 365 { ok = false; }
      if metar_rvr_max_m(&m, 1) != 609 { ok = false; }
      if !metar_rvr_is_variable(&m, 1) { ok = false; }
      if metar_rvr_unit(&m, 1) != 1 { ok = false; }
      if metar_rvr_trend(&m, 1) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "RVR: M prefix with N trend, variable FT range, feet to meters");
}

fn t18() -> TestResult {
  let r = taf_decode(taf_base());
  var ok = false;
  match r {
    Ok(t) => {
      ok = streq(taf_station(&t), "EGLL");
      if taf_is_amd(&t) { ok = false; }
      if taf_is_cor(&t) { ok = false; }
      if taf_day(&t) != 12 { ok = false; }
      if taf_hour(&t) != 17 { ok = false; }
      if taf_minute(&t) != 0 { ok = false; }
      if taf_valid_from_day(&t) != 12 { ok = false; }
      if taf_valid_from_hour(&t) != 18 { ok = false; }
      if taf_valid_to_day(&t) != 13 { ok = false; }
      if taf_valid_to_hour(&t) != 18 { ok = false; }
      if taf_forecast_count(&t) != 0 { ok = false; }
      if taf_extra_count(&t) != 3 { ok = false; }
      if !streq(taf_extra(&t, 0), "24010KT") { ok = false; }
      if !streq(taf_extra(&t, 2), "SCT030") { ok = false; }
      if !streq(taf_extra(&t, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "TAF header, validity, and undecoded base period as extras");
}

fn t19() -> TestResult {
  let r = taf_decode(taf_changes());
  var ok = false;
  match r {
    Ok(t) => {
      ok = taf_forecast_count(&t) == 3;
      if taf_fc_kind(&t, 0) != 1 { ok = false; }
      if taf_fc_kind(&t, 1) != 0 { ok = false; }
      if taf_fc_kind(&t, 2) != 2 { ok = false; }
      if taf_fc_from_day(&t, 0) != 4 { ok = false; }
      if taf_fc_from_hour(&t, 0) != 20 { ok = false; }
      if taf_fc_to_day(&t, 0) != 4 { ok = false; }
      if taf_fc_to_hour(&t, 0) != 23 { ok = false; }
      if !taf_fc_has_wind(&t, 0) { ok = false; }
      if taf_fc_wind_dir(&t, 0) != 200 { ok = false; }
      if taf_fc_wind_speed(&t, 0) != 15 { ok = false; }
      if taf_fc_wind_gust(&t, 0) != 25 { ok = false; }
      if !taf_fc_has_vis(&t, 0) { ok = false; }
      if taf_fc_vis_m(&t, 0) != 3000 { ok = false; }
      if taf_fc_is_cavok(&t, 0) { ok = false; }
      if taf_weather_count(&t) != 1 { ok = false; }
      if !streq(taf_weather_raw(&t, 0), "-RA") { ok = false; }
      if taf_weather_group(&t, 0) != 0 { ok = false; }
      if taf_sky_count(&t) != 2 { ok = false; }
      if !streq(taf_sky_raw(&t, 0), "BKN010") { ok = false; }
      if taf_sky_group(&t, 0) != 0 { ok = false; }
      if taf_sky_cover(&t, 0) != 2 { ok = false; }
      if taf_sky_height_ft(&t, 0) != 1000 { ok = false; }
      if taf_sky_group(&t, 1) != 1 { ok = false; }
      if taf_sky_height_ft(&t, 1) != 2500 { ok = false; }
      if taf_fc_from_day(&t, 1) != 5 { ok = false; }
      if taf_fc_from_hour(&t, 1) != 2 { ok = false; }
      if taf_fc_wind_dir(&t, 1) != 250 { ok = false; }
      if taf_fc_vis_m(&t, 1) != 9999 { ok = false; }
      if taf_fc_from_day(&t, 2) != 5 { ok = false; }
      if taf_fc_from_hour(&t, 2) != 6 { ok = false; }
      if taf_fc_to_day(&t, 2) != -1 { ok = false; }
      if taf_fc_to_hour(&t, 2) != -1 { ok = false; }
      if taf_fc_wind_dir(&t, 2) != 220 { ok = false; }
      if taf_extra_count(&t) != 3 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "TAF TEMPO/BECMG/FM groups decode wind, vis, weather and sky");
}

fn t20() -> TestResult {
  let r = taf_decode(taf_amd());
  var ok = false;
  match r {
    Ok(t) => {
      ok = taf_is_amd(&t);
      if taf_day(&t) != 12 { ok = false; }
      if taf_hour(&t) != 17 { ok = false; }
      if taf_minute(&t) != 0 { ok = false; }
      if taf_forecast_count(&t) != 1 { ok = false; }
      if taf_fc_kind(&t, 0) != 2 { ok = false; }
      if taf_fc_from_day(&t, 0) != 3 { ok = false; }
      if taf_fc_from_hour(&t, 0) != 0 { ok = false; }
      if taf_fc_to_day(&t, 0) != -1 { ok = false; }
      if taf_fc_wind_dir(&t, 0) != 220 { ok = false; }
      if taf_fc_extra_count(&t, 0) != 1 { ok = false; }
      if !streq(taf_fc_extra(&t, 0, 0), "TX32/1218Z") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "TAF AMD, short issue time, short FM group, group extras");
}

fn t21() -> TestResult {
  let r = taf_decode(taf_cavok());
  var ok = false;
  match r {
    Ok(t) => {
      ok = taf_forecast_count(&t) == 1;
      if taf_fc_kind(&t, 0) != 0 { ok = false; }
      if !taf_fc_has_vis(&t, 0) { ok = false; }
      if !taf_fc_is_cavok(&t, 0) { ok = false; }
      if taf_fc_vis_m(&t, 0) != 10000 { ok = false; }
      if taf_fc_has_wind(&t, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "TAF BECMG CAVOK group");
}

fn t22() -> TestResult {
  var ok = taf_err_is("", "taf: missing station at offset 0");
  if !taf_err_is("TAF EGLL", "taf: missing time at offset 8") { ok = false; }
  if !taf_err_is("TAF EGLL 121700Z 1218-1318", "taf: invalid validity at offset 17: 1218-1318") { ok = false; }
  if !taf_err_is("TAF EGLL 121700Z 1218/1318 TEMPO", "taf: missing validity after TEMPO at offset 32") { ok = false; }
  if !taf_err_is("TAF EGLL 121700Z 1218/1318 TEMPO 1220/12x4", "taf: invalid validity at offset 33: 1220/12x4") { ok = false; }
  if !taf_err_is("TAF EGLL 121700Z 1218/1318 FM9900 22010KT", "taf: invalid FM time at offset 27: FM9900") { ok = false; }
  return assert(ok, "TAF malformed station/time/validity/FM carry byte offsets");
}

fn main() -> Int {
  io.println("=== xiom.meteorology conformance tests ===");
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
    io.println("xiom.meteorology: all tests passed");
  } else {
    io.println("xiom.meteorology: tests failed");
  }
  return failed;
}
