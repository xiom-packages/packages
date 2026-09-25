# xiom.bencode

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** strict pure-XIOM bencode encoding and decoding for a documented
> subset: integers, byte strings, lists and dictionaries.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.convert`; tests add `xiom.test`, `xiom.io`, `xiom.string.compare`,
> `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.bencode` is a small, strict bencode (BitTorrent) codec. The decoder
validates every structural rule and returns `Result[BencodeDoc, Str]` with
deterministic error strings; the encoders emit canonical bytes; a decoded
document can be re-serialized from its token stream alone.

The decoded representation is a **flat token stream**, not a recursive
`Value` tree: one entry per token in parallel vectors, stored depth-first
pre-order. Each token records its parent, its first direct child, its child
count and its next sibling, so containers can be walked without recursion.
Integer text and byte-string payloads stay in the source buffer and are
referenced by offset ranges; accessors copy them out on demand.

Highlights:

- canonical encoding: decimal integers, byte-wise ascending dictionary keys;
- strict decoding: leading zeros, `-0`, integer overflow, missing
  delimiters, out-of-bounds lengths, dict key order violations, duplicate
  keys, trailing data and over-deep nesting are all rejected;
- `bencode_reserialize` rebuilds the exact input bytes from the token
  stream, which doubles as a round-trip witness;
- `bencode_dict_get` binary-searches a dictionary by raw key bytes;
- binary-safe: byte strings are opaque, keys are compared as unsigned
  bytes, UTF-8 is never assumed.

Non-goals: `.torrent` metadata semantics, UTF-8 validation/decoding,
streaming or incremental decoding, and arbitrary-precision integers.

## Install / use

```
xiom pkg install xiom.bencode@0.1.0     # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Quick start

