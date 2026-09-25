# xiom.ean

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness on compiler v0.61.3 (20/20). NOT published yet.
> **Scope:** EAN-13, EAN-8 and UPC-A parsing, validation, check-digit
> computation, structure access, canonical formatting and the UPC-A <-> EAN-13
> zero-prefix equivalence, for a documented digit-only subset.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`).

## What it is

`xiom.ean` validates the three canonical GS1 retail code lengths in their
ASCII digit forms:

- **EAN-13** -- exactly 13 digits (12-digit body plus check digit);
- **UPC-A** -- exactly 12 digits (11-digit body plus check digit);
- **EAN-8** -- exactly 8 digits (7-digit body plus check digit).

The trailing digit must equal the GS1 check digit computed over the body:
body digits weighted from the right with the alternating 3, 1, 3, 1, ...
sequence, summed, and `(10 - sum mod 10) mod 10`. `ean_parse` detects the type
from the input length; `ean13_parse`, `upca_parse` and `ean8_parse` enforce a
declared length, so a wrong length is a named error instead of a mismatch.

There is one representation, `Ean`, carrying the declared type (`kind`, which
equals the digit length) and the complete digit text. Structure accessors
expose the digits, the body, the check digit and the informational 3-digit
GS1 prefix field; `ean_compact` emits the canonical digit form and
`ean_format` the human-readable grouping used under a printed symbol.

Out of scope by design: barcode rendering, GS1 registry or company-prefix
validation, other symbologies (ITF, Code128, ...) and ISBN conversion.

## Install / use

```
xiom pkg install xiom.ean@0.1.0
```

```xi
use xiom.ean;
use xiom.io;

match ean_parse("4006381333931") {
  Ok(v) => {
    io.println(ean_format(&v));        // "4 006381 333931"
    io.println(ean_body(&v));          // "400638133393"
    io.println(ean_check_digit(&v));   // 1
    io.println(ean_country_prefix(&v));// "400" (informational)
  },
  Err(e) => {
    io.println(e);                     // "ean: bad check digit: ..."
  },
}
```

## Quick start

```xi
use xiom.ean;

// Validate and branch on the type.
if ean13_is_valid("5901234123457") { /* EAN-13 */ }
if upca_is_valid("036000291452")   { /* UPC-A  */ }
if ean8_is_valid("96385074")       { /* EAN-8  */ }

// Derive the check digit for a body and build a code.
match ean13_compute_check_digit("590123412345") {
  Ok(k) => { /* k == 7; the completed code is "5901234123457" */ },
  Err(e) => { io.println(e); },
}

// UPC-A and EAN-13 are one code space: a leading zero is the whole bridge.
// "036000291452" (UPC-A) <-> "0036000291452" (EAN-13)
```

## API reference

All functions are free functions in module `xiom.ean`.

```xi
pub const EAN_KIND_EAN8: Int = 8;
pub const EAN_KIND_UPCA: Int = 12;
pub const EAN_KIND_EAN13: Int = 13;

