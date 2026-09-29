# xiom.streaming -- SPEC

> **Status:** implemented, 21/21 conformance checks green on the pinned
> toolchain (v0.62.1, stdlib `E:\xiom-lang\stdlib`), not yet published.
> **Scope:** RTP (RFC 3550 header), wrap-safe sequence/timestamp
> arithmetic, interarrival jitter, RTCP SR/RR basics, and RTSP text
> messages. WebRTC (SDP/ICE/DTLS/SRTP), RTMP, HLS and DASH are explicitly
> **out of scope**.

All byte offsets are from the start of the packet/message. All arithmetic
is 64-bit signed `Int`; unsigned wire values never reach 2^32 so no sign
bit is involved, and bit fields are extracted with divisor/modulo
arithmetic rather than shifts or masks.

---

## 1. RTP fixed header (RFC 3550 section 5.1)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|X|  CC   |M|     PT      |       sequence number         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           timestamp                           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|           synchronization source (SSRC) identifier            |
+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
|            contributing source (CSRC) identifiers             |
:                             ....                              :
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|      defined by profile       |           length              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        header extension                       |
:                             ....                              :
```

| Field | Bytes | Extraction |
|---|---|---|
| V (version) | 0, bits 7-6 | `b0 / 64` (must equal 2) |
| P (padding) | 0, bit 5 | `(b0 % 64) / 32 == 1` |
| X (extension) | 0, bit 4 | `((b0 % 64) % 32) / 16 == 1` |
| CC (CSRC count) | 0, bits 3-0 | `b0 % 16` |
| M (marker) | 1, bit 7 | `b1 / 128 == 1` |
| PT (payload type) | 1, bits 6-0 | `b1 % 128` |
| sequence number | 2-3 | big-endian 16-bit |
| timestamp | 4-7 | big-endian 32-bit |
| SSRC | 8-11 | big-endian 32-bit |
| CSRC list | 12 .. 12+4*CC-1 | CC big-endian 32-bit values |
| extension profile | after CSRCs | big-endian 16-bit |
| extension length | +2 | big-endian 16-bit, in 32-bit words |
| extension data | +4 | `length * 4` bytes, copied verbatim |

`header_bytes` = 12 + 4*CC, plus 4 + 4*extension_words when X is set.
`payload_offset` = `header_bytes`.

**Parsing order** (`rtp_parse_header`): length 12 -> version = 2 ->
CSRC list present -> extension preamble present -> extension data present.
Trailing bytes after the declared header are the payload and never cause a
failure: the parser accepts a full packet, and the payload/padding views
are computed on demand.

**Building order** (`rtp_build_header`): version -> CSRC count -> CSRC
count vs `csrcs.len()` -> each CSRC -> payload type -> sequence ->
timestamp -> SSRC -> extension words -> extension data length ->
extension profile -> (when X clear) both extension fields must be
zero/empty. Nothing is written before all checks pass.

### 1.1 Padding

When P = 1 the last packet byte is the pad count, itself included
(RFC 3550 section 5.1). `rtp_padding_len` returns 0 when P = 0; otherwise
the pad count must be 1..payload_len, where payload_len =
`rtp_payload_len` = `data.len() - payload_offset` (clamped to 0).
`rtp_payload_len` counts padding bytes; the media payload is
`rtp_payload_len - rtp_padding_len`.

---

## 2. Wrap-safe arithmetic (RFC 1982 on unsigned modular wrap)

For 16-bit sequence numbers, `mod = 2^16 = 65536`, `half = 2^15 = 32768`:

```
d(a, b) = (b - a) mod 65536                 // normalized to 0..65535
seq_before(a, b) = d != 0 and d < 32768
seq_diff(a, b)   = d          if d <= 32767
                 = d - 65536  otherwise
