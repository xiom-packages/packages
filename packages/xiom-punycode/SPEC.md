# xiom.punycode -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
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

## Contracts (batch #28 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/punycode.xi` in the batch
#28 hardening pass (compiler v0.64.0; `package.xi` is bumped by the
coordinator at integration). 11 clauses across the 5 public entry points; all
are `ensures:` (no `requires:`), so the accepted-input domain is unchanged.
Two consecutive `& .\scripts\port.ps1 -Package xiom.punycode -TimeoutSec 60`
runs ended `port: PASS (passed=20 failed=0 program_exit=0 exit=0)` with the
clauses active (7.01 s and 6.93 s); the 20-check conformance suite exercises
every entry point, including the invalid-UTF-8, invalid-digit, overflow and
out-of-range `Err` paths and the empty-input cases, and no clause trapped.

All 11 clauses are runtime-checked: each reads a `Str` length, a `Result` tag,
or (one clause) calls `punycode_is_ascii_label`, so none is claimed
Z3-provable.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `punycode_is_ascii_label` | `ensures: label.len() == 0 => result`; `ensures: !result => label.len() > 0` | runtime-checked (`Str` length + Bool guard pair) |
| `punycode_encode_label` | `ensures: label.len() == 0 => result is Ok`; `ensures: punycode_is_ascii_label(label) => result is Ok`; `ensures: result is Err => label.len() > 0` | runtime-checked (`Result` tag + `Str` length; one non-re-entrant cross-call) |
| `punycode_decode_label` | `ensures: label.len() == 0 => result is Ok`; `ensures: result is Err => label.len() > 0` | runtime-checked (`Result` tag + `Str` length) |
| `punycode_to_ascii` | `ensures: domain.len() == 0 => result is Ok`; `ensures: result is Err => domain.len() > 0` | runtime-checked (`Result` tag + `Str` length) |
| `punycode_to_unicode` | `ensures: domain.len() == 0 => result is Ok`; `ensures: result is Err => domain.len() >= 5` | runtime-checked (`Result` tag + `Str` length) |

The one cross-call, `punycode_is_ascii_label(label) => result is Ok` on
`punycode_encode_label`, is safe: the predicate scans bytes only and never
calls back into `punycode_encode_label` (non-re-entrant). The
`punycode_to_unicode` lower bound (`result is Err => domain.len() >= 5`) was
verified against the source's `Err` paths: `Err` can only surface through
`punycode_decode_label` on an `xn--` label payload, and the shortest such
label is five bytes (`xn--` plus at least one digit byte); a four-byte `xn--`
label yields the empty payload, which decodes to `Ok("")`.

Deliberately not claimed: `Ok` payload lengths on the label decoders
(payload-length-vs-parameter is a forbidden shape); `Str` equality anywhere
(BUG 17). No clause was dropped.
