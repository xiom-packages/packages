# xiom.l10n-address -- specification

> **Status:** matches the implemented module `src/l10n_address.xi` and the
> 22-check suite `tests/test_conformance.xi` (green on XIOM v0.62.0).
> Package version 0.1.0. Pure XIOM: no FFI, no I/O in the library module, no
> floating point.

## 1. Data model

### 1.1 Address

```xiom
pub type Address = {
  name: Str; organization: Str; street1: Str; street2: Str;
  city: Str; region: Str; postal_code: Str; country_code: Str;
}
```

An empty `Str` is the documented **absent** sentinel. There is no `Option`:
presence is `field.len() > 0` everywhere in the module.

### 1.2 Field codes

Slots reference fields by a small integer code (never by a `Str` key):

| Code | Field | Can be required in this dataset |
|------|-------|---------------------------------|
| 0 | `name` | yes (all 12 countries) |
| 1 | `organization` | no (always optional) |
| 2 | `street1` | yes (all 12 countries) |
| 3 | `street2` | no (always optional) |
| 4 | `city` | yes (all 12 countries) |
| 5 | `region` | yes (8 countries; not a field in DE/FR/NL/GB) |
| 6 | `postal_code` | yes (all 12 countries) |
| 7 | `country_code` | not used by any template |

`address_field_name(code)` maps codes to these names and returns `"unknown"`
for anything else.

### 1.3 AddressTemplate (parallel Vec fields)

```xiom
pub type AddressTemplate = {
  country_code: Str;        // "" = missing/unknown
  slot_field: Vec[Int];     // field code per slot, in render order
  slot_line: Vec[Int];      // 0-based output line per slot
  slot_required: Vec[Int];  // 1 = required, 0 = optional
  slot_sep: Vec[Str];       // separator printed before this slot within its line
}
```

The four slot arrays are parallel and equal-length; a template is **never** a
`Vec` of structs and never a module-level table (module-level table
initializers are mis-materialized by the pinned compiler). Each layout shape
is built by a builder function, with every slot pushed into all four vectors
through the single helper `_slot` (mirrored pushes).

`slot_sep` is ignored for the first non-empty slot emitted on a line: the
renderer only inserts it when the previous emitted slot is on the same line.

### 1.4 FieldInventory

```xiom
pub type FieldInventory = {
  names: Vec[Str];      // field names, render order
  required: Vec[Int];   // parallel flags, 1/0
}
```

Built by walking slots in order and keeping the first appearance of each
field code. In this dataset every template uses each field at most once, so
the inventory is the render-order projection of the template.

### 1.5 Selector and fallback

The `country` argument is ASCII upper-cased (byte-safe `str_upper`) and
compared against the 12 codes with `str_compare`. When `country` is empty,
`addr.country_code` is used instead (`_pick_country`). `address_fields`,
`address_template`, `address_supports` and `address_template_summary` take
the selector with no address fallback.

## 2. Per-country templates (as implemented)

`slot` lists the fields in render order; `L` is the 0-based output line;
`sep` is the separator printed before the slot inside its line (`""` for the
first slot of a line). Required flags: `R` = 1, `o` = 0.

### US -- `_tpl_city_region_postal("US", ", ")` -- 7 slots, 5 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | name | R | "" |
| 1 | 1 | organization | o | "" |
| 2 | 2 | street1 | R | "" |
| 3 | 3 | street2 | o | "" |
| 4 | 4 | city | R | "" |
| 5 | 4 | region | R | ", " |
| 6 | 4 | postal_code | R | " " |

Output shape: `name / organization / street1 / street2 / city, region postal_code`.

### CA -- `_tpl_city_region_postal("CA", " ")` -- 7 slots, 5 lines

Same slots as US with `region` separator `" "`:
`name / organization / street1 / street2 / city region postal_code`.

### AU -- `_tpl_city_region_postal("AU", " ")` -- 7 slots, 5 lines

Same as CA: `name / organization / street1 / street2 / city region postal_code`.

### IN -- `_tpl_city_region_postal("IN", ", ")` -- 7 slots, 5 lines

Same as US: `name / organization / street1 / street2 / city, region postal_code`.

### GB -- `_tpl_city_then_postal("GB")` -- 6 slots, 6 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | name | R | "" |
| 1 | 1 | organization | o | "" |
| 2 | 2 | street1 | R | "" |
| 3 | 3 | street2 | o | "" |
| 4 | 4 | city | R | "" |
| 5 | 5 | postal_code | R | "" |