seq_next(s)      = (s + 1) mod 65536
```

For 32-bit timestamps, the same rules with `mod = 2^32`,
`half = 2^31 = 2147483648`; `ts_add(ts, delta) = (ts + delta) mod 2^32`
and `ts_sub(ts, delta) = (ts - delta) mod 2^32`, both accepting negative
deltas.

**Half-range convention:** the exactly-ambiguous distance (`d == half`)
resolves to "not before" in both directions and to `-half` in the signed
difference. This makes the functions total and deterministic:

| a | b | seq_before | seq_diff |
|---|---|---|---|
| 65534 | 1 | true | 3 |
| 1 | 65534 | false | -3 |
| 0 | 32767 | true | 32767 |
| 0 | 32768 | false | -32768 |
| 32768 | 0 | false | -32768 |
| 5 | 5 | false | 0 |

| a | b | ts_before | ts_diff |
|---|---|---|---|
| 4294967290 | 4 | true | 10 |
| 4 | 4294967290 | false | -10 |
| 0 | 2147483647 | true | 2147483647 |
| 0 | 2147483648 | false | -2147483648 |
| 4294967295 | 0 | true | 1 |
| 7 | 7 | false | 0 |

Modular reduction is implemented with `%` plus a negative-remainder
correction (the compiler language truncates toward zero).

---

## 3. Interarrival jitter (RFC 3550 A.8)

State: `RtpJitter { value; has_prev; prev_arrival; prev_send; updates }`.

With arrival timestamps `R_i` and sender timestamps `S_i` (same clock,
32-bit modulus, typically a 90 kHz video or 48 kHz audio clock):

```
D(i) = (R_i - R_{i-1}) - (S_i - S_{i-1})      // wrap-safe via rtp_ts_diff
J(i) = J(i-1) + (|D(i)| - J(i-1)) / 16
```

- **Units:** RTP timestamp ticks. Jitter in milliseconds:
  `jitter * 1000 / clock_rate` (`rtp_jitter_to_ms`), truncated.
- **Rounding:** division truncates toward zero, matching the C reference
  implementation in RFC 3550 A.8 (not round-to-nearest, not arithmetic
  shift). `(ad - value) / 16` can be negative; truncation toward zero
  makes the decay slightly slower than a floor division would.
- **First call:** only records the baseline; `value` stays 0 and `updates`
  stays 0. Every later call increments `updates`.
- `value` is always >= 0: the update can decrease it by at most
  `ceil(value / 16) < value` when `value >= 1`.

**Worked example** (pinned in the suite): arrivals
`0, 4600, 6000, 9000`, sends `0, 3000, 6000, 9000`:

| i | R_i - R_{i-1} | S_i - S_{i-1} | D(i) | J(i) |
|---|---|---|---|---|
| 1 | 4600 | 3000 | +1600 | 0 + 1600/16 = **100** |
| 2 | 1400 | 3000 | -1600 | 100 + (1600-100)/16 = **193** |
| 3 | 3000 | 3000 | 0 | 193 + (0-193)/16 = 193 - 12 = **181** |

`rtp_jitter_to_ms(181, 90000)` = 181000/90000 = **2 ms**.

**Sliding window:** `rtp_jitter_deltas(arrivals, sends)` returns the
`|D(i)|` series (length `n - 1`, or empty for `n < 2`);
`rtp_jitter_mean(deltas, window)` returns the truncated arithmetic mean
of the last `min(window, len)` deltas (0 for an empty series), i.e. the
literal finite-window view of the same deltas the EWMA consumes with
decay 1/16.

---

## 4. RTCP (RFC 3550 section 6)

### 4.1 Common header (4 bytes)

```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|  count  |       PT      |          length               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Field | Bytes | Extraction |
|---|---|---|
| V | 0, bits 7-6 | `b0 / 64` (must equal 2) |
| P | 0, bit 5 | `(b0 % 64) / 32 == 1` (exposed, not validated) |
| count | 0, bits 4-0 | `b0 % 32` (report/sender block count) |
| PT | 1 | 200 = SR, 201 = RR in this package |
| length | 2-3 | big-endian 16-bit, **packet length in 32-bit words minus one** |

`total_bytes = (length_words + 1) * 4`. A parser requires
`data.len() >= total_bytes`; any trailing bytes (compound packet members)
are ignored, and only the first packet is parsed.

### 4.2 RR layout

