// XIOM -- xiom.l10n.phone: E.164 / international phone number structures
// over an embedded ITU-T E.164 country calling-code subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: phone_parse accepts an international-form number in three surface
// shapes -- optional '+', optional '00' international prefix, or a bare
// digit string whose leading 1..3 digits are an E.164 country calling code
// from the embedded table. Separators (space, hyphen, dot, parentheses) are
// stripped and every digit keeps its input byte offset; extensions are
// recognized after 'x', 'ext' or ';ext='; every error carries the byte
// offset of the offending input byte.
//
// Out of scope: national-format input (trunk prefixes such as a leading 0),
// per-prefix dial-plan rules, carrier selection, short codes, and numbering
// data beyond the (code, ISO 3166-1 alpha-2, minimum national length) triple
// in the embedded table (see SPEC.md).
//
// Compiler discipline (v0.61.3): free functions only; no Str ==; typed
// Vec[Int] reads; Ok/Err constructed only in leaf helpers; UInt8 constants
// stay below 128; no Vec[StructType]; the only Vec is the parallel
// digit_offsets array, pushed in the same branch that appends the digit.

module xiom.l10n.phone

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _PN_PLUS: UInt8 = 43u8;
const _PN_SPACE: UInt8 = 32u8;
const _PN_LPAREN: UInt8 = 40u8;
const _PN_RPAREN: UInt8 = 41u8;
const _PN_HYPHEN: UInt8 = 45u8;
const _PN_DOT: UInt8 = 46u8;
const _PN_SEMI: UInt8 = 59u8;
const _PN_ZERO: UInt8 = 48u8;
const _PN_NINE: UInt8 = 57u8;
const _PN_UPPER_A: UInt8 = 65u8;
const _PN_UPPER_E: UInt8 = 69u8;
const _PN_UPPER_X: UInt8 = 88u8;
const _PN_UPPER_Z: UInt8 = 90u8;
const _PN_LOWER_E: UInt8 = 101u8;
const _PN_LOWER_X: UInt8 = 120u8;
const _PN_DIG2: UInt8 = 50u8;
const _PN_DIG3: UInt8 = 51u8;
const _PN_DIG4: UInt8 = 52u8;
const _PN_DIG5: UInt8 = 53u8;
const _PN_DIG6: UInt8 = 54u8;
const _PN_DIG8: UInt8 = 56u8;
const _PN_MAX_DIGITS: Int = 15;
const _PN_COUNTRY_COUNT: Int = 200;

/// One embedded E.164 calling-code row: the code digits, the ISO 3166-1
/// alpha-2 code of the code's primary country, and the documented minimum
/// national significant number length (a conservative floor; see SPEC.md).
pub type CallingCode = {
  code: Str;
  iso: Str;
  min_len: Int;
}

