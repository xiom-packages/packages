# xiom.punycode

> **Status:** `incubating` -- implemented and harness-green (compiler v0.61.3),
> **NOT published**. The API may change before 1.0.
> **Scope:** RFC 3492 Punycode for IDN labels: `xn--` encode/decode of domain
> labels with no external tables.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`). No FFI.

## What it is

`xiom.punycode` implements the RFC 3492 bootstring algorithm (base 36 with
bias adaptation) for converting Unicode domain labels to their ASCII
compatible encoding and back. The digit alphabet is inline; there are no
generated tables and no host-library calls.

This package is deliberately the Punycode layer only. It does **not** perform
IDNA (RFC 5890/5891) mapping, case folding, normalization or validity checks;
compose it with those rules when building a full IDN pipeline (see
[Limitations](#limitations)).

## API

| Function | Returns | Description |
|---|---|---|
| `punycode_encode_label(label)` | `Result[Str, Str]` | Unicode label -> Punycode **without** the `xn--` prefix. All-ASCII labels return unchanged (including `""`). |
| `punycode_decode_label(label)` | `Result[Str, Str]` | Punycode **without** the `xn--` prefix -> Unicode label. Digits are case-insensitive; the last `-` separates verbatim basic code points. |
| `punycode_to_ascii(domain)` | `Result[Str, Str]` | Dot-separated domain: ASCII labels unchanged, non-ASCII labels become `xn--...`; empty labels preserved. |
| `punycode_to_unicode(domain)` | `Result[Str, Str]` | Dot-separated domain: labels starting `xn--` (case-insensitive) are decoded; all other labels pass through. |
| `punycode_is_ascii_label(label)` | `Bool` | True when every byte of the label is `< 0x80`. |

```xi
use xiom.punycode;

let a = punycode_to_ascii("münchen.de");   // Ok("xn--mnchen-3ya.de")
let u = punycode_to_unicode("xn--mnchen-3ya.de"); // Ok("münchen.de")
let e = punycode_encode_label("bücher");   // Ok("bcher-kva")
let d = punycode_decode_label("bcher-kva"); // Ok("bücher")
punycode_is_ascii_label("example.com");    // true
```

## RFC references

- **RFC 3492** -- *Punycode: A Bootstring encoding of Unicode for
  Internationalized Domain Names in Applications (IDNA)*. This package
  implements sections 5 (digit alphabet), 6.1 (bias adaptation), 6.2
  (decoding) and 6.3 (encoding).
- **RFC 3629** -- *UTF-8, a transformation format of ISO 10646*. Used for
  the manual UTF-8 decode/encode of labels; overlong forms, surrogates and
  code points above U+10FFFF are rejected.
- **RFC 5890 / RFC 5891** -- IDNA definitions and protocol. Referenced for
  context only; **not** implemented here.

## Testing

```
xiom --run tests/test_conformance.xi
```

Expected: twenty `[PASS]` lines, then `xiom.punycode: all tests passed`,
exit 0. The same suite is what `scripts/port.ps1 -Package xiom.punycode`
executes.

Pinned RFC 3492 vectors include `bücher` <-> `bcher-kva`,
`mañana` <-> `maana-pta`, `例え` <-> `r8jz45g`, `Δ` <-> `swa` and
`münchen` <-> `mnchen-3ya`.

## Limitations

- **RFC 3492 only.** No IDNA mapping or normalization (UTS-46, NFC/NFKC,
  RFC 5892 code point validity, case folding, bidi rules) is applied.
- ASCII labels are passed through **unchanged** (not lowercased), on both
  `punycode_to_ascii` and `punycode_to_unicode`.
- `punycode_decode_label` treats its argument as the encoded part only:
  an all-digit input such as `r8jz45g` decodes rather than passing through.
- `punycode_to_unicode` passes non-`xn--` labels through without validating
  their UTF-8; use `punycode_encode_label` (or a validator) when strict
  validation of a Unicode label is required.
- Domain length limits (253 characters), label length limits and the
  restriction that a decoded label must not be all-ASCII are IDNA concerns
  and are not enforced by this package.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
