# xiom.humanize

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** human-readable rendering of byte counts, millisecond durations,
> counts, ordinals, and lists.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_string`).
> Tests additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.humanize` turns raw integers into the strings humans read in logs,
terminals and reports. It is pure integer arithmetic: no floating point, no
locale databases, no FFI, and every rule is pinned in `SPEC.md` so the output
is stable across platforms and versions.

## API

| Function | Returns | Description |
|---|---|---|
| `humanize_bytes(n, decimals, binary)` | `Str` | Byte count with unit suffix. `binary=true` uses 1024 (B, KiB, MiB, GiB, TiB, PiB); `false` uses 1000 (B, KB, MB, GB, TB, PB). `decimals` is clamped to 0..3 and rounds half away from zero. |
| `humanize_duration_ms(ms)` | `Str` | Compact duration: `"850ms"`, `"45s"`, `"2m 5s"`, `"1h 3m"`, `"2d 4h"`; non-positive input is `"0ms"`; a zero trailing component is omitted. |
| `humanize_count(n, singular, plural_form)` | `Str` | `"1 item"`, `"2 items"`, `"-1 item"`, `"0 items"`; the magnitude 1 selects `singular`. |
| `humanize_ordinal(n)` | `Str` | `"1st"`, `"2nd"`, `"3rd"`, `"4th"`, `"11th"`, `"21st"`, `"101st"`, `"111th"`; negatives keep the sign (`"-21st"`). |
| `humanize_list(items, conjunction)` | `Str` | `""` (empty), the item (one), `"a and b"` (two), `"a, b and c"` (three+); the conjunction word is used verbatim and the Oxford comma is omitted. |

## Usage

```xi
use xiom.humanize;
use xiom.io;

fn main() -> Int {
  io.println(humanize_bytes(1500000, 1, false));  // 1.5 MB
  io.println(humanize_bytes(2048, 0, true));      // 2 KiB
  io.println(humanize_duration_ms(125000));       // 2m 5s
  io.println(humanize_count(1, "item", "items")); // 1 item
  io.println(humanize_ordinal(21));               // 21st
  var items = Vec[Str].new();
  items.push("a");
  items.push("b");
  items.push("c");
  io.println(humanize_list(&items, "and"));       // a, b and c
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.humanize
```

Expected tail: 24 `[PASS]` lines, `xiom.humanize: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- The byte and duration rules are **opinionated and pinned**: decimals clamp
  to 0..3, the units are fixed (no `bits`, no custom suffixes), and durations
  use at most two components from the fixed stack ms/s/m/h/d.
- No locale support: output is always English-style ASCII (`KB`, `st`, `and`
  supplied by the caller); there are no translations, plural rules or decimal
  separators beyond `.`.
- Whole-value formatting only: `humanize_bytes` takes an integer byte count,
  and `humanize_duration_ms` takes an integer millisecond count.
- `humanize_list` performs no escaping and does not quote elements, so
  elements containing the conjunction are rendered as-is.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
