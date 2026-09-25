# xiom.cbor

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** strict pure-XIOM CBOR encoding and decoding for a documented
> subset: unsigned/negative integers, byte strings, text strings, arrays,
> maps, false/true/null/undefined.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.cbor` is a small, strict CBOR (RFC 8949) codec for a deterministic
subset: definite lengths only, shortest-form arguments required on decode,
canonical shortest-form emission. The decoder validates every structural rule
it implements and returns `Result[CborDoc, Str]` with deterministic error
strings; a decoded document can be re-serialized byte-for-byte from its token
stream alone.

The decoded representation is a **flat token stream**, not a recursive
`Value` tree: one entry per token in parallel vectors, stored depth-first
pre-order. Each token records its parent, its first direct child, its child
count and its next sibling, so containers can be walked without recursion.
Byte/text string payloads stay in the source buffer and are referenced by
offset ranges; accessors copy them out on demand.

Highlights:

- canonical encoding: shortest-form headers everywhere; `cbor_encode_map`
  sorts pairs by the bytewise lexicographic order of their encoded keys
  (RFC 8949 core deterministic encoding) and rejects duplicate keys;
- strict decoding: non-shortest arguments, reserved additional info,
  indefinite lengths, tags, floats, unsupported simple values, breaks,
  length/integer overflow, trailing data and over-deep nesting are all
  rejected with stable messages;
- `cbor_reserialize` rebuilds the exact accepted bytes from the token
  stream, which doubles as a round-trip witness (map order included);
- binary-safe: byte and text strings are opaque bytes; no UTF-8 validation
  is performed or required;
- depth cap of 64 nested containers bounds decoder recursion.

Non-goals: tags (major type 6), floats/half-floats, indefinite-length items,
CBOR sequences, semantic tag semantics (dates, bignums) and UTF-8 decoding.

## Install / use

```
xiom pkg install xiom.cbor@0.1.0     # consumer
xiom pkg publish                     # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.cbor;
use xiom.io;
use xiom.convert;

