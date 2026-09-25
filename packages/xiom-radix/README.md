# xiom.radix

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) signed integer text conversion for bases
> 2..36 over the canonical lowercase alphabet, with strict parsing, canonical
> emission and exact overflow detection against the 64-bit `Int` range.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.core`; tests add `xiom.test`, `xiom.io`, `xiom.string`,
> `xiom.string.compare`).

## What it is

`xiom.radix` is a small, dependency-light radix codec for whole numbers. It
parses digit text in any base from 2 to 36 into a signed `Int`, emits an
`Int` back as canonical lowercase digit text, and converts between bases
through `Int`. There are no prefixes, no fractions and no arbitrary
precision: values outside `[-9223372036854775808, 9223372036854775807]` are
rejected with a deterministic error instead of being truncated or wrapped.

## Install / use

```
xiom pkg install xiom.radix@0.1.0
```

```xi
use xiom.radix;
use xiom.io;

// Parse: "1010" is ten in base 2, "ff" is 255 in base 16.
let a = radix_to_int("1010", 2);      // Ok(10)
let b = radix_to_int("-ff", 16);      // Ok(-255)
match b {
  Ok(v)  => { io.println(radix_from_int(v, 10)); },  // -255
  Err(e) => { io.println(e); },
}

// Base-to-base: 511 decimal is 777 octal is 1ff hex.
match radix_convert("777", 8, 16) {
  Ok(t)  => { io.println(t); },       // 1ff
  Err(e) => { io.println(e); },
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `radix_alphabet()` | `Str` | The 36-character canonical alphabet `0123456789abcdefghijklmnopqrstuvwxyz`. |
| `radix_digit_value(c)` | `Int` | Digit value of a byte: `0..9` for `0-9`, `10..35` for `a-z`/`A-Z`, `-1` otherwise. |
| `radix_to_int(s, base)` | `Result[Int, Str]` | Signed parse in `base` (2..36); optional `+`/`-`; leading zeros accepted. |
| `radix_from_int(n, base)` | `Result[Str, Str]` | Canonical lowercase text for `n` in `base` (2..36). |
| `radix_convert(s, from, to)` | `Result[Str, Str]` | `s` parsed in `from`, emitted in `to`; both bases 2..36. |
| `radix_is_valid(s, base)` | `Bool` | True exactly when `radix_to_int(s, base)` is `Ok`. |

## Alphabet and canonical form

```
0123456789abcdefghijklmnopqrstuvwxyz
```

- Index 0 is `'0'`; index 35 is `'z'`. Values 10..35 are the letters `a`..`z`.
- **Parsing accepts both cases**: `a-z` and `A-Z` map to the same digit
  values (`"FF"` parses as 255 in base 16).
- **Emission is lowercase only**: `radix_from_int(255, 16)` is `"ff"`.
- Zero emits the single digit `"0"`; negative values emit a leading `-`;
  a `+` is never emitted.
- There are no prefixes (`0x`, `0b`, `0o`), no whitespace, no underscores and
  no digit separators. Any byte outside `0-9a-zA-Z` is an invalid digit.

## Error model

All errors start with the literal prefix `radix: ` and are produced by
`radix_to_int`, `radix_from_int` and `radix_convert`. Checks run in a fixed
order: first the base range, then the input scan left to right.

| Message | Trigger |
|---|---|
| `radix: base out of range` | `base` (or `from_base`/`to_base`) is outside 2..36. |
| `radix: empty input` | The input string is empty. |
| `radix: lone sign` | The input is exactly `"+"` or `"-"`. |
| `radix: invalid digit at position N` | Byte `N` (0-based, counting the sign byte) is not a digit, or is a digit `>= base`. |
| `radix: overflow` | The value does not fit the signed 64-bit `Int` range. |

`radix_from_int` can only return `radix: base out of range`; the other
messages come from parsing. `radix_is_valid` returns `false` for every one of
them, including an out-of-range base.

## Overflow rules

Values are checked against the exact `Int` bounds at every step:

- `radix_to_int("9223372036854775807", 10)` is `Ok(INT_MAX)`;
  `"9223372036854775808"` is `Err("radix: overflow")`.
- `radix_to_int("-9223372036854775808", 10)` is `Ok(INT_MIN)`;
  `"-9223372036854775809"` is `Err("radix: overflow")`.
- There is no wrap-around and no saturating mode.
- `radix_convert` goes through `Int`, so it is exact for every in-range
  value and reports `radix: overflow` for anything outside the range; it is
  not an arbitrary-precision converter.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.radix
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integers only.** No fractional values, no decimal point, no exponent
  notation; `xiom.convert.parse.parse_float` and friends cover floats.
- **64-bit range only.** No BigInt and no arbitrary-precision path; values
  outside the `Int` range are errors.
- **Fixed alphabet.** No custom alphabets, no aliases and no locale-specific
  digits; the canonical alphabet is always lowercase.
- **No prefixes or separators.** `0x`/`0b`/`0o` input is rejected (the `x`
  is an invalid digit), as are whitespace and underscores.
- **Strict input.** Leading zeros are accepted on parse but no other
  normalization is performed; the parser is case-insensitive for letters
  only.
- **In-memory, whole-string API.** No streaming reader/writer.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
