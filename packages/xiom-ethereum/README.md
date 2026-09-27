# xiom.ethereum

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** Ethereum RLP and ABI encoding structures in pure XIOM: a strict
> RLP codec, legacy transaction field listing, ABI static words plus one
> level of dynamic types, function-call data assembly, and hex/address
> helpers.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`,
> `xiom.encoding.hex`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`).
> No FFI. No keccak, no crypto, no network.

## What it is

`xiom.ethereum` implements the serialization *structures* around Ethereum in
pure XIOM and deliberately stops at cryptography:

- **RLP** (`rlp_decode`, `rlp_encode_*`): one complete item per decode, flat
  token stream in parallel vectors, strict canonical rules, and
  `rlp_reserialize` as a round-trip witness.
- **Legacy transaction field listing** (`tx_nonce`, `tx_gas_price`, ...):
  the RLP item index of each of the nine legacy fields, plus recognition of
  the EIP-155 signing preimage (`tx_is_unsigned_155`, `tx_chain_id`). No
  signature checking and no v interpretation.
- **ABI words** (`abi_encode_uint`, `abi_decode_int`, ...): uint<M>/int<M>
  for M = 8..256 step 8, bool, address, bytes<M>/bytes32, all as 32-byte
  big-endian words, with explicit bounds errors.
- **ABI dynamic types, one level** (`abi_encode_dynamic_bytes`,
  `abi_decode_dynamic_bytes`, `abi_encode_word_array`, ...): bytes/string as
  offset word + length word + padded data; dynamic arrays of 32-byte static
  words as offset word + length word + elements. Offsets are bounds checked
  against a caller-supplied base.
- **Function-call data** (`abi_encode_call`, `abi_call_selector`,
  `abi_call_args`): a 4-byte caller-provided selector plus head/tail
  argument sections. The selector is *not* computed: keccak256 is crypto and
  out of scope.
- **Hex and address helpers** (`eth_hex_bytes`, `eth_hex_uint`,
  `eth_address_normalize`, ...): 0x-prefixed lowercase, two digits per byte,
  zero-padded. EIP-55 mixed-case checksums are **not** verified (the
  checksum is keccak256-based); `eth_address_normalize` returns the
  all-lowercase form and documents why.

Value range: the platform `Int` is signed 64-bit, so every decoded ABI
integer and RLP length must fit it; a 256-bit word holding a value outside
the signed 64-bit range is rejected with `abi: uint word does not fit Int`
(or the int variant) instead of being silently truncated.

Non-goals: keccak/SHA hashing, secp256k1 signing/recovery, EIP-2718 typed
transaction envelopes (only the legacy 9-item shape is described), JSON-RPC
or any networking, nested dynamic ABI types (an array of bytes/strings is out
of scope), floats, and state.

## Quick start

```xi
use xiom.ethereum;
use xiom.io;
use xiom.convert;

fn main() {
  // 1. RLP round-trip: the two-item list ["cat", "dog"].
  var parts = Vec[Vec[UInt8]].new();
  parts.push(rlp_encode_str("cat"));
  parts.push(rlp_encode_str("dog"));
  let list = rlp_encode_list(&parts);   // c8 83 636174 83 646f67
  match rlp_decode(list) {
    Ok(doc) => {
      let tok = rlp_child(&doc, rlp_root(&doc), 0);
      // 3 bytes
      io.println("first item: " + convert.int_to_string(rlp_payload_len(&doc, tok)) + " bytes");
    }
    Err(e) => { io.println("rlp: " + e); },
  }

  // 2. ABI: a uint256 32-byte word, then decode it back.
  match abi_encode_uint(42, 256) {
    Ok(word) => {
      match abi_decode_uint(&word, 0, 256) {
        Ok(v) => { io.println("uint256: " + convert.int_to_string(v)); },  // 42
        Err(e) => { io.println("abi: " + e); },
      }
    }
    Err(e) => { io.println("abi: " + e); },
  }

  // 3. Address normalization (EIP-55 checksums need keccak; caller's job).
  match eth_address_normalize("0x52908400098527886E0F7030069857D2E4169EE7") {
    Ok(a) => { io.println(a); },  // 0x52908400098527886e0f7030069857d2e4169ee7
    Err(e) => { io.println("eth: " + e); },
  }
}
```

## API

### RLP

