# xiom.formatter-fw -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.formatter_fw` (`src/formatter_fw.xi`). Pure XIOM, no FFI, no IO,
no `Vec[Float64]`, no `Vec[StructType]`, no closures, no fn-pointer values.

## 1. Scope

A deterministic, IO-free Wadler/Leijen-style pretty-printing framework:

- a concrete **document arena** (`FmtDoc`, seven parallel `Vec` fields) with
  nine node kinds: `NIL`, `TEXT`, `LINE`, `SOFTLINE`, `HARDLINE`, `CONCAT`,
  `NEST`, `GROUP`, `ALIGN`;
- a small builder API that returns node indices;
- a **greedy renderer** (`fmt_render`) that lays a document out at an integer
  page width, flattening each group whose flat width fits the remaining width
  and breaking the others;
- flat-width analysis (`fmt_flat_width`) with a single `FMT_WIDTH_INFINITE`
  sentinel for never-flattenable subtrees;
- documented, deterministic, total behavior: no traps, no unbounded loops,
  no shared mutable state between renders.

Widths are **byte counts**: `TEXT` contributes its recorded byte length,
`LINE` contributes 1, `SOFTLINE`/`NIL` contribute 0, and `HARDLINE` (or a text
embedding CR/LF) is never flattenable. No Unicode column widths are computed.

## 2. Non-goals

- Syntax-aware formatting of any language: this is the layout engine, not a
  parser or a style checker; callers build documents from their own tokens.
- ANSI styling, color and terminal control (see `xiom.format.ansi`).
- Unicode display width (East Asian wide characters count as their byte
  length).
- Incremental or streaming rendering; the whole document is rendered to a
  `Str` in one call.
- Source-text rewriting, idempotency checks and formatting diffs (the
  placeholder README mentioned `styles`/`rewrite`/`diff` libs; they are not
  part of this version).
- Line-length minimization beyond the greedy per-group criterion (no
  lookahead, no dynamic programming).

## 3. Values

```
FmtDoc = { kinds: Vec[Int]; texts: Vec[Str]; text_lens: Vec[Int];
           text_breaks: Vec[Int]; indents: Vec[Int];
           child_a: Vec[Int]; child_b: Vec[Int] }
```

Node `i` is fully described by index `i` in each of the seven parallel
vectors:

| Field | Used by | Meaning |
|---|---|---|
| `kinds[i]` | all | `FMT_KIND_*` (0..9). |
| `texts[i]` | TEXT | The verbatim payload (`""` otherwise). |
| `text_lens[i]` | TEXT | Byte length, recorded once at build time. |
| `text_breaks[i]` | TEXT | 1 when the payload embeds a CR (`0x0D`) or LF (`0x0A`) byte, else 0. |
| `indents[i]` | NEST | The indentation delta (may be negative). |
| `child_a[i]` | CONCAT, NEST, GROUP, ALIGN | First child index; `-1` when unused. |
| `child_b[i]` | CONCAT | Second child index; `-1` when unused. |

`_doc_push` is the single push site for all seven vectors, so lengths cannot
drift; `fmt_is_consistent(g)` is true iff all seven have equal length.
`fmt_node_kind/text/text_len/text_has_break/indent/child_a/child_b` are
range-safe with defaults (`FMT_KIND_NONE`, `""`, `0`, `false`, `0`, `-1`,
`-1`).

Kinds: `FMT_KIND_NONE=0`, `NIL=1`, `TEXT=2`, `LINE=3`, `SOFTLINE=4`,
`HARDLINE=5`, `CONCAT=6`, `NEST=7`, `GROUP=8`, `ALIGN=9`.
Modes: `FMT_MODE_FLAT=0`, `FMT_MODE_BREAK=1`.
Sentinels: `FMT_WIDTH_INFINITE=1073741823` (never-flattens width and
saturation bound); `FMT_STEP_LIMIT=1048576` (iteration budget of the two
document traversals; see section 5).

## 4. Node semantics

Let `indent` be the indentation of the current work item (0 for the root) and
`col` the current column (bytes emitted since the last newline, 0 at start).

