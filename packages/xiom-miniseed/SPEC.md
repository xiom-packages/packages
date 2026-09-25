# xiom.miniseed -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.miniseed`, version `0.1.0`).
Module: `src/miniseed.xi` (`module xiom.miniseed`).
Depends on `xiom.std` (`xiom.string`: `byte_at`, `str_trim`;
`Str::from_utf8` is a compiler builtin); the tests additionally use
`xiom.test`, `xiom.io` and `xiom.string.compare`.

## 1. Scope

A pure-XIOM (no FFI) codec for the miniSEED 2.x fixed data-record header:

- `miniseed_parse` validates one record buffer and returns a flat
  `MseedHeader` of scalar fields (all 48 fixed-header bytes decoded);
- 26 infallible accessors for the header fields, the payload span, the
  exact sample-rate rational and the truncated micro-Hz value;
- `miniseed_sample_count` / `miniseed_samples_fit` /
  `miniseed_required_record_size` for the documented sample-count policy;
- `miniseed_data_bytes` copies the payload span out of the parse buffer;
- `miniseed_build` writes the canonical 48-byte header back out;
- `miniseed_is_leap_year` exposes the day-366 leap rule.

One call handles exactly one record. The record size is the length of the
buffer passed to `miniseed_parse`; the documented fixtures are 512-byte and
4096-byte records.

## 2. Non-goals

- **No blockette parsing.** Only `num_blockettes` and
  `begin_blockette_offset` are decoded. Blockette 1000 (encoding, word
  order, record length) and every other blockette are opaque bytes and are
  never validated or interpreted, even when a fixture places one after the
  header.
- **No sample decoding.** No Steim-1/Steim-2 decompression, no integer or
  float reconstruction, no data-quality filtering. `miniseed_data_bytes`
  copies bytes only.
- **No dataless SEED**, no SEED control headers, no station/channel
  metadata, no response files.
- **No little-endian records and no word-order auto-detection.** Detection
  needs blockette 1000, which is out of scope (section 3.3).
- **No stream walking / record framing.** The module does not search for
  record boundaries; a fixed-length stream must be sliced by the caller.
- **No time-zone or calendar conversion.** The start time stays in SEED's
  `year + day-of-year` form; there is no month/day or epoch conversion.
- **No JSON/hex rendering**, no file I/O, no threads; buffers only.

### 2.1 Deliberate narrowing of the port brief

Three points where this specification pins a narrower rule than a loose
reading of the port brief; each is documented here and covered by tests:

1. **Number of samples.** The miniSEED fixed header has no
   number-of-samples field. The sample count is implied by the payload span
   and the bytes-per-sample of the encoding, and the encoding lives in
   blockette 1000 (out of scope). The module therefore exposes the count as
   a derived accessor over a caller-supplied `sample_size` (section 6)
   instead of pretending to decode a header word.
2. **Sub-second field range.** The tenths-of-milliseconds field is a u16 in
   units of 0.0001 s, so its valid range is 0..9999 (values above 9999
   would exceed one second and are rejected as `miniseed: bad tenths`).
   A `tenths < 1000` rule would reject the upper three quarters of the
   documented field; it is not used.
3. **Record length.** The fixed header cannot encode the record length
   (blockette 1000 does). The parser treats `data.len()` as the record
   size; `miniseed_required_record_size` reports the length implied by a
   declared sample count (section 6).

## 3. Byte layout