| Function | Returns | Description |
|---|---|---|
| `rlp_decode(data)` | `Result[RlpDoc, Str]` | Strictly decode exactly one canonical RLP item. |
| `rlp_reserialize(doc)` | `Vec[UInt8]` | Rebuild the canonical bytes from the token stream. |
| `rlp_encode_bytes(bytes)` | `Vec[UInt8]` | Canonical byte string. |
| `rlp_encode_str(s)` | `Vec[UInt8]` | Canonical byte string from a `Str` (verbatim bytes). |
| `rlp_encode_int(n)` | `Result[Vec[UInt8], Str]` | Canonical non-negative integer (zero is `0x80`). |
| `rlp_encode_list(parts)` | `Vec[UInt8]` | Canonical list from pre-encoded chunks. |
| `rlp_kind_bytes()` / `rlp_kind_list()` | `Int` | Token kind codes (0 / 1). |
| `rlp_max_depth()` | `Int` | Nesting cap accepted by the decoder (64). |
| `rlp_token_count(doc)` | `Int` | Number of tokens. |
| `rlp_root(doc)` | `Int` | Root token index (always 0). |
| `rlp_kind(doc, i)` | `Int` | Item kind code, or -1 out of range. |
| `rlp_is_bytes(doc, i)` / `rlp_is_list(doc, i)` | `Bool` | Kind predicates. |
| `rlp_parent(doc, i)` | `Int` | Parent token index, or -1. |
| `rlp_first_child(doc, i)` | `Int` | First direct child, or -1. |
| `rlp_child_count(doc, i)` | `Int` | Item count of a list, or 0. |
| `rlp_child(doc, i, n)` | `Int` | n-th direct child, or -1. |
| `rlp_next_sibling(doc, i)` | `Int` | Next direct sibling, or -1. |
| `rlp_token_start(doc, i)` / `rlp_token_end(doc, i)` | `Int` | Whole-item byte span. |
| `rlp_payload_start(doc, i)` / `rlp_payload_end(doc, i)` | `Int` | Payload byte span. |
| `rlp_payload_len(doc, i)` | `Int` | Payload byte length, or -1. |
| `rlp_item_bytes(doc, i)` | `Vec[UInt8]` | Copy of a byte-string payload. |
| `rlp_token_bytes(doc, i)` | `Vec[UInt8]` | Copy of the whole item's source bytes. |

### Legacy transaction field listing

