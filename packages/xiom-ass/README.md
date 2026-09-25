# xiom.ass

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a strict, in-memory ASS/SSA subtitle codec for a documented
> subset: flat section storage, Format-driven field rows, `h:mm:ss.cc`
> centisecond timestamps, raw Text capture, accessors, and a canonical
> emitter.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.byte_at` and `xiom.string.compare.str_compare`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.ass` parses an Advanced SubStation Alpha (ASS/SSA) document held in
memory as an `Str` into a flat `Ass` value and serializes it back
canonically. It validates the documented subset strictly and round-trips
canonical documents `parse -> format -> parse`.

What it handles:

- sections `[Script Info]`, `[V4+ Styles]`, `[V4 Styles]`, `[Events]` and
  any other `[name]` section (preserved raw, line by line);
- `[Script Info]` `key: value` pairs (`;` comment lines are skipped), with
  first-match lookup by key;
- a `Format:` declaration followed by `Style:` rows in V4/V4+ styles
  sections, with the field count validated per row;
- a `Format:` declaration followed by `Dialogue:` and `Comment:` rows in
  `[Events]`; when no Format line is present the documented default mapping
  (Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text)
  applies;
- timestamps `h:mm:ss.cc` (one hour digit, two digits for minutes, seconds
  and centiseconds);
- the last declared field of a row captured raw to the end of the line, so
  commas inside Text, `\N`/`\n` escapes and `{...}` override blocks are
  preserved exactly;
- CRLF and LF documents (both parse to the same value; output is LF).

It intentionally does **not** render styles, interpret override tags, parse
font attachments, or apply SSA v4 semantics beyond each section's own Format
declaration -- see Limitations and `SPEC.md` for the exact policies.

## Install / use

```
xiom pkg install xiom.ass@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Quick start:

```xi
use xiom.ass;
use xiom.io;

fn main() -> Int {
  let doc = "[Script Info]\nTitle: Demo\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,Hello, world!\n";
  let r = ass_parse(doc);
  if !r.is_ok {
    io.println(r.error);
    return 1;
  }
  let a = r.value;
  io.println(ass_event_count(&a));             // 1
  io.println(ass_event_text(&a, 0));           // Hello, world!
  io.println(ass_event_start_cs(&a, 0));       // 100
  io.println(ass_format_timestamp(372345));    // 1:02:03.45
  io.println(ass_event_style(&a, 0));          // Default
  io.println(ass_format(&a));                  // canonical document
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `ass_parse(text)` | `Result[Ass, Str]` | Parse a whole document (LF/CRLF). |
| `ass_format(a)` | `Str` | Canonical serialization: section kind order, LF, raw lines verbatim. |
| `ass_parse_timestamp(t)` | `Result[Int, Str]` | Parse one `h:mm:ss.cc` timestamp to centiseconds. |
| `ass_format_timestamp(cs)` | `Str` | Canonical timestamp text for `cs` (negative clamps to zero). |
| `ass_section_count(a)` | `Int` | Number of sections. |
| `ass_section_name(a, i)` | `Str` | Section name; `""` out of range. |
| `ass_section_kind(a, i)` | `Int` | 0 Script Info, 1 styles, 2 Events, 3 other; `-1` out of range. |
| `ass_section_line_count(a, i)` | `Int` | Raw lines of section `i`; `0` out of range. |
| `ass_section_line(a, i, j)` | `Str` | Raw line `j` of section `i`; `""` out of range. |
| `ass_format_field_count(a, sec)` | `Int` | Declared Format fields (10 for a default Events section); `0` when none. |
| `ass_format_field(a, sec, j)` | `Str` | Declared field name `j`; `""` out of range. |
| `ass_info_count(a)` | `Int` | Script Info key/value pairs. |
| `ass_info_key(a, i)` | `Str` | Key of pair `i`; `""` out of range. |
| `ass_info_value(a, i)` | `Str` | Value of pair `i`; `""` out of range. |
| `ass_info_value_by_key(a, key)` | `Str` | First pair whose key equals `key`; `""` when absent. |
| `ass_style_count(a)` | `Int` | Style rows across all styles sections. |
| `ass_style_field_count(a, i)` | `Int` | Fields of Style row `i`; `0` out of range. |
| `ass_style_field_at(a, i, j)` | `Str` | Field `j` of Style row `i`; `""` out of range. |
| `ass_style_field(a, i, name)` | `Str` | First field named `name`; `""` when absent. |
| `ass_event_count(a)` | `Int` | Dialogue plus Comment rows. |
| `ass_dialogue_count(a)` | `Int` | Dialogue rows. |
| `ass_comment_count(a)` | `Int` | Comment rows. |
| `ass_event_kind(a, i)` | `Int` | 0 Dialogue, 1 Comment; `-1` out of range. |
| `ass_event_field_count(a, i)` | `Int` | Fields of event `i`; `0` out of range. |
| `ass_event_field_at(a, i, j)` | `Str` | Field `j` of event `i`, verbatim; `""` out of range. |
| `ass_event_field(a, i, name)` | `Str` | First field named `name`; `""` when absent. |
| `ass_event_start_cs(a, i)` | `Int` | Parsed start in centiseconds; `-1` out of range or no Start field. |
| `ass_event_end_cs(a, i)` | `Int` | Parsed end in centiseconds; `-1` out of range or no End field. |
| `ass_event_text(a, i)` | `Str` | First field named Text, raw; `""` when absent. |
| `ass_event_style(a, i)` | `Str` | First field named Style; `""` when absent. |

## Format rules

- A section's first `Format:` line declares the field names (trimmed,
  comma-separated, non-empty). Declaring none or an empty name, or declaring
  a second `Format:` line in the same section, is `ass: bad Format`.
