// XIOM -- xiom.l10n-currency: ISO 4217 currency data, lookups, and exact
// integer minor-unit amount parsing and formatting.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a currency is an immutable table row (alpha code, zero-padded
// 3-digit numeric code, minor-unit exponent, English name, a best-effort
// prefix symbol). An amount is `Money`: a signed integer count of minor
// units plus the currency alpha and the exponent captured at parse time.
// Nothing here uses floating point, locale databases, allocation-heavy
// builders or FFI; the module depends only on xiom.string,
// xiom.string.compare and xiom.convert from xiom.std.
//
// Table cut-off: the embedded table is the ISO 4217 "List One" published
// 2026-09-17 (SIX Financial Information) restricted to the 165 currency
// entries that carry a numeric minor-unit exponent 0, 2, 3 or 4. The 13
// active codes whose minor units are "N.A." (XAU, XAG, XPT, XPD, XDR, XBA,
// XBB, XBC, XBD, XSU, XUA, XTS, XXX) are deliberately excluded: they have no
// minor-unit semantics, so parse/format cannot be meaningfully defined for
// them. Every excluded code fails with "unknown currency". The cut-off is
// documented in SPEC.md and the failure mode is a test.
//
// Naming: the package manifest is "xiom.l10n-currency", but the compiler
// module must be a dotted identifier (v0.61.3 rejects '-' in `module`
// declarations, error[P001] at 1:17), so the module is xiom.l10n.currency.

module xiom.l10n.currency

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _CUR_PLUS: UInt8 = 43u8;
const _CUR_MINUS: UInt8 = 45u8;
const _CUR_ZERO: UInt8 = 48u8;
const _CUR_NINE: UInt8 = 57u8;
const _CUR_UPPER_A: UInt8 = 65u8;
const _CUR_UPPER_Z: UInt8 = 90u8;
const _CUR_SPACE: UInt8 = 32u8;
const _CUR_LOWER_A: UInt8 = 97u8;
const _CUR_LOWER_Z: UInt8 = 122u8;
const _CUR_INT_MAX: Int = 9223372036854775807;
const _CUR_INT_MAX_DIV10: Int = 922337203685477580;
const _CUR_INT_MAX_LAST_DIGIT: Int = 7;
const _CUR_COUNT: Int = 165;

/// ISO 4217 currency row. `alpha` is three uppercase ASCII letters, `numeric`
/// the zero-padded three-digit numeric code, `exponent` the number of decimal
/// digits in the minor unit (0, 2, 3 or 4 in this table), `name` the English
/// ISO name, and `symbol` a common prefix symbol for majors ("" when the
/// table carries none, or when the conventional symbol is written as a
/// suffix and therefore cannot be placed by this prefix-only formatter).
pub type Currency = {
  alpha: Str;
  numeric: Str;
  exponent: Int;
  name: Str;
  symbol: Str;
}

/// An exact monetary amount: `minor` is the value in minor units (minor =
/// value * 10^exponent), `alpha` the currency it belongs to, and `exponent`
/// the minor-unit exponent captured when the amount was parsed. No float ever
/// enters this type; a USD 12.34 amount is minor = 1234.
pub type Money = {
  alpha: Str;
  minor: Int;
  exponent: Int;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _cur_ok(v: Currency) -> Result[Currency, Str] { return Ok(v); }
fn _cur_err(m: Str) -> Result[Currency, Str] { return Err(m); }
fn _money_ok(v: Money) -> Result[Money, Str] { return Ok(v); }
fn _money_err(m: Str) -> Result[Money, Str] { return Err(m); }
fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }
fn _int_ok(n: Int) -> Result[Int, Str] { return Ok(n); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character and string helpers
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _CUR_ZERO && b <= _CUR_NINE;
}

fn _is_upper(b: UInt8) -> Bool {
  return b >= _CUR_UPPER_A && b <= _CUR_UPPER_Z;
}

fn _is_lower(b: UInt8) -> Bool {
  return b >= _CUR_LOWER_A && b <= _CUR_LOWER_Z;
}

// ASCII lowercase of one byte; non-letters pass through unchanged.
fn _lower(b: UInt8) -> UInt8 {
  if _is_upper(b) { return b + 32u8; }
  return b;
}

// ASCII case-insensitive equality. Non-ASCII bytes compare byte-for-byte, so
// names with accents still require their exact bytes.
fn _eq_ci(a: Str, b: Str) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x = string.byte_at(a, i);
    let y = string.byte_at(b, i);
    if _lower(x) != _lower(y) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly three ASCII letters (either case).