| Kind | Flat width | FLAT rendering | BREAK rendering |
|---|---|---|---|
| `NIL` | 0 | nothing | nothing |
| `TEXT` | recorded byte length, or `FMT_WIDTH_INFINITE` when `text_breaks[i] == 1` | bytes verbatim; column += recorded length | bytes verbatim; column += recorded length |
| `LINE` | 1 | one space (`col += 1`) | one newline + `indent` spaces (`col = indent`) |
| `SOFTLINE` | 0 | nothing | one newline + `indent` spaces (`col = indent`) |
| `HARDLINE` | `FMT_WIDTH_INFINITE` | one newline + `indent` spaces (`col = indent`) | same |
| `CONCAT` | saturated sum of the children's flat widths | child_a then child_b, same indent/mode | same |
| `NEST(n)` | child's flat width | child with indent + n, same mode | same |
| `GROUP` | child's flat width | child with FLAT mode | child flat iff it fits (section 5), else child with BREAK mode |
| `ALIGN` | child's flat width | child with indent = `col` at the align node, same mode | same |

Notes:

- `NEST` clamps the resulting indentation at 0 (`max(0, indent + n)`).
- `ALIGN` uses the column reached when the align node itself is rendered;
  earlier siblings on the same line have already been emitted, later ones
  have not.
- A `TEXT` payload is always emitted byte-for-byte, even when it embeds
  CR/LF. The renderer does not insert indentation inside a text payload; it
  only adjusts the column to the bytes after the last CR/LF so subsequent
  width decisions are correct. Layout-owned line breaks must use
  `LINE`/`SOFTLINE`/`HARDLINE`.
- Out-of-range node indices (`< 0`, `>= fmt_node_count`) behave as `NIL`:
  they render nothing and have flat width 0.

## 5. Layout algorithm and fit conditions (as implemented)

`fmt_render(g, root, width)`:

1. Clamp `width` to `>= 0` (`w`). Initialize `col = 0` and an explicit work
   stack of `(indent, mode, node)` triples; push `(0, BREAK, root)`. The
   stack is held as three parallel `Vec[Int]` fields popped in lockstep:
   **each iteration pops exactly one work item**, so the stack length is the
   single source of truth for progress; a mismatched stack length also stops
   the walk. Both traversals are additionally capped at `FMT_STEP_LIMIT`
   (1,048,576) pops as an explicit progress guard; on exhaustion the
   traversal stops deterministically (`fmt_render` returns the text produced
   so far).
2. Pop one item. Dispatch on `fmt_node_kind`:
   - TEXT emits bytes and updates `col` (recorded length, or bytes after the
     last CR/LF when the text embeds a break);
   - LINE/SOFTLINE/HARDLINE emit per the table in section 4;
   - CONCAT pushes child_b then child_a, both with the current indent and
     mode, so child_a renders first;
   - NEST pushes the child with `max(0, indent + delta)`;
   - ALIGN pushes the child with `indent = col`;
   - GROUP: in FLAT mode the child is pushed FLAT. In BREAK mode let
     `fw = fmt_flat_width(g, child)`; the child is pushed **FLAT exactly
     when**
     `fw < FMT_WIDTH_INFINITE && fw <= w - col`,
     otherwise it is pushed BREAK. An exact fit (`fw == w - col`) counts as
     fitting. A `col` beyond `w` never fits (mixed layout simply overflows
     unbreakable text);
   - NIL / NONE / unknown kinds emit nothing.
3. The result is the concatenation of everything emitted, in order. There is
   no synthetic trailing newline; a trailing LINE/HARDLINE in BREAK mode does
   produce a trailing newline plus indentation.

`fmt_flat_width(g, node)` computes the fully flattened byte width with an
explicit stack under the same discipline (one pop per iteration, same
`FMT_STEP_LIMIT` budget; on exhaustion it returns `FMT_WIDTH_INFINITE`,
conservatively never flattened): TEXT gives its recorded length (or
`FMT_WIDTH_INFINITE` when it embeds CR/LF), LINE gives 1, SOFTLINE/NIL/NONE
give 0, HARDLINE gives `FMT_WIDTH_INFINITE`, CONCAT gives the saturated sum
of its children, and NEST/GROUP/ALIGN are transparent. The sum saturates at
`FMT_WIDTH_INFINITE`.

