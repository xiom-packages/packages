# xiom.miniseed

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** miniSEED 2.x fixed 48-byte data-record header codec: parse,
> validate and build the header, locate the payload span and derive the
> sample-rate and sample-count values.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.str_trim`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.miniseed` reads and writes the structural part of a miniSEED 2.x data
record: the 48-byte fixed header, the caller-supplied record size and the
data payload span. `miniseed_parse` validates every documented field, decodes
all multi-byte values big-endian, trims the text identifiers and returns a
flat `MseedHeader` value. The payload bytes stay in the caller's buffer and
are copied out on request. `miniseed_build` writes the canonical 48-byte
header back out.

The module is deliberately narrow:

- **Blockettes are located, never parsed.** Only their offsets
  (`begin_blockette_offset`, `num_blockettes`) are decoded; blockette 1000's
  encoding and record-length bytes are out of scope, which is why the record
  size is caller-supplied.
- **Samples are never decoded.** There is no Steim decompression and no
  sample type interpretation.
- **Big-endian only.** miniSEED 2.x fixed headers are big-endian;
  little-endian records exist, but detecting them needs the blockette 1000
  word-order flag, which this module does not read, so there is no
  little-endian variant and no auto-detection.
- **No dataless SEED, no file I/O, no threads.** The API is buffer-in /
  buffer-out over `Vec[UInt8]`.

See `SPEC.md` for the byte layout, the validation order, the sample-rate
interpretation, the error catalog and the test plan.

## Install

Not yet published. Consume it from this repository with the package harness:

```
& .\scripts\port.ps1 -Package xiom.miniseed
```

Once published, the manifest name is `xiom.miniseed` version `0.1.0`.

## API

All functions are free functions in module `xiom.miniseed`.

| Function | Returns | Description |
|---|---|---|
| `miniseed_parse(data)` | `Result[MseedHeader, Str]` | Validate one record (the whole buffer) and decode the fixed header. |
| `miniseed_build(h)` | `Result[Vec[UInt8], Str]` | Build the canonical 48-byte header. |
| `miniseed_data_bytes(data, h)` | `Result[Vec[UInt8], Str]` | Copy the payload span out of the record buffer. |
| `miniseed_sequence(h)` | `Str` | Sequence number (bytes 0..5), trimmed. |
| `miniseed_quality(h)` | `Int` | Quality indicator byte: D 68, R 82, Q 81, M 77, space 32. |
| `miniseed_reserved(h)` | `Int` | Reserved byte 7 as parsed (0 or 32). |
| `miniseed_station(h)` | `Str` | Station identifier (bytes 8..12), trimmed. |
| `miniseed_channel(h)` | `Str` | Channel identifier (bytes 13..15), trimmed. |
| `miniseed_network(h)` | `Str` | Network identifier (bytes 16..17), trimmed. |
| `miniseed_location(h)` | `Str` | Location identifier (bytes 18..19), trimmed. |
| `miniseed_year(h)` | `Int` | Start year (BE u16). |
| `miniseed_day(h)` | `Int` | Start day-of-year (BE u16), 1..366. |
| `miniseed_hour(h)` | `Int` | Start hour (0..23). |
| `miniseed_minute(h)` | `Int` | Start minute (0..59). |
| `miniseed_second(h)` | `Int` | Start second (0..60; 60 is the leap second). |
| `miniseed_unused(h)` | `Int` | Unused byte 27, preserved as parsed. |
| `miniseed_tenths(h)` | `Int` | Tenths of milliseconds (BE u16), 0..9999 (0.0001 s units). |
| `miniseed_sample_rate_factor(h)` | `Int` | Raw sample rate factor (BE i16). |
| `miniseed_sample_rate_multiplier(h)` | `Int` | Raw sample rate multiplier (BE i16). |
| `miniseed_rate_num(h)` | `Int` | Exact rate numerator in Hz (`rate = num / den`). |
| `miniseed_rate_den(h)` | `Int` | Exact rate denominator in Hz (>= 1). |
| `miniseed_rate_microhz(h)` | `Int` | Rate in integer micro-Hz, truncated toward zero. |
| `miniseed_activity_flags(h)` | `Int` | Activity flags byte 34, raw. |
| `miniseed_io_flags(h)` | `Int` | I/O and clock flags byte 35, raw. |
| `miniseed_data_quality_flags(h)` | `Int` | Data quality flags byte 36, raw. |
| `miniseed_num_blockettes(h)` | `Int` | Blockette count byte 37, raw. |
| `miniseed_time_correction(h)` | `Int` | Time correction (BE i32) in 0.0001 s units. |
| `miniseed_begin_data_offset(h)` | `Int` | Payload start offset (BE u16, >= 48). |
| `miniseed_begin_blockette_offset(h)` | `Int` | First blockette offset (BE u16, 0 when none). |
| `miniseed_reserved2(h)` | `Int` | Reserved bytes 46..47 (BE u16), preserved as parsed. |
| `miniseed_record_size(h)` | `Int` | Record size supplied to `miniseed_parse`. |
| `miniseed_data_span(h)` | `Int` | `record_size - begin_data_offset`, 0 when inconsistent. |
| `miniseed_sample_count(h, sample_size)` | `Int` | `floor(span / sample_size)`; 0 when `sample_size <= 0`. |
| `miniseed_samples_fit(h, num_samples, sample_size)` | `Bool` | Whether the span holds that many samples (no overflow). |
| `miniseed_required_record_size(bdo, num, size)` | `Int` | `bdo + num * size`, the record length implied by a sample count. |
| `miniseed_is_leap_year(year)` | `Bool` | The proleptic Gregorian leap rule used for day 366. |