pub type Ean = { kind: Int; digits: Str; }
```

| Function | Returns | Description |
|---|---|---|
| `ean_parse(s)` | `Result[Ean, Str]` | Parse any supported type, detected by length (8/12/13). |
| `ean_is_valid(s)` | `Bool` | `true` iff `ean_parse` accepts `s`. |
| `ean13_parse(s)` / `ean13_is_valid(s)` | `Result[Ean, Str]` / `Bool` | Strict 13-digit EAN-13 entry points. |
| `upca_parse(s)` / `upca_is_valid(s)` | `Result[Ean, Str]` / `Bool` | Strict 12-digit UPC-A entry points. |
| `ean8_parse(s)` / `ean8_is_valid(s)` | `Result[Ean, Str]` / `Bool` | Strict 8-digit EAN-8 entry points. |
| `ean13_compute_check_digit(body)` | `Result[Int, Str]` | Check digit for a 12-digit EAN-13 body. |
| `upca_compute_check_digit(body)` | `Result[Int, Str]` | Check digit for an 11-digit UPC-A body. |
| `ean8_compute_check_digit(body)` | `Result[Int, Str]` | Check digit for a 7-digit EAN-8 body. |
| `ean_kind(v)` | `Int` | Declared type (8, 12 or 13). |
| `ean_digits(v)` | `Str` | Complete digit text including the check digit. |
| `ean_body(v)` | `Str` | Digits without the check digit (`kind - 1` digits). |
| `ean_check_digit(v)` | `Int` | Check digit value, `0..9`. |
| `ean_country_prefix(v)` | `Str` | Informational 3-digit GS1 prefix field (not authoritative). |
| `ean_compact(v)` | `Str` | Canonical digit text, no separators. |
| `ean_format(v)` | `Str` | Grouped display: EAN-13 `1-6-6`, UPC-A `1-5-5-1`, EAN-8 `4-4`. |
| `upca_to_ean13(s)` | `Result[Str, Str]` | Valid UPC-A -> zero-prefixed 13-digit EAN-13. |
| `ean13_to_upca(s)` | `Result[Str, Str]` | Zero-prefixed EAN-13 -> 12-digit UPC-A. |
| `ean13_is_upca_equivalent(s)` | `Bool` | `true` for a valid EAN-13 starting with `0`. |

## Error model

`ean_parse`, in order:

| Condition | Message |
|---|---|
| `s == ""` | `ean: empty input` |
| length not 8, 12 or 13 | `ean: bad length: <n> (expected 8, 12 or 13)` |
| a non-digit byte | `ean: bad characters: <s>` |
| check digit mismatch | `ean: bad check digit: <s>` |

The typed parsers (`ean13_parse`, `upca_parse`, `ean8_parse`) replace the
length row with a declared-type message:
`ean: bad length for EAN-13: expected 13, got <n>` (likewise `UPC-A` 12 and
`EAN-8` 8).

The check-digit helpers report `ean: empty input`,
`ean: bad body length for EAN-13: expected 12, got <n>` (likewise `UPC-A` 11
and `EAN-8` 7), and `ean: bad characters: <body>`.

`ean13_to_upca` adds `ean: not UPC-A equivalent: <s>` for a valid EAN-13 whose
first digit is not `0`; all other failures propagate the wrapped parser's
error unchanged. `upca_to_ean13` propagates `upca_parse` errors unchanged.

Input is strict: spaces, hyphens, lowercase and other non-digit bytes are
rejected (`bad characters`), never normalized. The grouped output of
`ean_format` is display text; strip the spaces before parsing it again.

## Limitations

- **Check-digit validation only.** A valid check digit proves internal
  consistency, not that GS1 assigned the code; `0000000000000` is
  check-digit-valid and deliberately accepted. The all-zero GTIN is never
  assignable by GS1.
- **No GS1 registry.** `ean_country_prefix` returns the first three body
  digits as an informational field. GS1 prefixes are 2-3 digits in the
  registry, indicate the issuing member organization (not the country of
  manufacture) and change over time; no prefix-to-country table is built in
  or implied.
- **No chained EAN-2 / EAN-5 add-ons** (the extra digits beside a printed
  EAN-13/UPC-A symbol).
- **No ITF, Code128 or other symbologies, and no ISBN conversion.**
- **No barcode rendering.**
- No FFI, no `extern "C"` blocks, and no dynamic allocation in the library
  module beyond the string slices it returns.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ean
```

Expected: 20 `[PASS]` lines and
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

Coverage: published fixtures for all three types parsed field by field;
check-digit computation for seven fixtures; compute -> build -> parse
round-trips; all-zero, all-nines and zero-check-digit boundaries; auto
detection by length; both UPC-A <-> EAN-13 directions plus their error paths;
grouped formatting; exact messages for every error class (empty, unsupported
length, declared bad length, bad characters, bad check digit, bad body
length, not UPC-A equivalent). See `SPEC.md` for the formal contract and the
test matrix.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
