# xiom.punycode -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.punycode`, version `0.1.0`).
Module: `src/punycode.xi` (`module xiom.punycode`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI, no
external tables.

## 1. Scope

Five free functions:

```xi
pub fn punycode_encode_label(label: Str) -> Result[Str, Str]
pub fn punycode_decode_label(label: Str) -> Result[Str, Str]
pub fn punycode_to_ascii(domain: Str) -> Result[Str, Str]
pub fn punycode_to_unicode(domain: Str) -> Result[Str, Str]
pub fn punycode_is_ascii_label(label: Str) -> Bool
```

All scanning is byte-wise via `xiom.string.byte_at`; every raw byte is widened
with `(byte_at(s, i) as Int) & 0xFF` before comparisons and arithmetic.
Labels are decoded to `Vec[Int]` code point lists instead of `Vec[StructType]`.
Output is accumulated in `Vec[UInt8]` and materialized once per result with
`xiom.string.builder.sb_to_str`. `Ok`/`Err` values are constructed only in the
leaf helpers `_pc_ok` / `_pc_err`.

## 2. Algorithm summary (RFC 3492)

Constants: `base = 36`, `tmin = 1`, `tmax = 26`, `skew = 38`, `damp = 700`,
`initial_bias = 72`, `initial_n = 128`.

Bias adaptation (section 6.1):

```
adapt(delta, numpoints, firsttime):
  delta = delta / damp  if firsttime, else delta / 2
  delta = delta + delta / numpoints
  k = 0
  while delta > (base - tmin) * tmax / 2:
    delta = delta / (base - tmin)
    k = k + base
  return k + (base - tmin + 1) * delta / (delta + skew)

t(k, bias) = tmin            if k <= bias
             tmax            if k >= bias + tmax
             k - bias        otherwise
```

Encoding (section 6.3):

1. Decode the label to code points; every ASCII code point (< 0x80) is copied
   verbatim and counted as a basic code point.
2. If at least one basic code point exists, append `-`.
3. Repeatedly take the smallest remaining non-basic code point `m`, update
   `delta` and emit one generalized variable-length integer per occurrence of
   `m` using `base`, `t(k, bias)` and `adapt`.

Decoding (section 6.2):

1. The bytes before the **last** `-` are the basic section; they must all be
   ASCII and are copied verbatim. Without a `-` the basic section is empty
   and the whole input is a digit run (so `r8jz45g` decodes to `例え`).
2. Read generalized variable-length integers, adapt the bias, and insert the
   recovered code points into the output list at each computed position.

Round-trip invariant: for every label `s` accepted by
`punycode_encode_label`, `punycode_decode_label(encode(s)) == Ok(s)`.

## 3. Digit alphabet (section 5)

| Digit value | Characters |
|---|---|
| 0..25 | `a`..`z` (decode also accepts `A`..`Z`) |
| 26..35 | `0`..`9` |

Digits are case-insensitive on decode. Any other byte (including space, `_`,
`.`, `!` and every byte >= 0x80) is not a digit.

## 4. UTF-8 handling

`punycode_encode_label` decodes labels with a manual RFC 3629 decoder.
Rejected (Err): invalid lead bytes, stray continuation bytes, truncated
sequences, overlong forms, UTF-16 surrogates (U+D800-U+DFFF) and code points
above U+10FFFF. In the basic section of a decode, any byte >= 0x80 is
rejected; in the digit section each byte is validated as a digit.

## 5. Error catalog

Every message starts with `punycode: `. Callers see:

| Message | Raised by | Condition |
|---|---|---|
| `punycode: invalid UTF-8` | `punycode_encode_label`, `punycode_to_ascii` | label bytes are not well-formed UTF-8 |
| `punycode: overflow` | encode/decode | arithmetic exceeds `_PC_MAXINT` (2147483647) |
| `punycode: non-ASCII basic code point` | decode | byte >= 0x80 before the last `-` |
| `punycode: invalid digit` | decode | byte outside the digit alphabet |
| `punycode: truncated encoded data` | decode | digit run ends before `t(k, bias)` is reached |
| `punycode: code point out of range` | decode | decoded code point > U+10FFFF |

`punycode_to_ascii` / `punycode_to_unicode` propagate the first label error
unchanged. Infallible functions: `punycode_is_ascii_label`.

## 6. Domain rules

- Labels are split on `.`; empty labels (including a leading, doubled or
  trailing dot) are preserved.
- `punycode_to_ascii`: ASCII labels pass through unchanged (no case folding);
  empty labels stay empty; non-ASCII labels become `"xn--" + punycode`.
- `punycode_to_unicode`: labels whose first four bytes are `xn--` in any
  ASCII case have those bytes stripped and the rest decoded; all other labels
  (including non-ASCII ones) pass through unchanged.
- No length limits, no IDNA validity checks, no normalization.

## 7. Test plan (`tests/test_conformance.xi`, 20 checks)

| # | Check |
|---|---|
| 1 | encode RFC examples: `bücher` -> `bcher-kva`, `mañana` -> `maana-pta`, `例え` -> `r8jz45g`, `Δ` -> `swa` |
| 2 | decode the same four vectors |
| 3 | all-ASCII labels (incl. `""`) encode unchanged |
| 4 | short non-ASCII labels: `ä`, `ü`, `Ü`, `café`, `münchen` |
| 5 | `punycode_is_ascii_label` for `""`, ASCII, umlauts, CJK, raw 0xFF/0x80 |
| 6 | `to_ascii`: mixed domains, ASCII passthrough |
| 7 | `to_unicode`: `xn--` decoding, ASCII passthrough |
| 8 | case-insensitive `XN--` prefix and digits, case-preserving basic part |
| 9 | empty labels preserved in both directions |
| 10 | invalid digit bytes are Err |
| 11 | long digit runs (60 `z`/`9`s) are Err (overflow) |
| 12 | invalid UTF-8 leads/truncations/overlongs are Err |
| 13 | Greek `ελλάδα` <-> `hxakic4aa` |
| 14 | Cyrillic `москва` <-> `80adxhks` |
| 15 | dotless label round-trips |
| 16 | full-domain round-trips through `to_ascii`/`to_unicode` |
| 17 | decode preserves basic-section case (`BCHER-KVA` -> `Bücher`) |
| 18 | domain functions propagate label errors |
| 19 | `to_ascii` never re-encodes; non-`xn--` labels pass `to_unicode` |
| 20 | batch round-trip over ten pinned labels |

All string equality in the suite goes through
`xiom.string.compare.str_compare` (BUG 17: `==` on `Str` values read from
`Vec[Str]` lowers to a pointer comparison).