### 3.1 Fixed header (48 bytes)

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 6 | sequence number | ASCII digits and spaces only; trimmed on access. |
| 6 | 1 | quality indicator | D (68), R (82), Q (81), M (77) or space (32). |
| 7 | 1 | reserved | `0x00` or `0x20`; preserved as parsed. |
| 8 | 5 | station | Printable ASCII `0x20..0x7E`; space-padded, trimmed on access. |
| 13 | 3 | channel | Same charset and padding. |
| 16 | 2 | network | Same charset and padding. |
| 18 | 2 | location | Same charset and padding; an all-space field reads as `""`. |
| 20 | 2 | start year | Big-endian u16. |
| 22 | 2 | start day-of-year | Big-endian u16; 1..365, plus 366 in a leap year. |
| 24 | 1 | start hour | 0..23. |
| 25 | 1 | start minute | 0..59. |
| 26 | 1 | start second | 0..60; 60 is the documented leap-second value. |
| 27 | 1 | unused | Preserved as parsed, never validated (SEED writes 0). |
| 28 | 2 | tenths of milliseconds | Big-endian u16, 0..9999; unit 0.0001 s. |
| 30 | 2 | sample rate factor | Big-endian i16 (signed). |
| 32 | 2 | sample rate multiplier | Big-endian i16 (signed). |
| 34 | 1 | activity flags | Raw byte, 0..255. |
| 35 | 1 | I/O and clock flags | Raw byte, 0..255. |
| 36 | 1 | data quality flags | Raw byte, 0..255. |
| 37 | 1 | number of blockettes | Raw byte, 0..255. |
| 38 | 4 | time correction | Big-endian i32, unit 0.0001 s. |
| 42 | 2 | beginning of data | Big-endian u16, `>= 48` and `<= record_size`. |
| 44 | 2 | first blockette | Big-endian u16; 0 or inside 48..record_size. |
| 46 | 2 | reserved | Preserved as parsed, never validated. |

The header is followed by the payload span `begin_data_offset ..
record_size`; any bytes between 48 and `begin_data_offset` (blockettes and
alignment) are opaque to this module.

### 3.2 Record size

`miniseed_parse(data)` sets `record_size = data.len()`. A caller reading a
fixed-length stream (the documented 512- and 4096-byte cases) slices exactly
one record and passes it. Bytes at indices `>= record_size` are never read.

### 3.3 Endianness stance

All multi-byte fields are read and written big-endian. miniSEED 2.x defines
the fixed header as big-endian; little-endian records are legal only through
the blockette 1000 word-order flag, which this module does not parse.
Therefore:

- there is no little-endian decode path and no auto-detection;
- a byte-swapped record is expected to fail validation (for example a
  swapped year/day pair or a swapped 16-bit day produces
  `miniseed: bad day`);
- `miniseed_build` always emits big-endian bytes.

### 3.4 Text fields

- Sequence: exactly six bytes, each an ASCII digit (`0x30..0x39`) or a
  space. The accessor trims leading and trailing spaces, so `"  1234"`
  reads as `"1234"` and an all-space field reads as `""`.
- Station (5), channel (3), network (2), location (2): each byte must be
  printable ASCII (`0x20..0x7E`); the accessor trims surrounding spaces.
  Non-ASCII station codes are out of scope.
- `miniseed_build` accepts shorter strings and right-pads with spaces;
  strings longer than the field width are rejected.

## 4. Validation order

`miniseed_parse` (first failure wins):

1. `data.len() < 48` -> `miniseed: truncated header`.
2. quality byte not in {68, 82, 81, 77, 32} -> `miniseed: bad quality
   indicator`.
3. reserved byte not in {0, 32} -> `miniseed: bad reserved byte`.
4. sequence bytes not all digits/spaces -> `miniseed: bad sequence number`.
5. station bytes outside `0x20..0x7E` -> `miniseed: bad station`.
6. channel bytes -> `miniseed: bad channel`.
7. network bytes -> `miniseed: bad network`.
8. location bytes -> `miniseed: bad location`.
9. day outside 1..366, or day 366 in a non-leap year -> `miniseed: bad
   day`.
10. hour > 23 -> `miniseed: bad hour`.
11. minute > 59 -> `miniseed: bad minute`.
12. second > 60 -> `miniseed: bad second`.
13. tenths > 9999 -> `miniseed: bad tenths`.
14. `begin_data_offset < 48` or `> data.len()` -> `miniseed: bad data
    offset`.
