# xiom.tzif -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.tzif`, version `0.1.0`).
Module: `src/tzif.xi` (`module xiom.tzif`).
Depends on `xiom.std`; the library module imports `xiom.string` from it
(tests add `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
`xiom.encoding.hex`). No FFI.

## Scope

A pure-XIOM (no FFI) codec for TZif files as specified by RFC 8536:

- `tzif_parse` validates and decodes versions 1, 2 and 3 into a `TzifFile`
  of flat parallel vectors;
- free-function accessors read the version, counts, transition times/types,
  local time type records (utoff/isdst/designation), per-transition
  designations, leap records and indicator tables;
- `tzif_build_v1` writes a complete version 1 file from a model;
- deterministic `Err(Str)` messages for malformed input and invalid builder
  input.

## Non-goals

- POSIX TZ string parsing: the version 2/3 footer is exposed as a raw token
  (`tzif_footer`) and never interpreted.
- Local time projection (timestamp -> local time) or transition lookup.
- A version 2/3 builder (the 64-bit block is parse-only).
- Enforcing RFC `SHOULD`s and ordering rules: transition times and leap
  occurrences are not checked for strict ascending order, and the leap
  record progression rules (first occurrence nonnegative, correction
  difference one, 2419199-second spacing) are not validated.
- Streaming/incremental parsing: the whole file is an in-memory
  `Vec[UInt8]`.
- Text encoding guarantees for designations: bytes are decoded with the
  runtime `Str::from_utf8` (practice is ASCII).

## Byte-level layout

All multi-octet integers are big-endian (network octet order) with two's
complement signed values, for the 32-bit and 64-bit fields alike, as
RFC 8536 section 3 requires.

### Header (44 bytes, repeated once for v2/v3)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `54 5A 69 66` (`TZif`) |
| 4 | 1 | version: `00` v1, `32` (`'2'`) v2, `33` (`'3'`) v3 |
| 5 | 15 | reserved (not validated) |
| 20 | 4 | isutcnt (u32) |
| 24 | 4 | isstdcnt (u32) |
| 28 | 4 | leapcnt (u32) |
| 32 | 4 | timecnt (u32) |
| 36 | 4 | typecnt (u32) |
| 40 | 4 | charcnt (u32) |

RFC 8536 count rules enforced for every header: `typecnt != 0`,
`charcnt != 0`, each indicator count either 0 or exactly `typecnt`.

### Data block (v1 `TIME_SIZE` 4, v2/v3 `TIME_SIZE` 8)

| Element | Size |
|---|---|
| transition times | `timecnt * TIME_SIZE`, signed |
| transition types | `timecnt` bytes, each `< typecnt` |
| local time type records | `typecnt * 6`: utoff (4, signed) + isdst (1) + desigidx (1) |
| designation table | `charcnt` bytes |
| leap-second records | `leapcnt * (TIME_SIZE + 4)`: occur (TIME_SIZE, signed) + correction (4, signed) |
| standard/wall indicators | `isstdcnt` bytes, each 0/1 |
| UT/local indicators | `isutcnt` bytes, each 0/1 |

Designation decoding rule: the designation of a local time type starts at
its `desigidx` in the table and runs to the first NUL at or after that
position; the string may be empty and designations may overlap. A NUL must
exist at or after every `desigidx`. The `charcnt` field counts every table
byte including the trailing NULs. Validation of the block, in order:
transition type indices, then utoff (`!= -2^31`), isdst (0/1), desigidx
(`< charcnt`), designation NUL existence, leap records, indicator bytes
(0/1), then the rule that a UT/local value of 1 requires the matching
standard/wall value to be 1 when both indicator tables are present.

### Version 2/3 extension and footer

After the version 1 data block: a second 44-byte header (same magic and
version byte) and a second data block with `TIME_SIZE = 8`; then the footer

```
0x0A  TZ-string (zero or more bytes, no NUL)  0x0A
```

The version 1 block is skipped for v2/v3 files: only its header counts and
total size are validated (RFC 8536 section 4 recommends ignoring it, except
for skipping). The footer TZ string is stored raw. Nothing may follow the
closing `0x0A`, and a version 1 file may not carry anything after its data
block.

### Documented 64-bit Int-range rejection

A 64-bit signed field is read as two's complement into the signed 64-bit
`Int`. Exactly one pattern cannot be represented after negation: its
magnitude is 2^63, i.e. the bytes `80 00 00 00 00 00 00 00`
(INT64_MIN). That single pattern is rejected with
`tzif: 64-bit value out of Int range`; every other 64-bit pattern,
including `80 00 00 00 00 00 00 01` (-2^63 + 1) and all negative values
down to it, is returned exactly.

## API signatures

```xi
pub type TzifFile = {
  version: Int;
  timecnt: Int;
  typecnt: Int;
  leapcnt: Int;
  charcnt: Int;
  isstdcnt: Int;
  isutcnt: Int;
  times: Vec[Int];
  type_indices: Vec[Int];
  utoffs: Vec[Int];
  isdsts: Vec[Int];
  desig_indices: Vec[Int];
  designations: Vec[Str];
  leap_occurs: Vec[Int];
  leap_corrections: Vec[Int];
  isstd: Vec[Int];
  isut: Vec[Int];
  footer: Str;
}

pub fn tzif_parse(data: &Vec[UInt8]) -> Result[TzifFile, Str]
pub fn tzif_version(f: &TzifFile) -> Int
pub fn tzif_timecnt(f: &TzifFile) -> Int
pub fn tzif_typecnt(f: &TzifFile) -> Int
pub fn tzif_leapcnt(f: &TzifFile) -> Int
pub fn tzif_charcnt(f: &TzifFile) -> Int
pub fn tzif_isstdcnt(f: &TzifFile) -> Int
pub fn tzif_isutcnt(f: &TzifFile) -> Int
pub fn tzif_footer(f: &TzifFile) -> Str
pub fn tzif_transition_time(f: &TzifFile, i: Int) -> Result[Int, Str]
pub fn tzif_transition_type(f: &TzifFile, i: Int) -> Result[Int, Str]
pub fn tzif_type_utoff(f: &TzifFile, t: Int) -> Result[Int, Str]
pub fn tzif_type_isdst(f: &TzifFile, t: Int) -> Result[Int, Str]
pub fn tzif_type_designation(f: &TzifFile, t: Int) -> Result[Str, Str]
pub fn tzif_transition_designation(f: &TzifFile, i: Int) -> Result[Str, Str]
pub fn tzif_leap_occur(f: &TzifFile, i: Int) -> Result[Int, Str]
pub fn tzif_leap_correction(f: &TzifFile, i: Int) -> Result[Int, Str]
pub fn tzif_std_indicator(f: &TzifFile, t: Int) -> Result[Int, Str]
pub fn tzif_ut_indicator(f: &TzifFile, t: Int) -> Result[Int, Str]
pub fn tzif_build_v1(f: &TzifFile) -> Result[Vec[UInt8], Str]
```

## Semantics

`tzif_parse(data)`
: Validation order: file framing first (header, counts, block sizes,
  second header, footer, trailing bytes), then data-block contents of the
  exposed block. `Ok` means every byte of `data` was consumed by a validated
  structure. On `Err`, no partial model is returned.

`tzif_version` .. `tzif_isutcnt`
: Return the stored count fields of the exposed block (the second block for
  v2/v3). For a parsed file they equal the vector lengths; element
  accessors bound-check against the actual vector lengths so a hand-built
  `TzifFile` with drifted vectors cannot read out of bounds.

`tzif_transition_time` / `tzif_transition_type` / `tzif_type_*` /
`tzif_leap_*`
: `Err("tzif: index out of range")` when the index is negative or beyond
  the relevant vector. `tzif_type_designation` returns the decoded
  NUL-terminated designation (possibly empty);
  `tzif_transition_designation` follows the transition's type index.

`tzif_std_indicator` / `tzif_ut_indicator`
: `Err("tzif: no standard indicator table")` /
  `Err("tzif: no UT indicator table")` when the file stores no such table
  (count 0); otherwise the byte value for the type, or
  `Err("tzif: index out of range")`.

`tzif_footer`
: The raw TZ-string bytes without the two `0x0A` delimiters; `""` for
  version 1 files and for an empty TZ string.

`tzif_build_v1(f)`
: The version field must be 1. Counts are recomputed from vector lengths;
  the header count fields, stored `desig_indices` and `footer` are not
  used. The designation table is canonical: for each type in order, its
  designation string then a NUL; `desigidx` values are the offsets of those
  strings. Validation order: version, typecnt, parallel vector lengths,
  designation table construction (NUL guard, one-octet index range), then
  transition fields, ttinfo fields, leap fields and indicator fields. The
  result is `header + data block` with nothing after it.

## Error string catalog

| Condition | Error text |
|---|---|
| `tzif_parse`: `data.len() < 44` | `tzif: truncated header` |
| `tzif_parse`: bytes 0..4 are not `TZif` | `tzif: bad magic` |
| `tzif_parse`: version byte not `00`/`32`/`33` | `tzif: unsupported version` |
| counts: `typecnt == 0` | `tzif: zero time type count` |
| counts: `charcnt == 0` | `tzif: zero designation count` |
| counts: `isstdcnt` not 0 and not `typecnt` | `tzif: standard indicator count mismatch` |
| counts: `isutcnt` not 0 and not `typecnt` | `tzif: UT indicator count mismatch` |
| v1 block, or v2/v3 second block, does not fit | `tzif: data block overruns buffer` |
| v2/v3: second 44-byte header does not fit | `tzif: truncated second header` |
| v2/v3: second header magic is not `TZif` | `tzif: bad second header magic` |
| v2/v3: second header version byte differs | `tzif: second header version mismatch` |
| v2/v3: no `0x0A` after the second block or no closing `0x0A` | `tzif: missing footer` |
| v2/v3: footer TZ string contains a NUL | `tzif: NUL in footer` |
| v1: bytes after the data block; v2/v3: bytes after the closing `0x0A` | `tzif: trailing bytes` |
| block: transition type index `>= typecnt` | `tzif: transition type index out of range` |
| block: `desigidx >= charcnt` | `tzif: designation index out of range` |
| block: no NUL at or after a `desigidx` | `tzif: unterminated designation` |
| block: `utoff == -2^31` | `tzif: invalid UT offset` |
| block: `isdst` not 0/1 | `tzif: invalid DST flag` |
| block: indicator byte not 0/1 | `tzif: invalid indicator value` |
| block: `isut[i] == 1` and `isstd[i] != 1` (both tables present) | `tzif: UT indicator without standard indicator` |
| block: 64-bit field `80 00 00 00 00 00 00 00` | `tzif: 64-bit value out of Int range` |
| accessor: index negative or beyond its vector | `tzif: index out of range` |
| `tzif_std_indicator`: `isstdcnt == 0` | `tzif: no standard indicator table` |
| `tzif_ut_indicator`: `isutcnt == 0` | `tzif: no UT indicator table` |
| `tzif_build_v1`: `version != 1` | `tzif: builder writes version 1 only` |
| `tzif_build_v1`: `utoffs`/`isdsts`/`desig_indices`/`designations` lengths differ | `tzif: ttinfo vector length mismatch` |
| `tzif_build_v1`: `times`/`type_indices` lengths differ | `tzif: transition vector length mismatch` |
| `tzif_build_v1`: `leap_occurs`/`leap_corrections` lengths differ | `tzif: leap vector length mismatch` |
| `tzif_build_v1`: `isstd` length neither 0 nor typecnt | `tzif: standard indicator count mismatch` |
| `tzif_build_v1`: `isut` length neither 0 nor typecnt | `tzif: UT indicator count mismatch` |
| `tzif_build_v1`: designation index would exceed 255 | `tzif: designation table too large` |
| `tzif_build_v1`: designation string contains a NUL byte | `tzif: NUL in designation` |
| `tzif_build_v1`: transition time outside signed 32-bit | `tzif: transition time out of range` |
| `tzif_build_v1`: type index outside `0..typecnt-1` | `tzif: transition type index out of range` |
| `tzif_build_v1`: `utoff` outside signed 32-bit | `tzif: UT offset out of range` |
| `tzif_build_v1`: `utoff == -2^31` | `tzif: invalid UT offset` |
| `tzif_build_v1`: `isdst` not 0/1 | `tzif: invalid DST flag` |
| `tzif_build_v1`: leap occurrence outside signed 32-bit | `tzif: leap occurrence out of range` |
| `tzif_build_v1`: leap correction outside signed 32-bit | `tzif: leap correction out of range` |
| `tzif_build_v1`: indicator not 0/1 | `tzif: invalid indicator value` |
| `tzif_build_v1`: `isut[i] == 1` without a standard table value 1 | `tzif: UT indicator without standard indicator` |

Width/order notes: count errors are reported typecnt, charcnt, isstdcnt,
isutcnt in that order; file framing errors precede block-content errors;
for v2/v3 the second header errors precede second-block content errors.

## Complexity

| Operation | Complexity |
|---|---|
| `tzif_parse` | O(data.len()) |
| count/version/footer accessors | O(1) |
| element accessors | O(1), designation accessors O(designation length) |
| `tzif_build_v1` | O(total vector contents) |

## Test plan

`tests/test_conformance.xi` (`module tzif_tests`, 17 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The two embedded fixtures are the RFC 8536
appendix B.1 (272 bytes) and B.2 (329 bytes) example files, byte for byte.

1. RFC B.1 parses: version 1, counts `0/1/27/4/1/1`, utoff 0, designation
   `UTC`, first and last leap records, both indicators 0, empty footer;
2. v1 round-trip: parse then `tzif_build_v1` reproduces RFC B.1 exactly;
3. RFC B.2 parses as version 2 with the 64-bit block: counts
   `7/6/0/20/6/6`, the seven signed 64-bit transition times, type indices,
   utoffs, isdsts, per-type designations, per-transition designations,
   indicator tables and footer `HST10`;
4. a corrupt `isdst` byte inside the skipped version 1 block is ignored
   while the same corruption in the 64-bit block is
   `tzif: invalid DST flag`;
5. 64-bit extremes: `-9223372036854775807` and a >32-bit positive time
   parse exactly; `80 00 00 00 00 00 00 00` is
   `tzif: 64-bit value out of Int range`;
6. magic/version errors, including the second header magic and version;
7. truncated file header, truncated second header, and v1 block overrun;
8. `typecnt == 0` and `charcnt == 0`;
9. indicator count mismatch (standard and UT);
10. transition type index out of range, with a valid counterpart;
11. `desigidx` out of range, unterminated designation, and a valid empty
    designation;
12. invalid utoff (-2^31), isdst, indicator bytes, UT indicator without
    standard indicator, plus a valid indicator pair;
13. v1 trailing bytes; missing footer (two forms), NUL in footer, and v2
    trailing bytes;
14. accessor bounds and the absent-indicator-table errors;
15. v1 builder output equals independently computed pinned bytes (86
    bytes: two transitions, two types, one leap record, both indicator
    tables, canonical designation table) and parses back;
16. builder rejects bad version, out-of-range times/types/utoffs/isdsts/
    indicators, NUL-free vector mismatches, and accepts the consistent
    source;
17. hand-built v2 round-trip with +-5000000000 times and an empty footer.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.tzif
```

Last verified: compiler 0.61.3,
`port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Version 1 block of v2/v3 files: skipped after size validation; its
  contents are not validated.
- No POSIX TZ string interpretation; the footer is a raw token.
- No local time projection or transition lookup.
- No v2/v3 builder.
- Transition and leap ordering rules are not enforced (exposed as stored).
- Version 1 builder canonicalizes designations (no overlapping tables) and
  cannot express a designation containing a NUL byte. In this compiler a
  `Str` cannot carry an embedded NUL (`Str::from_utf8` truncates at it), so
  the guard is defensive; the error is not reachable through the public API
  today.
- Reserved header bytes are not required to be zero (RFC 8536 leaves them
  for future use).
- Designations are decoded as UTF-8-compatible bytes.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_file`,
  `_err_file`, `_ok_block`, `_err_block`, `_ok_bytes`, `_err_bytes`,
  `_ok_int`, `_err_int`, `_ok_str`, `_err_str` (constructing Result
  payloads elsewhere miscompiles).
- All big-endian extraction/packing is arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles (same bug documented in
  `xiom.tlv` and `xiom.msgpack`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF`.
- Str values read from `Vec[Str]` are bound to typed locals; the module
  performs no `==` on Str values.
- The package declares no `extern "C"` blocks (no FFI).
