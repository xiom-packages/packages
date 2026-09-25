# xiom.ntp

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM NTPv4 packet codec (RFC 5905 subset): 48-byte
> encode/decode, version/mode validation, integer-only 32.32 timestamp
> math, and offset/delay helpers in whole microseconds.
> **Deps:** `xiom.std` only. The library module is dependency-free; the
> tests use `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.ntp` encodes and decodes the fixed 48-byte NTPv4 packet header from
RFC 5905: the packed LI/VN/Mode byte, stratum, poll, precision, root delay
and root dispersion (16.16 fixed point), reference id, and the
reference/origin/receive/transmit timestamps (32.32 fixed point, seconds
since the 1900 NTP epoch). It also provides the RFC 5905 offset and
round-trip delay formulas, computed in whole microseconds with integer
math only -- no `Float64` anywhere.

The codec is deliberately protocol-only: it never touches a socket, the
system clock, or the local clock discipline. A decoded packet whose
timestamps are all zero is returned as-is; the all-zero timestamp is the
NTP "unsynchronized" marker, and the offset/delay helpers refuse it.

Fixed-point conventions:

- **16.16** (root delay, root dispersion): 32 raw units per 1/65536 s.
  Root delay is signed, root dispersion is unsigned.
- **32.32** (timestamps): each timestamp is carried as two raw 32-bit
  halves, `seconds` and `fraction` (1 fraction unit = 2^-32 s). No 64-bit
  signed intermediate is ever formed, so the values stay exact across the
  2036 era boundary.
- **Microseconds/nanoseconds**: fraction -> unit truncates toward zero;
  unit -> fraction rounds to the nearest 2^-32 unit, halfway cases up.

## API

| Function | Returns | Description |
|---|---|---|
| `ntp_decode(data)` | `Result[NtpPacket, Str]` | Decode the first 48 bytes; reject bad version/mode. |
| `ntp_encode(p)` | `Result[Vec[UInt8], Str]` | Encode a packet as exactly 48 bytes; range-check every field first. |
| `ntp_packet_valid(p)` | `Bool` | True when every field is in range (zero timestamps allowed). |
| `ntp_version_valid(vn)` | `Bool` | True for version 3 or 4. |
| `ntp_mode_valid(mode)` | `Bool` | True for modes 1..6. |
| `ntp_timestamp_new(seconds, fraction)` | `NtpTimestamp` | Raw constructor (no validation). |
| `ntp_timestamp_zero()` | `NtpTimestamp` | The all-zero unsynchronized timestamp. |
| `ntp_timestamp_is_zero(t)` | `Bool` | True only when both halves are zero. |
| `ntp_timestamp_is_valid(t)` | `Bool` | True when both halves are in 0..2^32-1. |
| `ntp_timestamp_to_micros(t)` | `Result[Int, Str]` | Seconds and fraction as microseconds since the NTP epoch. |
| `ntp_fraction_to_micros(fraction)` | `Result[Int, Str]` | Raw 2^-32 fraction -> whole microseconds (floor). |
| `ntp_fraction_to_nanos(fraction)` | `Result[Int, Str]` | Raw 2^-32 fraction -> whole nanoseconds (floor). |
| `ntp_micros_to_fraction(micros)` | `Result[Int, Str]` | Whole microseconds -> nearest raw fraction. |
| `ntp_nanos_to_fraction(nanos)` | `Result[Int, Str]` | Whole nanoseconds -> nearest raw fraction. |
| `ntp_offset_micros(t1, t2, t3, t4)` | `Result[Int, Str]` | RFC 5905 offset `((T2-T1)+(T3-T4))/2` in microseconds. |
| `ntp_delay_micros(t1, t2, t3, t4)` | `Result[Int, Str]` | RFC 5905 delay `(T4-T1)-(T3-T2)` in microseconds. |

