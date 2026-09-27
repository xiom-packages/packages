# xiom.rtc -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.rtc`, version `0.1.0`).
Module: `src/rtc.xi` (`module xiom.rtc`).
Depends on `xiom.std`; the library module imports `xiom.convert` (tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## Scope

A pure-XIOM (no FFI) codec for two classic I2C clock-calendar register
layouts plus the arithmetic they need:

- packed BCD encode/decode with decimal-nibble validation;
- DS1307 (7 registers) and PCF8563 (9 registers, control/status registers)
  decode and encode;
- 12/24-hour modes with the AM/PM bit, the century flag, day-of-week field
  validation, clock-halt bit semantics;
- civil-date <-> days-since-epoch integer conversion with the Gregorian
  leap-year rule and impossible-field rejection;
- documented register read orders;
- a deterministic `Err(Str)` catalog for malformed and impossible fields.

## Non-goals

- Bus I/O: no I2C start/stop/ACK sequencing, no register-pointer state, no
  timing, no device state. Frames are in-memory `Vec[UInt8]`.
- Alarm, timer and square-wave registers (PCF8563 alarm set registers,
  control 2 interrupt flags are preserved on encode but not modeled).
- Fixing the century convention beyond the documented year bases.
- Parsing/formatting dates as text.
- Cross-checking the weekday field against the calendar date (both families
  define the register as user-assigned).
- Retry policy for torn reads (the read orders express the rule; the caller
  owns the retry loop).

## BCD

`rtc_bcd_encode(value)` packs a decimal 0..99 as `(value / 10) * 16 +
(value % 10)`: tens digit in the high nibble, ones digit in the low nibble.
`rtc_bcd_decode(byte)` unpacks only when both nibbles are 0..9 (0x1A, 0xA0,
0xFF are invalid). `rtc_bcd_is_valid(byte)` is the non-fallible predicate.

The register decoders are stricter than their masks: for example the DS1307
hour field is masked to 6 bits before BCD validation, but a masked value of
0x3A is still rejected as non-decimal. Values are checked after decoding
(0x60 decodes to 60 and fails the 0..59 range).

## DS1307 register map (7 bytes, offsets 0x00..0x06)

| Offset | Field | Bits |
|---|---|---|
| 0x00 | seconds | 7 = CH (clock halt); 6-0 = 00..59 BCD |
| 0x01 | minutes | 7-0 = 00..59 BCD |
| 0x02 | hours | 6 = 12/24 (1 = 12-hour); 12h: 5 = PM, 4-0 = 1..12 BCD; 24h: 5-0 = 0..23 BCD |
| 0x03 | weekday | 7-3 reserved (must be 0); 2-0 = 1..7 |
| 0x04 | date | 7-6 reserved (must be 0); 5-0 = 1..31 BCD |
| 0x05 | month | 7-5 reserved (must be 0); 4-0 = 1..12 BCD |
| 0x06 | year | 7-0 = 0..99 BCD |

- The hour register's bit 7 must be 0.
- `halted` is the CH bit: the oscillator is off and the time registers are
  frozen. The seconds value is still decoded from bits 6-0.
- There is no century register: `century` decodes as 0, encode ignores the
  `century` field, and impossible-date checks use
  `RTC_DS1307_YEAR_BASE (2000) + year`.
- Weekday range 1..7; date, month and year ranges as above.

### DS1307 decode validation order

1. length: fewer than 7 bytes -> `rtc.ds1307: need 7 registers, have N`;
2. seconds (bits 6-0): BCD, 0..59;
3. minutes: BCD, 0..59;
4. hours: bit 7 must be 0 ("reserved bits"); mode by bit 6; 12-hour value
   BCD 1..12; 24-hour value BCD 0..23;
5. weekday: bits 7-3 must be 0; value 1..7;
6. date: bits 7-6 must be 0; BCD 1..31;
7. month: bits 7-5 must be 0; BCD 1..12;
8. year: BCD 0..99;
9. cross-field: the assembled date must exist with full year 2000 + year
   (`rtc.ds1307: impossible date Y-M-D`).

Bytes beyond the first 7 are ignored.

### DS1307 encode validation order

year 0..99, month 1..12, date exists, weekday 1..7, minutes 0..59, seconds
0..59, hours (1..12 with `hour12`, else 0..23 with `pm` rejected). The
7-byte output is in register order and uses the 12/24-hour bit, the PM bit
and the CH bit.

## PCF8563 register map (9 bytes, offsets 0x00..0x08)

| Offset | Field | Bits |
|---|---|---|
| 0x00 | control 1 | 5 = STOP (clock halt); other bits preserved |
| 0x01 | control 2 | 7-5 reserved (must be 0); 4-0 preserved |
| 0x02 | seconds | 7 = VL (voltage low); 6-0 = 00..59 BCD |
| 0x03 | minutes | 7-0 = 00..59 BCD |
| 0x04 | hours | 7 = 12/24 (1 = 12-hour); 12h: 6 = PM, 5-0 = 1..12 BCD; 24h: 6 must be 0, 5-0 = 0..23 BCD |
| 0x05 | date | 7-6 reserved (must be 0); 5-0 = 1..31 BCD |
| 0x06 | weekday | 7-3 reserved (must be 0); 2-0 = 0..6 |
| 0x07 | month/century | 7 = C century flag; 6-5 reserved (must be 0); 4-0 = 1..12 BCD |
| 0x08 | year | 7-0 = 0..99 BCD |

- `halted` is control 1 bit 5 (STOP); `vl` is seconds bit 7; `century` is
  the month bit 7. Full year = `RTC_PCF8563_YEAR_BASE (2000) + 100 * century
  + year`, so century 0 covers 2000..2099 and century 1 covers 2100..2199.
- On encode, control 1 keeps its other bits and STOP is driven by
  `time.halted`; control 2 is written as stored after the reserved check.

### PCF8563 decode validation order

1. length: fewer than 9 bytes -> `rtc.pcf8563: need 9 registers, have N`;
2. control 2 bits 7-5 must be 0 ("reserved bits");
3. seconds (bits 6-0): BCD, 0..59; bits 7 is VL;
4. minutes: BCD, 0..59;
5. hours: 12-hour if bit 7, value BCD 1..12 (bit 6 = PM); otherwise bit 6
   must be 0 ("reserved bits") and the value is BCD 0..23;
6. weekday: bits 7-3 must be 0; value 0..6;
7. date: bits 7-6 must be 0; BCD 1..31;
8. month: bits 6-5 must be 0; BCD 1..12; bit 7 is the century flag;
9. year: BCD 0..99;
10. cross-field: the assembled date must exist with the century-based full
    year (`rtc.pcf8563: impossible date Y-M-D`).

Bytes beyond the first 9 are ignored; control 1 and control 2 are preserved
on the result so an encode round-trips them.

### PCF8563 encode validation order

control 1 range 0..255; control 2 range 0..255 and bits 7-5 clear; then year
0..99, century 0..1, month 1..12, date exists, weekday 0..6, minutes 0..59,
seconds 0..59, hours (1..12 with `hour12`, else 0..23 with `pm` rejected).
The STOP bit of the emitted control 1 is always `time.halted`, and the VL
bit is `vl`.

## 12/24-hour conversion

| Input | Result |
|---|---|
| 12 AM (12, false) | 0 |
| 1..11 AM (h, false) | h |
| 12 PM (12, true) | 12 |
| 1..11 PM (h, true) | h + 12 |

`rtc_24_to_twelve_hours(0) = 12`, `(12) = 12`, `(13) = 1`, `(23) = 11`;
`rtc_24_to_twelve_pm` is true exactly for 12..23. `rtc_full_year(t)` =
2000 + 100 * t.century + t.year (shared by both families).

## Civil dates and epoch days

Leap rule: divisible by 4, except centuries (divisible by 100), except
400-year centuries (divisible by 400). 2000 and 2024 are leap; 1900 and 2100
are not.

`rtc_days_from_civil(year, month, day)` returns days since 1970-01-01
(day 0) using Howard Hinnant's civil-date algorithm with floor division for
negative years; it validates month 1..12 (`rtc: month N out of range 1..12`)
and the day against `rtc_days_in_month` (`rtc: impossible date Y-M-D`, with
zero-padded month/day). `rtc_civil_from_days` is the exact inverse for any
day count, including negative (before the epoch).

Pinned days:

| Date | Days |
|---|---|
| 1969-12-31 | -1 |
| 1970-01-01 | 0 |
| 1970-01-02 | 1 |
| 2000-02-29 | 11016 |
| 2000-03-01 | 11017 |
| 2024-02-29 | 19782 |
| 2026-09-27 | 20723 |
| 2099-12-31 | 47481 |
| 2100-01-01 | 47482 |
| 2100-03-01 | 47541 (2100 is common) |

`rtc_weekday_from_days` maps 0 -> 4 (1970-01-01 was a Thursday), ISO
1 = Monday .. 7 = Sunday.

## Register read order

A running clock can tear a sequential read at the minute boundary: minutes
read as 59 and seconds read as 00 on the far side of the rollover describe a
minute that never existed. Both orders therefore sample the seconds register
last, so any rollover is confined to the final field:

- DS1307: `[1, 2, 3, 4, 5, 6, 0]` (minutes, hours, weekday, date, month,
  year, seconds);
- PCF8563: `[0, 1, 3, 4, 5, 6, 7, 8, 2]` (control 1, control 2, minutes,
  hours, date, weekday, month, year, seconds).

Detecting the tear is the caller's retry policy: re-read seconds and discard
the snapshot when it changed. The codec keeps no hidden state.

## Error catalog

`rtc.bcd: value N out of range 0..99` / `rtc.bcd: byte N out of range
0..255` / `rtc.bcd: byte N is not valid BCD`.

`rtc: month N out of range 1..12` / `rtc: impossible date Y-M-D` /
`rtc: 12-hour value N out of range 1..12` / `rtc: hours N out of range
0..23`.

DS1307: `rtc.ds1307: need 7 registers, have N` (decode, `is_halted`,
`set_halted`); per field `rtc.ds1307 <field> register N is not valid BCD`,
`rtc.ds1307 <field> value N out of range L..H`, `rtc.ds1307 <field>
register N has reserved bits set` where `<field>` is `seconds`, `minutes`,
`hours`, `12-hour`, `weekday`, `date`, `month` or `year`;
`rtc.ds1307: impossible date Y-M-D`. Encode-side messages use the
`rtc.ds1307:` prefix: `year N out of range 0..99`, `month N out of range
1..12`, `impossible date Y-M-D`, `weekday N out of range 1..7`, `minutes N
out of range 0..59`, `seconds N out of range 0..59`, `12-hour hours N out of
range 1..12`, `hours N out of range 0..23`, `PM flag set in 24-hour mode`.

PCF8563: `rtc.pcf8563: need 9 registers, have N` (decode and
`is_voltage_low`); decode-side per field the same three shapes plus
`rtc.pcf8563 control 2 register N has reserved bits set` and the
`12-hour`/`weekday 0..6` ranges; `rtc.pcf8563: impossible date Y-M-D`.
Encode-side messages use the `rtc.pcf8563:` prefix: `control 1 value N out
of range 0..255`, `control 2 value N out of range 0..255`, `control 2
register N has reserved bits set`, `year N out of range 0..99`, `century N
out of range 0..1`, `month N out of range 1..12`, `impossible date Y-M-D`,
`weekday N out of range 0..6`, `minutes N out of range 0..59`, `seconds N
out of range 0..59`, `12-hour hours N out of range 1..12`, `hours N out of
range 0..23`, `PM flag set in 24-hour mode`.

## Worked examples (pinned by the suite)

| Frame (hex) | Meaning |
|---|---|
| `45 59 23 05 31 12 99` | DS1307, 2099-12-31 23:59:45, weekday 5, running |
| `80 30 12 03 18 02 00` | DS1307, 2000-02-18 12:30:00, CH set, seconds decode 0 |
| `00 30 71 02 15 06 24` | DS1307, 2024-06-15 11:30 PM (12-hour: 0x71 = mode + PM + BCD 0x11) |
| `00 00 52 01 01 01 01` | DS1307, 2001-01-01 12:00 AM (12-hour: 0x52 = mode + BCD 12) |
| `20 13 45 30 12 25 06 85 24` | PCF8563, 2124-05-25 12:30:45, weekday 6, STOP set, century 1 |
| `00 00 80 00 00 01 00 01 00` | PCF8563, 2000-01-01 00:00:00, VL set |
| `00 08 D9 59 D1 31 04 12 99` | PCF8563, 2099-12-31 11:59:59 PM (12-hour: 0xD1 = mode + PM + BCD 0x11), VL set |

## Test matrix (`tests/test_conformance.xi`, 18 checks)

1. BCD pack/unpack table and nibble validation;
2. leap-year rule and month lengths;
3. impossible fields rejected (Feb 30, month 13, hour 24, minute 60);
4. days-since-epoch pinned values and date errors;
5. `civil_from_days` pinned values and epoch round trips;
6. ISO weekday pinned values;
7. 12/24-hour conversion and the AM/PM boundary;
8. DS1307 24-hour decode, extra bytes ignored;
9. DS1307 CH halt semantics, `is_halted`, `set_halted`;
10. DS1307 12-hour AM/PM decode, conversion, encode round trip;
11. DS1307 encode pinned leap-day frame, halt bit, determinism;
12. DS1307 decode error catalog;
13. DS1307 encode error catalog and ignored century field;
14. PCF8563 decode, STOP bit, century flag, round trip;
15. PCF8563 VL flag and midnight decode;
16. PCF8563 encode pinned 12-hour PM frame, VL/century bits, STOP drive;
17. PCF8563 decode/encode error catalog (including Feb 29 2100);
18. register read orders, century full year, epoch integration.

## v0.61.3 notes

- Free functions only; no self methods, no lambdas, no `Vec[fn]` dispatch.
- `Ok`/`Err` construction is confined to the leaf `_ok_*` / `_err_*`
  helpers; constructing `Result` payloads inside other functions
  miscompiles.
- Every `Vec[UInt8]` byte read is widened with `(x as Int) & 0xFF`.
- Bits are extracted with truncating division and modulo, not shifts; the
  civil-date math uses a floor-division helper so negative days (before
  1970) round-trip exactly.
- No `Vec[Float64]` and no floating-point arithmetic anywhere.
- Struct fields are bound to typed locals before being borrowed
  (`let t: RtcTime = s.time;` in the PCF8563 encoder).
- `Str` values are never compared with `==`; the suite uses
  `xiom.string.compare.str_compare`. Bool flags are compared through a
  Bool-safe helper rather than `==`.
