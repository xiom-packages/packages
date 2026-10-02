# xiom.geography

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.2` on the XIOM registry.
> **Scope:** embedded ISO 3166-1 country table (249 officially assigned
> codes), UN M49 region table (30 codes), ISO 3166-2 subdivision code
> *syntax*, and integer coordinate text codecs (decimal degrees and DMS).
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`).

## What it is

`xiom.geography` is a pure-data, integer-only geography core. Nothing here
uses floating point, a locale database, FFI or an allocator-heavy builder.

- **Country table.** All 249 officially assigned ISO 3166-1 alpha-2 codes,
  each with its alpha-3 code, zero-padded three-digit numeric code, ISO
  English short name, UN M49 top-level continent code and the finest UN M49
  region code of the embedded region table. Lookups by alpha-2 / alpha-3
  (ASCII case-insensitive) and numeric (one to three digits, left-zero-padded
  so `"8"` resolves like `"008"`), validity predicates, field accessors and
  reverse accessors (name / continent / region by any key kind).
- **Region table.** The six M49 top-level regions plus the subregions listed
  in SPEC.md, including `010 Antarctica`, so every country code resolves.
  Each row carries code, UN English name and parent code.
- **ISO 3166-2 subdivision syntax.** `CC-SUB` parse and format: two ASCII
  letters, `-`, then one to three ASCII alphanumerics. There is **no**
  per-country subdivision list; the parser validates the shape, normalizes
  to uppercase and preserves the raw text verbatim.
- **Coordinates.** Decimal degrees (`[-]DD.dddd`, optional N/S/E/W
  hemisphere) and sexagesimal DMS (`DD°MM'SS.ssssss"H`) parsed into scaled
  integer micro-degrees (1e-6 degree), plus canonical renderers for both.
  Latitude `[-90000000, 90000000]`, longitude `[-180000000, 180000000]`;
  minutes and seconds below 60; hemisphere letters must match the axis and
  agree with an explicit sign. Canonical renders re-parse to exactly the same
  micro-degree value.

## Install / use

```
xiom pkg install xiom.geography@0.1.0
```

The manifest package name and the importable module name are the same,
`xiom.geography` (no hyphen, so no name mapping is needed).

```xi
use xiom.geography;
use xiom.io;

match geog_country_by_alpha2("gr") {
  Ok(c) => {
    io.println(c.name);       // "Greece"
    io.println(c.alpha3);     // "GRC"
    io.println(c.numeric);    // "300"
    io.println(c.continent);  // "150"
    io.println(c.region);     // "039"
  },
  Err(e) => { io.println(e); },
}

match geog_coord_parse_decimal("37.975N", true) {
  Ok(micro) => { io.println(geog_coord_format_dms(micro, true)); },
  Err(e) => { io.println(e); },   // prints 37°58'30.000000"N
}
```

Other one-liners:

```xi
// lookups
geog_country_by_numeric("8");          // Ok(Albania) -- short forms zero-pad
geog_country_by_alpha3("jpn");         // Ok(Japan)
geog_country_name_by_code("grc");      // Ok("Greece")
geog_country_region_by_code("300");    // Ok("039")
// regions
geog_region_name_by_code("010");       // Ok("Antarctica")
geog_region_parent_by_code("202");     // Ok("002")
// subdivision syntax (no per-country list)
geog_subdivision_parse("gb-eng");      // Ok(country "GB", part "ENG", raw "gb-eng")
geog_subdivision_format("gr", "a");    // Ok("GR-A")
geog_subdivision_is_valid("GR_");      // false
// coordinates
geog_coord_parse_dms("37d58m30\"N", true);   // Ok(37975000)
geog_coord_parse_dms("122°30'0\"W", false);  // Ok(-122500000)
geog_coord_format_decimal(37975000);         // "37.975000"
geog_coord_format_dms(0, true);              // 0°00'00.000000"N
geog_coord_in_range(90000001, true);         // false
```

## API

All functions are free functions in module `xiom.geography`.