```
0               4               8
+---------------+---------------+
| common header | receiver SSRC |
+---------------+---------------+
| report block 0 (24 bytes)     |
| ... count blocks ...          |
```

### 4.3 SR layout

```
0               4               8
+---------------+---------------+
| common header |  sender SSRC  |
+---------------+---------------+
| NTP msw (4)   | NTP lsw (4)   |   } sender info:
| RTP ts (4)    | pkt count (4) |   } 20 bytes after the sender SSRC
| octet count(4)| report block 0 (24) ...
```

### 4.4 Report block (24 bytes)

| Offset | Size | Field | Interpretation |
|---|---|---|---|
| +0 | 4 | SSRC_1 | unsigned 32-bit |
| +4 | 1 | fraction lost | fixed point: value / 256 |
| +5 | 3 | cumulative packets lost | **signed** 24-bit: values >= 2^23 map to value - 2^24 |
| +8 | 4 | extended highest sequence | unsigned 32-bit (cycles in the high 16 bits) |
| +12 | 4 | interarrival jitter | unsigned 32-bit RTP ticks |
| +16 | 4 | LSR | unsigned 32-bit (NTP middle 32 bits of the last SR) |
| +20 | 4 | DLSR | unsigned 32-bit, units of 1/65536 s |

**Parsing/building order** (`rtcp_parse_rr`, `rtcp_parse_sr`): common
header -> packet type -> minimum bytes (8 for RR, 28 for SR) -> declared
length vs available bytes -> `min_bytes + 24 * count <= total_bytes`.
Building validates receiver/sender SSRC, block count 0..31, the seven
parallel Vec lengths against each other, and each field range.

---

## 5. RTSP text messages

Grammar accepted (RFC 2326 style, headers-only level):

```
request  = Method SP URI SP Version CRLF *( header CRLF ) CRLF [ body ]
response = Version SP Status-Code [ SP Reason-Phrase ] CRLF
           *( header CRLF ) CRLF [ body ]
header   = Name ":" *( SP / HTAB ) value
```

- Lines end with LF or CRLF (a CR immediately before the LF is dropped).
- Version = `"RTSP/"` followed by a digit (at least 6 characters;
  `RTSP/1.0` and `RTSP/2.0` both pass).
- Request line: exactly single-space separators, three non-empty tokens
  with no spaces inside; anything else is `rtsp: bad request line`.
- Status code: exactly three decimal digits, 100..999. A missing reason
  phrase is accepted and stored as `""`.
- Header names are stored untrimmed and must be non-empty and free of
  SP/HTAB/CR/LF/`:`; values are trimmed of leading/trailing SP/HTAB.
  Obs-fold (a line starting with SP/HTAB) is rejected.
- The blank line terminating the headers is required; everything after it
  is the body, verbatim.
- `rtsp_build_*` emits canonical CRLF text: request/status line, one
  `Name: value` line per pair, blank line, body. An empty reason phrase is
  emitted without its separating space, so `"RTSP/1.0 200"` round-trips.
- Header lookup is case-insensitive ASCII, first match wins.

---

## 6. Error catalog (exact strings)

Decoders report the first failing check in the order listed. `N`, `M`, `T`,
`B`, `C` are decimal values via `convert.int_to_string`.

### RTP parse (`rtp_parse_header`)

1. `rtp: header needs 12 bytes, have N`
2. `rtp: version N is not 2`
3. `rtp: header needs N bytes, have M` (CSRC list or extension preamble)
4. `rtp: extension declares N words, have M bytes`

### RTP padding (`rtp_padding_len`)

1. `rtp: padding set but packet has no payload`
2. `rtp: padding length N out of range 1..M`
3. `rtp: padding length N exceeds payload M`

### RTP build (`rtp_build_header`)

1. `rtp: version N is not 2`
2. `rtp: csrc count N out of range 0..15`
3. `rtp: csrc count N does not match M identifiers`
4. `rtp: csrc N out of range 0..4294967295`
5. `rtp: payload type N out of range 0..127`
6. `rtp: sequence N out of range 0..65535`
7. `rtp: timestamp N out of range 0..4294967295`
8. `rtp: ssrc N out of range 0..4294967295`
9. `rtp: extension words N out of range 0..65535`
10. `rtp: extension declares N words but data is M bytes`
11. `rtp: extension profile N out of range 0..65535`
12. `rtp: extension flag clear but extension words is N`
13. `rtp: extension flag clear but extension data is N bytes`