| Function | Returns | Description |
|---|---|---|
| `tx_field_count(doc, tx)` | `Int` | Number of fields (9 for legacy), or 0. |
| `tx_field(doc, tx, field)` | `Int` | RLP item index of field `field`, or -1. |
| `tx_nonce` / `tx_gas_price` / `tx_gas_limit` | `Int` | Fields 0 / 1 / 2. |
| `tx_to` / `tx_value` / `tx_data` | `Int` | Fields 3 / 4 / 5. |
| `tx_v` / `tx_r` / `tx_s` | `Int` | Fields 6 / 7 / 8 (raw items). |
| `tx_is_unsigned_155(doc, tx)` | `Bool` | True for the EIP-155 preimage `[nonce, gasPrice, gasLimit, to, value, data, chainId, 0, 0]`. |
| `tx_chain_id(doc, tx)` | `Int` | Field 6 of the preimage, or -1 (a signed transaction's field 6 is `v`). |

### ABI

| Function | Returns | Description |
|---|---|---|
| `abi_encode_uint(value, m)` / `abi_encode_int(value, m)` | `Result[Vec[UInt8], Str]` | One 32-byte word (two's complement for int). |
| `abi_decode_uint_word(word, m)` / `abi_decode_int_word(word, m)` | `Result[Int, Str]` | Decode a word with width checks. |
| `abi_decode_uint(data, off, m)` / `abi_decode_int(data, off, m)` | `Result[Int, Str]` | Bounds-checked word read plus decode. |
| `abi_encode_bool(value)` | `Result[Vec[UInt8], Str]` | 0/1 only. |
| `abi_decode_bool_word(word)` / `abi_decode_bool(data, off)` | `Result[Bool, Str]` | 0/1 only, rejects other words. |
| `abi_encode_address(address)` | `Result[Vec[UInt8], Str]` | 20 bytes, right-aligned in a word. |
| `abi_decode_address_word(word)` / `abi_decode_address(data, off)` | `Result[Vec[UInt8], Str]` | Rejects a non-right-aligned word. |
| `abi_encode_bytes_m(value, m)` / `abi_encode_bytes32(value)` | `Result[Vec[UInt8], Str]` | Left-aligned, zero-padded. |
| `abi_decode_bytes_m_word(word, m)` / `abi_decode_bytes32_word(word)` | `Result[Vec[UInt8], Str]` | Rejects non-zero padding. |
| `abi_read_word(data, off)` | `Result[Vec[UInt8], Str]` | Copy of a 32-byte word. |
| `abi_encode_dynamic_bytes(payload)` | `Vec[UInt8]` | Standalone offset + length + padded data. |
| `abi_encode_dynamic_bytes_tail(payload)` | `Vec[UInt8]` | Length + padded data (no offset word). |
| `abi_decode_dynamic_bytes(data, head_off, base)` | `Result[Vec[UInt8], Str]` | Resolve the offset word and copy the payload. |
| `abi_encode_word_array(words)` | `Result[Vec[UInt8], Str]` | Standalone offset + length + 32-byte elements. |
| `abi_encode_word_array_tail(words)` | `Result[Vec[UInt8], Str]` | Length + elements (no offset word). |
| `abi_decode_array_count(data, head_off, base)` | `Result[Int, Str]` | Element count with all elements bounded. |
| `abi_array_element(data, head_off, base, index)` | `Result[Vec[UInt8], Str]` | Bounds-checked element word. |
| `abi_decode_uint_array(data, head_off, base, m)` | `Result[Vec[Int], Str]` | Decode a full uint<M> array. |
| `abi_encode_call(selector, head, tail)` | `Result[Vec[UInt8], Str]` | selector must be 4 bytes. |
| `abi_call_selector(data)` / `abi_call_args(data)` | `Result[Vec[UInt8], Str]` | Split call data. |
| `abi_call_args_offset()` | `Int` | 4 (dynamic offsets are relative to this). |
| `abi_word_size()` / `abi_selector_size()` | `Int` | 32 / 4. |
| `abi_valid_int_bits(m)` / `abi_valid_bytes_m(m)` | `Bool` | Width validation predicates. |

### Hex and addresses

| Function | Returns | Description |
|---|---|---|
| `eth_hex_bytes(data)` | `Str` | `0x` + lowercase hex, two digits per byte. |
| `eth_hex_uint(n, width_bytes)` | `Result[Str, Str]` | Zero-padded to exactly `width_bytes` bytes. |
| `eth_address_bytes(input)` | `Result[Vec[UInt8], Str]` | 40 hex digits, optional 0x/0X prefix. |
| `eth_address_normalize(input)` | `Result[Str, Str]` | Canonical all-lowercase `0x...` form. |
| `eth_address_from_bytes(bytes)` | `Result[Str, Str]` | 20 raw bytes to canonical lowercase hex. |

## Errors

RLP error strings: `rlp: truncated input`, `rlp: non-canonical single byte`,
`rlp: leading zero in length`, `rlp: non-canonical long length`,
`rlp: length overflow`, `rlp: list payload overrun`,
`rlp: nesting depth exceeds limit of 64`,
`rlp: trailing data after top-level item`,
`rlp: integer must be non-negative` (encoder).

ABI error strings carry byte offsets where relevant: `abi: word out of bounds
at offset N`, `abi: offset word exceeds Int at offset N`, `abi: length word
exceeds Int at offset N`, `abi: dynamic offset is not word-aligned at offset
N`, `abi: dynamic offset points into the head at offset N`, `abi: dynamic
offset out of bounds at offset N`, `abi: dynamic data out of bounds at offset
N`, `abi: array elements out of bounds at offset N`, plus the width and value
errors (`abi: invalid uint width M`, `abi: uint word does not fit Int`,
`abi: bool word must be 0 or 1`, `abi: address word is not right-aligned`,
`abi: fixed bytes padding is not zero`, ...). See `SPEC.md` for the full
catalog.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 23 `[PASS]` lines, then `xiom.ethereum: all tests passed`, exit 0.
The suite builds all buffers in-test (no external vectors): RLP
single/short/long/nested items, canonicality rejections, the depth cap,
EIP-155 and signed transaction listings, ABI uint/int/bool/address/bytes
round-trips and bounds errors, dynamic offsets and malformed truncation,
call-data assembly, hex rendering and address normalization.

## Install / publish

```
xiom pkg install xiom.ethereum@0.1.0   # consumer
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
