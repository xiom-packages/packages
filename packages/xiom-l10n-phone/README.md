# xiom.l10n.phone

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.2` on the XIOM registry.
> **Scope:** E.164 / international phone-number structures over an embedded
> country calling-code subset: parse, validate, format, mask, RFC 3966
> `tel:` URI build/parse.
> **Deps:** `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`);
> tests additionally use `xiom.io` and `xiom.test`.

## What it is

`xiom.l10n.phone` is a pure-XIOM (no FFI, no allocation-heavy builders)
structural codec for **international-form** phone numbers. It embeds a table
of **200 ITU-T E.164 country calling codes** (1..998) with the ISO 3166-1
alpha-2 code and a documented minimum national significant number length per
country, and it works entirely on digit structure:

- parses `+CC...`, `00CC...` (international dialling prefix) and bare
  `CC...` digit strings;
- strips separators (space, hyphen, dot, parentheses) while keeping the
  input byte offset of every digit;
- recognizes extensions after `x`, `ext` and `;ext=`;
- enforces the E.164 15-digit maximum and the per-country minimum national
  length;
- emits E.164, grouped-international, masked and `tel:` URI forms;
- reports every validation failure with the byte offset of the offending
  input byte.

The package manifest is `xiom.l10n-phone`; the compiler module is
`xiom.l10n.phone` (v0.61.3 rejects `-` in `module` declarations), matching
the `xiom.l10n.currency` naming note.

## What it is not

- Not a dial-plan validator: no per-prefix rules, no number-type detection
  (mobile/fixed/VoIP), no carrier data.
- Not a national-format parser: a leading trunk `0` is rejected, not
  normalized (`+44 (0)20 ...` fails on the `0`).
- Not a phonebook: no names, no geocoding, no short codes.
- Not full ITU coverage: 200 codes; unassigned/non-geographic ranges
  (`8xx` freephone, `87x` Inmarsat, etc.) and codes outside the table are
  unknown-country errors.

## API

| Function | Returns | Description |
|---|---|---|
| `phone_parse(s)` | `Result[PhoneNumber, Str]` | Parse `+`/`00`/bare international form. |
| `phone_parse_tel_uri(s)` | `Result[PhoneNumber, Str]` | Parse an RFC 3966 `tel:` URI (`+` or `%2B`). |
| `phone_is_valid(s)` | `Bool` | Boolean shorthand for `phone_parse`. |
| `phone_e164(v)` | `Str` | `+CCNNN...`; extension omitted (E.164 has none). |
| `phone_international(v)` | `Str` | `+CC NNN NNN NNN` (threes from the right) plus ` x<ext>`. |
| `phone_mask(v)` | `Str` | `+CC********NNNN`; <= 4 national digits are fully masked. |
| `phone_tel_uri(v)` | `Str` | `tel:+...;ext=...` when an extension is present. |
| `phone_country_code(v)` | `Str` | Calling code digits. |
| `phone_iso(v)` | `Str` | ISO 3166-1 alpha-2 of the primary country. |
| `phone_national(v)` | `Str` | National significant digits, separators stripped. |
| `phone_extension(v)` | `Str` | Extension digits (`""` when absent). |
| `phone_raw_digits(v)` | `Str` | Canonical digits: country code + national. |
| `phone_digit_count(v)` | `Int` | Length of `phone_raw_digits`. |
| `phone_digit_offset(v, i)` | `Int` | Input byte offset of the i-th digit, or `-1`. |
| `phone_equals(a, b)` | `Bool` | Equal canonical digits (extension-independent). |
| `phone_min_length(cc)` | `Int` | Table minimum national length, `0` when unknown. |
| `phone_iso_for_code(cc)` | `Str` | ISO alpha-2 for a code, `""` when unknown. |
| `phone_country_count()` | `Int` | Table row count (200). |

## Usage

```xi
use xiom.io;
use xiom.convert;
use xiom.l10n.phone;

fn main() -> Int {
  match phone_parse("+1 (202) 555-0147 x89") {
    Ok(v) => {
      io.println(phone_e164(&v));           // +12025550147
      io.println(phone_international(&v));  // +1 2 025 550 147 x89
      io.println(phone_mask(&v));           // +1******0147
      io.println(phone_tel_uri(&v));        // tel:+12025550147;ext=89
      io.println(phone_iso(&v));            // US
      io.println(int_to_string(phone_digit_offset(&v, 0))); // 1
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Accepted surface forms for the same number:

```xi
"+442079460958"  "0044-20-7946-0958"  "44 20 7946 0958"
"tel:+442079460958"  "tel:%2B442079460958"
```

## Error handling

Errors are deterministic `Str` messages prefixed with `phone:` and (except
for `phone: empty input`) carry a byte offset into the input. Examples:

```
phone: unknown country code '999' at offset 1
phone: national number too short for GB: 7 digits, minimum 10 at offset 3
phone: national number starts with zero at offset 4
phone: more than 15 digits (E.164 max) at offset 16
phone: unexpected character '@' at offset 3
phone: not a tel URI at offset 0
```

The full catalog is in [SPEC.md](SPEC.md).

## Tests

```
& .\scripts\port.ps1 -Package xiom.l10n-phone
```

Expected tail: `port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

The suite builds every fixture in-test (1/2/3-digit country codes,
separators, offsets, extensions, `tel:` URIs, the 15/16-digit boundary,
unknown codes, malformed text, empty forms) and never uses a `Vec[fn]`
dispatch table.

## Install / publish

```
xiom pkg install xiom.l10n-phone@0.1.0   # consumer
xiom pkg publish                         # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Known caveats

- The per-country minimum national lengths are conservative structural
  floors, not dial-plan data: rows whose plan minimum could not be pinned
  carry the documented default `4` (see SPEC.md).
- Italy-style national numbers whose significant number starts with `0`
  (`+39 06 ...`) are rejected by the documented "first digit non-zero"
  structural rule.
- Grouped international output is the generic 3-from-the-right grouping,
  not the national convention of the country (e.g. NANP numbers are not
  grouped as `NXX NXX-XXXX`).
- Offsets cover country code + national digits only; extension digits are
  not offset-mapped.
- Input is expected to be ASCII; non-ASCII bytes are reported as
  unexpected characters.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
