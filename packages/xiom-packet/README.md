# xiom.packet

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) length-prefixed packet framing with CRC-32
> validation: framing, whole-buffer parsing and a streaming chunk decoder.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex`.

## What it is

`xiom.packet` frames opaque payload bytes as

```
[u32 little-endian payload length][payload][u32 little-endian CRC-32(payload)]
```

and decodes them back. `packet_parse_all` walks a buffer of concatenated
frames in order; `PacketDecoder` buffers chunked input (sockets, pipes,
files) and hands back one payload at a time. Every payload is checked
against its CRC-32 before it is returned, with deterministic error strings
for truncation and corruption (see `SPEC.md` for the full catalog).

## API

| Function | Returns | Description |
|---|---|---|
| `packet_crc32(data)` | `Int` | Standard CRC-32 (IEEE 802.3), unsigned 32-bit value in an `Int`. |
| `packet_frame(payload)` | `Vec[UInt8]` | `[u32 LE length][payload][u32 LE CRC-32]`. |
| `packet_parse_all(data)` | `Result[Vec[Vec[UInt8]], Str]` | Every complete frame, in order; Err on a partial tail or CRC failure. |
| `packet_is_valid(data)` | `Bool` | Exactly one complete CRC-valid frame, no trailing bytes. |
| `packet_decoder_new()` | `PacketDecoder` | Empty streaming decoder. |
| `packet_decoder_feed(&mut d, chunk)` | `Unit` | Append a chunk; compacts the consumed prefix. |
| `packet_decoder_available(d)` | `Int` | Complete frames currently buffered (CRC not yet checked). |
| `packet_decoder_take(&mut d)` | `Result[Vec[UInt8], Str]` | Next frame payload; Err when none complete or CRC fails. |
| `packet_decoder_buffered(d)` | `Int` | Unconsumed bytes. |

`pub type PacketDecoder = { buf: Vec[UInt8]; pos: Int; }` (fields are
implementation details; use the free functions).

Errors: `Err("packet: truncated frame")`, `Err("packet: crc mismatch")`,
`Err("packet: no complete frame")` (see SPEC.md).

## Usage

```xi
use xiom.packet;
use xiom.convert;
use xiom.io;

var payload = Vec[UInt8].new();
payload.push(1);
payload.push(2);
payload.push(3);
let framed = packet_frame(&payload);              // 4 + 3 + 4 = 11 bytes

let parsed = packet_parse_all(&framed);
match parsed {
  Ok(frames) => { io.println("frames: " + convert.int_to_string(frames.len())); },  // 1
  Err(e) => { io.println("parse error: " + e); },
}

var dec = packet_decoder_new();
packet_decoder_feed(&mut dec, &framed);           // feed chunks in any split
let one = packet_decoder_take(&mut dec);
match one {
  Ok(p) => { io.println("payload bytes: " + convert.int_to_string(p.len())); },     // 3
  Err(e) => { io.println("decode error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.packet
```

Expected: the section-4 namespace check passes, 24 `[PASS]` lines, and a
final `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Single-frame payload length <= 2^31-1 bytes.** The length field is a
  u32, but the API works with `Int` lengths; frames beyond the documented
  bound are rejected as truncated. A frame also has to fit in memory: the
  codec operates on `Vec[UInt8]` buffers, not streams with callback sinks.
- **No compression, encryption, framing-in-framing or payload typing.**
  Payload bytes are opaque and copied verbatim.
- **CRC-32 is an error-detection checksum, not cryptography.** It detects
  accidental corruption; it does not authenticate data.
- `packet_decoder_available` counts structurally complete frames (declared
  length fully buffered) and does **not** verify CRCs; `take` does.
- `take` skips a corrupt frame (advances past it) so the decoder resyncs
  on the following bytes; this is intentional and documented in SPEC.md.
- `packet_parse_all` fails the whole buffer on the first bad frame; it does
  not return the valid prefix.
- The decoder buffer grows with fed-but-unconsumed bytes; `feed` compacts
  the consumed prefix so returned payloads are not retained.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