Types: `NtpTimestamp { seconds, fraction }` and `NtpPacket { li, vn, mode,
stratum, poll, precision, root_delay, root_dispersion, reference_id,
reference, origin, receive, transmit }`. Constants: `NTP_PACKET_SIZE`,
`NTP_FRACTION_UNITS`, `NTP_FRACTION_MAX`, `NTP_SECONDS_MAX`,
`NTP_VERSION_3/4`, `NTP_MODE_*`, `NTP_LI_*`.

Errors: `ntp: truncated packet`, `ntp: unsupported version`,
`ntp: invalid mode`, `ntp: invalid leap indicator`, `ntp: invalid
stratum`, `ntp: invalid poll`, `ntp: invalid precision`, `ntp: invalid
root delay`, `ntp: invalid root dispersion`, `ntp: invalid reference id`,
`ntp: invalid timestamp`, `ntp: zero timestamp`, `ntp: micros out of
range`, `ntp: nanos out of range` (see SPEC.md for the exact conditions).

## Usage

```xi
use xiom.ntp;
use xiom.io;

// Decode a 48-byte server reply captured from the wire.
let reply = ntp_decode(&wire);
match reply {
  Ok(p) => {
    io.println("stratum " + xiom.convert.int_to_string(p.stratum));
    // T1 = the origin timestamp echoed back by the server
    // T2 = the server receive timestamp, T3 = the server transmit stamp,
    // T4 = the local receive time measured by the caller.
    let t1: NtpTimestamp = p.origin;
    let t2: NtpTimestamp = p.receive;
    let t3: NtpTimestamp = p.transmit;
    let t4 = ntp_timestamp_new(3944000000, 0);
    let off = ntp_offset_micros(&t1, &t2, &t3, &t4);
    if off.is_ok {
      io.println("offset us: " + xiom.convert.int_to_string(off.value));
    }
    let rtt = ntp_delay_micros(&t1, &t2, &t3, &t4);
    if rtt.is_ok {
      io.println("delay us: " + xiom.convert.int_to_string(rtt.value));
    }
  },
  Err(e) => { io.println("decode error: " + e); },
}

// Build a client request: LI=0, VN=4, Mode=3, transmit time set.
var request = NtpPacket{
  li: NTP_LI_NONE;
  vn: NTP_VERSION_4;
  mode: NTP_MODE_CLIENT;
  stratum: 0;
  poll: 6;
  precision: -20;
  root_delay: 0;
  root_dispersion: 0;
  reference_id: 0;
  reference: ntp_timestamp_zero();
  origin: ntp_timestamp_zero();
  receive: ntp_timestamp_zero();
  transmit: ntp_timestamp_new(3944000000, 0);
};
let bytes = ntp_encode(&request);
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ntp
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No sockets.** `xiom.ntp` is a codec: sending/receiving datagrams,
  retries, and server selection are the caller's job.
- **No clock discipline.** Offset/delay are reported, never applied; no
  filtering, no slew/smear, no holdover.
- **No NTS or authentication extensions.** Trailing bytes after the 48-byte
  header are ignored on decode; MAC/extension fields are not modeled and
  `ntp_encode` never emits them.
- **Fixed version window.** Versions 3 and 4 decode; version 1/2 packets
  are rejected as `ntp: unsupported version`. Modes 0 and 7 are rejected.
- **Reference id is opaque.** The 32-bit field is returned raw; its
  stratum-dependent meaning (IPv4 address, kiss-o'-death code, ...) is not
  interpreted.
- **Truncated fractions.** Fraction -> microsecond/nanosecond conversion
  floors, so it is not an exact inverse of the nearest-unit round trip at
  full resolution; the documented pinned values are what the tests check.
- **Not thread-safe by construction** (plain value types, no shared state);
  no synchronization is needed for the pure functions.
- **No leap-second table.** Leap-indicator bits are carried through
  verbatim; no conversion between UTC, TAI or the leap-second list.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
