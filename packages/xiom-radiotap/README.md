# xiom.radiotap

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) codec for IEEE 802.11 radiotap capture
> headers: the 8-byte base header, the present bitmap chain (max 2 words)
> and the fixed-size data fields selected by bits 0..19, plus canonical
> re-encoding.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.radiotap` parses the radiotap header that Wireshark, `tcpdump` and
other monitor-mode capture tools put in front of each 802.11 frame. A
radiotap header is an 8-byte base header followed by one or two 4-byte
present bitmap words and then the data fields those bits select:

```
[version 0][pad][length u16 LE][present word 0 u32 LE]
[present word 1 u32 LE]          <- only when bit 31 of word 0 is set
[data fields, lsb-first, aligned within the header]
[802.11 frame bytes]             <- located by frame_off / frame_len
```

`radiotap_parse` walks present bits in ascending order, aligns and reads
each field from the fixed table (TSFT, FLAGS, RATE, CHANNEL, FHSS, signal /
noise, antenna, FCS, XCHANNEL, ...), and returns a `RadiotapHeader` index.
Set bits outside the table -- including the vendor namespace (bit 30) and
every second-word field bit -- stop the parse with a documented error
instead of guessing sizes. The frame bytes are not copied: the header
stores the offset and length of the frame span, and `radiotap_frame`
slices it out of the original buffer on demand. `radiotap_emit` re-encodes
a parsed header byte-for-byte, so parse -> emit is a canonical round trip.

## Header layout

Base header, 8 bytes (12 with a second present word):

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 1 | version | must be 0 |
| 1 | 1 | pad | skipped |
| 2 | 2 | length | header bytes, little-endian; equals the encoded size |
| 4 | 4 | present word 0 | little-endian; bit 31 chains to word 1 |
| 8 | 4 | present word 1 | only when word 0 bit 31 is set |

Field table (present bits of word 0), size and alignment relative to the
header start:

| Bit | Name | Wire | Size | Align |
|---|---|---|---|---|
| 0 | TSFT | u64 LE | 8 | 8 |
| 1 | FLAGS | u8 | 1 | 1 |
| 2 | RATE | u8 | 1 | 1 |
| 3 | CHANNEL | u16 freq + u16 flags LE | 4 | 2 |
| 4 | FHSS | u8 + u8 | 2 | 1 |
| 5 | DBM_ANTSIGNAL | i8 | 1 | 1 |
| 6 | DBM_ANTNOISE | i8 | 1 | 1 |
| 7 | LOCK_QUALITY | u16 LE | 2 | 2 |
| 8 | TX_ATTENUATION | u16 LE | 2 | 2 |
| 9 | DB_TX_ATTENUATION | u16 LE | 2 | 2 |
| 10 | DBM_TX_POWER | i8 | 1 | 1 |
| 11 | ANTENNA | u8 | 1 | 1 |
| 12 | DBM_ANTSIGNAL_2 | u8 | 1 | 1 |
| 13 | DB_ANTSIGNAL_3 | u8 | 1 | 1 |
| 14 | FCS | u8 | 1 | 1 |
| 15 | RX_FLAGS | u16 LE | 2 | 2 |
| 16 | TX_FLAGS | u16 LE | 2 | 2 |
| 17 | RTS_RETRIES | u8 | 1 | 1 |
| 18 | DATA_RETRIES | u8 | 1 | 1 |
| 19 | XCHANNEL | u32 LE | 4 | 4 |

CHANNEL is stored as `freq + flags * 65536`, FHSS as
`hop set + hop pattern * 256`, and the three i8 fields are sign-extended;
`radiotap_value` returns the stored Int for any bit.

## API

| Function | Returns | Description |
|---|---|---|
| `radiotap_parse(data)` | `Result[RadiotapHeader, Str]` | Parse base header, present words and fields; frame span recorded. |
| `radiotap_emit(h)` | `Result[Vec[UInt8], Str]` | Canonical re-encoding, fields in bit order, length recomputed. |
| `radiotap_version(h)` | `Int` | Version byte (0 on success). |
| `radiotap_length(h)` | `Int` | Header length; offset of the first frame byte. |
| `radiotap_present_count(h)` | `Int` | 1, or 2 with a chained word. |
| `radiotap_present_word(h, i)` | `Int` | Present word `i`; -1 out of range. |
| `radiotap_field_count(h)` | `Int` | Number of parsed fields. |
| `radiotap_field_bit(h, i)` | `Int` | Present bit of field `i`; -1 out of range. |
| `radiotap_field_value_at(h, i)` | `Result[Int, Str]` | Value of field `i`. |
| `radiotap_find(h, bit)` | `Int` | First field index with `bit`; -1 when absent. |
| `radiotap_value(h, bit)` | `Result[Int, Str]` | Value for `bit`; `Err` when absent. |
| `radiotap_channel_freq(h)` | `Int` | CHANNEL MHz; -1 when absent. |
| `radiotap_channel_flags(h)` | `Int` | CHANNEL flags; -1 when absent. |
| `radiotap_frame_offset(h)` | `Int` | Absolute frame start in the parsed buffer. |
| `radiotap_frame_length(h)` | `Int` | Frame bytes after the header. |
| `radiotap_frame(data, h)` | `Result[Vec[UInt8], Str]` | Copy the frame bytes out of `data`. |

Errors include `radiotap: truncated header`, `radiotap: bad version`,
`radiotap: bad length`, `radiotap: bad present chain`,
`radiotap: too many present words`, `radiotap: unsupported field`,
`radiotap: truncated field`, `radiotap: bad alignment padding`,
`radiotap: tsft out of range`, `radiotap: length mismatch` (see `SPEC.md`
for the full catalog and exact precedence).

## Usage

```xi
use xiom.radiotap;
use xiom.convert;
use xiom.io;