`MseedHeader` is a flat value type of scalar fields (sequence, quality,
reserved, station, channel, network, location, year, day, hour, minute,
second, unused, tenths, sample_rate_factor, sample_rate_multiplier,
activity_flags, io_flags, data_quality_flags, num_blockettes,
time_correction, begin_data_offset, begin_blockette_offset, reserved2,
record_size). No `Vec` of structs and no nested structs are used anywhere.

## Quick start

Read one 512-byte record the caller already sliced out of a stream:

```xi
use xiom.miniseed;
use xiom.io;

fn report(record: &Vec[UInt8]) {
  let pr = miniseed_parse(record);
  if !pr.is_ok {
    io.println("error: " + pr.error);
    return;
  }
  let h: MseedHeader = pr.value;
  io.println(miniseed_station(&h) + "." + miniseed_channel(&h));   // "ANMO.BHZ"
  io.println(miniseed_location(&h));                                // "00"

  // 40 samples/second -> 40,000,000 micro-Hz
  io.println(miniseed_rate_microhz(&h));

  // 116 samples fit the 464 payload bytes at 4 bytes per sample.
  io.println(miniseed_sample_count(&h, 4));

  let payload = miniseed_data_bytes(record, &h);
  if payload.is_ok {
    let bytes: Vec[UInt8] = payload.value;
    io.println("payload bytes: " + bytes.len());
  }
}
```

Build a header from scratch:

```xi
let h = MseedHeader{
  sequence: "1";
  quality: 68;
  reserved: 32;
  station: "ANMO";
  channel: "BHZ";
  network: "IU";
  location: "00";
  year: 2026;
  day: 267;
  hour: 12;
  minute: 34;
  second: 56;
  unused: 0;
  tenths: 500;
  sample_rate_factor: 40;
  sample_rate_multiplier: 1;
  activity_flags: 0;
  io_flags: 0;
  data_quality_flags: 0;
  num_blockettes: 0;
  time_correction: 0;
  begin_data_offset: 48;
  begin_blockette_offset: 0;
  reserved2: 0;
  record_size: 512;
};
let built = miniseed_build(&h);   // Ok(48 bytes)
```

The builder emits the header only; the caller appends the payload. Text
fields are space-padded to their widths, and the unused byte (27) plus the
two reserved bytes (46..47) are written as 0.

## Sample rate

The `(factor, multiplier)` pair is interpreted as in the SEED manual:

| factor | multiplier | rate |
|---|---|---|
| `> 0` | `> 0` | `factor * multiplier` Hz |
| `> 0` | `< 0` | `factor / abs(multiplier)` Hz |
| `< 0` | `> 0` | `multiplier / abs(factor)` Hz |
| `< 0` | `< 0` | `1 / (abs(factor) * abs(multiplier))` Hz |
| `= 0` | any | 0 Hz (rate undefined) |
| `!= 0` | `= 0` | multiplier treated as `1` |