`region` is not a template field for GB.

### DE / FR / NL -- `_tpl_postal_city(cc)` -- 6 slots, 5 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | name | R | "" |
| 1 | 1 | organization | o | "" |
| 2 | 2 | street1 | R | "" |
| 3 | 3 | street2 | o | "" |
| 4 | 4 | postal_code | R | "" |
| 5 | 4 | city | R | " " |

Output shape: `name / organization / street1 / street2 / postal_code city`.
A supplied `region` is ignored (not a template field).

### IT -- `_tpl_postal_city_region("IT")` -- 7 slots, 5 lines

Same as DE/FR/NL plus `region` on line 4 with separator `" "`:
`name / organization / street1 / street2 / postal_code city region`.

### JP -- `_tpl_bigfirst_inline("JP")` -- 7 slots, 6 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | postal_code | R | "" |
| 1 | 1 | region | R | "" |
| 2 | 1 | city | R | " " |
| 3 | 2 | street1 | R | "" |
| 4 | 3 | street2 | o | "" |
| 5 | 4 | organization | o | "" |
| 6 | 5 | name | R | "" |

Big-to-small: `postal_code / region city / street1 / street2 / organization / name`;
the recipient is last.

### CN -- `_tpl_bigfirst_stacked("CN")` -- 7 slots, 7 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | postal_code | R | "" |
| 1 | 1 | region | R | "" |
| 2 | 2 | city | R | "" |
| 3 | 3 | street1 | R | "" |
| 4 | 4 | street2 | o | "" |
| 5 | 5 | organization | o | "" |
| 6 | 6 | name | R | "" |

Like JP but `region` and `city` occupy separate lines.

### BR -- `_tpl_postal_city_dash_region("BR")` -- 7 slots, 5 lines

| slot | L | field | req | sep |
|------|---|-------|-----|-----|
| 0 | 0 | name | R | "" |
| 1 | 1 | organization | o | "" |
| 2 | 2 | street1 | R | "" |
| 3 | 3 | street2 | o | "" |
| 4 | 4 | postal_code | R | "" |
| 5 | 4 | city | R | " " |
| 6 | 4 | region | R | " - " |

Output shape: `name / organization / street1 / street2 / postal_code city - region`.

### Summary table

| Code | Shape builder | Slots | Lines | Region in template |
|------|---------------|-------|-------|--------------------|
| US | `_tpl_city_region_postal(", ")` | 7 | 5 | yes |
| CA | `_tpl_city_region_postal(" ")` | 7 | 5 | yes |
| GB | `_tpl_city_then_postal` | 6 | 6 | no |
| DE | `_tpl_postal_city` | 6 | 5 | no |
| FR | `_tpl_postal_city` | 6 | 5 | no |
| NL | `_tpl_postal_city` | 6 | 5 | no |
| IT | `_tpl_postal_city_region` | 7 | 5 | yes |
| JP | `_tpl_bigfirst_inline` | 7 | 6 | yes |
| CN | `_tpl_bigfirst_stacked` | 7 | 7 | yes |
| AU | `_tpl_city_region_postal(" ")` | 7 | 5 | yes |
| IN | `_tpl_city_region_postal(", ")` | 7 | 5 | yes |
| BR | `_tpl_postal_city_dash_region` | 7 | 5 | yes |

## 3. Algorithms

### 3.1 address_render(country, addr) -> Result[Str, Str]

1. `sel = country` when non-empty, else `addr.country_code`.
2. `tpl = _template(sel)`; if `tpl.country_code.len() == 0` ->
   `Err("address: unknown country: " + str_upper(sel))`.
3. `errs = _validate_slots(tpl, addr)`; if non-empty ->
   `Err(errs[0])` (first missing required field in slot order).
4. Otherwise join slots: walk slots in order; skip absent values; for the
   first emitted slot `out = v`; for a subsequent slot on the same line
   `out = out + sep + v`; on a new line `out = out + "\n" + v`. Return
   `Ok(out)`.

`Ok`/`Err` are constructed only inside the leaf helpers `_render_ok` /
`_render_err` (inline construction next to struct values miscompiles on the
pinned compiler).

### 3.2 address_validate(country, addr) -> Vec[Str]

