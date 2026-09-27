# xiom.l10n.phone -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.l10n-phone`, version `0.1.0`).
Module: `src/l10n_phone.xi` (`module xiom.l10n.phone`; the manifest name
keeps the hyphen, the module cannot).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`,
`xiom.convert`); no other dependencies.

## Scope

A pure-XIOM (no FFI) structural codec for international-form phone numbers
over an embedded table of 200 ITU-T E.164 country calling codes:

- `phone_parse`: parse `+CC...`, `00CC...` (international dialling prefix)
  and bare `CC...` digit strings, strip separators, recognize extensions,
  validate structure, keep per-digit input offsets;
- `phone_parse_tel_uri`: parse RFC 3966 `tel:` URIs (literal `+` or the
  URI-encoded `%2B`, optional `;ext=`), with offsets into the URI text;
- `phone_is_valid`: boolean shorthand;
- `phone_e164` / `phone_international` / `phone_mask` / `phone_tel_uri`:
  emit canonical, grouped, masked and URI forms;
- `phone_country_code` / `phone_iso` / `phone_national` /
  `phone_extension` / `phone_raw_digits` / `phone_digit_count` /
  `phone_digit_offset`: accessors on a parsed value;
- `phone_equals`: canonical-digit equality (extension-independent);
- `phone_min_length` / `phone_iso_for_code` / `phone_country_count`:
  table lookups.

## Non-goals

- National-format parsing: a trunk prefix (leading `0`) is rejected, not
  normalized; `+44 (0)20 ...` fails on the `0`.
- Per-prefix dial-plan rules, number-type detection (mobile/fixed/VoIP),
  carrier selection, short codes, emergency numbers.
- Geocoding, phonebooks, line-type databases, CNAM.
- Full ITU coverage: ranges outside the embedded table (unassigned codes,
  non-geographic `8xx`/`87x`/`88x` services, satellite codes) are
  unknown-country errors.
- Floating point, allocation-heavy builders, FFI: none are used.

## Data model

```xiom
pub type CallingCode = {
  code: Str;     // E.164 calling code digits, "1".."998"
  iso: Str;      // ISO 3166-1 alpha-2 of the code's primary country
  min_len: Int;  // documented minimum national length (conservative floor)
}

pub type PhoneNumber = {
  country_code: Str;      // calling code digits, a table key
  iso: Str;               // ISO alpha-2, copied from the table
  national: Str;          // national significant digits, separators stripped
  extension: Str;         // extension digits, "" when absent
  digit_offsets: Vec[Int]; // input byte offset of each digit of country_code + national
}
```

Invariants of a value produced by `phone_parse` / `phone_parse_tel_uri`:

- `country_code.len()` is 1..3 and is a table key;
- `national` is non-empty, all digits, first digit non-zero, and
  `national.len() >= min_len(country_code)`;
- `country_code.len() + national.len() <= 15`;
- `digit_offsets.len() == country_code.len() + national.len()`; each entry
  is the input byte offset of the corresponding digit;
- `extension` is either `""` or a non-empty digit string (extension digits
  are not offset-mapped).

The `CallingCode` type is the table row type; the public table accessors
return its fields rather than the row.

## Input grammar (international form)

```
input        := "" | number
number       := prefix body
prefix       := "" | "+" | "00"        ; consumed; not part of the digits
body         := digit-stuff ext?
digit-stuff  := ( DIGIT | SEP )*
ext          := marker ext-stuff
marker       := "x" | "ext" | ";ext="  ; ASCII case-insensitive
ext-stuff    := ( DIGIT | SEP )* DIGIT ( DIGIT | SEP )*
DIGIT        := "0".."9"
SEP          := " " | "-" | "." | "(" | ")"
```

Rules:

- **Prefix** is optional. `+` (one byte) is consumed; `00` (two bytes) is
  consumed as the ITU international dialling prefix; otherwise the string is
  read as a bare E.164 digit string starting at byte 0. The prefix is never
  part of the collected digits.
- **Separators** are stripped anywhere in `digit-stuff` and in the extension
  (including leading/trailing positions); the digits keep their input byte
  offsets. Any other non-digit text (letters, `@`, `_`, `#`, `*`, `+`, ...)
  is an error with its byte offset.
- **Extension markers** are ASCII case-insensitive: `x` (one byte), `ext`
  (three bytes), `;ext=` (five bytes). After a marker, separators are
  skipped and at least one extension digit is required.
- **Extension digits** are collected with separators stripped and are not
  counted against the E.164 digit maximum and not offset-mapped.
