# xiom.streaming

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets, no I/O) wire-format codecs for
> RTP, RTCP, and RTSP. WebRTC (SDP/ICE/DTLS/SRTP), RTMP, HLS, and DASH are
> explicitly out of scope (see Limitations).
> **Deps:** `xiom.std` only. The library module imports `xiom.string` and
> `xiom.convert`; the tests also use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.streaming` turns real-time media protocol bytes and text into values
and back, with no hidden state and no I/O:

- **RTP header codec** -- `rtp_parse_header` / `rtp_build_header` cover the
  RFC 3550 fixed header (V/P/X/CC, marker, payload type, 16-bit sequence,
  32-bit timestamp, SSRC), the CSRC list, and the one-byte header extension
  (16-bit profile and 16-bit declared length in 32-bit words, with the
  extension payload copied out as bytes). The version field must be 2;
  short, overlong, and inconsistent inputs are rejected with named errors.
- **Wrap-safe arithmetic** -- `rtp_seq_before` / `rtp_seq_diff` for 16-bit
  sequence numbers and `rtp_ts_before` / `rtp_ts_diff` for 32-bit
  timestamps implement RFC 1982 serial-number rules on top of unsigned
  modular wrap; `rtp_seq_next`, `rtp_ts_add` and `rtp_ts_sub` advance
  values across the wrap boundary.
- **Interarrival jitter** -- `rtp_jitter_update` feeds arrival/send
  timestamp pairs through the RFC 3550 A.8 estimator in pure integer
  arithmetic (units: RTP ticks; division truncates toward zero, matching
  the C reference). `rtp_jitter_deltas` and `rtp_jitter_mean` expose the
  same transit deltas as a literal sliding window, and
  `rtp_jitter_to_ms` converts ticks to milliseconds for a given clock rate.
- **RTCP SR/RR basics** -- `rtcp_parse_header` (version, PT, length in
  32-bit words minus one), `rtcp_parse_rr` / `rtcp_parse_sr` with report
  block iteration (SSRC, 8-bit fixed-point fraction lost, signed 24-bit
  cumulative packets lost, extended highest sequence, jitter, LSR, DLSR),
  `rtcp_build_rr` / `rtcp_build_sr` for canonical construction, and
  per-field block accessors.
- **RTSP text messages** -- `rtsp_parse_request` / `rtsp_parse_response`
  parse the request line (method/URI/version) or status line
  (version/status/reason) plus header lines into parallel `Vec[Str]`
  fields, keeping the body verbatim; `rtsp_build_request` /
  `rtsp_build_response` emit canonical CRLF text. Header lookup
  (`rtsp_request_header_get` / `rtsp_response_header_get`) is
  case-insensitive ASCII.

Everything is a free function over `Int`, `Bool`, `Str`, `Vec[Int]`,
`Vec[Str]`, `Vec[UInt8]` and seven small struct types. Errors are a
deterministic `Err(Str)` catalog (see `SPEC.md`); an `Err` never carries a
half-built buffer.

## Install / use

```
xiom pkg install xiom.streaming@0.1.0     # consumer
xiom pkg publish                          # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.streaming;

// --- RTP -----------------------------------------------------------------
let parsed = rtp_parse_header(&packet);       // packet: Vec[UInt8]
if parsed.is_ok {
  let h: RtpHeader = parsed.value;
  let seq  = h.sequence;                      // 0..65535
  let wraps = rtp_seq_before(65534, seq);     // wrap-safe comparison
  let ext   = rtp_extension_bytes(&h);        // words * 4
  let load  = rtp_payload_len(&packet, &h);   // bytes after the header
  let pad   = rtp_padding_len(&packet, &h);   // Result[Int, Str]
  let rebuilt = rtp_build_header(&h);         // Result[Vec[UInt8], Str]
}

// --- Jitter (RFC 3550 A.8) -----------------------------------------------
var j = rtp_jitter_init();
j = rtp_jitter_update(&j, arrival_ts, send_ts);
j = rtp_jitter_update(&j, arrival_ts2, send_ts2);
let ticks = rtp_jitter_value(&j);             // RTP ticks
let ms    = rtp_jitter_to_ms(ticks, 90000);   // Result[Int, Str]

// --- RTCP ----------------------------------------------------------------
let rr = rtcp_parse_rr(&rtcp_packet);         // Result[RtcpReports, Str]
if rr.is_ok {
  let rep: RtcpReports = rr.value;
  let blocks = rtcp_block_count(&rep);
  let lost   = rtcp_block_cumulative_lost(&rep, 0);  // signed 24-bit
  let frac   = rtcp_block_fraction_lost(&rep, 0);    // value / 256
}