Same selector and template resolution as rendering. For each slot with
`slot_required != 0`, append `"address: missing required field: " +
_field_name(code)` when the field is absent. Unknown country yields a
one-element list with the unknown-country message. Rendering is never
invoked; the list is exactly the set of reasons `address_render` would
reject the input, in the same order.

### 3.3 address_fields(country) -> FieldInventory

Walks slots, deduplicates by field code (first appearance wins), and emits
parallel `names`/`required` arrays. Unknown country -> two empty arrays.

### 3.4 address_template_summary(country) -> Str

`"<CC>: <slots> slots, <lines> lines"`; `lines` is `max(slot_line) + 1`.
Unknown country -> `"address: unknown country: <CODE>"`. Uses
`convert.int_to_string` from `xiom.convert`.

## 4. Error catalog

| Message | Emitted by | Condition |
|---------|-----------|-----------|
| `address: unknown country: <CODE>` | `address_render` (Err), `address_validate` (single list entry), `address_template_summary` (returned text) | selector not one of the 12 codes; `<CODE>` is the ASCII upper-cased selector, possibly empty |
| `address: missing required field: <name>` | `address_render` (Err, first only), `address_validate` (one entry per field, slot order) | field absent (`len() == 0`) and `slot_required == 1` |

`<name>` is one of `name`, `street1`, `city`, `region`, `postal_code` in this
dataset; `organization` and `street2` are always optional and can never
produce this message. `country_code` is never a template slot. No other
messages exist; optional-field absence, empty `organization`/`street2`,
unknown `region` on DE/FR/NL and a `country_code` that disagrees with the
template selector are all accepted.

## 5. Test plan (tests/test_conformance.xi, 22 checks)

| Test | Proves |
|------|--------|
| t1 | US full render exact text (5 lines, `city, region postal_code`) |
| t2 | absent optional organization/street2 vanish; street2 alone still renders |
| t3 | each absent US required field is the first render error (`name`/`street1`/`region`/`postal_code`) |
| t4 | US validate on a blank address returns all 5 required errors in slot order |
| t5 | validate-vs-render consistency: 2 errors -> `Err(errs[0])`; 0 errors -> `Ok` |
| t6 | GB postcode on its own final line; inventory ends city/postal_code |
| t7 | DE `postal_code city` order; region not a DE field |
| t8 | FR shares DE's shape |
| t9 | JP full render: postal first, `region city` inline, recipient last |
| t10 | JP/CN optional-absent renders; CN big-to-small with stacked region/city |
| t11 | US/GB/DE/FR/JP/CN field orders via `address_fields` |
| t12 | unknown-country render error, upper-cased code in message, empty selector |
| t13 | unknown-country validate (one error), empty fields/template, empty-selector blank |
| t14 | selector is ASCII case-insensitive (`fr`, `Fr`, `us`, `Us`, `XX`) |
| t15 | US inventory: 7 names in render order, required flags 1,0,1,0,1,1,1 |
| t16 | DE/GB/IT/JP/CN/BR inventory sizes and flags (FR org optional) |
| t17 | all 12 countries validate cleanly and render non-empty for a complete address |
| t18 | `address_countries` returns 12 codes, sorted (AU first, US last) |
| t19 | AU/CA/NL/IT/IN/BR exact renders (in-line separators) |
| t20 | empty selector falls back to `addr.country_code` (render + validate) |
| t21 | template summaries (US/JP/CN/DE) and parallel-array integrity for all 12 |
| t22 | `address_field_name` maps 0/6/7 and returns `unknown` for 99 |

Support functions: `streq` (all `Str` equality via `str_compare`), `mk` /
`blank` fixtures, `render_ok_eq`, `render_err_is`, `validate_len`,
`validate_at`, `field_count`, `field_name_at`, `field_req_at`,
`template_parallel_ok`, `clean_for`. Every `Vec` element read is bound to a
typed local; test dispatch is a direct `t1..t22` call chain (never a
`Vec[fn]`).

## 6. Provenance and limitations

- The 12 templates are **illustrative UPU-style layouts** selected to cover
  distinct field orders and separators; they are not an authoritative
  addressing standard and carry no postal guarantees.
- ASCII/Latin output only: no transliteration, script shaping or bidi.
- `postal_code`, `region` and `city` are free text; only presence is
  checked. No geocoding, no address parsing, no subdivision validation.
- In-line separators and line breaks are fixed per template; no per-call
  overrides.
- Unknown countries fail closed (no fallback template).
- All test fixtures are synthetic; no real personal data is used.
