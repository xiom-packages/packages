# xiom.charts -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.charts` (`src/charts.xi`). Pure XIOM, no FFI.

## 1. Scope

A deterministic integer chart model with an SVG 1.1 text emitter:

- an integer data model (`ChartSeries`: parallel label/value vectors) with a
  drift guard (`series_len`),
- an integer layout (`ChartLayout`) with clamped canvas size, uniform padding
  and a tick count,
- linear value-to-pixel scaling with documented half-away-from-zero rounding
  (`chart_scale_y`),
- evenly spaced y-axis ticks (`chart_ticks`),
- four leaf element emitters (`chart_rect_element`, `chart_line_element`,
  `chart_path_element`, `chart_text_element`),
- five-entity XML escaping (`chart_escape`),
- two document renderers (`chart_bar_svg`, `chart_line_svg`) that emit a
  complete `<svg>` document as text.

The module emits text; it never parses SVG, never touches the filesystem and
never calls C. Every arithmetic step is `Int`; `Float64` appears nowhere.

## 2. Non-goals

- `Float64` / fractional geometry of any kind (see section 4).
- Chart types beyond line and bar: area, pie, doughnut, scatter, bubble,
  radar, polar, box, candlestick, histogram, heatmap, treemap, sunburst and
  statistical plots from the placeholder inventory are not implemented.
- Transforms, gradients, filters, animations, CSS, `<defs>`.
- Text metrics: labels are placed at integer anchors; the module does not
  measure or wrap them.
- Configurable palette at the document level (v0.1.0 emits the fixed palette
  in section 6; the element emitters accept paint values).
- A parser or DOM; file I/O; registry integration.

## 3. Model

```xi
pub type ChartSeries = {
  labels: Vec[Str];
  values: Vec[Int];
}

pub type ChartLayout = {
  width: Int;
  height: Int;
  pad: Int;
  ticks: Int;
}
```

- `series_len(s) = min(labels.len(), values.len())`. Every reader touches at
  most that many entries, so mismatched parallel vectors never cause an
  out-of-bounds read; the longer vector is truncated for all purposes.
- `series_new(labels, values)` stores both vectors as given (by value).
- `chart_min` / `chart_max` return the extremes over the usable prefix, and
  `0` for an empty series.
- The domain is `[chart_min(s), chart_max(s)]`, normalized to
  `[dmin, dmin + 1]` when `max <= min` (empty series included: `[0, 1]`).

### Layout clamping (`chart_layout`)

| Input | Rule |
|---|---|
| `width <= 0` | becomes `1` |
| `height <= 0` | becomes `1` |
| `pad < 0` | becomes `0` |
| `pad > min((width-1)/2, (height-1)/2)` | becomes that minimum (integer division, truncation toward zero) |
| `ticks < 2` | becomes `2` |

After clamping: `chart_plot_x0 = chart_plot_y0 = pad`,
`chart_plot_w = width - 2*pad`, `chart_plot_h = height - 2*pad`, and both plot
dimensions are `>= 1`.

## 4. Scaling and rounding (`chart_scale_y`)

```
dmax = (dom_max <= dom_min) ? dom_min + 1 : dom_max
ph   = max(plot_h, 0)
vc   = clamp(v, dom_min, dmax)
y    = y_bottom - round_half_away((vc - dom_min) * ph, dmax - dom_min)
```

`round_half_away(n, d)` for `d > 0`:

```
q = n / d          // Int division truncates toward zero
r = n % d
if 2*r >= d  -> q + 1
if -2*r >= d -> q - 1
else         -> q
```

This is round-half-away-from-zero for both signs. The naive ceil idiom
`(n + d - 1) / d` is wrong for negative `n` and is not used; after clamping,
the numerator `(vc - dom_min) * ph` is always `>= 0`, but the helper stays
sign-correct so callers can rely on the rule, not on the clamp.

Consequences pinned by the conformance suite:

- `chart_scale_y(0, 0, 10, 100, 10) == 100`, `... (5, ...) == 95`,
  `... (10, ...) == 90` (endpoints and midpoint exact),
