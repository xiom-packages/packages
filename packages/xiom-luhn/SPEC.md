# xiom.luhn -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.luhn`, version `0.1.0`).
Module: `src/luhn.xi` (`module xiom.luhn`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert`); no other dependencies.

## Scope

A pure-XIOM (no FFI) Luhn (mod-10) check-digit codec for a documented
digit-only subset:

- `luhn_parse`: strict parse and full validation of canonical ASCII digit
  text (no separators) with the trailing check digit verified;
- `luhn_is_valid`: boolean shorthand for `luhn_parse`;
- `luhn_normalize`: strip exactly the documented separators (space, hyphen);
- `luhn_parse_normalized` / `luhn_is_valid_normalized`: normalize first, then
  apply the canonical rules, for human-readable grouped input;
- `luhn_compute_check_digit`: derive the check digit for a body;
- `luhn_append_check_digit`: body plus check digit as canonical text;
- `luhn_digits` / `luhn_digit_count` / `luhn_body` / `luhn_check_digit`:
  accessors on a parsed value.

## Non-goals

- Card-brand or issuer rules (BIN/IIN ranges, lengths, prefixes), PAN
  semantics, or any claim that a check-digit-valid number is real or
  assignable.
- IBAN, IMEI, ISBN, credit-card or any other scheme's structure: only the
  arithmetic check is modeled.
- BigInt / arbitrary precision: indexing and the running sum are `Int`.
- Charset beyond ASCII `0-9`, and separators beyond U+0020 space and U+002D
  hyphen-minus.
- Luhn inversion (recovering unknown digits), check-digit position search,
  or error-correction codes.
- Any implicit normalization in the strict entry points: `luhn_parse` and
  `luhn_compute_check_digit` reject separators; normalization is explicit.

## Data model

```xiom
pub const LUHN_MIN_DIGITS: Int = 2;

pub type Luhn = {
  digits: Str;   // canonical ASCII digits including the check digit
}
```

A valid `Luhn` always satisfies `digits.len() >= LUHN_MIN_DIGITS`, every byte
is `0-9`, and the last digit equals the check digit computed over the body
(`digits` without its last byte). The type stores no other state; the
accessors recompute the body slice and check value from `digits`.

## Input grammar (strict)

```
luhn    := DIGIT+ DIGIT                ; >= 2 digits, last is the check digit
DIGIT   := "0".."9"
```

No whitespace, separator, sign or other byte is allowed anywhere. The byte
length equals the character length because only ASCII is admitted. There is
no upper bound beyond the platform's string and `Int` capacities: the
implementation loops over `Int` indices, and a body of `n` digits adds at
most `9 * n` to the sum.

Validation order is fixed so every malformed input has exactly one
deterministic error:

1. empty input;
2. every byte is `0-9` (charset);
3. at least `LUHN_MIN_DIGITS` digits;
4. the trailing digit equals the computed check digit.

Charset precedes length so a non-digit byte is always reported as
`bad characters`, never as `too short` (for example `"A"` is
`bad characters`, while `"1"` is `too short`).

For the normalized entry point the order is: raw empty input; normalize;
normalized text empty (`only separators`); then the canonical order above
over the normalized text.

## Normalization rules

`luhn_normalize(s)` copies `s` byte by byte and drops exactly two bytes:

| Byte | Character | Removed |
|---|---|---|
| `0x20` | space | yes |
| `0x2D` | hyphen-minus `-` | yes |
| anything else | | no, copied unchanged |

The result is not validated. `luhn_parse_normalized` applies the canonical
grammar to the normalized text, so `"4532-0151 1283-0366"` becomes
`"4532015112830366"`, while `"4532.0151.1283.0366"` fails with
`luhn: bad characters: 4532.0151.1283.0366` (dots are copied through and are
not digits). Input that is non-empty but consists only of removable
separators (`"  - - "`) fails with `luhn: only separators: <s>`; raw `""`
fails with `luhn: empty input`. Messages of the normalized parser echo the
normalized digits, except the only-separators message which echoes the raw
input.

## Check-digit algorithm

For a body `d[0]..d[n-1]` (all ASCII digits, `n >= 1`):

```
sum = 0
double_next = true                  ; the rightmost body digit is doubled
for i = n-1 down to 0:
  v = int(d[i])
  if double_next:
    v = v * 2
    if v > 9: v = v - 9             ; the standard 9-subtraction rule
  sum = sum + v
  double_next = not double_next
check = (10 - (sum mod 10)) mod 10
```

For a complete number `d[0]..d[n-1]` (all ASCII digits, `n >= 2`) validity is
evaluated by the same walk with `double_next = false` at the rightmost
position (the check digit is never doubled): the number is valid exactly when
the total is a multiple of 10. The two walks are consistent: the complete-sum
walk over `body + check` equals the body walk plus the check digit, because
appending the check shifts the body's doubling phase back to the body's
rightmost digit.

The `mod 10` outside the parentheses is what yields check digit `0` when the
body sum is a multiple of 10 (for example the body `"0"` or `"00"`).

Worked examples (all covered by the tests):

| Number | Body | Check | Note |
|---|---|---|---|
| `79927398713` | `7992739871` | 3 | classic published vector |
| `1234567812345670` | `123456781234567` | 0 | check digit 0 |
| `4532015112830366` | `453201511283036` | 6 | published vector |
| `4111111111111111` | `411111111111111` | 1 | repeated-digit body |
| `378282246310005` | `37828224631000` | 5 | odd digit count (15) |
| `3566002020360505` | `356600202036050` | 5 | published vector |
| `00` | `0` | 0 | minimum length |
| `18` | `1` | 8 | 9-subtraction at `1` |
| `91` | `9` | 1 | 9-subtraction at `9` (18 -> 9) |
| `893` | `89` | 3 | mixed weights |
| `9999999999999995` | `999999999999999` | 5 | all-nines body |

Verification walk for the valid `79927398713`: from the right,
`3`, `1*2=2`, `7`, `8*2-9=7`, `9`, `3*2=6`, `7`, `2*2=4`, `9`,
`9*2-9=9`, `7` sum to 70, a multiple of 10. The mutated `79927398714` sums
to 71 and is rejected.

The sum is at most `9 * len`, so `Int` cannot overflow for any string the
platform can represent.

## API contract

```xi
pub const LUHN_MIN_DIGITS: Int = 2;
pub type Luhn = { digits: Str; }

pub fn luhn_parse(s: Str) -> Result[Luhn, Str]
pub fn luhn_is_valid(s: Str) -> Bool
pub fn luhn_normalize(s: Str) -> Str
pub fn luhn_parse_normalized(s: Str) -> Result[Luhn, Str]
pub fn luhn_is_valid_normalized(s: Str) -> Bool
pub fn luhn_compute_check_digit(body: Str) -> Result[Int, Str]
pub fn luhn_append_check_digit(body: Str) -> Result[Str, Str]
pub fn luhn_digits(v: &Luhn) -> Str
pub fn luhn_digit_count(v: &Luhn) -> Int
pub fn luhn_body(v: &Luhn) -> Str
pub fn luhn_check_digit(v: &Luhn) -> Int
```

- `luhn_parse` returns `Ok(Luhn)` for canonical valid digits and
  `Err("luhn: ...")` otherwise; the returned `digits` are exactly the input.
- `luhn_parse_normalized` returns the normalized digits in `Ok(Luhn)`, never
  the raw grouped text.
- `luhn_is_valid` / `luhn_is_valid_normalized` are exact boolean shorthands:
  `true` iff the corresponding parser returns `Ok`. Every error collapses to
  `false`.
- `luhn_compute_check_digit(body)` accepts any non-empty all-digit body,
  including one digit; the result is the digit that makes `body + check`
  valid.
- `luhn_append_check_digit(body)` equals
  `body + int_to_string(luhn_compute_check_digit(body))`.
- Accessors are total on a parsed value: `luhn_digit_count` is
  `digits.len()`, `luhn_body` is every digit but the last, and
  `luhn_check_digit` is the numeric value of the last digit.
- `LUHN_MIN_DIGITS` is the only policy constant: 2.

## Error catalog

`luhn_parse`, in validation order:

| Condition | Message |
|---|---|
| `s == ""` | `luhn: empty input` |
| a byte outside `0-9` (separators included) | `luhn: bad characters: <s>` |
| `len(s) < LUHN_MIN_DIGITS` | `luhn: too short: <s> (minimum 2 digits)` |
| `(10 - sum mod 10) mod 10 != last digit` | `luhn: bad check digit: <s>` |

`luhn_parse_normalized` adds, before the canonical rows and over the raw
input:

| Condition | Message |
|---|---|
| `s == ""` | `luhn: empty input` |
| `s != ""` but `luhn_normalize(s) == ""` | `luhn: only separators: <s>` |

After normalization the canonical rows apply with `<s>` replaced by the
normalized digit text.

`luhn_compute_check_digit` and `luhn_append_check_digit`:

| Condition | Message |
|---|---|
| `body == ""` | `luhn: empty input` |
| a body byte outside `0-9` | `luhn: bad characters: <body>` |

No other error strings exist; there are no panics and no exceptions. Messages
are deterministic (no allocation-dependent text) and every failing input maps
to exactly one class by the orders above. `luhn_normalize` itself never
fails.

## Complexity

| Operation | Time | Space |
|---|---|---|
| `luhn_parse` / `luhn_is_valid` | O(len(s)) | O(1) |
| `luhn_normalize` | O(len(s)) | O(len) output |
| `luhn_parse_normalized` / `luhn_is_valid_normalized` | O(len(s)) | O(len) output |
| `luhn_compute_check_digit` | O(len(body)) | O(1) |
| `luhn_append_check_digit` | O(len(body)) | O(len) output |
| accessors | O(1) or O(len) for `luhn_body` | O(1) / O(len) output |

## Test plan

`tests/test_conformance.xi` (`module luhn_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Every valid fixture is a public arithmetic test
vector that was independently re-checked against a separate Luhn
implementation before being pinned; the fixtures are arithmetic samples, not
claims about any issuer's number assignment. Invalid fixtures are one-byte
mutations, so every error class is reachable in isolation.

1. strict parse and structure accessors for four fixtures
   (`79927398713`, `1234567812345670`, `4532015112830366`,
   `4111111111111111`);
2. strict parse of `378282246310005` / `3566002020360505` plus `is_valid` for
   all six fixtures;
3. `luhn_compute_check_digit` reproduces all six fixture check digits;
4. `luhn_append_check_digit` output parses for all six bodies;
5. small bodies: `0` -> 0, `1` -> 8, `9` -> 1, `89` -> 3, with round-trips;
6. minimum length policy: `00` and `18` accepted, `0` and `5` too short,
   empty input; `"0 0"` normalizes to a valid `00`;
7. `luhn_normalize` strips exactly space and hyphen, keeps every other byte;
8. normalized parse of hyphen, space and mixed grouped forms, canonical
   digits returned in `Ok`;
9. normalized parse rejects dots, slashes and underscores as
   `bad characters`;
10. normalized parser distinguishes raw empty, only separators and bad
    characters, with exact messages;
11. strict parse rejects raw separator forms that the normalized parser
    accepts (`is_valid` split);
12. non-digit bytes are bad characters, checked before length and check
    digit;
13. one-byte mutations of check digits and of a body digit are
    `bad check digit`;
14. `luhn_compute_check_digit` error catalog: empty and non-digit bodies;
15. `luhn_append_check_digit` propagates the compute errors and returns
    `body + check`, including check digit 0;
16. `is_valid` / `is_valid_normalized` truth table over every error class;
17. 1000-digit zero and nine bodies: `Int` safety, check digit 0 for the
    all-nines body, no length ceiling;
18. `luhn_normalize` -> parse equivalence for the published display forms.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.luhn
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Only the arithmetic check is modeled: a passing number is internally
  consistent, not issuer-approved or assignable; brand rules and scheme
  metadata are out of scope.
- Two separators only; any other display punctuation is `bad characters`.
- Minimum length 2; a one-digit input is never valid even though a single
  digit trivially "matches itself".
- No BigInt and no `Vec`: very large inputs are bounded by the platform's
  `Str`/`Int` limits, and the library is scalar-only.
- No display formatting helper: `luhn_normalize` is the documented way back
  from grouped text.
- Check digits detect transcription errors, not tampering or intent.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas or `Vec[fn]` dispatch; one public
  struct (`Luhn`), no `Vec[StructType]`; the test suite uses no `Vec` at all.
- `Ok`/`Err` are constructed only in leaf helpers (`_luhn_ok`, `_luhn_err`,
  `_int_ok`, `_int_err`, `_str_ok`, `_str_err`); `_parse_canonical` builds the
  struct first and then calls the matching leaf.
- All `Str` equality uses `xiom.string.compare.str_compare`; `==` is never
  applied to `Str`. The library module itself needs no string comparison.
- Every `UInt8` widening masks (`(b as Int) & 255`), per the BUG-17 /
  high-byte rules. All byte constants are below 128.
- No `xiom.string.builder` use: text is built by concatenating digit slices
  and validated text, so no NUL-byte abort path is reachable.
- The module declares no `extern "C"` blocks (no FFI) and imports only
  `xiom.string` and `xiom.convert`.
