// XIOM -- xiom.rtc: real-time clock register codecs (BCD, DS1307, PCF8563, civil dates)
// Port task: greenfield pure-XIOM port (no FFI) of the register codecs of two
// classic I2C clock-calendar chips plus the BCD and civil-date arithmetic
// they need. Codec only: register buffers in memory, no bus transactions, no
// timing, no device state.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// DS1307 (7 registers, 0x00..0x06: seconds, minutes, hours, day, date,
// month, year). Full tables in SPEC.md:
//   * seconds bit 7 = CH (clock halt: 1 = oscillator off, the time is frozen
//     and the other registers keep their last value);
//   * hours bit 6 = 12/24 mode; in 12-hour mode bit 5 = PM (1 = PM) and bits
//     4-0 hold 1..12 BCD; in 24-hour mode bit 5 is the 20-hour bit and bits
//     5-0 hold 0..23 BCD;
//   * weekday 1..7 (user-defined meaning), date 1..31, month 1..12, year
//     0..99; there is no century register, so a full year is YearBase + year;
//   * register read order: minutes, hours, weekday, date, month, year, then
//     seconds.
//
// PCF8563 (9 registers, 0x00..0x08: control 1, control 2, seconds, minutes,
// hours, date, weekday, month/century, year):
//   * control 1 bit 5 = STOP (clock halted); control 2 bits 7-5 are reserved
//     and must be 0;
//   * seconds bit 7 = VL (voltage low: the integrity of the time is not
//     guaranteed);
//   * hours bit 7 = 12/24 mode; in 12-hour mode bit 6 = PM (1 = PM) and bits
//     5-0 hold 1..12 BCD; in 24-hour mode bit 6 must be 0 and bits 5-0 hold
//     0..23 BCD;
//   * weekday 0..6, date 1..31, month 1..12, year 0..99;
//   * month bit 7 = C century flag: full year = YearBase + 100 * century +
//     year;
//   * register read order: control 1, control 2, minutes, hours, date,
//     weekday, month, year, then seconds.
//
// Register read order rationale: a clock keeps counting while its registers
// are read, so a single sequential burst can tear at the minute boundary
// (minutes read as 59, then seconds read as 00 on the far side of the
// rollover, reporting a minute that never existed). Sampling seconds last
// confines any such rollover to the final field, where a caller can detect
// it by re-reading seconds and discarding the snapshot when the value
// changed. xiom.rtc pins both chip orders (rtc_ds1307_read_order /
// rtc_pcf8563_read_order) and exposes the civil-date/epoch math needed to
// reason about the sampled fields.
//
// Cross-field validation: a register frame is rejected when the fields are
// impossible together (month 13, Feb 30, hour 24, weekday out of range), not
// only when one field is malformed. Impossible Gregorian dates are checked
// against the leap-year rule with full year = year base + century
// contribution (see the constants below).
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[fn] dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results inside other functions
//     miscompiles);
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic;
//   * bit fields are extracted with truncating division and modulo, never a
//     shift on a value that could carry the sign bit, and day arithmetic
//     that can go negative goes through `_floor_div`;
//   * no Vec[Float64] and no floating-point math anywhere: the epoch
//     conversions are pure integer arithmetic (Howard Hinnant's civil-date
//     algorithms, adapted to truncating division);
//   * struct fields are bound to typed locals before being borrowed.

module xiom.rtc

use xiom.convert;

// --------------------------------------------------
//  Register maps, bit masks and year bases
// --------------------------------------------------

/// DS1307 seconds register offset (bit 7 = CH clock-halt). Complexity: O(1).
pub const RTC_DS1307_REG_SECONDS: Int = 0;
/// DS1307 minutes register offset. Complexity: O(1).
pub const RTC_DS1307_REG_MINUTES: Int = 1;
/// DS1307 hours register offset. Complexity: O(1).
pub const RTC_DS1307_REG_HOURS: Int = 2;
/// DS1307 day-of-week register offset. Complexity: O(1).
pub const RTC_DS1307_REG_WEEKDAY: Int = 3;
/// DS1307 date register offset. Complexity: O(1).
pub const RTC_DS1307_REG_DATE: Int = 4;
/// DS1307 month register offset. Complexity: O(1).
pub const RTC_DS1307_REG_MONTH: Int = 5;
/// DS1307 year register offset. Complexity: O(1).
pub const RTC_DS1307_REG_YEAR: Int = 6;
/// DS1307 frame length in registers. Complexity: O(1).
pub const RTC_DS1307_REG_COUNT: Int = 7;
/// DS1307 full-year base: the chip stores no century, so full year =
/// RTC_DS1307_YEAR_BASE + year. Complexity: O(1).
pub const RTC_DS1307_YEAR_BASE: Int = 2000;

/// PCF8563 control 1 register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_CONTROL1: Int = 0;
/// PCF8563 control 2 register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_CONTROL2: Int = 1;
/// PCF8563 seconds register offset (bit 7 = VL voltage-low). Complexity: O(1).
pub const RTC_PCF8563_REG_SECONDS: Int = 2;
/// PCF8563 minutes register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_MINUTES: Int = 3;
/// PCF8563 hours register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_HOURS: Int = 4;
/// PCF8563 date register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_DATE: Int = 5;
/// PCF8563 day-of-week register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_WEEKDAY: Int = 6;
/// PCF8563 month/century register offset (bit 7 = C century flag).
/// Complexity: O(1).
pub const RTC_PCF8563_REG_MONTH: Int = 7;
/// PCF8563 year register offset. Complexity: O(1).
pub const RTC_PCF8563_REG_YEAR: Int = 8;
/// PCF8563 frame length in registers. Complexity: O(1).
pub const RTC_PCF8563_REG_COUNT: Int = 9;
/// PCF8563 full-year base: full year = RTC_PCF8563_YEAR_BASE + 100 *
/// century + year. Complexity: O(1).
pub const RTC_PCF8563_YEAR_BASE: Int = 2000;