fn _is_alpha3(s: Str) -> Bool {
  if s.len() != 3 { return false; }
  var i = 0;
  while i < 3 {
    let b = string.byte_at(s, i);
    if !_is_upper(b) && !_is_lower(b) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `s` is exactly three ASCII digits (the canonical numeric form).
fn _is_numeric3(s: Str) -> Bool {
  if s.len() != 3 { return false; }
  var i = 0;
  while i < 3 {
    if !_is_digit(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when sub occurs in text at byte offset at (byte-wise comparison).
// An empty sub never matches (an empty separator is handled by its caller).
fn _matches_at(text: Str, at: Int, sub: Str) -> Bool {
  if sub.len() == 0 { return false; }
  if at < 0 { return false; }
  if at + sub.len() > text.len() { return false; }
  var i = 0;
  while i < sub.len() {
    if string.byte_at(text, at + i) != string.byte_at(sub, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Case-insensitive variant of _matches_at (ASCII only), used for the
// optional leading alpha-code prefix.
fn _matches_ci_at(text: Str, at: Int, sub: Str) -> Bool {
  if sub.len() == 0 { return false; }
  if at < 0 { return false; }
  if at + sub.len() > text.len() { return false; }
  var i = 0;
  while i < sub.len() {
    let x = string.byte_at(text, at + i);
    let y = string.byte_at(sub, i);
    if _lower(x) != _lower(y) { return false; }
    i = i + 1;
  }
  return true;
}

// Decimal text of an Int with no sign, exact for every 64-bit value
// including the minimum (which has no representable positive counterpart).
fn _abs_digits(n: Int) -> Str {
  let s = convert.int_to_string(n);
  if s.len() > 0 {
    if string.byte_at(s, 0) == _CUR_MINUS {
      return string.str_slice(s, 1, s.len());
    }
  }
  return s;
}

// Insert sep every three digits counted from the right; an empty sep returns
// the digits untouched.
fn _group_digits(digits: Str, sep: Str) -> Str {
  let n = digits.len();
  if sep.len() == 0 {
    return digits;
  }
  var out = "";
  var i = 0;
  while i < n {
    if i > 0 && (n - i) % 3 == 0 {
      out = out + sep;
    }
    out = out + string.str_slice(digits, i, i + 1);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Embedded ISO 4217 table (see the header for the cut-off)
// ---------------------------------------------------------------------------
//
// The table is three explicit if-chains of one-line rows in ascending alpha
// order. Module-level table initializers are mis-materialized by v0.61.3, so
// the rows are compiled into comparison chains, as in xiom.iban.

fn _mk_row(a: Str, n: Str, e: Int, nm: Str, s: Str) -> Currency {
  let v = Currency{ alpha: a; numeric: n; exponent: e; name: nm; symbol: s };
  return v;
}

fn _missing() -> Currency {
  return _mk_row("", "", -1, "", "");
}

// Rows 0..65 (AED..ISK).
fn _bank_a(i: Int) -> Currency {
  if i == 0 { return _mk_row("AED", "784", 2, "UAE Dirham", ""); }
  if i == 1 { return _mk_row("AFN", "971", 2, "Afghani", ""); }
  if i == 2 { return _mk_row("ALL", "008", 2, "Lek", ""); }
  if i == 3 { return _mk_row("AMD", "051", 2, "Armenian Dram", ""); }
  if i == 4 { return _mk_row("AOA", "973", 2, "Kwanza", ""); }
  if i == 5 { return _mk_row("ARS", "032", 2, "Argentine Peso", "AR$"); }
  if i == 6 { return _mk_row("AUD", "036", 2, "Australian Dollar", "A$"); }
  if i == 7 { return _mk_row("AWG", "533", 2, "Aruban Florin", ""); }
  if i == 8 { return _mk_row("AZN", "944", 2, "Azerbaijan Manat", ""); }
  if i == 9 { return _mk_row("BAM", "977", 2, "Convertible Mark", ""); }
  if i == 10 { return _mk_row("BBD", "052", 2, "Barbados Dollar", ""); }
  if i == 11 { return _mk_row("BDT", "050", 2, "Taka", ""); }
  if i == 12 { return _mk_row("BHD", "048", 3, "Bahraini Dinar", ""); }
  if i == 13 { return _mk_row("BIF", "108", 0, "Burundi Franc", ""); }
  if i == 14 { return _mk_row("BMD", "060", 2, "Bermudian Dollar", ""); }
  if i == 15 { return _mk_row("BND", "096", 2, "Brunei Dollar", ""); }
  if i == 16 { return _mk_row("BOB", "068", 2, "Boliviano", ""); }
  if i == 17 { return _mk_row("BOV", "984", 2, "Mvdol", ""); }
  if i == 18 { return _mk_row("BRL", "986", 2, "Brazilian Real", "R$"); }
  if i == 19 { return _mk_row("BSD", "044", 2, "Bahamian Dollar", ""); }
  if i == 20 { return _mk_row("BTN", "064", 2, "Ngultrum", ""); }
  if i == 21 { return _mk_row("BWP", "072", 2, "Pula", ""); }
  if i == 22 { return _mk_row("BYN", "933", 2, "Belarusian Ruble", ""); }
  if i == 23 { return _mk_row("BZD", "084", 2, "Belize Dollar", ""); }
  if i == 24 { return _mk_row("CAD", "124", 2, "Canadian Dollar", "CA$"); }
  if i == 25 { return _mk_row("CDF", "976", 2, "Congolese Franc", ""); }
  if i == 26 { return _mk_row("CHE", "947", 2, "WIR Euro", ""); }
  if i == 27 { return _mk_row("CHF", "756", 2, "Swiss Franc", "CHF"); }
  if i == 28 { return _mk_row("CHW", "948", 2, "WIR Franc", ""); }
  if i == 29 { return _mk_row("CLF", "990", 4, "Unidad de Fomento", ""); }
  if i == 30 { return _mk_row("CLP", "152", 0, "Chilean Peso", "CL$"); }
  if i == 31 { return _mk_row("CNY", "156", 2, "Yuan Renminbi", "CN¥"); }
  if i == 32 { return _mk_row("COP", "170", 2, "Colombian Peso", "CO$"); }
  if i == 33 { return _mk_row("COU", "970", 2, "Unidad de Valor Real", ""); }
  if i == 34 { return _mk_row("CRC", "188", 2, "Costa Rican Colon", "₡"); }
  if i == 35 { return _mk_row("CUP", "192", 2, "Cuban Peso", ""); }
  if i == 36 { return _mk_row("CVE", "132", 2, "Cabo Verde Escudo", ""); }
  if i == 37 { return _mk_row("CZK", "203", 2, "Czech Koruna", ""); }
  if i == 38 { return _mk_row("DJF", "262", 0, "Djibouti Franc", ""); }
  if i == 39 { return _mk_row("DKK", "208", 2, "Danish Krone", ""); }
  if i == 40 { return _mk_row("DOP", "214", 2, "Dominican Peso", "RD$"); }
  if i == 41 { return _mk_row("DZD", "012", 2, "Algerian Dinar", ""); }
  if i == 42 { return _mk_row("EGP", "818", 2, "Egyptian Pound", ""); }
  if i == 43 { return _mk_row("ERN", "232", 2, "Nakfa", ""); }
  if i == 44 { return _mk_row("ETB", "230", 2, "Ethiopian Birr", ""); }
  if i == 45 { return _mk_row("EUR", "978", 2, "Euro", "€"); }
  if i == 46 { return _mk_row("FJD", "242", 2, "Fiji Dollar", ""); }
  if i == 47 { return _mk_row("FKP", "238", 2, "Falkland Islands Pound", ""); }
  if i == 48 { return _mk_row("GBP", "826", 2, "Pound Sterling", "£"); }
  if i == 49 { return _mk_row("GEL", "981", 2, "Lari", ""); }
  if i == 50 { return _mk_row("GHS", "936", 2, "Ghana Cedi", "₵"); }
  if i == 51 { return _mk_row("GIP", "292", 2, "Gibraltar Pound", ""); }
  if i == 52 { return _mk_row("GMD", "270", 2, "Dalasi", ""); }
  if i == 53 { return _mk_row("GNF", "324", 0, "Guinean Franc", ""); }
  if i == 54 { return _mk_row("GTQ", "320", 2, "Quetzal", "Q"); }
  if i == 55 { return _mk_row("GYD", "328", 2, "Guyana Dollar", ""); }
  if i == 56 { return _mk_row("HKD", "344", 2, "Hong Kong Dollar", "HK$"); }
  if i == 57 { return _mk_row("HNL", "340", 2, "Lempira", ""); }
  if i == 58 { return _mk_row("HTG", "332", 2, "Gourde", ""); }
  if i == 59 { return _mk_row("HUF", "348", 2, "Forint", ""); }
  if i == 60 { return _mk_row("IDR", "360", 2, "Rupiah", ""); }
  if i == 61 { return _mk_row("ILS", "376", 2, "New Israeli Sheqel", "₪"); }
  if i == 62 { return _mk_row("INR", "356", 2, "Indian Rupee", "₹"); }
  if i == 63 { return _mk_row("IQD", "368", 3, "Iraqi Dinar", ""); }
  if i == 64 { return _mk_row("IRR", "364", 2, "Iranian Rial", ""); }
  if i == 65 { return _mk_row("ISK", "352", 0, "Iceland Krona", ""); }
  return _missing();
}

// Rows 66..131 (JMD..SYP).
fn _bank_b(i: Int) -> Currency {
  if i == 0 { return _mk_row("JMD", "388", 2, "Jamaican Dollar", ""); }
  if i == 1 { return _mk_row("JOD", "400", 3, "Jordanian Dinar", ""); }
  if i == 2 { return _mk_row("JPY", "392", 0, "Yen", "¥"); }
  if i == 3 { return _mk_row("KES", "404", 2, "Kenyan Shilling", "KSh"); }
  if i == 4 { return _mk_row("KGS", "417", 2, "Som", ""); }
  if i == 5 { return _mk_row("KHR", "116", 2, "Riel", ""); }
  if i == 6 { return _mk_row("KMF", "174", 0, "Comorian Franc", ""); }
  if i == 7 { return _mk_row("KPW", "408", 2, "North Korean Won", ""); }
  if i == 8 { return _mk_row("KRW", "410", 0, "Won", "₩"); }
  if i == 9 { return _mk_row("KWD", "414", 3, "Kuwaiti Dinar", ""); }
  if i == 10 { return _mk_row("KYD", "136", 2, "Cayman Islands Dollar", ""); }
  if i == 11 { return _mk_row("KZT", "398", 2, "Tenge", "₸"); }
  if i == 12 { return _mk_row("LAK", "418", 2, "Lao Kip", ""); }
  if i == 13 { return _mk_row("LBP", "422", 2, "Lebanese Pound", ""); }
  if i == 14 { return _mk_row("LKR", "144", 2, "Sri Lanka Rupee", ""); }
  if i == 15 { return _mk_row("LRD", "430", 2, "Liberian Dollar", ""); }
  if i == 16 { return _mk_row("LSL", "426", 2, "Loti", ""); }
  if i == 17 { return _mk_row("LYD", "434", 3, "Libyan Dinar", ""); }
  if i == 18 { return _mk_row("MAD", "504", 2, "Moroccan Dirham", ""); }
  if i == 19 { return _mk_row("MDL", "498", 2, "Moldovan Leu", ""); }
  if i == 20 { return _mk_row("MGA", "969", 2, "Malagasy Ariary", ""); }
  if i == 21 { return _mk_row("MKD", "807", 2, "Denar", ""); }
  if i == 22 { return _mk_row("MMK", "104", 2, "Kyat", ""); }
  if i == 23 { return _mk_row("MNT", "496", 2, "Tugrik", "₮"); }
  if i == 24 { return _mk_row("MOP", "446", 2, "Pataca", ""); }
  if i == 25 { return _mk_row("MRU", "929", 2, "Ouguiya", ""); }
  if i == 26 { return _mk_row("MUR", "480", 2, "Mauritius Rupee", ""); }
  if i == 27 { return _mk_row("MVR", "462", 2, "Rufiyaa", ""); }
  if i == 28 { return _mk_row("MWK", "454", 2, "Malawi Kwacha", ""); }
  if i == 29 { return _mk_row("MXN", "484", 2, "Mexican Peso", "MX$"); }
  if i == 30 { return _mk_row("MXV", "979", 2, "Mexican Unidad de Inversion (UDI)", ""); }
  if i == 31 { return _mk_row("MYR", "458", 2, "Malaysian Ringgit", ""); }
  if i == 32 { return _mk_row("MZN", "943", 2, "Mozambique Metical", ""); }
  if i == 33 { return _mk_row("NAD", "516", 2, "Namibia Dollar", ""); }
  if i == 34 { return _mk_row("NGN", "566", 2, "Naira", "₦"); }
  if i == 35 { return _mk_row("NIO", "558", 2, "Cordoba Oro", "C$"); }
  if i == 36 { return _mk_row("NOK", "578", 2, "Norwegian Krone", ""); }
  if i == 37 { return _mk_row("NPR", "524", 2, "Nepalese Rupee", ""); }
  if i == 38 { return _mk_row("NZD", "554", 2, "New Zealand Dollar", "NZ$"); }
  if i == 39 { return _mk_row("OMR", "512", 3, "Rial Omani", ""); }
  if i == 40 { return _mk_row("PAB", "590", 2, "Balboa", "B/."); }
  if i == 41 { return _mk_row("PEN", "604", 2, "Sol", "S/"); }
  if i == 42 { return _mk_row("PGK", "598", 2, "Kina", ""); }
  if i == 43 { return _mk_row("PHP", "608", 2, "Philippine Peso", "₱"); }
  if i == 44 { return _mk_row("PKR", "586", 2, "Pakistan Rupee", ""); }
  if i == 45 { return _mk_row("PLN", "985", 2, "Zloty", ""); }
  if i == 46 { return _mk_row("PYG", "600", 0, "Guarani", ""); }
  if i == 47 { return _mk_row("QAR", "634", 2, "Qatari Rial", ""); }
  if i == 48 { return _mk_row("RON", "946", 2, "Romanian Leu", ""); }
  if i == 49 { return _mk_row("RSD", "941", 2, "Serbian Dinar", ""); }
  if i == 50 { return _mk_row("RUB", "643", 2, "Russian Ruble", "₽"); }
  if i == 51 { return _mk_row("RWF", "646", 0, "Rwanda Franc", ""); }
  if i == 52 { return _mk_row("SAR", "682", 2, "Saudi Riyal", ""); }
  if i == 53 { return _mk_row("SBD", "090", 2, "Solomon Islands Dollar", ""); }
  if i == 54 { return _mk_row("SCR", "690", 2, "Seychelles Rupee", ""); }
  if i == 55 { return _mk_row("SDG", "938", 2, "Sudanese Pound", ""); }
  if i == 56 { return _mk_row("SEK", "752", 2, "Swedish Krona", ""); }
  if i == 57 { return _mk_row("SGD", "702", 2, "Singapore Dollar", "S$"); }
  if i == 58 { return _mk_row("SHP", "654", 2, "Saint Helena Pound", ""); }
  if i == 59 { return _mk_row("SLE", "925", 2, "Leone", ""); }
  if i == 60 { return _mk_row("SOS", "706", 2, "Somali Shilling", ""); }
  if i == 61 { return _mk_row("SRD", "968", 2, "Surinam Dollar", ""); }
  if i == 62 { return _mk_row("SSP", "728", 2, "South Sudanese Pound", ""); }
  if i == 63 { return _mk_row("STN", "930", 2, "Dobra", ""); }
  if i == 64 { return _mk_row("SVC", "222", 2, "El Salvador Colon", ""); }
  if i == 65 { return _mk_row("SYP", "760", 2, "Syrian Pound", ""); }
  return _missing();
}

// Rows 132..164 (SZL..ZWG).
fn _bank_c(i: Int) -> Currency {
  if i == 0 { return _mk_row("SZL", "748", 2, "Lilangeni", ""); }
  if i == 1 { return _mk_row("THB", "764", 2, "Baht", "฿"); }
  if i == 2 { return _mk_row("TJS", "972", 2, "Somoni", ""); }
  if i == 3 { return _mk_row("TMT", "934", 2, "Turkmenistan New Manat", ""); }
  if i == 4 { return _mk_row("TND", "788", 3, "Tunisian Dinar", ""); }
  if i == 5 { return _mk_row("TOP", "776", 2, "Pa'anga", ""); }
  if i == 6 { return _mk_row("TRY", "949", 2, "Turkish Lira", "₺"); }
  if i == 7 { return _mk_row("TTD", "780", 2, "Trinidad and Tobago Dollar", ""); }
  if i == 8 { return _mk_row("TWD", "901", 2, "New Taiwan Dollar", ""); }
  if i == 9 { return _mk_row("TZS", "834", 2, "Tanzanian Shilling", ""); }
  if i == 10 { return _mk_row("UAH", "980", 2, "Hryvnia", "₴"); }
  if i == 11 { return _mk_row("UGX", "800", 0, "Uganda Shilling", ""); }
  if i == 12 { return _mk_row("USD", "840", 2, "US Dollar", "$"); }
  if i == 13 { return _mk_row("USN", "997", 2, "US Dollar (Next day)", ""); }
  if i == 14 { return _mk_row("UYI", "940", 0, "Uruguay Peso en Unidades Indexadas (UI)", ""); }
  if i == 15 { return _mk_row("UYU", "858", 2, "Peso Uruguayo", "$U"); }
  if i == 16 { return _mk_row("UYW", "927", 4, "Unidad Previsional", ""); }
  if i == 17 { return _mk_row("UZS", "860", 2, "Uzbekistan Sum", ""); }
  if i == 18 { return _mk_row("VED", "926", 2, "Bolívar Soberano (VED)", ""); }
  if i == 19 { return _mk_row("VES", "928", 2, "Bolívar Soberano", ""); }
  if i == 20 { return _mk_row("VND", "704", 0, "Dong", "₫"); }
  if i == 21 { return _mk_row("VUV", "548", 0, "Vatu", ""); }
  if i == 22 { return _mk_row("WST", "882", 2, "Tala", ""); }
  if i == 23 { return _mk_row("XAD", "396", 2, "Arab Accounting Dinar", ""); }
  if i == 24 { return _mk_row("XAF", "950", 0, "CFA Franc BEAC", ""); }
  if i == 25 { return _mk_row("XCD", "951", 2, "East Caribbean Dollar", ""); }
  if i == 26 { return _mk_row("XCG", "532", 2, "Caribbean Guilder", ""); }
  if i == 27 { return _mk_row("XOF", "952", 0, "CFA Franc BCEAO", ""); }
  if i == 28 { return _mk_row("XPF", "953", 0, "CFP Franc", ""); }
  if i == 29 { return _mk_row("YER", "886", 2, "Yemeni Rial", ""); }
  if i == 30 { return _mk_row("ZAR", "710", 2, "Rand", ""); }
  if i == 31 { return _mk_row("ZMW", "967", 2, "Zambian Kwacha", ""); }
  if i == 32 { return _mk_row("ZWG", "924", 2, "Zimbabwe Gold", ""); }
  return _missing();
}

// Row dispatch. `i` outside 0.._CUR_COUNT-1 yields the _missing sentinel
// (exponent -1, empty alpha).
fn _row(i: Int) -> Currency {
  if i < 0 { return _missing(); }
  if i < 66 { return _bank_a(i); }
  if i < 132 { return _bank_b(i - 66); }
  if i < _CUR_COUNT { return _bank_c(i - 132); }
  return _missing();
}

// Index of the row whose alpha equals `code` ASCII-case-insensitively, or -1.
// Callers validate the 3-letter shape first.
fn _find_by_alpha(code: Str) -> Int {
  var i = 0;
  while i < _CUR_COUNT {
    let c = _row(i);
    let a = c.alpha;
    if _eq_ci(a, code) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Index of the row whose numeric code equals `code`, or -1. Callers validate
// the 3-digit shape first.
fn _find_by_numeric(code: Str) -> Int {
  var i = 0;
  while i < _CUR_COUNT {
    let c = _row(i);
    let n = c.numeric;
    if compare.str_compare(n, code) == 0 { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Index of the row whose English name equals `name` case-insensitively, or -1.
fn _find_by_name(name: Str) -> Int {
  var i = 0;
  while i < _CUR_COUNT {
    let c = _row(i);
    let nm = c.name;
    if _eq_ci(nm, name) { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Index of the first row whose symbol equals `sym` byte-for-byte, or -1.
fn _find_by_symbol(sym: Str) -> Int {
  var i = 0;
  while i < _CUR_COUNT {
    let c = _row(i);
    let s = c.symbol;
    if compare.str_compare(s, sym) == 0 { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// ---------------------------------------------------------------------------
// Public API -- table access and lookups
// ---------------------------------------------------------------------------

/// Number of currency rows in the embedded table (the parse/format range is
/// 0 .. count-1).
/// Returns: 165 for the documented 2026-09-17 cut-off.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_currency_count() -> Int {
  return _CUR_COUNT;
}

/// Row of the embedded table by index.
/// Params: index - 0 .. l10n_currency_count()-1.
/// Returns: Ok(Currency) for an in-range index; Err("l10n-currency: index out
/// of range: <index>") otherwise.
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_currency_at(index: Int) -> Result[Currency, Str] {
  if index < 0 {
    return _cur_err("l10n-currency: index out of range: " + convert.int_to_string(index));
  }
  if index >= _CUR_COUNT {
    return _cur_err("l10n-currency: index out of range: " + convert.int_to_string(index));
  }
  let c = _row(index);
  if c.exponent < 0 {
    return _cur_err("l10n-currency: index out of range: " + convert.int_to_string(index));
  }
  return _cur_ok(c);
}

/// Look up a currency by its three-letter alpha code.
/// Params: code - exactly three ASCII letters; case-insensitive.
/// Returns: Ok(Currency); Err("l10n-currency: bad currency code: <code>")
/// when `code` is not three ASCII letters, or
/// Err("l10n-currency: unknown currency: <code>") when it is well formed but
/// not in the table (including every N.A. code of the documented cut-off).
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 165 rows).
pub fn l10n_currency_by_alpha(code: Str) -> Result[Currency, Str] {
  if !_is_alpha3(code) {
    return _cur_err("l10n-currency: bad currency code: " + code);
  }
  let idx = _find_by_alpha(code);
  if idx < 0 {
    return _cur_err("l10n-currency: unknown currency: " + code);
  }
  let c = _row(idx);
  if c.exponent < 0 {
    return _cur_err("l10n-currency: unknown currency: " + code);
  }
  return _cur_ok(c);
}

/// Look up a currency by its numeric code.
/// Params: code - exactly three ASCII digits, zero-padded ("008", not "8").
/// Returns: Ok(Currency); Err("l10n-currency: bad numeric code: <code>") for
/// any other shape, or Err("l10n-currency: unknown numeric code: <code>")
/// when no row carries digits (includes "999" / XXX and "959" / XAU, both
/// outside the cut-off).
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 165 rows).
pub fn l10n_currency_by_numeric(code: Str) -> Result[Currency, Str] {
  if !_is_numeric3(code) {
    return _cur_err("l10n-currency: bad numeric code: " + code);
  }
  let idx = _find_by_numeric(code);
  if idx < 0 {
    return _cur_err("l10n-currency: unknown numeric code: " + code);
  }
  let c = _row(idx);
  if c.exponent < 0 {
    return _cur_err("l10n-currency: unknown numeric code: " + code);
  }
  return _cur_ok(c);
}

/// Look up a currency by its English ISO name.
/// Params: name - the full name as spelled in the table; ASCII case is
/// ignored, accented bytes must match exactly.
/// Returns: Ok(Currency); Err("l10n-currency: unknown currency name: <name>")
/// when no row matches (the empty string is such an error; table names are
/// unique except that VED is "Bolívar Soberano (VED)" while VES is
/// "Bolívar Soberano").
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 165 rows).
pub fn l10n_currency_by_name(name: Str) -> Result[Currency, Str] {
  if name.len() == 0 {
    return _cur_err("l10n-currency: unknown currency name: " + name);
  }
  let idx = _find_by_name(name);
  if idx < 0 {
    return _cur_err("l10n-currency: unknown currency name: " + name);
  }
  let c = _row(idx);
  if c.exponent < 0 {
    return _cur_err("l10n-currency: unknown currency name: " + name);
  }
  return _cur_ok(c);
}

/// Look up a currency by its common symbol.
/// Params: symbol - the symbol exactly as stored ("$", "€", "£", "¥", ...).
/// Returns: Ok(Currency) for the first row whose symbol matches byte-for-byte;
/// Err("l10n-currency: bad symbol: ") for the empty string, or
/// Err("l10n-currency: unknown currency symbol: <symbol>") when no row matches.
/// Only prefix symbols are stored; the table keeps symbols unique, so the
/// first-match rule is not currently reachable ambiguity.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 165 rows).
pub fn l10n_currency_by_symbol(symbol: Str) -> Result[Currency, Str] {
  if symbol.len() == 0 {
    return _cur_err("l10n-currency: bad symbol: " + symbol);
  }
  let idx = _find_by_symbol(symbol);
  if idx < 0 {
    return _cur_err("l10n-currency: unknown currency symbol: " + symbol);
  }
  let c = _row(idx);
  if c.exponent < 0 {
    return _cur_err("l10n-currency: unknown currency symbol: " + symbol);
  }
  return _cur_ok(c);
}

/// Validity check by alpha code.
/// Params: code - candidate alpha code.
/// Returns: true iff l10n_currency_by_alpha accepts `code` (case-insensitive).
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn l10n_currency_is_valid(code: Str) -> Bool {
  match l10n_currency_by_alpha(code) {
    Ok(c) => { return true; },
    Err(e) => { return false; },
  }
  return false;
}

/// Cross-check helper: does the alpha code resolve to exactly this numeric
/// code?
/// Params: alpha - three-letter code (case-insensitive); numeric - the
/// candidate zero-padded three-digit numeric code.
/// Returns: true iff `alpha` is in the table and its row's numeric field
/// equals `numeric` byte-for-byte; false for a malformed alpha, a malformed
/// numeric, an unknown alpha, or a mismatched pair.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn l10n_currency_cross_check(alpha: Str, numeric: Str) -> Bool {
  if !_is_alpha3(alpha) { return false; }
  if !_is_numeric3(numeric) { return false; }
  let idx = _find_by_alpha(alpha);
  if idx < 0 { return false; }
  let c = _row(idx);
  let n = c.numeric;
  return compare.str_compare(n, numeric) == 0;
}

// ---------------------------------------------------------------------------
// Public API -- Money accessors
// ---------------------------------------------------------------------------

/// Alpha code carried by an amount.
pub fn l10n_currency_money_alpha(m: &Money) -> Str {
  return m.alpha;
}

/// Signed minor-unit value of an amount.
pub fn l10n_currency_money_minor(m: &Money) -> Int {
  return m.minor;
}

/// Minor-unit exponent captured when the amount was parsed.
pub fn l10n_currency_money_exponent(m: &Money) -> Int {
  return m.exponent;
}

// ---------------------------------------------------------------------------
// Public API -- parsing
// ---------------------------------------------------------------------------

/// Parse a localized money text into exact minor units.
/// Params: text - the amount text; cur - the target currency (exponent,
/// symbol and alpha come from here); decimal_sep - the exact string that
/// marks the fraction boundary (".", ",", ...); group_sep - the exact string
/// ignored as a thousands separator (",", ".", " ", ...); an empty
/// group_sep disables grouping entirely.
/// Grammar: optional leading '+' or '-', then an optional currency prefix
/// (cur.symbol verbatim, or cur.alpha case-insensitively), optional ASCII
/// spaces, then ASCII digits, group_sep and at most one decimal_sep. The
/// integer part may be empty when a fraction is present (".5"); a trailing
/// decimal_sep yields zero fraction digits. At most cur.exponent fraction
/// digits are accepted; every digit beyond that is an error. "-0" parses to
/// the non-negative 0. No floats are used at any point.
/// Returns: Ok(Money) with minor = value * 10^cur.exponent; Err is the
/// offset-carrying catalog of SPEC.md ("... at byte <n>"), and
/// Err("l10n-currency: empty input") for "".
/// Error case: empty input, no digits, unexpected character, multiple
/// decimal separators, too many decimals, magnitude overflow.
/// Complexity: O(len(text)).
pub fn l10n_currency_parse_amount(text: Str, cur: &Currency, decimal_sep: Str, group_sep: Str) -> Result[Money, Str] {
  let n = text.len();
  if n == 0 {
    return _money_err("l10n-currency: empty input");
  }
  let exp: Int = cur.exponent;
  let code: Str = cur.alpha;
  let sym: Str = cur.symbol;
  if exp < 0 {
    return _money_err("l10n-currency: bad currency: " + code);
  }
  var i = 0;
  var neg = false;
  let first = string.byte_at(text, 0);
  if first == _CUR_MINUS {
    neg = true;
    i = 1;
  } elif first == _CUR_PLUS {
    i = 1;
  }
  if sym.len() > 0 && _matches_at(text, i, sym) {
    i = i + sym.len();
  } elif _matches_ci_at(text, i, code) {
    i = i + code.len();
  }
  while i < n && string.byte_at(text, i) == _CUR_SPACE {
    i = i + 1;
  }
  var int_mag: Int = 0;
  var frac_mag: Int = 0;
  var frac_digits = 0;
  var seen_sep = false;
  var seen_digit = false;
  while i < n {
    let b = string.byte_at(text, i);
    if _is_digit(b) {
      let d = ((b as Int) & 255) - 48;
      if seen_sep {
        if frac_digits >= exp {
          return _money_err("l10n-currency: too many decimals at byte " + convert.int_to_string(i));
        }
        frac_mag = frac_mag * 10 + d;
        frac_digits = frac_digits + 1;
      } else {
        if int_mag > _CUR_INT_MAX_DIV10 {
          return _money_err("l10n-currency: number too large at byte " + convert.int_to_string(i));
        }
        if int_mag == _CUR_INT_MAX_DIV10 && d > _CUR_INT_MAX_LAST_DIGIT {
          return _money_err("l10n-currency: number too large at byte " + convert.int_to_string(i));
        }
        int_mag = int_mag * 10 + d;
      }
      seen_digit = true;
      i = i + 1;
    } elif decimal_sep.len() > 0 && _matches_at(text, i, decimal_sep) {
      if seen_sep {
        return _money_err("l10n-currency: multiple decimal separators at byte " + convert.int_to_string(i));
      }
      seen_sep = true;
      i = i + decimal_sep.len();
    } elif group_sep.len() > 0 && _matches_at(text, i, group_sep) {
      i = i + group_sep.len();
    } else {
      return _money_err("l10n-currency: unexpected character at byte " + convert.int_to_string(i));
    }
  }
  if !seen_digit {
    return _money_err("l10n-currency: no digits at byte " + convert.int_to_string(n));
  }
  var value = int_mag;
  var m = 0;
  while m < exp && value != 0 {
    if value > _CUR_INT_MAX_DIV10 {
      return _money_err("l10n-currency: number too large at byte " + convert.int_to_string(n));
    }
    value = value * 10;
    m = m + 1;
  }
  var frac_scaled = frac_mag;
  var k = frac_digits;
  while k < exp {
    frac_scaled = frac_scaled * 10;
    k = k + 1;
  }
  if value > _CUR_INT_MAX - frac_scaled {
    return _money_err("l10n-currency: number too large at byte " + convert.int_to_string(n));
  }
  value = value + frac_scaled;
  if neg && value != 0 {
    value = 0 - value;
  }
  let out = Money{ alpha: code; minor: value; exponent: exp };
  return _money_ok(out);
}

/// Parse with the currency given by alpha code instead of a Currency value.
/// Params: text / decimal_sep / group_sep as for l10n_currency_parse_amount;
/// alpha - the currency code, resolved with l10n_currency_by_alpha.
/// Returns: Ok(Money), or the lookup error for a malformed or unknown alpha
/// (Err("l10n-currency: ...")), or the l10n_currency_parse_amount error.
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn l10n_currency_parse_amount_code(text: Str, alpha: Str, decimal_sep: Str, group_sep: Str) -> Result[Money, Str] {
  let rc = l10n_currency_by_alpha(alpha);
  match rc {
    Ok(c) => {
      let cur = c;
      return l10n_currency_parse_amount(text, &cur, decimal_sep, group_sep);
    },
    Err(e) => { return _money_err(e); },
  }
  return _money_err("l10n-currency: unknown currency: " + alpha);
}

// ---------------------------------------------------------------------------
// Public API -- formatting
// ---------------------------------------------------------------------------

/// Format an amount with its currency.
/// Params: m - the amount; group_sep - thousands separator ("" disables
/// grouping); decimal_sep - fraction separator; use_symbol - true selects
/// the currency's symbol when the table carries one (falling back to the
/// alpha code plus one space), false always renders the alpha code plus one
/// space; paren_negative - true wraps negative amounts in parentheses,
/// false prefixes them with '-'. The exponent used is the table exponent of
/// m.alpha (Money.exponent is informational).
/// Returns: Ok(text): "USD 1,234.56", "$1,234.56", "(USD 1,234.56)",
/// "-$1,234.56", "JPY 1,234" (exponent 0, no separator), "BHD 1.234"
/// (exponent 3), "CLF 1.2345" (exponent 4), "USD 0.05" (zero padding).
/// Err("l10n-currency: ...") when m.alpha is malformed or unknown.
/// Error case: see above.
/// Complexity: O(digits).
pub fn l10n_currency_format_amount(m: &Money, group_sep: Str, decimal_sep: Str, use_symbol: Bool, paren_negative: Bool) -> Result[Str, Str] {
  let alpha: Str = m.alpha;
  let rc = l10n_currency_by_alpha(alpha);
  match rc {
    Ok(c) => {
      let minor: Int = m.minor;
      let exp: Int = c.exponent;
      let code: Str = c.alpha;
      var digits = _abs_digits(minor);
      var body = "";
      if exp > 0 {
        while digits.len() <= exp {
          digits = "0" + digits;
        }
        let split = digits.len() - exp;
        let int_digits = string.str_slice(digits, 0, split);
        let frac_digits = string.str_slice(digits, split, digits.len());
        body = _group_digits(int_digits, group_sep) + decimal_sep + frac_digits;
      } else {
        body = _group_digits(digits, group_sep);
      }
      var prefix = code + " ";
      if use_symbol {
        let s: Str = c.symbol;
        if s.len() > 0 {
          prefix = s;
        }
      }
      if minor < 0 {
        if paren_negative {
          return _str_ok("(" + prefix + body + ")");
        }
        return _str_ok("-" + prefix + body);
      }
      return _str_ok(prefix + body);
    },
    Err(e) => { return _str_err(e); },
  }
  return _str_err("l10n-currency: unknown currency: " + alpha);
}

// ---------------------------------------------------------------------------
// Public API -- rounding
// ---------------------------------------------------------------------------

/// Rescale a scaled integer to fewer fraction digits, rounding halves away
/// from zero.
/// Params: scaled - the scaled value; from_decimals - its current fraction
/// digit count; to_decimals - the wanted fraction digit count. Both counts
/// clamp to >= 0. When to_decimals >= from_decimals the value is already
/// exact and is returned unchanged.
/// Returns: the half-away-from-zero rounding of scaled / 10^(from-to). For
/// negative values "half up" is applied to the magnitude, so -25 at one
/// decimal rounds to -3 (not -2): the sign is handled explicitly instead of
/// relying on truncating division. 19-digit drops saturate exactly like
/// xiom.l10n.number: a signed 1 when the magnitude is at least 5*10^18,
/// else 0; larger drops yield 0.
/// Examples: (12345, 2, 0) -> 123; (12355, 2, 0) -> 124; (-12355, 2, 0) ->
/// -124; (25, 1, 0) -> 3; (-25, 1, 0) -> -3.
/// Error case: none.
/// Complexity: O(min(from - to, 19)).
pub fn l10n_currency_round_half_up(scaled: Int, from_decimals: Int, to_decimals: Int) -> Int {
  var from_d = from_decimals;
  if from_d < 0 {
    from_d = 0;
  }
  var to_d = to_decimals;
  if to_d < 0 {
    to_d = 0;
  }
  if to_d >= from_d {
    return scaled;
  }
  let drop = from_d - to_d;
  if drop > 19 {
    return 0;
  }
  if drop == 19 {
    let digits = _abs_digits(scaled);
    if digits.len() < 19 {
      return 0;
    }
    let lead = string.byte_at(digits, 0);
    if lead < _CUR_ZERO + 5u8 {
      return 0;
    }
    if scaled < 0 {
      return 0 - 1;
    }
    return 1;
  }
  var div: Int = 1;
  var k = 0;
  while k < drop {
    div = div * 10;
    k = k + 1;
  }
  let q = scaled / div;
  let r = scaled % div;
  if scaled >= 0 {
    if r * 2 >= div {
      return q + 1;
    }
    return q;
  }
  if (0 - r) * 2 >= div {
    return q - 1;
  }
  return q;
}

/// Round an extra-precision amount down to a currency's minor units.
/// Params: scaled - the scaled value; from_decimals - its current fraction
/// digit count (>= 0 after clamping; must be >= cur.exponent); cur - the
/// target currency.
/// Returns: Ok(minor) with the half-away-from-zero result at cur.exponent
/// digits; Err("l10n-currency: scale up not supported: from <a> to <b>") when
/// from_decimals is below cur.exponent (scaling up is a multiplication the
/// caller must do deliberately, and it can overflow).
/// Error case: see above.
/// Complexity: O(min(from - to, 19)).
pub fn l10n_currency_round_to_currency(scaled: Int, from_decimals: Int, cur: &Currency) -> Result[Int, Str] {
  var from_d = from_decimals;
  if from_d < 0 {
    from_d = 0;
  }
  let exp: Int = cur.exponent;
  if exp < 0 {
    return _int_err("l10n-currency: bad currency: " + cur.alpha);
  }
  if from_d < exp {
    return _int_err("l10n-currency: scale up not supported: from " + convert.int_to_string(from_d) + " to " + convert.int_to_string(exp));
  }
  return _int_ok(l10n_currency_round_half_up(scaled, from_d, exp));
}