fn main() {
  // {"name": "xiom", "size": 1024}
  var keys = Vec[Vec[UInt8]].new();
  var values = Vec[Vec[UInt8]].new();
  keys.push(cbor_encode_text("name"));
  values.push(cbor_encode_text("xiom"));
  keys.push(cbor_encode_text("size"));
  values.push(cbor_encode_int(1024));

  let encoded = cbor_encode_map(&keys, &values);
  match encoded {
    Ok(bytes) => {
      match cbor_decode(bytes) {
        Ok(doc) => {
          // Map children alternate key, value: pair k is child 2*k / 2*k+1.
          let size_val = cbor_child(&doc, 0, 3);
          io.println(convert.int_to_string(cbor_int_value(&doc, size_val))); // 1024
        }
        Err(e) => { io.println("decode error: " + e); },
      }
    }
    Err(e) => { io.println("encode error: " + e); },
  }
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `cbor_decode(data)` | `Result[CborDoc, Str]` | Strictly decode exactly one CBOR value. |
| `cbor_reserialize(doc)` | `Vec[UInt8]` | Rebuild the accepted bytes from the token stream. |
| `cbor_kind_uint()` / `cbor_kind_negint()` | `Int` | Token kind codes (0 / 1). |
| `cbor_kind_bytes()` / `cbor_kind_text()` | `Int` | Token kind codes (2 / 3). |
| `cbor_kind_array()` / `cbor_kind_map()` | `Int` | Token kind codes (4 / 5). |
| `cbor_kind_bool()` | `Int` | Token kind code for false/true (6). |
| `cbor_kind_null()` / `cbor_kind_undefined()` | `Int` | Token kind codes (7 / 8). |
| `cbor_max_depth()` | `Int` | Nesting depth cap accepted by the decoder (64). |
| `cbor_token_count(doc)` | `Int` | Number of tokens. |
| `cbor_root(doc)` | `Int` | Root token index (always 0). |
| `cbor_kind(doc, i)` | `Int` | Token kind code, or -1 out of range. |
| `cbor_parent(doc, i)` | `Int` | Parent token index, or -1. |
| `cbor_first_child(doc, i)` | `Int` | First direct child, or -1. |
| `cbor_child_count(doc, i)` | `Int` | Number of direct children (2x pairs for maps). |
| `cbor_next_sibling(doc, i)` | `Int` | Next direct sibling, or -1. |
| `cbor_child(doc, i, n)` | `Int` | n-th direct child, or -1. |
| `cbor_token_start(doc, i)` | `Int` | First source byte of the token, or -1. |
| `cbor_token_end(doc, i)` | `Int` | One past the last source byte, or -1. |
| `cbor_int_value(doc, i)` | `Int` | Integer value, or 0 for other kinds. |
| `cbor_bool_value(doc, i)` | `Int` | 1 / 0 for bool tokens, -1 otherwise. |
| `cbor_bytes_len(doc, i)` | `Int` | Byte-string payload length, or -1. |
| `cbor_bytes(doc, i)` | `Vec[UInt8]` | Copy of the byte-string payload. |
| `cbor_text_len(doc, i)` | `Int` | Text-string payload byte length, or -1. |
| `cbor_text_bytes(doc, i)` | `Vec[UInt8]` | Copy of the text payload (no UTF-8 decoding). |
| `cbor_token_bytes(doc, i)` | `Vec[UInt8]` | Copy of the whole token's source bytes. |
| `cbor_encode_int(n)` | `Vec[UInt8]` | Canonical major 0/1 encoding of the full Int range. |
| `cbor_encode_bool(b)` | `Vec[UInt8]` | `0xf4` false / `0xf5` true. |
| `cbor_encode_null()` | `Vec[UInt8]` | `0xf6`. |
| `cbor_encode_undefined()` | `Vec[UInt8]` | `0xf7`. |
| `cbor_encode_bytes(bytes)` | `Vec[UInt8]` | Definite-length byte string. |
| `cbor_encode_text(s)` | `Vec[UInt8]` | Definite-length text string from `Str` UTF-8 bytes. |
| `cbor_encode_text_bytes(bytes)` | `Vec[UInt8]` | Text string from raw bytes (no UTF-8 validation). |
| `cbor_encode_array(parts)` | `Vec[UInt8]` | Array from encoded element chunks. |
| `cbor_encode_map(keys, values)` | `Result[Vec[UInt8], Str]` | Canonical map; sorts keys, rejects duplicates. |

Map children alternate key, value: pair `k` is child `2*k` (key) and child
`2*k + 1` (its value).

## Error model

Every decode failure is `Err(<deterministic message>)`; every message is
listed in SPEC.md. The catalog covers:

| Condition | Message |
|---|---|
| Buffer ends inside a value, header or payload | `cbor: truncated input` |
| Additional info 28/29/30 (and 31 on major types 0/1/6) | `cbor: reserved additional info NN` |
| Additional info 31 on majors 2..5 | `cbor: indefinite length not supported` |
| `0xff` where a value is expected | `cbor: break outside indefinite item` |
| Major type 6 initial byte | `cbor: tags not supported` |
| Major type 7 additional info 25/26/27 | `cbor: floats not supported` |
| Other major 7 simple values (incl. ai 24 with value >= 32) | `cbor: simple values not supported` |
| Argument that could have used a smaller width | `cbor: non-shortest form` |
| String/array/map argument above `INT64_MAX` | `cbor: length overflow` |
| Major type 0/1 argument above `INT64_MAX` | `cbor: integer out of range` |
| Bytes remain after the top-level value | `cbor: trailing data after top-level value` |
| Container nested deeper than 64 levels | `cbor: nesting depth exceeds limit of 64` |

Encoder errors: `cbor: map keys/values length mismatch` and
`cbor: duplicate map key` from `cbor_encode_map`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.cbor
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Signed 64-bit integers.** Major type 0 values above `INT64_MAX` (and
  major type 1 values below `INT64_MIN`) are rejected as
  `cbor: integer out of range`; CBOR's full unsigned 64-bit range would
  need an unsigned type or bignum representation.
- **No tags.** Major type 6 is rejected from its initial byte, so dates,
  bignums, decimals and other tagged items are out of scope.
- **No floats.** Half/single/double floats (`0xf9`/`0xfa`/`0xfb`) are
  rejected; v0.61.3 has no `Int <-> Float64` bitcast, so a lossless
  round-trip could not be offered in pure XIOM anyway.
- **No indefinite-length items or CBOR sequences.** Definite lengths only.
- **Strict shortest form on decode.** Any argument that could have used a
  smaller width is rejected, even where RFC 8949 well-formedness would
  allow it; this is the deterministic encoding enforced by the package.
- **No UTF-8 validation.** Text strings are opaque bytes. `encode_text`
  uses the UTF-8 bytes of a `Str`; `text_bytes` never decodes or validates.
- **Map key order is not validated on decode.** Any order is accepted and
  `cbor_reserialize` preserves it; `cbor_encode_map` is the canonical path
  (sorted bytewise by encoded key, duplicates rejected).
- **No streaming.** Decoding requires the whole buffer in memory, and
  `CborDoc` keeps the source bytes alive (payloads are offset ranges).
- **Depth cap of 64 containers** (`cbor_max_depth()`), enforced on both
  arrays and maps to bound parser recursion.
- **Flat encoder input.** `cbor_encode_array`/`cbor_encode_map` take
  already-encoded chunks; the caller is responsible for composing valid
  element encodings (the encoders do not re-validate chunks).
- Not thread-safe; documents are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