```xi
use xiom.bencode;
use xiom.io;
use xiom.convert;
use xiom.string;

// ASCII literal -> raw bytes, for dictionary keys.
fn raw(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < str_len(s) {
    v.push(byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn main() {
  var keys = Vec[Vec[UInt8]].new();
  var values = Vec[Vec[UInt8]].new();
  keys.push(raw("name"));
  values.push(bencode_encode_str("xiom"));
  keys.push(raw("size"));
  values.push(bencode_encode_int(1024));

  // Keys are sorted byte-wise on output: {"name": "xiom", "size": 1024}
  let encoded = bencode_encode_dict(&keys, &values);
  match encoded {
    Ok(bytes) => {
      let decoded = bencode_decode(bytes);
      match decoded {
        Ok(doc) => {
          let key = raw("size");
          let tok = bencode_dict_get(&doc, bencode_root(&doc), &key);
          io.println(convert.int_to_string(bencode_int_value(&doc, tok))); // 1024
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
| `bencode_decode(data)` | `Result[BencodeDoc, Str]` | Strictly decode exactly one bencode value. |
| `bencode_reserialize(doc)` | `Vec[UInt8]` | Rebuild canonical bytes from the token stream. |
| `bencode_kind_int()` / `bencode_kind_str()` | `Int` | Token kind codes (0 / 1). |
| `bencode_kind_list()` / `bencode_kind_dict()` | `Int` | Token kind codes (2 / 3). |
| `bencode_max_depth()` | `Int` | Nesting depth cap accepted by the decoder (64). |
| `bencode_token_count(doc)` | `Int` | Number of tokens. |
| `bencode_root(doc)` | `Int` | Root token index (always 0). |
| `bencode_kind(doc, i)` | `Int` | Token kind code, or -1 out of range. |
| `bencode_parent(doc, i)` | `Int` | Parent token index, or -1. |
| `bencode_first_child(doc, i)` | `Int` | First direct child, or -1. |
| `bencode_child_count(doc, i)` | `Int` | Number of direct children. |
| `bencode_next_sibling(doc, i)` | `Int` | Next direct sibling, or -1. |
| `bencode_child(doc, i, n)` | `Int` | n-th direct child, or -1. |
| `bencode_token_start(doc, i)` | `Int` | First source byte of the token, or -1. |
| `bencode_token_end(doc, i)` | `Int` | One past the last source byte, or -1. |
| `bencode_int_value(doc, i)` | `Int` | Parsed integer, or 0 for non-int tokens. |
| `bencode_str_len(doc, i)` | `Int` | Payload byte length, or -1 for non-str tokens. |
| `bencode_str_bytes(doc, i)` | `Vec[UInt8]` | Copy of the payload bytes. |
| `bencode_token_bytes(doc, i)` | `Vec[UInt8]` | Copy of the whole token's source bytes. |
| `bencode_dict_get(doc, i, key)` | `Int` | Value token for raw `key` bytes, or -1. |
| `bencode_encode_int(n)` | `Vec[UInt8]` | `i<n>e`, exact for the full Int range. |
| `bencode_encode_bytes(bytes)` | `Vec[UInt8]` | `<len>:<bytes>`. |
| `bencode_encode_str(s)` | `Vec[UInt8]` | `<utf8-len>:<utf8 bytes>` (verbatim). |
| `bencode_encode_list(parts)` | `Vec[UInt8]` | `l` + encoded chunks + `e`. |
| `bencode_encode_dict(keys, values)` | `Result[Vec[UInt8], Str]` | Canonical dict; sorts keys, rejects duplicates. |

Dictionary children alternate key, value: pair `k` is child `2*k` (a
byte-string token) and child `2*k + 1` (its value).

## Error model

Every decode failure is `Err(<deterministic message>)`; every message is
listed in SPEC.md. The catalog covers:

| Condition | Message |
|---|---|
| Buffer ends inside a value, header or payload | `bencode: truncated input` |
| First byte is not `i`, `l`, `d` or a length digit | `bencode: bad type byte 0xNN` |
| Malformed integer digits (empty, non-digit, leading zero) | `bencode: bad integer digits` |
| `i-0e` and other negative zeros | `bencode: negative zero in integer` |
| Integer outside the signed 64-bit range | `bencode: integer overflow` |
| Missing `e` after integer digits or `:` after length digits | `bencode: bad delimiter` |
| Leading zero in a string length | `bencode: bad length digits` |
| String length outside the signed 64-bit range | `bencode: string length overflow` |
| Dictionary key is not a byte string | `bencode: dict key must be a byte string` |
| Keys not strictly ascending byte-wise | `bencode: dict key order violation` |
| Equal adjacent keys | `bencode: duplicate dict key` |
| Bytes remain after the top-level value | `bencode: trailing data after top-level value` |
| Container nested deeper than 64 levels | `bencode: nesting depth exceeds limit of 64` |

Encoder errors: `bencode: dict keys/values length mismatch` and
`bencode: duplicate dict key` from `bencode_encode_dict`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bencode
```

Expected: the section-4 namespace check passes, 19 `[PASS]` lines, and a
final `port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integers are signed 64-bit.** Values outside `-2^63 .. 2^63-1` are an
  overflow error; bencode itself has no range limit, so this is a documented
  subset. `INT64_MIN` is accepted and encoded exactly.
- **No `.torrent` semantics.** `announce`, `info`, piece hashes and
  info-hashes are application-level concerns; this package is a codec only.
- **No UTF-8 validation.** Byte strings are opaque bytes. `encode_str` uses
  the UTF-8 bytes of the `Str` and its byte length; `str_bytes` never
  decodes or validates.
- **No streaming.** Decoding requires the whole buffer in memory, and
  `BencodeDoc` keeps the source bytes alive (payloads are offset ranges).
- **Strictness beyond the wire format.** Bencode permits non-canonical
  integer spellings, unordered/duplicate dictionary keys and trailing bytes
  in practice; this decoder rejects all of them. A document produced by
  `bencode_encode_*` always decodes on the first try.
- **Depth cap of 64 containers** (`bencode_max_depth()`), enforced on both
  lists and dictionaries to bound parser recursion.
- **Flat API.** Encoders take already-encoded chunks
  (`Vec[Vec[UInt8]]`); there is no recursive `Value` tree to build, and no
  stream writer.
- Not thread-safe; documents are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