`miniseed_rate_num`/`miniseed_rate_den` expose the exact rational (not
reduced); `miniseed_rate_microhz` returns `num * 1,000,000 / den` truncated
toward zero. Example: factor `1`, multiplier `-3` is `1/3` Hz =
`333333` micro-Hz.

## Sample count

A miniSEED 2.x fixed header has **no number-of-samples field**: the count is
implied by the payload span and the encoding's bytes per sample, and the
encoding lives in blockette 1000 (out of scope). The module therefore:

- treats `data.len()` as the record size (the caller slices a fixed-length
  stream into records, e.g. 512 or 4096 bytes);
- computes `payload span = record_size - begin_data_offset`;
- derives `miniseed_sample_count(h, sample_size)` as `floor(span /
  sample_size)`, documented as the whole samples that fit (trailing pad bytes
  are not samples);
- checks a declared count with `miniseed_samples_fit(h, n, sample_size)`,
  evaluated as `n <= span / sample_size` so no multiplication can overflow;
- reports the record length a sample count implies through
  `miniseed_required_record_size(bdo, n, sample_size)` (`48 + 116 * 4 = 512`).

## Errors

Every failure is an `Err(Str)` with a deterministic `miniseed:` message.

| Message | Condition |
|---|---|
| `miniseed: truncated header` | Buffer shorter than 48 bytes. |
| `miniseed: bad sequence number` | Sequence bytes are not digits/spaces, or a build sequence is longer than 6 bytes. |
| `miniseed: bad quality indicator` | Quality byte is not D (68), R (82), Q (81), M (77) or space (32). |
| `miniseed: bad reserved byte` | Byte 7 is not 0x00 or 0x20. |
| `miniseed: bad station` / `miniseed: bad channel` / `miniseed: bad network` / `miniseed: bad location` | A text byte is outside 0x20..0x7E, or a build text value is longer than its field. |
| `miniseed: bad year` | Build year outside 0..65535. |
| `miniseed: bad day` | Day outside 1..366, or day 366 in a non-leap year. |
| `miniseed: bad hour` | Hour > 23 (or negative at build). |
| `miniseed: bad minute` | Minute > 59 (or negative at build). |
| `miniseed: bad second` | Second > 60 (or negative at build); 60 is allowed (leap second). |
| `miniseed: bad tenths` | Tenths > 9999 (or negative at build). |
| `miniseed: bad sample rate` | Build factor or multiplier outside -32768..32767. |
| `miniseed: bad flags` | Build flag byte or blockette count outside 0..255. |
| `miniseed: bad time correction` | Build time correction outside -2^31..2^31-1. |
| `miniseed: bad data offset` | `begin_data_offset < 48` or past the record size. |
| `miniseed: bad blockette offset` | First blockette offset is neither 0 nor inside 48..record_size, or the count is nonzero with offset 0. |
| `miniseed: bad record size` | Build `record_size < 48` or `< begin_data_offset`. |
| `miniseed: truncated data` | The header's record size or payload range does not fit the supplied buffer. |

The unused byte (27) and the two reserved bytes (46..47) are never rejected
on parse; `miniseed_build` canonicalises them to 0.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.miniseed
```

Expected: the namespace check passes, 20 `[PASS]` lines,
`xiom.miniseed: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`. The fixtures (a
512-byte and a 4096-byte record) are assembled byte by byte, so
`miniseed_parse` is exercised independently of `miniseed_build`.

## Limitations

- **Fixed header only.** Blockettes are located by offset but not parsed;
  blockette 1000, 1001 and event/calibration blockettes are out of scope, so
  the encoding, word order and record length are not read.
- **Big-endian only.** No little-endian records and no word-order
  auto-detection (see `SPEC.md` section 3).
- **No sample decoding.** No Steim-1/Steim-2 decompression, no integer or
  float sample reconstruction; only the payload bytes are copied.
- **No record-size inference from the header.** The header cannot carry it;
  the caller supplies the record size by slicing one record.
- **No multi-record stream walking.** One call parses one record; a stream
  must be sliced by the caller (fixed-length records are the documented
  case).
- **No month/day conversion.** Start time stays in SEED's year + day-of-year
  form; day 366 validation uses a proleptic Gregorian leap rule.
- **No Float64 anywhere.** The sample rate is exposed as an exact integer
  rational plus a truncated micro-Hz value.
- Whole-buffer API: the record and every copied payload live in memory.
  Plain value types; not thread-safe.

See `SPEC.md` for the full semantics and test matrix. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