15. `begin_blockette_offset` is neither 0 nor inside
    `48..data.len()` -> `miniseed: bad blockette offset`; likewise
    `num_blockettes > 0` with a zero offset -> `miniseed: bad blockette
    offset`.

The unused byte (27) and the two reserved bytes (46..47) are preserved and
never rejected.

`miniseed_build` (first failure wins):

1. sequence longer than 6 bytes or outside digits/spaces -> `miniseed: bad
   sequence number`.
2. quality -> `miniseed: bad quality indicator`.
3. reserved -> `miniseed: bad reserved byte`.
4. station/channel/network/location longer than the width or outside
   `0x20..0x7E` -> the matching text error.
5. year outside 0..65535 -> `miniseed: bad year`.
6. day -> `miniseed: bad day`; hour/minute/second/tenths -> the matching
   errors (negative values are also rejected, unlike parse where the byte
   casts cannot be negative).
7. factor or multiplier outside -32768..32767 -> `miniseed: bad sample
   rate`.
8. activity/io/data-quality flags or blockette count outside 0..255 ->
   `miniseed: bad flags`.
9. time correction outside -2^31..2^31-1 -> `miniseed: bad time
   correction`.
10. `begin_data_offset < 48` -> `miniseed: bad data offset`.
11. blockette offset policy as in parse (against `record_size`) ->
    `miniseed: bad blockette offset`.
12. `record_size < 48` or `< begin_data_offset` -> `miniseed: bad record
    size`.

The builder then writes the 48 bytes: text right-padded with spaces, the
unused byte and the reserved bytes written as 0, every other field written
as given. `record_size` itself is not encoded.

## 5. Sample rate interpretation

The `(factor, multiplier)` pair is interpreted as in the SEED manual; the
rate is in Hz:

| factor | multiplier | rate (Hz) |
|---|---|---|
| `> 0` | `> 0` | `factor * multiplier` |
| `> 0` | `< 0` | `factor / abs(multiplier)` |
| `< 0` | `> 0` | `multiplier / abs(factor)` |
| `< 0` | `< 0` | `1 / (abs(factor) * abs(multiplier))` |
| `= 0` | any | `0` (undefined; multiplier ignored) |
| `!= 0` | `= 0` | multiplier treated as `1` |

The rate is exposed twice (the documented "duplicate pair"):

- raw: `miniseed_sample_rate_factor`, `miniseed_sample_rate_multiplier`;
- derived: `miniseed_rate_num` / `miniseed_rate_den` give the exact
  non-reduced rational (`num >= 0`, `den >= 1`); `miniseed_rate_microhz`
  returns `num * 1,000,000 / den` truncated toward zero (XIOM has no
  `Float64` in this package, so the derived value is an integer).

For any i16 pair the largest product is `32767 * 32767 * 1,000,000`, which
fits an `Int`.

| factor | multiplier | num/den | micro-Hz |
|---|---|---|---|
| 40 | 1 | 40/1 | 40000000 |
| 40 | -2 | 40/2 | 20000000 |
| -100 | 1 | 1/100 | 10000 |
| -1 | -100 | 1/100 | 10000 |
| 1 | -3 | 1/3 | 333333 |
| 40 | 0 | 40/1 | 40000000 |
| 0 | -5 | 0/1 | 0 |

## 6. Record size, payload span and sample count

- `miniseed_record_size(h)` is the buffer length supplied to parse.
- `miniseed_data_span(h)` is `record_size - begin_data_offset`, or 0 when a
  hand-built header has an offset outside `0..record_size`.
- `miniseed_sample_count(h, sample_size)` is `floor(span / sample_size)`,
  and 0 when `sample_size <= 0` (bytes per sample unknown). Trailing pad
  bytes are not samples.
- `miniseed_samples_fit(h, n, sample_size)` is
  `n <= span / sample_size` (false for `n < 0` or `sample_size <= 0`),
  evaluated by division so no multiplication can overflow.
- `miniseed_required_record_size(begin_data_offset, n, sample_size)` is
  `begin_data_offset + n * sample_size`, 0 when any argument is negative or
  `sample_size` is zero. This is the documented "record length inferred
  from data offset and samples" rule.