- `chart_scale_y(1, 0, 4, 100, 10) == 97` (2.5 rounds to 3),
  `chart_scale_y(3, 0, 4, 100, 10) == 92` (7.5 rounds to 8),
- out-of-domain values clamp to the domain ends,
- negative domains and negative `y_bottom` work (e.g.
  `chart_scale_y(-5, -10, 10, 0, 10) == -3`),
- a flat domain behaves as `[dom_min, dom_min + 1]`.

### Point x coordinates (`_x_at`, used by the line renderer)

For point `i` of `n` points across a plot of width `pw` starting at `x0`:

```
n <= 1 -> x0
n > 1  -> x0 + round_half_away(i * pw, n - 1)
```

## 5. Ticks (`chart_ticks`)

```
t = max(count, 2)
normalize the domain as in section 4
tick[j] = dom_min + round_half_away(j * span, t - 1), j = 0 .. t-1
```

Returns exactly `t` values, ascending, `tick[0] = dom_min` and
`tick[t-1] = normalized dom_max`; interior ticks round half away from zero.
Adjacent ticks may coincide when the domain is narrower than the tick count
(division rounding only, no deduplication). Examples:
`(0, 10, 3) -> [0, 5, 10]`, `(0, 10, 4) -> [0, 3, 7, 10]`,
`(5, 5, 2) -> [5, 6]`, `(-10, 10, 5) -> [-10, -5, 0, 5, 10]`.

## 6. Document rendering

### Escaping (`chart_escape`)

Exactly five bytes are replaced; every other byte (including multi-byte
UTF-8 sequences and control bytes) passes through unchanged:

| Input byte | Output |
|---|---|
| `&` (38) | `&amp;` |
| `<` (60) | `&lt;` |
| `>` (62) | `&gt;` |
| `"` (34) | `&quot;` |
| `'` (39) | `&apos;` |

`0x00` is the one exception: it is dropped, because XML 1.0 cannot represent
NUL and a XIOM `Str` cannot round-trip it (`sb_to_str` aborts on 0x00).
Escaping is not idempotent for strings containing `&`; applying it twice is
not supported.

Every `Str` that reaches the output is escaped: `fill`, `stroke`, path `d`,
character data and all label/tick text.

### Element formats

Attribute order is fixed and equals the parameter order. All attribute
values are double-quoted; integers are rendered in exact decimal; `Str`
values are escaped. An element never contains a trailing newline.

| Emitter | Format | Omitted when empty |
|---|---|---|
| `chart_rect_element(x, y, w, h, fill)` | `<rect x=".." y=".." width=".." height=".." fill=".."/>` | `fill` |
| `chart_line_element(x1, y1, x2, y2, stroke, stroke_width)` | `<line x1=".." y1=".." x2=".." y2=".." stroke=".." stroke-width=".."/>` | never |
| `chart_path_element(d, fill, stroke, stroke_width)` | `<path d=".." fill=".." stroke=".." stroke-width=".."/>` | `fill`; `stroke` (and `stroke-width` with it) |
| `chart_text_element(x, y, text, font_size, fill)` | `<text x=".." y=".." font-size=".." fill="..">escaped</text>` | `fill` |

`chart_line_element` always emits `stroke` (escaped, `stroke=""` included)
and `stroke-width`. `chart_path_element` always emits `d` (escaped, `d=""`
included) and emits `stroke-width` exactly when `stroke` is non-empty.
Negative geometry is emitted as-is.

### Fixed palette (v0.1.0)

| Constant | Value | Used for |
|---|---|---|
| axes | `#000000` | y axis, x axis |
| gridlines | `#e6e6e6` | one horizontal line per tick |
| bars | `#4c78a8` | bar `fill` |
| line | `#4c78a8` | polyline `stroke`, width 1 |
| labels | `#333333` | tick and category text, font size 10 |

### Page layout

`chart_bar_svg(s, l)` and `chart_line_svg(s, l)` return, joined with a single
LF and with **no trailing newline**:

```
<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H">
  <y axis line>
  <x axis line>
  <gridline + tick label>   (once per tick, ascending)
  <series elements>
  <category label per point>
</svg>
```

- `W`/`H` are the clamped layout dimensions.
- y axis: `(px0, py0) -> (px0, pbot)`; x axis: `(px0, pbot) -> (px1, pbot)`;
  `pbot = py0 + plot_h`, `px1 = px0 + plot_w`.
- Per tick, in ascending order: a gridline `(px0, ty) -> (px1, ty)` where
  `ty = chart_scale_y(tick, ...)`, then its label at
  `(max(0, px0 - 4), ty + 3)`.
- Bars, per point `i`: `<rect x="px0 + i*slot" y="scale_y(v)" width="bw"
  height="pbot - scale_y(v)" fill="#4c78a8"/>`, where
  `slot = max(1, plot_w / n)` (integer division) and `bw = max(1, slot - 1)`;
  then, per point, a category label at `(px0 + i*slot, pbot + 12)`.
- Line, once: a `<path>` with `d = "M x0 y0"` then `" L xi yi"` per further
  point (`xi = _x_at(i, n, px0, pw)`, `yi = scale_y(v)`), `fill="none"`,
  `stroke="#4c78a8"`, `stroke-width="1"`; then, per point, a category label
  at `(_x_at(i, n, px0, pw), pbot + 12)`.
- An empty series renders the frame (header, axes, gridlines, tick labels)
  and no series elements. A single point renders a lone `M` command.

## 7. API signatures

```xi
pub type ChartSeries = { labels: Vec[Str]; values: Vec[Int]; }
pub type ChartLayout = { width: Int; height: Int; pad: Int; ticks: Int; }

pub fn series_new(labels: Vec[Str], values: Vec[Int]) -> ChartSeries
pub fn series_len(s: &ChartSeries) -> Int
pub fn chart_min(s: &ChartSeries) -> Int
pub fn chart_max(s: &ChartSeries) -> Int
pub fn chart_layout(width: Int, height: Int, pad: Int, ticks: Int) -> ChartLayout
pub fn chart_plot_x0(l: &ChartLayout) -> Int
pub fn chart_plot_y0(l: &ChartLayout) -> Int
pub fn chart_plot_w(l: &ChartLayout) -> Int
pub fn chart_plot_h(l: &ChartLayout) -> Int
pub fn chart_scale_y(v: Int, dom_min: Int, dom_max: Int, y_bottom: Int, plot_h: Int) -> Int
pub fn chart_ticks(dom_min: Int, dom_max: Int, count: Int) -> Vec[Int]
pub fn chart_escape(s: Str) -> Str
pub fn chart_rect_element(x: Int, y: Int, w: Int, h: Int, fill: Str) -> Str
pub fn chart_line_element(x1: Int, y1: Int, x2: Int, y2: Int, stroke: Str, stroke_width: Int) -> Str
pub fn chart_path_element(d: Str, fill: Str, stroke: Str, stroke_width: Int) -> Str
pub fn chart_text_element(x: Int, y: Int, text: Str, font_size: Int, fill: Str) -> Str
pub fn chart_bar_svg(s: &ChartSeries, l: &ChartLayout) -> Str
pub fn chart_line_svg(s: &ChartSeries, l: &ChartLayout) -> Str
```

All functions are infallible (no `Result` channel); complexity is linear in
`series_len` times the emitted digit count.

## 8. Test plan