/// A parsed international phone number. `national` holds the national
/// significant digits with every separator stripped; `extension` is "" when
/// no extension marker was present; `digit_offsets[i]` is the input byte
/// offset of the i-th digit of country_code + national, so every stripped
/// digit can be mapped back to the source text. The offset array is parallel
/// to country_code + national and never covers extension digits.
pub type PhoneNumber = {
  country_code: Str;
  iso: Str;
  national: Str;
  extension: Str;
  digit_offsets: Vec[Int];
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _pn_ok(v: PhoneNumber) -> Result[PhoneNumber, Str] { return Ok(v); }
fn _pn_err(m: Str) -> Result[PhoneNumber, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character helpers
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _PN_ZERO && b <= _PN_NINE;
}

// Separators stripped anywhere after the international prefix.
fn _is_separator(b: UInt8) -> Bool {
  if b == _PN_SPACE { return true; }
  if b == _PN_LPAREN { return true; }
  if b == _PN_RPAREN { return true; }
  if b == _PN_HYPHEN { return true; }
  if b == _PN_DOT { return true; }
  return false;
}

// ASCII lowercase of one byte; non-letters pass through unchanged.
fn _lower_byte(b: UInt8) -> UInt8 {
  if b >= _PN_UPPER_A && b <= _PN_UPPER_Z { return b + 32u8; }
  return b;
}

// True when the case-insensitive ASCII text `sub` occurs in `text` at `at`.
fn _matches_ci_at(text: Str, at: Int, sub: Str) -> Bool {
  if at < 0 { return false; }
  if at + sub.len() > text.len() { return false; }
  var i = 0;
  while i < sub.len() {
    let x = string.byte_at(text, at + i);
    let y = string.byte_at(sub, i);
    if _lower_byte(x) != _lower_byte(y) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Embedded E.164 country calling-code table (see SPEC.md)
// ---------------------------------------------------------------------------
//
// Rows are one-line if-chains in ascending code order split by leading digit
// (module-level table initializers are mis-materialized by v0.61.3, so the
// rows compile into comparison chains, as in xiom.iban). `min_len` is the
// documented conservative minimum national significant number length; rows
// whose plan minimum could not be confidently pinned carry the default 4.

fn _mk_cc(code: Str, iso: Str, min_len: Int) -> CallingCode {
  let v = CallingCode{ code: code; iso: iso; min_len: min_len };
  return v;
}

fn _cc_missing() -> CallingCode {
  return _mk_cc("", "", 0);
}

// One-digit codes: 1 (NANP), 7 (RU/KZ).
fn _code1(c: Str) -> CallingCode {
  if compare.str_compare(c, "1") == 0 { return _mk_cc("1", "US", 10); }
  if compare.str_compare(c, "7") == 0 { return _mk_cc("7", "RU", 10); }
  return _cc_missing();
}

// Two-digit codes.
fn _code2(c: Str) -> CallingCode {
  if compare.str_compare(c, "20") == 0 { return _mk_cc("20", "EG", 9); }
  if compare.str_compare(c, "27") == 0 { return _mk_cc("27", "ZA", 9); }
  if compare.str_compare(c, "30") == 0 { return _mk_cc("30", "GR", 10); }
  if compare.str_compare(c, "31") == 0 { return _mk_cc("31", "NL", 9); }
  if compare.str_compare(c, "32") == 0 { return _mk_cc("32", "BE", 8); }
  if compare.str_compare(c, "33") == 0 { return _mk_cc("33", "FR", 9); }
  if compare.str_compare(c, "34") == 0 { return _mk_cc("34", "ES", 9); }
  if compare.str_compare(c, "36") == 0 { return _mk_cc("36", "HU", 9); }
  if compare.str_compare(c, "39") == 0 { return _mk_cc("39", "IT", 9); }
  if compare.str_compare(c, "40") == 0 { return _mk_cc("40", "RO", 9); }
  if compare.str_compare(c, "41") == 0 { return _mk_cc("41", "CH", 9); }
  if compare.str_compare(c, "43") == 0 { return _mk_cc("43", "AT", 10); }
  if compare.str_compare(c, "44") == 0 { return _mk_cc("44", "GB", 10); }
  if compare.str_compare(c, "45") == 0 { return _mk_cc("45", "DK", 8); }
  if compare.str_compare(c, "46") == 0 { return _mk_cc("46", "SE", 7); }
  if compare.str_compare(c, "47") == 0 { return _mk_cc("47", "NO", 8); }
  if compare.str_compare(c, "48") == 0 { return _mk_cc("48", "PL", 9); }
  if compare.str_compare(c, "49") == 0 { return _mk_cc("49", "DE", 9); }
  if compare.str_compare(c, "51") == 0 { return _mk_cc("51", "PE", 8); }
  if compare.str_compare(c, "52") == 0 { return _mk_cc("52", "MX", 10); }
  if compare.str_compare(c, "53") == 0 { return _mk_cc("53", "CU", 8); }
  if compare.str_compare(c, "54") == 0 { return _mk_cc("54", "AR", 10); }
  if compare.str_compare(c, "55") == 0 { return _mk_cc("55", "BR", 10); }
  if compare.str_compare(c, "56") == 0 { return _mk_cc("56", "CL", 9); }
  if compare.str_compare(c, "57") == 0 { return _mk_cc("57", "CO", 10); }
  if compare.str_compare(c, "58") == 0 { return _mk_cc("58", "VE", 10); }
  if compare.str_compare(c, "60") == 0 { return _mk_cc("60", "MY", 9); }
  if compare.str_compare(c, "61") == 0 { return _mk_cc("61", "AU", 9); }
  if compare.str_compare(c, "62") == 0 { return _mk_cc("62", "ID", 9); }
  if compare.str_compare(c, "63") == 0 { return _mk_cc("63", "PH", 10); }
  if compare.str_compare(c, "64") == 0 { return _mk_cc("64", "NZ", 8); }
  if compare.str_compare(c, "65") == 0 { return _mk_cc("65", "SG", 8); }
  if compare.str_compare(c, "66") == 0 { return _mk_cc("66", "TH", 9); }
  if compare.str_compare(c, "81") == 0 { return _mk_cc("81", "JP", 9); }
  if compare.str_compare(c, "82") == 0 { return _mk_cc("82", "KR", 9); }
  if compare.str_compare(c, "84") == 0 { return _mk_cc("84", "VN", 9); }
  if compare.str_compare(c, "86") == 0 { return _mk_cc("86", "CN", 9); }
  if compare.str_compare(c, "90") == 0 { return _mk_cc("90", "TR", 10); }
  if compare.str_compare(c, "91") == 0 { return _mk_cc("91", "IN", 10); }
  if compare.str_compare(c, "92") == 0 { return _mk_cc("92", "PK", 10); }
  if compare.str_compare(c, "93") == 0 { return _mk_cc("93", "AF", 9); }
  if compare.str_compare(c, "94") == 0 { return _mk_cc("94", "LK", 9); }
  if compare.str_compare(c, "95") == 0 { return _mk_cc("95", "MM", 8); }
  if compare.str_compare(c, "98") == 0 { return _mk_cc("98", "IR", 10); }
  return _cc_missing();
}

// Three-digit codes: dispatcher on the leading digit.
fn _code3(c: Str) -> CallingCode {
  if c.len() != 3 { return _cc_missing(); }
  let b = string.byte_at(c, 0);
  if b == _PN_DIG2 { return _code3_2(c); }
  if b == _PN_DIG3 { return _code3_3(c); }
  if b == _PN_DIG4 { return _code3_4(c); }
  if b == _PN_DIG5 { return _code3_5(c); }
  if b == _PN_DIG6 { return _code3_6(c); }
  if b == _PN_DIG8 { return _code3_8(c); }
  if b == _PN_NINE { return _code3_9(c); }
  return _cc_missing();
}

// Africa (2xx).
fn _code3_2(c: Str) -> CallingCode {
  if compare.str_compare(c, "211") == 0 { return _mk_cc("211", "SS", 9); }
  if compare.str_compare(c, "212") == 0 { return _mk_cc("212", "MA", 9); }
  if compare.str_compare(c, "213") == 0 { return _mk_cc("213", "DZ", 9); }
  if compare.str_compare(c, "216") == 0 { return _mk_cc("216", "TN", 8); }
  if compare.str_compare(c, "218") == 0 { return _mk_cc("218", "LY", 9); }
  if compare.str_compare(c, "220") == 0 { return _mk_cc("220", "GM", 7); }
  if compare.str_compare(c, "221") == 0 { return _mk_cc("221", "SN", 9); }
  if compare.str_compare(c, "222") == 0 { return _mk_cc("222", "MR", 8); }
  if compare.str_compare(c, "223") == 0 { return _mk_cc("223", "ML", 8); }
  if compare.str_compare(c, "224") == 0 { return _mk_cc("224", "GN", 9); }
  if compare.str_compare(c, "225") == 0 { return _mk_cc("225", "CI", 8); }
  if compare.str_compare(c, "226") == 0 { return _mk_cc("226", "BF", 8); }
  if compare.str_compare(c, "227") == 0 { return _mk_cc("227", "NE", 8); }
  if compare.str_compare(c, "228") == 0 { return _mk_cc("228", "TG", 8); }
  if compare.str_compare(c, "229") == 0 { return _mk_cc("229", "BJ", 8); }
  if compare.str_compare(c, "230") == 0 { return _mk_cc("230", "MU", 7); }
  if compare.str_compare(c, "231") == 0 { return _mk_cc("231", "LR", 8); }
  if compare.str_compare(c, "232") == 0 { return _mk_cc("232", "SL", 8); }
  if compare.str_compare(c, "233") == 0 { return _mk_cc("233", "GH", 9); }
  if compare.str_compare(c, "234") == 0 { return _mk_cc("234", "NG", 10); }
  if compare.str_compare(c, "235") == 0 { return _mk_cc("235", "TD", 8); }
  if compare.str_compare(c, "236") == 0 { return _mk_cc("236", "CF", 8); }
  if compare.str_compare(c, "237") == 0 { return _mk_cc("237", "CM", 9); }
  if compare.str_compare(c, "238") == 0 { return _mk_cc("238", "CV", 7); }
  if compare.str_compare(c, "239") == 0 { return _mk_cc("239", "ST", 7); }
  if compare.str_compare(c, "240") == 0 { return _mk_cc("240", "GQ", 9); }
  if compare.str_compare(c, "241") == 0 { return _mk_cc("241", "GA", 8); }
  if compare.str_compare(c, "242") == 0 { return _mk_cc("242", "CG", 9); }
  if compare.str_compare(c, "243") == 0 { return _mk_cc("243", "CD", 9); }
  if compare.str_compare(c, "244") == 0 { return _mk_cc("244", "AO", 9); }
  if compare.str_compare(c, "245") == 0 { return _mk_cc("245", "GW", 7); }
  if compare.str_compare(c, "246") == 0 { return _mk_cc("246", "IO", 4); }
  if compare.str_compare(c, "248") == 0 { return _mk_cc("248", "SC", 7); }
  if compare.str_compare(c, "249") == 0 { return _mk_cc("249", "SD", 9); }
  if compare.str_compare(c, "250") == 0 { return _mk_cc("250", "RW", 9); }
  if compare.str_compare(c, "251") == 0 { return _mk_cc("251", "ET", 9); }
  if compare.str_compare(c, "252") == 0 { return _mk_cc("252", "SO", 8); }
  if compare.str_compare(c, "253") == 0 { return _mk_cc("253", "DJ", 8); }
  if compare.str_compare(c, "254") == 0 { return _mk_cc("254", "KE", 9); }
  if compare.str_compare(c, "255") == 0 { return _mk_cc("255", "TZ", 9); }
  if compare.str_compare(c, "256") == 0 { return _mk_cc("256", "UG", 9); }
  if compare.str_compare(c, "257") == 0 { return _mk_cc("257", "BI", 8); }
  if compare.str_compare(c, "258") == 0 { return _mk_cc("258", "MZ", 9); }
  if compare.str_compare(c, "260") == 0 { return _mk_cc("260", "ZM", 9); }
  if compare.str_compare(c, "261") == 0 { return _mk_cc("261", "MG", 9); }
  if compare.str_compare(c, "262") == 0 { return _mk_cc("262", "RE", 9); }
  if compare.str_compare(c, "263") == 0 { return _mk_cc("263", "ZW", 9); }
  if compare.str_compare(c, "264") == 0 { return _mk_cc("264", "NA", 9); }
  if compare.str_compare(c, "265") == 0 { return _mk_cc("265", "MW", 9); }
  if compare.str_compare(c, "266") == 0 { return _mk_cc("266", "LS", 8); }
  if compare.str_compare(c, "267") == 0 { return _mk_cc("267", "BW", 8); }
  if compare.str_compare(c, "268") == 0 { return _mk_cc("268", "SZ", 8); }
  if compare.str_compare(c, "269") == 0 { return _mk_cc("269", "KM", 7); }
  if compare.str_compare(c, "290") == 0 { return _mk_cc("290", "SH", 4); }
  if compare.str_compare(c, "291") == 0 { return _mk_cc("291", "ER", 7); }
  if compare.str_compare(c, "297") == 0 { return _mk_cc("297", "AW", 7); }
  if compare.str_compare(c, "298") == 0 { return _mk_cc("298", "FO", 6); }
  if compare.str_compare(c, "299") == 0 { return _mk_cc("299", "GL", 6); }
  return _cc_missing();
}

// Europe extras (3xx).
fn _code3_3(c: Str) -> CallingCode {
  if compare.str_compare(c, "350") == 0 { return _mk_cc("350", "GI", 8); }
  if compare.str_compare(c, "351") == 0 { return _mk_cc("351", "PT", 9); }
  if compare.str_compare(c, "352") == 0 { return _mk_cc("352", "LU", 8); }
  if compare.str_compare(c, "353") == 0 { return _mk_cc("353", "IE", 9); }
  if compare.str_compare(c, "354") == 0 { return _mk_cc("354", "IS", 7); }
  if compare.str_compare(c, "355") == 0 { return _mk_cc("355", "AL", 9); }
  if compare.str_compare(c, "356") == 0 { return _mk_cc("356", "MT", 8); }
  if compare.str_compare(c, "357") == 0 { return _mk_cc("357", "CY", 8); }
  if compare.str_compare(c, "358") == 0 { return _mk_cc("358", "FI", 9); }
  if compare.str_compare(c, "359") == 0 { return _mk_cc("359", "BG", 9); }
  if compare.str_compare(c, "370") == 0 { return _mk_cc("370", "LT", 8); }
  if compare.str_compare(c, "371") == 0 { return _mk_cc("371", "LV", 8); }
  if compare.str_compare(c, "372") == 0 { return _mk_cc("372", "EE", 7); }
  if compare.str_compare(c, "373") == 0 { return _mk_cc("373", "MD", 8); }
  if compare.str_compare(c, "374") == 0 { return _mk_cc("374", "AM", 8); }
  if compare.str_compare(c, "375") == 0 { return _mk_cc("375", "BY", 9); }
  if compare.str_compare(c, "376") == 0 { return _mk_cc("376", "AD", 6); }
  if compare.str_compare(c, "377") == 0 { return _mk_cc("377", "MC", 8); }
  if compare.str_compare(c, "378") == 0 { return _mk_cc("378", "SM", 9); }
  if compare.str_compare(c, "379") == 0 { return _mk_cc("379", "VA", 8); }
  if compare.str_compare(c, "380") == 0 { return _mk_cc("380", "UA", 9); }
  if compare.str_compare(c, "381") == 0 { return _mk_cc("381", "RS", 9); }
  if compare.str_compare(c, "382") == 0 { return _mk_cc("382", "ME", 8); }
  if compare.str_compare(c, "385") == 0 { return _mk_cc("385", "HR", 8); }
  if compare.str_compare(c, "386") == 0 { return _mk_cc("386", "SI", 8); }
  if compare.str_compare(c, "387") == 0 { return _mk_cc("387", "BA", 8); }
  if compare.str_compare(c, "389") == 0 { return _mk_cc("389", "MK", 8); }
  return _cc_missing();
}

// Europe extras (4xx block).
fn _code3_4(c: Str) -> CallingCode {
  if compare.str_compare(c, "420") == 0 { return _mk_cc("420", "CZ", 9); }
  if compare.str_compare(c, "421") == 0 { return _mk_cc("421", "SK", 9); }
  if compare.str_compare(c, "423") == 0 { return _mk_cc("423", "LI", 7); }
  return _cc_missing();
}

// Central America (50x) and South America (59x).
fn _code3_5(c: Str) -> CallingCode {
  if compare.str_compare(c, "501") == 0 { return _mk_cc("501", "BZ", 7); }
  if compare.str_compare(c, "502") == 0 { return _mk_cc("502", "GT", 8); }
  if compare.str_compare(c, "503") == 0 { return _mk_cc("503", "SV", 8); }
  if compare.str_compare(c, "504") == 0 { return _mk_cc("504", "HN", 8); }
  if compare.str_compare(c, "505") == 0 { return _mk_cc("505", "NI", 8); }
  if compare.str_compare(c, "506") == 0 { return _mk_cc("506", "CR", 8); }
  if compare.str_compare(c, "507") == 0 { return _mk_cc("507", "PA", 7); }
  if compare.str_compare(c, "508") == 0 { return _mk_cc("508", "PM", 6); }
  if compare.str_compare(c, "509") == 0 { return _mk_cc("509", "HT", 8); }
  if compare.str_compare(c, "591") == 0 { return _mk_cc("591", "BO", 8); }
  if compare.str_compare(c, "592") == 0 { return _mk_cc("592", "GY", 7); }
  if compare.str_compare(c, "593") == 0 { return _mk_cc("593", "EC", 9); }
  if compare.str_compare(c, "594") == 0 { return _mk_cc("594", "GF", 9); }
  if compare.str_compare(c, "595") == 0 { return _mk_cc("595", "PY", 9); }
  if compare.str_compare(c, "596") == 0 { return _mk_cc("596", "MQ", 9); }
  if compare.str_compare(c, "597") == 0 { return _mk_cc("597", "SR", 7); }
  if compare.str_compare(c, "598") == 0 { return _mk_cc("598", "UY", 8); }
  return _cc_missing();
}

// Asia / Pacific (6xx).
fn _code3_6(c: Str) -> CallingCode {
  if compare.str_compare(c, "673") == 0 { return _mk_cc("673", "BN", 7); }
  if compare.str_compare(c, "674") == 0 { return _mk_cc("674", "NR", 7); }
  if compare.str_compare(c, "675") == 0 { return _mk_cc("675", "PG", 8); }
  if compare.str_compare(c, "676") == 0 { return _mk_cc("676", "TO", 5); }
  if compare.str_compare(c, "677") == 0 { return _mk_cc("677", "SB", 5); }
  if compare.str_compare(c, "678") == 0 { return _mk_cc("678", "VU", 5); }
  if compare.str_compare(c, "679") == 0 { return _mk_cc("679", "FJ", 7); }
  if compare.str_compare(c, "680") == 0 { return _mk_cc("680", "PW", 7); }
  if compare.str_compare(c, "681") == 0 { return _mk_cc("681", "WF", 6); }
  if compare.str_compare(c, "682") == 0 { return _mk_cc("682", "CK", 5); }
  if compare.str_compare(c, "683") == 0 { return _mk_cc("683", "NU", 4); }
  if compare.str_compare(c, "685") == 0 { return _mk_cc("685", "WS", 5); }
  if compare.str_compare(c, "686") == 0 { return _mk_cc("686", "KI", 5); }
  if compare.str_compare(c, "687") == 0 { return _mk_cc("687", "NC", 6); }
  if compare.str_compare(c, "688") == 0 { return _mk_cc("688", "TV", 5); }
  if compare.str_compare(c, "689") == 0 { return _mk_cc("689", "PF", 8); }
  if compare.str_compare(c, "690") == 0 { return _mk_cc("690", "TK", 4); }
  if compare.str_compare(c, "691") == 0 { return _mk_cc("691", "FM", 7); }
  if compare.str_compare(c, "692") == 0 { return _mk_cc("692", "MH", 7); }
  return _cc_missing();
}

// East / Southeast Asia (8xx).
fn _code3_8(c: Str) -> CallingCode {
  if compare.str_compare(c, "850") == 0 { return _mk_cc("850", "KP", 9); }
  if compare.str_compare(c, "852") == 0 { return _mk_cc("852", "HK", 8); }
  if compare.str_compare(c, "853") == 0 { return _mk_cc("853", "MO", 8); }
  if compare.str_compare(c, "855") == 0 { return _mk_cc("855", "KH", 8); }
  if compare.str_compare(c, "856") == 0 { return _mk_cc("856", "LA", 8); }
  if compare.str_compare(c, "880") == 0 { return _mk_cc("880", "BD", 10); }
  if compare.str_compare(c, "886") == 0 { return _mk_cc("886", "TW", 9); }
  return _cc_missing();
}

// Middle East / Central Asia (9xx).
fn _code3_9(c: Str) -> CallingCode {
  if compare.str_compare(c, "960") == 0 { return _mk_cc("960", "MV", 7); }
  if compare.str_compare(c, "961") == 0 { return _mk_cc("961", "LB", 7); }
  if compare.str_compare(c, "962") == 0 { return _mk_cc("962", "JO", 9); }
  if compare.str_compare(c, "963") == 0 { return _mk_cc("963", "SY", 9); }
  if compare.str_compare(c, "964") == 0 { return _mk_cc("964", "IQ", 10); }
  if compare.str_compare(c, "965") == 0 { return _mk_cc("965", "KW", 8); }
  if compare.str_compare(c, "966") == 0 { return _mk_cc("966", "SA", 9); }
  if compare.str_compare(c, "967") == 0 { return _mk_cc("967", "YE", 9); }
  if compare.str_compare(c, "968") == 0 { return _mk_cc("968", "OM", 8); }
  if compare.str_compare(c, "970") == 0 { return _mk_cc("970", "PS", 9); }
  if compare.str_compare(c, "971") == 0 { return _mk_cc("971", "AE", 9); }
  if compare.str_compare(c, "972") == 0 { return _mk_cc("972", "IL", 9); }
  if compare.str_compare(c, "973") == 0 { return _mk_cc("973", "BH", 8); }
  if compare.str_compare(c, "974") == 0 { return _mk_cc("974", "QA", 8); }
  if compare.str_compare(c, "975") == 0 { return _mk_cc("975", "BT", 8); }
  if compare.str_compare(c, "976") == 0 { return _mk_cc("976", "MN", 8); }
  if compare.str_compare(c, "977") == 0 { return _mk_cc("977", "NP", 9); }
  if compare.str_compare(c, "992") == 0 { return _mk_cc("992", "TJ", 9); }
  if compare.str_compare(c, "993") == 0 { return _mk_cc("993", "TM", 8); }
  if compare.str_compare(c, "994") == 0 { return _mk_cc("994", "AZ", 9); }
  if compare.str_compare(c, "995") == 0 { return _mk_cc("995", "GE", 9); }
  if compare.str_compare(c, "996") == 0 { return _mk_cc("996", "KG", 9); }
  if compare.str_compare(c, "998") == 0 { return _mk_cc("998", "UZ", 9); }
  return _cc_missing();
}

// ---------------------------------------------------------------------------
// Country-code resolution (longest match: 3, then 2, then 1 digit)
// ---------------------------------------------------------------------------

fn _lookup_code(c: Str) -> CallingCode {
  let n = c.len();
  if n == 1 { return _code1(c); }
  if n == 2 { return _code2(c); }
  if n == 3 { return _code3(c); }
  return _cc_missing();
}

fn _resolve_cc(digits: Str) -> CallingCode {
  let n = digits.len();
  if n >= 3 {
    let c3 = _code3(string.str_slice(digits, 0, 3));
    let k3: Str = c3.code;
    if k3.len() > 0 { return c3; }
  }
  if n >= 2 {
    let c2 = _code2(string.str_slice(digits, 0, 2));
    let k2: Str = c2.code;
    if k2.len() > 0 { return c2; }
  }
  if n >= 1 {
    return _code1(string.str_slice(digits, 0, 1));
  }
  return _cc_missing();
}

// First min(k, len) characters of an all-digit string (for error messages).
fn _digit_prefix(s: Str, k: Int) -> Str {
  if s.len() <= k { return s; }
  return string.str_slice(s, 0, k);
}

// ---------------------------------------------------------------------------
// Scanner
// ---------------------------------------------------------------------------

// Scan one international-form body starting at byte `start`, the position
// just after any '+' / '00' / '%2B' prefix the caller consumed. `s` is the
// original input, so every offset reported is an input byte offset. Digits
// are collected (separators stripped) into `digits` while their input byte
// offsets are pushed in lockstep into the parallel offset vector; national
// validation runs after the scan.
fn _scan_body(s: Str, start: Int) -> Result[PhoneNumber, Str] {
  let n = s.len();
  var digits = "";
  var offsets = Vec[Int].new();
  var ext = "";
  var in_ext = false;
  var ext_seen = false;
  var ext_marker_at = start;
  var i = start;
  while i < n {
    let b = string.byte_at(s, i);
    if _is_digit(b) {
      let d = string.str_slice(s, i, i + 1);
      if in_ext {
        ext = ext + d;
        ext_seen = true;
      } else {
        if digits.len() >= _PN_MAX_DIGITS {
          return _pn_err("phone: more than 15 digits (E.164 max) at offset " + convert.int_to_string(i));
        }
        digits = digits + d;
        offsets.push(i);
      }
      i = i + 1;
    } else if _is_separator(b) {
      i = i + 1;
    } else if !in_ext && (b == _PN_LOWER_X || b == _PN_UPPER_X) {
      in_ext = true;
      ext_marker_at = i;
      i = i + 1;
    } else if !in_ext && (b == _PN_LOWER_E || b == _PN_UPPER_E) {
      if !_matches_ci_at(s, i, "ext") {
        return _pn_err("phone: unexpected character '" + string.str_slice(s, i, i + 1) + "' at offset " + convert.int_to_string(i));
      }
      in_ext = true;
      ext_marker_at = i;
      i = i + 3;
    } else if !in_ext && b == _PN_SEMI {
      if !_matches_ci_at(s, i + 1, "ext=") {
        return _pn_err("phone: unexpected character '" + string.str_slice(s, i, i + 1) + "' at offset " + convert.int_to_string(i));
      }
      in_ext = true;
      ext_marker_at = i;
      i = i + 5;
    } else {
      return _pn_err("phone: unexpected character '" + string.str_slice(s, i, i + 1) + "' at offset " + convert.int_to_string(i));
    }
  }
  if in_ext && !ext_seen {
    return _pn_err("phone: empty extension at offset " + convert.int_to_string(ext_marker_at));
  }
  if digits.len() == 0 {
    return _pn_err("phone: empty national number at offset " + convert.int_to_string(start));
  }
  let cc = _resolve_cc(digits);
  let code: Str = cc.code;
  if code.len() == 0 {
    let p = _digit_prefix(digits, 3);
    return _pn_err("phone: unknown country code '" + p + "' at offset " + convert.int_to_string(start));
  }
  let sep = code.len();
  let national = string.str_slice(digits, sep, digits.len());
  if national.len() == 0 {
    let last: Int = offsets[sep - 1];
    return _pn_err("phone: empty national number at offset " + convert.int_to_string(last + 1));
  }
  let nat_at: Int = offsets[sep];
  if string.byte_at(national, 0) == _PN_ZERO {
    return _pn_err("phone: national number starts with zero at offset " + convert.int_to_string(nat_at));
  }
  let minl: Int = cc.min_len;
  if national.len() < minl {
    let isos: Str = cc.iso;
    return _pn_err("phone: national number too short for " + isos + ": " + convert.int_to_string(national.len()) + " digits, minimum " + convert.int_to_string(minl) + " at offset " + convert.int_to_string(nat_at));
  }
  let v = PhoneNumber{ country_code: code; iso: cc.iso; national: national; extension: ext; digit_offsets: offsets };
  return _pn_ok(v);
}

// ---------------------------------------------------------------------------
// Public parsing API
// ---------------------------------------------------------------------------

/// Parse an international-form phone number.
/// Params: s - the candidate text. Accepted surface shapes: "+CC...", the
/// "00CC..." international dialling prefix, or a bare "CC..." digit string.
/// Separators (space, hyphen, dot, parentheses) are stripped anywhere after
/// the prefix; an extension may follow 'x', 'ext' or ';ext=' (ASCII case
/// insensitive). Non-digit text after the prefix is rejected.
/// Returns: Ok(PhoneNumber); Err("phone: ...") with a byte offset (see
/// SPEC.md for the exact message catalog).
/// Error case: see the SPEC.md error catalog.
/// Complexity: O(len(s)).
pub fn phone_parse(s: Str) -> Result[PhoneNumber, Str] {
  let n = s.len();
  if n == 0 { return _pn_err("phone: empty input"); }
  let b0 = string.byte_at(s, 0);
  if b0 == _PN_PLUS { return _scan_body(s, 1); }
  if b0 == _PN_ZERO && n >= 2 && string.byte_at(s, 1) == _PN_ZERO {
    return _scan_body(s, 2);
  }
  return _scan_body(s, 0);
}

/// Parse an RFC 3966 `tel:` URI.
/// Params: s - the URI text: "tel:" (ASCII case insensitive), then either a
/// literal '+' or the URI-encoded "%2B" (hex case insensitive), then the
/// number in the phone_parse body grammar, optionally followed by
/// ";ext=<digits>".
/// Returns: Ok(PhoneNumber); Err("phone: ...") with a byte offset into the
/// URI text (the "%2B" form included, because scanning starts at the
/// original bytes).
/// Error case: not a "tel:" URI, missing '+' or '%2B', then every
/// phone_parse body error.
/// Complexity: O(len(s)).
pub fn phone_parse_tel_uri(s: Str) -> Result[PhoneNumber, Str] {
  if s.len() < 4 { return _pn_err("phone: not a tel URI at offset 0"); }
  if !_matches_ci_at(s, 0, "tel:") { return _pn_err("phone: not a tel URI at offset 0"); }
  if s.len() >= 5 {
    let b4 = string.byte_at(s, 4);
    if b4 == _PN_PLUS { return _scan_body(s, 5); }
  }
  if _matches_ci_at(s, 4, "%2b") { return _scan_body(s, 7); }
  return _pn_err("phone: tel URI missing '+' or '%2B' at offset 4");
}

/// True when phone_parse accepts `s`, false for every error.
/// Params: s - candidate phone text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(len(s)).
pub fn phone_is_valid(s: Str) -> Bool {
  match phone_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Formatting API
// ---------------------------------------------------------------------------

/// Canonical E.164 text: '+' followed by the country code and the national
/// significant digits. The extension is not part of E.164 and is omitted.
/// Params: v - a parsed number.
/// Returns: for example "+12025550147".
/// Error case: none.
/// Complexity: O(len).
pub fn phone_e164(v: &PhoneNumber) -> Str {
  let c: Str = v.country_code;
  let d: Str = v.national;
  return "+" + c + d;
}

// Space-group a digit string in threes counted from the right; the leftmost
// group may hold 1 or 2 digits.
fn _group3(digits: Str) -> Str {
  let n = digits.len();
  var out = "";
  var i = 0;
  while i < n {
    if i > 0 && (n - i) % 3 == 0 {
      out = out + " ";
    }
    out = out + string.str_slice(digits, i, i + 1);
    i = i + 1;
  }
  return out;
}

/// Grouped international display: "+CC NNN NNN NNN" with the national digits
/// grouped in threes counted from the right (the leftmost group may be
/// shorter). This is a generic grouping, not the national convention of the
/// country. A parsed extension is appended as " x<digits>".
/// Params: v - a parsed number.
/// Returns: for example "+44 2 079 460 958".
/// Error case: none.
/// Complexity: O(len).
pub fn phone_international(v: &PhoneNumber) -> Str {
  let c: Str = v.country_code;
  let d: Str = v.national;
  let e: Str = v.extension;
  let out = "+" + c + " " + _group3(d);
  if e.len() == 0 { return out; }
  return out + " x" + e;
}

/// Masked display: "+CC" followed by '*' for every national digit except the
/// last four, which stay visible; when the national number has four or fewer
/// digits every national digit is masked. The country code is not masked.
/// Params: v - a parsed number.
/// Returns: for example "+12025550147" -> "+1******0147".
/// Error case: none.
/// Complexity: O(len).
pub fn phone_mask(v: &PhoneNumber) -> Str {
  let c: Str = v.country_code;
  let d: Str = v.national;
  let n = d.len();
  if n <= 4 {
    return "+" + c + string.str_repeat("*", n);
  }
  let tail = string.str_slice(d, n - 4, n);
  return "+" + c + string.str_repeat("*", n - 4) + tail;
}

/// RFC 3966 URI: "tel:+<digits>", plus ";ext=<digits>" when a parsed
/// extension is present. The '+' is emitted literally; the "%2B" encoded
/// form is accepted by phone_parse_tel_uri but never produced.
/// Params: v - a parsed number.
/// Returns: for example "tel:+12025550147;ext=89".
/// Error case: none.
/// Complexity: O(len).
pub fn phone_tel_uri(v: &PhoneNumber) -> Str {
  let c: Str = v.country_code;
  let d: Str = v.national;
  let e: Str = v.extension;
  let base = "tel:+" + c + d;
  if e.len() == 0 { return base; }
  return base + ";ext=" + e;
}

// ---------------------------------------------------------------------------
// Accessors and equality
// ---------------------------------------------------------------------------

/// E.164 country calling code digits of a parsed number ("1".."998").
pub fn phone_country_code(v: &PhoneNumber) -> Str {
  let s: Str = v.country_code;
  return s;
}

/// ISO 3166-1 alpha-2 code of the parsed number's primary country.
pub fn phone_iso(v: &PhoneNumber) -> Str {
  let s: Str = v.iso;
  return s;
}

/// National significant digits of a parsed number (separators stripped).
pub fn phone_national(v: &PhoneNumber) -> Str {
  let s: Str = v.national;
  return s;
}

/// Extension digits of a parsed number ("" when none was present).
pub fn phone_extension(v: &PhoneNumber) -> Str {
  let s: Str = v.extension;
  return s;
}

/// Raw digit string of a parsed number: country code followed by the
/// national digits, without '+' and without the extension.
pub fn phone_raw_digits(v: &PhoneNumber) -> Str {
  let c: Str = v.country_code;
  let d: Str = v.national;
  return c + d;
}

/// Number of digits in country_code + national (extension digits excluded).
pub fn phone_digit_count(v: &PhoneNumber) -> Int {
  let c: Str = v.country_code;
  let d: Str = v.national;
  return c.len() + d.len();
}

/// Input byte offset of the i-th digit of country_code + national, or -1
/// when i is outside 0..phone_digit_count(v)-1.
pub fn phone_digit_offset(v: &PhoneNumber, i: Int) -> Int {
  let offs: Vec[Int] = v.digit_offsets;
  if i < 0 { return -1; }
  if i >= offs.len() { return -1; }
  let x: Int = offs[i];
  return x;
}

/// True when two parsed numbers have the same canonical digits, i.e. the
/// same country code and national digits. The extension is not part of the
/// canonical digit string and does not affect equality.
pub fn phone_equals(a: &PhoneNumber, b: &PhoneNumber) -> Bool {
  let ca: Str = a.country_code;
  let cb: Str = b.country_code;
  if compare.str_compare(ca, cb) != 0 { return false; }
  let na: Str = a.national;
  let nb: Str = b.national;
  return compare.str_compare(na, nb) == 0;
}

// ---------------------------------------------------------------------------
// Table accessors
// ---------------------------------------------------------------------------

/// Documented minimum national significant number length for a calling code.
/// Params: country_code - the E.164 code digits ("1".."998"), compared
/// as-is; non-digit text is simply unknown.
/// Returns: the table minimum (>= 4) for a table code, or 0 when the code is
/// not in the table. The value is a conservative structural floor, not a
/// dial-plan validator (see SPEC.md).
/// Error case: none.
/// Complexity: O(1).
pub fn phone_min_length(country_code: Str) -> Int {
  let v = _lookup_code(country_code);
  let m: Int = v.min_len;
  return m;
}

/// ISO 3166-1 alpha-2 code of a calling code's primary country.
/// Params: country_code - the E.164 code digits, compared as-is.
/// Returns: the two-letter code for a table code, or "" when the code is
/// not in the table.
/// Error case: none.
/// Complexity: O(1).
pub fn phone_iso_for_code(country_code: Str) -> Str {
  let v = _lookup_code(country_code);
  let s: Str = v.iso;
  return s;
}

/// Number of rows in the embedded country calling-code table.
pub fn phone_country_count() -> Int {
  return _PN_COUNTRY_COUNT;
}