- `miniseed_data_bytes(data, h)` copies `data[begin_data_offset ..
  record_size]`; it rejects a header whose record size or offset does not
  fit `data` with `miniseed: truncated data`.

Worked fixtures: 512-byte record with data at 48 -> span 464, 116 samples
of 4 bytes, required size 512; 4096-byte record with data at 64 -> span
4032, 1008 samples of 4 bytes, required size 4096.

## 7. API signatures

All functions are free functions in module `xiom.miniseed`:

```xi
pub type MseedHeader = {
  sequence: Str; quality: Int; reserved: Int; station: Str; channel: Str;
  network: Str; location: Str; year: Int; day: Int; hour: Int; minute: Int;
  second: Int; unused: Int; tenths: Int; sample_rate_factor: Int;
  sample_rate_multiplier: Int; activity_flags: Int; io_flags: Int;
  data_quality_flags: Int; num_blockettes: Int; time_correction: Int;
  begin_data_offset: Int; begin_blockette_offset: Int; reserved2: Int;
  record_size: Int;
}

pub fn miniseed_parse(data: &Vec[UInt8]) -> Result[MseedHeader, Str]
pub fn miniseed_build(h: &MseedHeader) -> Result[Vec[UInt8], Str]
pub fn miniseed_data_bytes(data: &Vec[UInt8], h: &MseedHeader) -> Result[Vec[UInt8], Str]

pub fn miniseed_sequence(h: &MseedHeader) -> Str
pub fn miniseed_quality(h: &MseedHeader) -> Int
pub fn miniseed_reserved(h: &MseedHeader) -> Int
pub fn miniseed_station(h: &MseedHeader) -> Str
pub fn miniseed_channel(h: &MseedHeader) -> Str
pub fn miniseed_network(h: &MseedHeader) -> Str
pub fn miniseed_location(h: &MseedHeader) -> Str
pub fn miniseed_year(h: &MseedHeader) -> Int
pub fn miniseed_day(h: &MseedHeader) -> Int
pub fn miniseed_hour(h: &MseedHeader) -> Int
pub fn miniseed_minute(h: &MseedHeader) -> Int
pub fn miniseed_second(h: &MseedHeader) -> Int
pub fn miniseed_unused(h: &MseedHeader) -> Int
pub fn miniseed_tenths(h: &MseedHeader) -> Int
pub fn miniseed_sample_rate_factor(h: &MseedHeader) -> Int
pub fn miniseed_sample_rate_multiplier(h: &MseedHeader) -> Int
pub fn miniseed_rate_num(h: &MseedHeader) -> Int
pub fn miniseed_rate_den(h: &MseedHeader) -> Int
pub fn miniseed_rate_microhz(h: &MseedHeader) -> Int
pub fn miniseed_activity_flags(h: &MseedHeader) -> Int
pub fn miniseed_io_flags(h: &MseedHeader) -> Int
pub fn miniseed_data_quality_flags(h: &MseedHeader) -> Int
pub fn miniseed_num_blockettes(h: &MseedHeader) -> Int
pub fn miniseed_time_correction(h: &MseedHeader) -> Int
pub fn miniseed_begin_data_offset(h: &MseedHeader) -> Int
pub fn miniseed_begin_blockette_offset(h: &MseedHeader) -> Int
pub fn miniseed_reserved2(h: &MseedHeader) -> Int
pub fn miniseed_record_size(h: &MseedHeader) -> Int
pub fn miniseed_data_span(h: &MseedHeader) -> Int
pub fn miniseed_sample_count(h: &MseedHeader, sample_size: Int) -> Int
pub fn miniseed_samples_fit(h: &MseedHeader, num_samples: Int, sample_size: Int) -> Bool
pub fn miniseed_required_record_size(begin_data_offset: Int, num_samples: Int, sample_size: Int) -> Int
pub fn miniseed_is_leap_year(year: Int) -> Bool
```