The fit test is **local and greedy**: a group is compared against the
remaining width using its own flattened subtree only; it does not look ahead
at the rest of the line. Consequently an outer group may break while an inner
group on the same line stays flat (the inner group is re-evaluated at its own
column). This is the documented, intentional criterion.

`fmt_render_flat(g, root)` is exactly `fmt_render(g, root,
FMT_WIDTH_INFINITE)`: every group with a finite flat width is flattened;
hardlines and embedded breaks still break.

## 6. API signatures

```xi
pub const FMT_MODE_FLAT: Int = 0;           // .. FMT_MODE_BREAK = 1
pub const FMT_KIND_NONE: Int = 0;           // .. FMT_KIND_ALIGN = 9
pub const FMT_WIDTH_INFINITE: Int = 1073741823;
pub const FMT_STEP_LIMIT: Int = 1048576;

pub type FmtDoc = { kinds: Vec[Int]; texts: Vec[Str]; text_lens: Vec[Int];
                    text_breaks: Vec[Int]; indents: Vec[Int];
                    child_a: Vec[Int]; child_b: Vec[Int]; }

pub fn fmt_doc_new() -> FmtDoc
pub fn fmt_node_count(g: &FmtDoc) -> Int
pub fn fmt_is_consistent(g: &FmtDoc) -> Bool
pub fn fmt_nil(g: &mut FmtDoc) -> Int
pub fn fmt_text(g: &mut FmtDoc, text: Str) -> Int
pub fn fmt_line(g: &mut FmtDoc) -> Int
pub fn fmt_softline(g: &mut FmtDoc) -> Int
pub fn fmt_hardline(g: &mut FmtDoc) -> Int
pub fn fmt_concat(g: &mut FmtDoc, a: Int, b: Int) -> Int
pub fn fmt_nest(g: &mut FmtDoc, a: Int, indent: Int) -> Int
pub fn fmt_group(g: &mut FmtDoc, a: Int) -> Int
pub fn fmt_align(g: &mut FmtDoc, a: Int) -> Int
pub fn fmt_join(g: &mut FmtDoc, ids: &Vec[Int], sep: Int) -> Int

pub fn fmt_node_kind(g: &FmtDoc, i: Int) -> Int
pub fn fmt_node_text(g: &FmtDoc, i: Int) -> Str
pub fn fmt_text_len(g: &FmtDoc, i: Int) -> Int
pub fn fmt_text_has_break(g: &FmtDoc, i: Int) -> Bool
pub fn fmt_node_indent(g: &FmtDoc, i: Int) -> Int
pub fn fmt_node_child_a(g: &FmtDoc, i: Int) -> Int
pub fn fmt_node_child_b(g: &FmtDoc, i: Int) -> Int
pub fn fmt_kind_name(kind: Int) -> Str
pub fn fmt_mode_name(mode: Int) -> Str
pub fn fmt_flat_width(g: &FmtDoc, node: Int) -> Int

pub fn fmt_render(g: &FmtDoc, root: Int, width: Int) -> Str
pub fn fmt_render_flat(g: &FmtDoc, root: Int) -> Str
```

`fmt_join` folds element nodes with a separator: `[]` yields a fresh NIL
node, `[x]` returns `x` unchanged (no new node), and longer lists produce a
left-nested CONCAT chain `((id0 sep id1) sep id2) ...`.

## 7. Guarantees

- **Determinism.** `fmt_render` and `fmt_flat_width` are pure functions of
  `(arena contents, root, width)`; no global state is read or written and the
  arena is never mutated by them. Identical arenas render identically at the
  same width.
- **Totality.** No step can trap: accessors clamp out-of-range indices,
  negative widths and negative indentation clamp at 0, an empty arena renders
  `""`, and unbreakable text simply overflows. Builders are append-only and
  each node references only previously created nodes, so the document graph
  is acyclic and both traversals terminate (they use explicit stacks, so deep
  documents do not consume the call stack). Each traversal pops exactly one
  work item per iteration and is capped at `FMT_STEP_LIMIT` pops, so even an
  unexpected graph shape cannot spin; the cap is far above any realistic
  document (one pop per root-to-node path).