var capture = Vec[UInt8].new();
// ... fill `capture` with a monitor-mode capture ...

let parsed = radiotap_parse(&capture);
match parsed {
  Ok(h) => {
    io.println("header bytes: " + convert.int_to_string(radiotap_length(&h)));
    let freq = radiotap_channel_freq(&h);
    if freq >= 0 {
      io.println("channel MHz: " + convert.int_to_string(freq));
    }
    let rssi = radiotap_value(&h, 5);       // DBM_ANTSIGNAL
    if rssi.is_ok {
      io.println("signal dBm: " + convert.int_to_string(rssi.value));
    }
    let frame = radiotap_frame(&capture, &h);
    match frame {
      Ok(bytes) => { io.println("frame bytes: " + convert.int_to_string(bytes.len())); },
      Err(e) => { io.println("frame error: " + e); },
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.radiotap
```

Expected: the section-4 namespace check passes, 19 `[PASS]` lines, and a
final `port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Fixed table, bits 0..19 only.** Namespace bits 20..29, the vendor
  namespace (bit 30) and every second-word field bit are
  `radiotap: unsupported field`; vendor TLVs cannot be skipped.
- **At most two present words.** A declared third word is
  `radiotap: too many present words`. A second word is accepted only when
  its field bits are all clear.
- **Strict canonical form.** The declared length must equal the encoded
  size (no trailing slack: `radiotap: length mismatch`) and alignment
  padding must be zero bytes (`radiotap: bad alignment padding`).
- **TSFT as Int.** Values with bit 63 set do not fit and are
  `radiotap: tsft out of range`.
- **No 802.11 decoding.** Frame bytes are opaque; FCS is just a byte; RATE,
  channel flags and retry counters are returned verbatim.
- **In-memory buffers.** `radiotap_parse` and `radiotap_frame` operate on
  `Vec[UInt8]`; the frame span indexes the buffer passed to parse, and
  `radiotap_frame` copies on every call.
- **Not thread-safe.** `RadiotapHeader` is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