/// DS1307 CH clock-halt bit (seconds bit 7). Complexity: O(1).
pub const RTC_DS1307_CH_BIT: Int = 128;
/// DS1307 12/24-hour mode bit (hours bit 6). Complexity: O(1).
pub const RTC_DS1307_12H_BIT: Int = 64;
/// DS1307 PM bit (hours bit 5 in 12-hour mode). Complexity: O(1).
pub const RTC_DS1307_PM_BIT: Int = 32;
/// PCF8563 VL voltage-low bit (seconds bit 7). Complexity: O(1).
pub const RTC_PCF8563_VL_BIT: Int = 128;
/// PCF8563 12/24-hour mode bit (hours bit 7). Complexity: O(1).
pub const RTC_PCF8563_12H_BIT: Int = 128;
/// PCF8563 PM bit (hours bit 6 in 12-hour mode). Complexity: O(1).
pub const RTC_PCF8563_PM_BIT: Int = 64;
/// PCF8563 C century flag (month bit 7). Complexity: O(1).
pub const RTC_PCF8563_CENTURY_BIT: Int = 128;
/// PCF8563 STOP clock-halt bit (control 1 bit 5). Complexity: O(1).
pub const RTC_PCF8563_STOP_BIT: Int = 32;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// One clock-calendar sample as decoded from a device frame.
///
/// `year` is the two-digit year register value (0..99); `century` is the
/// PCF8563 century flag (0 or 1; the DS1307 has no century register and its
/// decoder always reports 0). `hours` keeps the register's own
/// representation: 0..23 with hour12 = false in 24-hour mode, 1..12 with
/// hour12 = true and the `pm` flag in 12-hour mode. `halted` is the DS1307
/// CH oscillator-halt bit or the PCF8563 control 1 STOP bit. The wire-level
/// VL flag of the PCF8563 lives on Pcf8563Time, not here, because it is
/// per-read integrity information rather than a time field.
pub type RtcTime = {
  year: Int;
  month: Int;
  day: Int;
  weekday: Int;
  hours: Int;
  minutes: Int;
  seconds: Int;
  hour12: Bool;
  pm: Bool;
  century: Int;
  halted: Bool;
}

/// A PCF8563 frame: the two control registers, the VL integrity flag and the
/// decoded time. On encode, control 1 keeps its preserved bits except STOP
/// (bit 5), which is driven by `time.halted`; control 2 bits 7-5 must be
/// zero.
pub type Pcf8563Time = {
  control1: Int;
  control2: Int;
  vl: Bool;
  time: RtcTime;
}

