# xiom.geography -- Specification

Version: 0.1.0 (`incubating`; implemented, harness-green with compiler
v0.61.3, not published).
Manifest: `package.xi` (`xiom.geography`, version `0.1.0`).
Module: `src/geography.xi` (`module xiom.geography`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`);
no other dependencies, no FFI.

## Name mapping

The manifest name and the importable module name are identical:
`xiom.geography`. The manifest `modules` field lists it.

## Scope

A pure-XIOM geography data and text codec core:

- embedded ISO 3166-1 table for all 249 officially assigned alpha-2 codes
  with alpha-3, zero-padded numeric, ISO English short name and UN M49
  continent / region codes;
- lookups by alpha-2 / alpha-3 (ASCII case-insensitive) and numeric (short
  forms zero-padded), validation predicates and reverse accessors;
- embedded UN M49 region table (30 codes) with parent links, used by the
  country rows;
- ISO 3166-2 subdivision code syntax (`CC-SUB`) parse/format, raw preserving,
  without a per-country subdivision list;
- decimal-degree and DMS text parse into scaled integer micro-degrees, with
  canonical renderers and axis range predicates.

## Non-goals

- The full ISO 3166-2 per-country subdivision list (thousands of rows,
  several amendments a year).
- User-assigned, reserved or transitional ISO 3166-1 codes; historical codes.
- Map projections, map tiles, terrain, distance/geodesic math, geohashing.
- Localized country names, CLDR data or name transliteration.
- Floating-point coordinates (the module never exposes a Float64 value).

## Data model

```xiom
pub type Country = {
  alpha2: Str;     // exactly 2 ASCII letters, uppercase in the table
  alpha3: Str;     // exactly 3 ASCII letters, uppercase in the table
  numeric: Str;    // exactly 3 ASCII digits, zero padded ("008")
  name: Str;       // ISO English short name, ASCII or UTF-8 diacritics
  continent: Str;  // UN M49 top-level code: 002, 009, 010, 019, 142, 150
  region: Str;     // finest embedded M49 code (one of the 30 rows below)
}

pub type Region = {
  code: Str;       // exactly 3 ASCII digits, zero padded
  name: Str;       // UN English name
  parent: Str;     // next coarser region code; "" for top-level regions
}

pub type Subdivision = {
  country: Str;    // canonical uppercase alpha-2 part
  part: Str;       // canonical uppercase subdivision part (1..3 alnum)
  raw: Str;        // the input text verbatim
}
```

Coordinates are not a type: they are signed integer micro-degrees
(1 micro-degree = 1e-6 degree), axis selected by a `Bool` parameter.

## Table summary

### Country rows

249 rows, in ascending alpha-2 order. Source: the ISO 3166-1 officially
assigned code list (alpha-2, alpha-3, numeric, English short name) with the
UN M49 grouping per country. Counts asserted by the integrity test:

| continent | code | country rows | regions used |
|---|---|---|---|
| Africa | 002 | 60 | 011, 014, 015, 017, 018 |
| Americas | 019 | 57 | 005, 013, 021, 029 |
| Asia | 142 | 51 | 030, 034, 035, 143, 145 |
| Europe | 150 | 51 | 039, 151, 154, 155 |
| Oceania | 009 | 29 | 053, 054, 057, 061 |
| Antarctica | 010 | 1 | 010 |
| total | | 249 | |

Country rows per finest region (rows with an ancestor-only code -- 002, 009,
019, 142, 150, 202, 419 -- do not occur):

| region | rows | | region | rows | | region | rows |
|---|---|---|---|---|---|---|---|
| 005 South America | 16 | | 034 Southern Asia | 9 | | 054 Melanesia | 5 |
| 010 Antarctica | 1 | | 035 South-Eastern Asia | 11 | | 057 Micronesia | 8 |
| 011 Western Africa | 17 | | 039 Southern Europe | 16 | | 061 Polynesia | 10 |
| 013 Central America | 8 | | 053 Australia and New Zealand | 6 | | 143 Central Asia | 5 |
| 014 Eastern Africa | 22 | | 145 Western Asia | 18 | | 151 Eastern Europe | 10 |
| 015 Northern Africa | 7 | | 154 Northern Europe | 16 | | 155 Western Europe | 9 |
| 017 Middle Africa | 9 | | 018 Southern Africa | 5 | | 021 Northern America | 5 |
| 029 Caribbean | 28 | | 030 Eastern Asia | 8 | | | |

Size note: one-line `if` chains for 249 rows are compiled by `_bank_a` ..
`_bank_e` (50/50/50/50/49 rows) behind `_country(i)`; module-level table
initializers are mis-materialized by XIOM v0.61.3 (documented workaround,
same shape as `xiom.l10n-currency` and `xiom.iban`).

### Region rows (30, ascending code)

| code | name | parent | | code | name | parent |
|---|---|---|---|---|---|---|
| 002 | Africa | "" | | 039 | Southern Europe | 150 |
| 005 | South America | 019 | | 053 | Australia and New Zealand | 009 |
| 009 | Oceania | "" | | 054 | Melanesia | 009 |
| 010 | Antarctica | "" | | 057 | Micronesia | 009 |
| 011 | Western Africa | 202 | | 061 | Polynesia | 009 |
| 013 | Central America | 019 | | 142 | Asia | "" |
| 014 | Eastern Africa | 202 | | 143 | Central Asia | 142 |
| 015 | Northern Africa | 002 | | 145 | Western Asia | 142 |
| 017 | Middle Africa | 202 | | 150 | Europe | "" |
| 018 | Southern Africa | 202 | | 151 | Eastern Europe | 150 |
| 019 | Americas | "" | | 154 | Northern Europe | 150 |
| 021 | Northern America | 019 | | 155 | Western Europe | 150 |
| 029 | Caribbean | 019 | | 202 | Sub-Saharan Africa | 002 |
| 030 | Eastern Asia | 142 | | 419 | Latin America and the Caribbean | 019 |
| 034 | Southern Asia | 142 | | | | |
| 035 | South-Eastern Asia | 142 | | | | |

`010 Antarctica` is included (it is a UN M49 top-level region and the scope
groups the country table under it) so that the AQ country row's `continent`
and `region` both resolve. Chains are at most three deep: subregion ->
202/419 -> top.

## Lookup semantics

| Function | Input rule | Success | Failure |
|---|---|---|---|
| `by_alpha2` | exactly 2 ASCII letters, any case | row | `bad alpha-2 code: <code>` / `unknown country code: <code>` |
| `by_alpha3` | exactly 3 ASCII letters, any case | row | `bad alpha-3 code: <code>` / `unknown country code: <code>` |
| `by_numeric` | 1..3 ASCII digits, left-zero-padded | first row with that numeric | `bad numeric code: <code>` / `unknown numeric code: <code>` |
| `at(index)` | `0 <= index < count` | row | `index out of range: <index>` |
| `is_valid_alpha2/3/num` | any | `Bool` | never (errors collapse to `false`) |
| `region_by_code` | exactly 3 ASCII digits | row | `bad region code: <code>` / `unknown region code: <code>` |
| `region_at(index)` | `0 <= index < 30` | row | `index out of range: <index>` |

Reverse accessors `name_by_code`, `continent_by_code` and `region_by_code`
(country) try the three key kinds in the order alpha-2, alpha-3, numeric;
the key spaces are disjoint, so the first match is the only match. A
malformed or unknown key is `unknown country code: <code>`.

## Subdivision grammar

`geog_subdivision_parse(text)` and `geog_subdivision_format(country, part)`:

```
subdivision := country "-" part
country     := ASCII letter ASCII letter
part        := alnum{1,3}          ; ASCII letters or digits
```

- The parse normalizes `country` and `part` to uppercase; `raw` preserves
  the input byte-for-byte.
- The country part is shape-checked only, not resolved against the country
  table (use `geog_country_is_valid_alpha2` for that); ISO 3166-2 code
  elements are 1..3 alphanumerics, so `"GB-ENG"`, `"GR-A"` and `"GR-69"`
  are all valid shapes.
- Format re-validates both pieces and renders the canonical uppercase text.
- Empty input: `geography: empty subdivision`.

## Coordinate model

Micro-degrees are exact integers:

```
degrees = micro / 1000000          (truncating division, magnitude domain)
micro   = degrees * 1000000 + fraction
```

Canonical renderers:

- `geog_coord_format_decimal(micro)` -> signed, exactly six fraction digits,
  no hemisphere: `37975000` -> `"37.975000"`, `-37975000` -> `"-37.975000"`,
  `0` -> `"0.000000"` (negative zero never renders).
- `geog_coord_format_dms(micro, lat)` -> `D°MM'SS.FFFFFF"H` with 1..3 degree
  digits, two-digit minutes/seconds, exactly six second-fraction digits and
  a trailing uppercase hemisphere: `37975000, lat` ->
  `37°58'30.000000"N`. Zero renders `N` (lat) or `E` (lon).

The renderer arithmetic (all on the magnitude, sign applied at the end):

```
d    = mag / 1000000
r1   = mag % 1000000
min  = r1 * 60 / 1000000
r2   = (r1 * 60) % 1000000
secμ = r2 * 60
sec  = secμ / 1000000
frac = secμ % 1000000
```

This is exactly invertible: parsing the canonical text reproduces `micro`
for every representable value (asserted by round-trip tests).

## Decimal-degree grammar

```
decimal := hemi? sign? deg ( "." frac )? hemi?
hemi    := "N" | "S" | "E" | "W"     ; either case, at most once, start or end
sign    := "+" | "-"
deg     := digit{1,3}
frac    := digit{1,6}                ; a seventh digit is an error
```

Rules:

- `lat` selects the axis: N/S are latitude-only, E/W longitude-only; the
  other letters are `wrong hemisphere for axis at byte <n>`.
- Hemisphere sign must agree with an explicit sign when both appear
  (`-37.975S` is fine, `-37.975N` is `hemisphere conflicts with sign`).
- `-0.000000` parses to `0` (no negative zero value).
- Bounds: latitude `|micro| <= 90000000`, longitude `|micro| <= 180000000`;
  out-of-range reports `latitude out of range at byte <n>` /
  `longitude out of range at byte <n>` where `<n>` is the offset just past
  the parsed text.

## DMS grammar

```
dms    := hemi? deg degsym min minsym sec secsym hemi?
hemi   := as above
deg    := digit{1,3}
degsym := "°" (C2 B0) | "º" (C2 BA) | "d" | "D"
min    := digit{1,2}                  ; value < 60
minsym := "'" | "m" | "M" | U+2032 (E2 80 B2)
sec    := digit{1,2} ( "." digit{1,6} )?   ; value < 60
secsym := "\"" | U+2033 (E2 80 B3)
```

Rules:

- All three components and their symbols are required.
- `s`/`S` is deliberately **not** a second symbol: a trailing `S` would be
  ambiguous with the south hemisphere.
- Minutes and seconds must be below 60 (`minutes out of range at byte <n>`,
  `seconds out of range at byte <n>`); the seconds fraction has at most six
  digits.
- Bounds and hemisphere rules are as for decimal degrees. The conversion is
  `total_microseconds = ((d * 60 + min) * 60 + sec) * 1e6 + frac`, then
  `micro = total_microseconds / 3600` (truncating, magnitude domain); the
  canonical render has no truncation loss.
- Examples: `37°58'30"N` is exactly `37975000`; the fractional variant
  `37°58'30.5"N` truncates to `37975138`.

## Error catalog (coordinate and subdivision text)

| Message | Trigger |
|---|---|
| `geography: empty input` | empty text (decimal/DMS) |
| `geography: missing digits at byte <n>` | decimal: no digits after sign/hemisphere |
| `geography: too many degree digits at byte <n>` | 4th degree digit |
| `geography: too many fraction digits at byte <n>` | 7th fraction digit |
| `geography: missing fraction digits at byte <n>` | `.` with no digit after it |
| `geography: unexpected character at byte <n>` | any other byte before the end |
| `geography: bad hemisphere at byte <n>` | an alpha byte that is not N/S/E/W |
| `geography: wrong hemisphere for axis at byte <n>` | N/S on longitude, E/W on latitude |
| `geography: duplicate hemisphere at byte <n>` | a second hemisphere letter |
| `geography: hemisphere conflicts with sign at byte <n>` | sign and hemisphere differ |
| `geography: latitude out of range at byte <n>` | lat magnitude > 90000000 |
| `geography: longitude out of range at byte <n>` | lon magnitude > 180000000 |
| `geography: missing degree digits at byte <n>` | DMS: no degree digits |
| `geography: missing degree symbol at byte <n>` | DMS: no °/º/d/D |
| `geography: missing minute digits at byte <n>` | DMS: no minute digits |
| `geography: too many minute digits at byte <n>` | DMS: 3rd minute digit |
| `geography: minutes out of range at byte <n>` | DMS: minutes >= 60 |
| `geography: missing minute symbol at byte <n>` | DMS: no '/m/M/prime |
| `geography: missing second digits at byte <n>` | DMS: no second digits |
| `geography: too many second digits at byte <n>` | DMS: 3rd second digit |
| `geography: seconds out of range at byte <n>` | DMS: seconds >= 60 |
| `geography: missing second symbol at byte <n>` | DMS: no "/double prime |
| `geography: empty subdivision` | empty text |
| `geography: subdivision too short at byte 0` | fewer than 4 bytes |
| `geography: bad country letter at byte 0/1` | country part not two letters |
| `geography: missing hyphen at byte 2` | byte 2 is not `-` |
| `geography: bad subdivision length at byte 3` | part not 1..3 bytes |
| `geography: bad subdivision character at byte <n>` | part has a non-alphanumeric |

Validation is strictly left to right, so every malformed input has exactly
one deterministic error. Table-lookup errors are listed in the lookup
semantics section and the README.

## Integrity test matrix

The 21-test suite (`tests/test_conformance.xi`) asserts:

1. count 249, `AD` first / `ZW` last, out-of-range errors;
2. sample rows GR/US/JP/BR/DE for all fields;
3. alpha-2 case-insensitivity and shape/unknown errors;
4. alpha-3 case-insensitivity and shape/unknown errors;
5. numeric zero-padding (`8`, `08`, `008`) and shape/unknown errors;
6. the three validation predicates;
7. region count 30, names/parents (including 010), index and code errors;
8. country->region mapping for 11 countries plus by-code variants;
9. reverse name accessor across all three key kinds;
10-12. subdivision accept/reject/format with exact offset errors;
13-15. decimal parse accept/reject/render round-trips;
16-18. DMS parse accept/reject/render round-trips with symbol variants;
19. full-table sweep: 249 rows, 2/3/3 shapes, unique alpha-2/alpha-3/numeric,
    ascending order, region resolution, parent chains;
20. region sweep: 30 unique sorted rows, parent chains, continent totals
    (60/57/51/51/29/1);
21. the coordinate range predicate.

## Compiler notes (XIOM v0.61.3)

- Rows are `if` chains, not module-level table initializers (which
  mis-materialize).
- All Str equality goes through `xiom.string.compare` (BUG 17).
- Vec reads are bound to typed locals; bytes enter the Int domain through
  `(byte_at(s, i) as Int) & 255`.
- `Ok`/`Err` are constructed only in leaf helpers.
- No `Vec[Float64]`, no `&mut Int` out-params, no `[T, U]` callbacks, no
  indexed `Vec[fn]` dispatch; free functions only.
- Test dispatch is a direct call chain, and parallel Vec pushes happen in
  one arm per row so they cannot drift.
