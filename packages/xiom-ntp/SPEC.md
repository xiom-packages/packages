# xiom.ntp -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ntp`, version `0.1.0`).
Module: `src/ntp.xi` (`module xiom.ntp`).
Depends on `xiom.std`; the library module imports nothing from it (tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).

## Scope

A pure-XIOM (no FFI) codec for the fixed 48-byte NTPv4 packet header of
RFC 5905:

- `ntp_decode` reads the header, validates version and mode, and returns an
  `NtpPacket`;
- `ntp_encode` range-checks every field and writes exactly 48 big-endian
  bytes;
- `ntp_packet_valid` / `ntp_version_valid` / `ntp_mode_valid` are the
  public validation predicates;
- integer-only timestamp helpers convert a raw 2^-32 fraction to whole
  microseconds/nanoseconds and back, and a 32.32 timestamp to whole
  microseconds since the NTP epoch;
- `ntp_offset_micros` / `ntp_delay_micros` implement the RFC 5905 clock
  offset and round-trip delay formulas in whole microseconds;
- the all-zero timestamp is the "unsynchronized" marker: predicates expose
  it and the offset/delay helpers reject it;
- deterministic `Err(Str)` messages for every rejection path.

## Non-goals

- Sockets, transport, retries, server selection: this package never sends
  or receives a datagram.
- Clock discipline: offset/delay are reported, never applied; no filtering,
  slew, smear or holdover.
- NTS, authentication, MAC and extension fields: trailing bytes after the
  48-byte header are ignored on decode and never emitted on encode.
- NTP control messages (mode 6) are carried as packets; their payload
  semantics are not decoded. Mode 0 and mode 7 are rejected.
- NTPv1/NTPv2 (and the pre-1988 formats): versions other than 3 and 4 are
  rejected by decode.
