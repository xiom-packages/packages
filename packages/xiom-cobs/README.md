# xiom.cobs

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) COBS (Consistent Overhead Byte Stuffing)
> single-frame encode/decode: the 0x00-free wire form plus size and
> validation helpers.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

COBS encodes a byte payload into a sequence that never contains `0x00`, so
`0x00` can be used as an unambiguous frame delimiter on serial lines,
sockets or any byte stream. Encoding overhead is at most one code byte per
254 payload bytes (plus the final code byte). Decoding reverses the
transformation exactly; no payload bytes are modified.

`xiom.cobs` works on one frame at a time:

```
payload --cobs_encode--> frame body (no 0x00) --0x00--> on the wire
```

The helpers never add or remove the `0x00` delimiter -- the caller appends
it to a finished frame and strips it before decoding (see Limitations).

## API

| Function | Returns | Description |
|---|---|---|
| `cobs_encode(data)` | `Vec[UInt8]` | COBS-encode `data`; output contains no `0x00`. Empty input yields `[0x01]`. |
| `cobs_decode(data)` | `Result[Vec[UInt8], Str]` | Decode one 0x00-free frame; Err on a `0x00` byte or a truncated code byte. |
| `cobs_encoded_size(data)` | `Int` | Exact encoded length; always equals `cobs_encode(data).len()`. |
| `cobs_is_encoded(data)` | `Bool` | `true` iff `data` contains no `0x00` byte. |
| `cobs_max_payload_for(frame_len)` | `Int` | Largest payload (worst case: all bytes non-zero) that fits a frame of `frame_len` bytes. |

Errors: `Err("cobs: zero byte in frame")`, `Err("cobs: truncated frame")`
(see SPEC.md for the full catalog).

## Usage

```xi
use xiom.cobs;
use xiom.io;
use xiom.convert;

var payload = Vec[UInt8].new();
payload.push(0x11);
payload.push(0x00);
payload.push(0x22);

let frame = cobs_encode(&payload);                 // [02 11 02 22], 4 bytes
io.println("frame bytes: " + convert.int_to_string(frame.len()));  // 4

// On the wire the caller appends the 0x00 delimiter (5 bytes total) and
// strips it again before decoding:
let decoded = cobs_decode(&frame);
match decoded {
  Ok(bytes) => { io.println("payload bytes: " + convert.int_to_string(bytes.len())); },  // 3
  Err(e) => { io.println("decode error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.cobs
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Single frame only.** These helpers encode/decode one frame body. The
  caller handles the `0x00` delimiter: append it after `cobs_encode` and
  split on / strip it before `cobs_decode`. There is no multi-frame parser
  and no `0x00` splitting here.
- **Whole-buffer, no streaming.** Payloads and frames are in-memory
  `Vec[UInt8]` values; there is no incremental decoder state for chunked
  input. The caller concatenates chunks until the delimiter arrives.
- **No error detection beyond framing structure.** COBS guarantees
  delimiter transparency, not integrity; combine with a checksum (e.g.
  `xiom.packet` or `xiom.hash.crc`) when corruption matters.
- **Frames have no length field.** A decoded frame accepts both the minimal
  form and the padded form with a trailing empty code block (see SPEC.md).
- **Decoding is not a security boundary.** A truncated frame is rejected,
  and a decoded payload is never longer than its frame, but the decoder
  materializes the whole payload in memory; the caller bounds frame sizes.
- Not thread-safe; the API is stateless free functions operating on values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
