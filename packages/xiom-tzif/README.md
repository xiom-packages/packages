# xiom.tzif

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) codec for TZif time zone files (RFC 8536)
> versions 1, 2 and 3, plus a version 1 builder.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` from it
> (no FFI, no other packages); the tests add `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

TZif is the binary time zone format produced by `zic` and read by most
UNIX systems. A file starts with a 44-byte header (magic `TZif`, a version
byte, six big-endian counts) followed by a data block of 32-bit transition
times, one-byte type indices, 6-byte local time type records, a
NUL-terminated designation table, leap-second records and two indicator
tables. Versions 2 and 3 append a second 44-byte header, a second data
block whose time fields are 64 bits, and a footer holding a raw POSIX TZ
string between two newline bytes.

`tzif_parse` validates the whole structure (RFC 8536 count rules, block
sizes, type/designation references, indicator values, footer framing) and
returns a `TzifFile` of flat parallel vectors: `times`, `type_indices`,
`utoffs`, `isdsts`, `desig_indices`, `designations`, `leap_occurs`,
`leap_corrections`, `isstd` and `isut`. Versions 2/3 expose the 64-bit
block; the version 1 block is size-checked and skipped, as RFC 8536
recommends. Free-function accessors read the model back with bounds checks,
`tzif_build_v1` writes a complete version 1 file, and the footer TZ string
is exposed only as a raw token (never parsed).

## API

All functions are free functions in module `xiom.tzif` (no self methods).

| Function | Returns | Description |
|---|---|---|
| `tzif_parse(data)` | `Result[TzifFile, Str]` | Parse and validate a complete v1/v2/v3 TZif file. |
| `tzif_version(f)` | `Int` | File version: 1, 2 or 3. |
| `tzif_timecnt(f)` | `Int` | Transition count of the exposed block. |
| `tzif_typecnt(f)` | `Int` | Local time type count. |
| `tzif_leapcnt(f)` | `Int` | Leap-second record count. |
| `tzif_charcnt(f)` | `Int` | Designation table byte count. |
| `tzif_isstdcnt(f)` | `Int` | Standard/wall indicator count (0 or typecnt). |
| `tzif_isutcnt(f)` | `Int` | UT/local indicator count (0 or typecnt). |
| `tzif_footer(f)` | `Str` | Raw footer TZ string; `""` for v1 or an empty TZ string. |
| `tzif_transition_time(f, i)` | `Result[Int, Str]` | Signed transition time `i`. |
| `tzif_transition_type(f, i)` | `Result[Int, Str]` | Local time type index of transition `i`. |
| `tzif_type_utoff(f, t)` | `Result[Int, Str]` | UT offset (seconds) of type `t`. |
| `tzif_type_isdst(f, t)` | `Result[Int, Str]` | DST flag of type `t` (0/1). |
| `tzif_type_designation(f, t)` | `Result[Str, Str]` | Decoded designation of type `t`. |
| `tzif_transition_designation(f, i)` | `Result[Str, Str]` | Designation of the type of transition `i`. |
| `tzif_leap_occur(f, i)` | `Result[Int, Str]` | Occurrence time of leap record `i`. |
| `tzif_leap_correction(f, i)` | `Result[Int, Str]` | Correction value of leap record `i`. |
| `tzif_std_indicator(f, t)` | `Result[Int, Str]` | Standard/wall indicator of type `t`. |
| `tzif_ut_indicator(f, t)` | `Result[Int, Str]` | UT/local indicator of type `t`. |
| `tzif_build_v1(f)` | `Result[Vec[UInt8], Str]` | Build a complete version 1 file from a model. |

Errors: `tzif: truncated header`, `tzif: bad magic`,
`tzif: unsupported version`, `tzif: zero time type count`,
`tzif: zero designation count`,
`tzif: standard indicator count mismatch`,
`tzif: UT indicator count mismatch`, `tzif: data block overruns buffer`,
`tzif: truncated second header`, `tzif: bad second header magic`,
`tzif: second header version mismatch`, `tzif: missing footer`,
`tzif: NUL in footer`, `tzif: trailing bytes`,
`tzif: transition type index out of range`,
`tzif: designation index out of range`, `tzif: unterminated designation`,
`tzif: invalid UT offset`, `tzif: invalid DST flag`,
`tzif: invalid indicator value`,
`tzif: UT indicator without standard indicator`,
`tzif: 64-bit value out of Int range`, `tzif: index out of range`,
`tzif: no standard indicator table`, `tzif: no UT indicator table`,
`tzif: builder writes version 1 only`,
`tzif: ttinfo vector length mismatch`,
`tzif: transition vector length mismatch`,
`tzif: leap vector length mismatch`, `tzif: designation table too large`,
`tzif: NUL in designation`, `tzif: transition time out of range`,
`tzif: transition type index out of range`, `tzif: UT offset out of range`,
`tzif: leap occurrence out of range`, `tzif: leap correction out of range`.
See SPEC.md for the exact conditions and validation order.

## Usage

```xi
use xiom.tzif;
use xiom.io;

// Parse a TZif file already in memory.
let parsed = tzif_parse(&bytes);
match parsed {
  Ok(f) => {
    io.println("version: " + xiom.convert.int_to_string(tzif_version(&f)));
    io.println("transitions: " + xiom.convert.int_to_string(tzif_timecnt(&f)));
    let d = tzif_transition_designation(&f, 0);
    if d.is_ok {
      io.println("first designation: " + d.value);
    }
    io.println("footer TZ string: " + tzif_footer(&f));
  },
  Err(e) => { io.println("parse error: " + e); },
}

// Rebuild a parsed version 1 file byte for byte.
let built = tzif_build_v1(&f);
if built.is_ok {
  // built.value holds a complete version 1 TZif image.
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.tzif
```

Expected: the section-4 namespace check passes, 17 `[PASS]` lines, and a
final `port: PASS (passed=17 failed=0 program_exit=0 exit=0)`. The two
largest fixtures are the byte-for-byte example files of RFC 8536
appendices B.1 (version 1 UTC with 27 leap seconds) and B.2 (version 2
Pacific/Honolulu); the suite also rebuilds B.1 from its parse result and
compares the bytes.

## Limitations

- **No POSIX TZ string parsing.** The version 2/3 footer is kept as a raw
  token (`tzif_footer`); interpreting `HST10`-style rules is out of scope.
- **No local time projection.** The codec never maps a timestamp to local
  time; it exposes transitions and local time types only.
- **Versions 2/3 are parse-only.** `tzif_build_v1` writes version 1 files
  only; there is no 64-bit builder.
- **The version 1 block of a v2/v3 file is skipped.** Its header counts and
  total size are validated so the second header can be located, but its
  data contents are not checked (RFC 8536 section 4 recommends ignoring
  them).
- **Ordering is not enforced.** Transition times and leap occurrences are
  exposed exactly as stored; the RFC `SHOULD`/ordering rules and the
  leap-correction progression rules are not validated.
- **Version 1 builder canonicalizes designations.** Each type's string is
  written followed by a NUL in type order and the indices are recomputed;
  overlapping designation tables cannot be expressed.
- **Designations are decoded with `Str::from_utf8`.** RFC 8536 leaves the
  designation encoding unspecified; this codec assumes UTF-8-compatible
  bytes (practice is ASCII).
- Not thread-safe; `TzifFile` is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