- **Complexity.** Builders are O(1) (`fmt_text` is O(payload bytes),
  `fmt_join` is O(elements)). Rendering performs O(nodes) stack steps and one
  flat-width scan per group evaluated in BREAK mode: O(nodes^2) worst case,
  O(nodes) for documents without groups. Text emission accumulates with `Str`
  concatenation, so large outputs pay the stdlib concat cost.
- **No source mutation.** Documents are plain data; rendering never writes
  back into the arena.

## 8. Test plan

`tests/test_conformance.xi` (module `formatter_fw_tests`) runs 23 named
checks via `assert(cond, "name")`, one `fn` per check, direct calls (no fn
tables); `main` returns the failure count (0 = green). All string equality
goes through `str_compare`. Fixtures are built with the public builder API;
`words12()` (three 12-byte words, flat width 38), `words20()` (three 20-byte
words, flat width 62) and `call_doc()` (`call(alpha, beta, gamma)`, flat
width 24) pin the 20/40/80 matrix, the exact-fit boundary and a realistic
nested call layout.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | text/concat | verbatim render, flat width 4, arena count 3 |
| t2 | nil | empty render, concat identity, flat width 0 |
| t3 | line flat | LINE -> one space inside a fitting group |
| t4 | line broken | LINE -> newline when the group does not fit, widths 3/2/0 |
| t5 | softline | `f(x)` at 4/80, `f(\n  x)` at 3 (nest 2) |
| t6 | hardline | flat width infinite; always breaks, even at width 80 |
| t7 | hardline propagation | enclosing groups break; nest(2) indents the hardline |
| t8 | deep nesting | five nested nests accumulate ten spaces |
| t9 | align | indentation becomes the column at the align node |
| t10 | group independence | inner group flat inside a broken outer group |
| t11 | widths 20/40/80 | 12-byte words flat at 40/80, broken at 20; 20-byte words flat only at 80 |
| t12 | exact fit | flat width 6 fits at width 6, breaks at 5 |
| t13 | nested groups | broken outer, fitting inner ("(\n  key val\n)" vs "( key val )") |
| t14 | align prefix | "name = value" flat; continuation aligned at column 6 |
| t15 | join | three elements fold; empty -> NIL; single -> unchanged node |
| t16 | flat width | per-kind widths; nest/group/align transparent; bounds -> 0 |
| t17 | determinism | repeated renders and rebuilt arenas agree |
| t18 | totality | empty arena, width -5, nest -10, out-of-range group, root 999 |
| t19 | arena | seven parallel fields consistent; kinds/payloads/children; bounded accessors |
| t20 | call fixture | nest(4) argument block: one item per line and the closing paren on its own line at width 10 |
| t21 | embedded break | multi-line text never flattens; column resets to the last line |
| t22 | render_flat | flattens groups, never hardlines |
| t23 | overflow | unbreakable text emitted whole, never truncated |

## 9. Compiler / stdlib notes (pinned v0.62.1)

- The arena holds seven parallel `Vec` fields fed by one private push site
  (`_doc_push`), so the vectors cannot drift (t19 checks consistency).
- Text byte lengths are recorded at build time; no `Str` read back from a
  `Vec[Str]` element is measured with `.len()` outside a function parameter
  (BUG 17 / trap 1). Embedded-break detection reads bytes through a typed
  `UInt8` local and widens with `(b as Int) & 0xFF` before comparison.
- Every `Int` read from a `Vec` goes through a typed local (trap 2).
- Free functions only; no closures, no indexed `Vec[fn]` dispatch, no
  `Vec[StructType]`, no `self`, no lambdas; no free function named after a
  builtin (`fmt_` prefix throughout).
- The only stdlib import is `xiom.string` (`byte_at`); the renderer builds its
  output with `Str` concatenation and never uses `sb_to_str`.
- No `Result`/`Ok`/`Err` values are used; no generic angle-bracket spellings
  appear in this package.
