// XIOM -- xiom.l10n.address: country address templates, rendering, validation
// Port task: replace the xiom.l10n.address placeholder with a pure-XIOM module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a country's postal layout is an ordered list of *slots* (field
// placeholders) grouped into *lines*. Every slot carries the field it renders
// (a small integer code), its line number, a required flag (1/0) and the
// separator that precedes it inside its line. A template is stored as parallel
// Vec fields on AddressTemplate -- one entry per slot in render order -- never
// as a Vec of structs, and never as a module-level table (module-level table
// initializers are mis-materialized by XIOM v0.62.0), so each layout shape is
// built by a plain builder function and selected by an if-chain.
//
// Absence: an empty Str in Address is the documented "absent" sentinel.
// Rendering skips absent optional slots; an absent required slot is an error.
// Country selection is case-insensitive (ASCII upper-casing); when the
// `country` argument is empty, the address's own country_code field is used.
//
// Out of scope: geocoding, postal-code syntax checks, transliteration,
// national-script output (templates render ASCII/Latin transliterations) and
// locale-specific casing or punctuation beyond the documented separators.
// The 12 templates are illustrative UPU-style layouts (see README.md and
// SPEC.md), not a complete worldwide dataset.
//
// Compiler discipline (v0.62.0): free functions only; no Str ==; typed
// Vec[Int] reads; Ok/Err constructed only in leaf helpers; no Vec of
// structs; parallel Vec pushes mirrored through one helper; all UInt8
// comparisons stay in the ASCII range.

module xiom.l10n.address

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// Field codes: the canonical position of each Address field.
const _AD_NAME: Int = 0;
const _AD_ORG: Int = 1;
const _AD_STREET1: Int = 2;
const _AD_STREET2: Int = 3;
const _AD_CITY: Int = 4;
const _AD_REGION: Int = 5;
const _AD_POSTAL: Int = 6;
const _AD_COUNTRY: Int = 7;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Address input record. An empty Str is the documented "absent" sentinel:
/// absent optional fields are skipped while rendering, absent required fields
/// produce an error. country_code is consulted only when the template-selector
/// argument is empty (see address_render and address_validate).
pub type Address = {
  name: Str;
  organization: Str;
  street1: Str;
  street2: Str;
  city: Str;
  region: Str;
  postal_code: Str;
  country_code: Str;
}

/// One country's layout as parallel arrays, one entry per slot in render
/// order (never a Vec of structs): slot_field is the field code, slot_line the
/// 0-based output line, slot_required 1 (required) or 0 (optional), and
/// slot_sep the separator inserted before the slot inside its line ("" for
/// the first slot of a line). country_code is "" when the requested country
/// is not in the dataset.
pub type AddressTemplate = {
  country_code: Str;
  slot_field: Vec[Int];
  slot_line: Vec[Int];
  slot_required: Vec[Int];
  slot_sep: Vec[Str];
}

/// Field inventory of a template, in render order: names[i] is the field name
/// and required[i] is 1 (required) or 0 (optional) for the same field. Slots
/// of one field collapse to their first appearance, so both arrays are
/// parallel and equal-length. An unknown country yields two empty arrays.
pub type FieldInventory = {
  names: Vec[Str];
  required: Vec[Int];
}

// ---------------------------------------------------------------------------
// Field helpers
// ---------------------------------------------------------------------------

// Human name of a field code ("unknown" for codes outside the dataset).
fn _field_name(code: Int) -> Str {
  if code == _AD_NAME { return "name"; }
  if code == _AD_ORG { return "organization"; }
  if code == _AD_STREET1 { return "street1"; }
  if code == _AD_STREET2 { return "street2"; }
  if code == _AD_CITY { return "city"; }
  if code == _AD_REGION { return "region"; }
  if code == _AD_POSTAL { return "postal_code"; }
  if code == _AD_COUNTRY { return "country_code"; }
  return "unknown";
}

// Value of a field code on an address ("" for absent fields and unknown codes).
fn _field_value(addr: &Address, code: Int) -> Str {
  if code == _AD_NAME { let v: Str = addr.name; return v; }
  if code == _AD_ORG { let v: Str = addr.organization; return v; }
  if code == _AD_STREET1 { let v: Str = addr.street1; return v; }
  if code == _AD_STREET2 { let v: Str = addr.street2; return v; }
  if code == _AD_CITY { let v: Str = addr.city; return v; }
  if code == _AD_REGION { let v: Str = addr.region; return v; }
  if code == _AD_POSTAL { let v: Str = addr.postal_code; return v; }
  if code == _AD_COUNTRY { let v: Str = addr.country_code; return v; }
  return "";
}

