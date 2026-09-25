# xiom.luhn

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness on compiler v0.61.3 (18/18). NOT published yet.
> **Scope:** canonical Luhn (mod-10) parsing and validation, check-digit
> computation, check-digit appending, space/hyphen normalization of display
> text, and structure access, for a documented digit-only subset.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.convert`).

## What it is

`xiom.luhn` implements the Luhn (mod-10) check-digit rule for ASCII digit
strings:

- a complete number is valid when doubling every second digit from the right
  (the trailing check digit is never doubled), subtracting 9 from any doubled
  value above 9, and summing the result gives a multiple of 10;
- the check digit of a body (the number without its last digit) is
  `(10 - weighted body sum mod 10) mod 10`, where doubling starts at the
  rightmost body digit.

`luhn_parse` verifies canonical digit text and returns a `Luhn` value carrying
the validated digits. Input is strict: spaces, hyphens and every other
non-digit byte are rejected, never silently accepted. For human-readable
display forms, `luhn_normalize` strips exactly the two documented separators
(space and hyphen) and `luhn_parse_normalized` normalizes before applying the
same canonical rules; every other separator (dot, slash, underscore, tab)
remains a `bad characters` error. The minimum accepted length is two digits
(`LUHN_MIN_DIGITS`); there is no maximum length beyond the platform's string
and `Int` capacities.

This is the same arithmetic check used by many identifier schemes, but the
package attaches no scheme semantics: it is a check-digit codec, not a
validator of who may issue a number.

## Install / use

```
xiom pkg install xiom.luhn@0.1.0
```

```xi
use xiom.luhn;
use xiom.io;

match luhn_parse("79927398713") {
  Ok(v) => {
    io.println(luhn_digit_count(&v));  // 11
    io.println(luhn_body(&v));         // "7992739871"
    io.println(luhn_check_digit(&v));  // 3
  },
  Err(e) => {
    io.println(e);                     // "luhn: bad check digit: ..."
  },
}
```

## Quick start

```xi
use xiom.luhn;

// Strict verification: canonical digits only.
if luhn_is_valid("1234567812345670") { /* check digit agrees */ }

// Display forms: strip the documented separators first.
if luhn_is_valid_normalized("1234-5678-1234-5670") { /* same number */ }

// Derive the check digit for a body and build the full number.
match luhn_append_check_digit("453201511283036") {
  Ok(full) => { /* full == "4532015112830366" */ },
  Err(e)    => { io.println(e); },
}

// Or compute just the digit.
match luhn_compute_check_digit("453201511283036") {
  Ok(k) => { /* k == 6 */ },
  Err(e) => { io.println(e); },
}
```

## API reference

All functions are free functions in module `xiom.luhn`.

```xi
pub const LUHN_MIN_DIGITS: Int = 2;

pub type Luhn = { digits: Str; }
```

| Function | Returns | Description |
|---|---|---|
| `luhn_parse(s)` | `Result[Luhn, Str]` | Strict parse and full validation of canonical digits. |
| `luhn_is_valid(s)` | `Bool` | `true` iff `luhn_parse` accepts `s`. |
| `luhn_normalize(s)` | `Str` | Remove exactly the separators space and hyphen. |
| `luhn_parse_normalized(s)` | `Result[Luhn, Str]` | Normalize (space/hyphen) then parse and validate. |
| `luhn_is_valid_normalized(s)` | `Bool` | `true` iff `luhn_parse_normalized` accepts `s`. |
| `luhn_compute_check_digit(body)` | `Result[Int, Str]` | Check digit `0..9` for a body. |
| `luhn_append_check_digit(body)` | `Result[Str, Str]` | Body plus its check digit, as canonical text. |
| `luhn_digits(v)` | `Str` | Validated digit text including the check digit. |
| `luhn_digit_count(v)` | `Int` | Number of digits, including the check digit. |
| `luhn_body(v)` | `Str` | Digits without the trailing check digit. |
| `luhn_check_digit(v)` | `Int` | Check digit value, `0..9`. |

## Error model

`luhn_parse`, in order:

| Condition | Message |
|---|---|
| `s == ""` | `luhn: empty input` |
| a non-digit byte | `luhn: bad characters: <s>` |
| fewer than 2 digits | `luhn: too short: <s> (minimum 2 digits)` |
| check digit mismatch | `luhn: bad check digit: <s>` |

`luhn_parse_normalized` first handles `luhn: empty input` for `s == ""`, then
`luhn: only separators: <s>` when `s` is non-empty but normalizes to the empty
string; after that it reports the canonical errors above, with `<s>` being the
**normalized** digit text (the only-separators message echoes the raw input).

`luhn_compute_check_digit` and `luhn_append_check_digit` report
`luhn: empty input` for an empty body and `luhn: bad characters: <body>` for a
non-digit body; `luhn_append_check_digit` propagates those messages unchanged.

There are no panics and no other error strings; every failing input maps to
exactly one class by the orders above. The `*_is_valid` shorthands collapse
every error to `false`.

## Limitations

- **Check-digit arithmetic only.** A passing number is internally consistent;
  it is not proof that any issuer assigned it. The documented fixtures are
  public arithmetic test vectors, not validity claims about brands, issuers or
  accounts.
- **No scheme semantics.** No card-brand rules, no PAN/IBAN/IMEI/ISBN
  structure, no length rules beyond `LUHN_MIN_DIGITS`, no Luhn-inverse or
  check-digit-position search.
- **No BigInt.** Digit indexing and the running sum use `Int`; one digit
  contributes at most 9, so the sum cannot overflow for any `Str` length the
  platform can hold.
- **Two separators, no more.** Only space and hyphen are normalized; dots,
  slashes, underscores, tabs and any other non-digit byte are
  `bad characters`. Normalization is explicit: strict parsing never normalizes.
- **No floating point and no `Vec`:** scalar integer arithmetic only.
- **Display formatting is left to callers.** The package emits no grouped
  text; use `luhn_normalize` to go back from a grouped form.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.luhn
```

Expected: 18 `[PASS]` lines and
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

Coverage: six public arithmetic fixtures parsed field by field; check-digit
computation and append round-trips; the 9-subtraction boundary; the minimum
length policy; normalization and the strict/normalized split; all separator
rejections; the full error catalog with exact messages; one-byte mutations;
`is_valid` truth tables; and 1000-digit bodies to show `Int` safety and the
absence of a length ceiling. See `SPEC.md` for the formal contract and the
test matrix.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