## 8. Accessor semantics

- Scalar readers and `miniseed_data_span` are O(1) and infallible.
- `miniseed_data_span` clamps: a hand-built header with
  `begin_data_offset < 0` or `> record_size` reports 0.
- `miniseed_rate_num` / `miniseed_rate_den` implement section 5 exactly,
  without reduction: `(40, -2)` reports `40/2`, not `20/1`.
- `miniseed_rate_microhz` truncates toward zero; the exact value is always
  non-negative, so this is a floor.
- `miniseed_sample_count` floors; `miniseed_samples_fit` compares against
  the floored quotient, which is equivalent to `n * size <= span` for
  non-negative inputs without overflow.
- `miniseed_data_bytes` validates `record_size >= 48`,
  `data.len() >= record_size` and `48 <= begin_data_offset <= record_size`
  before copying, so a drifted hand-built header cannot read out of bounds.
- `miniseed_build` validates in the documented order and emits exactly 48
  bytes; the returned vector's length is always 48 on success.
- `miniseed_is_leap_year` uses the proleptic Gregorian rule (divisible by
  4, except centuries not divisible by 400); parse year 0 is treated as a
  leap year, consistent with that rule.

## 9. Error string catalog

| Condition | Error text | Parse | Build |
|---|---|---|---|
| Buffer shorter than 48 bytes | `miniseed: truncated header` | yes | -- |
| Sequence chars/width | `miniseed: bad sequence number` | yes | yes |
| Quality byte | `miniseed: bad quality indicator` | yes | yes |
| Reserved byte | `miniseed: bad reserved byte` | yes | yes |
| Station text | `miniseed: bad station` | yes | yes |
| Channel text | `miniseed: bad channel` | yes | yes |
| Network text | `miniseed: bad network` | yes | yes |
| Location text | `miniseed: bad location` | yes | yes |
| Build year outside 0..65535 | `miniseed: bad year` | -- | yes |
| Day range / leap rule | `miniseed: bad day` | yes | yes |
| Hour range | `miniseed: bad hour` | yes | yes |
| Minute range | `miniseed: bad minute` | yes | yes |
| Second range | `miniseed: bad second` | yes | yes |
| Tenths range | `miniseed: bad tenths` | yes | yes |
| Build factor/multiplier outside i16 | `miniseed: bad sample rate` | -- | yes |
| Build flags / blockette count outside u8 | `miniseed: bad flags` | -- | yes |
| Build time correction outside i32 | `miniseed: bad time correction` | -- | yes |
| Data offset policy | `miniseed: bad data offset` | yes | yes |
| Blockette offset policy | `miniseed: bad blockette offset` | yes | yes |
| Build record size policy | `miniseed: bad record size` | -- | yes |
| Payload range does not fit the buffer | `miniseed: truncated data` | yes | -- |

## 10. Complexity

| Operation | Complexity |
|---|---|
| `miniseed_parse` | O(48) |
| scalar accessors, rate and span readers | O(1) |
| `miniseed_sample_count` / `miniseed_samples_fit` | O(1) |
| `miniseed_data_bytes` | O(payload span) |
| `miniseed_build` | O(48) |

## 11. Test plan

