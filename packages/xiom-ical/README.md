# xiom.ical

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** RFC 5545-**subset** iCalendar codec: CRLF folding/unfolding,
> content lines with parameters, TEXT escaping, BEGIN/END component trees
> (VCALENDAR / VEVENT and any nesting they contain), first-match property
> lookup, and a minimal VCALENDAR/VEVENT builder; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.ical` treats an iCalendar stream as text. `ical_parse` unfolds the
stream, reads every content line `NAME;PARAM=VAL:value`, and builds a flat
component tree: `BEGIN:VCALENDAR` / `END:VCALENDAR` pairs (and any nested
`BEGIN`/`END` component, such as `VEVENT` or `VALARM`) become components,
while the other content lines become the components' properties. Names are
compared case-insensitively and stored lowercased; values and parameter
values are stored **raw**, with TEXT escapes still in them, so
`ical_serialize` can reproduce the input byte-for-byte. `ical_get_text`
returns the TEXT-decoded form.

Date-time values (`DTSTART`, `DTEND`, `DTSTAMP`, ...) stay `Str`; the module
never converts them to numbers, never expands `RRULE`, and never interprets
`VTIMEZONE`/`TZID`. See Limitations.

## API

| Function | Returns | Description |
|---|---|---|
| `ical_parse(text)` | `Result[Ical, Str]` | Parse a whole stream; `Err("ical: ...")` on malformed input. |
| `ical_unfold(text)` | `Str` | Remove folds: each line break + one SP/TAB disappears. |
| `ical_escape_text(s)` | `Str` | Escape `\`, `;`, `,`, newline for a TEXT value. |
| `ical_unescape_text(s)` | `Str` | Decode `\\`, `\;`, `\,`, `\n`/`\N`; unknown escapes kept. |
| `ical_component_count(c)` | `Int` | Number of components. |
| `ical_root_count(c)` | `Int` | Number of top-level components. |
| `ical_root(c, i)` | `Int` | Index of the i-th top-level component, or -1. |
| `ical_component_name(c, comp)` | `Str` | Lowercased component name ("" when out of range). |
| `ical_component_parent(c, comp)` | `Int` | Parent index; -1 = top level, -2 = out of range. |
| `ical_child_count(c, comp)` | `Int` | Direct children (-1 addresses the top level). |
| `ical_child(c, comp, i)` | `Int` | Index of the i-th direct child, or -1. |
| `ical_find_child(c, comp, name)` | `Int` | First direct child named `name` (case-insensitive), or -1. |
| `ical_prop_count(c, comp)` | `Int` | Direct properties of a component. |
| `ical_prop_name(c, comp, i)` | `Str` | Lowercased name of the i-th property. |
| `ical_prop_value(c, comp, i)` | `Str` | Raw value of the i-th property (escapes preserved). |
| `ical_prop_value_text(c, comp, i)` | `Str` | TEXT-decoded value of the i-th property. |
| `ical_find_prop(c, comp, name)` | `Int` | Pool index of the first property named `name`, or -1. |
| `ical_get(c, comp, name)` | `Option[Str]` | Raw value of the first property named `name`; first match wins. |
| `ical_get_text(c, comp, name)` | `Option[Str]` | TEXT-decoded value of the first property named `name`. |
| `ical_prop_param_count(c, comp, i)` | `Int` | Parameters of the i-th property. |
| `ical_prop_param_name(c, comp, i, j)` | `Str` | Lowercased name of parameter `j`. |
| `ical_prop_param_value(c, comp, i, j)` | `Str` | Verbatim parameter value (quotes kept). |
| `ical_new()` | `Ical` | Empty stream. |
| `ical_add_component(c, parent, name)` | `Int` | Append a component; -1 on invalid name/parent. |
| `ical_add_prop(c, comp, name, value)` | `Bool` | Append a raw property; false on invalid input. |
| `ical_add_text_prop(c, comp, name, text)` | `Bool` | Append a TEXT property, escaping `text` first. |
| `ical_build_event(uid, dtstamp, dtstart, dtend, summary, description, location)` | `Ical` | Minimal VCALENDAR + one VEVENT with those seven properties. |
| `ical_serialize(c)` | `Str` | CRLF text, unfolded, names uppercased. |
| `ical_serialize_folded(c)` | `Str` | Same, folded to at most 75 octets per physical line. |

Property lookups only see a component's **direct** properties: children are
searchable through `ical_child` / `ical_find_child`. The first property with
a matching name in document order wins; duplicates are reachable through
`ical_prop_count` / `ical_prop_name` / `ical_prop_value`.

## Usage

```xi
use xiom.ical;
use xiom.io;

fn main() -> Int {
  let r = ical_parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Standup\\, 09:00\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n");
  match r {
    Ok(c) => {
      let cal = ical_root(&c, 0);          // 0
      let ev  = ical_find_child(&c, cal, "VEVENT");
      match ical_get_text(&c, ev, "SUMMARY") {
        Some(title) => { io.println(title); },  // Standup, 09:00
        None => {},
      }
      io.println(ical_serialize(&c));       // canonical CRLF text
    },
    Err(e) => { io.println(e); },
  }

  let built = ical_build_event("uid-1@example.com", "20260925T090000Z",
    "20260925T100000Z", "20260925T110000Z", "Planning", "Agenda:\n1. Budget", "Room 4");
  io.println(ical_serialize_folded(&built));
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ical
```

Expected tail: 22 `[PASS]` lines, `xiom.ical: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Subset only.** The grammar covers unfolding, content lines with
  parameters, TEXT escaping, and BEGIN/END nesting. There is no RFC 6868
  caret-encoding (`^'`, `^^`, ...), no parameter unquoting (a quoted
  parameter value keeps its quotes), no group syntax (`group.NAME`), and no
  validation of property/component semantics (unknown components round-trip
  unchanged).
- **Values stay strings.** `DTSTART`, `DTEND`, `DTSTAMP`, `DURATION`,
  `TRIGGER`, ... are never parsed into dates, times or epochs.
- **No recurrence or time-zone arithmetic.** `RRULE` is not expanded and
  `VTIMEZONE` / `TZID` are inert data.
- **No calendar semantics.** No validation of required properties, no
  UID uniqueness, no `SEQUENCE`/`STATUS` interpretation, no scheduling.
- **Tolerant line endings.** CRLF, LF and lone CR all terminate lines on
  input; output always uses CRLF. Blank and whitespace-only lines are
  skipped. This is more permissive than RFC 5545.
- **Strict parameter quoting.** A `:` inside a quoted parameter value is
  protected, but a `:` inside an unquoted one ends the structural part of the
  line (as the grammar requires).
- **Escaping rules.** `ical_escape_text` also turns CR (including the CR of a
  CRLF pair) into `\n`. `ical_unescape_text` keeps unknown escapes such as
  `\q` byte-for-byte instead of rejecting or dropping them.
- **Builder limits.** `ical_add_prop` stores values verbatim and rejects
  values containing CR/LF; use `ical_add_text_prop` for TEXT values. The
  builder emits parameter-free properties.
- **Errors carry no line/column positions.**

See `SPEC.md` for the exact grammar, the error catalog and the test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
