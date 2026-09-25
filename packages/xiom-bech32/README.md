# xiom.bech32

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) Bech32 and Bech32m codec: encode/decode with
> the BIP-173 / BIP-350 checksums, the 5-bit data alphabet, HRP validation,
> variant detection, and `convertbits` 8->5 / 5->8 helpers.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`; tests add
> `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare`,
> `xiom.string.builder` and `xiom.encoding.hex`).

## What it is

`xiom.bech32` is a small, dependency-light codec for the checksummed base32
formats defined by [BIP-173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki)
(Bech32) and [BIP-350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki)
(Bech32m). Every function is a free function over flat vectors: the encoder
takes an HRP plus 5-bit data symbols and returns canonical lowercase text,
the decoder returns a `Result[Bech32, Str]` whose payload exposes the HRP,
the variant and the 5-bit data (checksum symbols removed) through
`bech32_hrp` / `bech32_variant` / `bech32_data`.

The formats differ only in the constant xored into the checksum:
`1` for Bech32 (BIP-173) and `0x2bc830a3` for Bech32m (BIP-350).
`bech32_decode` detects the variant from the checksum, and
`bech32_decode_variant` requires a specific one and reports
`bech32: wrong variant` when a string is valid only under the other
constant.

Deliberately out of scope: segwit address semantics (witness versions,
program lengths, network HRPs), base58, and error correction. This package
is the codec layer only; see SPEC.md.

## Install / use

```
xiom pkg install xiom.bech32@0.1.0
```

```xi
use xiom.bech32;
use xiom.io;

// Bytes -> 5-bit symbols -> Bech32 text (canonical lowercase).
let bytes = ...;                         // Vec[UInt8]
let sym = bech32_bytes_to_symbols(&bytes);
match bech32_encode("bc", &sym, BECH32_VARIANT_BECH32) {
  Ok(text) => { io.println(text); },     // "bc1q..."
  Err(e)   => { io.println(e); },
}

// Decode: the variant is detected from the checksum.
match bech32_decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4") {
  Ok(v) => {
    // v.hrp == "bc", v.variant == BECH32_VARIANT_BECH32
    let payload = bech32_data(&v);       // Vec[Int] of 5-bit values
    let raw = bech32_symbols_to_bytes(&payload);
    io.println("ok: " + v.hrp);
  },
  Err(e) => { io.println(e); },
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `bech32_charset()` | `Str` | The 32-character data alphabet `qpzry9x8gf2tvdw0s3jn54khce6mua7l`. |
| `bech32_encode(hrp, data, variant)` | `Result[Str, Str]` | Encode HRP + 5-bit symbols under the chosen variant; canonical lowercase. |
| `bech32_decode(s)` | `Result[Bech32, Str]` | Decode and detect the variant from the checksum. |
| `bech32_decode_variant(s, variant)` | `Result[Bech32, Str]` | Decode, requiring one checksum constant. |
| `bech32_is_valid(s)` | `Bool` | True iff `bech32_decode(s)` is `Ok` (either variant). |
| `bech32_hrp(v)` | `Str` | HRP of a decoded value, lowercase. |
| `bech32_variant(v)` | `Int` | `BECH32_VARIANT_BECH32` or `BECH32_VARIANT_BECH32M`. |
| `bech32_data(v)` | `Vec[Int]` | 5-bit data symbols with the checksum removed. |
| `bech32_convertbits(data, frombits, tobits, pad)` | `Result[Vec[Int], Str]` | BIP-173 bit regrouping. |
| `bech32_bytes_to_symbols(data)` | `Vec[Int]` | 8->5 conversion with zero padding (total). |
| `bech32_symbols_to_bytes(data)` | `Result[Vec[UInt8], Str]` | 5->8 conversion, strict zero-padding rules. |

Constants: `BECH32_VARIANT_BECH32` (0, checksum constant 1) and
`BECH32_VARIANT_BECH32M` (1, checksum constant `0x2bc830a3`).

## Format rules

- A Bech32 string is **at most 90 characters** long and has the shape
  `hrp + "1" + data`. The last `1` in the string is the separator; it may
  also appear inside the HRP.
- **HRP:** 1..83 US-ASCII characters with values in `[33,126]`. The encoder
  requires the canonical lowercase form and rejects an uppercase HRP
  (emitting it would produce a mixed-case string); the decoder accepts an
  all-uppercase string and folds it to lowercase, and rejects mixed case.
- **Data part:** at least 6 characters from the alphabet above, ending in
  6 checksum characters.
