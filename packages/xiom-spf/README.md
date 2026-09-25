# xiom.spf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parsing and canonical emitting of one in-memory SPF record (the
> RFC 7208 syntax subset described in `SPEC.md`); no DNS lookups, no
> evaluation, no DNS TXT framing.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder`,
> `xiom.string.compare.str_compare_ignore_case` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Overview

`xiom.spf` is a small, dependency-free codec for the documented SPF subset:

- the `v=spf1` version section (ASCII case-insensitive);
- mechanisms `all`, `include:<domain>`, `a[:domain][/cidr]`,
  `mx[:domain][/cidr]`, `ip4:<addr>[/cidr]`, `ip6:<addr>[/cidr]`,
  `ptr[:domain]` (parsed but discouraged by RFC 7208) and `exists:<domain>`;
- the four qualifiers `+ - ~ ?` (the default `+` is stored and omitted when
  emitting);
- modifiers `redirect=<domain>`, `exp=<domain>` and any other `name=value`,
  each name allowed once (case-insensitive);
- `%{...}` macros passed through verbatim after `spf_macro_valid` accepts
  them (`%%`, `%_` and `%-` escapes included);
- CIDR lengths validated as canonical decimals in 0..32 (a/mx/ip4) and
  0..128 (ip6);
- unknown mechanisms, malformed terms and malformed macros rejected with
  deterministic `Err("spf: ...")` messages.

A parsed record is a flat set of parallel vectors (`kind`, `qualifier`,
`value`, `cidr`, `is_modifier`) with accessors and a `spf_find_modifier`
lookup, because `Vec[StructType]` is not usable in this compiler. The emitter
produces canonical single-space text and `spf_parse(spf_emit(r))` round-trips
every parsed record.

## Quick start

```xi
use xiom.spf;
use xiom.io;

fn main() -> Int {
  let r = spf_parse("v=spf1 ip4:192.0.2.0/24 include:_spf.example.com -all");
  match r {
    Ok(d) => {
      io.println(spf_term_kind(&d, 0));          // ip4
      io.println(spf_term_value(&d, 0));         // 192.0.2.0
      io.println(spf_emit(&d));
      // v=spf1 ip4:192.0.2.0/24 include:_spf.example.com -all
      if spf_find_modifier(&d, "redirect") >= 0 {
        io.println("has a redirect");
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `spf_parse(record)` | `Result[Spf, Str]` | Parse one record; `Err("spf: ...")` on the catalogued errors. |
| `spf_new()` | `Spf` | An empty record (zero terms); emits `"v=spf1"`. |
| `spf_term_count(r)` | `Int` | Number of terms (mechanisms plus modifiers). |
| `spf_term_kind(r, i)` | `Str` | Canonical mechanism name or modifier name as written; `""` when out of range. |
| `spf_term_qualifier(r, i)` | `Str` | `"+"`, `"-"`, `"~"` or `"?"` for mechanisms, `""` for modifiers. |
| `spf_term_value(r, i)` | `Str` | Domain-spec, address or modifier value, verbatim. |
| `spf_term_cidr(r, i)` | `Int` | CIDR length, or `-1` when absent. |
| `spf_term_is_modifier(r, i)` | `Bool` | True when term `i` is a modifier. |
| `spf_find_modifier(r, name)` | `Int` | Index of a modifier by case-insensitive name, or `-1`. |
| `spf_macro_valid(s)` | `Bool` | The documented macro-shape predicate. |
| `spf_emit(r)` | `Str` | Canonical single-space text, no trailing space. |

Accessors never trap: an out-of-range index yields `""`, `-1` or `false`.

### Term model in one paragraph

Term `i` is a mechanism when `spf_term_is_modifier(r, i)` is false: its kind
is one of the eight canonical lowercase names, its qualifier defaults to
`"+"`, and its value is the domain-spec or address written after the `:` (or
`""`). It is a modifier when `spf_term_is_modifier(r, i)` is true: its kind
is the name as written before the `=`, its qualifier is `""`, and its value
is everything after the `=` (possibly `""` for non-redirect/exp modifiers). A
CIDR is stored as an `Int` in `0..32` or `0..128`, with `-1` meaning "no
CIDR".

## Error model

Every parse failure is `Err(msg)` with a deterministic message starting with
`"spf: "`:

| Message | Trigger |
|---|---|
| `spf: control byte in input` | C0 control byte (not SP/TAB), LF, CR or DEL anywhere |
| `spf: missing version` | empty input, or a first token that does not start with `v=` |
| `spf: wrong version: <token>` | a first token that starts with `v=` but is not `v=spf1` |
| `spf: empty term: <term>` | a term that is only a qualifier, or whose name is empty |
| `spf: unknown mechanism: <term>` | a name that is not one of the eight mechanisms |
| `spf: bad mechanism syntax: <term>` | unexpected value/CIDR, or a missing required value |
| `spf: bad cidr: <term>` | a CIDR outside 0..32 / 0..128 or not a canonical decimal |
| `spf: bad macro: <term>` | a `%` that does not start a well-formed macro |
| `spf: duplicate modifier: <name>` | the same modifier name twice (case-insensitive) |
| `spf: bad modifier: <term>` | a qualifier before `=`, or empty `redirect=`/`exp=` |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.spf
```

Expected tail: 26 `[PASS]` lines, `xiom.spf: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Install / publish

```
xiom pkg install xiom.spf@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations

- No DNS lookups and no evaluation: `include`, `redirect` and `exp` are
  parsed, stored and re-emitted, never followed; there is no recursion, no
  lookup limit and no result computation.
- No DNS TXT framing: the caller supplies the already-concatenated record
  string; multiple strings, size limits and record selection are out of
  scope.
- `ip4`/`ip6` addresses are stored verbatim: no address-syntax validation
  (only the CIDR length is checked), no normalisation.
- Only the RFC 7208 syntax subset in `SPEC.md`: dual CIDR lengths
  (`/24//64`), `exp` explanation strings, DNSBL-style reversed domains and
  vendor extensions are not modelled.
- Macro shape is checked, never expanded: `%{p}` etc. stay verbatim.
- Every modifier name is single-instance; RFC 7208 only requires that for
  `redirect` and `exp`, so records repeating an unknown modifier are rejected
  here.
- Canonical emit rewrites mechanism names to lowercase, drops comments and
  spacing from the source, and omits the default `+`; modifier names and
  values, domains and addresses are kept verbatim.
- Errors carry the offending token, not a column number.

See `SPEC.md` for the full grammar, decisions, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
