# xiom.formatter-fw

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.1` on the XIOM registry.
> **Scope:** a Wadler/Leijen-style pretty-printing framework over an explicit
> document model: text/line/softline/hardline/concat/nest/group/align nodes,
> greedy group fitting against an integer width, indentation tracking and a
> deterministic, total renderer.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.formatter-fw` packages the document algebra and the line-breaking
machinery of a pretty-printer, without any language-specific formatting
policy. A document is an arena (`FmtDoc`) of concrete nodes -- there are no
closures, no fn-pointer values and no `Vec[StructType]` -- so it is plain
data that one iterative renderer (`fmt_render`) lays out at a byte width.

Nine node kinds:

- `TEXT` -- verbatim bytes; its byte length is recorded once at build time.
- `LINE` -- break opportunity that is one space when flat.
- `SOFTLINE` -- break opportunity that is nothing when flat.
- `HARDLINE` -- unconditional break; a subtree containing it can never be
  flattened, so every enclosing group always breaks.
- `CONCAT` -- ordered pair.
- `NEST(n)` -- raise the indentation of line breaks inside the child by `n`.
- `GROUP` -- flatten the child when its fully flattened width fits the
  remaining width, otherwise break it.
- `ALIGN` -- set the indentation to the current column (the classic
  continuation-line idiom).
- `NIL` -- the empty document, the identity of `CONCAT`.

Every group decides **independently and greedily**: the fit test is the
group's own flat width against `width - column`, with an exact fit counting
as fitting. An outer group can break while an inner group on the same line
stays flat. `fmt_render_flat` flattens every flattenable group.

## Example

```xi
use xiom.formatter_fw;
use xiom.io;

fn main() -> Int {
  var g = fmt_doc_new();
  let open = fmt_text(&mut g, "call(");
  let a = fmt_text(&mut g, "alpha");
  let comma = fmt_text(&mut g, ",");
  let ln = fmt_line(&mut g);
  let b = fmt_text(&mut g, "beta)");
  let body = fmt_concat(&mut g, a, fmt_concat(&mut g, comma, fmt_concat(&mut g, ln, b)));
  let doc = fmt_group(&mut g, fmt_concat(&mut g, open, fmt_nest(&mut g, body, 4)));
  io.println(fmt_render(&g, doc, 80));  // "call(alpha, beta)"
  io.println(fmt_render(&g, doc, 8));   // "call(alpha,\n    beta)"
  return 0;
}
```

## API

Construction (`g` is `&mut FmtDoc`; each returns the new node index). All
builders push to all seven parallel vectors through one private push site, so
the arena cannot drift:

| Function | Node | Semantics |
|---|---|---|
| `fmt_doc_new()` | -- | Fresh empty arena. |
| `fmt_text(g, text)` | text | Verbatim payload; length and embedded-break flag recorded here. |
| `fmt_line(g)` | line | Space when flat, newline + indentation when broken. |
| `fmt_softline(g)` | softline | Nothing when flat, newline + indentation when broken. |
| `fmt_hardline(g)` | hardline | Always newline + indentation; blocks flattening. |
| `fmt_nil(g)` | nil | The empty document. |
| `fmt_concat(g, a, b)` | concat | `a` then `b`. |
| `fmt_nest(g, a, n)` | nest | Child `a` with indentation `max(0, indent + n)`. |
| `fmt_group(g, a)` | group | Child `a` flat when it fits, broken otherwise. |
| `fmt_align(g, a)` | align | Child `a` with indentation = current column. |
| `fmt_join(g, ids, sep)` | -- | Folds element nodes with `sep`: `[]` -> NIL, `[x]` -> `x`, else a left-nested concat chain. |

Introspection (range-safe, defaults on out-of-range indices): `fmt_node_count`,
`fmt_is_consistent` (all seven vectors same length), `fmt_node_kind`,
`fmt_node_text`, `fmt_text_len`, `fmt_text_has_break`, `fmt_node_indent`,
`fmt_node_child_a`, `fmt_node_child_b`, `fmt_kind_name`, `fmt_mode_name`,
`fmt_flat_width`.

Rendering:

| Function | Returns | Description |
|---|---|---|
| `fmt_render(g, root, width)` | `Str` | Render at `width` (clamped to `>= 0`) bytes; a group breaks when its flat width exceeds `width - column`; out-of-range nodes render empty. |
| `fmt_render_flat(g, root)` | `Str` | `fmt_render` with unbounded width: flattens every group except hardlines/embedded breaks. |

Constants: `FMT_KIND_NONE .. FMT_KIND_ALIGN` (0..9), `FMT_MODE_FLAT`,
`FMT_MODE_BREAK`, `FMT_WIDTH_INFINITE` (the never-flattens sentinel and
flat-width saturation bound) and `FMT_STEP_LIMIT` (the traversals' iteration
budget).

## Layout algorithm (summary)

The renderer walks the document with an explicit stack of `(indent, mode,
node)` triples, starting broken at indent 0, column 0. `TEXT` emits bytes and
advances the column; `LINE`/`SOFTLINE` emit a space/nothing flat or a newline
plus indentation when broken; `HARDLINE` always breaks; `CONCAT` pushes both
children; `NEST` raises the indent; `ALIGN` sets it to the column; a `GROUP`
is flattened exactly when `flat_width(child) <= width - column` and the flat
width is finite. `flat_width` is `TEXT` -> recorded byte length (`LINE` -> 1,
`SOFTLINE` -> 0, `CONCAT` -> sum, `NEST`/`GROUP`/`ALIGN` -> child) and is
`FMT_WIDTH_INFINITE` for any subtree containing a hardline or a text with an
embedded CR/LF. Both traversals pop exactly one work item per iteration (the
stack length is the single source of truth for progress) and are capped at
`FMT_STEP_LIMIT` pops as a totality guard. See `SPEC.md` for the full
statement and the complexity notes.

## Install / usage

The package is published on the XIOM registry; the consumer workflow is:

```
xiom pkg install xiom.formatter-fw@0.1.1
```

Alternatively, use it from this repository (the module is pure XIOM, no FFI):

```
use xiom.formatter_fw;
```

## Tests

From the repository root:

```
.\scripts\port.ps1 -Package xiom.formatter-fw
```

Expected tail: 23 `[PASS]` lines, `xiom.formatter-fw: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Layout engine only.** No parser, no token model, no language policy;
  callers build documents from their own constructs.
- **Byte widths.** Width is measured in bytes, not display columns; wide
  Unicode characters count as their UTF-8 byte length.
- **Local, greedy fitting.** A group is judged by its own flattened width, not
  by a lookahead over the rest of the line; an outer break never re-measures
  what follows.
- **Text is opaque.** Embedded CR/LF in a `TEXT` payload is emitted verbatim
  and is not indentation-managed; use `HARDLINE` for layout-owned breaks.
- **No styling.** No ANSI colors or terminal attributes.
- **Whole-document rendering.** The document is rendered to one `Str` in a
  single pass; there is no streaming or incremental rendering.
- **Worst-case complexity.** Rendering is O(nodes^2) when groups nest over
  each other, because each broken group scans its subtree for its flat width.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