- `Style:`, `Dialogue:` and `Comment:` rows are split into exactly as many
  fields as the declaration has names. All fields except the last are
  trimmed of spaces/tabs; the last declared field is captured raw to the end
  of the line, so commas inside it are preserved.
- A row with fewer commas than the declaration is `ass: field count
  mismatch`.
- `Start` and `End` are found by name (first match) and validated as
  timestamps; a Format without those names disables timestamp parsing for
  that section and the time accessors return `-1`.
- A `Style:` row before its section's `Format:` line (or in a styles section
  with no Format line) is `ass: style before Format`. A `Dialogue:` or
  `Comment:` row before its section's Format line is `ass: dialogue before
  Format` / `ass: comment before Format`. When an `[Events]` section has no
  Format line at all, the documented default mapping applies to every row.
- V4 and V4+ styles sections are treated identically; the Format line is the
  only field mapping.

## Section rules

- A line whose first byte is `[` starts a section. The name between the first
  `[` and the first `]` is trimmed; it must be non-empty and only spaces/tabs
  may follow the `]`. A missing `]` is `ass: unterminated section name`;
  an empty name or trailing text is `ass: bad section name`.
- Known names are case-sensitive: `Script Info`, `V4+ Styles`, `V4 Styles`
  and `Events`; any other name is an "other" section preserved raw.
- Every non-header line of every section is stored verbatim, in order. A
  document must contain an `[Events]` section; multiple sections of the same
  kind are allowed and aggregate in document order.
- `[Script Info]` lines must be `key: value` (or `;` comments or blank);
  keys and values are trimmed for the accessors while the raw line is kept.

## Timestamp rules

Accepted form (byte-exact, no surrounding whitespace):

```
h:mm:ss.cc       one hour digit 0..9, two-digit minutes/seconds 00..59,
                 two-digit centiseconds 00..99, dot separator
```

Centiseconds are `h*360000 + mm*6000 + ss*100 + cc`. Minutes or seconds
above 59 are `ass: timestamp out of range`, distinct from
`ass: bad timestamp shape` (wrong length, digits or separator; a two-digit
hour such as `00:00:00.00` is a bad shape). Canonical output prints the hour
without padding (`0:00:00.00`, `9:59:59.99`); values at or above 10 hours
print with more hour digits and do not re-parse.

## Canonical output

`ass_format` writes sections in the documented kind order (Script Info,
styles, Events, other), preserving document order inside each kind; each
header is `[name]` with the stored trimmed name, and every stored raw line is
written verbatim followed by LF. Nothing is renumbered or reformatted: rows,
field spacing, field values and timestamps keep their stored bytes. CRLF is
normalized to LF, blank lines before the first section are dropped, and
section order is canonicalized; an input already in canonical order and LF
round-trips byte-exactly.

## Error model

All failures are `Err(message)` with an `"ass: "` prefix and no line numbers:

| Message | Raised when |
|---|---|
| `ass: control byte` | The input holds a C0 control other than TAB/LF/CR, or DEL (0x7F). |
| `ass: empty input` | The document has no sections (empty or blank lines only). |
| `ass: text before first section` | A non-blank line appears before the first `[section]`. |
| `ass: unterminated section name` | A `[` line has no closing `]`. |
| `ass: bad section name` | The name is empty or non-space/tab bytes follow the `]`. |
| `ass: missing [Events]` | The document has no `[Events]` section. |
| `ass: bad Format` | Empty or gapped Format declaration, or a second Format line in one section. |
| `ass: bad script info line` | A Script Info line is neither blank, a `;` comment nor `key: value` with a non-empty key. |
| `ass: style before Format` | A Style row precedes (or has no) Format declaration in its section. |
| `ass: dialogue before Format` | A Dialogue row precedes its Events section's Format line. |
| `ass: comment before Format` | A Comment row precedes its Events section's Format line. |
| `ass: field count mismatch` | A row has fewer commas than its Format declaration has fields. |
| `ass: bad timestamp shape` | A Start/End field is not exactly `h:mm:ss.cc` with the documented digits. |
| `ass: timestamp out of range` | A Start/End field has minutes or seconds above 59. |
| `ass: unexpected line` | Any other non-blank line inside a structured section (known kinds 0-2). |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ass
```

Expected tail: 23 `[PASS]` lines, `xiom.ass: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Whole document only**: no streaming or incremental parsing.
- **No interpretation**: styles are never rendered, `{...}` override blocks
  and `\N`/`\n` escapes stay raw bytes, font/image attachments are not
  parsed (their sections are preserved raw).
- **Strict timestamps**: exactly one hour digit and two digits per smaller
  field; times at or above 10 hours format but do not re-parse.
- **Last field is raw**: only the last declared field keeps commas; a Format
  that puts Text before another field changes what the raw capture applies
  to.
- **Strict structured sections**: non-blank lines that are not Format/row
  declarations (for example SSA `Picture:`, `Sound:` or `Movie:` events) are
  `ass: unexpected line`; only Dialogue and Comment are documented.
- **Bracket lines always start sections**: an "other" section cannot contain
  a line beginning with `[`.
- **Blank means zero bytes**: a whitespace-only line is content, not a
  separator (it is an error in structured sections).
- **No BOM handling**: a leading UTF-8 BOM makes the first line fail.
- Errors carry no line/column numbers.

See `SPEC.md` for the full grammar, decisions, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
