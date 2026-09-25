# xiom.iban -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.iban`, version `0.1.0`).
Module: `src/iban.xi` (`module xiom.iban`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`);
no other dependencies.

## Scope

A pure-XIOM (no FFI) IBAN codec for a documented 19-country table:

- `iban_parse`: strict parse and full validation of the compact uppercase
  form `CCkkBBAN` (country code, check digits, BBAN, MOD-97-10);
- `iban_is_valid`: boolean shorthand for `iban_parse`;
- `iban_compact` / `iban_format`: canonical uppercase emit, plain and in
  space-separated groups of four;
- `iban_country` / `iban_check_digits` / `iban_bban`: accessors on a parsed
  value;
- `iban_length_for_country`: registered total length for a country code
  (`0` when unknown);
- `iban_compute_check_digits`: derive the two check digits for a country and
  BBAN.

## Non-goals

- Bank, branch, account-type or national sub-field semantics (positional
  structure inside the BBAN).
- SEPA rules, BIC, payment routing, or any bank directory lookup.
- The full IBAN registry: countries outside the table below are
  unknown-country errors, not accepted values.
- Lenient input normalization: lowercase text, embedded spaces or hyphens,
  and prefix/suffix padding are rejected rather than normalized.
- Arbitrary-precision arithmetic: MOD-97-10 is evaluated digit-wise, so no
  big-integer type is needed or exposed.

## Data model

```xiom
pub type Iban = {
  country: Str;   // exactly 2 ASCII uppercase letters, a table key
  check: Int;     // numeric value of the two check digits, 0..99
  bban: Str;      // uppercase BBAN exactly as parsed
}
```

`check` stores the numeric value; `iban_compact` and `iban_format` zero-pad
it back to exactly two digits. A valid IBAN always has `check` in `2..98`
(see the MOD-97 section).

## Input grammar (strict)

```
iban    := country check bban
country := UPPER UPPER                 ; must be a key of the country table
check   := DIGIT DIGIT
bban    := 11..24 chars                ; length fixed per country
UPPER   := "A".."Z"
DIGIT   := "0".."9"
ALNUM   := DIGIT / UPPER               ; BBAN charset fixed per country
```

No whitespace or separator is allowed anywhere, and no lowercase letter is
accepted (`case validation`). The byte length equals the character length
because only ASCII is admitted.

Validation order is fixed so every malformed input has exactly one
deterministic error:

1. empty input;
2. bytes 0 and 1 exist and are `A-Z`;
3. the two-letter code is in the country table;
4. total length equals the registered length;
5. bytes 2 and 3 are `0-9`;
6. every BBAN byte is in the country's class;
7. MOD-97-10 remainder of the rearranged string is 1.

## Country table

| Country | Total length | BBAN length | BBAN class |
|---|---|---|---|
| AT | 20 | 16 | numeric (`0-9`) |
| BE | 16 | 12 | numeric |
| CH | 21 | 17 | alphanumeric (`0-9A-Z`) |
| CZ | 24 | 20 | numeric |
| DE | 22 | 18 | numeric |
| DK | 18 | 14 | numeric |
| ES | 24 | 20 | numeric |
| FI | 18 | 14 | numeric |
| FR | 27 | 23 | alphanumeric |
| GB | 22 | 18 | alphanumeric |
| GR | 27 | 23 | alphanumeric |
| IE | 22 | 18 | alphanumeric |
| IT | 27 | 23 | alphanumeric |
| LU | 20 | 16 | alphanumeric |
| NL | 18 | 14 | alphanumeric |
| NO | 15 | 11 | numeric |
| PL | 28 | 24 | numeric |
| PT | 25 | 21 | numeric |
| SE | 24 | 20 | numeric |

The numeric-only set is exactly `{AT, BE, CZ, DE, DK, ES, FI, NO, PL, PT,
SE}`; every other table country accepts uppercase letters as well. The class
is a union over BBAN positions: positional structure (for example "GB sort
code positions must be digits") is a non-goal and is not enforced.

Any code not listed is `iban: unknown country: <CC>`;
`iban_length_for_country` returns `0` for it (including lowercase codes and
the empty string, which are simply not table keys).

## MOD-97-10

Definitions for a compact IBAN `CCkkBBAN`:

- **Rearrange** to `BBAN + CC + kk` (the first four characters move to the
  end, unchanged).
- **Expand** each character to its decimal value: digit `0`-`9` maps to
  `0`-`9`, letter `A`-`Z` maps to `10`-`35` (two decimal digits).
- **Evaluate** the expansion as one huge decimal number, MOD 97, digit by
  digit:

  ```
  r = 0
  for each character c of the rearranged string, v = value(c):
    if v < 10:  r = (r * 10 + v) mod 97
    else:       r = (r * 100 + v) mod 97
  ```

  Because `r < 97` before every step, `r * 100 + 35 <= 9635`: the running
  remainder is the only state and `Int` never overflows, regardless of the
  IBAN's 15..28 characters.

- **Validity**: `r == 1`.
- **Check-digit computation** (`iban_compute_check_digits`): with the check
  positions replaced by `00`, `r' = mod97(BBAN + CC + "00")` and the check
  value is `98 - r'`, always in `2..98`. `iban_compute_check_digits` returns
  that value; `iban_compact(iban_parse("CC" + twoDigit(check) + BBAN))`
  reproduces the input text.

Character values are only defined for validated input; callers must not
invoke `_mod97` on text outside the grammar (it is a private helper).

## API signatures

```xi
pub fn iban_parse(s: Str) -> Result[Iban, Str]
pub fn iban_is_valid(s: Str) -> Bool
pub fn iban_compact(v: &Iban) -> Str
pub fn iban_format(v: &Iban) -> Str
pub fn iban_country(v: &Iban) -> Str
pub fn iban_check_digits(v: &Iban) -> Int
pub fn iban_bban(v: &Iban) -> Str
pub fn iban_length_for_country(country: Str) -> Int
pub fn iban_compute_check_digits(country: Str, bban: Str) -> Result[Int, Str]
```

`iban_compute_check_digits` validates its arguments with the same rules as
`iban_parse` (country letters, membership, total length `bban.len() + 4`,
BBAN class) and returns the check value; the length error message therefore
reports the same total-length numbers as `iban_parse` would.

## Error catalog

`iban_parse`, in validation order:

| Condition | Message |
|---|---|
| `s == ""` | `iban: empty input` |
| `len(s) < 2`, or byte 0/1 not `A-Z` (lowercase and non-letters included) | `iban: bad characters: <s>` |
| bytes 0/1 a valid pair not in the table | `iban: unknown country: <CC>` |
| `len(s) != table[CC]` | `iban: bad length for <CC>: expected <n>, got <m>` |
| byte 2/3 not `0-9` | `iban: bad characters: <s>` |
| a BBAN byte outside the country's class | `iban: bad characters: <s>` |
| `mod97(BBAN + CC + kk) != 1` | `iban: bad check digits: <s>` |

`<s>` is the whole input exactly as passed. `iban_compute_check_digits`:

| Condition | Message |
|---|---|
| `country == ""` or `bban == ""` | `iban: empty input` |
| `country.len() != 2`, or a country byte not `A-Z` | `iban: bad characters: <country>` |
| country not in the table | `iban: unknown country: <CC>` |
| `bban.len() + 4 != table[CC]` | `iban: bad length for <CC>: expected <n>, got <m>` |
| a BBAN byte outside the country's class | `iban: bad characters: <bban>` |

No other error strings exist; there are no panics and no exceptions. Messages
are deterministic (no allocation-dependent text) and every failing input maps
to exactly one class by the order above.

## Complexity

| Operation | Time | Space |
|---|---|---|
| `iban_parse` | O(len(s)) | O(1) |
| `iban_is_valid` | O(len(s)) | O(1) |
| `iban_compact` / `iban_format` | O(len) | O(len) output |
| accessors | O(1) | O(1) |
| `iban_length_for_country` | O(1) | O(1) |
| `iban_compute_check_digits` | O(len(bban)) | O(1) |

The country table is compiled into comparison chains, not a runtime data
structure.

## Test plan

`tests/test_conformance.xi` (`module iban_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Every valid fixture is a published IBAN example
that was independently re-checked against a separate MOD-97-10
implementation before being pinned.

1. DE/GB/FR/NO fixtures parsed field by field (country, check, BBAN);
2. ES/IT/NL/BE/CH/AT/PT/IE fixtures parse `Ok`;
3. FI/SE/DK/PL/GR/CZ/LU fixtures parse `Ok` (all 19 table countries);
4. `iban_length_for_country` for all 19 codes, plus `ZZ`, `de`, `""` -> 0;
5. grouped formatting, including an exact multiple of four (PL) and short
   final groups (NO);
6. compact emit equals the fixture text;
7. hand-built struct: single-digit check values zero-pad in both emitters;
8. `iban_compute_check_digits` reproduces six fixtures' check digits;
9. compute+parse round-trips for letter-carrying alphanumeric BBANs
   (CH/GR/LU/NL/IT/IE), including field and compact equality;
10. single-digit check value `02` parses and formats;
11. all-nines BBANs (PL 24, CZ 20, DE 18 digits) stay Int-safe through
    compute and parse;
12. numeric-only countries reject a letter (DE/ES/BE) as `bad characters`;
13. lowercase country and lowercase BBAN letters are `bad characters`;
14. empty input, one-letter input, digit-led country, and short input;
15. unknown countries (ZZ, AA) are reported before length;
16. exact bad-length messages (21/23/20 bytes, plus spaced input);
17. malformed check digits and non-alphanumeric BBAN bytes;
18. MOD-97 mismatch -> `bad check digits` (four one-byte mutations);
19. `iban_compute_check_digits` error catalog (empty, bad country, unknown,
    length, charset);
20. `iban_is_valid` true for fixtures, false for one input per error class;
21. `iban_format` -> strip spaces -> canonical compact round-trip.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.iban
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- 19 documented countries; all other codes are unknown-country errors.
- No positional BBAN semantics: class and length only, so national schemes
  with digit-only positions inside an otherwise alphanumeric BBAN are not
  fully enforced.
- Strict compact uppercase input only; no normalization helpers.
- Check digits are a typo detector (1/97 residual for arbitrary mutations),
  not an authenticity or payment-routing mechanism.
- No SEPA, BIC, bank-directory or currency functionality.
- `iban_compute_check_digits` can return `98` (when the rearranged remainder
  is 0); such an IBAN is valid per the MOD-97 rule, and the emitters render
  it as `98`.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas or `Vec[fn]` dispatch; one public
  struct (`Iban`), no `Vec[StructType]`.
- `Ok`/`Err` are constructed only in leaf helpers (`_iban_ok`, `_iban_err`,
  `_int_ok`, `_int_err`); `iban_parse` and `iban_compute_check_digits`
  construct the struct/value first and then call the appropriate leaf.
- All `Str` equality uses `xiom.string.compare.str_compare`; `==` is never
  applied to `Str`.
- Every `UInt8` widening masks (`(b as Int) & 255`), per the BUG-17 /
  high-byte rules. All byte constants are below 128.
- No `xiom.string.builder` use: all text is built by concatenating slices of
  already-validated ASCII, so no NUL-byte abort path is reachable.
- The country-table functions are explicit `if` chains over string
  comparisons rather than module-level tables, which are mis-materialized by
  this compiler (see the `xiom.crc` and `xiom.compress.gzip` notes).
- The module declares no `extern "C"` blocks (no FFI) and imports only
  `xiom.string`, `xiom.string.compare`, and `xiom.convert`.