// ---------------------------------------------------------------------------
// Dataset builders (one shape function per family of countries)
// ---------------------------------------------------------------------------
//
// Every builder pushes one entry into each of the four parallel vectors for
// every slot; _slot centralizes the mirrored pushes (trap 16).

fn _slot(fields: &mut Vec[Int], lines: &mut Vec[Int], reqs: &mut Vec[Int],
         seps: &mut Vec[Str], code: Int, line: Int, req: Int, sep: Str) {
  fields.push(code);
  lines.push(line);
  reqs.push(req);
  seps.push(sep);
}

fn _mk_tpl(cc: Str, fields: Vec[Int], lines: Vec[Int], reqs: Vec[Int],
           seps: Vec[Str]) -> AddressTemplate {
  let t = AddressTemplate{ country_code: cc; slot_field: fields; slot_line: lines; slot_required: reqs; slot_sep: seps };
  return t;
}

fn _tpl_missing() -> AddressTemplate {
  let fields = Vec[Int].new();
  let lines = Vec[Int].new();
  let reqs = Vec[Int].new();
  let seps = Vec[Str].new();
  return _mk_tpl("", fields, lines, reqs, seps);
}

// Western block: name / organization / street1 / street2 / city <sep> region postal.
// Used by US (", "), CA (" "), AU (" ") and IN (", ").
fn _tpl_city_region_postal(cc: Str, region_sep: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 1, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 4, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_REGION, 4, 1, region_sep);
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 4, 1, " ");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// GB: the postcode gets its own final line after the post town.
fn _tpl_city_then_postal(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 1, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 4, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 5, 1, "");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// German-style: postal code before the city on one line ("10115 Berlin").
// Used by DE, FR and NL.
fn _tpl_postal_city(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 1, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 4, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 4, 1, " ");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// IT: postal code, city and province abbreviation on one line ("00185 Roma RM").
fn _tpl_postal_city_region(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 1, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 4, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 4, 1, " ");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_REGION, 4, 1, " ");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// Big-to-small with the prefecture/region and the city on one line, the
// recipient last (JP): postal / region city / street1 / street2 / org / name.
fn _tpl_bigfirst_inline(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_REGION, 1, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 1, 1, " ");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 4, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 5, 1, "");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// Big-to-small with region and city on separate lines (CN): postal / region /
// city / street1 / street2 / org / name.
fn _tpl_bigfirst_stacked(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_REGION, 1, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 3, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 4, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 5, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 6, 1, "");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// BR: "01000-000 Sao Paulo - SP" -- postal code first, region after the city.
fn _tpl_postal_city_dash_region(cc: Str) -> AddressTemplate {
  var fields = Vec[Int].new();
  var lines = Vec[Int].new();
  var reqs = Vec[Int].new();
  var seps = Vec[Str].new();
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_NAME, 0, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_ORG, 1, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET1, 2, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_STREET2, 3, 0, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_POSTAL, 4, 1, "");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_CITY, 4, 1, " ");
  _slot(&mut fields, &mut lines, &mut reqs, &mut seps, _AD_REGION, 4, 1, " - ");
  return _mk_tpl(cc, fields, lines, reqs, seps);
}

// Country selector: ASCII case-insensitive match on the ISO 3166-1 alpha-2
// code; unknown codes return the missing template (country_code "").
fn _template(country: Str) -> AddressTemplate {
  let c = string.str_upper(country);
  if compare.str_compare(c, "US") == 0 { return _tpl_city_region_postal("US", ", "); }
  if compare.str_compare(c, "CA") == 0 { return _tpl_city_region_postal("CA", " "); }
  if compare.str_compare(c, "GB") == 0 { return _tpl_city_then_postal("GB"); }
  if compare.str_compare(c, "DE") == 0 { return _tpl_postal_city("DE"); }
  if compare.str_compare(c, "FR") == 0 { return _tpl_postal_city("FR"); }
  if compare.str_compare(c, "NL") == 0 { return _tpl_postal_city("NL"); }
  if compare.str_compare(c, "IT") == 0 { return _tpl_postal_city_region("IT"); }
  if compare.str_compare(c, "JP") == 0 { return _tpl_bigfirst_inline("JP"); }
  if compare.str_compare(c, "CN") == 0 { return _tpl_bigfirst_stacked("CN"); }
  if compare.str_compare(c, "AU") == 0 { return _tpl_city_region_postal("AU", " "); }
  if compare.str_compare(c, "IN") == 0 { return _tpl_city_region_postal("IN", ", "); }
  if compare.str_compare(c, "BR") == 0 { return _tpl_postal_city_dash_region("BR"); }
  return _tpl_missing();
}

