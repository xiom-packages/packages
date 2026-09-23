# xiom.svg -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.svg` (`src/svg.xi`). Pure XIOM, no FFI.

## 1. Scope

An in-memory SVG 1.1 document builder:

- create an integer-sized canvas (`svg_new`),
- append prebuilt element strings (`svg_add`) and count them
  (`svg_element_count`),
- build the six most common leaf elements (`svg_rect`, `svg_circle`,
  `svg_ellipse`, `svg_line`, `svg_text`, `svg_path`),
- escape text with the five predefined entities (`svg_escape`),
- serialize the document deterministically (`svg_render`).

The module emits text; it never parses SVG, never touches the filesystem and
never calls C.

## 2. Non-goals

- Fractional geometry (`Float64`): all geometry is `Int` (see section 3).
- Transforms, gradients, filters, clip paths, patterns, markers, animation.
- CSS / `style` attributes and presentation-attribute inheritance.
- Path-data parsing, validation or bounds computation.
- XML declaration / DOCTYPE emission, comments, metadata, `<defs>` helpers.
- A parser or a DOM: `svg_add` takes complete element strings.
- Any FFI, file I/O, or registry integration.

## 3. Document model

```xi
pub type SvgDoc = {
  width: Int;
  height: Int;
  elements: Vec[Str];
}
```

- `width` / `height` are canvas dimensions in user units. `svg_new` clamps a
  value `<= 0` to `1`; positive values are kept exactly.
- `elements` holds complete element strings in append order. `svg_add`
  appends verbatim: no validation, no escaping, no reformatting.
- Geometry is integer-only. Fractional coordinates must be scaled to integers
  by the caller before calling the helpers, with the scale tracked separately.
- Negative coordinates, sizes and widths are emitted as-is by the helpers
  (an SVG renderer ignores non-positive geometry). Only `svg_new` clamps.

### Render layout

`svg_render(d)` returns, joined with a single LF and with **no trailing
newline**:

```
<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H">
  <element 1>
  <element 2>
  ...
</svg>
```

Equivalently: `header + ("\n  " + element) * n + "\n</svg>"`. Each element
contributes exactly one line, indented with two spaces. An empty canvas
renders as two lines: the header line followed by `</svg>`.

## 4. Element formats

Attribute order is fixed and equals the parameter order below. Attribute
values are double-quoted; integers are rendered in exact decimal (negatives
included). An element never contains a trailing newline.

| Helper | Format | Omitted when empty |
|---|---|---|
| `svg_rect(x, y, w, h, fill)` | `<rect x=".." y=".." width=".." height=".." fill=".."/>` | `fill` |
| `svg_circle(cx, cy, r, fill)` | `<circle cx=".." cy=".." r=".." fill=".."/>` | `fill` |
| `svg_ellipse(cx, cy, rx, ry, fill)` | `<ellipse cx=".." cy=".." rx=".." ry=".." fill=".."/>` | `fill` |
| `svg_line(x1, y1, x2, y2, stroke, stroke_width)` | `<line x1=".." y1=".." x2=".." y2=".." stroke=".." stroke-width=".."/>` | never (`stroke=""` stays) |
| `svg_text(x, y, text, font_size, fill)` | `<text x=".." y=".." font-size=".." fill="..">escaped</text>` | `fill` |
| `svg_path(d, fill, stroke)` | `<path d=".." fill=".." stroke=".."/>` | `fill`, `stroke` (never `d`) |

Decisions pinned by the conformance suite:

1. **Empty-attribute omission** applies to paint helper parameters that name
   an empty string: `fill` on rect/circle/ellipse/text, and `fill`/`stroke`
   on path. The attribute is dropped entirely, including its leading space,
   producing `<rect .../>` style output.
2. **`svg_line` always emits `stroke`** (escaped) and `stroke-width`, even
   when `stroke` is `""` or `stroke-width` is `0` or negative.
3. **`svg_path` always emits `d`** (escaped), even when `d` is `""`.
4. **`svg_text` always emits `x`, `y` and `font-size`**; only `fill` can be
   omitted. Character data is escaped (section 5) between `>` and `</text>`.
5. **Prebuilt elements** added with `svg_add` are not inspected; they may be
   any markup (e.g. `<g id="layer1"/>`).

## 5. Escaping

`svg_escape(s)` maps exactly five bytes, and passes every other byte
(including multi-byte UTF-8 sequences) through unchanged:

| Input byte | Output |
|---|---|
| `&` (38) | `&amp;` |
| `<` (60) | `&lt;` |
| `>` (62) | `&gt;` |
| `"` (34) | `&quot;` |
| `'` (39) | `&apos;` |

Escaped by the package (these are text content):