// --- RTSP ----------------------------------------------------------------
let req = rtsp_parse_request("OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n");
if req.is_ok {
  let r: RtspRequest = req.value;
  let cseq = rtsp_request_header_get(&r, "cseq");    // "1"
  let text = rtsp_build_request(&r);            // canonical CRLF text
}
```

## API

All functions are free functions in module `xiom.streaming`.

### RTP header

| Function | Returns | Description |
|---|---|---|
| `rtp_parse_header(data)` | `Result[RtpHeader, Str]` | Parse fixed header + CSRCs + extension; payload ignored. |
| `rtp_build_header(h)` | `Result[Vec[UInt8], Str]` | Build header bytes (validated; no payload). |
| `rtp_header_bytes(h)` | `Int` | Total header length in bytes. |
| `rtp_extension_bytes(h)` | `Int` | Declared extension payload length (`words * 4`). |
| `rtp_csrc_len(h)` | `Int` | CSRC count. |
| `rtp_csrc(h, i)` | `Int` | CSRC `i`, or -1 out of range. |
| `rtp_payload_len(data, h)` | `Int` | Bytes after the header (padding included), clamped to 0. |
| `rtp_padding_len(data, h)` | `Result[Int, Str]` | 0 without the P bit, else the validated trailer length. |

### Sequence / timestamp arithmetic

| Function | Returns | Description |
|---|---|---|
| `rtp_seq_before(a, b)` | `Bool` | RFC 1982 "a before b" on 16 bits; half range is false. |
| `rtp_seq_diff(a, b)` | `Int` | Signed distance -32768..32767. |
| `rtp_seq_next(s)` | `Int` | `(s + 1) mod 2^16`. |
| `rtp_ts_before(a, b)` | `Bool` | RFC 1982 "a before b" on 32 bits. |
| `rtp_ts_diff(a, b)` | `Int` | Signed distance -2^31..2^31-1. |
| `rtp_ts_add(ts, delta)` | `Int` | `(ts + delta) mod 2^32`; negative delta allowed. |
| `rtp_ts_sub(ts, delta)` | `Int` | `(ts - delta) mod 2^32`. |

### Interarrival jitter

| Function | Returns | Description |
|---|---|---|
| `rtp_jitter_init()` | `RtpJitter` | Fresh state (value 0, no baseline). |
| `rtp_jitter_update(st, arrival, send_ts)` | `RtpJitter` | Next state; first call only sets the baseline. |
| `rtp_jitter_value(st)` | `Int` | Current estimate in RTP ticks. |
| `rtp_jitter_to_ms(jitter, clock_rate)` | `Result[Int, Str]` | `jitter * 1000 / clock_rate`, truncated. |
| `rtp_jitter_deltas(arrivals, sends)` | `Result[Vec[Int], Str]` | Per-step `|D(i)|` values. |
| `rtp_jitter_mean(deltas, window)` | `Result[Int, Str]` | Truncated mean of the last `window` deltas. |

### RTCP

| Function | Returns | Description |
|---|---|---|
| `rtcp_parse_header(data)` | `Result[RtcpHeader, Str]` | Common header; `length_words` is words minus one. |
| `rtcp_parse_rr(data)` | `Result[RtcpReports, Str]` | First RR packet; blocks in parallel Vecs. |
| `rtcp_parse_sr(data)` | `Result[RtcpSr, Str]` | First SR packet: sender info + nested reports. |
| `rtcp_build_rr(r)` | `Result[Vec[UInt8], Str]` | Complete RR packet (8 + 24n bytes). |
| `rtcp_build_sr(s)` | `Result[Vec[UInt8], Str]` | Complete SR packet (28 + 24n bytes). |
| `rtcp_block_count(r)` | `Int` | Report block count. |
| `rtcp_block_ssrc(r, i)` | `Int` | Block SSRC, or -1 out of range. |
| `rtcp_block_fraction_lost(r, i)` | `Int` | Raw 8-bit field (actual fraction = value / 256). |
| `rtcp_block_cumulative_lost(r, i)` | `Int` | Signed 24-bit value, or 0 out of range. |
| `rtcp_block_highest_seq(r, i)` | `Int` | Extended highest sequence number. |
| `rtcp_block_jitter(r, i)` | `Int` | Jitter field in RTP ticks. |
| `rtcp_block_lsr(r, i)` | `Int` | Last-SR timestamp. |
| `rtcp_block_dlsr(r, i)` | `Int` | Delay since last SR. |

### RTSP

| Function | Returns | Description |
|---|---|---|
| `rtsp_parse_request(text)` | `Result[RtspRequest, Str]` | Request line + headers + verbatim body. |
| `rtsp_parse_response(text)` | `Result[RtspResponse, Str]` | Status line + headers + verbatim body. |
| `rtsp_build_request(r)` | `Result[Str, Str]` | Canonical CRLF request text. |
| `rtsp_build_response(r)` | `Result[Str, Str]` | Canonical CRLF response text. |
| `rtsp_request_header_count(r)` | `Int` | Header line count. |
| `rtsp_request_header_name(r, i)` | `Str` | Name `i`, "" out of range. |
| `rtsp_request_header_value(r, i)` | `Str` | Value `i`, "" out of range. |
| `rtsp_request_header_get(r, name)` | `Str` | First case-insensitive match, else "". |
| `rtsp_response_header_count(r)` | `Int` | Header line count. |
| `rtsp_response_header_name(r, i)` | `Str` | Name `i`, "" out of range. |
| `rtsp_response_header_value(r, i)` | `Str` | Value `i`, "" out of range. |
| `rtsp_response_header_get(r, name)` | `Str` | First case-insensitive match, else "". |

### Types and constants

```xi
pub type RtpHeader   = { version; padding; extension; csrc_count; marker;
                         payload_type; sequence; timestamp; ssrc; csrcs;
                         extension_profile; extension_words; extension_data;
                         header_bytes; payload_offset; }