// ---------------------------------------------------------------------------
// Validation and rendering internals
// ---------------------------------------------------------------------------

// Error list for a known template: one entry per absent required field, in
// slot (render) order. Rendering is never needed for this check.
fn _validate_slots(tpl: &AddressTemplate, addr: &Address) -> Vec[Str] {
  var errs = Vec[Str].new();
  let fields: Vec[Int] = tpl.slot_field;
  let reqs: Vec[Int] = tpl.slot_required;
  let n = fields.len();
  var i = 0;
  while i < n {
    let req: Int = reqs[i];
    if req != 0 {
      let code: Int = fields[i];
      let v: Str = _field_value(addr, code);
      if v.len() == 0 {
        errs.push("address: missing required field: " + _field_name(code));
      }
    }
    i = i + 1;
  }
  return errs;
}

// Join the present slots: slots sharing a line are joined with their in-line
// separator, a line change emits "\n". Absent optional slots vanish; for a
// template that passed validation the remaining slots cover every line.
fn _join_slots(tpl: &AddressTemplate, addr: &Address) -> Str {
  let fields: Vec[Int] = tpl.slot_field;
  let lines: Vec[Int] = tpl.slot_line;
  let seps: Vec[Str] = tpl.slot_sep;
  let n = fields.len();
  var out = "";
  var last_line: Int = 0 - 1;
  var i = 0;
  while i < n {
    let code: Int = fields[i];
    let v: Str = _field_value(addr, code);
    if v.len() > 0 {
      let ln: Int = lines[i];
      if out.len() == 0 {
        out = v;
        last_line = ln;
      } elif ln == last_line {
        let sep: Str = seps[i];
        out = out + sep + v;
      } else {
        out = out + "\n" + v;
        last_line = ln;
      }
    }
    i = i + 1;
  }
  return out;
}

