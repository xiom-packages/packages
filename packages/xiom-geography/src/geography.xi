// XIOM -- xiom.geography: ISO 3166-1 country table, UN M49 regions, ISO 3166-2
// subdivision syntax, and integer coordinate text codecs.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: pure data + integer math. No floats, no FFI, no locale database.
//
// Model:
//   * Country -- one row of the embedded ISO 3166-1 table (all 249 officially
//     assigned alpha-2 codes): alpha-2, alpha-3, zero-padded 3-digit numeric,
//     English short name, UN M49 top-level continent code and the finest M49
//     region code listed in the embedded region table.
//   * Region -- one row of the embedded UN M49 region table (30 codes: the
//     six top-level regions plus the subregions listed in SPEC.md; 010
//     Antarctica is included so every country code resolves).
//   * Subdivision -- the syntax layer only of ISO 3166-2: "CC-SUB" with a
//     1..3 alphanumeric subdivision part. There is no per-country subdivision
//     list; the raw text is preserved verbatim and the canonical form is
//     uppercase.
//   * Coordinates -- decimal degrees ("[-]DD.dddd", optional N/S/E/W
//     hemisphere) and sexagesimal DMS text (DD deg MM min SS.ssssss sec H)
//     parsed into scaled integer micro-degrees (1e-6 degree), and canonical
//     renderers for both. All math is integer; the division steps are chosen
//     so every canonical render re-parses to exactly the same micro-degree
//     value.
//
// Angular conventions (documented, asserted by the tests):
//   * latitude is [-90000000, 90000000] micro-degrees; longitude is
//     [-180000000, 180000000];
//   * N/E are positive, S/W negative; a hemisphere letter must match the
//     axis (N/S are latitude-only, E/W longitude-only) and must agree with an
//     explicit sign when both are present;
//   * canonical decimal text has exactly six fraction digits and no
//     hemisphere ("-37.975000");
//   * canonical DMS text has two-digit minutes and seconds, exactly six
//     second fraction digits, and a trailing uppercase hemisphere
//     ("37deg58'30.000000\"N" with U+00B0 for deg).
//
// Language notes (XIOM v0.61.3): free functions only; module-level table
// initializers mis-materialize, so the 249+30 rows are compiled into
// `if`-chains behind accessor dispatchers; all Str equality goes through
// xiom.string.compare (BUG 17: `==` on Str values read from Vec[Str] elements
// lowers to a pointer comparison); every Vec element read is bound to a typed
// local first; bytes enter the Int domain through `(byte_at(s, i) as Int) &
// 255` (masked widening); Ok/Err are constructed only in the leaf helpers
// (_geoc_ok/_geoc_err, _geor_ok/_geor_err, _geos_ok/_geos_err,
// _geo_ok_int/_geo_err_int, _geo_ok_str/_geo_err_str) because direct
// construction in other shapes miscompiles. See SPEC.md for the full data
// model, grammar and error catalog.

module xiom.geography

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
//  Types
// ---------------------------------------------------------------------------

/// One ISO 3166-1 country row. `alpha2` and `alpha3` are uppercase ASCII in
/// the table and matched case-insensitively by the lookups; `numeric` is the
/// zero-padded three-digit string; `name` is the ISO English short name;
/// `continent` is the UN M49 top-level region code (002, 009, 010, 019, 142,
/// 150) and `region` the finest M49 code of the 30-row region table that the
/// country belongs to (for Antarctica both are "010").
pub type Country = {
  alpha2: Str;
  alpha3: Str;
  numeric: Str;
  name: Str;
  continent: Str;
  region: Str;
}

/// One UN M49 region row. `code` is the zero-padded three-digit code, `name`
/// the UN English name, and `parent` the next coarser region code ("" for the
/// top-level regions 002, 009, 010, 019, 142 and 150).
pub type Region = {
  code: Str;
  name: Str;
  parent: Str;
}

/// One parsed ISO 3166-2 subdivision code reference. `country` and `part` are
/// the canonical uppercase pieces; `raw` is the input text verbatim.
pub type Subdivision = {
  country: Str;
  part: Str;
  raw: Str;
}

// ---------------------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------------------

const _GEO_PLUS: Int = 43;
const _GEO_MINUS: Int = 45;
const _GEO_HYPHEN: Int = 45;
const _GEO_DOT: Int = 46;
const _GEO_DIGIT_0: Int = 48;
const _GEO_DIGIT_9: Int = 57;
const _GEO_UPPER_A: Int = 65;
const _GEO_UPPER_D: Int = 68;
const _GEO_UPPER_E: Int = 69;
const _GEO_UPPER_M: Int = 77;
const _GEO_UPPER_N: Int = 78;
const _GEO_UPPER_S: Int = 83;
const _GEO_UPPER_W: Int = 87;
const _GEO_UPPER_Z: Int = 90;
const _GEO_LOWER_A: Int = 97;
const _GEO_LOWER_D: Int = 100;
const _GEO_LOWER_M: Int = 109;
const _GEO_LOWER_Z: Int = 122;
const _GEO_LOWER_CASE_BIT: Int = 32;

// UTF-8 symbol bytes, kept in the Int domain (masked widening, see header).
const _GEO_UTF8_C2: Int = 194;
const _GEO_UTF8_DEGREE: Int = 176;    // 0xB0: C2 B0 = U+00B0 DEGREE SIGN
const _GEO_UTF8_MASC: Int = 186;      // 0xBA: C2 BA = U+00BA MASCULINE ORDINAL
const _GEO_UTF8_E2: Int = 226;
const _GEO_UTF8_B1: Int = 128;
const _GEO_UTF8_PRIME: Int = 178;     // 0xB2: E2 80 B2 = U+2032 PRIME
const _GEO_UTF8_DPRIME: Int = 179;    // 0xB3: E2 80 B3 = U+2033 DOUBLE PRIME

const _GEO_COUNT: Int = 249;
const _GEO_REGION_COUNT: Int = 30;
const _GEO_MICRO: Int = 1000000;
const _GEO_LAT_MAX: Int = 90000000;
const _GEO_LON_MAX: Int = 180000000;
const _GEO_LAT_MAX_US: Int = 324000000000;
const _GEO_LON_MAX_US: Int = 648000000000;
const _GEO_SECONDS_PER_DEGREE: Int = 3600;

// ---------------------------------------------------------------------------
//  Result constructors (see the module header)
// ---------------------------------------------------------------------------

fn _geoc_ok(v: Country) -> Result[Country, Str] { return Ok(v); }
fn _geoc_err(m: Str) -> Result[Country, Str] { return Err(m); }
fn _geor_ok(v: Region) -> Result[Region, Str] { return Ok(v); }
fn _geor_err(m: Str) -> Result[Region, Str] { return Err(m); }
fn _geos_ok(v: Subdivision) -> Result[Subdivision, Str] { return Ok(v); }
fn _geos_err(m: Str) -> Result[Subdivision, Str] { return Err(m); }
fn _geo_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _geo_err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _geo_ok_str(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _geo_err_str(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
//  Byte and string helpers
// ---------------------------------------------------------------------------

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 255;
}

fn _is_digit_i(b: Int) -> Bool {
  return b >= _GEO_DIGIT_0 && b <= _GEO_DIGIT_9;
}

fn _is_upper_i(b: Int) -> Bool {
  return b >= _GEO_UPPER_A && b <= _GEO_UPPER_Z;
}

fn _is_lower_i(b: Int) -> Bool {
  return b >= _GEO_LOWER_A && b <= _GEO_LOWER_Z;
}

fn _is_alpha_i(b: Int) -> Bool {
  if _is_upper_i(b) { return true; }
  return _is_lower_i(b);
}

fn _is_alnum_i(b: Int) -> Bool {
  if _is_digit_i(b) { return true; }
  return _is_alpha_i(b);
}

// ASCII uppercase of one Int-domain byte; non-letters pass through.
fn _upper_i(b: Int) -> Int {
  if _is_lower_i(b) { return b - _GEO_LOWER_CASE_BIT; }
  return b;
}

// ASCII uppercase of one UInt8; non-letters pass through.
fn _upper_byte(b: UInt8) -> UInt8 {
  if b >= 97u8 && b <= 122u8 {
    return b - 32u8;
  }
  return b;
}

// ASCII uppercase copy of `s`; non-ASCII bytes pass through unchanged.
fn _ascii_upper(s: Str) -> Str {
  var buf = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    buf.push(_upper_byte(string.byte_at(s, i)));
    i = i + 1;
  }
  return Str::from_utf8(buf);
}

// True when two Str values have identical bytes (BUG 17-safe).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII case-insensitive equality; non-ASCII bytes compare byte-for-byte.
fn _eq_ci(a: Str, b: Str) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x = _byte_at(a, i);
    let y = _byte_at(b, i);
    if _upper_i(x) != _upper_i(y) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly two ASCII letters (alpha-2 shape).
fn _is_alpha2(s: Str) -> Bool {
  if s.len() != 2 { return false; }
  if !_is_alpha_i(_byte_at(s, 0)) { return false; }
  return _is_alpha_i(_byte_at(s, 1));
}