### Jitter helpers

- `rtp: clock rate N out of range 1..1000000000`
- `rtp: arrivals N do not match sends M`
- `rtp: jitter window N is not positive`

### RTCP (`rtcp_parse_header`, `rtcp_parse_rr`, `rtcp_parse_sr`, builders)

1. `rtcp: packet needs 4 bytes, have N`
2. `rtcp: version N is not 2`
3. `rtcp: packet type N is not 201` (RR) / `rtcp: packet type N is not 200` (SR)
4. `rtcp: packet needs 8 bytes, have N` (RR) / `rtcp: packet needs 28 bytes, have N` (SR)
5. `rtcp: packet length says T bytes, have N`
6. `rtcp: C report blocks need B bytes, packet has T`
7. `rtcp: receiver ssrc N out of range 0..4294967295`
8. `rtcp: sender ssrc N out of range 0..4294967295`
9. `rtcp: ntp msw N out of range 0..4294967295` / `rtcp: ntp lsw N ...`
10. `rtcp: rtp timestamp N out of range 0..4294967295`
11. `rtcp: packet count N ...` / `rtcp: octet count N ...`
12. `rtcp: block count N out of range 0..31`
13. `rtcp: block field count L does not match N`
14. `rtcp: ssrc N out of range 0..4294967295`
15. `rtcp: fraction lost N out of range 0..255`
16. `rtcp: cumulative lost N out of range -8388608..8388607`
17. `rtcp: highest sequence N ...` / `rtcp: jitter N ...` /
    `rtcp: lsr N ...` / `rtcp: dlsr N ... out of range 0..4294967295`

### RTSP parse

1. `rtsp: empty message`
2. `rtsp: missing blank line after headers`
3. `rtsp: bad request line`
4. `rtsp: bad status line`
5. `rtsp: bad version X`
6. `rtsp: bad status code X`
7. `rtsp: status code N out of range 100..999`
8. `rtsp: folded header not supported`
9. `rtsp: bad header line`
10. `rtsp: bad header name X`

### RTSP build

1. `rtsp: method is empty`
2. `rtsp: method contains space`
3. `rtsp: uri is empty`
4. `rtsp: uri contains space`
5. `rtsp: bad version X`
6. `rtsp: status code N out of range 100..999`
7. `rtsp: reason contains CR or LF`
8. `rtsp: header count mismatch N vs M`
9. `rtsp: header name N is empty`
10. `rtsp: header name N is invalid`
11. `rtsp: header value N contains CR or LF`

---

## 7. Pinned fixtures (used by `tests/test_conformance.xi`)

RTP basic (`t1`): `80E0 7724 000F4240 DEADBEEF` + payload `AA BB`
(seq 30500, ts 1000000, SSRC 3735928559, M=1, PT=96).

RTP CSRC + extension (`t2`/`t3`):

```
92 61 0000 FFFFFFFF 01020304
11 12 13 14   21 22 23 24          CSRCs
BE DE 00 03                        profile 0xBEDE, 3 words
01 02 03 04 05 06 07 08 09 0A 0B 0C
DE AD                              payload
```

(header 36 bytes; SSRC 0x01020304; ts 0xFFFFFFFF.)

RTP padding (`t4`): `A0 60 0001 0000005A CAFEBABE 41 42 43 03`
(payload 4 bytes, pad count 3).

RTCP RR (`t11`-`t13`), 56 bytes total, receiver SSRC 0x0A0B0C0D:

```
82 C9 000D 0A0B0C0D
01 02 03 04 19 00012C 00010001 00000064 00000001 00000002
A1 A2 A3 A4 00 FFFFFB 00000000 80000000 FFFFFFFF 7FFFFFFF
```