// Template selector fallback: an explicit argument wins, otherwise the
// address's own country_code is used.
fn _pick_country(country: Str, addr: &Address) -> Str {
  if country.len() > 0 { return country; }
  let cc: Str = addr.country_code;
  return cc;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also builds a struct value miscompiles on XIOM v0.62.0.
fn _render_ok(text: Str) -> Result[Str, Str] {
  return Ok(text);
}

fn _render_err(msg: Str) -> Result[Str, Str] {
  return Err(msg);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Render an address with a country's template.
/// Params: country - ISO 3166-1 alpha-2 code of the template to apply (ASCII
/// case-insensitive). When empty, addr.country_code is used instead. addr -
/// the address input; an empty Str marks an absent field.
/// Returns: Ok(text) with one line per populated template line, in template
/// order; optional absent fields are skipped with their in-line separators.
/// Error case: Err("address: unknown country: <CODE>") when the selected code
/// is not in the dataset; Err("address: missing required field: <name>") with
/// the first missing required field in render order.
/// Examples: address_render("US", ada) with city/region/postal set ->
/// "Ada Lovelace\n123 Analytical Way\nSpringfield, IL 62704".
/// Complexity: O(slots + output length).
pub fn address_render(country: Str, addr: &Address) -> Result[Str, Str] {
  let sel = _pick_country(country, addr);
  let tpl = _template(sel);
  let cc: Str = tpl.country_code;
  if cc.len() == 0 {
    return _render_err("address: unknown country: " + string.str_upper(sel));
  }
  let errs = _validate_slots(&tpl, addr);
  if errs.len() > 0 {
    let first: Str = errs[0];
    return _render_err(first);
  }
  return _render_ok(_join_slots(&tpl, addr));
}

/// Validate an address against a country's template without rendering it.
/// Params: country - template selector as in address_render (empty falls back
/// to addr.country_code); addr - the address input.
/// Returns: an error list in template (render) order, empty when the address
/// has every required field. An unknown country yields exactly one entry,
/// "address: unknown country: <CODE>"; each absent required field yields
/// "address: missing required field: <name>". Optional fields are never
/// errors, so the list is exactly the set of reasons address_render would
/// reject the same input.
/// Examples: address_validate("DE", no_postal) -> ["address: missing required
/// field: postal_code"].
/// Complexity: O(slots).
pub fn address_validate(country: Str, addr: &Address) -> Vec[Str] {
  let sel = _pick_country(country, addr);
  let tpl = _template(sel);
  let cc: Str = tpl.country_code;
  if cc.len() == 0 {
    var errs = Vec[Str].new();
    errs.push("address: unknown country: " + string.str_upper(sel));
    return errs;
  }
  return _validate_slots(&tpl, addr);
}

/// Field inventory of a country's template, in render order.
/// Params: country - ISO 3166-1 alpha-2 code, ASCII case-insensitive.
/// Returns: FieldInventory with parallel arrays names and required (1/0).
/// Both are empty for an unknown country.
/// Error case: none (unknown countries yield empty inventories).
/// Complexity: O(slots^2) in the worst case; the dataset is small and fixed.
pub fn address_fields(country: Str) -> FieldInventory {
  let tpl = _template(country);
  let fields: Vec[Int] = tpl.slot_field;
  let reqs: Vec[Int] = tpl.slot_required;
  var names = Vec[Str].new();
  var required = Vec[Int].new();
  var seen = Vec[Int].new();
  let n = fields.len();
  var i = 0;
  while i < n {
    let code: Int = fields[i];
    var dup = false;
    var j = 0;
    while j < seen.len() {
      let prior: Int = seen[j];
      if prior == code { dup = true; }
      j = j + 1;
    }
    if !dup {
      seen.push(code);
      names.push(_field_name(code));
      let r: Int = reqs[i];
      required.push(r);
    }
    i = i + 1;
  }
  return FieldInventory{ names: names; required: required };
}

/// The raw template record for a country (parallel slot arrays; see
/// AddressTemplate). Unknown countries return the empty missing template with
/// country_code "".
/// Error case: none.
/// Complexity: O(slots).
pub fn address_template(country: Str) -> AddressTemplate {
  return _template(country);
}

/// True when a country code has a template in the embedded dataset.
/// Params: country - ISO 3166-1 alpha-2 code, ASCII case-insensitive.
/// Returns: Bool.
/// Error case: none.
/// Complexity: O(1) comparisons over the 12-entry if-chain.
pub fn address_supports(country: Str) -> Bool {
  let tpl = _template(country);
  let cc: Str = tpl.country_code;
  return cc.len() > 0;
}

/// Canonical field name for a field code (see AddressTemplate.slot_field).
/// Params: code - a field code; codes outside the dataset are accepted.
/// Returns: "name", "organization", "street1", "street2", "city", "region",
/// "postal_code", "country_code", or "unknown".
/// Error case: none.
/// Complexity: O(1).
pub fn address_field_name(code: Int) -> Str {
  return _field_name(code);
}

/// Number of countries in the embedded dataset.
/// Returns: 12.
/// Error case: none.
/// Complexity: O(1).
pub fn address_country_count() -> Int {
  return 12;
}

/// ISO 3166-1 alpha-2 codes of every country in the dataset, sorted.
/// Returns: Vec[Str] of 12 codes.
/// Error case: none.
/// Complexity: O(1).
pub fn address_countries() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("AU");
  v.push("BR");
  v.push("CA");
  v.push("CN");
  v.push("DE");
  v.push("FR");
  v.push("GB");
  v.push("IN");
  v.push("IT");
  v.push("JP");
  v.push("NL");
  v.push("US");
  return v;
}

/// One-line structural summary of a country's template, for tooling and
/// debugging: "<CC>: <slots> slots, <lines> lines".
/// Params: country - template selector as in address_render (no address
/// fallback; the argument is used as given).
/// Returns: the summary, or "address: unknown country: <CODE>" for a code not
/// in the dataset.
/// Error case: none.
/// Complexity: O(slots).
pub fn address_template_summary(country: Str) -> Str {
  let tpl = _template(country);
  let cc: Str = tpl.country_code;
  if cc.len() == 0 {
    return "address: unknown country: " + string.str_upper(country);
  }
  let fields: Vec[Int] = tpl.slot_field;
  let lines: Vec[Int] = tpl.slot_line;
  let slots = fields.len();
  var line_count: Int = 0;
  var i = 0;
  while i < lines.len() {
    let ln: Int = lines[i];
    if ln >= line_count { line_count = ln + 1; }
    i = i + 1;
  }
  return cc + ": " + convert.int_to_string(slots) + " slots, " + convert.int_to_string(line_count) + " lines";
}