| Location | Escaped |
|---|---|
| `svg_text` character data (`text`) | yes |
| `svg_path` `d` | yes |
| `svg_path` `stroke` | yes |
| `svg_line` `stroke` | yes (hardening; superset of the minimum contract) |

Emitted verbatim (paint values, not text content):

| Location | Verbatim |
|---|---|
| `fill` on rect/circle/ellipse/text/path | yes |
| `svg_add` element string | yes |

The package ships **no unescape function**. Escaping is idempotent only for
strings without `&`; applying it twice is not supported. The test suite proves
a round-trip with a test-local inverse (`unescape_five`).

## 6. API signatures

```xi
pub type SvgDoc = { width: Int; height: Int; elements: Vec[Str]; }

pub fn svg_new(width: Int, height: Int) -> SvgDoc
pub fn svg_add(d: &mut SvgDoc, element: Str)
pub fn svg_element_count(d: &SvgDoc) -> Int
pub fn svg_rect(x: Int, y: Int, w: Int, h: Int, fill: Str) -> Str
pub fn svg_circle(cx: Int, cy: Int, r: Int, fill: Str) -> Str
pub fn svg_ellipse(cx: Int, cy: Int, rx: Int, ry: Int, fill: Str) -> Str
pub fn svg_line(x1: Int, y1: Int, x2: Int, y2: Int, stroke: Str, stroke_width: Int) -> Str
pub fn svg_text(x: Int, y: Int, text: Str, font_size: Int, fill: Str) -> Str
pub fn svg_path(d: Str, fill: Str, stroke: Str) -> Str
pub fn svg_escape(s: Str) -> Str
pub fn svg_render(d: &SvgDoc) -> Str
```

All functions are infallible (no `Result` channel); complexity is linear in
the produced byte count.

## 7. Test plan

`tests/test_conformance.xi` (module `svg_tests`) runs 20 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | rect exact string | format + attribute order (section 4) |
| t2 | empty fill omission | rect, circle, ellipse drop empty `fill` |
| t3 | circle exact string | format |
| t4 | ellipse exact string | format |
| t5 | line exact string | `stroke` + `stroke-width` order |
| t6 | text escaping | all five entities in character data |
| t7 | text without fill | omission on `<text>`; plain text untouched |
| t8 | path with stroke | `d`, `fill`, `stroke` order |
| t9 | path omissions | empty `fill` and empty `stroke` drop; `d` kept |
| t10 | path escaping | `d` and `stroke` escaped |
| t11 | svg_new clamping | `<= 0` -> 1; positives kept; starts empty |
| t12 | count and order | count grows per add; render preserves append order |
| t13 | render layout | header, two-space indent, LF join, footer |
| t14 | render empty doc | header + `</svg>` only |
| t15 | negative coordinates | emitted as-is (rect and line) |
| t16 | large numbers | 1234567890123456789, INT32 edges, exact decimal |
| t17 | escape table | exact five entities; `""` and plain text pass |
| t18 | escape round-trip | test-local inverse; UTF-8 passes; no raw `<` `>` `"` |
| t19 | svg_add verbatim | prebuilt `<g .../>` appears exactly, once |
| t20 | line empty stroke | `stroke=""` always emitted |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Assertions are exact-string; none is weakened.

## 8. Known limitations

- Integer geometry only; no fractional coordinates, no `Float64`.
- No transforms/gradients/filters/patterns/markers/animation, no CSS.
- No path-data parsing or validation: `d` is escaped and emitted.
- Paint values (`fill`, `svg_line` `stroke`) are not escaped; pass trusted
  values (a quote in a paint value would break the attribute).
- `svg_add` accepts any string, including empty strings and multi-line
  strings; `svg_render` indents each entry once and does not split it.
- No unescape function, no parser, no round-trip reading.
- No XML declaration / DOCTYPE; the root element carries `xmlns` only.
- Non-positive geometry is not clamped by the helpers (only `svg_new`).

## 9. Compiler / stdlib notes (v0.61.3)

- Free functions only; no `self` methods, no inline lambdas, no
  `Vec[StructType]`.
- No `==` on `Str` values read from `Vec[Str]` elements anywhere in the
  module or tests; the tests route every comparison through `str_compare`.
- Element strings are read back one at a time through `_indented_line` so no
  `Vec[Str]` element is concatenated in place.
- Int -> Str uses a local exact decimal renderer (`_int_to_str`) built from
  `xiom.string.str_slice` + concatenation; it deliberately avoids the
  `xiom.convert.*` / `xiom.num.base` conversion tower.
- Byte constants compared against `string.byte_at` output are all `< 128`.
- The suite pins all deterministic output byte-for-byte; the only non-ASCII
  data is a UTF-8 pass-through check in t18.
