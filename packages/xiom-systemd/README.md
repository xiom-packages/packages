# xiom.systemd

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** systemd unit-file parsing and emitting for in-memory `Str`
> documents; no directive semantics, no drop-ins, no process management.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.builder.sb_push_str`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test`,
> `xiom.io` and `xiom.convert`.

## Scope

`xiom.systemd` parses a systemd unit file into a flat `Unit` (distinct section
names plus parallel `sec_starts`/`sec_counts` range vectors and index-aligned
`keys`/`values` vectors), supports indexed lookup, and emits the document back
in a canonical form. Section names and keys are byte-exact and case-sensitive.
Duplicate keys are preserved in document order, so `unit_get` returns the
first assignment and `unit_get_last` the last. A repeated `[Section]` header
reopens that section; its entries always stay in one contiguous range.
Continuation lines (a trailing `\`) are joined with no inserted separator, and
`#`/`;` comment markers are only recognised at the start of a line. Malformed
lines, keys before any section, bad headers, missing `=` and C0 control bytes
return `Err("systemd: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `unit_parse(text)` | `Result[Unit, Str]` | Parse a whole unit file; `Err("systemd: ...")` on the documented error catalog. |
| `unit_section_count(u)` | `Int` | Number of distinct sections (repeated headers count once). |
| `unit_key_count(u)` | `Int` | Total entries across all sections, duplicates included. |
| `unit_section_index(u, name)` | `Int` | First-seen index of a section name, or `-1`. |
| `unit_section_name(u, index)` | `Option[Str]` | Section name at `index`; `None` out of range. |
| `unit_section_key_count(u, index)` | `Int` | Entries in the section at `index`; `-1` out of range. |
| `unit_section_keys(u, index)` | `Vec[Str]` | Keys of that section in entry order (a fresh copy). |
| `unit_section_value_at(u, section, key)` | `Option[Str]` | Value of the `key`-th entry of a section index; `None` out of range. |
| `unit_key_at(u, index)` | `Option[Str]` | Key at flat entry index; `None` out of range. |
| `unit_value_at(u, index)` | `Option[Str]` | Value at flat entry index, aligned with `unit_key_at`. |
| `unit_get(u, section, key)` | `Option[Str]` | First value of the pair; `None` when absent. |
| `unit_get_last(u, section, key)` | `Option[Str]` | Last value of the pair; `None` when absent. |
| `unit_emit(u)` | `Str` | Canonical text: `[Name]` groups, one `Key=Value` line each, one blank line between sections, no trailing LF. |

## Usage

```xi
use xiom.systemd;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let text = "[Unit]\nDescription=Demo\nAfter=network.target\n\n[Service]\nExecStart=/bin/echo one \\\n  two\n";
  let r = unit_parse(text);
  match r {
    Ok(unit) => {
      match unit_get(&unit, "Service", "ExecStart") {
        Some(cmd) => { io.println(cmd); },   // /bin/echo one   two
        None => {},
      }
      io.println(convert.int_to_string(unit_section_count(&unit)) + " sections");
      io.println(unit_emit(&unit));
      // [Unit]
      // Description=Demo
      // After=network.target
      //
      // [Service]
      // ExecStart=/bin/echo one   two
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Error model

`unit_parse` is the only function that can fail, and it never panics on
malformed text: it returns `Err(message)` with a deterministic message that
starts with `"systemd: "`. The full catalog (line text included) is in
`SPEC.md` section 6:

| Message prefix | Trigger |
|---|---|
| `systemd: control byte 0x..` | C0 control byte other than TAB/LF, or a lone CR |
| `systemd: key before any section` | a `Key=Value` line before the first `[Section]` |
| `systemd: malformed section header` | `[` missing, junk after `]`, or a byte outside `A-Za-z0-9_.-` |
| `systemd: empty section name` | `[]` |
| `systemd: empty key in line` | `=value`, `   =` |
| `systemd: malformed key in line` | a key containing SP or TAB |
| `systemd: line without '='` | non-blank, non-comment line with no `=` |
| `systemd: continuation at end of input` | a trailing `\` on the final physical line |

Accessors and `unit_emit` are total: out-of-range indices return `None`/`-1`/
an empty vector, and a drifted hand-built `Unit` is clamped rather than read
out of bounds.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.systemd
```

Expected tail: 20 `[PASS]` lines, `xiom.systemd: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- No directive semantics: values are opaque byte runs. `ExecStart=`, `After=`,
  `Environment=` and every other key are not validated, split or interpreted.
- No drop-ins, no `systemctl` integration, no process management; the module
  is pure in-memory `Str` parsing.
- No specifier expansion (`%i`, `%n`, `${VAR}` are literal data).
- Comments are not preserved on emit, and continuation joins are not
  reconstructed: emit writes each section's `Key=Value` lines verbatim.
- A `#` or `;` is a comment marker at the start of a line only; elsewhere it
  is ordinary data. Inline comments are never stripped.
- Only one trailing `\` style of continuation is supported; the marker is
  removed and the next physical line is appended with no separator. A
  trailing `\` on the final physical line is an error.
- Keys must not contain SP or TAB; a value keeps trailing whitespace and may
  be empty. Leading value whitespace is trimmed.
- CR is only valid as part of a CRLF pair; a lone CR is a control-byte error.
  NUL cannot be represented in an XIOM `Str` and therefore never round-trips.
- `unit_emit` and the accessors clamp a hand-built, internally drifted `Unit`,
  but they do not repair it: build `Unit` values with `unit_parse` or keep
  `sec_starts`, `sec_counts`, `keys` and `values` consistent.
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, decisions, error strings and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