pub type RtpJitter   = { value; has_prev; prev_arrival; prev_send; updates; }
pub type RtcpHeader  = { version; padding; count; packet_type; length_words;
                         total_bytes; }
pub type RtcpReports = { receiver_ssrc; ssrcs; fraction_lost; cumulative_lost;
                         highest_seq; jitter; lsr; dlsr; }      // parallel Vecs
pub type RtcpSr      = { sender_ssrc; ntp_msw; ntp_lsw; rtp_timestamp;
                         packet_count; octet_count; reports: RtcpReports; }
pub type RtspRequest  = { method; uri; version; names; values; body: Str; }
pub type RtspResponse = { version; status; reason; names; values; body: Str; }

pub const RTP_VERSION = 2;          pub const RTP_FIXED_HEADER_BYTES = 12;
pub const RTP_CSRC_BYTES = 4;       pub const RTP_EXTENSION_PREAMBLE_BYTES = 4;
pub const RTP_MAX_CSRC_COUNT = 15;  pub const RTP_MAX_PAYLOAD_TYPE = 127;
pub const RTP_SEQ_MOD = 65536;      pub const RTP_SEQ_HALF = 32768;
pub const RTP_SEQ_MAX = 65535;      pub const RTP_TS_MOD = 4294967296;
pub const RTP_TS_HALF = 2147483648; pub const RTP_TS_MAX = 4294967295;
pub const RTCP_VERSION = 2;         pub const RTCP_PT_SR = 200;
pub const RTCP_PT_RR = 201;         pub const RTCP_HEADER_BYTES = 4;
pub const RTCP_RR_HEADER_BYTES = 8; pub const RTCP_SR_HEADER_BYTES = 28;
pub const RTCP_REPORT_BLOCK_BYTES = 24; pub const RTCP_MAX_BLOCKS = 31;
pub const RTCP_FRACTION_MAX = 255;
pub const RTCP_CUM_LOST_MIN = -8388608; pub const RTCP_CUM_LOST_MAX = 8388607;
```

## Error model

Every fallible function returns `Result[T, Str]` with a stable, lowercase
message using `rtp:`, `rtcp:` or `rtsp:` prefixes. Errors are deterministic
and ordered; decoders validate in a fixed order documented per function in
`SPEC.md`, and an `Err` never carries a partial result. A few examples:

```
rtp: header needs 12 bytes, have 11
rtp: version 1 is not 2
rtp: extension declares 10 words, have 0 bytes
rtp: padding length 5 exceeds payload 2
rtcp: 3 report blocks need 80 bytes, packet has 56
rtcp: cumulative lost 8388608 out of range -8388608..8388607
rtsp: missing blank line after headers
rtsp: bad status code 20x
rtsp: header value 0 contains CR or LF
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.streaming
```

Expected: the namespace check passes, 21 `[PASS]` lines, and a final
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`. The suite pins
byte strings derived by hand in `SPEC.md` (RTP basic/CSRC/extension/padding
frames, an RR with two blocks, an SR with one block, RTSP request and
response messages) and asserts the full error catalog. Run the command
twice to confirm stability (the suite has no state and no I/O).

## Limitations

- **Wire formats only.** No sockets, no timers, no packet capture, no I/O
  of any kind: bytes and text go in and out as values.
- **WebRTC is out of scope.** No SDP, ICE, DTLS, SRTP, or bundling; none of
  the WebRTC control-plane formats are modeled.
- **RTMP/HLS/DASH are out of scope.** This package covers RTP/RTCP/RTSP
  only, as documented in `SPEC.md`.
- **No RTP payload formats.** The header is parsed; codec-specific payload
  structure (H.264, Opus, ...) is not. Padding is measured, not stripped:
  `rtp_payload_len` counts it and `rtp_padding_len` validates it.
- **RTCP compound packets.** Only the first packet of a compound packet is
  parsed; trailing bytes are ignored. Padding is exposed as a bit but not
  validated. SDES/BYE/XR/feedback messages are not modeled.
- **Jitter units.** The estimator works in RTP timestamp ticks supplied by
  the caller; both timestamps must share the same clock and modulus.
  Rounding is truncation toward zero (RFC 3550 reference C behavior), not
  round-to-nearest.
- **RTSP is a message grammar, not a session.** No session state, no
  interleaved TCP framing, no Content-Length enforcement, no body
  decoding. Obs-fold (continuation lines) is rejected; header lookup is
  case-insensitive ASCII.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