| Function | Returns | Description |
|---|---|---|
| `geog_country_count()` | `Int` | Number of country rows (249). |
| `geog_country_at(index)` | `Result[Country, Str]` | Row by index `0..248`, ascending alpha-2. |
| `geog_country_by_alpha2(code)` | `Result[Country, Str]` | Case-insensitive alpha-2 lookup. |
| `geog_country_by_alpha3(code)` | `Result[Country, Str]` | Case-insensitive alpha-3 lookup. |
| `geog_country_by_numeric(code)` | `Result[Country, Str]` | 1..3 digits, left-zero-padded. |
| `geog_country_is_valid_alpha2(code)` | `Bool` | `true` iff the alpha-2 lookup accepts `code`. |
| `geog_country_is_valid_alpha3(code)` | `Bool` | `true` iff the alpha-3 lookup accepts `code`. |
| `geog_country_is_valid_numeric(code)` | `Bool` | `true` iff the numeric lookup accepts `code`. |
| `geog_country_alpha2(c)` / `_alpha3(c)` / `_numeric(c)` | `Str` | Field accessors on a `Country`. |
| `geog_country_name(c)` | `Str` | ISO English short name of a `Country`. |
| `geog_country_continent(c)` / `_region(c)` | `Str` | UN M49 continent / finest region code. |
| `geog_country_name_by_code(code)` | `Result[Str, Str]` | Name by alpha-2 / alpha-3 / numeric. |
| `geog_country_continent_by_code(code)` | `Result[Str, Str]` | Continent code by any key. |
| `geog_country_region_by_code(code)` | `Result[Str, Str]` | Finest region code by any key. |
| `geog_region_count()` | `Int` | Number of region rows (30). |
| `geog_region_at(index)` | `Result[Region, Str]` | Row by index, ascending numeric code. |
| `geog_region_by_code(code)` | `Result[Region, Str]` | Exact 3-digit M49 code lookup. |
| `geog_region_is_valid(code)` | `Bool` | `true` iff the region lookup accepts `code`. |
| `geog_region_code(r)` / `_name(r)` / `_parent(r)` | `Str` | Field accessors on a `Region`. |
| `geog_region_name_by_code(code)` | `Result[Str, Str]` | Region name by code. |
| `geog_region_parent_by_code(code)` | `Result[Str, Str]` | Parent code (`""` for top-level). |
| `geog_subdivision_parse(text)` | `Result[Subdivision, Str]` | `CC-SUB` syntax; raw preserved; offset errors. |
| `geog_subdivision_format(country, part)` | `Result[Str, Str]` | Canonical uppercase `CC-SUB`. |
| `geog_subdivision_is_valid(text)` | `Bool` | `true` iff the parse accepts `text`. |
| `geog_subdivision_country(s)` / `_part(s)` / `_raw(s)` | `Str` | Parsed pieces (raw verbatim). |
| `geog_subdivision_canonical(s)` | `Str` | Canonical `CC-SUB` of a parsed value. |
| `geog_coord_parse_decimal(text, lat)` | `Result[Int, Str]` | Decimal degrees to micro-degrees. |
| `geog_coord_parse_dms(text, lat)` | `Result[Int, Str]` | DMS text to micro-degrees. |
| `geog_coord_format_decimal(micro)` | `Str` | Signed fixed-six-decimal text. |
| `geog_coord_format_dms(micro, lat)` | `Str` | Canonical DMS with hemisphere. |
| `geog_coord_in_range(micro, lat)` | `Bool` | Inclusive axis range check. |

```xi
pub type Country     = { alpha2: Str; alpha3: Str; numeric: Str; name: Str;
                         continent: Str; region: Str; }
pub type Region      = { code: Str; name: Str; parent: Str; }
pub type Subdivision = { country: Str; part: Str; raw: Str; }
```

## Error model

Table lookups are strict and carry the offending key:
`geography: bad alpha-2 code: <code>`, `geography: bad alpha-3 code:
<code>`, `geography: bad numeric code: <code>`, `geography: unknown country
code: <code>`, `geography: unknown numeric code: <code>`, `geography: bad
region code: <code>`, `geography: unknown region code: <code>`,
`geography: index out of range: <index>`, `geography: unknown country code:
<code>` for the reverse accessors.

Every positional text error carries the byte offset of the failing byte
(see SPEC.md for the full catalog), e.g. `geography: missing hyphen at byte
2`, `geography: seconds out of range at byte 7`, `geography: too many
fraction digits at byte 9`, `geography: latitude out of range at byte 9`,
`geography: hemisphere conflicts with sign at byte 7`. Out-of-range
coordinate errors point just past the parsed text; the empty input is
`geography: empty input` (or `geography: empty subdivision`).

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.geography
```

Expected: 21 `[PASS]` lines and
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

Coverage: sample lookups by all three keys for GR/US/JP/BR/DE, alpha case
variants, numeric zero-padding, validation predicates, region names/parents,
country->region mapping (including AQ to 010), reverse name accessor,
subdivision accept/reject with offsets, decimal and DMS parse/render
round-trips, bounds and symbol rejections, continent totals
(60/57/51/51/29/1) and the full-table integrity sweep (unique 2/3/3 keys,
shapes, sorted order, region resolution and parent chains).

## Limitations

- **Snapshot table.** The country rows are the ISO 3166-1 officially
  assigned set at the package cut-off; user-assigned codes (`AA`, `QM`-`QZ`,
  `XA`-`XZ`, `ZZ`), reserved and transitional codes are not present.
- **UN M49 granularity.** A country maps to the finest embedded M49 code;
  `202 Sub-Saharan Africa` and `419 Latin America and the Caribbean` are
  ancestors in the table and have no direct country rows. `010 Antarctica`
  is included so the AQ row resolves.
- **Subdivision syntax only.** There is no per-country ISO 3166-2 list. The
  country part is shape-checked, not checked against the country table (use
  `geog_country_is_valid_alpha2` for that); the subdivision part is
  preserved verbatim and only uppercased for the canonical form.
- **Names.** ISO English short names with their diacritics (`Åland Islands`,
  `Côte d'Ivoire`, `Curaçao`, `Réunion`, `Türkiye`); only the alpha/numeric
  lookups are case-insensitive, name matching is byte-exact.
- **Coordinate text, not geodesy.** Micro-degree precision, at most six
  fraction digits (a seventh is an error), DMS requires all three components
  and their symbols; `s`/`S` is deliberately not a second symbol because it
  would be ambiguous with the south hemisphere. No map projections, terrain,
  distances or geodesic math -- those were mentioned in the pre-implementation
  placeholder scope and are explicitly out of this module.
- **Integer-only.** No `Vec[Float64]`, no float parse, no floating math
  anywhere in the module.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