- Only one extension is accepted; a second marker character is an
  unexpected-character error.
- The surface length can be arbitrary; only the digit structure is bounded
  (15 digits, see below).
- The input is expected to be ASCII. A non-ASCII byte is reported as an
  unexpected character (the message embeds the single input byte).

Grouping example (all equivalent):

```
"+442079460958"   "0044-20-7946-0958"   "44 20 7946 0958"
```

## Country-code resolution

After the scan, the collected digits `D` (country code + national, in input
order) are resolved by **longest match** on the leading bytes:

1. if `len(D) >= 3` and the first three digits are a table code, take them;
2. else if `len(D) >= 2` and the first two digits are a table code, take
   them;
3. else if the first digit is a table code (`1` or `7`), take it;
4. else it is an unknown country code.

The first 1..3 digits of `D` are also the digits echoed in the unknown-code
error. With the current table no code is a proper prefix of another code, so
the fallback arms are structural; the algorithm is defined this way for
future table growth.

## Validation order and rules

Deterministic order; each malformed input maps to exactly one error:

1. empty string -> `phone: empty input`;
2. during the scan, a 16th collected digit -> too-many-digits error
   (allowed total is exactly 1..15 digits, E.164's maximum of 15);
3. no collected digit at all -> empty national number;
4. the leading digits must resolve to a table code;
5. a matched code with no following digit -> empty national number;
6. first digit of the national number must not be `0`;
7. `national.len()` must be `>= min_len` of the table row;
8. a marker with no extension digit -> empty extension.

Rule 6 is a structural rule: international form drops the national trunk
prefix, so an international significant number never starts with `0`. The
documented exception is Italy (`+39 06 ...` keeps a leading `0` in the
significant number); such numbers are rejected by this rule (see Known
limitations).

## Embedded table

200 rows: 2 one-digit codes, 44 two-digit codes, 154 three-digit codes.
`min` is the documented conservative minimum national significant number
length; the default `4` is used where the plan minimum could not be
confidently pinned (mostly small states and island territories), and rows
with a well-known floor carry it explicitly. The values are structural
floors, not dial-plan data.

### One-digit codes

| Code | ISO | Min |
|---|---|---|
| 1 | US | 10 |
| 7 | RU | 10 |

`1` is the NANP code shared by the US, Canada and Caribbean territories;
the table names its primary country US. `7` is shared by Russia and
Kazakhstan; the table names RU.

### Two-digit codes

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 20 | EG | 9 | 27 | ZA | 9 | 30 | GR | 10 |
| 31 | NL | 9 | 32 | BE | 8 | 33 | FR | 9 |
| 34 | ES | 9 | 36 | HU | 9 | 39 | IT | 9 |
| 40 | RO | 9 | 41 | CH | 9 | 43 | AT | 10 |
| 44 | GB | 10 | 45 | DK | 8 | 46 | SE | 7 |
| 47 | NO | 8 | 48 | PL | 9 | 49 | DE | 9 |
| 51 | PE | 8 | 52 | MX | 10 | 53 | CU | 8 |
| 54 | AR | 10 | 55 | BR | 10 | 56 | CL | 9 |
| 57 | CO | 10 | 58 | VE | 10 | 60 | MY | 9 |
| 61 | AU | 9 | 62 | ID | 9 | 63 | PH | 10 |
| 64 | NZ | 8 | 65 | SG | 8 | 66 | TH | 9 |
| 81 | JP | 9 | 82 | KR | 9 | 84 | VN | 9 |
| 86 | CN | 9 | 90 | TR | 10 | 91 | IN | 10 |
| 92 | PK | 10 | 93 | AF | 9 | 94 | LK | 9 |
| 95 | MM | 8 | 98 | IR | 10 | | | |

### 2xx -- Africa

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 211 | SS | 9 | 212 | MA | 9 | 213 | DZ | 9 |
| 216 | TN | 8 | 218 | LY | 9 | 220 | GM | 7 |
| 221 | SN | 9 | 222 | MR | 8 | 223 | ML | 8 |
| 224 | GN | 9 | 225 | CI | 8 | 226 | BF | 8 |
| 227 | NE | 8 | 228 | TG | 8 | 229 | BJ | 8 |
| 230 | MU | 7 | 231 | LR | 8 | 232 | SL | 8 |
| 233 | GH | 9 | 234 | NG | 10 | 235 | TD | 8 |
| 236 | CF | 8 | 237 | CM | 9 | 238 | CV | 7 |
| 239 | ST | 7 | 240 | GQ | 9 | 241 | GA | 8 |
| 242 | CG | 9 | 243 | CD | 9 | 244 | AO | 9 |
| 245 | GW | 7 | 246 | IO | 4 | 248 | SC | 7 |
| 249 | SD | 9 | 250 | RW | 9 | 251 | ET | 9 |
| 252 | SO | 8 | 253 | DJ | 8 | 254 | KE | 9 |
| 255 | TZ | 9 | 256 | UG | 9 | 257 | BI | 8 |
| 258 | MZ | 9 | 260 | ZM | 9 | 261 | MG | 9 |
| 262 | RE | 9 | 263 | ZW | 9 | 264 | NA | 9 |
| 265 | MW | 9 | 266 | LS | 8 | 267 | BW | 8 |
| 268 | SZ | 8 | 269 | KM | 7 | 290 | SH | 4 |
| 291 | ER | 7 | 297 | AW | 7 | 298 | FO | 6 |
| 299 | GL | 6 | | | | | | |

### 3xx -- Europe extras

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 350 | GI | 8 | 351 | PT | 9 | 352 | LU | 8 |
| 353 | IE | 9 | 354 | IS | 7 | 355 | AL | 9 |
| 356 | MT | 8 | 357 | CY | 8 | 358 | FI | 9 |
| 359 | BG | 9 | 370 | LT | 8 | 371 | LV | 8 |
| 372 | EE | 7 | 373 | MD | 8 | 374 | AM | 8 |
| 375 | BY | 9 | 376 | AD | 6 | 377 | MC | 8 |
| 378 | SM | 9 | 379 | VA | 8 | 380 | UA | 9 |
| 381 | RS | 9 | 382 | ME | 8 | 385 | HR | 8 |
| 386 | SI | 8 | 387 | BA | 8 | 389 | MK | 8 |

### 4xx -- Europe extras

| Code | ISO | Min |
|---|---|---|
| 420 | CZ | 9 |
| 421 | SK | 9 |
| 423 | LI | 7 |

### 5xx -- Central America and South America

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 501 | BZ | 7 | 502 | GT | 8 | 503 | SV | 8 |
| 504 | HN | 8 | 505 | NI | 8 | 506 | CR | 8 |
| 507 | PA | 7 | 508 | PM | 6 | 509 | HT | 8 |
| 591 | BO | 8 | 592 | GY | 7 | 593 | EC | 9 |
| 594 | GF | 9 | 595 | PY | 9 | 596 | MQ | 9 |
| 597 | SR | 7 | 598 | UY | 8 | | | |

### 6xx -- Asia / Pacific

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 673 | BN | 7 | 674 | NR | 7 | 675 | PG | 8 |
| 676 | TO | 5 | 677 | SB | 5 | 678 | VU | 5 |
| 679 | FJ | 7 | 680 | PW | 7 | 681 | WF | 6 |
| 682 | CK | 5 | 683 | NU | 4 | 685 | WS | 5 |
| 686 | KI | 5 | 687 | NC | 6 | 688 | TV | 5 |
| 689 | PF | 8 | 690 | TK | 4 | 691 | FM | 7 |
| 692 | MH | 7 | | | | | | |

### 8xx -- East / Southeast Asia

| Code | ISO | Min |
|---|---|---|
| 850 | KP | 9 |
| 852 | HK | 8 |
| 853 | MO | 8 |
| 855 | KH | 8 |
| 856 | LA | 8 |
| 880 | BD | 10 |
| 886 | TW | 9 |

### 9xx -- Middle East / Central Asia

| Code | ISO | Min | Code | ISO | Min | Code | ISO | Min |
|---|---|---|---|---|---|---|---|---|
| 960 | MV | 7 | 961 | LB | 7 | 962 | JO | 9 |
| 963 | SY | 9 | 964 | IQ | 10 | 965 | KW | 8 |
| 966 | SA | 9 | 967 | YE | 9 | 968 | OM | 8 |
| 970 | PS | 9 | 971 | AE | 9 | 972 | IL | 9 |
| 973 | BH | 8 | 974 | QA | 8 | 975 | BT | 8 |
| 976 | MN | 8 | 977 | NP | 9 | 992 | TJ | 9 |
| 993 | TM | 8 | 994 | AZ | 9 | 995 | GE | 9 |
| 996 | KG | 9 | 998 | UZ | 9 | | | |

The table is compiled into comparison chains (`_code1`, `_code2`,
`_code3_*`) because module-level table initializers are mis-materialized by
v0.61.3.

## Formatting

- **E.164** (`phone_e164`): `"+" + country_code + national`. The extension
  is not part of E.164 and is omitted. Parsing `phone_e164(v)` reproduces
  the same canonical digits.
- **Grouped international** (`phone_international`): `"+" + country_code +
  " " + group3(national)`, where `group3` inserts a space every three digits
  counted from the right (the leftmost group holds 1..3 digits). A parsed
  extension is appended as `" x" + extension`. This is a generic grouping,
  not the national convention of the country.
- **Masked** (`phone_mask`): `"+" + country_code + "*" * (n - 4) +
  last4(national)` when `n > 4`; when `n <= 4` all `n` national digits are
  masked. The country code is never masked.
- **tel URI** (`phone_tel_uri`): `"tel:+" + country_code + national`, plus
  `";ext=" + extension` when an extension is present. The literal `+` is
  emitted; `%2B` is accepted on parse but never produced.

## API signatures

```xi
pub fn phone_parse(s: Str) -> Result[PhoneNumber, Str]
pub fn phone_parse_tel_uri(s: Str) -> Result[PhoneNumber, Str]
pub fn phone_is_valid(s: Str) -> Bool
pub fn phone_e164(v: &PhoneNumber) -> Str
pub fn phone_international(v: &PhoneNumber) -> Str
pub fn phone_mask(v: &PhoneNumber) -> Str
pub fn phone_tel_uri(v: &PhoneNumber) -> Str
pub fn phone_country_code(v: &PhoneNumber) -> Str
pub fn phone_iso(v: &PhoneNumber) -> Str
pub fn phone_national(v: &PhoneNumber) -> Str
pub fn phone_extension(v: &PhoneNumber) -> Str
pub fn phone_raw_digits(v: &PhoneNumber) -> Str
pub fn phone_digit_count(v: &PhoneNumber) -> Int
pub fn phone_digit_offset(v: &PhoneNumber, i: Int) -> Int
pub fn phone_equals(a: &PhoneNumber, b: &PhoneNumber) -> Bool
pub fn phone_min_length(country_code: Str) -> Int
pub fn phone_iso_for_code(country_code: Str) -> Str
pub fn phone_country_count() -> Int
```

## Error catalog

All messages start with `phone: ` and are deterministic. Except for
`phone: empty input` (there is no byte to point at) every message carries
the byte offset of the offending input byte. `<c>` is the single input byte
at that offset, `<p>` the first `min(3, len(D))` digits of `D`, `<ISO>` the
table ISO code, and `start` the byte offset where the digits begin (the
length of the consumed prefix).

`phone_parse`:

| # | Condition | Message |
|---|---|---|
| 1 | `s == ""` | `phone: empty input` |
| 2 | a 16th collected digit at byte `i` | `phone: more than 15 digits (E.164 max) at offset <i>` |
| 3 | no collected digit (end reached) | `phone: empty national number at offset <start>` |
| 4 | leading digits match no table code | `phone: unknown country code '<p>' at offset <start>` |
| 5 | matched code, no national digit | `phone: empty national number at offset <i>` (i = offset after the last country-code digit) |
| 6 | first national digit is `0` | `phone: national number starts with zero at offset <i>` |
| 7 | `national.len() < min_len` | `phone: national number too short for <ISO>: <n> digits, minimum <m> at offset <i>` |
| 8 | marker present, no extension digit | `phone: empty extension at offset <i>` (i = first byte of the marker) |
| 9 | byte is not a digit/separator/marker | `phone: unexpected character '<c>' at offset <i>` |

`phone_parse_tel_uri` adds, before the body rules:

| # | Condition | Message |
|---|---|---|
| 10 | `len(s) < 4` or first four bytes not `tel:` (case-insensitive) | `phone: not a tel URI at offset 0` |
| 11 | after `tel:` neither `+` nor `%2B` (hex case-insensitive) | `phone: tel URI missing '+' or '%2B' at offset 4` |

Rule 9 also covers a malformed marker (`;` not followed by `ext=`, `e` not
starting `ext`). Rules 2..9 report offsets into the original `phone_parse`
input or, for `phone_parse_tel_uri`, into the URI text (the `%2B` form is
scanned in place, so the offsets stay URI-absolute).

## Complexity

| Operation | Time | Space |
|---|---|---|
| `phone_parse` | O(len(s)) | O(len(s)) output + offsets |
| `phone_parse_tel_uri` | O(len(s)) | O(len(s)) |
| `phone_is_valid` | O(len(s)) | O(len(s)) |
| `phone_e164` / `phone_international` / `phone_mask` / `phone_tel_uri` | O(len) | O(len) output |
| accessors | O(1) except `phone_digit_offset` O(1) | O(1) |
| `phone_min_length` / `phone_iso_for_code` | O(1) | O(1) |
| `phone_country_count` | O(1) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module l10n_phone_tests`, 23 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). All fixtures are synthetic strings built
in-test.

1. 1-digit codes (`1`, `7`) in `+`/`00`/bare shapes with field and E.164
   checks;
2. 2-digit codes (GB/DE/FR/JP/CN/SG) field checks;
3. 3-digit codes (MA/PT/UZ/FJ/LI) field checks;
4. separators stripped, digit offsets preserved (mixed `( )`, `-`, `.`,
   spaces), out-of-range offset `-1`;
5. exactly-15-digit acceptance (1-digit and 2-digit codes, spaced form);
6. 16th digit rejected with the exact offset (`+`, `00` shapes);
7. extension markers `x`, `ext`, `;ext=`, uppercase forms, extension
   excluded from E.164, rendered by URI and grouped forms;
8. `tel:` build/parse, `;ext=` round-trip, `%2B` and `TEL:` forms,
   URI-absolute offsets;
9. `tel:` error catalog (not-a-URI, missing `+`/`%2B`, empty extension,
   body errors with URI offsets);
10. grouped international (`+CC NNN NNN NNN`) and masked forms, including
    a <= 4-digit national number;
11. accessors and `phone_digit_offset` bounds (`-1`);
12. canonical-digit equality across surface forms, extension-independent,
    differences detected;
13. table minimum lookups including default-4 rows and unknown codes -> 0;
14. ISO lookups (parsed and by code), unknown -> `""`;
15. national shorter than the table minimum (GB/US/PT/TK) exact messages;
16. national starting with zero (GB/US/IT style) exact messages;
17. unknown country codes (`999`, `023`, `0`, `012`) and NANP `+1242...`
    resolving to code `1`;
18. malformed characters (`@`, second `+`, `g`, `#`, `_`) exact offsets;
19. empty forms (`""`, `+`, `00`, `+44`, `+44x5`, `+44 ( )`, `+44x`);
20. `phone_is_valid` true/false across every error class;
21. parse -> E.164 -> parse round-trip for seven fixtures;
22. table size (200 rows, `>= 80`) and a hand-built value through all
    emitters with an empty offset vector;
23. equality of hand-built values (extension-independent) plus extension
    rendering.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.l10n-phone
```

Last verified: compiler 0.61.3,
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Known limitations

- 200 table rows; all other codes (including non-geographic `8xx`
  services) are unknown-country errors.
- Minimum national lengths are conservative structural floors. Rows whose
  plan minimum could not be confidently pinned carry the documented default
  `4`; the values are not dial-plan data and do not detect invalid prefixes
  inside a plausible-length number.
- The leading-zero rejection is structural: Italy-style numbers whose
  significant number begins with `0` (`+39 06 ...`) are rejected. There is
  no per-country exception mechanism.
- Grouped international output uses one generic grouping (threes from the
  right); it is not locale-aware.
- Extensions are digit-only, unlimited in length, and not offset-mapped.
- The bare (prefix-less) form assumes the leading digits are the calling
  code; national-format input is out of scope.
- `1` is labelled US and `7` RU (primary countries of shared codes).

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas or `Vec[fn]` dispatch; two public
  structs; no `Vec[StructType]`.
- `Ok`/`Err` are constructed only in the leaf helpers `_pn_ok` / `_pn_err`.
- All `Str` equality uses `xiom.string.compare.str_compare`; `==` is never
  applied to `Str`.
- `Vec[Int]` element reads are bound to typed locals; the parallel
  `digit_offsets` vector is pushed in the same branch that appends the
  digit (trap 16 discipline).
- All `UInt8` constants are ASCII (< 128), so no widening/masking path is
  reachable; every byte comparison is against a below-128 constant.
- The table is compiled into comparison chains, not a module-level table
  (module-level table initializers are mis-materialized by v0.61.3).
- No `xiom.string.builder` use: all text is built from validated ASCII
  slices, so no NUL-byte abort path is reachable.
- The module declares no `extern "C"` blocks (no FFI) and imports only
  `xiom.string`, `xiom.string.compare`, and `xiom.convert`.