// True when `s` is exactly three ASCII letters (alpha-3 shape).
fn _is_alpha3(s: Str) -> Bool {
  if s.len() != 3 { return false; }
  var i = 0;
  while i < 3 {
    if !_is_alpha_i(_byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is one to three ASCII digits (numeric input shape; the caller
// left-pads to the canonical three digits).
fn _is_numeric13(s: Str) -> Bool {
  let n = s.len();
  if n < 1 { return false; }
  if n > 3 { return false; }
  var i = 0;
  while i < n {
    if !_is_digit_i(_byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly three ASCII digits (canonical numeric shape).
fn _is_numeric3(s: Str) -> Bool {
  if s.len() != 3 { return false; }
  var i = 0;
  while i < 3 {
    if !_is_digit_i(_byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Left-pad a 1..3 digit numeric string to the canonical three digits.
fn _pad_numeric(code: Str) -> Str {
  let n = code.len();
  if n >= 3 { return code; }
  if n == 2 { return "0" + code; }
  return "00" + code;
}

fn _pad2(n: Int) -> Str {
  if n < 10 { return "0" + convert.int_to_string(n); }
  return convert.int_to_string(n);
}

fn _pad6(n: Int) -> Str {
  var s = convert.int_to_string(n);
  while s.len() < 6 {
    s = "0" + s;
  }
  return s;
}

// Absolute value of an Int magnitude. Coordinate-scale values are far from
// the Int minimum, where 0 - n would overflow.
fn _abs_int(n: Int) -> Int {
  if n < 0 { return 0 - n; }
  return n;
}

// ---------------------------------------------------------------------------
//  Embedded ISO 3166-1 table (249 officially assigned codes)
// ---------------------------------------------------------------------------
//
// Rows are in ascending alpha-2 order. Module-level table initializers are
// mis-materialized by v0.61.3, so the rows are explicit `if`-chains of
// one-line builders behind `_country(i)`; this mirrors xiom.l10n-currency and
// xiom.iban. `_missing_country` (empty alpha-2) is the past-the-end sentinel
// and is never exposed.

fn _mk_country(a2: Str, a3: Str, num: Str, nm: Str, cont: Str, reg: Str) -> Country {
  let v = Country{ alpha2: a2; alpha3: a3; numeric: num; name: nm; continent: cont; region: reg };
  return v;
}

fn _missing_country() -> Country {
  return _mk_country("", "", "", "", "", "");
}

// Rows 0..49 (AD..CR).
fn _bank_a(i: Int) -> Country {
  if i == 0 { return _mk_country("AD", "AND", "020", "Andorra", "150", "039"); }
  if i == 1 { return _mk_country("AE", "ARE", "784", "United Arab Emirates", "142", "145"); }
  if i == 2 { return _mk_country("AF", "AFG", "004", "Afghanistan", "142", "034"); }
  if i == 3 { return _mk_country("AG", "ATG", "028", "Antigua and Barbuda", "019", "029"); }
  if i == 4 { return _mk_country("AI", "AIA", "660", "Anguilla", "019", "029"); }
  if i == 5 { return _mk_country("AL", "ALB", "008", "Albania", "150", "039"); }
  if i == 6 { return _mk_country("AM", "ARM", "051", "Armenia", "142", "145"); }
  if i == 7 { return _mk_country("AO", "AGO", "024", "Angola", "002", "017"); }
  if i == 8 { return _mk_country("AQ", "ATA", "010", "Antarctica", "010", "010"); }
  if i == 9 { return _mk_country("AR", "ARG", "032", "Argentina", "019", "005"); }
  if i == 10 { return _mk_country("AS", "ASM", "016", "American Samoa", "009", "061"); }
  if i == 11 { return _mk_country("AT", "AUT", "040", "Austria", "150", "155"); }
  if i == 12 { return _mk_country("AU", "AUS", "036", "Australia", "009", "053"); }
  if i == 13 { return _mk_country("AW", "ABW", "533", "Aruba", "019", "029"); }
  if i == 14 { return _mk_country("AX", "ALA", "248", "Åland Islands", "150", "154"); }
  if i == 15 { return _mk_country("AZ", "AZE", "031", "Azerbaijan", "142", "145"); }
  if i == 16 { return _mk_country("BA", "BIH", "070", "Bosnia and Herzegovina", "150", "039"); }
  if i == 17 { return _mk_country("BB", "BRB", "052", "Barbados", "019", "029"); }
  if i == 18 { return _mk_country("BD", "BGD", "050", "Bangladesh", "142", "034"); }
  if i == 19 { return _mk_country("BE", "BEL", "056", "Belgium", "150", "155"); }
  if i == 20 { return _mk_country("BF", "BFA", "854", "Burkina Faso", "002", "011"); }
  if i == 21 { return _mk_country("BG", "BGR", "100", "Bulgaria", "150", "151"); }
  if i == 22 { return _mk_country("BH", "BHR", "048", "Bahrain", "142", "145"); }
  if i == 23 { return _mk_country("BI", "BDI", "108", "Burundi", "002", "014"); }
  if i == 24 { return _mk_country("BJ", "BEN", "204", "Benin", "002", "011"); }
  if i == 25 { return _mk_country("BL", "BLM", "652", "Saint Barthélemy", "019", "029"); }
  if i == 26 { return _mk_country("BM", "BMU", "060", "Bermuda", "019", "021"); }
  if i == 27 { return _mk_country("BN", "BRN", "096", "Brunei Darussalam", "142", "035"); }
  if i == 28 { return _mk_country("BO", "BOL", "068", "Bolivia (Plurinational State of)", "019", "005"); }
  if i == 29 { return _mk_country("BQ", "BES", "535", "Bonaire, Sint Eustatius and Saba", "019", "029"); }
  if i == 30 { return _mk_country("BR", "BRA", "076", "Brazil", "019", "005"); }
  if i == 31 { return _mk_country("BS", "BHS", "044", "Bahamas", "019", "029"); }
  if i == 32 { return _mk_country("BT", "BTN", "064", "Bhutan", "142", "034"); }
  if i == 33 { return _mk_country("BV", "BVT", "074", "Bouvet Island", "019", "005"); }
  if i == 34 { return _mk_country("BW", "BWA", "072", "Botswana", "002", "018"); }
  if i == 35 { return _mk_country("BY", "BLR", "112", "Belarus", "150", "151"); }
  if i == 36 { return _mk_country("BZ", "BLZ", "084", "Belize", "019", "013"); }
  if i == 37 { return _mk_country("CA", "CAN", "124", "Canada", "019", "021"); }
  if i == 38 { return _mk_country("CC", "CCK", "166", "Cocos (Keeling) Islands", "009", "053"); }
  if i == 39 { return _mk_country("CD", "COD", "180", "Congo (Democratic Republic of the)", "002", "017"); }
  if i == 40 { return _mk_country("CF", "CAF", "140", "Central African Republic", "002", "017"); }
  if i == 41 { return _mk_country("CG", "COG", "178", "Congo", "002", "017"); }
  if i == 42 { return _mk_country("CH", "CHE", "756", "Switzerland", "150", "155"); }
  if i == 43 { return _mk_country("CI", "CIV", "384", "Côte d'Ivoire", "002", "011"); }
  if i == 44 { return _mk_country("CK", "COK", "184", "Cook Islands", "009", "061"); }
  if i == 45 { return _mk_country("CL", "CHL", "152", "Chile", "019", "005"); }
  if i == 46 { return _mk_country("CM", "CMR", "120", "Cameroon", "002", "017"); }
  if i == 47 { return _mk_country("CN", "CHN", "156", "China", "142", "030"); }
  if i == 48 { return _mk_country("CO", "COL", "170", "Colombia", "019", "005"); }
  if i == 49 { return _mk_country("CR", "CRI", "188", "Costa Rica", "019", "013"); }
  return _missing_country();
}

// Rows 50..99 (CU..HU).
fn _bank_b(i: Int) -> Country {
  if i == 0 { return _mk_country("CU", "CUB", "192", "Cuba", "019", "029"); }
  if i == 1 { return _mk_country("CV", "CPV", "132", "Cabo Verde", "002", "011"); }
  if i == 2 { return _mk_country("CW", "CUW", "531", "Curaçao", "019", "029"); }
  if i == 3 { return _mk_country("CX", "CXR", "162", "Christmas Island", "009", "053"); }
  if i == 4 { return _mk_country("CY", "CYP", "196", "Cyprus", "142", "145"); }
  if i == 5 { return _mk_country("CZ", "CZE", "203", "Czechia", "150", "151"); }
  if i == 6 { return _mk_country("DE", "DEU", "276", "Germany", "150", "155"); }
  if i == 7 { return _mk_country("DJ", "DJI", "262", "Djibouti", "002", "014"); }
  if i == 8 { return _mk_country("DK", "DNK", "208", "Denmark", "150", "154"); }
  if i == 9 { return _mk_country("DM", "DMA", "212", "Dominica", "019", "029"); }
  if i == 10 { return _mk_country("DO", "DOM", "214", "Dominican Republic", "019", "029"); }
  if i == 11 { return _mk_country("DZ", "DZA", "012", "Algeria", "002", "015"); }
  if i == 12 { return _mk_country("EC", "ECU", "218", "Ecuador", "019", "005"); }
  if i == 13 { return _mk_country("EE", "EST", "233", "Estonia", "150", "154"); }
  if i == 14 { return _mk_country("EG", "EGY", "818", "Egypt", "002", "015"); }
  if i == 15 { return _mk_country("EH", "ESH", "732", "Western Sahara", "002", "015"); }
  if i == 16 { return _mk_country("ER", "ERI", "232", "Eritrea", "002", "014"); }
  if i == 17 { return _mk_country("ES", "ESP", "724", "Spain", "150", "039"); }
  if i == 18 { return _mk_country("ET", "ETH", "231", "Ethiopia", "002", "014"); }
  if i == 19 { return _mk_country("FI", "FIN", "246", "Finland", "150", "154"); }
  if i == 20 { return _mk_country("FJ", "FJI", "242", "Fiji", "009", "054"); }
  if i == 21 { return _mk_country("FK", "FLK", "238", "Falkland Islands (Malvinas)", "019", "005"); }
  if i == 22 { return _mk_country("FM", "FSM", "583", "Micronesia (Federated States of)", "009", "057"); }
  if i == 23 { return _mk_country("FO", "FRO", "234", "Faroe Islands", "150", "154"); }
  if i == 24 { return _mk_country("FR", "FRA", "250", "France", "150", "155"); }
  if i == 25 { return _mk_country("GA", "GAB", "266", "Gabon", "002", "017"); }
  if i == 26 { return _mk_country("GB", "GBR", "826", "United Kingdom of Great Britain and Northern Ireland", "150", "154"); }
  if i == 27 { return _mk_country("GD", "GRD", "308", "Grenada", "019", "029"); }
  if i == 28 { return _mk_country("GE", "GEO", "268", "Georgia", "142", "145"); }
  if i == 29 { return _mk_country("GF", "GUF", "254", "French Guiana", "019", "005"); }
  if i == 30 { return _mk_country("GG", "GGY", "831", "Guernsey", "150", "154"); }
  if i == 31 { return _mk_country("GH", "GHA", "288", "Ghana", "002", "011"); }
  if i == 32 { return _mk_country("GI", "GIB", "292", "Gibraltar", "150", "039"); }
  if i == 33 { return _mk_country("GL", "GRL", "304", "Greenland", "019", "021"); }
  if i == 34 { return _mk_country("GM", "GMB", "270", "Gambia", "002", "011"); }
  if i == 35 { return _mk_country("GN", "GIN", "324", "Guinea", "002", "011"); }
  if i == 36 { return _mk_country("GP", "GLP", "312", "Guadeloupe", "019", "029"); }
  if i == 37 { return _mk_country("GQ", "GNQ", "226", "Equatorial Guinea", "002", "017"); }
  if i == 38 { return _mk_country("GR", "GRC", "300", "Greece", "150", "039"); }
  if i == 39 { return _mk_country("GS", "SGS", "239", "South Georgia and the South Sandwich Islands", "019", "005"); }
  if i == 40 { return _mk_country("GT", "GTM", "320", "Guatemala", "019", "013"); }
  if i == 41 { return _mk_country("GU", "GUM", "316", "Guam", "009", "057"); }
  if i == 42 { return _mk_country("GW", "GNB", "624", "Guinea-Bissau", "002", "011"); }
  if i == 43 { return _mk_country("GY", "GUY", "328", "Guyana", "019", "005"); }
  if i == 44 { return _mk_country("HK", "HKG", "344", "Hong Kong", "142", "030"); }
  if i == 45 { return _mk_country("HM", "HMD", "334", "Heard Island and McDonald Islands", "009", "053"); }
  if i == 46 { return _mk_country("HN", "HND", "340", "Honduras", "019", "013"); }
  if i == 47 { return _mk_country("HR", "HRV", "191", "Croatia", "150", "039"); }
  if i == 48 { return _mk_country("HT", "HTI", "332", "Haiti", "019", "029"); }
  if i == 49 { return _mk_country("HU", "HUN", "348", "Hungary", "150", "151"); }
  return _missing_country();
}

// Rows 100..149 (ID..MQ).
fn _bank_c(i: Int) -> Country {
  if i == 0 { return _mk_country("ID", "IDN", "360", "Indonesia", "142", "035"); }
  if i == 1 { return _mk_country("IE", "IRL", "372", "Ireland", "150", "154"); }
  if i == 2 { return _mk_country("IL", "ISR", "376", "Israel", "142", "145"); }
  if i == 3 { return _mk_country("IM", "IMN", "833", "Isle of Man", "150", "154"); }
  if i == 4 { return _mk_country("IN", "IND", "356", "India", "142", "034"); }
  if i == 5 { return _mk_country("IO", "IOT", "086", "British Indian Ocean Territory", "002", "014"); }
  if i == 6 { return _mk_country("IQ", "IRQ", "368", "Iraq", "142", "145"); }
  if i == 7 { return _mk_country("IR", "IRN", "364", "Iran (Islamic Republic of)", "142", "034"); }
  if i == 8 { return _mk_country("IS", "ISL", "352", "Iceland", "150", "154"); }
  if i == 9 { return _mk_country("IT", "ITA", "380", "Italy", "150", "039"); }
  if i == 10 { return _mk_country("JE", "JEY", "832", "Jersey", "150", "154"); }
  if i == 11 { return _mk_country("JM", "JAM", "388", "Jamaica", "019", "029"); }
  if i == 12 { return _mk_country("JO", "JOR", "400", "Jordan", "142", "145"); }
  if i == 13 { return _mk_country("JP", "JPN", "392", "Japan", "142", "030"); }
  if i == 14 { return _mk_country("KE", "KEN", "404", "Kenya", "002", "014"); }
  if i == 15 { return _mk_country("KG", "KGZ", "417", "Kyrgyzstan", "142", "143"); }
  if i == 16 { return _mk_country("KH", "KHM", "116", "Cambodia", "142", "035"); }
  if i == 17 { return _mk_country("KI", "KIR", "296", "Kiribati", "009", "057"); }
  if i == 18 { return _mk_country("KM", "COM", "174", "Comoros", "002", "014"); }
  if i == 19 { return _mk_country("KN", "KNA", "659", "Saint Kitts and Nevis", "019", "029"); }
  if i == 20 { return _mk_country("KP", "PRK", "408", "Korea (Democratic People's Republic of)", "142", "030"); }
  if i == 21 { return _mk_country("KR", "KOR", "410", "Korea (Republic of)", "142", "030"); }
  if i == 22 { return _mk_country("KW", "KWT", "414", "Kuwait", "142", "145"); }
  if i == 23 { return _mk_country("KY", "CYM", "136", "Cayman Islands", "019", "029"); }
  if i == 24 { return _mk_country("KZ", "KAZ", "398", "Kazakhstan", "142", "143"); }
  if i == 25 { return _mk_country("LA", "LAO", "418", "Lao People's Democratic Republic", "142", "035"); }
  if i == 26 { return _mk_country("LB", "LBN", "422", "Lebanon", "142", "145"); }
  if i == 27 { return _mk_country("LC", "LCA", "662", "Saint Lucia", "019", "029"); }
  if i == 28 { return _mk_country("LI", "LIE", "438", "Liechtenstein", "150", "155"); }
  if i == 29 { return _mk_country("LK", "LKA", "144", "Sri Lanka", "142", "034"); }
  if i == 30 { return _mk_country("LR", "LBR", "430", "Liberia", "002", "011"); }
  if i == 31 { return _mk_country("LS", "LSO", "426", "Lesotho", "002", "018"); }
  if i == 32 { return _mk_country("LT", "LTU", "440", "Lithuania", "150", "154"); }
  if i == 33 { return _mk_country("LU", "LUX", "442", "Luxembourg", "150", "155"); }
  if i == 34 { return _mk_country("LV", "LVA", "428", "Latvia", "150", "154"); }
  if i == 35 { return _mk_country("LY", "LBY", "434", "Libya", "002", "015"); }
  if i == 36 { return _mk_country("MA", "MAR", "504", "Morocco", "002", "015"); }
  if i == 37 { return _mk_country("MC", "MCO", "492", "Monaco", "150", "155"); }
  if i == 38 { return _mk_country("MD", "MDA", "498", "Moldova (Republic of)", "150", "151"); }
  if i == 39 { return _mk_country("ME", "MNE", "499", "Montenegro", "150", "039"); }
  if i == 40 { return _mk_country("MF", "MAF", "663", "Saint Martin (French part)", "019", "029"); }
  if i == 41 { return _mk_country("MG", "MDG", "450", "Madagascar", "002", "014"); }
  if i == 42 { return _mk_country("MH", "MHL", "584", "Marshall Islands", "009", "057"); }
  if i == 43 { return _mk_country("MK", "MKD", "807", "North Macedonia", "150", "039"); }
  if i == 44 { return _mk_country("ML", "MLI", "466", "Mali", "002", "011"); }
  if i == 45 { return _mk_country("MM", "MMR", "104", "Myanmar", "142", "035"); }
  if i == 46 { return _mk_country("MN", "MNG", "496", "Mongolia", "142", "030"); }
  if i == 47 { return _mk_country("MO", "MAC", "446", "Macao", "142", "030"); }
  if i == 48 { return _mk_country("MP", "MNP", "580", "Northern Mariana Islands", "009", "057"); }
  if i == 49 { return _mk_country("MQ", "MTQ", "474", "Martinique", "019", "029"); }
  return _missing_country();
}

// Rows 150..199 (MR..SI).
fn _bank_d(i: Int) -> Country {
  if i == 0 { return _mk_country("MR", "MRT", "478", "Mauritania", "002", "011"); }
  if i == 1 { return _mk_country("MS", "MSR", "500", "Montserrat", "019", "029"); }
  if i == 2 { return _mk_country("MT", "MLT", "470", "Malta", "150", "039"); }
  if i == 3 { return _mk_country("MU", "MUS", "480", "Mauritius", "002", "014"); }
  if i == 4 { return _mk_country("MV", "MDV", "462", "Maldives", "142", "034"); }
  if i == 5 { return _mk_country("MW", "MWI", "454", "Malawi", "002", "014"); }
  if i == 6 { return _mk_country("MX", "MEX", "484", "Mexico", "019", "013"); }
  if i == 7 { return _mk_country("MY", "MYS", "458", "Malaysia", "142", "035"); }
  if i == 8 { return _mk_country("MZ", "MOZ", "508", "Mozambique", "002", "014"); }
  if i == 9 { return _mk_country("NA", "NAM", "516", "Namibia", "002", "018"); }
  if i == 10 { return _mk_country("NC", "NCL", "540", "New Caledonia", "009", "054"); }
  if i == 11 { return _mk_country("NE", "NER", "562", "Niger", "002", "011"); }
  if i == 12 { return _mk_country("NF", "NFK", "574", "Norfolk Island", "009", "053"); }
  if i == 13 { return _mk_country("NG", "NGA", "566", "Nigeria", "002", "011"); }
  if i == 14 { return _mk_country("NI", "NIC", "558", "Nicaragua", "019", "013"); }
  if i == 15 { return _mk_country("NL", "NLD", "528", "Netherlands", "150", "155"); }
  if i == 16 { return _mk_country("NO", "NOR", "578", "Norway", "150", "154"); }
  if i == 17 { return _mk_country("NP", "NPL", "524", "Nepal", "142", "034"); }
  if i == 18 { return _mk_country("NR", "NRU", "520", "Nauru", "009", "057"); }
  if i == 19 { return _mk_country("NU", "NIU", "570", "Niue", "009", "061"); }
  if i == 20 { return _mk_country("NZ", "NZL", "554", "New Zealand", "009", "053"); }
  if i == 21 { return _mk_country("OM", "OMN", "512", "Oman", "142", "145"); }
  if i == 22 { return _mk_country("PA", "PAN", "591", "Panama", "019", "013"); }
  if i == 23 { return _mk_country("PE", "PER", "604", "Peru", "019", "005"); }
  if i == 24 { return _mk_country("PF", "PYF", "258", "French Polynesia", "009", "061"); }
  if i == 25 { return _mk_country("PG", "PNG", "598", "Papua New Guinea", "009", "054"); }
  if i == 26 { return _mk_country("PH", "PHL", "608", "Philippines", "142", "035"); }
  if i == 27 { return _mk_country("PK", "PAK", "586", "Pakistan", "142", "034"); }
  if i == 28 { return _mk_country("PL", "POL", "616", "Poland", "150", "151"); }
  if i == 29 { return _mk_country("PM", "SPM", "666", "Saint Pierre and Miquelon", "019", "021"); }
  if i == 30 { return _mk_country("PN", "PCN", "612", "Pitcairn", "009", "061"); }
  if i == 31 { return _mk_country("PR", "PRI", "630", "Puerto Rico", "019", "029"); }
  if i == 32 { return _mk_country("PS", "PSE", "275", "Palestine, State of", "142", "145"); }
  if i == 33 { return _mk_country("PT", "PRT", "620", "Portugal", "150", "039"); }
  if i == 34 { return _mk_country("PW", "PLW", "585", "Palau", "009", "057"); }
  if i == 35 { return _mk_country("PY", "PRY", "600", "Paraguay", "019", "005"); }
  if i == 36 { return _mk_country("QA", "QAT", "634", "Qatar", "142", "145"); }
  if i == 37 { return _mk_country("RE", "REU", "638", "Réunion", "002", "014"); }
  if i == 38 { return _mk_country("RO", "ROU", "642", "Romania", "150", "151"); }
  if i == 39 { return _mk_country("RS", "SRB", "688", "Serbia", "150", "039"); }
  if i == 40 { return _mk_country("RU", "RUS", "643", "Russian Federation", "150", "151"); }
  if i == 41 { return _mk_country("RW", "RWA", "646", "Rwanda", "002", "014"); }
  if i == 42 { return _mk_country("SA", "SAU", "682", "Saudi Arabia", "142", "145"); }
  if i == 43 { return _mk_country("SB", "SLB", "090", "Solomon Islands", "009", "054"); }
  if i == 44 { return _mk_country("SC", "SYC", "690", "Seychelles", "002", "014"); }
  if i == 45 { return _mk_country("SD", "SDN", "729", "Sudan", "002", "015"); }
  if i == 46 { return _mk_country("SE", "SWE", "752", "Sweden", "150", "154"); }
  if i == 47 { return _mk_country("SG", "SGP", "702", "Singapore", "142", "035"); }
  if i == 48 { return _mk_country("SH", "SHN", "654", "Saint Helena, Ascension and Tristan da Cunha", "002", "011"); }
  if i == 49 { return _mk_country("SI", "SVN", "705", "Slovenia", "150", "039"); }
  return _missing_country();
}

// Rows 200..248 (SJ..ZW).
fn _bank_e(i: Int) -> Country {
  if i == 0 { return _mk_country("SJ", "SJM", "744", "Svalbard and Jan Mayen", "150", "154"); }
  if i == 1 { return _mk_country("SK", "SVK", "703", "Slovakia", "150", "151"); }
  if i == 2 { return _mk_country("SL", "SLE", "694", "Sierra Leone", "002", "011"); }
  if i == 3 { return _mk_country("SM", "SMR", "674", "San Marino", "150", "039"); }
  if i == 4 { return _mk_country("SN", "SEN", "686", "Senegal", "002", "011"); }
  if i == 5 { return _mk_country("SO", "SOM", "706", "Somalia", "002", "014"); }
  if i == 6 { return _mk_country("SR", "SUR", "740", "Suriname", "019", "005"); }
  if i == 7 { return _mk_country("SS", "SSD", "728", "South Sudan", "002", "014"); }
  if i == 8 { return _mk_country("ST", "STP", "678", "Sao Tome and Principe", "002", "017"); }
  if i == 9 { return _mk_country("SV", "SLV", "222", "El Salvador", "019", "013"); }
  if i == 10 { return _mk_country("SX", "SXM", "534", "Sint Maarten (Dutch part)", "019", "029"); }
  if i == 11 { return _mk_country("SY", "SYR", "760", "Syrian Arab Republic", "142", "145"); }
  if i == 12 { return _mk_country("SZ", "SWZ", "748", "Eswatini", "002", "018"); }
  if i == 13 { return _mk_country("TC", "TCA", "796", "Turks and Caicos Islands", "019", "029"); }
  if i == 14 { return _mk_country("TD", "TCD", "148", "Chad", "002", "017"); }
  if i == 15 { return _mk_country("TF", "ATF", "260", "French Southern Territories", "002", "014"); }
  if i == 16 { return _mk_country("TG", "TGO", "768", "Togo", "002", "011"); }
  if i == 17 { return _mk_country("TH", "THA", "764", "Thailand", "142", "035"); }
  if i == 18 { return _mk_country("TJ", "TJK", "762", "Tajikistan", "142", "143"); }
  if i == 19 { return _mk_country("TK", "TKL", "772", "Tokelau", "009", "061"); }
  if i == 20 { return _mk_country("TL", "TLS", "626", "Timor-Leste", "142", "035"); }
  if i == 21 { return _mk_country("TM", "TKM", "795", "Turkmenistan", "142", "143"); }
  if i == 22 { return _mk_country("TN", "TUN", "788", "Tunisia", "002", "015"); }
  if i == 23 { return _mk_country("TO", "TON", "776", "Tonga", "009", "061"); }
  if i == 24 { return _mk_country("TR", "TUR", "792", "Türkiye", "142", "145"); }
  if i == 25 { return _mk_country("TT", "TTO", "780", "Trinidad and Tobago", "019", "029"); }
  if i == 26 { return _mk_country("TV", "TUV", "798", "Tuvalu", "009", "061"); }
  if i == 27 { return _mk_country("TW", "TWN", "158", "Taiwan, Province of China", "142", "030"); }
  if i == 28 { return _mk_country("TZ", "TZA", "834", "Tanzania, United Republic of", "002", "014"); }
  if i == 29 { return _mk_country("UA", "UKR", "804", "Ukraine", "150", "151"); }
  if i == 30 { return _mk_country("UG", "UGA", "800", "Uganda", "002", "014"); }
  if i == 31 { return _mk_country("UM", "UMI", "581", "United States Minor Outlying Islands", "009", "057"); }
  if i == 32 { return _mk_country("US", "USA", "840", "United States of America", "019", "021"); }
  if i == 33 { return _mk_country("UY", "URY", "858", "Uruguay", "019", "005"); }
  if i == 34 { return _mk_country("UZ", "UZB", "860", "Uzbekistan", "142", "143"); }
  if i == 35 { return _mk_country("VA", "VAT", "336", "Holy See", "150", "039"); }
  if i == 36 { return _mk_country("VC", "VCT", "670", "Saint Vincent and the Grenadines", "019", "029"); }
  if i == 37 { return _mk_country("VE", "VEN", "862", "Venezuela (Bolivarian Republic of)", "019", "005"); }
  if i == 38 { return _mk_country("VG", "VGB", "092", "Virgin Islands (British)", "019", "029"); }
  if i == 39 { return _mk_country("VI", "VIR", "850", "Virgin Islands (U.S.)", "019", "029"); }
  if i == 40 { return _mk_country("VN", "VNM", "704", "Viet Nam", "142", "035"); }
  if i == 41 { return _mk_country("VU", "VUT", "548", "Vanuatu", "009", "054"); }
  if i == 42 { return _mk_country("WF", "WLF", "876", "Wallis and Futuna", "009", "061"); }
  if i == 43 { return _mk_country("WS", "WSM", "882", "Samoa", "009", "061"); }
  if i == 44 { return _mk_country("YE", "YEM", "887", "Yemen", "142", "145"); }
  if i == 45 { return _mk_country("YT", "MYT", "175", "Mayotte", "002", "014"); }
  if i == 46 { return _mk_country("ZA", "ZAF", "710", "South Africa", "002", "018"); }
  if i == 47 { return _mk_country("ZM", "ZMB", "894", "Zambia", "002", "014"); }
  if i == 48 { return _mk_country("ZW", "ZWE", "716", "Zimbabwe", "002", "014"); }
  return _missing_country();
}

// Row dispatch. `i` outside 0.._GEO_COUNT-1 yields the past-the-end sentinel.
fn _country(i: Int) -> Country {
  if i < 0 { return _missing_country(); }
  if i < 50 { return _bank_a(i); }
  if i < 100 { return _bank_b(i - 50); }
  if i < 150 { return _bank_c(i - 100); }
  if i < 200 { return _bank_d(i - 150); }
  if i < _GEO_COUNT { return _bank_e(i - 200); }
  return _missing_country();
}

// Index of the row whose alpha-2 equals `code` ASCII-case-insensitively, or -1.
fn _find_alpha2(code: Str) -> Int {
  var i = 0;
  while i < _GEO_COUNT {
    let c = _country(i);
    let a = c.alpha2;
    if _eq_ci(a, code) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Index of the row whose alpha-3 equals `code` ASCII-case-insensitively, or -1.
fn _find_alpha3(code: Str) -> Int {
  var i = 0;
  while i < _GEO_COUNT {
    let c = _country(i);
    let a = c.alpha3;
    if _eq_ci(a, code) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Index of the row whose numeric equals the canonical `code`, or -1. Callers
// validate the 3-digit shape first.
fn _find_numeric(code: Str) -> Int {
  var i = 0;
  while i < _GEO_COUNT {
    let c = _country(i);
    let n = c.numeric;
    if _streq(n, code) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// ---------------------------------------------------------------------------
//  Embedded UN M49 region table (30 codes; see SPEC.md)
// ---------------------------------------------------------------------------
//
// Includes 010 Antarctica, the top-level region of the AQ country row, so
// every `continent`/`region` code of the country table resolves here.

fn _mk_region(code: Str, nm: Str, parent: Str) -> Region {
  let v = Region{ code: code; name: nm; parent: parent };
  return v;
}

fn _missing_region() -> Region {
  return _mk_region("", "", "");
}

// Rows 0..29 (ascending numeric code order).
fn _region_rows(i: Int) -> Region {
  if i == 0 { return _mk_region("002", "Africa", ""); }
  if i == 1 { return _mk_region("005", "South America", "019"); }
  if i == 2 { return _mk_region("009", "Oceania", ""); }
  if i == 3 { return _mk_region("010", "Antarctica", ""); }
  if i == 4 { return _mk_region("011", "Western Africa", "202"); }
  if i == 5 { return _mk_region("013", "Central America", "019"); }
  if i == 6 { return _mk_region("014", "Eastern Africa", "202"); }
  if i == 7 { return _mk_region("015", "Northern Africa", "002"); }
  if i == 8 { return _mk_region("017", "Middle Africa", "202"); }
  if i == 9 { return _mk_region("018", "Southern Africa", "202"); }
  if i == 10 { return _mk_region("019", "Americas", ""); }
  if i == 11 { return _mk_region("021", "Northern America", "019"); }
  if i == 12 { return _mk_region("029", "Caribbean", "019"); }
  if i == 13 { return _mk_region("030", "Eastern Asia", "142"); }
  if i == 14 { return _mk_region("034", "Southern Asia", "142"); }
  if i == 15 { return _mk_region("035", "South-Eastern Asia", "142"); }
  if i == 16 { return _mk_region("039", "Southern Europe", "150"); }
  if i == 17 { return _mk_region("053", "Australia and New Zealand", "009"); }
  if i == 18 { return _mk_region("054", "Melanesia", "009"); }
  if i == 19 { return _mk_region("057", "Micronesia", "009"); }
  if i == 20 { return _mk_region("061", "Polynesia", "009"); }
  if i == 21 { return _mk_region("142", "Asia", ""); }
  if i == 22 { return _mk_region("143", "Central Asia", "142"); }
  if i == 23 { return _mk_region("145", "Western Asia", "142"); }
  if i == 24 { return _mk_region("150", "Europe", ""); }
  if i == 25 { return _mk_region("151", "Eastern Europe", "150"); }
  if i == 26 { return _mk_region("154", "Northern Europe", "150"); }
  if i == 27 { return _mk_region("155", "Western Europe", "150"); }
  if i == 28 { return _mk_region("202", "Sub-Saharan Africa", "002"); }
  if i == 29 { return _mk_region("419", "Latin America and the Caribbean", "019"); }
  return _missing_region();
}

fn _region(i: Int) -> Region {
  if i < 0 { return _missing_region(); }
  if i < _GEO_REGION_COUNT { return _region_rows(i); }
  return _missing_region();
}

// Index of the region row whose code equals `code`, or -1. Callers validate
// the 3-digit shape first.
fn _find_region(code: Str) -> Int {
  var i = 0;
  while i < _GEO_REGION_COUNT {
    let r = _region(i);
    let c = r.code;
    if _streq(c, code) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// ---------------------------------------------------------------------------
//  Public API -- country table
// ---------------------------------------------------------------------------

/// Number of country rows in the embedded ISO 3166-1 table.
/// Returns: 249 (all officially assigned alpha-2 codes at the 0.1.0 cut-off).
/// Error case: none.
/// Complexity: O(1).
pub fn geog_country_count() -> Int {
  return _GEO_COUNT;
}

/// Country row by index, in ascending alpha-2 order.
/// Params: index - 0 .. geog_country_count()-1.
/// Returns: Ok(Country); Err("geography: index out of range: <index>")
/// otherwise.
/// Error case: see above.
/// Complexity: O(1).
pub fn geog_country_at(index: Int) -> Result[Country, Str] {
  if index < 0 {
    return _geoc_err("geography: index out of range: " + convert.int_to_string(index));
  }
  if index >= _GEO_COUNT {
    return _geoc_err("geography: index out of range: " + convert.int_to_string(index));
  }
  let c = _country(index);
  let a2 = c.alpha2;
  if a2.len() == 0 {
    return _geoc_err("geography: index out of range: " + convert.int_to_string(index));
  }
  return _geoc_ok(c);
}

/// Look up a country by its two-letter alpha-2 code.
/// Params: code - exactly two ASCII letters; case-insensitive.
/// Returns: Ok(Country); Err("geography: bad alpha-2 code: <code>") for a
/// malformed shape, or Err("geography: unknown country code: <code>") when
/// well formed but not in the table.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 249 rows).
pub fn geog_country_by_alpha2(code: Str) -> Result[Country, Str] {
  if !_is_alpha2(code) {
    return _geoc_err("geography: bad alpha-2 code: " + code);
  }
  let idx = _find_alpha2(code);
  if idx < 0 {
    return _geoc_err("geography: unknown country code: " + code);
  }
  let c = _country(idx);
  let a = c.alpha2;
  if a.len() == 0 {
    return _geoc_err("geography: unknown country code: " + code);
  }
  return _geoc_ok(c);
}

/// Look up a country by its three-letter alpha-3 code.
/// Params: code - exactly three ASCII letters; case-insensitive.
/// Returns: Ok(Country); Err("geography: bad alpha-3 code: <code>") for a
/// malformed shape, or Err("geography: unknown country code: <code>") when
/// well formed but not in the table.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 249 rows).
pub fn geog_country_by_alpha3(code: Str) -> Result[Country, Str] {
  if !_is_alpha3(code) {
    return _geoc_err("geography: bad alpha-3 code: " + code);
  }
  let idx = _find_alpha3(code);
  if idx < 0 {
    return _geoc_err("geography: unknown country code: " + code);
  }
  let c = _country(idx);
  let a = c.alpha3;
  if a.len() == 0 {
    return _geoc_err("geography: unknown country code: " + code);
  }
  return _geoc_ok(c);
}

/// Look up a country by its numeric code, left-zero-padded as needed.
/// Params: code - one to three ASCII digits ("300", "8", "08"); the lookup
/// pads on the left, so "8" resolves like "008".
/// Returns: Ok(Country); Err("geography: bad numeric code: <code>") for any
/// other shape, or Err("geography: unknown numeric code: <code>") when no row
/// carries those digits.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 249 rows).
pub fn geog_country_by_numeric(code: Str) -> Result[Country, Str] {
  if !_is_numeric13(code) {
    return _geoc_err("geography: bad numeric code: " + code);
  }
  let padded = _pad_numeric(code);
  let idx = _find_numeric(padded);
  if idx < 0 {
    return _geoc_err("geography: unknown numeric code: " + code);
  }
  let c = _country(idx);
  let a = c.numeric;
  if a.len() == 0 {
    return _geoc_err("geography: unknown numeric code: " + code);
  }
  return _geoc_ok(c);
}

/// Validity check by alpha-2 code.
/// Returns: true iff geog_country_by_alpha2 accepts `code`.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn geog_country_is_valid_alpha2(code: Str) -> Bool {
  match geog_country_by_alpha2(code) {
    Ok(c) => {
      let a = c.alpha2;
      return a.len() > 0;
    },
    Err(e) => { return false; },
  }
  return false;
}

/// Validity check by alpha-3 code.
/// Returns: true iff geog_country_by_alpha3 accepts `code`.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn geog_country_is_valid_alpha3(code: Str) -> Bool {
  match geog_country_by_alpha3(code) {
    Ok(c) => {
      let a = c.alpha3;
      return a.len() > 0;
    },
    Err(e) => { return false; },
  }
  return false;
}

/// Validity check by numeric code (1..3 digits, zero-padded on the left).
/// Returns: true iff geog_country_by_numeric accepts `code`.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn geog_country_is_valid_numeric(code: Str) -> Bool {
  match geog_country_by_numeric(code) {
    Ok(c) => {
      let a = c.numeric;
      return a.len() > 0;
    },
    Err(e) => { return false; },
  }
  return false;
}

/// Alpha-2 field of a country row.
pub fn geog_country_alpha2(c: &Country) -> Str {
  return c.alpha2;
}

/// Alpha-3 field of a country row.
pub fn geog_country_alpha3(c: &Country) -> Str {
  return c.alpha3;
}

/// Numeric field of a country row (zero-padded three digits).
pub fn geog_country_numeric(c: &Country) -> Str {
  return c.numeric;
}

/// English short name field of a country row.
pub fn geog_country_name(c: &Country) -> Str {
  return c.name;
}

/// UN M49 top-level continent code field of a country row (one of 002, 009,
/// 010, 019, 142, 150).
pub fn geog_country_continent(c: &Country) -> Str {
  return c.continent;
}

/// Finest UN M49 region code field of a country row (resolvable with
/// geog_region_by_code).
pub fn geog_country_region(c: &Country) -> Str {
  return c.region;
}

// Resolve a country by any of the three key kinds, alpha-2 first, then
// alpha-3, then numeric; the past-the-end sentinel when nothing matches.
fn _country_by_any(code: Str) -> Country {
  if _is_alpha2(code) {
    let i2 = _find_alpha2(code);
    if i2 >= 0 { return _country(i2); }
  }
  if _is_alpha3(code) {
    let i3 = _find_alpha3(code);
    if i3 >= 0 { return _country(i3); }
  }
  if _is_numeric13(code) {
    let inum = _find_numeric(_pad_numeric(code));
    if inum >= 0 { return _country(inum); }
  }
  return _missing_country();
}

/// Reverse accessor: English short name by any country key.
/// Params: code - alpha-2, alpha-3 (either case) or 1..3 numeric digits.
/// Returns: Ok(name); Err("geography: unknown country code: <code>") for a
/// malformed or unknown key (the three key spaces are disjoint, so the first
/// match is the only match).
/// Error case: see above.
/// Complexity: O(1) (bounded scans).
pub fn geog_country_name_by_code(code: Str) -> Result[Str, Str] {
  let c = _country_by_any(code);
  let a = c.alpha2;
  if a.len() == 0 {
    return _geo_err_str("geography: unknown country code: " + code);
  }
  return _geo_ok_str(c.name);
}

/// Reverse accessor: UN M49 top-level continent code by any country key.
/// Params / errors: as geog_country_name_by_code.
/// Returns: Ok(continent code).
/// Complexity: O(1) (bounded scans).
pub fn geog_country_continent_by_code(code: Str) -> Result[Str, Str] {
  let c = _country_by_any(code);
  let a = c.alpha2;
  if a.len() == 0 {
    return _geo_err_str("geography: unknown country code: " + code);
  }
  return _geo_ok_str(c.continent);
}

/// Reverse accessor: finest UN M49 region code by any country key.
/// Params / errors: as geog_country_name_by_code.
/// Returns: Ok(region code).
/// Complexity: O(1) (bounded scans).
pub fn geog_country_region_by_code(code: Str) -> Result[Str, Str] {
  let c = _country_by_any(code);
  let a = c.alpha2;
  if a.len() == 0 {
    return _geo_err_str("geography: unknown country code: " + code);
  }
  return _geo_ok_str(c.region);
}

// ---------------------------------------------------------------------------
//  Public API -- UN M49 region table
// ---------------------------------------------------------------------------

/// Number of rows in the embedded UN M49 region table.
/// Returns: 30 (the six top-level regions, the subregions of SPEC.md, and
/// 010 Antarctica).
/// Error case: none.
/// Complexity: O(1).
pub fn geog_region_count() -> Int {
  return _GEO_REGION_COUNT;
}

/// Region row by index, in ascending numeric-code order.
/// Params: index - 0 .. geog_region_count()-1.
/// Returns: Ok(Region); Err("geography: index out of range: <index>")
/// otherwise.
/// Error case: see above.
/// Complexity: O(1).
pub fn geog_region_at(index: Int) -> Result[Region, Str] {
  if index < 0 {
    return _geor_err("geography: index out of range: " + convert.int_to_string(index));
  }
  if index >= _GEO_REGION_COUNT {
    return _geor_err("geography: index out of range: " + convert.int_to_string(index));
  }
  let r = _region(index);
  let c = r.code;
  if c.len() == 0 {
    return _geor_err("geography: index out of range: " + convert.int_to_string(index));
  }
  return _geor_ok(r);
}

/// Look up a region by its zero-padded three-digit M49 code.
/// Params: code - exactly three ASCII digits ("002", "039", "150").
/// Returns: Ok(Region); Err("geography: bad region code: <code>") for any
/// other shape, or Err("geography: unknown region code: <code>") when no row
/// carries the code.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 30 rows).
pub fn geog_region_by_code(code: Str) -> Result[Region, Str] {
  if !_is_numeric3(code) {
    return _geor_err("geography: bad region code: " + code);
  }
  let idx = _find_region(code);
  if idx < 0 {
    return _geor_err("geography: unknown region code: " + code);
  }
  let r = _region(idx);
  let c = r.code;
  if c.len() == 0 {
    return _geor_err("geography: unknown region code: " + code);
  }
  return _geor_ok(r);
}

/// Validity check by region code.
/// Returns: true iff geog_region_by_code accepts `code`.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn geog_region_is_valid(code: Str) -> Bool {
  match geog_region_by_code(code) {
    Ok(r) => {
      let c = r.code;
      return c.len() > 0;
    },
    Err(e) => { return false; },
  }
  return false;
}

/// Code field of a region row.
pub fn geog_region_code(r: &Region) -> Str {
  return r.code;
}

/// Name field of a region row.
pub fn geog_region_name(r: &Region) -> Str {
  return r.name;
}

/// Parent code field of a region row ("" for a top-level region).
pub fn geog_region_parent(r: &Region) -> Str {
  return r.parent;
}

/// Reverse accessor: region name by region code.
/// Params: code - as for geog_region_by_code.
/// Returns: Ok(name); Err("geography: bad region code: <code>") for a
/// malformed shape, or Err("geography: unknown region code: <code>").
/// Error case: see above.
/// Complexity: O(1).
pub fn geog_region_name_by_code(code: Str) -> Result[Str, Str] {
  match geog_region_by_code(code) {
    Ok(r) => { return _geo_ok_str(r.name); },
    Err(e) => { return _geo_err_str(e); },
  }
  return _geo_err_str("geography: unknown region code: " + code);
}

/// Reverse accessor: parent code by region code.
/// Params / errors: as geog_region_name_by_code.
/// Returns: Ok(parent code); the empty string for a top-level region.
/// Complexity: O(1).
pub fn geog_region_parent_by_code(code: Str) -> Result[Str, Str] {
  match geog_region_by_code(code) {
    Ok(r) => { return _geo_ok_str(r.parent); },
    Err(e) => { return _geo_err_str(e); },
  }
  return _geo_err_str("geography: unknown region code: " + code);
}

// ---------------------------------------------------------------------------
//  Public API -- ISO 3166-2 subdivision syntax
// ---------------------------------------------------------------------------
//
// This is the syntax layer only: "CC-SUB" is a two-letter country part, one
// hyphen and a one-to-three alphanumeric subdivision part. The module does
// NOT embed the per-country ISO 3166-2 subdivision list (that is thousands of
// rows and changes several times a year); it checks the shape and preserves
// the raw text. Whether the country part is a real ISO 3166-1 code can be
// checked separately with geog_country_is_valid_alpha2, and whether the
// subdivision part exists for that country is out of scope.

/// Parse an ISO 3166-2 subdivision code reference.
/// Params: text - "CC-SUB": two ASCII letters, "-", then one to three ASCII
/// alphanumeric characters (e.g. "GR-A", "GR-69", "US-CA", "GB-ENG").
/// Returns: Ok(Subdivision) with the country and subdivision parts
/// normalized to uppercase and `raw` preserved verbatim; errors carry byte
/// offsets: "empty subdivision", "subdivision too short at byte 0" (fewer
/// than four bytes), "bad country letter at byte 0/1", "missing hyphen at
/// byte 2", "bad subdivision length at byte 3" (outside 1..3 bytes), "bad
/// subdivision character at byte <n>".
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn geog_subdivision_parse(text: Str) -> Result[Subdivision, Str] {
  let n = text.len();
  if n == 0 {
    return _geos_err("geography: empty subdivision");
  }
  if n < 4 {
    return _geos_err("geography: subdivision too short at byte 0");
  }
  let b0 = _byte_at(text, 0);
  if !_is_alpha_i(b0) {
    return _geos_err("geography: bad country letter at byte 0");
  }
  let b1 = _byte_at(text, 1);
  if !_is_alpha_i(b1) {
    return _geos_err("geography: bad country letter at byte 1");
  }
  let b2 = _byte_at(text, 2);
  if b2 != _GEO_HYPHEN {
    return _geos_err("geography: missing hyphen at byte 2");
  }
  let plen = n - 3;
  if plen > 3 {
    return _geos_err("geography: bad subdivision length at byte 3");
  }
  var i = 3;
  while i < n {
    if !_is_alnum_i(_byte_at(text, i)) {
      return _geos_err("geography: bad subdivision character at byte " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  let cc = _ascii_upper(string.str_slice(text, 0, 2));
  let part = _ascii_upper(string.str_slice(text, 3, n));
  let out = Subdivision{ country: cc; part: part; raw: text };
  return _geos_ok(out);
}

/// Format and validate the pieces of an ISO 3166-2 subdivision code.
/// Params: country - two ASCII letters (any case); part - one to three ASCII
/// alphanumeric characters (any case).
/// Returns: Ok("CC-SUB") in canonical uppercase; Err("geography: bad country
/// code: <country>") or Err("geography: bad subdivision part: <part>").
/// Error case: see above.
/// Complexity: O(len(country) + len(part)).
pub fn geog_subdivision_format(country: Str, part: Str) -> Result[Str, Str] {
  if !_is_alpha2(country) {
    return _geo_err_str("geography: bad country code: " + country);
  }
  let pn = part.len();
  if pn < 1 {
    return _geo_err_str("geography: bad subdivision part: " + part);
  }
  if pn > 3 {
    return _geo_err_str("geography: bad subdivision part: " + part);
  }
  var i = 0;
  while i < pn {
    if !_is_alnum_i(_byte_at(part, i)) {
      return _geo_err_str("geography: bad subdivision part: " + part);
    }
    i = i + 1;
  }
  return _geo_ok_str(_ascii_upper(country) + "-" + _ascii_upper(part));
}

/// Validity check for ISO 3166-2 subdivision syntax.
/// Returns: true iff geog_subdivision_parse accepts `text`.
/// Error case: none (errors collapse to false).
/// Complexity: O(len(text)).
pub fn geog_subdivision_is_valid(text: Str) -> Bool {
  match geog_subdivision_parse(text) {
    Ok(s) => {
      let c = s.country;
      return c.len() > 0;
    },
    Err(e) => { return false; },
  }
  return false;
}

/// Country part of a parsed subdivision reference (canonical uppercase).
pub fn geog_subdivision_country(s: &Subdivision) -> Str {
  return s.country;
}

/// Subdivision part of a parsed subdivision reference (canonical uppercase).
pub fn geog_subdivision_part(s: &Subdivision) -> Str {
  return s.part;
}

/// Raw input text of a parsed subdivision reference.
pub fn geog_subdivision_raw(s: &Subdivision) -> Str {
  return s.raw;
}

/// Canonical "CC-SUB" text of a parsed subdivision reference.
pub fn geog_subdivision_canonical(s: &Subdivision) -> Str {
  let cc = s.country;
  let p = s.part;
  return cc + "-" + p;
}

// ---------------------------------------------------------------------------
//  Public API -- coordinate text
// ---------------------------------------------------------------------------
//
// Coordinates are scaled integer micro-degrees (1e-6 degree). The axis is a
// caller-supplied Bool: true = latitude [-90000000, 90000000], false =
// longitude [-180000000, 180000000].

// Length of a degree symbol at `i` (1 or 2 bytes: "d"/"D", degree sign or
// masculine ordinal), 0 when absent.
fn _match_degree_symbol(text: Str, i: Int) -> Int {
  if i >= text.len() { return 0; }
  let b = _byte_at(text, i);
  if b == _GEO_LOWER_D || b == _GEO_UPPER_D { return 1; }
  if b == _GEO_UTF8_C2 && i + 1 < text.len() {
    let b2 = _byte_at(text, i + 1);
    if b2 == _GEO_UTF8_DEGREE || b2 == _GEO_UTF8_MASC { return 2; }
  }
  return 0;
}

// Length of a minute symbol at `i` (1 or 3 bytes: apostrophe, "m"/"M" or
// prime), 0 when absent.
fn _match_minute_symbol(text: Str, i: Int) -> Int {
  if i >= text.len() { return 0; }
  let b = _byte_at(text, i);
  if b == 39 { return 1; }
  if b == _GEO_LOWER_M || b == _GEO_UPPER_M { return 1; }
  if b == _GEO_UTF8_E2 && i + 2 < text.len() {
    let b1 = _byte_at(text, i + 1);
    let b2 = _byte_at(text, i + 2);
    if b1 == _GEO_UTF8_B1 && b2 == _GEO_UTF8_PRIME { return 3; }
  }
  return 0;
}

// Length of a second symbol at `i` (1 or 3 bytes: double quote or double
// prime), 0 when absent. "s"/"S" is deliberately NOT accepted here: it would
// make a bare trailing "S" (south) ambiguous with a second symbol.
fn _match_second_symbol(text: Str, i: Int) -> Int {
  if i >= text.len() { return 0; }
  let b = _byte_at(text, i);
  if b == 34 { return 1; }
  if b == _GEO_UTF8_E2 && i + 2 < text.len() {
    let b1 = _byte_at(text, i + 1);
    let b2 = _byte_at(text, i + 2);
    if b1 == _GEO_UTF8_B1 && b2 == _GEO_UTF8_DPRIME { return 3; }
  }
  return 0;
}

// Hemisphere code of the byte at `at`: 1 north/east, -1 south/west, 0 not a
// hemisphere letter, -2 a hemisphere letter but for the other axis.
fn _hemi_sign(text: Str, at: Int, lat: Bool) -> Int {
  if at < 0 { return 0; }
  if at >= text.len() { return 0; }
  let b = _upper_i(_byte_at(text, at));
  if b == _GEO_UPPER_N {
    if lat { return 1; }
    return 0 - 2;
  }
  if b == _GEO_UPPER_S {
    if lat { return 0 - 1; }
    return 0 - 2;
  }
  if b == _GEO_UPPER_E {
    if lat { return 0 - 2; }
    return 1;
  }
  if b == _GEO_UPPER_W {
    if lat { return 0 - 2; }
    return 0 - 1;
  }
  return 0;
}

// Apply a parsed sign/hemisphere pair to a magnitude; Err carries the byte
// offset of the hemisphere letter.
fn _apply_hemi_sign(mag: Int, sign: Int, hemi: Int, hemi_at: Int) -> Result[Int, Str] {
  if sign == 1 && hemi == 0 - 1 {
    return _geo_err_int("geography: hemisphere conflicts with sign at byte " + convert.int_to_string(hemi_at));
  }
  if sign == 0 - 1 && hemi == 1 {
    return _geo_err_int("geography: hemisphere conflicts with sign at byte " + convert.int_to_string(hemi_at));
  }
  var neg = false;
  if sign == 0 - 1 { neg = true; }
  if hemi == 0 - 1 { neg = true; }
  if neg && mag != 0 {
    return _geo_ok_int(0 - mag);
  }
  return _geo_ok_int(mag);
}

/// Parse decimal-degree text into micro-degrees.
/// Params: text - "[H]?[+|-]?DD[.FFFF[FF]]H?" where H is N, S, E or W (either
/// case, at most once, at the start or end), DD is one to three ASCII digits,
/// and the optional fraction has at most six digits (a seventh is an error).
/// lat - true selects the latitude axis (N/S only), false longitude (E/W
/// only); the opposite hemisphere letters are errors.
/// Returns: Ok(micro-degrees); the exact error catalog of SPEC.md, e.g.
/// "geography: empty input", "missing digits at byte <n>", "bad hemisphere at
/// byte <n>", "wrong hemisphere for axis at byte <n>", "duplicate hemisphere
/// at byte <n>", "too many degree digits at byte <n>", "too many fraction
/// digits at byte <n>", "missing fraction digits at byte <n>", "unexpected
/// character at byte <n>", "hemisphere conflicts with sign at byte <n>",
/// "latitude out of range at byte <n>", "longitude out of range at byte <n>"
/// (out-of-range offsets point just past the parsed text).
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn geog_coord_parse_decimal(text: Str, lat: Bool) -> Result[Int, Str] {
  let n = text.len();
  if n == 0 {
    return _geo_err_int("geography: empty input");
  }
  var i = 0;
  var hemi = 0;
  var hemi_at = 0;
  if _is_alpha_i(_byte_at(text, 0)) {
    let h0 = _hemi_sign(text, 0, lat);
    if h0 == 0 {
      return _geo_err_int("geography: bad hemisphere at byte 0");
    }
    if h0 == 0 - 2 {
      return _geo_err_int("geography: wrong hemisphere for axis at byte 0");
    }
    hemi = h0;
    hemi_at = 0;
    i = 1;
  }
  var sign = 0;
  if i < n {
    let bs = _byte_at(text, i);
    if bs == _GEO_PLUS {
      sign = 1;
      i = i + 1;
    } elif bs == _GEO_MINUS {
      sign = 0 - 1;
      i = i + 1;
    }
  }
  var deg = 0;
  var ddigits = 0;
  while i < n && _is_digit_i(_byte_at(text, i)) {
    deg = deg * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
    ddigits = ddigits + 1;
    i = i + 1;
  }
  if ddigits == 0 {
    return _geo_err_int("geography: missing digits at byte " + convert.int_to_string(i));
  }
  if ddigits > 3 {
    return _geo_err_int("geography: too many degree digits at byte " + convert.int_to_string(i - 1));
  }
  var frac = 0;
  var fdigits = 0;
  if i < n && _byte_at(text, i) == _GEO_DOT {
    i = i + 1;
    while i < n && _is_digit_i(_byte_at(text, i)) {
      if fdigits >= 6 {
        return _geo_err_int("geography: too many fraction digits at byte " + convert.int_to_string(i));
      }
      frac = frac * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
      fdigits = fdigits + 1;
      i = i + 1;
    }
    if fdigits == 0 {
      return _geo_err_int("geography: missing fraction digits at byte " + convert.int_to_string(i));
    }
  }
  if i < n {
    if _is_alpha_i(_byte_at(text, i)) {
      if hemi != 0 {
        return _geo_err_int("geography: duplicate hemisphere at byte " + convert.int_to_string(i));
      }
      let ht = _hemi_sign(text, i, lat);
      if ht == 0 {
        return _geo_err_int("geography: bad hemisphere at byte " + convert.int_to_string(i));
      }
      if ht == 0 - 2 {
        return _geo_err_int("geography: wrong hemisphere for axis at byte " + convert.int_to_string(i));
      }
      hemi = ht;
      hemi_at = i;
      i = i + 1;
    }
  }
  if i < n {
    return _geo_err_int("geography: unexpected character at byte " + convert.int_to_string(i));
  }
  let num_end = i;
  var micro = deg * _GEO_MICRO;
  var k = fdigits;
  while k < 6 {
    frac = frac * 10;
    k = k + 1;
  }
  micro = micro + frac;
  if lat {
    if micro > _GEO_LAT_MAX {
      return _geo_err_int("geography: latitude out of range at byte " + convert.int_to_string(num_end));
    }
  } else {
    if micro > _GEO_LON_MAX {
      return _geo_err_int("geography: longitude out of range at byte " + convert.int_to_string(num_end));
    }
  }
  return _apply_hemi_sign(micro, sign, hemi, hemi_at);
}

/// Parse sexagesimal DMS text into micro-degrees.
/// Params: text - "[H]?DD<deg>MM<min>SS[.FFFF[FF]]<sec>H?" where DD is one to
/// three ASCII digits, MM and SS one or two digits, the seconds fraction has
/// at most six digits, and the symbols are: degree "°", "º", "d" or "D";
/// minute "'", "m" or "M"; second "\"" or the double prime (U+2033). "s" is
/// not a second symbol (see _match_second_symbol). H is N, S, E or W (either
/// case) at the start or end; lat selects the axis as for
/// geog_coord_parse_decimal.
/// Returns: Ok(micro-degrees), truncating the seconds fraction below one
/// micro-degree (canonical render is exact); errors carry byte offsets:
/// "empty input", "missing degree digits", "too many degree digits",
/// "missing degree symbol", "missing minute digits", "too many minute
/// digits", "minutes out of range", "missing minute symbol", "missing second
/// digits", "too many second digits", "seconds out of range", "missing second
/// symbol", the hemisphere catalog, the fraction catalog, and
/// "latitude/longitude out of range" (bounds: minutes and seconds below 60,
/// latitude at most 90 degrees, longitude at most 180 degrees).
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn geog_coord_parse_dms(text: Str, lat: Bool) -> Result[Int, Str] {
  let n = text.len();
  if n == 0 {
    return _geo_err_int("geography: empty input");
  }
  var i = 0;
  var hemi = 0;
  var hemi_at = 0;
  if _is_alpha_i(_byte_at(text, 0)) {
    let h0 = _hemi_sign(text, 0, lat);
    if h0 == 0 {
      return _geo_err_int("geography: bad hemisphere at byte 0");
    }
    if h0 == 0 - 2 {
      return _geo_err_int("geography: wrong hemisphere for axis at byte 0");
    }
    hemi = h0;
    hemi_at = 0;
    i = 1;
  }
  var deg = 0;
  var ddigits = 0;
  while i < n && _is_digit_i(_byte_at(text, i)) {
    deg = deg * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
    ddigits = ddigits + 1;
    i = i + 1;
  }
  if ddigits == 0 {
    return _geo_err_int("geography: missing degree digits at byte " + convert.int_to_string(i));
  }
  if ddigits > 3 {
    return _geo_err_int("geography: too many degree digits at byte " + convert.int_to_string(i - 1));
  }
  let dlen = _match_degree_symbol(text, i);
  if dlen == 0 {
    return _geo_err_int("geography: missing degree symbol at byte " + convert.int_to_string(i));
  }
  i = i + dlen;
  var min = 0;
  var mdigits = 0;
  let m_start = i;
  while i < n && _is_digit_i(_byte_at(text, i)) {
    min = min * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
    mdigits = mdigits + 1;
    i = i + 1;
  }
  if mdigits == 0 {
    return _geo_err_int("geography: missing minute digits at byte " + convert.int_to_string(i));
  }
  if mdigits > 2 {
    return _geo_err_int("geography: too many minute digits at byte " + convert.int_to_string(i - 1));
  }
  if min > 59 {
    return _geo_err_int("geography: minutes out of range at byte " + convert.int_to_string(m_start));
  }
  let mlen = _match_minute_symbol(text, i);
  if mlen == 0 {
    return _geo_err_int("geography: missing minute symbol at byte " + convert.int_to_string(i));
  }
  i = i + mlen;
  var sec = 0;
  var sdigits = 0;
  let s_start = i;
  while i < n && _is_digit_i(_byte_at(text, i)) {
    sec = sec * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
    sdigits = sdigits + 1;
    i = i + 1;
  }
  if sdigits == 0 {
    return _geo_err_int("geography: missing second digits at byte " + convert.int_to_string(i));
  }
  if sdigits > 2 {
    return _geo_err_int("geography: too many second digits at byte " + convert.int_to_string(i - 1));
  }
  var sfrac = 0;
  var sfdigits = 0;
  if i < n && _byte_at(text, i) == _GEO_DOT {
    i = i + 1;
    while i < n && _is_digit_i(_byte_at(text, i)) {
      if sfdigits >= 6 {
        return _geo_err_int("geography: too many fraction digits at byte " + convert.int_to_string(i));
      }
      sfrac = sfrac * 10 + (_byte_at(text, i) - _GEO_DIGIT_0);
      sfdigits = sfdigits + 1;
      i = i + 1;
    }
    if sfdigits == 0 {
      return _geo_err_int("geography: missing fraction digits at byte " + convert.int_to_string(i));
    }
  }
  if sec > 59 {
    return _geo_err_int("geography: seconds out of range at byte " + convert.int_to_string(s_start));
  }
  let slen = _match_second_symbol(text, i);
  if slen == 0 {
    return _geo_err_int("geography: missing second symbol at byte " + convert.int_to_string(i));
  }
  i = i + slen;
  if i < n {
    if _is_alpha_i(_byte_at(text, i)) {
      if hemi != 0 {
        return _geo_err_int("geography: duplicate hemisphere at byte " + convert.int_to_string(i));
      }
      let ht = _hemi_sign(text, i, lat);
      if ht == 0 {
        return _geo_err_int("geography: bad hemisphere at byte " + convert.int_to_string(i));
      }
      if ht == 0 - 2 {
        return _geo_err_int("geography: wrong hemisphere for axis at byte " + convert.int_to_string(i));
      }
      hemi = ht;
      hemi_at = i;
      i = i + 1;
    }
  }
  if i < n {
    return _geo_err_int("geography: unexpected character at byte " + convert.int_to_string(i));
  }
  let num_end = i;
  var k = sfdigits;
  while k < 6 {
    sfrac = sfrac * 10;
    k = k + 1;
  }
  let total_us = ((deg * 60 + min) * 60 + sec) * _GEO_MICRO + sfrac;
  if lat {
    if total_us > _GEO_LAT_MAX_US {
      return _geo_err_int("geography: latitude out of range at byte " + convert.int_to_string(num_end));
    }
  } else {
    if total_us > _GEO_LON_MAX_US {
      return _geo_err_int("geography: longitude out of range at byte " + convert.int_to_string(num_end));
    }
  }
  let micro = total_us / _GEO_SECONDS_PER_DEGREE;
  return _apply_hemi_sign(micro, 0, hemi, hemi_at);
}

/// Canonical decimal-degree text of a micro-degree value.
/// Params: micro - scaled micro-degrees (any Int value; no range check here,
/// see geog_coord_in_range).
/// Returns: the signed fixed-six-decimal text: "37.975000", "-37.975000",
/// "0.000000". Zero never renders as "-0.000000".
/// Error case: none.
/// Complexity: O(digits).
pub fn geog_coord_format_decimal(micro: Int) -> Str {
  var mag = micro;
  var neg = false;
  if micro < 0 {
    neg = true;
    mag = 0 - micro;
  }
  let d = mag / _GEO_MICRO;
  let frac = mag % _GEO_MICRO;
  var out = convert.int_to_string(d) + "." + _pad6(frac);
  if neg {
    out = "-" + out;
  }
  return out;
}

/// Canonical DMS text of a micro-degree value.
/// Params: micro - scaled micro-degrees (any Int value; no range check here);
/// lat - true renders an N/S hemisphere, false an E/W one.
/// Returns: "DD deg MM'SS.FFFFFF\"H" with one-to-three degree digits,
/// two-digit minutes and seconds, exactly six second fraction digits and a
/// trailing uppercase hemisphere: "37°58'30.000000\"N". Zero renders N (lat)
/// or E (lon). The render is exact: geog_coord_parse_dms of the output
/// reproduces `micro` for every value.
/// Error case: none.
/// Complexity: O(digits).
pub fn geog_coord_format_dms(micro: Int, lat: Bool) -> Str {
  var mag = micro;
  var neg = false;
  if micro < 0 {
    neg = true;
    mag = 0 - micro;
  }
  let d = mag / _GEO_MICRO;
  let r1 = mag % _GEO_MICRO;
  let min = r1 * 60 / _GEO_MICRO;
  let r2 = (r1 * 60) % _GEO_MICRO;
  let sec_us = r2 * 60;
  let sec = sec_us / _GEO_MICRO;
  let sfrac = sec_us % _GEO_MICRO;
  var hemi = "N";
  if lat {
    if neg {
      hemi = "S";
    }
  } else {
    if neg {
      hemi = "W";
    } else {
      hemi = "E";
    }
  }
  return convert.int_to_string(d) + "°" + _pad2(min) + "'" + _pad2(sec) + "." + _pad6(sfrac) + "\"" + hemi;
}

/// Range predicate for scaled micro-degree values.
/// Params: micro - candidate; lat - true checks [-90000000, 90000000], false
/// checks [-180000000, 180000000].
/// Returns: true iff `micro` is inside the axis interval (inclusive).
/// Error case: none.
/// Complexity: O(1).
pub fn geog_coord_in_range(micro: Int, lat: Bool) -> Bool {
  if lat {
    if micro < 0 - _GEO_LAT_MAX { return false; }
    return micro <= _GEO_LAT_MAX;
  }
  if micro < 0 - _GEO_LON_MAX { return false; }
  return micro <= _GEO_LON_MAX;
}
