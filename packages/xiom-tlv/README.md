# xiom.tlv

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM generic big-endian TLV (tag-length-value) parsing and
> building with caller-chosen tag/length widths of 1..4 bytes.
> **Deps:** `xiom.std` only. The library module is dependency-free; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.tlv` encodes and decodes flat TLV streams: each entry is a big-endian
tag, a big-endian value length, then the value bytes. The widths of the tag
and length fields are not carried in the stream; the caller picks them
(`1..4` bytes each) and must use the same widths to parse that it used to
build. `tlv_parse` returns a `TlvList` index that stores the tags plus the
absolute byte span of every value inside the source buffer;
`tlv_append`/`tlv_build_from` write the same layout, and `tlv_find` /
`tlv_value` read the index back.

## API

| Function | Returns | Description |
|---|---|---|
| `tlv_parse(data, tag_size, length_size)` | `Result[TlvList, Str]` | Walk a flat stream until `data` ends; index tags and value spans. |
| `tlv_count(l)` | `Int` | Number of parsed entries. |
| `tlv_tag(l, i)` | `Int` | Tag of entry `i`; `-1` when out of range. |
| `tlv_value(data, l, i)` | `Result[Vec[UInt8], Str]` | Copy the value bytes of entry `i` out of `data`. |
| `tlv_find(l, tag)` | `Int` | First entry index with `tag`; `-1` when absent. |
| `tlv_append(out, tag, value, tag_size, length_size)` | `Result[Unit, Str]` | Append one entry to `out`; `out` is untouched on `Err`. |
| `tlv_build_from(tags, values, tag_size, length_size)` | `Result[Vec[UInt8], Str]` | Build a whole stream from parallel tag/value vectors. |
| `tlv_size(tag_size, length_size, value_len)` | `Int` | Encoded size of one entry (`-1` on invalid widths/length). |

Errors: `tlv: invalid tag size`, `tlv: invalid length size`,
`tlv: negative tag`, `tlv: tag too large for tag_size`,
`tlv: value too large for length_size`, `tlv: tags/values length mismatch`,
`tlv: truncated header`, `tlv: value overruns buffer`,
`tlv: index out of range`, `tlv: value out of bounds`
(see SPEC.md for the full catalog and the exact conditions).

## Usage

```xi
use xiom.tlv;
use xiom.io;

// Build: entry 1 -> "AB", entry 2 -> empty value, widths 1/1.
var value = Vec[UInt8].new();
value.push(65 as UInt8);   // 'A'
value.push(66 as UInt8);   // 'B'
var out = Vec[UInt8].new();
tlv_append(&mut out, 1, &value, 1, 1);        // 01 02 41 42
var empty = Vec[UInt8].new();
tlv_append(&mut out, 2, &empty, 1, 1);        // 02 00

// Parse it back.
let parsed = tlv_parse(&out, 1, 1);
match parsed {
  Ok(l) => {
    io.println("entries: " + xiom.convert.int_to_string(tlv_count(&l)));      // 2
    io.println("first tag: " + xiom.convert.int_to_string(tlv_tag(&l, 0)));   // 1
    let v = tlv_value(&out, &l, 0);
    if v.is_ok {
      io.println("first value length: " + xiom.convert.int_to_string(v.value.len())); // 2
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.tlv
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Flat TLVs only.** The stream is a plain sequence of entries walked
  until the buffer ends. There is no support for **nesting** (a value that
  is itself a TLV stream must be re-parsed by the caller) and no recursive
  tree type.
- **No length-includes-header variants.** The length field counts the value
  bytes only; variants where the length includes the tag and/or length
  fields themselves are not modeled.
- **Widths are out-of-band and caller-consistent.** `tag_size`/`length_size`
  are not stored in the stream; parsing a stream with different widths than
  it was built with is not detected (it yields whatever tags/lengths those
  bytes decode to). Widths are limited to `1..4` bytes.
- **Tags are unsigned.** A negative tag cannot be encoded; `tlv_append`
  rejects it.
- **Values are raw bytes.** No UTF-8 validation or text conveniences; the
  caller interprets the bytes.
- `TlvList` borrows nothing: values are located in the original `data`
  buffer, so `tlv_value` needs that same buffer (or one holding at least the
  recorded span).
- Not thread-safe; `TlvList` is a plain value type.
- Ordering/duplicate tags are preserved as-is; `tlv_find` returns the first
  match. There is no canonical-order enforcement.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