- Reference-id interpretation (IPv4 address, kiss-o'-death ASCII, ...):
  the field is copied verbatim.
- Leap-second tables, UTC/TAI conversion, era disambiguation: nothing is
  inferred from a 32.32 timestamp beyond its raw seconds and fraction.
- Streaming/incremental parsing: the whole packet is an in-memory
  `Vec[UInt8]`.

## Byte-level layout

The packet is exactly `NTP_PACKET_SIZE` (48) bytes, big-endian:

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | LI / VN / Mode | bit 7..6 = LI, bit 5..3 = VN, bit 2..0 = Mode |
| 1 | 1 | Stratum | unsigned 8-bit |
| 2 | 1 | Poll | signed 8-bit, two's complement |
| 3 | 1 | Precision | signed 8-bit, two's complement |
| 4 | 4 | Root Delay | signed 16.16 fixed point |
| 8 | 4 | Root Dispersion | unsigned 16.16 fixed point |
| 12 | 4 | Reference ID | raw 32-bit |
| 16 | 8 | Reference Timestamp | 32.32 fixed point |
| 24 | 8 | Origin Timestamp | 32.32 fixed point |
| 32 | 8 | Receive Timestamp | 32.32 fixed point |
| 40 | 8 | Transmit Timestamp | 32.32 fixed point |

There is no padding, checksum or terminator: the fields above are the whole
48 bytes.

`ntp_decode` extracts the packed byte arithmetically:
`li = b0 / 64`, `vn = (b0 / 8) % 8`, `mode = b0 % 8`, where
`b0 = (data[0] as Int) & 0xFF`.

## Fixed-point conventions

- **16.16** (`root_delay`, `root_dispersion`): 1 raw unit = 2^-16 s, i.e.
  65536 units = 1 s. On the wire the 32-bit pattern is kept as-is:
  `root_delay` is signed (`-2^31 .. 2^31-1`, range about -32768 s .. 32767 s)
  and `root_dispersion` is unsigned (`0 .. 2^32-1`).
- **32.32** (timestamps): one timestamp is two raw 32-bit halves,
  `seconds` (whole seconds since 1900-01-01, NTP era 0) and `fraction`
  (units of 2^-32 s). Both halves are carried as non-negative Ints in
  `0 .. 2^32-1`; the pair is never reassembled into one 64-bit signed Int,
  so seconds with bit 31 set (after 2036-02-07) remain exact.
- **All-zero**: `seconds == 0 && fraction == 0` is the unsynchronized
  marker. `seconds == 0` with a nonzero fraction is a valid epoch-boundary
  timestamp, not the marker.
- **Fraction -> microseconds**: `fraction * 10^6 / 2^32`, truncated toward
  zero (floor on the non-negative domain). `2^32-1` maps to `999999`.
- **Fraction -> nanoseconds**: `fraction * 10^9 / 2^32`, truncated. The
  maximum product is `(2^32-1) * 10^9`, which fits in Int64.
- **Microseconds -> fraction**: `(micros * 2^32 + 500000) / 10^6`, the
  nearest unit with halfway cases rounded up. The domain is `0 .. 999999`,
  so the result stays in `0 .. 2^32-1`.
- **Nanoseconds -> fraction**: `(nanos * 2^32 + 500000000) / 10^9`, same
  rounding; domain `0 .. 999999999`.
- **Timestamp -> microseconds**: `seconds * 10^6 + truncate(fraction)*10^6/2^32`.
  The maximum is `(2^32-1) * 10^6 + 999999 = 4294967295999999`, well inside
  Int64.

## API signatures

All functions are free functions in module `xiom.ntp` (no self methods):

```xi
pub const NTP_PACKET_SIZE: Int = 48
pub const NTP_FRACTION_UNITS: Int = 4294967296
pub const NTP_FRACTION_MAX: Int = 4294967295
pub const NTP_SECONDS_MAX: Int = 4294967295
pub const NTP_VERSION_3: Int = 3
pub const NTP_VERSION_4: Int = 4
pub const NTP_MODE_SYMMETRIC_ACTIVE: Int = 1
pub const NTP_MODE_SYMMETRIC_PASSIVE: Int = 2
pub const NTP_MODE_CLIENT: Int = 3
pub const NTP_MODE_SERVER: Int = 4
pub const NTP_MODE_BROADCAST: Int = 5
pub const NTP_MODE_CONTROL: Int = 6
pub const NTP_LI_NONE: Int = 0
pub const NTP_LI_LAST_MINUTE_61: Int = 1
pub const NTP_LI_LAST_MINUTE_59: Int = 2
pub const NTP_LI_UNSYNCHRONIZED: Int = 3

pub type NtpTimestamp = { seconds: Int; fraction: Int; }
pub type NtpPacket = {
  li: Int; vn: Int; mode: Int; stratum: Int; poll: Int; precision: Int;
  root_delay: Int; root_dispersion: Int; reference_id: Int;
  reference: NtpTimestamp; origin: NtpTimestamp;
  receive: NtpTimestamp; transmit: NtpTimestamp;
}

pub fn ntp_timestamp_new(seconds: Int, fraction: Int) -> NtpTimestamp
pub fn ntp_timestamp_zero() -> NtpTimestamp
pub fn ntp_timestamp_is_zero(t: &NtpTimestamp) -> Bool
pub fn ntp_timestamp_is_valid(t: &NtpTimestamp) -> Bool
pub fn ntp_timestamp_to_micros(t: &NtpTimestamp) -> Result[Int, Str]
pub fn ntp_fraction_to_micros(fraction: Int) -> Result[Int, Str]
pub fn ntp_fraction_to_nanos(fraction: Int) -> Result[Int, Str]
pub fn ntp_micros_to_fraction(micros: Int) -> Result[Int, Str]
pub fn ntp_nanos_to_fraction(nanos: Int) -> Result[Int, Str]
pub fn ntp_version_valid(vn: Int) -> Bool
pub fn ntp_mode_valid(mode: Int) -> Bool
pub fn ntp_packet_valid(p: &NtpPacket) -> Bool
pub fn ntp_decode(data: &Vec[UInt8]) -> Result[NtpPacket, Str]
pub fn ntp_encode(p: &NtpPacket) -> Result[Vec[UInt8], Str]
pub fn ntp_offset_micros(t1_origin: &NtpTimestamp, t2_receive: &NtpTimestamp, t3_transmit: &NtpTimestamp, t4_dest: &NtpTimestamp) -> Result[Int, Str]
pub fn ntp_delay_micros(t1_origin: &NtpTimestamp, t2_receive: &NtpTimestamp, t3_transmit: &NtpTimestamp, t4_dest: &NtpTimestamp) -> Result[Int, Str]
```

## Semantics

`ntp_decode(data)`
: Requires `data.len() >= 48`; the first 48 bytes are read and any trailing
  bytes are ignored. Checks in order: length -> `vn` in 3..4 -> `mode` in
  1..6. The returned packet keeps all fields raw (zero timestamps are not
  an error). `li` is accepted for any 2-bit value.

`ntp_encode(p)`
: Checks in this order, aborting on the first failure: `li` 0..3, `vn` 3..4,
  `mode` 1..6, `stratum` 0..255, `poll` -128..127, `precision` -128..127,
  `root_delay` -2^31..2^31-1, `root_dispersion` 0..2^32-1, `reference_id`
  0..2^32-1, then `reference`, `origin`, `receive`, `transmit` (each half
  0..2^32-1). Nothing is written until every check passes; the result is
  always exactly 48 bytes.

`ntp_version_valid(vn)`
: True when `vn == 3 || vn == 4`.

`ntp_mode_valid(mode)`
: True when `mode >= 1 && mode <= 6`.

`ntp_packet_valid(p)`
: True when every range check above passes. Zero timestamps are allowed;
  this predicate checks ranges only.

`ntp_timestamp_is_zero(t)`
: True when `t.seconds == 0 && t.fraction == 0`.

`ntp_timestamp_is_valid(t)`
: True when both halves are in 0..2^32-1.

`ntp_offset_micros(t1, t2, t3, t4)`
: All four timestamps are range-checked first (T1..T4 order), then
  zero-checked. Each is truncated to whole microseconds, then
  `floor(((t2 - t1) + (t3 - t4)) / 2)` is returned (floor division, i.e.
  rounding toward negative infinity; the exact value uses RFC 5905's
  `((T2-T1) + (T3-T4)) / 2`). A positive offset means the local clock is
  behind the server.

`ntp_delay_micros(t1, t2, t3, t4)`
: Same validation, then `(t4 - t1) - (t3 - t2)` over the truncated
  microsecond values (RFC 5905's `(T4-T1) - (T3-T2)`). A nonsensical
  ordering yields a negative value rather than an error.

Mapping for a client exchange: T1 = the client transmit time (echoed by the
server as the reply's origin timestamp), T2 = the reply's receive
timestamp, T3 = the reply's transmit timestamp, T4 = the client receive
time measured locally.

## Error string catalog

| Condition | Error text |
|---|---|
| `ntp_decode`: `data.len() < 48` | `ntp: truncated packet` |
| `ntp_decode`/`ntp_encode`: `vn` outside 3..4 | `ntp: unsupported version` |
| `ntp_decode`/`ntp_encode`: `mode` outside 1..6 | `ntp: invalid mode` |
| `ntp_encode`: `li` outside 0..3 | `ntp: invalid leap indicator` |
| `ntp_encode`: `stratum` outside 0..255 | `ntp: invalid stratum` |
| `ntp_encode`: `poll` outside -128..127 | `ntp: invalid poll` |
| `ntp_encode`: `precision` outside -128..127 | `ntp: invalid precision` |
| `ntp_encode`: `root_delay` outside -2^31..2^31-1 | `ntp: invalid root delay` |
| `ntp_encode`: `root_dispersion` outside 0..2^32-1 | `ntp: invalid root dispersion` |
| `ntp_encode`: `reference_id` outside 0..2^32-1 | `ntp: invalid reference id` |
| `ntp_encode`, `ntp_timestamp_to_micros`, `ntp_fraction_to_micros`, `ntp_fraction_to_nanos`: any timestamp half / fraction outside 0..2^32-1 | `ntp: invalid timestamp` |
| `ntp_offset_micros`, `ntp_delay_micros`: any of T1..T4 is the all-zero timestamp | `ntp: zero timestamp` |
| `ntp_micros_to_fraction`: `micros` outside 0..999999 | `ntp: micros out of range` |
| `ntp_nanos_to_fraction`: `nanos` outside 0..999999999 | `ntp: nanos out of range` |

Check order is fixed as documented under `ntp_encode`; for
`ntp_offset_micros`/`ntp_delay_micros`, out-of-range errors take precedence
over zero-timestamp errors.

## Complexity

| Operation | Complexity |
|---|---|
| `ntp_decode` / `ntp_encode` | O(1) (exactly 48 bytes) |
| `ntp_packet_valid` / predicates / `ntp_timestamp_*` | O(1) |
| fraction/nanos conversions | O(1) |
| `ntp_offset_micros` / `ntp_delay_micros` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module ntp_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. a pinned 48-byte NTPv4 server packet decodes to the exact field values
   and re-encodes byte-for-byte;
2. 47 bytes and the empty buffer are `Err("ntp: truncated packet")`; 48 and
   50 bytes (trailing suffix ignored) decode;
3. versions 2 and 5 are `Err("ntp: unsupported version")` on decode and
   encode; 3 and 4 decode;
4. modes 0 and 7 are `Err("ntp: invalid mode")` on decode and encode;
   modes 1..6 decode;
5. LI occupies bits 7..6: all four LI values round-trip and LI 4/-1 are
   `Err("ntp: invalid leap indicator")`;
6. signed poll/precision (-128, 127, -1) and root delay (-1, -2^31, 2^31-1)
   use two's complement and decode back signed;
7. root dispersion and reference id boundaries (`2^32-1`) round-trip;
   negative and 2^32 values are the documented errors;
8. stratum 255 encodes, 256/-1 are `Err("ntp: invalid stratum")`; poll and
   precision out-of-range are the documented errors;
9. timestamp halves at `2^32-1` and `(0, 1)` round-trip; -1 and 2^32 are
   `Err("ntp: invalid timestamp")`;
10. zero timestamps encode as zero bytes, decode as unsynchronized, and are
    rejected by offset/delay with `Err("ntp: zero timestamp")`;
11. fraction -> microseconds table (`0`, `2^30`, `2^31`, `3*2^30`, `2^32-2`,
    `2^32-1`, `4295`) with truncation;
12. fraction -> nanoseconds table, including the `999999999` cap;
13. micros/nanos -> fraction table (nearest, halfway up: `1 us -> 4295`,
    `1 ns -> 4`, `999999 us -> 4294963001`, `999999999 ns -> 4294967292`)
    and the range errors;
14. offset/delay against the RFC formulas for a perfect exchange
    (offset 125000 us, delay 750000 us) and a symmetric zero-offset path;
15. offset floor rounding on odd microsecond sums (positive and negative),
    and exact delay for the same inputs;
16. 32.32 -> microseconds for zero, half, sub-second and maximum
    timestamps, plus the invalid-half errors;
17. `ntp_packet_valid` rejects one bad field per call (vn, mode, li,
    stratum, poll, precision, root delay, root dispersion, reference id,
    fraction) and `ntp_version_valid`/`ntp_mode_valid` cover the windows;
18. all 48 LI/VN/Mode combinations decode to the right trio and re-encode
    to the same packed byte in a 48-byte packet.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ntp
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The codec reads only the 48-byte header: extension fields and MACs after
  byte 48 are ignored, never validated or produced.
- Timestamps keep the raw `seconds`/`fraction` pair; no era resolution or
  conversion to a wall-clock date is attempted.
- Fraction conversions are not lossless inverses at full 2^-32 resolution:
  fraction -> unit floors and unit -> fraction rounds to nearest, so the
  composition can differ by one unit in the smallest place.
- Offset/delay truncate each timestamp to microseconds before arithmetic;
  the result is deterministic but not exact for sub-microsecond inputs.
- `ntp_packet_valid` checks ranges only; it does not check protocol
  plausibility (e.g. stratum vs. reference id semantics, serve flags).
- The API is stateless and pure; it does not manage packet IDs, request
  matching or retry state.
- No Float64 appears in the API or internals; all conversions are integer.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_packet` /
  `_err_packet` / `_ok_bytes` / `_err_bytes` / `_ok_int` / `_err_int`
  (constructing Results directly in other functions miscompiles).
- Byte extraction and packing are arithmetic (modulo/division with a
  negative-remainder correction); `& 0xFF`/shifts on operands with bit 31
  set miscompile in v0.61.3. This is what keeps the negative root delay and
  the 32-bit timestamp halves exact.
- Every `Vec[UInt8]` byte read widens through `(data[pos] as Int) & 0xFF`
  before entering Int arithmetic.
- Nested plain structs (`NtpPacket` containing `NtpTimestamp`) compile and
  copy safely; no `Vec[StructType]` is used.
- Free functions only: no methods, no lambdas, no indexed `Vec[fn]` test
  dispatch.
- Str comparisons go through `xiom.string.compare.str_compare`; `==` on a
  Str read from a `Vec` lowers to a pointer comparison (BUG 17). Tests
  route every expected-error comparison through `str_compare`.
- The package declares no `extern "C"` blocks (no FFI) and imports nothing
  into the library module.
