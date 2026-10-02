# xiom.l10n-address

> **Naming:** registry package `xiom.l10n-address`; module namespace `xiom.l10n.address`.

Country address templates, multi-line rendering and field validation for a
built-in 12-country dataset.

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.1` on the XIOM registry.

## Scope

Given an ISO 3166-1 alpha-2 country code and an `Address` record, the module
applies that country's postal layout: which fields appear, in which order,
on which lines, with which separators, and which of them are required.

- `address_render` produces the formatted multi-line text.
- `address_validate` reports every missing required field without rendering.
- `address_fields` returns the field inventory (names and required flags) in
  render order.
- `address_template` exposes the raw template (parallel slot arrays).

An empty `Str` is the documented **absent** sentinel for every `Address`
field. Absent optional fields are skipped; an absent required field is an
error.

## Dataset (12 countries)

`|` separates slots on the same output line; `/` separates lines. All listed
fields except `organization` and `street2` are required.

| Code | Rendered layout |
|------|-----------------|
| US | `name / organization / street1 / street2 / city, region postal_code` |
| CA | `name / organization / street1 / street2 / city region postal_code` |
| GB | `name / organization / street1 / street2 / city / postal_code` |
| DE | `name / organization / street1 / street2 / postal_code city` |
| FR | `name / organization / street1 / street2 / postal_code city` |
| NL | `name / organization / street1 / street2 / postal_code city` |
| IT | `name / organization / street1 / street2 / postal_code city region` |
| JP | `postal_code / region city / street1 / street2 / organization / name` |
| CN | `postal_code / region / city / street1 / street2 / organization / name` |
| AU | `name / organization / street1 / street2 / city region postal_code` |
| IN | `name / organization / street1 / street2 / city, region postal_code` |
| BR | `name / organization / street1 / street2 / postal_code city - region` |

Example outputs (synthetic data):

```
US: Ada Lovelace / Analytical Engines / 123 Analytical Way / Suite 200
    Springfield, IL 62704

JP: 100-0001 / Tokyo Chiyoda / 1-1 Chiyoda / Sakura Labs / Kai Tanaka

BR: Rio Example / 1 Avenida / 01000-000 Sao Paulo - SP
```

## API

```xiom
pub type Address = {
  name: Str; organization: Str; street1: Str; street2: Str;
  city: Str; region: Str; postal_code: Str; country_code: Str;
}

pub fn address_render(country: Str, addr: &Address) -> Result[Str, Str]
pub fn address_validate(country: Str, addr: &Address) -> Vec[Str]
pub fn address_fields(country: Str) -> FieldInventory
pub fn address_template(country: Str) -> AddressTemplate
pub fn address_supports(country: Str) -> Bool
pub fn address_field_name(code: Int) -> Str
pub fn address_country_count() -> Int
pub fn address_countries() -> Vec[Str]
pub fn address_template_summary(country: Str) -> Str
```

`country` is matched ASCII case-insensitively. When it is empty,
`addr.country_code` is used as the selector instead (see
`address_render` and `address_validate`).

`FieldInventory` carries the inventory as parallel arrays:
`names: Vec[Str]` and `required: Vec[Int]` (1 required, 0 optional), in
render order. `AddressTemplate` stores the layout as parallel slot arrays
(`slot_field`, `slot_line`, `slot_required`, `slot_sep`); see SPEC.md.

## Usage

```xiom
module demo
use xiom.io; use xiom.l10n.address; use xiom.convert;

fn main() -> Int {
  let a = Address{
    name: "Ada Lovelace"; organization: "Analytical Engines";
    street1: "123 Analytical Way"; street2: "";
    city: "Springfield"; region: "IL"; postal_code: "62704";
    country_code: "US"
  };
  match address_render("US", &a) {
    Ok(text) => { io.println(text); },
    Err(msg) => { io.println(msg); },
  }
  let errs = address_validate("JP", &a);
  io.println("JP problems: " + convert.int_to_string(errs.len()));
  return 0;
}
```

## Limitations (honest scope)

- **The dataset is illustrative, not authoritative.** The 12 templates are
  simplified UPU-style layouts chosen to exercise distinct field orders and
  separators; they are not a complete or current worldwide addressing
  standard. Treat them as a starting point, not postal advice.
- **No geocoding, no parsing.** Input is a structured `Address`; free-form
  addresses are out of scope. There is no reverse lookup from text.
- **No postal-code syntax validation.** `postal_code` is checked only for
  presence on required templates, never for country-specific format.
- **ASCII/Latin output only.** Templates concatenate the `Str` bytes given;
  there is no transliteration, script shaping or bidi handling.
- **No division names.** `region` is free text; the module never validates a
  state/province against `postal_code` or a city.
- **No country-name line.** Templates do not append a country name; only the
  eight `Address` fields can appear.
- **Fixed separators.** The in-line separators (e.g. `", "`, `" - "`) are
  part of each template and cannot be re-configured per call.
- **Unknown countries fail closed** with `address: unknown country: <CODE>`;
  there is no fallback template.

## Test coverage

`tests/test_conformance.xi` runs 22 checks: per-country renders (US/GB/DE/
FR/JP/CN orders), required-field errors, unknown-country behaviour,
case-insensitivity, optional-absent handling, field inventories and flags,
validate-vs-render consistency, template parallel-array integrity, and the
country_code fallback. Run:

```powershell
.\scripts\port.ps1 -Package xiom.l10n-address
```