`tests/test_conformance.xi` (`module miniseed_tests`, 20 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the
failure count). Fixtures are assembled byte by byte, so `miniseed_parse` is
exercised against bytes the test controls, not only against
`miniseed_build`. Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | header identity | sequence, quality, reserved, station/channel/network/location, record size |
| t2 | text trimming | leading/trailing spaces, all-space sequence and location |
| t3 | start time | year, day, hour, minute, second, unused, tenths on both fixtures (incl. second 60, tenths 9999) |
| t4 | sample rate table | 40/1, 40/-2, -100/1, -1/-100, 40/0, 0/-5: num/den and micro-Hz |
| t5 | flags and spans | activity/io/data-quality flags, blockette count, i32 time correction, offsets, record size, span |
| t6 | 512 payload | span 464, `miniseed_data_bytes` equals bytes 48..512 |
| t7 | 4096 payload | span 4032, byte copy equals bytes 64..4096, required record size |
| t8 | sample policy | floor count (span 464: /4 = 116, /3 = 154), zero/negative sizes, samples-fit boundaries |
| t9 | truncation | 47-byte buffer, empty buffer, 500-byte payload cut, drifted offset -> truncated data |
| t10 | text/header errors | sequence, quality (2 values), reserved, station/channel/network/location |
| t11 | day policy | 0/367 rejected, 366 rejected in 2026, 366 accepted in 2024, 365 accepted, leap-year rule |
| t12 | time ranges | hour 24, minute 60, second 61, tenths 10000 rejected; second 60 and tenths 9999 accepted |
| t13 | offset policy | data offset 47/513 rejected, blockette offset 1 rejected, count 1 with offset 0 rejected, offset 48 accepted |
| t14 | 512 builder | byte-exact 48-byte prefix plus pinned bytes (quality, date, factor, data offset) |
| t15 | 4096 builder | byte-exact prefix plus pinned two's-complement bytes (factor -1, multiplier -100, tc -250, offsets) |
| t16 | builder padding | short sequence/location padded with spaces and re-parsed trimmed |
| t17 | canonicalisation | unused byte 7 and reserved2 0x1234 preserved on parse, written as 0 by build |
| t18 | builder errors | 23 rejection paths incl. `\u{001F}` station byte, year, flags, time correction, record size |
| t19 | build -> parse | header fields, record_size 48, span 0, sample count 0 |
| t20 | rounding | 1/-3 -> 333333 micro-Hz, 250/1 -> 250000000, 0/0 and -100/0 policies |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.miniseed
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## 12. Known limitations

- **No blockette parsing.** A record with `num_blockettes > 0` is accepted
  once its offsets are in range; the blockette contents (including the
  encoding and word order) are never read.
- **No sample decoding or Steim decompression.** Sample values, sample
  types and quality filtering are out of scope.
- **Big-endian only.** Little-endian records and word-order auto-detection
  are out of scope (section 3.3).
- **Record size is caller-supplied.** The fixed header cannot encode it;
  multi-record buffers are not walked.
- **No calendar conversion.** Start time stays as year + day-of-year; day
  366 is validated with the proleptic Gregorian rule.
- **Build canonicalises** the unused byte (27) and reserved bytes (46..47)
  to 0, so parse -> build is byte-exact only for records that already store
  0 there; build -> parse -> build is byte-stable.
- **Text is ASCII.** The fixed header's text fields are validated as
  printable ASCII `0x20..0x7E`; UTF-8 station codes are out of scope.
- **No floating point.** The rate is an exact integer rational plus a
  truncated micro-Hz integer; there is no `Float64` value anywhere.
- Whole-buffer API; plain value types; not thread-safe.

## 13. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_header`,
  `_err_header`, `_ok_bytes`, `_err_bytes`; every other function returns
  through one of them.
- Every byte read is widened with `(data[pos] as Int) & _MS_BYTE_MASK`;
  UInt8 values are never compared against Int constants without widening.
- Str values are never compared with `==`; the module performs no string
  equality at all. Accessors bind the `Str` field to a typed local before
  returning it, and the tests route every equality through
  `xiom.string.compare.str_compare`.
- Multi-byte writes use `_byte_low` (arithmetic with a negative-remainder
  correction) instead of shifts or `& 0xFF` on values that may have bit 31
  set, so negative i16/i32 fields emit exact two's-complement bytes.
- Free functions only: no methods, no lambdas, no `Vec` of structs, no
  `Vec[Float64]`, no generics, no `match`.
- The test suite binds every `&` argument to a local (never a struct field
  or a call result), following the `docs/repro/struct-field-vec` findings;
  `set_byte`/`set_be16` return fresh vectors instead of mutating in place.
- `a.exe` is generated by `port.ps1` and is gitignored.
