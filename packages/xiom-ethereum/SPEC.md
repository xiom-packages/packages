# xiom.ethereum -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ethereum`, version `0.1.0`).
Module: `src/ethereum.xi` (`module xiom.ethereum`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`, `xiom.encoding.hex`).
No FFI. No keccak, no crypto, no network.

This document describes the exact byte-level formats and validation rules
implemented by the module. Where the module is deliberately stricter or
narrower than the Ethereum specifications, that is stated explicitly.

## 1. RLP

### 1.1 Grammar

```
item         = single-byte / short-string / long-string / short-list / long-list
single-byte  = %x00-7F
short-string = %x80-B7 *OCTET              ; length = b - 0x80, 0..55
long-string  = %xB8-BF len-of-len *OCTET   ; len-of-len = b - 0xB7, 1..8
short-list   = %xC0-F7 *item               ; payload length = b - 0xC0, 0..55
long-list    = %xF8-FF len-of-len *item    ; len-of-len = b - 0xF7, 1..8
len-of-len   = 1*8 OCTET                   ; big-endian payload length
```

A long-form payload length is serialized big-endian in exactly
`len-of-len` bytes; its first byte must not be zero (that would be a
non-minimal length-of-length), and its value must be >= 56.

### 1.2 Byte-level examples

| Input bytes | Item |
|---|---|
| `00` | integer 0 / empty-ish single byte |
| `7f` | single byte 0x7F |
| `80` | empty byte string |
| `81 80` | byte string `0x80` (one high byte) |
| `83 63 61 74` | `"cat"` |
| `b8 38` + 56 bytes | 56-byte string (long form) |
| `b9 01 2c` + 300 bytes | 300-byte string |
| `c0` | empty list |
| `c8 83 636174 83 646f67` | `["cat", "dog"]` |
| `f8 3c` + 60 bytes | list whose payload is 60 bytes |

### 1.3 Strict canonical rules enforced on decode

`rlp_decode(data)` accepts exactly one complete item; anything else is an
error. The rules, with the exact `Err(Str)` texts:

1. **Single byte below 0x80** must be encoded as itself: `81 00`..`81 7F` is
   `rlp: non-canonical single byte`.
2. **Short string with length 1** must hold a byte >= 0x80 (otherwise rule 1
   applied): `rlp: non-canonical single byte`.
3. **Long form length >= 56**: `b8 37` + 55 bytes (and the list form
   `f8 37` + 55 bytes) is `rlp: non-canonical long length`.
4. **No leading zero in a length**: `b9 00 38` + 56 bytes and `b8 00` are
   `rlp: leading zero in length` (the same for list forms). This covers both
   "leading zeros in lengths" and "length-of-length non-minimal".
5. **Lengths fit the signed 64-bit `Int`**: `rlp: length overflow`.
6. **Truncation**: a buffer that ends inside a header, a length or a payload
   is `rlp: truncated input`. A child item that claims bytes past the end of
   its enclosing list payload is `rlp: list payload overrun`.
7. **Exactly one item**: bytes after the top-level item are
   `rlp: trailing data after top-level item`. An empty buffer is
   `rlp: truncated input`.
8. **Nesting depth**: the top-level item has depth 0; a list at depth 63 is
   the deepest accepted one, a list at depth 64 is
   `rlp: nesting depth exceeds limit of 64` (`rlp_max_depth()` = 64). Only
   lists count against the cap.
9. **Bytes-safe**: payload bytes are opaque; `0x00` inside a payload is data,
   never a terminator. No UTF-8 validation is performed anywhere.

The decoder is transactional: any error yields only the message; no partial
document is exposed.

### 1.4 Flat token representation (`RlpDoc`)

Tokens are stored depth-first pre-order in **parallel vectors** (one entry
per token; no `Vec[StructType]`). Token 0 is the root. For token `i`:

| Vector | Meaning |
|---|---|
| `kind[i]` | `rlp_kind_bytes()` = 0 or `rlp_kind_list()` = 1 |
| `parent[i]` | enclosing token index, -1 at the root |
| `first_child[i]` | first direct child of a list, -1 for byte strings |
| `child_count[i]` | number of direct children (item count), 0 for byte strings |
| `next_sibling[i]` | next direct sibling, -1 on the last child |
| `start[i]` / `end[i]` | whole item, header included |
| `payload_start[i]` / `payload_end[i]` | string payload, or a list's children |
| `value[i]` | payload byte length |

`data` keeps the source buffer; `rlp_item_bytes` copies a string payload out
and `rlp_token_bytes` copies the whole item. Because subtrees sit between a
token and its next sibling, children must be walked with `rlp_child` /
`rlp_next_sibling`, not by adding 1 to the index.

### 1.5 Canonical encoders

| Function | Output |
|---|---|
| `rlp_encode_bytes(bytes)` | `80` for empty; the byte itself when there is exactly one byte < 0x80; else `80+len` (len <= 55) or `B7+k` + big-endian length (len >= 56) + payload. |
| `rlp_encode_int(n)` | `80` for 0; the byte itself for 1..127; else shortest big-endian byte string with no leading zeros, length-prefixed. Negative input is `rlp: integer must be non-negative`. |
| `rlp_encode_str(s)` | `rlp_encode_bytes` over the verbatim UTF-8 bytes of `s`. |
| `rlp_encode_list(parts)` | `C0` for empty; else the short/long list header for the total payload, then each pre-encoded chunk verbatim. |
| `rlp_reserialize(doc)` | Walk of the token stream re-emitting canonical bytes; equals the original input for every document `rlp_decode` produced (single-byte items included). |

## 2. Legacy transaction field listing

The helpers describe the legacy (pre-EIP-2718) transaction shape:

```
tx = [ nonce, gasPrice, gasLimit, to, value, data, v, r, s ]
```

| Field | Index | Type |
|---|---|---|
| `nonce` | 0 | RLP integer (byte string) |
| `gasPrice` | 1 | RLP integer |
| `gasLimit` | 2 | RLP integer |
| `to` | 3 | 20-byte string, or empty for contract creation |
| `value` | 4 | RLP integer |
| `data` | 5 | byte string (may be empty) |
| `v` | 6 | RLP integer (raw; not interpreted) |
| `r` | 7 | RLP integer |
| `s` | 8 | RLP integer |

`tx_nonce(doc, tx)` ... `tx_s(doc, tx)` return the RLP item index of the
field (usable with `rlp_item_bytes`, `rlp_payload_len`, ...), or -1 when
`tx` is not a list or the field is absent. `tx_field_count` returns the item
count of the list (9 for a well-formed legacy transaction).

`tx_is_unsigned_155(doc, tx)` is true exactly when `tx` is a 9-item list
whose fields 7 and 8 are empty byte strings -- the EIP-155 signing preimage
`[nonce, gasPrice, gasLimit, to, value, data, chainId, 0, 0]`.
`tx_chain_id(doc, tx)` then returns field 6's item index, else -1.

**ChainId note:** in a *signed* 9-item list field 6 is `v`, not the chain id
(under EIP-155, `v = chainId * 2 + 35/36`). This module never guesses:
`tx_chain_id` refuses signed transactions, and no v/r/s mathematics or
signature validation is performed.

## 3. ABI

All statically-sized ABI values occupy exactly one **32-byte word**,
serialized big-endian.

### 3.1 uint<M> (M = 8, 16, ..., 256)

- Word: 24 zero bytes, then the value in the low 8 bytes, unsigned.
- Encode: `value >= 0`, and `value < 2^M` when M <= 62 (for M >= 64 every
  signed 64-bit `Int` is in range).
  Errors: `abi: invalid uint width M`, `abi: uint value is negative`,
  `abi: uint value exceeds uint width M`.
- Decode: bytes 0..23 must be zero and byte 24 < 0x80, else
  `abi: uint word does not fit Int` (the 256-bit word is outside the signed
  64-bit range); then the `uint<M>` bound, else
  `abi: uint word exceeds uint width M`.

### 3.2 int<M> (M = 8, 16, ..., 256)

- Word: two's complement, sign-extended to 256 bits.
- Encode bounds: `-2^(M-1) <= value <= 2^(M-1) - 1` for M <= 63; for M >= 64
  every `Int` is in range. Error: `abi: int value exceeds int width M`.
- Decode: the high 24 bytes must be the sign extension of byte 24 (all
  0x00 when byte 24 < 0x80, all 0xFF when byte 24 >= 0x80), else
  `abi: int word does not fit Int`; then the `int<M>` bound, else
  `abi: int word exceeds int width M`.
- Examples: int256 `-1` = 32 x `FF`; int256 `INT64_MIN` = 24 x `FF` then
  `80 00 00 00 00 00 00 00`; int8 `-128` = 31 x `00` then `80`.

### 3.3 bool

- Encode: only 0 or 1 (`abi: bool value must be 0 or 1`); the word is all
  zero except byte 31.
- Decode: bytes 0..30 must be zero and byte 31 must be 0 or 1, else
  `abi: bool word must be 0 or 1`.

### 3.4 address

- Encode: exactly 20 bytes (`abi: address value must be 20 bytes`),
  right-aligned: 12 zero bytes then the address.
- Decode: bytes 0..11 must be zero, else
  `abi: address word is not right-aligned`; returns the 20 bytes.

### 3.5 bytes<M> (M = 1..32) and bytes32

- Encode: at most M bytes (`abi: fixed bytes value exceeds width M`),
  left-aligned: the value in bytes 0..len-1, zero padding through byte 31.
  `abi: invalid fixed-bytes width M` when M is outside 1..32.
- Decode: bytes M..31 must be zero, else
  `abi: fixed bytes padding is not zero`; returns exactly M bytes (for
  bytes32, all 32 bytes including any trailing zeros). `bytes32` is
  `bytes<32>`, so no padding check applies.

### 3.6 Word reads

`abi_read_word(data, off)` copies the 32 bytes at absolute offset `off`.
A negative offset, a buffer shorter than 32 bytes, or an offset that would
overrun is `abi: word out of bounds at offset N`. The word-level decoders
reject a buffer that is not exactly 32 bytes with `abi: word must be 32
bytes`. The `(data, off, ...)` variants combine the read with the decode.

### 3.7 Dynamic bytes / string (one level)

Layout of a standalone value:

```
head:  [ offset word = 0x20 ]                 (32 bytes, relative to base)
tail:  [ length word ][ payload bytes ][ zero pad to 32 ]
```

`abi_encode_dynamic_bytes(payload)` emits head + tail;
`abi_encode_dynamic_bytes_tail(payload)` emits only the tail (for call
data). Solidity `string` is uninterpreted UTF-8 here, so the same encoding
serves `bytes` and `string`, and the decoder returns the raw payload bytes
(callers that need a `Str` must handle NUL bytes themselves).

`abi_decode_dynamic_bytes(data, head_off, base)` reads the offset word at
absolute `head_off`; the stored offset is relative to `base` (0 for a
standalone block, `abi_call_args_offset()` = 4 for call arguments). Rules:

1. the offset word must be non-negative and fit `Int`
   (`abi: offset word exceeds Int at offset N`);
2. the offset must be a multiple of 32
   (`abi: dynamic offset is not word-aligned at offset N`);
3. `base + offset >= base + 32`, i.e. the target must lie after the head
   word (`abi: dynamic offset points into the head at offset N`);
4. the length word must fit (`abi: length word exceeds Int at offset N`) and
   the target must be inside the buffer
   (`abi: dynamic offset out of bounds at offset N`);
5. `length` payload bytes **and** their zero padding to the next 32-byte
   boundary must fit (`abi: dynamic data out of bounds at offset N`); a
   truncated or unpadded tail is rejected.

### 3.8 Dynamic arrays of static words (one level)

Layout of a standalone array of 32-byte static words:

```
head:  [ offset word = 0x20 ]
tail:  [ length word = element count ][ element 0 (32 bytes) ] ... [ element N-1 ]
```

- `abi_encode_word_array(words)` / `abi_encode_word_array_tail(words)`: every
  element must be exactly 32 bytes (`abi: array element must be 32 bytes`).
  Build the element words with `abi_encode_uint` / `abi_encode_int` /
  `abi_encode_bool` / `abi_encode_address` / `abi_encode_bytes32`.
- Offset resolution is the same as for dynamic bytes (rules 1-4 above).
- `abi_decode_array_count(data, head_off, base)` returns the element count
  and requires every element to fit:
  `count <= floor((len(data) - (target + 32)) / 32)`, else
  `abi: array elements out of bounds at offset M` where M is the first
  element byte.
- `abi_array_element(data, head_off, base, index)` copies one element word
  and reports `abi: array index out of range` outside `0..count-1`.
- `abi_decode_uint_array(data, head_off, base, m)` decodes all elements as
  uint<M>.

Arrays of dynamic element types (arrays of bytes/strings) are out of scope.

### 3.9 Function-call data

```
call = [ selector (4 bytes) ][ head ][ tail ]
```

- The selector is caller-provided; this package never computes keccak
  (`abi_encode_call` requires exactly 4 bytes:
  `abi: selector must be 4 bytes`).
- Dynamic offset words in the head are relative to `base = 4`
  (`abi_call_args_offset()`), the first byte of the argument section.
- `abi_call_selector(data)` copies the first 4 bytes; `abi_call_args(data)`
  copies everything after them; a shorter buffer is
  `abi: call data shorter than selector`.
- Example: `selector ++ uint256(5) ++ offset(64) ++ tail` is decoded with
  `abi_decode_uint(call, 4, 256)` and
  `abi_decode_dynamic_bytes(call, 36, 4)`.

## 4. Hex and address helpers

- `eth_hex_bytes(data)` = `"0x"` + lowercase hex with exactly two digits per
  byte (empty input is `"0x"`; never an odd number of digits).
- `eth_hex_uint(n, width_bytes)`: `n >= 0`, `width_bytes` in 1..32, and
  `n < 256^width_bytes` for widths 1..7 (any `Int` fits 8+ bytes); the
  output is zero-padded to exactly `width_bytes` bytes. Errors:
  `eth: quantity is negative`, `eth: quantity width must be 1..32 bytes`,
  `eth: quantity exceeds width N bytes`.
- `eth_address_bytes(input)`: exactly 40 hex digits, optionally prefixed by
  `0x` or `0X`; returns 20 raw bytes. Case-insensitive hex digits are
  accepted. Errors: `eth: address must be 40 hex digits with optional 0x
  prefix`, `eth: address contains a non-hex character`.
- `eth_address_normalize(input)`: the same validation, output as the
  canonical all-lowercase `0x` + 40 digits form. Mixed-case input is
  lowercased.
- `eth_address_from_bytes(bytes)`: 20 bytes to the same canonical form;
  `eth: address bytes must be 20 bytes` otherwise.

**EIP-55 note.** EIP-55 defines the mixed-case checksum as keccak256 of the
lowercase address; the case of each hex letter then encodes one bit of the
hash. Verifying it requires keccak256, which is a cryptographic hash and is
excluded from this package (see the module header). `eth_address_normalize`
therefore returns the all-lowercase form, which is exactly the input EIP-55
hashing needs; checksummed rendering and verification are left to the
caller.

## 5. Value range and non-goals

- Every integer exposed or accepted by this module is the signed 64-bit
  platform `Int`; wider ABI values are rejected, never truncated.
- Not implemented: keccak/SHA, secp256k1, EIP-2718 typed envelopes,
  JSON-RPC, EIP-55 checksums, nested dynamic ABI types, floats, state,
  streaming/incremental decoding.
- ABI bytes/string decoders return raw bytes; converting them to `Str` is
  the caller's concern (payloads may contain `0x00`).

## 6. Verification

```
xiom --run tests/test_conformance.xi
```

23 checks, all `[PASS]`, exit 0, with compiler v0.61.3 and the pinned
`E:\xiom-lang\stdlib`. The suite builds every buffer in-test and covers the
canonical rules, error catalog, transaction listings, ABI round-trips,
malformed dynamic offsets, call data, hex and address handling.
