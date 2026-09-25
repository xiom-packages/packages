# xiom.netstring

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM DJB netstring framing for in-memory `Vec[UInt8]`
> buffers: parse a concatenated stream into flat payload spans, build frames
> with computed decimal lengths, iterate frames with a cursor.
> **Deps:** `xiom.std` only. The library module is dependency-free; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

A netstring frame is `<length>:<payload>,` -- the payload length in ASCII
decimal, a colon, exactly that many raw payload bytes, and a trailing comma
(the Python `netstring` / DJB convention). A stream is zero or more frames
concatenated with nothing between them, so `"3:abc,0:,5:hello,"` is three
frames.

`xiom.netstring` covers the whole in-memory lifecycle of that format:

- `netstring_parse` walks a whole buffer and returns a flat index of payload
  spans (absolute offset + length per frame, parallel `Vec[Int]` fields --
  no per-frame structs);
- `netstring_payload` copies one payload out of the source buffer;
- `netstring_append` / `netstring_build` write frames with computed decimal
  lengths;
- `netstring_digit_count` / `netstring_frame_size` pre-size buffers exactly;
- a cursor (`netstring_cursor_new` / `netstring_cursor_next`) pulls frames
  one at a time, which is handy for consuming a stream incrementally and
  resuming after a truncated tail.

Errors are deterministic strings (`Err("netstring: ...")`, full catalog
below). Payloads are raw bytes: no escaping, no UTF-8 validation, no
nesting, no sockets/IO.

## API

| Function | Returns | Description |
|---|---|---|
| `netstring_parse(data)` | `Result[NetstringList, Str]` | Parse a whole stream into frame payload spans. |
| `netstring_count(l)` | `Int` | Number of parsed frames. |
| `netstring_offset(l, i)` | `Int` | Absolute payload offset of frame `i`; `-1` when out of range. |
| `netstring_length(l, i)` | `Int` | Payload length of frame `i`; `-1` when out of range. |
| `netstring_payload(data, l, i)` | `Result[Vec[UInt8], Str]` | Copy the payload bytes of frame `i`. |
| `netstring_append(out, payload)` | `()` | Append one frame (`<len>:<payload>,`) to `out`. |
| `netstring_build(payloads)` | `Vec[UInt8]` | Build a whole stream from a vector of payloads. |
| `netstring_digit_count(n)` | `Int` | Decimal digits in the length field of an `n`-byte payload; `-1` when `n < 0`. |
| `netstring_frame_size(payload_len)` | `Int` | Total encoded size of one frame; `-1` when negative. |
| `netstring_cursor_new()` | `NetstringCursor` | Fresh pull cursor at offset 0. |
| `netstring_cursor_next(data, c)` | `Result[Int, Str]` | Consume one frame: `Ok(index)`, or `Ok(-1)` at the end of the buffer. |
| `netstring_cursor_position(c)` | `Int` | Byte offset of the next frame (end of the buffer when done). |
| `netstring_cursor_index(c)` | `Int` | Frames consumed so far. |
| `netstring_cursor_payload_offset(c)` | `Int` | Payload offset of the last consumed frame; `-1` before the first. |
| `netstring_cursor_payload_length(c)` | `Int` | Payload length of the last consumed frame; `-1` before the first. |

`NetstringList` stores `payload_offsets` and `payload_lengths` as parallel
`Vec[Int]` fields; payload bytes stay in the source buffer, so
`netstring_payload` needs that same buffer (or one holding at least the
recorded span).

Errors: `netstring: bad length digits`, `netstring: missing colon`,
`netstring: payload too short`, `netstring: missing comma`,
`netstring: length overflow`, `netstring: trailing garbage`,
`netstring: index out of range`, `netstring: payload out of bounds`
(see `SPEC.md` for the exact conditions and check order).

## Install

```
xiom pkg install xiom.netstring@0.1.0   # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Then `use xiom.netstring;` in the consuming module.

## Quick start

```xi
use xiom.netstring;
use xiom.io;

// Build two frames: "3:abc,0:,"
var payload = Vec[UInt8].new();
payload.push(97 as UInt8);   // 'a'
payload.push(98 as UInt8);   // 'b'
payload.push(99 as UInt8);   // 'c'
var empty = Vec[UInt8].new();
var out = Vec[UInt8].new();
netstring_append(&mut out, &payload);    // 33 3a 61 62 63 2c  ("3:abc,")
netstring_append(&mut out, &empty);      // 30 3a 2c           ("0:,")

// Parse it back.
let parsed = netstring_parse(&out);
match parsed {
  Ok(l) => {
    io.println("frames: " + xiom.convert.int_to_string(netstring_count(&l)));      // 2
    let p = netstring_payload(&out, &l, 0);
    if p.is_ok {
      let bytes: Vec[UInt8] = p.value;
      io.println("first payload: " + xiom.convert.int_to_string(bytes.len()));      // 3
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

Cursor style (same buffer):

```xi
var c = netstring_cursor_new();
var r = netstring_cursor_next(&out, &mut c);
while r.is_ok && r.value >= 0 {
  let off: Int = netstring_cursor_payload_offset(&c);
  let n: Int = netstring_cursor_payload_length(&c);
  // payload bytes are out[off .. off + n)
  r = netstring_cursor_next(&out, &mut c);
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.netstring
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Raw bytes only.** Payloads are opaque byte strings. There is no quoting,
  escaping, checksum, compression or text decoding; a payload containing
  `,` or `:` is still parsed correctly because its length is explicit, but
  the caller interprets the bytes.
- **In-memory only.** No sockets, files or pipes; parse and build work on
  `Vec[UInt8]`. The cursor is a pull iterator over a complete buffer, and
  its `position` marks where an incomplete tail begins so a consumer can
  retain the tail and retry later; there is no push/callback streaming API.
- **The cursor is not a language iterator.** `netstring_cursor_next` must be
  called with the same buffer every time; the cursor itself holds only
  offsets. On `Err` the cursor is unchanged, so errors can be retried.
- **Lengths are platform `Int`s.** A declared length above `INT64_MAX` is a
  `length overflow` error; there is no arbitrary-precision fallback. A
  declared length that fits but exceeds the buffer is `payload too short`.
- **Strict length syntax.** Exactly one or more ASCII digits, no leading
  zeros (`0` itself is fine), no sign, no whitespace, and the colon must
  immediately follow the digits.
- **Strict framing.** The comma is mandatory even for empty payloads
  (`0:,`); there is no separator-free or newline-terminated mode and no
  trailing padding.
- **Not thread-safe;** the functions are plain free functions over values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