`tests/test_conformance.xi` (module `charts_tests`) runs 28 named checks
through `assert(cond, "name")`, one `fn` per check, direct calls (no fn
tables), and `main` returns the failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t01 | series construction | storage + element read-back + `series_len` |
| t02 | drift guard | `series_len` is the shorter vector, empty is 0 |
| t03 | min/max | usable prefix, empty is 0 |
| t04 | layout clamps | size >= 1, pad >= 0, ticks >= 2 |
| t05 | pad clamp | plot stays >= 1 x 1 |
| t06 | plot geometry | accessors = pad / size - 2*pad |
| t07 | scale endpoints | domain ends and midpoint exact |
| t08 | scale halves | 2.5 -> 3, 7.5 -> 8 (half away from zero) |
| t09 | scale clamps | out-of-domain values; `plot_h < 0` -> 0 |
| t10 | negative domain | negative values and negative y |
| t11 | flat domain | widened to `[min, min + 1]` |
| t12 | ticks basic | span inclusive; count clamps to 2 |
| t13 | ticks rounding | `(0,10,4) -> [0,3,7,10]` etc. |
| t14 | ticks flat/negative | `(5,5,2) -> [5,6]`; `[-10..10]` |
| t15 | escape table | exact five entities; `""` and plain text pass |
| t16 | escape control bytes | `\u{0001}` `\u{000B}` `\u{001F}` `\u{007F}` byte-exact |
| t17 | rect element | exact string; empty fill omitted |
| t18 | line element | exact string; stroke escaped; empty stroke kept |
| t19 | path element | exact string; `d` escaped; empty fill/stroke omitted |
| t20 | text element | exact string; character data escaped; empty fill omitted |
| t21 | bar document | byte-for-byte 2-point fixture (axes, ticks, bars, labels) |
| t22 | bar label escaping | `&` `<` escaped; raw form absent |
| t23 | line document | exact polyline path; no `<rect>`; labels present |
| t24 | single point | lone `M` command, no `L` |
| t25 | empty series | axes + ticks only; no `<rect>`/`<path>` |
| t26 | x rounding | `i*10/3` -> x 8 and 12 |
| t27 | extreme padding | 20x20 with pad 100 -> 2 x 2 plot, no crash |
| t28 | determinism | repeated renders are byte-identical |

All Str comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison), and every `Vec` element read is bound to a typed local
first.

## 9. Known limitations

- Only line and bar charts; the rest of the placeholder inventory is future
  work.
- Integer geometry only; no `Float64`. No text metrics: labels are placed by
  integer anchors and can overflow or clip on small canvases.
- The document palette is fixed (section 6); the element emitters accept
  paint values, the document renderers do not.
- `slot = max(1, plot_w / n)`: when the series is wider than the plot, bars
  stride past the plot's right edge instead of shrinking below width 1.
- A bar whose value equals the domain minimum has `height="0"` (invisible):
  geometry is exact, no minimum height is imposed.
- `dmin + 1` on `INT_MAX` (and huge-value products) overflow `Int`; domains
  are assumed sane.
- Escaping is not idempotent for strings containing `&`; no unescape ships.
- NUL bytes are dropped (section 6); control bytes below 0x20 other than
  `\t\n\r` are passed through and produce markup XML 1.0 does not accept.
- No XML declaration / DOCTYPE, no parser, no validation.

## 10. Compiler / stdlib notes (v0.62.1)

- Free functions only; no `self` methods, no inline lambdas, no
  `Vec[StructType]`; tests call checks directly, never through fn tables.
- BUG 17 discipline: the module never compares `Str`; the tests route every
  comparison through `str_compare` and bind every `Vec[Str]` element to a
  typed local before use.
- **Type-name collision (new finding, cost one red gate):** naming a public
  struct `Layout` collides with the stdlib type `xiom.alloc.Layout`
  (`{ size, align }`). The collision is not diagnosed; callers that bind the
  returned struct and read fields silently read constant `0`
  (`chart_layout(...)` produced all-zero fields, while the callee's own IR was
  correct). Renaming the public types to `ChartLayout` / `ChartSeries` fixed
  it. Packages should prefix public struct names.
- The rounding helper deliberately avoids the naive ceil idiom
  `(n + d - 1) / d`, which is wrong for negative `n` (Int division truncates
  toward zero); the remainder-based form is used instead.
- `chart_escape` drops 0x00 because `sb_to_str` aborts on a NUL-containing
  buffer; the five entity bytes are compared directly against `< 128`
  `UInt8` constants.
- Int -> Str uses `xiom.convert.int_to_string` (exact for `INT_MIN`).