(block 0: ssrc 16909060, fraction 25, cumulative +300, highest 65537,
jitter 100, LSR 1, DLSR 2; block 1: ssrc 2711790500, fraction 0,
cumulative -5, highest 0, jitter 2^31, LSR 2^32-1, DLSR 2^31-1.)

RTCP SR (`t14`/`t15`), 52 bytes total:

```
81 C8 000C 00000001
E0000000 00000001 0000EA60 00000064 00003200
00 000002 40 000064 00000005 0000000A 00000003 00000004
```

(sender SSRC 1; NTP msw 0xE0000000, lsw 1; RTP ts 60000; 100 packets;
12800 octets; block: ssrc 2, fraction 64, cumulative 100, highest 5,
jitter 10, LSR 3, DLSR 4.)

RTSP request (`t17`/`t18`):

```
DESCRIBE rtsp://camera.example/stream RTSP/1.0\r\n
CSeq: 2\r\n
Accept: application/sdp\r\n
Content-Length: 4\r\n
\r\n
body
```

RTSP response (`t19`):

```
RTSP/1.0 200 OK\r\n
CSeq: 1\r\n
Server: xiom.streaming/0.1.0\r\n
Content-Length: 5\r\n
\r\n
hello
```

---

## 8. Test plan

`tests/test_conformance.xi` runs 21 checks, each printing `[PASS]` or
`[FAIL]`; `main` returns the failure count, so the port harness's
`program_exit=0` is required for green.

| # | Test | Covers |
|---|---|---|
| 1 | rtp parse pinned basic header | field extraction, payload ignored |
| 2 | rtp parse CSRC + extension | CC list, profile/words/data, header_bytes |
| 3 | rtp build pinned bytes | parsed->built identity, hand-built, determinism |
| 4 | rtp padding | P bit, pad trailer, three padding errors |
| 5 | rtp parse errors | short, version, CSRC overrun, extension overrun |
| 6 | rtp build errors | 13-message catalog |
| 7 | sequence wrap table | before/diff/next incl. half range |
| 8 | timestamp wrap table | before/diff/add/sub incl. half range |
| 9 | jitter EWMA | 100, 193, 181; wrap-safe; ms conversion |
| 10 | jitter window | deltas series, mean, window errors |
| 11 | rtcp RR header | version/PT/length-words/total bytes |
| 12 | rtcp RR blocks | fraction, signed cumulative, seq, jitter, LSR/DLSR |
| 13 | rtcp build RR | pinned bytes, negative loss round trip |
| 14 | rtcp SR parse | sender info + nested block |
| 15 | rtcp build SR | pinned bytes, parse back |
| 16 | rtcp errors | bounds, PT, counts, field ranges, SR fields |
| 17 | rtsp parse request | fields, headers, lookup, body, LF/CRLF |
| 18 | rtsp build request | canonical text, round trip |
| 19 | rtsp response | status/reason/headers/body, empty reason, LF |
| 20 | rtsp parse errors | 12-message catalog |
| 21 | rtsp build errors | 11-message catalog |

Verify from the repository root:

```
& .\scripts\port.ps1 -Package xiom.streaming
```

Expected tail: `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.
Run twice for stability.

---

## 9. Toolchain notes (pinned v0.62.1)

- Free functions only; no methods, lambdas, or `Vec[StructType]`. CSRC
  lists and RTCP report blocks are parallel `Vec` fields in plain types.
- `Ok`/`Err` are constructed only in the leaf `_ok_*` / `_err_*` helpers.
- Every byte read from a `Vec[UInt8]` or `Str` is widened with
  `(x as Int) & 0xFF` before any comparison (`byte_at` comparisons at
  >= 128 are still miscompiled).
- Bit fields use divisor/modulo arithmetic; 32-bit packing uses the
  negative-safe `_be_byte` extractor; no shift or mask touches a value
  that could carry the sign bit.
- `Str` values read from `Vec[Str]` are bound to typed locals and compared
  byte by byte (never `==`); header lookup lowercases ASCII bytes.
- `&mut` call sites are explicit (`_push_be(&mut out, ...)`).
- No `Vec[Float64]`, no floating-point math anywhere.
- Angle brackets are canonical `Vec[...]` / `Result[...]` only.