- **Checksum:** `polymod(hrp-expand(hrp) + data) == 1` (Bech32) or
  `== 0x2bc830a3` (Bech32m).
- **Canonical output:** encoders always emit lowercase, exactly as BIP-173
  requires.

Pinned examples (BIP-173 / BIP-350 test vectors):

| String | Variant | HRP | Data symbols |
|---|---|---|---|
| `a12uel5l` | Bech32 | `a` | `[]` |
| `abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw` | Bech32 | `abcdef` | `[0..31]` |
| `a1lqfn3a` | Bech32m | `a` | `[]` |
| `abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx` | Bech32m | `abcdef` | `[31..0]` |
| `bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4` | Bech32 | `bc` | v0 address shape |

## Variants and ambiguity

BIP-350 states that no string can be simultaneously valid Bech32 and
Bech32m: validity is one equality `polymod(...) == constant`, and `1` and
`0x2bc830a3` are different values. A decoder therefore resolves every valid
string to exactly one variant, and there is no "valid under both" outcome
to report. This module exposes that distinction as:

- `bech32_decode(s)` -- `Ok(v)` with the unique variant that verified, or
  `Err("bech32: bad checksum")` under neither.
- `bech32_decode_variant(s, variant)` -- `Ok(v)` for the requested
  constant, `Err("bech32: wrong variant")` when the string is valid only
  under the other constant, `Err("bech32: bad checksum")` under neither.
  This is the check an application such as a segwit address parser should
  use after deciding which variant a payload requires.

## convertbits and padding

`bech32_convertbits(data, frombits, tobits, pad)` regroups bits most
significant first.

- **8->5 (`bech32_bytes_to_symbols`, pad = true):** each byte becomes 5-bit
  groups; a partial trailing group is zero-padded up to a whole symbol.
  Total: every `Vec[UInt8]` can be converted. 6 bytes (`foobar`) become
  10 symbols, the last symbol carrying 2 zero pad bits.
- **5->8 (`bech32_symbols_to_bytes`, pad = false):** the strict direction
  used for payload bytes. A trailing group is acceptable only when it is
  shorter than `frombits` (fewer than 5 bits) and all zero; anything else is
  `Err("bech32: invalid padding")`. 16 symbols may become 10 bytes exactly,
  while a single symbol cannot become a byte.

## Error model

All errors start with the literal prefix `bech32: `. They are produced by
`bech32_encode`, the two decoders, `bech32_convertbits` and
`bech32_symbols_to_bytes` (and surface as `false` from `bech32_is_valid`).
The first applicable rule in the documented order wins.

| Message | Trigger |
|---|---|
| `bech32: bad length` | Decode: total length < 8 or > 90, or data part < 6. Encode: resulting string would exceed 90. |
| `bech32: invalid hrp length` | Encode: HRP empty or longer than 83. |
| `bech32: invalid hrp character` | An HRP byte outside `[33,126]` (encode or decode). |
| `bech32: mixed case` | Decode: the string contains both uppercase and lowercase letters. Encode: the HRP contains an uppercase letter. |
| `bech32: missing separator` | Decode: no `1`, or `1` at position 0 (empty HRP). |
| `bech32: invalid data character` | A data-part byte outside the 32-character alphabet. |
| `bech32: invalid data value` | Encode: a data symbol outside 0..31. |
| `bech32: bad variant` | Encode / `bech32_decode_variant`: variant is not 0 or 1. |
| `bech32: bad checksum` | The polymod matches neither constant (or not the requested one and not the other). |
| `bech32: wrong variant` | `bech32_decode_variant`: the string is valid under the other constant. |
| `bech32: invalid bits` | `convertbits`: `frombits` or `tobits` outside 1..8. |
| `bech32: convertbits overflow` | `convertbits`: an input value is negative or >= 2^frombits. |
| `bech32: invalid padding` | `convertbits` with pad false: at least `frombits` leftover bits, or non-zero leftovers. |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bech32
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No segwit semantics.** Witness versions, program lengths and HRP
  selection (`bc`/`tb`/...) are application policy and are not implemented;
  the BIP address vectors are used only as codec-level pins.
- **No error correction.** BIP-173 discourages it; this codec only detects.
- **No base58, base64 or hex.** Sibling packages own those codecs.
- **Strict input.** No whitespace tolerance, no aliases, no
  auto-normalization; input is validated byte-for-byte.
- **Bytes/symbols only.** No `Str` UTF-8 convenience helpers; callers own
  the bytes <-> text boundary.
- **In-memory, O(n)**, no streaming API.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