/// A Gregorian calendar date. Complexity: O(1).
pub type CivilDate = {
  year: Int;
  month: Int;
  day: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[RtcTime, Str].
fn _ok_time(v: RtcTime) -> Result[RtcTime, Str] {
  return Ok(v);
}

// Err(m) for Result[RtcTime, Str].
fn _err_time(m: Str) -> Result[RtcTime, Str] {
  return Err(m);
}

// Ok(v) for Result[Pcf8563Time, Str].
fn _ok_pcf(v: Pcf8563Time) -> Result[Pcf8563Time, Str] {
  return Ok(v);
}

// Err(m) for Result[Pcf8563Time, Str].
fn _err_pcf(m: Str) -> Result[Pcf8563Time, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Packed BCD of a caller-validated value 0..99: tens in the high nibble,
// ones in the low nibble.
fn _bcd_value(v: Int) -> Int {
  return (v / 10) * 16 + (v % 10);
}

// Decode the packed BCD byte `b` and range-check the decimal value against
// lo..hi. Two messages: an invalid nibble and an out-of-range value.
fn _bcd_range(b: Int, what: Str, lo: Int, hi: Int) -> Result[Int, Str] {
  if b / 16 > 9 || b % 16 > 9 {
    return _err_int(what + " register " + convert.int_to_string(b) + " is not valid BCD");
  }
  let v = (b / 16) * 10 + (b % 16);
  if v < lo || v > hi {
    return _err_int(what + " value " + convert.int_to_string(v) + " out of range " + convert.int_to_string(lo) + ".." + convert.int_to_string(hi));
  }
  return _ok_int(v);
}

// `n` zero-padded to two decimal digits (for date error messages).
fn _two(n: Int) -> Str {
  if n < 10 {
    return "0" + convert.int_to_string(n);
  }
  return convert.int_to_string(n);
}

// Floor of a / b for b > 0: truncating division corrected when the
// truncating remainder is negative (trap: / and % truncate toward zero).
fn _floor_div(a: Int, b: Int) -> Int {
  let q = a / b;
  let r = a % b;
  if r < 0 {
    return q - 1;
  }
  return q;
}

// --------------------------------------------------
//  BCD fields
// --------------------------------------------------

/// Encode a decimal value 0..99 as packed BCD (tens digit in the high
/// nibble, ones digit in the low nibble).
///
/// Err("rtc.bcd: value N out of range 0..99") when value is negative or
/// greater than 99.
/// Complexity: O(1).
pub fn rtc_bcd_encode(value: Int) -> Result[Int, Str] {
  if value < 0 || value > 99 {
    return _err_int("rtc.bcd: value " + convert.int_to_string(value) + " out of range 0..99");
  }
  return _ok_int(_bcd_value(value));
}

/// Decode a packed BCD byte; both nibbles must be decimal digits (0..9).
///
/// Err("rtc.bcd: byte N out of range 0..255") when byte is outside 0..255;
/// Err("rtc.bcd: byte N is not valid BCD") when either nibble exceeds 9.
/// Complexity: O(1).
pub fn rtc_bcd_decode(byte: Int) -> Result[Int, Str] {
  if byte < 0 || byte > 255 {
    return _err_int("rtc.bcd: byte " + convert.int_to_string(byte) + " out of range 0..255");
  }
  let hi = byte / 16;
  let lo = byte % 16;
  if hi > 9 || lo > 9 {
    return _err_int("rtc.bcd: byte " + convert.int_to_string(byte) + " is not valid BCD");
  }
  return _ok_int(hi * 10 + lo);
}

/// True when `byte` is in 0..255 and both of its nibbles are decimal digits.
/// Complexity: O(1).
pub fn rtc_bcd_is_valid(byte: Int) -> Bool {
  if byte < 0 || byte > 255 {
    return false;
  }
  if byte / 16 > 9 {
    return false;
  }
  if byte % 16 > 9 {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Civil dates and epoch days
// --------------------------------------------------

/// True when `year` is a leap year in the proleptic Gregorian calendar:
/// divisible by 4, except centuries, except 400-year centuries. So 2000 and
/// 2024 are leap, 1900 and 2100 are not.
/// Complexity: O(1).
pub fn rtc_is_leap(year: Int) -> Bool {
  if year % 4 != 0 {
    return false;
  }
  if year % 100 != 0 {
    return true;
  }
  if year % 400 != 0 {
    return false;
  }
  return true;
}

/// Days in `month` of `year` (28/29/30/31), or 0 when month is outside
/// 1..12. Complexity: O(1).
pub fn rtc_days_in_month(year: Int, month: Int) -> Int {
  if month < 1 || month > 12 {
    return 0;
  }
  if month == 2 {
    if rtc_is_leap(year) {
      return 29;
    }
    return 28;
  }
  if month == 4 || month == 6 || month == 9 || month == 11 {
    return 30;
  }
  return 31;
}

/// True when (year, month, day) is a real Gregorian date: month 1..12 and
/// day 1..days_in_month. Feb 30, Feb 29 in a common year, day 0 and month 13
/// are all false. Complexity: O(1).
pub fn rtc_is_valid_date(year: Int, month: Int, day: Int) -> Bool {
  let dim = rtc_days_in_month(year, month);
  if dim == 0 {
    return false;
  }
  if day < 1 || day > dim {
    return false;
  }
  return true;
}

/// True when (hours, minutes, seconds) is a real 24-hour clock time: hours
/// 0..23, minutes 0..59, seconds 0..59; hour 24 and second 60 are rejected.
/// Complexity: O(1).
pub fn rtc_is_valid_time(hours: Int, minutes: Int, seconds: Int) -> Bool {
  if hours < 0 || hours > 23 {
    return false;
  }
  if minutes < 0 || minutes > 59 {
    return false;
  }
  if seconds < 0 || seconds > 59 {
    return false;
  }
  return true;
}

/// Days from the UNIX epoch (1970-01-01 = day 0) to the Gregorian date
/// (year, month, day), for any year (negative years included) but only for
/// real dates.
///
/// Err("rtc: month N out of range 1..12") when month is outside 1..12;
/// Err("rtc: impossible date Y-M-D") when day is outside the month's range
/// (Feb 30, Feb 29 in a common year, day 0, ...).
/// Complexity: O(1).
pub fn rtc_days_from_civil(year: Int, month: Int, day: Int) -> Result[Int, Str] {
  if month < 1 || month > 12 {
    return _err_int("rtc: month " + convert.int_to_string(month) + " out of range 1..12");
  }
  let dim = rtc_days_in_month(year, month);
  if day < 1 || day > dim {
    return _err_int("rtc: impossible date " + convert.int_to_string(year) + "-" + _two(month) + "-" + _two(day));
  }
  var y = year;
  if month <= 2 {
    y = year - 1;
  }
  let era = _floor_div(y, 400);
  let yoe = y - era * 400;
  var mp = month + 9;
  if month > 2 {
    mp = month - 3;
  }
  let doy = (153 * mp + 2) / 5 + day - 1;
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return _ok_int(era * 146097 + doe - 719468);
}

/// Inverse of rtc_days_from_civil: the Gregorian date `days` after the UNIX
/// epoch, including dates before it (negative days).
/// Complexity: O(1).
pub fn rtc_civil_from_days(days: Int) -> CivilDate {
  let z = days + 719468;
  let era = _floor_div(z, 146097);
  let doe = z - era * 146097;
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  let y = yoe + era * 400;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let d = doy - (153 * mp + 2) / 5 + 1;
  var m = mp + 3;
  if mp >= 10 {
    m = mp - 9;
  }
  var yy = y;
  if m <= 2 {
    yy = y + 1;
  }
  return CivilDate{ year: yy; month: m; day: d; };
}

/// ISO day of week (1 = Monday .. 7 = Sunday) of the day `days` after the
/// UNIX epoch (1970-01-01 was a Thursday). Complexity: O(1).
pub fn rtc_weekday_from_days(days: Int) -> Int {
  var r = (days + 3) % 7;
  if r < 0 {
    r = r + 7;
  }
  return r + 1;
}

// --------------------------------------------------
//  12/24-hour conversion
// --------------------------------------------------

/// Convert a 12-hour clock reading to 24-hour hours: 12 AM -> 0, 12 PM ->
/// 12, 1..11 AM -> unchanged, 1..11 PM -> +12.
///
/// Err("rtc: 12-hour value N out of range 1..12") when hours is outside
/// 1..12. Complexity: O(1).
pub fn rtc_twelve_hour_to_24(hours: Int, pm: Bool) -> Result[Int, Str] {
  if hours < 1 || hours > 12 {
    return _err_int("rtc: 12-hour value " + convert.int_to_string(hours) + " out of range 1..12");
  }
  if pm {
    if hours == 12 {
      return _ok_int(12);
    }
    return _ok_int(hours + 12);
  }
  if hours == 12 {
    return _ok_int(0);
  }
  return _ok_int(hours);
}

/// 12-hour clock hours (1..12) of a 24-hour value: 0 -> 12 AM, 12 -> 12 PM,
/// 13 -> 1, 23 -> 11.
///
/// Err("rtc: hours N out of range 0..23") when hours is outside 0..23.
/// Complexity: O(1).
pub fn rtc_24_to_twelve_hours(hours: Int) -> Result[Int, Str] {
  if hours < 0 || hours > 23 {
    return _err_int("rtc: hours " + convert.int_to_string(hours) + " out of range 0..23");
  }
  var h = hours % 12;
  if h == 0 {
    h = 12;
  }
  return _ok_int(h);
}

/// True when a 24-hour value is PM in 12-hour notation (12..23).
///
/// Err("rtc: hours N out of range 0..23") when hours is outside 0..23.
/// Complexity: O(1).
pub fn rtc_24_to_twelve_pm(hours: Int) -> Result[Bool, Str] {
  if hours < 0 || hours > 23 {
    return _err_bool("rtc: hours " + convert.int_to_string(hours) + " out of range 0..23");
  }
  return _ok_bool(hours >= 12);
}

/// Full year of a sample: RTC_PCF8563_YEAR_BASE + 100 * century + year. Both
/// families share the 2000 year base, so this is also the full DS1307 year
/// (whose century is always 0). Complexity: O(1).
pub fn rtc_full_year(t: &RtcTime) -> Int {
  return RTC_PCF8563_YEAR_BASE + t.century * 100 + t.year;
}

// --------------------------------------------------
//  DS1307 (7 registers)
// --------------------------------------------------

// Validate the fields of `t` as a DS1307 sample. Century is ignored (the
// chip has no century register); the full year used for the impossible-date
// check is RTC_DS1307_YEAR_BASE + year.
fn _validate_ds1307(t: &RtcTime) -> Result[Unit, Str] {
  if t.year < 0 || t.year > 99 {
    return _err_unit("rtc.ds1307: year " + convert.int_to_string(t.year) + " out of range 0..99");
  }
  if t.month < 1 || t.month > 12 {
    return _err_unit("rtc.ds1307: month " + convert.int_to_string(t.month) + " out of range 1..12");
  }
  let fy = RTC_DS1307_YEAR_BASE + t.year;
  let dim = rtc_days_in_month(fy, t.month);
  if t.day < 1 || t.day > dim {
    return _err_unit("rtc.ds1307: impossible date " + convert.int_to_string(fy) + "-" + _two(t.month) + "-" + _two(t.day));
  }
  if t.weekday < 1 || t.weekday > 7 {
    return _err_unit("rtc.ds1307: weekday " + convert.int_to_string(t.weekday) + " out of range 1..7");
  }
  if t.minutes < 0 || t.minutes > 59 {
    return _err_unit("rtc.ds1307: minutes " + convert.int_to_string(t.minutes) + " out of range 0..59");
  }
  if t.seconds < 0 || t.seconds > 59 {
    return _err_unit("rtc.ds1307: seconds " + convert.int_to_string(t.seconds) + " out of range 0..59");
  }
  if t.hour12 {
    if t.hours < 1 || t.hours > 12 {
      return _err_unit("rtc.ds1307: 12-hour hours " + convert.int_to_string(t.hours) + " out of range 1..12");
    }
  } else {
    if t.hours < 0 || t.hours > 23 {
      return _err_unit("rtc.ds1307: hours " + convert.int_to_string(t.hours) + " out of range 0..23");
    }
    if t.pm {
      return _err_unit("rtc.ds1307: PM flag set in 24-hour mode");
    }
  }
  return _ok_unit();
}

/// Decode a DS1307 frame (seconds, minutes, hours, weekday, date, month,
/// year; bytes beyond the first 7 are ignored).
///
/// The decoded `hours` keeps the register representation: 0..23 with
/// hour12 = false in 24-hour mode, 1..12 with hour12 = true and the `pm`
/// flag in 12-hour mode. `halted` is the CH bit (seconds bit 7), which
/// freezes the clock independently of the decoded seconds value (bits 6-0).
/// `century` is always 0.
///
/// Validation order (first failure wins):
///   1. fewer than 7 bytes -> Err("rtc.ds1307: need 7 registers, have N");
///   2. seconds (bits 6-0): invalid BCD -> "rtc.ds1307 seconds register N
///      is not valid BCD"; value outside 0..59 -> "rtc.ds1307 seconds value
///      N out of range 0..59";
///   3. minutes, the same two messages;
///   4. hours: bit 7 set -> "rtc.ds1307 hours register N has reserved bits
///      set"; invalid BCD -> "rtc.ds1307 hours register N is not valid
///      BCD"; 24-hour value outside 0..23 -> "rtc.ds1307 hours value N out
///      of range 0..23"; 12-hour value outside 1..12 -> "rtc.ds1307
///      12-hour value N out of range 1..12";
///   5. weekday: bits 7-3 nonzero -> "rtc.ds1307 weekday register N has
///      reserved bits set"; value outside 1..7 -> "rtc.ds1307 weekday value
///      N out of range 1..7";
///   6. date: bits 7-6 nonzero (reserved), BCD, range 1..31;
///   7. month: bits 7-5 nonzero (reserved), BCD, range 1..12;
///   8. year: BCD, range 0..99;
///   9. the assembled date must exist (Feb 30, Feb 29 in a common year) ->
///      Err("rtc.ds1307: impossible date Y-M-D") with full year
///      RTC_DS1307_YEAR_BASE + year.
/// Complexity: O(1).
pub fn rtc_ds1307_decode(regs: &Vec[UInt8]) -> Result[RtcTime, Str] {
  if regs.len() < RTC_DS1307_REG_COUNT {
    return _err_time("rtc.ds1307: need " + convert.int_to_string(RTC_DS1307_REG_COUNT) + " registers, have " + convert.int_to_string(regs.len()));
  }
  let sb = _byte(regs, RTC_DS1307_REG_SECONDS);
  let halted = (sb / RTC_DS1307_CH_BIT) % 2 == 1;
  let sr = _bcd_range(sb % RTC_DS1307_CH_BIT, "rtc.ds1307 seconds", 0, 59);
  if !sr.is_ok {
    return _err_time(sr.error);
  }
  let seconds: Int = sr.value;
  let mr = _bcd_range(_byte(regs, RTC_DS1307_REG_MINUTES), "rtc.ds1307 minutes", 0, 59);
  if !mr.is_ok {
    return _err_time(mr.error);
  }
  let minutes: Int = mr.value;
  let hb = _byte(regs, RTC_DS1307_REG_HOURS);
  if hb / RTC_DS1307_CH_BIT != 0 {
    return _err_time("rtc.ds1307 hours register " + convert.int_to_string(hb) + " has reserved bits set");
  }
  var hour12 = false;
  var pm = false;
  var hours = 0;
  if (hb / RTC_DS1307_12H_BIT) % 2 == 1 {
    hour12 = true;
    pm = (hb / RTC_DS1307_PM_BIT) % 2 == 1;
    let hr = _bcd_range(hb % RTC_DS1307_PM_BIT, "rtc.ds1307 12-hour", 1, 12);
    if !hr.is_ok {
      return _err_time(hr.error);
    }
    hours = hr.value;
  } else {
    let hr2 = _bcd_range(hb % RTC_DS1307_12H_BIT, "rtc.ds1307 hours", 0, 23);
    if !hr2.is_ok {
      return _err_time(hr2.error);
    }
    hours = hr2.value;
  }
  let wb = _byte(regs, RTC_DS1307_REG_WEEKDAY);
  if wb / 8 != 0 {
    return _err_time("rtc.ds1307 weekday register " + convert.int_to_string(wb) + " has reserved bits set");
  }
  if wb < 1 || wb > 7 {
    return _err_time("rtc.ds1307 weekday value " + convert.int_to_string(wb) + " out of range 1..7");
  }
  let db = _byte(regs, RTC_DS1307_REG_DATE);
  if db / 64 != 0 {
    return _err_time("rtc.ds1307 date register " + convert.int_to_string(db) + " has reserved bits set");
  }
  let dr = _bcd_range(db % 64, "rtc.ds1307 date", 1, 31);
  if !dr.is_ok {
    return _err_time(dr.error);
  }
  let day: Int = dr.value;
  let mb = _byte(regs, RTC_DS1307_REG_MONTH);
  if mb / 32 != 0 {
    return _err_time("rtc.ds1307 month register " + convert.int_to_string(mb) + " has reserved bits set");
  }
  let mor = _bcd_range(mb % 32, "rtc.ds1307 month", 1, 12);
  if !mor.is_ok {
    return _err_time(mor.error);
  }
  let month: Int = mor.value;
  let yr = _bcd_range(_byte(regs, RTC_DS1307_REG_YEAR), "rtc.ds1307 year", 0, 99);
  if !yr.is_ok {
    return _err_time(yr.error);
  }
  let year: Int = yr.value;
  let fy = RTC_DS1307_YEAR_BASE + year;
  let dim = rtc_days_in_month(fy, month);
  if day > dim {
    return _err_time("rtc.ds1307: impossible date " + convert.int_to_string(fy) + "-" + _two(month) + "-" + _two(day));
  }
  return _ok_time(RtcTime{
    year: year;
    month: month;
    day: day;
    weekday: wb;
    hours: hours;
    minutes: minutes;
    seconds: seconds;
    hour12: hour12;
    pm: pm;
    century: 0;
    halted: halted;
  });
}

/// Encode a DS1307 frame from `t` (7 bytes in register order). The century
/// field is ignored (no century register); `halted` drives the CH bit, and
/// `hour12`/`pm` select the 12-hour representation.
///
/// Validation order (first failure wins): year 0..99, month 1..12, the date
/// must exist, weekday 1..7, minutes 0..59, seconds 0..59, then hours (1..12
/// with hour12, otherwise 0..23 with the PM flag rejected).
/// Err("rtc.ds1307: year N out of range 0..99"),
/// Err("rtc.ds1307: month N out of range 1..12"),
/// Err("rtc.ds1307: impossible date Y-M-D"),
/// Err("rtc.ds1307: weekday N out of range 1..7"),
/// Err("rtc.ds1307: minutes N out of range 0..59"),
/// Err("rtc.ds1307: seconds N out of range 0..59"),
/// Err("rtc.ds1307: 12-hour hours N out of range 1..12"),
/// Err("rtc.ds1307: hours N out of range 0..23"),
/// Err("rtc.ds1307: PM flag set in 24-hour mode").
/// Complexity: O(1).
pub fn rtc_ds1307_encode(t: &RtcTime) -> Result[Vec[UInt8], Str] {
  let vr = _validate_ds1307(t);
  if !vr.is_ok {
    return _err_bytes(vr.error);
  }
  var out = Vec[UInt8].new();
  var sb = _bcd_value(t.seconds);
  if t.halted {
    sb = sb + RTC_DS1307_CH_BIT;
  }
  out.push(sb as UInt8);
  out.push(_bcd_value(t.minutes) as UInt8);
  var hb = _bcd_value(t.hours);
  if t.hour12 {
    hb = hb + RTC_DS1307_12H_BIT;
    if t.pm {
      hb = hb + RTC_DS1307_PM_BIT;
    }
  }
  out.push(hb as UInt8);
  out.push(t.weekday as UInt8);
  out.push(_bcd_value(t.day) as UInt8);
  out.push(_bcd_value(t.month) as UInt8);
  out.push(_bcd_value(t.year) as UInt8);
  return _ok_bytes(out);
}

/// True when the DS1307 CH clock-halt bit (seconds bit 7) is set: the
/// oscillator is off and the time registers are frozen.
///
/// Err("rtc.ds1307: need 7 registers, have N").
/// Complexity: O(1).
pub fn rtc_ds1307_is_halted(regs: &Vec[UInt8]) -> Result[Bool, Str] {
  if regs.len() < RTC_DS1307_REG_COUNT {
    return _err_bool("rtc.ds1307: need " + convert.int_to_string(RTC_DS1307_REG_COUNT) + " registers, have " + convert.int_to_string(regs.len()));
  }
  let sb = _byte(regs, RTC_DS1307_REG_SECONDS);
  return _ok_bool((sb / RTC_DS1307_CH_BIT) % 2 == 1);
}

/// Copy of `regs` with the CH bit of the seconds register set (`halted`) or
/// cleared (running); every other bit and byte is preserved, so the copy
/// stays a valid frame when `regs` was one.
///
/// Err("rtc.ds1307: need 7 registers, have N").
/// Complexity: O(regs.len()).
pub fn rtc_ds1307_set_halted(regs: &Vec[UInt8], halted: Bool) -> Result[Vec[UInt8], Str] {
  if regs.len() < RTC_DS1307_REG_COUNT {
    return _err_bytes("rtc.ds1307: need " + convert.int_to_string(RTC_DS1307_REG_COUNT) + " registers, have " + convert.int_to_string(regs.len()));
  }
  var out = Vec[UInt8].new();
  var sb = _byte(regs, RTC_DS1307_REG_SECONDS) % RTC_DS1307_CH_BIT;
  if halted {
    sb = sb + RTC_DS1307_CH_BIT;
  }
  out.push(sb as UInt8);
  var i = 1;
  while i < regs.len() {
    out.push(regs[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// DS1307 register read order: minutes, hours, weekday, date, month, year,
/// then seconds last (see the module header for the read-tearing rule and
/// the constants for the register offsets). Complexity: O(1).
pub fn rtc_ds1307_read_order() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(RTC_DS1307_REG_MINUTES);
  v.push(RTC_DS1307_REG_HOURS);
  v.push(RTC_DS1307_REG_WEEKDAY);
  v.push(RTC_DS1307_REG_DATE);
  v.push(RTC_DS1307_REG_MONTH);
  v.push(RTC_DS1307_REG_YEAR);
  v.push(RTC_DS1307_REG_SECONDS);
  return v;
}

// --------------------------------------------------
//  PCF8563 (9 registers)
// --------------------------------------------------

// Validate the fields of `t` as a PCF8563 sample. The full year used for
// the impossible-date check is RTC_PCF8563_YEAR_BASE + 100 * century + year.
fn _validate_pcf8563(t: &RtcTime) -> Result[Unit, Str] {
  if t.year < 0 || t.year > 99 {
    return _err_unit("rtc.pcf8563: year " + convert.int_to_string(t.year) + " out of range 0..99");
  }
  if t.century < 0 || t.century > 1 {
    return _err_unit("rtc.pcf8563: century " + convert.int_to_string(t.century) + " out of range 0..1");
  }
  if t.month < 1 || t.month > 12 {
    return _err_unit("rtc.pcf8563: month " + convert.int_to_string(t.month) + " out of range 1..12");
  }
  let fy = RTC_PCF8563_YEAR_BASE + t.century * 100 + t.year;
  let dim = rtc_days_in_month(fy, t.month);
  if t.day < 1 || t.day > dim {
    return _err_unit("rtc.pcf8563: impossible date " + convert.int_to_string(fy) + "-" + _two(t.month) + "-" + _two(t.day));
  }
  if t.weekday < 0 || t.weekday > 6 {
    return _err_unit("rtc.pcf8563: weekday " + convert.int_to_string(t.weekday) + " out of range 0..6");
  }
  if t.minutes < 0 || t.minutes > 59 {
    return _err_unit("rtc.pcf8563: minutes " + convert.int_to_string(t.minutes) + " out of range 0..59");
  }
  if t.seconds < 0 || t.seconds > 59 {
    return _err_unit("rtc.pcf8563: seconds " + convert.int_to_string(t.seconds) + " out of range 0..59");
  }
  if t.hour12 {
    if t.hours < 1 || t.hours > 12 {
      return _err_unit("rtc.pcf8563: 12-hour hours " + convert.int_to_string(t.hours) + " out of range 1..12");
    }
  } else {
    if t.hours < 0 || t.hours > 23 {
      return _err_unit("rtc.pcf8563: hours " + convert.int_to_string(t.hours) + " out of range 0..23");
    }
    if t.pm {
      return _err_unit("rtc.pcf8563: PM flag set in 24-hour mode");
    }
  }
  return _ok_unit();
}

/// Decode a PCF8563 frame (control 1, control 2, seconds, minutes, hours,
/// date, weekday, month/century, year; bytes beyond the first 9 are
/// ignored). Bytes 0 and 1 are preserved on the result so an encode can
/// round-trip them.
///
/// The decoded `hours` keeps the register representation (0..23 with
/// hour12 = false, or 1..12 with hour12 = true and the `pm` flag); `vl` is
/// the VL voltage-low bit of the seconds register; `century` is the C flag
/// of the month register; `halted` is the control 1 STOP bit.
///
/// Validation order (first failure wins):
///   1. fewer than 9 bytes -> Err("rtc.pcf8563: need 9 registers, have N");
///   2. control 2 bits 7-5 nonzero -> "rtc.pcf8563 control 2 register N has
///      reserved bits set";
///   3. seconds (bits 6-0): invalid BCD -> "rtc.pcf8563 seconds register N
///      is not valid BCD"; value outside 0..59 -> "rtc.pcf8563 seconds
///      value N out of range 0..59";
///   4. minutes, the same two messages;
///   5. hours: bit 6 set in 24-hour mode -> "rtc.pcf8563 hours register N
///      has reserved bits set"; invalid BCD -> "rtc.pcf8563 hours register
///      N is not valid BCD"; 24-hour value outside 0..23 -> "rtc.pcf8563
///      hours value N out of range 0..23"; 12-hour value outside 1..12 ->
///      "rtc.pcf8563 12-hour value N out of range 1..12";
///   6. weekday: bits 7-3 nonzero (reserved), value 0..6;
///   7. date: bits 7-6 nonzero (reserved), BCD, range 1..31;
///   8. month: bits 6-5 nonzero (reserved), BCD, range 1..12;
///   9. year: BCD, range 0..99;
///  10. the assembled date must exist ->
///      Err("rtc.pcf8563: impossible date Y-M-D") with full year
///      RTC_PCF8563_YEAR_BASE + 100 * century + year.
/// Complexity: O(1).
pub fn rtc_pcf8563_decode(regs: &Vec[UInt8]) -> Result[Pcf8563Time, Str] {
  if regs.len() < RTC_PCF8563_REG_COUNT {
    return _err_pcf("rtc.pcf8563: need " + convert.int_to_string(RTC_PCF8563_REG_COUNT) + " registers, have " + convert.int_to_string(regs.len()));
  }
  let c1 = _byte(regs, RTC_PCF8563_REG_CONTROL1);
  let c2 = _byte(regs, RTC_PCF8563_REG_CONTROL2);
  if c2 / 32 != 0 {
    return _err_pcf("rtc.pcf8563 control 2 register " + convert.int_to_string(c2) + " has reserved bits set");
  }
  let sb = _byte(regs, RTC_PCF8563_REG_SECONDS);
  let vl = (sb / RTC_PCF8563_VL_BIT) % 2 == 1;
  let sr = _bcd_range(sb % RTC_PCF8563_VL_BIT, "rtc.pcf8563 seconds", 0, 59);
  if !sr.is_ok {
    return _err_pcf(sr.error);
  }
  let seconds: Int = sr.value;
  let mr = _bcd_range(_byte(regs, RTC_PCF8563_REG_MINUTES), "rtc.pcf8563 minutes", 0, 59);
  if !mr.is_ok {
    return _err_pcf(mr.error);
  }
  let minutes: Int = mr.value;
  let hb = _byte(regs, RTC_PCF8563_REG_HOURS);
  var hour12 = false;
  var pm = false;
  var hours = 0;
  if (hb / RTC_PCF8563_12H_BIT) % 2 == 1 {
    hour12 = true;
    pm = (hb / RTC_PCF8563_PM_BIT) % 2 == 1;
    let hr = _bcd_range(hb % RTC_PCF8563_PM_BIT, "rtc.pcf8563 12-hour", 1, 12);
    if !hr.is_ok {
      return _err_pcf(hr.error);
    }
    hours = hr.value;
  } else {
    if hb / RTC_PCF8563_PM_BIT != 0 {
      return _err_pcf("rtc.pcf8563 hours register " + convert.int_to_string(hb) + " has reserved bits set");
    }
    let hr2 = _bcd_range(hb % RTC_PCF8563_PM_BIT, "rtc.pcf8563 hours", 0, 23);
    if !hr2.is_ok {
      return _err_pcf(hr2.error);
    }
    hours = hr2.value;
  }
  let wb = _byte(regs, RTC_PCF8563_REG_WEEKDAY);
  if wb / 8 != 0 {
    return _err_pcf("rtc.pcf8563 weekday register " + convert.int_to_string(wb) + " has reserved bits set");
  }
  if wb > 6 {
    return _err_pcf("rtc.pcf8563 weekday value " + convert.int_to_string(wb) + " out of range 0..6");
  }
  let db = _byte(regs, RTC_PCF8563_REG_DATE);
  if db / 64 != 0 {
    return _err_pcf("rtc.pcf8563 date register " + convert.int_to_string(db) + " has reserved bits set");
  }
  let dr = _bcd_range(db % 64, "rtc.pcf8563 date", 1, 31);
  if !dr.is_ok {
    return _err_pcf(dr.error);
  }
  let day: Int = dr.value;
  let mb = _byte(regs, RTC_PCF8563_REG_MONTH);
  var century = 0;
  if (mb / RTC_PCF8563_CENTURY_BIT) % 2 == 1 {
    century = 1;
  }
  let mb_rest = mb % RTC_PCF8563_CENTURY_BIT;
  if mb_rest / 32 != 0 {
    return _err_pcf("rtc.pcf8563 month register " + convert.int_to_string(mb) + " has reserved bits set");
  }
  let mor = _bcd_range(mb_rest % 32, "rtc.pcf8563 month", 1, 12);
  if !mor.is_ok {
    return _err_pcf(mor.error);
  }
  let month: Int = mor.value;
  let yr = _bcd_range(_byte(regs, RTC_PCF8563_REG_YEAR), "rtc.pcf8563 year", 0, 99);
  if !yr.is_ok {
    return _err_pcf(yr.error);
  }
  let year: Int = yr.value;
  let fy = RTC_PCF8563_YEAR_BASE + century * 100 + year;
  let dim = rtc_days_in_month(fy, month);
  if day > dim {
    return _err_pcf("rtc.pcf8563: impossible date " + convert.int_to_string(fy) + "-" + _two(month) + "-" + _two(day));
  }
  let halted = (c1 / RTC_PCF8563_STOP_BIT) % 2 == 1;
  return _ok_pcf(Pcf8563Time{
    control1: c1;
    control2: c2;
    vl: vl;
    time: RtcTime{
      year: year;
      month: month;
      day: day;
      weekday: wb;
      hours: hours;
      minutes: minutes;
      seconds: seconds;
      hour12: hour12;
      pm: pm;
      century: century;
      halted: halted;
    };
  });
}

/// Encode a PCF8563 frame from `s` (9 bytes in register order). Control 1
/// keeps its reserved/configuration bits; STOP (bit 5) is driven by
/// `s.time.halted`. Control 2 must be a byte with bits 7-5 clear. `vl`
/// drives the VL bit, `time.century` the C bit, and `hour12`/`pm` select
/// the 12-hour representation.
///
/// Validation order (first failure wins): control 1 range 0..255, control 2
/// range 0..255 and reserved bits, then the field checks of
/// rtc_pcf8563_encode's model: year 0..99, century 0..1, month 1..12, the
/// date must exist, weekday 0..6, minutes 0..59, seconds 0..59, hours (1..12
/// with hour12, otherwise 0..23 with the PM flag rejected).
/// Err("rtc.pcf8563: control 1 value N out of range 0..255"),
/// Err("rtc.pcf8563: control 2 value N out of range 0..255"),
/// Err("rtc.pcf8563: control 2 register N has reserved bits set"),
/// Err("rtc.pcf8563: year N out of range 0..99"),
/// Err("rtc.pcf8563: century N out of range 0..1"),
/// Err("rtc.pcf8563: month N out of range 1..12"),
/// Err("rtc.pcf8563: impossible date Y-M-D"),
/// Err("rtc.pcf8563: weekday N out of range 0..6"),
/// Err("rtc.pcf8563: minutes N out of range 0..59"),
/// Err("rtc.pcf8563: seconds N out of range 0..59"),
/// Err("rtc.pcf8563: 12-hour hours N out of range 1..12"),
/// Err("rtc.pcf8563: hours N out of range 0..23"),
/// Err("rtc.pcf8563: PM flag set in 24-hour mode").
/// Complexity: O(1).
pub fn rtc_pcf8563_encode(s: &Pcf8563Time) -> Result[Vec[UInt8], Str] {
  if s.control1 < 0 || s.control1 > 255 {
    return _err_bytes("rtc.pcf8563: control 1 value " + convert.int_to_string(s.control1) + " out of range 0..255");
  }
  if s.control2 < 0 || s.control2 > 255 {
    return _err_bytes("rtc.pcf8563: control 2 value " + convert.int_to_string(s.control2) + " out of range 0..255");
  }
  if s.control2 / 32 != 0 {
    return _err_bytes("rtc.pcf8563: control 2 register " + convert.int_to_string(s.control2) + " has reserved bits set");
  }
  let t: RtcTime = s.time;
  let vr = _validate_pcf8563(&t);
  if !vr.is_ok {
    return _err_bytes(vr.error);
  }
  var out = Vec[UInt8].new();
  var c1 = s.control1 - ((s.control1 / RTC_PCF8563_STOP_BIT) % 2) * RTC_PCF8563_STOP_BIT;
  if t.halted {
    c1 = c1 + RTC_PCF8563_STOP_BIT;
  }
  out.push(c1 as UInt8);
  out.push(s.control2 as UInt8);
  var sb = _bcd_value(t.seconds);
  if s.vl {
    sb = sb + RTC_PCF8563_VL_BIT;
  }
  out.push(sb as UInt8);
  out.push(_bcd_value(t.minutes) as UInt8);
  var hb = _bcd_value(t.hours);
  if t.hour12 {
    hb = hb + RTC_PCF8563_12H_BIT;
    if t.pm {
      hb = hb + RTC_PCF8563_PM_BIT;
    }
  }
  out.push(hb as UInt8);
  out.push(_bcd_value(t.day) as UInt8);
  out.push(t.weekday as UInt8);
  out.push((_bcd_value(t.month) + t.century * RTC_PCF8563_CENTURY_BIT) as UInt8);
  out.push(_bcd_value(t.year) as UInt8);
  return _ok_bytes(out);
}

/// True when the PCF8563 VL voltage-low bit (seconds bit 7) is set: the
/// oscillator integrity of the sampled time is not guaranteed.
///
/// Err("rtc.pcf8563: need 9 registers, have N").
/// Complexity: O(1).
pub fn rtc_pcf8563_is_voltage_low(regs: &Vec[UInt8]) -> Result[Bool, Str] {
  if regs.len() < RTC_PCF8563_REG_COUNT {
    return _err_bool("rtc.pcf8563: need " + convert.int_to_string(RTC_PCF8563_REG_COUNT) + " registers, have " + convert.int_to_string(regs.len()));
  }
  let sb = _byte(regs, RTC_PCF8563_REG_SECONDS);
  return _ok_bool((sb / RTC_PCF8563_VL_BIT) % 2 == 1);
}

/// PCF8563 register read order: control 1, control 2, minutes, hours, date,
/// weekday, month, year, then seconds last (see the module header for the
/// read-tearing rule and the constants for the register offsets).
/// Complexity: O(1).
pub fn rtc_pcf8563_read_order() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(RTC_PCF8563_REG_CONTROL1);
  v.push(RTC_PCF8563_REG_CONTROL2);
  v.push(RTC_PCF8563_REG_MINUTES);
  v.push(RTC_PCF8563_REG_HOURS);
  v.push(RTC_PCF8563_REG_DATE);
  v.push(RTC_PCF8563_REG_WEEKDAY);
  v.push(RTC_PCF8563_REG_MONTH);
  v.push(RTC_PCF8563_REG_YEAR);
  v.push(RTC_PCF8563_REG_SECONDS);
  return v;
}
