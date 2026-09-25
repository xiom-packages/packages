# xiom.iban

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness on compiler v0.61.3 (21/21). NOT published yet.
> **Scope:** strict IBAN parsing, validation, canonical formatting, and
> MOD-97 check-digit computation for a documented 19-country table.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`).

## What it is

`xiom.iban` validates International Bank Account Numbers in the compact
uppercase form `CCkkBBAN`:

- country code: two ASCII uppercase letters present in the documented table
  (unknown codes are an error);
- total length: exactly the country's registered IBAN length (15..28);
- check digits: two ASCII digits, verified with the ISO 7064 MOD-97-10
  check (remainder 1 after the standard rearrangement);
- BBAN: the country's documented character class -- digits only for the
  numeric-only countries, digits and uppercase letters otherwise.

The MOD-97-10 remainder is evaluated digit-wise, so a 28-digit IBAN never
needs an arbitrary-length integer and `Int` cannot overflow. Formatting emits
the canonical uppercase form split into space-separated groups of four, and
`iban_compute_check_digits` derives the check digits for a country and BBAN
(useful for generation and round-trip verification).

Out of scope by design: bank/branch/account semantics, national sub-field
structure, SEPA rules and BIC.

## Install / use

```
xiom pkg install xiom.iban@0.1.0
```

```xi
use xiom.iban;
use xiom.io;

match iban_parse("DE89370400440532013000") {
  Ok(v) => {
    io.println(iban_format(&v));    // "DE89 3704 0044 0532 0130 00"
    io.println(iban_country(&v));   // "DE"
    io.println(iban_bban(&v));      // "370400440532013000"
  },
  Err(e) => {
    io.println(e);                  // "iban: bad check digits: ..."
  },
}
```

## API

All functions are free functions in module `xiom.iban`:

| Function | Returns | Description |
|---|---|---|
| `iban_parse(s)` | `Result[Iban, Str]` | Strict parse + full validation of compact uppercase text; `Err` catalog below. |
| `iban_is_valid(s)` | `Bool` | `true` iff `iban_parse` accepts `s`; every error collapses to `false`. |
| `iban_compact(v)` | `Str` | Canonical `"CCkkBBAN"`, uppercase, no separators. |
| `iban_format(v)` | `Str` | Canonical grouped text, e.g. `"DE89 3704 0044 0532 0130 00"`; final group may be short. |
| `iban_country(v)` | `Str` | Two-letter country code of a parsed IBAN. |
| `iban_check_digits(v)` | `Int` | Numeric value of the two check digits, `0..99`. |
| `iban_bban(v)` | `Str` | BBAN of a parsed IBAN, as written (uppercase). |
| `iban_length_for_country(country)` | `Int` | Registered total length for a table country, `0` when unknown. |
| `iban_compute_check_digits(country, bban)` | `Result[Int, Str]` | Check-digit value `2..98` for a country and BBAN; same validation classes as `iban_parse`. |

```xi
pub type Iban = { country: Str; check: Int; bban: Str; }
```

## Country table

| Country | Total length | BBAN length | BBAN class |
|---|---|---|---|
| AT | 20 | 16 | numeric |
| BE | 16 | 12 | numeric |
| CH | 21 | 17 | alphanumeric |
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

"Alphanumeric" means uppercase letters or digits at any BBAN position; the
table intentionally does not encode national sub-field boundaries (that is
bank/branch semantics, a non-goal). Any other country code is
`iban: unknown country: <CC>`.

## Error model

`iban_parse` reports the first failing check, in this order:

| Condition | Message |
|---|---|
| `s == ""` | `iban: empty input` |
| fewer than 2 bytes, or bytes 0/1 not ASCII `A-Z` | `iban: bad characters: <s>` |
| country not in the table | `iban: unknown country: <CC>` |
| `len(s)` != registered length | `iban: bad length for <CC>: expected <n>, got <m>` |
| bytes 2/3 not ASCII digits | `iban: bad characters: <s>` |
| a BBAN byte outside the country's class | `iban: bad characters: <s>` |
| MOD-97-10 remainder != 1 | `iban: bad check digits: <s>` |

`iban_compute_check_digits` uses the same classes: `iban: empty input` for an
empty country or BBAN, `iban: bad characters: <country>` for a malformed
country, `iban: unknown country: <CC>`, `iban: bad length for <CC>: expected
<n>, got <m>` (total length, i.e. `bban.len() + 4`), and
`iban: bad characters: <bban>` for a disallowed BBAN byte.

Input is strict: lowercase letters, embedded separators, and padded input are
rejected (`bad characters` or `bad length`). The grouped output of
`iban_format` is display text; strip the spaces before feeding it back to
`iban_parse`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.iban
```

Expected: 21 `[PASS]` lines and
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

Coverage: all 19 published fixtures parsed field by field; the length table
(19 codes plus unknown/lowercase/empty); grouped formatting, including an
exact multiple of four and a short final group; compact round-trips;
zero-padding of a single-digit check value; check-digit computation against
six published fixtures; compute+parse round-trips for letter-carrying
alphanumeric BBANs and all-nines stress BBANs; numeric-only charset
enforcement; case rejection; and exact messages for every error class
(empty, short, unknown country, bad length, bad characters, bad check
digits). See `SPEC.md` for the formal contract.

## Limitations

- **Documented 19-country subset.** Every other ISO country code is an
  unknown-country error, even if its IBAN would be valid under the full
  registry.
- **Class-level BBAN validation.** No positional semantics: a BBAN is
  accepted when its length, charset and MOD-97 all hold, so a national
  scheme that demands digits at a specific position (for example the GB sort
  code) is not enforced beyond the class.
- **Strict uppercase compact input.** No automatic uppercasing or space
  stripping during parse; callers normalize first.
- **No bank, branch, account-type, SEPA or BIC functionality.** Check digits
  catch typos, not fraud: any 4-character mutation survives with
  probability 1/97.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
