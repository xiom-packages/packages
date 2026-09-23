# xiom.typography

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Typographic prettification of plain text: smart quotes, dashes,
> ellipsis, spacing.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## Scope

`xiom.typography` turns ASCII typing conventions into typographic
punctuation, byte-wise and without any locale data:

- straight quotes `'` `"` into curly quotes (with apostrophes handled),
- hyphen runs into en/em dashes,
- `...` into a single ellipsis character,
- runs of spaces/tabs into one space while preserving line structure.

All Unicode output is emitted as explicit UTF-8 byte sequences through
`xiom.string.builder`; nothing is delegated to FFI or OS text services. See
`SPEC.md` for the rules, the context and byte-sequence tables, and the test
plan.

## API

| Function | Returns | Description |
|---|---|---|
| `typography_smart_quotes(s)` | `Str` | `'`/`"` become curly quotes: opening after start-of-string, whitespace, `([{<` or a dash; otherwise closing (so `don't` becomes `don’t`). |
| `typography_smart_dashes(s)` | `Str` | Longest match first: `---` becomes an em dash, `--` an en dash. |
| `typography_ellipsis(s)` | `Str` | `...` becomes U+2026; a fourth dot stays literal. |
| `typography_collapse_spaces(s)` | `Str` | Runs of spaces/tabs become one space; LF and CR are preserved and nothing is trimmed. |
| `typography_smart(s)` | `Str` | Full pipeline: ellipsis, then dashes, then quotes, then space collapsing. |

All functions are total (no error channel) and O(n) over the input bytes.

## Usage

```xi
use xiom.typography;
use xiom.io;

fn main() -> Int {
  io.println(typography_smart("\"Well...\" -- it's \"fine\""));
  // “Well…” – it’s “fine”
  return 0;
}
```

Single steps compose the same way:

```xi
io.println(typography_smart_dashes("a---b--c"));   // a—b–c
io.println(typography_ellipsis("wait..."));        // wait…
io.println(typography_collapse_spaces("a  \t b")); // a b
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.typography
```

Expected tail: 20 `[PASS]` lines, `xiom.typography: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- ASCII quote detection heuristics: quote direction is decided only by the
  preceding byte (start, whitespace, `( [ { <` or a dash); there is no pairing
  state, sentence context or language model, so unusual quoting can be
  classified the wrong way (e.g. a quote directly after a closing quote).
- No locale awareness: the same substitutions apply to every input; there is
  no German/French/typographer's-quote variant, no unit spacing, no
  dash-vs-hyphen linguistic analysis.
- No Unicode normalization or validity checking; input is treated as opaque
  UTF-8 bytes and passes through byte-exact apart from the ASCII triggers.
- Nested markup is not understood: quote characters inside code, HTML, URLs
  or file paths are converted like any other text.
- `typography_collapse_spaces` also collapses intended column alignment
  (only LF/CR boundaries are preserved).

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
