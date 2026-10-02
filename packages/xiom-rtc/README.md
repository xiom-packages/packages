# xiom.rtc

> **Status:** `stable` -- conformance-tested (18/18); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI) real-time clock register codecs: packed BCD
> fields, the DS1307 7-register and PCF8563 9-register layouts (control and
> status registers, 12/24-hour modes, the AM/PM bit, the century flag, the
> clock-halt bits) and civil-date <-> epoch-day arithmetic.
> **Deps:** `xiom.std` only. The library module imports `xiom.convert`; the
> tests also use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.rtc` turns clock-calendar register frames into values and back:

- **BCD fields** -- `rtc_bcd_encode` / `rtc_bcd_decode` pack and unpack a
  decimal value 0..99, rejecting bytes whose nibbles are not decimal digits;
- **DS1307 layout** -- 7 registers (seconds, minutes, hours, weekday, date,
  month, year), seconds bit 7 = CH clock halt, hours bit 6 = 12/24 mode with
  bit 5 as PM in 12-hour mode and the 20-hour bit in 24-hour mode, weekday
  1..7, date 1..31, month 1..12, year 0..99;
- **PCF8563 layout** -- 9 registers (control 1, control 2, seconds, minutes,
  hours, date, weekday, month/century, year), control 1 bit 5 = STOP, control
  2 bits 7-5 reserved, seconds bit 7 = VL voltage-low, hours bit 7 = 12/24
  mode with bit 6 as PM, weekday 0..6, month bit 7 = C century flag;
- **12/24-hour conversion** -- `rtc_twelve_hour_to_24`,
  `rtc_24_to_twelve_hours` and `rtc_24_to_twelve_pm` around the 12
  AM / 12 PM boundaries;
- **Civil dates** -- leap-year rule (divisible by 4, except centuries, except
  400-year centuries), `rtc_days_in_month`, `rtc_is_valid_date`,
  `rtc_days_from_civil` and `rtc_civil_from_days` (UNIX epoch day 0 =
  1970-01-01, negative days included), plus `rtc_weekday_from_days` (ISO
  1 = Monday);
- **Impossible-field validation** -- month 13, Feb 30, Feb 29 in a common
  year, hour 24, minute/second 60, weekday outside its family range and
  reserved-bit patterns are all rejected with named errors;
- **Read order and halt semantics** -- both documented register read orders
  (seconds sampled last to confine minute-boundary tearing) and the CH / STOP
  clock-halt bits plus the VL integrity flag as first-class operations.

Everything is a free function over `Int`, `Bool`, `Vec[UInt8]` and three
small struct types. There is no I/O, no bus transaction, no timing and no
device state: the codec only formats, validates and converts. The error model
is a deterministic `Err(Str)` catalog (see `SPEC.md`); an `Err` never carries
a half-built buffer.

## Install / use

```
xiom pkg install xiom.rtc@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.rtc;
use xiom.io;
use xiom.encoding.hex;

// DS1307: 2099-12-31 23:59:45, weekday 5, running, 24-hour mode.
// Register order seconds..year: 45 59 23 05 31 12 99.
let dr = rtc_ds1307_decode(&regs);          // regs: Vec[UInt8]
if dr.is_ok {
  let t: RtcTime = dr.value;                // t.hours == 23, t.halted == false
  let day = rtc_days_from_civil(2099, 12, 31);   // 47481
}

// DS1307 read order: seconds last.
let order = rtc_ds1307_read_order();        // [1, 2, 3, 4, 5, 6, 0]

// Clear the CH halt bit without touching any other bit.
let run = rtc_ds1307_set_halted(&regs, false);

// PCF8563: 2124-05-25 12:30:45, weekday 6, STOP set, century flag 1.
// Registers: 20 13 45 30 12 25 06 85 24.
let pr = rtc_pcf8563_decode(&regs9);
if pr.is_ok {
  let s: Pcf8563Time = pr.value;            // s.time.century == 1, s.time.halted == true
  let full = rtc_full_year(&s.time);        // 2124
}

// 12-hour mode: 11 PM is 23 in 24-hour notation.
let h24 = rtc_twelve_hour_to_24(11, true);  // 23
let back = rtc_24_to_twelve_hours(23);      // 11
```

## API

All functions are free functions in module `xiom.rtc`.

### BCD

| Function | Returns | Description |
|---|---|---|
| `rtc_bcd_encode(value)` | `Result[Int, Str]` | Pack 0..99 as BCD (tens in the high nibble). |
| `rtc_bcd_decode(byte)` | `Result[Int, Str]` | Unpack; both nibbles must be 0..9. |
| `rtc_bcd_is_valid(byte)` | `Bool` | Non-fallible nibble check. |

### Civil dates

| Function | Returns | Description |
|---|---|---|
| `rtc_is_leap(year)` | `Bool` | Proleptic Gregorian leap rule. |
| `rtc_days_in_month(year, month)` | `Int` | 28/29/30/31, or 0 for month outside 1..12. |
| `rtc_is_valid_date(year, month, day)` | `Bool` | Real Gregorian date. |
| `rtc_is_valid_time(hours, minutes, seconds)` | `Bool` | 24-hour clock time. |
| `rtc_days_from_civil(year, month, day)` | `Result[Int, Str]` | Days since 1970-01-01 (negative for earlier dates). |
| `rtc_civil_from_days(days)` | `CivilDate` | Inverse of `rtc_days_from_civil`. |
| `rtc_weekday_from_days(days)` | `Int` | ISO day of week 1..7 (1970-01-01 = 4, Thursday). |

### 12/24-hour mode

| Function | Returns | Description |
|---|---|---|
| `rtc_twelve_hour_to_24(hours, pm)` | `Result[Int, Str]` | 12 AM -> 0, 12 PM -> 12, 1..11 PM -> +12. |
| `rtc_24_to_twelve_hours(hours)` | `Result[Int, Str]` | 1..12 for a 24-hour value. |
| `rtc_24_to_twelve_pm(hours)` | `Result[Bool, Str]` | True for 12..23. |
| `rtc_full_year(t)` | `Int` | 2000 + 100 * century + year. |

### DS1307

| Function | Returns | Description |
|---|---|---|
| `rtc_ds1307_decode(regs)` | `Result[RtcTime, Str]` | 7-register frame; extra bytes ignored. |
| `rtc_ds1307_encode(t)` | `Result[Vec[UInt8], Str]` | 7-register frame; century field ignored. |
| `rtc_ds1307_is_halted(regs)` | `Result[Bool, Str]` | CH bit (seconds bit 7). |
| `rtc_ds1307_set_halted(regs, halted)` | `Result[Vec[UInt8], Str]` | Copy with CH set/cleared, all other bits kept. |
| `rtc_ds1307_read_order()` | `Vec[Int]` | `[1, 2, 3, 4, 5, 6, 0]` (seconds last). |

### PCF8563

| Function | Returns | Description |
|---|---|---|
| `rtc_pcf8563_decode(regs)` | `Result[Pcf8563Time, Str]` | 9-register frame; control bytes preserved. |
| `rtc_pcf8563_encode(s)` | `Result[Vec[UInt8], Str]` | 9-register frame; STOP driven by `time.halted`. |
| `rtc_pcf8563_is_voltage_low(regs)` | `Result[Bool, Str]` | VL bit (seconds bit 7). |
| `rtc_pcf8563_read_order()` | `Vec[Int]` | `[0, 1, 3, 4, 5, 6, 7, 8, 2]` (seconds last). |

### Constants and types

```xi
pub const RTC_DS1307_REG_SECONDS: Int = 0;   // .. RTC_DS1307_REG_YEAR = 6
pub const RTC_DS1307_REG_COUNT: Int = 7;
pub const RTC_DS1307_YEAR_BASE: Int = 2000;
pub const RTC_DS1307_CH_BIT: Int = 128;
pub const RTC_DS1307_12H_BIT: Int = 64;
pub const RTC_DS1307_PM_BIT: Int = 32;

pub const RTC_PCF8563_REG_CONTROL1: Int = 0; // .. RTC_PCF8563_REG_YEAR = 8
pub const RTC_PCF8563_REG_COUNT: Int = 9;
pub const RTC_PCF8563_YEAR_BASE: Int = 2000;
pub const RTC_PCF8563_VL_BIT: Int = 128;
pub const RTC_PCF8563_12H_BIT: Int = 128;
pub const RTC_PCF8563_PM_BIT: Int = 64;
pub const RTC_PCF8563_CENTURY_BIT: Int = 128;
pub const RTC_PCF8563_STOP_BIT: Int = 32;

pub type RtcTime = { year; month; day; weekday; hours; minutes; seconds; hour12; pm; century; halted; }
pub type Pcf8563Time = { control1; control2; vl; time: RtcTime; }
pub type CivilDate = { year; month; day; }
```

`RtcTime` keeps the register representation of the hours field: 0..23 with
`hour12 = false`, or 1..12 with `hour12 = true` and the `pm` flag.

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
message. Families use `rtc.bcd:`, `rtc.ds1307:`, `rtc.pcf8563:` and bare
`rtc:` prefixes; field errors inside a frame say
`rtc.<family> <field> register N ...` or `rtc.<family> <field> value N out of
range L..H`, and impossible cross-field dates are reported as
`rtc.<family>: impossible date Y-M-D`. Decoders validate in a fixed order
documented per function in `SPEC.md`; `Err` never carries a partial result.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.rtc
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`. Pinned frames
(`45 59 23 05 31 12 99`, `80 30 12 03 18 02 00`, `00 30 71 02 15 06 24`,
`20 13 45 30 12 25 06 85 24`, `00 08 D9 59 D1 31 04 12 99`) and pinned epoch
days (0, -1, 11016, 11017, 19782, 20723, 47481, 47482, 47541) are derived by
hand in `SPEC.md` and asserted in the suite. See `SPEC.md` for the full
matrix.

## Limitations

- **No bus I/O.** No I2C start/stop/ACK, no register-pointer state, no
  timing. Frames go in and out as `Vec[UInt8]`.
- **No century register on the DS1307.** The decoder always reports
  `century = 0`, the encoder ignores the field, and impossible-date checks
  use `RTC_DS1307_YEAR_BASE + year` (2000 + year).
- **PCF8563 century convention.** Full year = 2000 + 100 * century + year,
  so century 0 covers 2000..2099 and century 1 covers 2100..2199; other
  conventions (1900 base) are the caller's mapping.
- **Weekday is a field value, not a calendar lookup.** The codec validates
  the field range (DS1307 1..7, PCF8563 0..6); it does not cross-check the
  weekday against the date, because both families treat the register as
  user-defined.
- **Read order is advisory.** The read orders express the seconds-last
  sampling rule; detecting a torn snapshot is the caller's retry policy (no
  hidden state is kept).
- **Alarm/timer registers are out of scope.** PCF8563 control 2 and alarm
  registers are preserved byte-for-byte on control 2 only; the alarm set
  registers are not modeled.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
