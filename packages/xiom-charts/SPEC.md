# xiom.charts -- Specification

Version: 0.2.0 (incubating, publish pending).
Module: `xiom.charts` (`src/charts.xi`). Pure XIOM, no FFI, no filesystem, no
global state. 71 conformance checks.

0.2.0 is a deliberate breaking redesign of the 0.1.0 integer line/bar module:
the data model, layout and every renderer are Float64, and the declared
surface now covers the P1 static 2D set.

## 1. Scope

A deterministic static-2D chart model plus an SVG 1.1 text emitter:

- Float64 series with optional category labels or explicit x coordinates,
- linear and base-10 logarithmic scales with clamping and inversion,
- auto or explicit axes, "nice" linear ticks and power-of-ten log ticks,
- layout with four independent margins and a guaranteed >= 1 x 1 plot,
- color model (RGB + alpha + `none`), ten-color palette, viridis/magma
  colormaps, hex parse/format and interpolation,
- nine renderers: multi-series line, scatter, grouped bar, stacked bar, area,
  step, histogram, pie and doughnut, plus a `chart_svg` dispatcher,
- gridlines, legends, titles, axis labels, five marker shapes,
- text, arrow, horizontal-line and vertical-line annotations,
- deterministic escaping and numeric formatting,
- low-level SVG element emitters intended for reuse by the future
  `xiom.plots` interactive layer.

The model, geometry, and render layers are separate functions over value
structs. There is no module-level mutable state; renderers never mutate the
figure.

## 2. Non-goals (later phases)

Explicitly **not** in 0.2.0:

- heatmap / imshow / contour / quiver / streamplot / spectrogram,
- candlestick / OHLC / box / violin / error bars / regression plots,
- 3D axes, projections, surfaces, wireframes (planned for `xiom.charts` 0.3),
- interactive figures, pan/zoom/pick, layout/gridspec, animation (planned for
  the separate `xiom.plots` package),
- SVG parsing, DOM, CSS, `<defs>`, gradients, filters, clip paths,
  patterns, transforms, custom fonts,
- text measurement, wrapping, rotation, or collision avoidance,
- scientific notation, locale-aware formatting, time/date axes,
- categorical coordinate transforms, polar axes, dual axes, insets,
- file I/O, registry integration, threads, randomness.

## 3. Model types

```xi
pub type ChartColor = { r: Int; g: Int; b: Int; a: Float64; none: Bool; }

pub type ChartSeries = {
  name: Str;
  labels: Vec[Str];
  xs: Vec[Float64];
  ys: Vec[Float64];
  color: ChartColor;
  auto_color: Bool;
  line_width: Float64;
  marker: Int;
  opacity: Float64;
}

pub type ChartLayout = {
  width: Float64; height: Float64;
  left: Float64; right: Float64; top: Float64; bottom: Float64;
}

pub type ChartAxis = {
  min: Float64; max: Float64;
  auto: Bool; log: Bool;
  label: Str; tick_count: Int;
}

pub type ChartScale = { min: Float64; max: Float64; p0: Float64; p1: Float64; log: Bool; }

pub type ChartAnnotation = {
  kind: Int;
  x1: Float64; y1: Float64; x2: Float64; y2: Float64;
  text: Str; color: ChartColor;
}

pub type ChartFigure = {
  series: Vec[ChartSeries];
  layout: ChartLayout;
  title: Str;
  x_axis: ChartAxis; y_axis: ChartAxis;
  grid_x: Bool; grid_y: Bool; legend: Bool;
  kind: Int;
  bar_width: Float64; doughnut_hole: Float64; bins: Int;
  annotations: Vec[ChartAnnotation];
  background: ChartColor;
}
```

### Series construction and drift guard

- `series_new(name, xs, ys)` stores numeric x coordinates and values; labels
  are empty; `auto_color=true`, `marker=MARKER_NONE`, `line_width=2.0`,
  `opacity=1.0`.
- `series_cat(name, labels, ys)` stores category labels and no xs.
- `series_len` is the shortest of `ys.len()`, a **non-empty** `labels.len()`
  and a **non-empty** `xs.len()`. Every renderer reads at most that many
  entries, so mismatched parallel vectors never cause an out-of-bounds read.
- An empty `labels` or `xs` vector is not a constraint: it means "derive
  category labels" or "use index positions".
- `series_set_color` sets `color` and clears `auto_color`. `series_set_marker`
  clamps tags outside `MARKER_NONE..MARKER_TRIANGLE` to `MARKER_NONE`.

### Color model

- Channels are clamped to 0..255, alpha to 0..1.
- `none=true` is the SVG `none` paint; its hex form is `#000000` and its paint
  form is `none`. All element emitters honor it.
- Alpha below 1 emits `fill-opacity`/`stroke-opacity`; alpha 1 omits it.

## 4. Deterministic numeric formatting

All coordinates pass through `_fmt_dec(x, 3)` unless stated otherwise:

```
d      = clamp(decimals, 0, 9)
ax     = |x|                        (neg = x < 0)
scale  = 10^d
rounded= trunc(ax * scale + 0.5)    (half away from zero)
body   = integer part, with d fractional digits when non-zero
trim   = drop trailing fractional zeros and a trailing '.'
sign   = '-' only when rounded > 0
```

Consequences pinned by tests:

- `chart_format_float(1.23456, 3) == "1.235"`,
- `chart_format_float(-1.23456, 3) == "-1.235"`,
- `chart_format_float(-0.004, 2) == "0"` (`"-0"` never appears),
- `chart_format_float(10.0, 3) == "10"` (trailing zeros trimmed),
- non-finite inputs format as `"0"`; values above 9e15 also format `"0"`
  (the Int rounding path would otherwise overflow).

`chart_format_value` chooses decimals by magnitude:

| |x| | decimals |
|---|---|---|
| >= 1000 | 0 |
| >= 10 | 1 |
| >= 1 | 2 |
| >= 0.01 | 3 |
| otherwise | 6 |

Every coordinate/attribute uses at most 3 decimals. `chart_svg_open` formats
both `width`/`height` and the matching `viewBox`.

## 5. Escaping

`chart_escape` replaces exactly five bytes: `& -> &amp;`, `< -> &lt;`,
`> -> &gt;`, `" -> &quot;`, `' -> &apos;`. Other bytes, including multi-byte
UTF-8 and control bytes, pass through unchanged, except `0x00` which is
dropped (a XIOM `Str` cannot round-trip NUL). Escaping is not idempotent for
strings containing `&`; applying it twice is unsupported.

## 6. Layout

`chart_layout(width, height, left, right, top, bottom)`:

- non-finite or `<= 0` width/height become `1`,
- each margin is clamped to `>= 0`,
- `left`/`top` are clamped to `width-1`/`height-1` first, then `right`/
  `bottom` to the remaining space,
- therefore `chart_plot_w >= 1` and `chart_plot_h >= 1` always.

`chart_layout_uniform(w, h, pad)` uses the same pad on all sides.
`chart_layout_default()` is `640 x 360` with `left=56, right=20, top=36,
bottom=44` (plot `564 x 280`). Plot accessors are `left`, `top`,
`width-left-right`, `height-top-bottom`, `width-right`, `height-bottom`.

## 7. Scales and axes

### Linear scale

`scale_linear(min, max, p0, p1)` normalizes non-finite bounds to `[0,1]` and a
degenerate domain to `[min, min+1]`. `p0`/`p1` may be reversed.

```
t = (v - min) / (max - min)
px = p0 + t * (p1 - p0)
```

`scale_map` clamps `t` to `0..1`; `scale_map_unclamped` does not.
`scale_invert(px)` computes the inverse; a zero-width pixel span returns
`min`.

### Log scale

`scale_log(min, max, p0, p1)` floors a non-positive minimum to `1`, widens a
degenerate domain to `[min, min*10]`, and maps with `log10`:

```
t = (log10(max(v, min)) - log10(min)) / (log10(max) - log10(min))
```

Non-positive values map to the domain minimum. `scale_invert` returns
`10^(log10(min) + t * (log10(max) - log10(min)))`. `scale_span` is the
arithmetic width `max - min`, not a decade count.

### Axes

- `axis_auto(label, ticks)` stores `[0,1]` with `auto=true`; renderers resolve
  the actual domain from data. `axis_ticks` on an auto axis still uses the
  stored `[0,1]` (documented); chart renderers resolve first.
- `axis_linear` / `axis_log` are explicit and normalize like the corresponding
  scale.
- `tick_count` is clamped to `2..100` for axes (and `2..1000` inside
  `ticks_nice`).
- `axis_scale(a, p0, p1)` builds the matching scale.

## 8. Auto domains

Only axes with `auto=true` are derived; explicit axes are used verbatim
(after normalization).

- **Category x** (bar, stacked bar, pie, doughnut, or line/scatter/area/step
  whose first series has labels and no xs): domain is `[-0.5, n-0.5]`, where
  `n` is the longest usable series. An explicit x axis is ignored for category
  charts; x is always linear.
- **Numeric x**: data min/max over `series_len` points, padded by 5% on both
  sides. With `n <= 1` the domain is `[-0.5, 0.5]`.
- **Histogram x**: data min/max, padded 5%; a flat range is widened by 10% of
  its magnitude (or to `0..1` at zero).
- **y, ordinary charts**: data min/max padded 5%. Bar, area and histogram
  include zero: if all values are non-negative the lower bound is exactly 0
  and only the upper bound is padded; the mirror holds for non-positive data;
  mixed-sign data pads both sides.
- **y, stacked bar**: per category, positive and negative values are summed
  separately; the bounds are the extrema of those sums, include zero, and are
  padded like mixed-sign data.
- A degenerate domain is widened (`0..1` at zero, otherwise by 10% of the
  magnitude).

## 9. Tick locators and formatting

`ticks_nice(min, max, count)`:

1. normalize non-finite/degenerate input,
2. `raw = span / (count-1)`,
3. `base = 10^floor(log10(raw))`, `f = raw/base`,
4. step = `base`, `2*base`, `2.5*base`, `5*base` or `10*base` for
   `f <= 1, 2, 2.5, 5, else`,
5. emit every grid multiple inside `[min, max]` (with a small epsilon),
6. the result is never empty; a single tick is followed by the domain max.

The tick count is advisory: `(0,10,5) -> [0, 2.5, 5, 7.5, 10]`,
`(0,10,6) -> [0, 2, 4, 6, 8, 10]`, `(-3,7,6) -> [-2, 0, 2, 4, 6]`.
`(0,10,4)` yields `[0,5,10]` (three ticks, not four).

`ticks_log(min, max)` emits powers of ten from `ceil(log10(min))` through
`floor(log10(max))`; if the domain spans less than one decade it returns the
two endpoints. `ticks_category(n)` emits `0..n-1` (negative `n` -> empty).

Tick labels use `chart_format_value`; category labels come from the first
series and fall back to `1`, `2`, ... when the label vector is shorter.
Histogram auto-y ticks are integer counts `0..max_count`.

## 10. SVG document

### Root

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H" viewBox="0 0 W H">
```

`W`/`H` are the layout size formatted by `_fmt_dec(...,3)`. The document has
no XML declaration, DOCTYPE, trailing newline, or pretty-printing beyond one
element per line with two-space indentation.

### Fixed order (Cartesian charts)

1. root open,
2. full-canvas background rectangle,
3. title (if non-empty), centered at `(W/2, 20)`, size 16, `#222222`,
4. y gridlines (if `grid_y`),
5. x gridlines (if `grid_x`),
6. y axis line, then x axis line (`#000000`, width 1),
7. y tick labels (right-aligned at `plot_x0 - 6`, baseline `ty + 3`),
8. x tick labels (centered at `plot_y1 + 16`) and x axis label,
9. y axis label at `(8, plot_center_y)` (horizontal, left-aligned),
10. series elements,
11. annotations,
12. legend (if enabled),
13. `</svg>`.

Title text is placed at `font-size + 4`; axis labels use size 11. There is no
text measurement: labels can overlap or clip on small canvases.

### Element formats

Attribute order is fixed. All numbers use `_fmt_dec(...,3)`; all Str values
are escaped. A color with `none=true` renders paint `none`.

| Emitter | Format |
|---|---|
| `chart_rect_element(x,y,w,h,fill)` | `<rect x=".." y=".." width=".." height=".." fill=".."[ fill-opacity=".."]/>` |
| `chart_circle_element(cx,cy,r,fill)` | `<circle cx=".." cy=".." r=".." fill=".."[ fill-opacity=".."]/>` |
| `chart_line_element(x1,y1,x2,y2,stroke,width)` | `<line x1=".." y1=".." x2=".." y2=".." stroke=".." stroke-width=".."[ stroke-opacity=".."]/>` |
| `chart_path_element(d,fill,stroke,width)` | `<path d=".." fill=".."[ fill-opacity=".."] stroke=".." stroke-width=".."[ stroke-opacity=".."]/>` |
| `chart_text_element(x,y,text,size,fill)` | `<text x=".." y=".." font-size=".." fill=".."[ fill-opacity=".."]>escaped</text>` |
| `chart_text_anchor_element(...,anchor)` | same + `text-anchor=".."` when anchor is non-empty |
| `chart_polygon_element(points,fill)` | `<polygon points="x0,y0 x1,y1 ..." fill=".."[ fill-opacity=".."]/>` |
| `chart_polyline_element(points,stroke,width)` | `<polyline points="..." stroke=".." stroke-width=".."[ stroke-opacity=".."]/>` |

`chart_circle_element` clamps negative radii to 0. `chart_polygon_element` and
`chart_polyline_element` take a flat `[x0,y0,x1,y1,...]` vector; fewer than two
pairs render `points=""`. Opacity attributes are omitted at alpha 1 and for
the `none` paint.

## 11. Renderers

All renderers return a complete document and are pure. Series are drawn in
vector order; a series with `series_len == 0` contributes nothing.

- **`chart_line_svg`**: one path per series (`M`, then ` L` per point); x is
  explicit xs or the index; y uses the resolved y scale. Markers are emitted
  when `marker != MARKER_NONE`.
- **`chart_scatter_svg`**: one marker per point, no connecting path.
  `MARKER_NONE` is treated as `MARKER_CIRCLE`. Shapes: circle (r=3), square
  (6x6), diamond (3.9 half-diagonal), cross (two 1px lines), triangle (base 6,
  height 6). Unknown tags render as circles.
- **`chart_bar_svg`** (grouped): category slots of width `plot_w / ncat`;
  `bar_width` is clamped to `0.05..1.0` and is the fraction of the slot used;
  each series gets an equal sub-bar. Bars grow from the pixel of y=0; negative
  values grow downward. Category labels come from the first series.
- **`chart_bar_stacked_svg`**: full inner width per category; categories are
  drawn left-to-right, series bottom-to-top within each sign; positive values
  stack upward from zero and negative values downward.
- **`chart_area_svg`**: per series, a closed polygon from the baseline pixel
  of y=0 through the points and back, filled at 30% of the series alpha; the
  outline path is drawn at full color. Markers are honored.
- **`chart_step_svg`**: step-post geometry. After each point, emit
  `L (next_x, current_y)` then `L (next_x, next_y)`. One point is a lone `M`.
- **`chart_histogram_svg`**: pools all finite ys from all series; `bins` is
  clamped to `1..200`; equal-width bins span the data range or an explicit x
  axis. Bars use the first series color (or palette 0), the zero baseline and
  the pooled counts. Auto y is `0..max_count` with integer ticks. Legend still
  lists series names.
- **`chart_pie_svg`**: first series only; positive values are slices, sum
  normalized, colors cycle the palette, start at 12 o'clock and sweep
  clockwise. Slice paths are stroked white, width 1. Negative/zero values are
  ignored. A single full slice uses two 180-degree arcs.
- **`chart_doughnut_svg`**: pie geometry with `doughnut_hole` clamped to
  `0..0.95` as the inner-radius fraction; outer and inner arcs form a
  nonzero-filled ring.
- **`chart_svg`**: dispatches on `kind`; unknown kinds render as line.

### Legend

Enabled by default. For Cartesian charts, one row per series (swatch + name)
at the top-right of the plot; labels are the series names, or `series N` when
empty. For pie/doughnut, rows are the first-series category labels with the
slice palette. Row height is 14, swatch 10x10, text size 10. Placement uses a
byte-length estimate (`6*len + 34`), not real text metrics, and is not clipped.

### Annotations

All coordinates are data coordinates mapped through the resolved scales.

- text: `text` at `(px+4, py-4)`, size 10,
- arrow: a 1px line plus a triangular head (8 long, 6 wide) at the target,
- hline: 1px line across the plot at the mapped y,
- vline: 1px line across the plot at the mapped x.

### Grid and title

`grid_y` draws one `#e6e6e6` horizontal line per y tick; `grid_x` draws one
per x tick, both behind the axes. Title is drawn only when non-empty and is
escaped.

## 12. Public API and coverage

All 74 public functions are declared below; every one is exercised by at
least one conformance check. `tNN` refers to
`tests/test_conformance.xi`.

### Formatting, escaping, colors

| Function | Checks |
|---|---|
| `chart_format_float` | t25 |
| `chart_format_value` | t26 |
| `chart_escape` | t30 |
| `color_rgb` | t05, t08 |
| `color_rgba` | t05, t31 |
| `color_none` | t06 |
| `color_with_alpha` | t08 |
| `color_from_hex` | t07, t31 |
| `color_to_hex` | t07, t08 |
| `color_lerp` | t08 |
| `palette_color` | t09 |
| `colormap_viridis` | t10 |
| `colormap_magma` | t11 |

### Series

| Function | Checks |
|---|---|
| `series_new` | t02 |
| `series_cat` | t03 |
| `series_len` | t02, t03 |
| `series_set_color` | t04 |
| `series_set_marker` | t04 |

### Scales, axes, ticks

| Function | Checks |
|---|---|
| `scale_linear` | t12, t13 |
| `scale_log` | t16 |
| `scale_map` | t12, t16 |
| `scale_map_unclamped` | t14 |
| `scale_invert` | t15 |
| `scale_min` | t13, t17 |
| `scale_max` | t13, t17 |
| `scale_span` | t17 |
| `axis_auto` | t18 |
| `axis_linear` | t18 |
| `axis_log` | t19 |
| `axis_ticks` | t19, t20 |
| `axis_scale` | t20 |
| `ticks_nice` | t21, t22 |
| `ticks_log` | t23 |
| `ticks_category` | t24 |

### Layout and elements

| Function | Checks |
|---|---|
| `chart_layout` | t28, t29 |
| `chart_layout_uniform` | t28 |
| `chart_layout_default` | t27 |
| `chart_plot_x0` | t27 |
| `chart_plot_y0` | t27 |
| `chart_plot_w` | t27, t28 |
| `chart_plot_h` | t27, t28 |
| `chart_plot_x1` | t27 |
| `chart_plot_y1` | t27 |
| `chart_rect_element` | t31 |
| `chart_circle_element` | t32 |
| `chart_line_element` | t33 |
| `chart_path_element` | t34 |
| `chart_text_element` | t35 |
| `chart_text_anchor_element` | t36 |
| `chart_polygon_element` | t37 |
| `chart_polyline_element` | t38 |
| `chart_svg_open` | t39 |
| `chart_svg_close` | t39 |

### Annotations and figures

| Function | Checks |
|---|---|
| `annotation_text` | t40 |
| `annotation_arrow` | t40 |
| `annotation_hline` | t40 |
| `annotation_vline` | t40 |
| `figure_new` | t41 |
| `figure_set_title` | t42 |
| `figure_set_axes` | t42 |
| `figure_set_kind` | t43 |
| `figure_set_grid` | t42 |
| `figure_set_legend` | t42 |
| `figure_add_annotation` | t43 |

### Renderers

| Function | Checks |
|---|---|
| `chart_line_svg` | t44, t45, t46 |
| `chart_scatter_svg` | t47, t48 |
| `chart_bar_svg` | t49, t50 |
| `chart_bar_stacked_svg` | t51, t52 |
| `chart_area_svg` | t53, t54 |
| `chart_step_svg` | t55, t56 |
| `chart_histogram_svg` | t57, t58, t59 |
| `chart_pie_svg` | t60, t61 |
| `chart_doughnut_svg` | t62, t63 |
| `chart_svg` | t68 |

Public constants `CHART_*`, `MARKER_*`, `ANNOTATION_*` are pinned by t01.
Public types are exercised through their constructors and renderers:
`ChartColor` t05, `ChartSeries` t02, `ChartLayout` t27, `ChartAxis` t18,
`ChartScale` t12, `ChartAnnotation` t40, `ChartFigure` t41.

## 13. Test plan (71 checks)

| # | Check | Pinned semantics |
|---|---|---|
| t01 | constants | kind/marker/annotation tags |
| t02 | series_new | storage/defaults/len |
| t03 | series_len | shortest non-empty vector |
| t04 | series setters | color + marker clamping |
| t05 | color constructors | channel/alpha clamps |
| t06 | none paint | `none` SVG paint |
| t07 | hex parse | case-insensitive, fail closed |
| t08 | alpha/lerp | interpolation + none |
| t09 | palette | ten colors, wrap, negative |
| t10 | viridis | endpoints/midpoint |
| t11 | magma | endpoints/midpoint |
| t12 | linear map | endpoints/midpoint/clamp |
| t13 | linear normalize | flat + reversed |
| t14 | unclamped | extrapolation |
| t15 | invert | linear + log |
| t16 | log normalize | non-positive + flat |
| t17 | accessors | min/max/span |
| t18 | axis constructors | auto/linear + clamps |
| t19 | log axis | normalization + ticks |
| t20 | axis scale | ticks + mapping |
| t21 | nice ticks | step 2 |
| t22 | nice ticks | 2.5 + negative |
| t23 | log ticks | decades + narrow |
| t24 | category ticks | indices |
| t25 | float format | halves/trim/-0 |
| t26 | value format | magnitude decimals |
| t27 | default layout | 640x360 geometry |
| t28 | custom layout | margins + uniform |
| t29 | layout clamps | >= 1 x 1 |
| t30 | escape | five entities + controls |
| t31 | rect | exact format/opacity |
| t32 | circle | radius clamp/opacity |
| t33 | line | exact format/opacity |
| t34 | path | d escape + paint pairs |
| t35 | text | escape + opacity |
| t36 | anchored text | anchor omission |
| t37 | polygon | flat pairs + empty |
| t38 | polyline | flat pairs + opacity |
| t39 | svg root | exact open/close |
| t40 | annotations | constructors |
| t41 | figure defaults | axes/grid/legend/style |
| t42 | figure setters | title/axes/grid/legend |
| t43 | kind/annotations | clamp + append |
| t44 | line multi | two paths/markers/legend |
| t45 | line snapshot | exact document |
| t46 | line edge | single point + empty |
| t47 | scatter markers | all five shapes |
| t48 | scatter empty | frame only |
| t49 | bar snapshot | exact grouped document |
| t50 | bar negative/width | baseline + bar_width |
| t51 | stacked positive | exact rects |
| t52 | stacked negative | exact rects |
| t53 | area | polygon + outline |
| t54 | area multi/empty | two fills + no fill |
| t55 | step | exact step-post path |
| t56 | step single | lone M |
| t57 | histogram bins | pooled counts + bars |
| t58 | histogram flat | widened range |
| t59 | histogram clamps | bins >= 1 + axes |
| t60 | pie snapshot | exact two-slice document |
| t61 | pie full/negative | full arcs + ignore <=0 |
| t62 | doughnut | outer/inner arcs |
| t63 | doughnut clamp | hole 0..0.95 |
| t64 | annotations render | text/arrow/hline/vline |
| t65 | legend toggle | on/off |
| t66 | grid toggle | both directions |
| t67 | title/background | escaping + color |
| t68 | dispatch | all nine kinds |
| t69 | determinism A | line/bar/dispatch |
| t70 | determinism B | pie/doughnut/histogram |
| t71 | empty figures | every kind safe |

All Str equality uses `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17), and every Vec element read is bound to a typed local. The suite is
pure: no filesystem, no FFI, no clocks, no randomness.

## 14. Known limitations

- No text metrics: titles, labels and legends can overlap or clip; legend
  placement is a byte-length estimate.
- Category x axes ignore an explicit x domain; x is always linear for
  categories.
- Log axes map non-positive values to the domain minimum; log bar baselines
  therefore sit at the domain minimum rather than at zero.
- Pie/doughnut render only the first series; slices ignore negative and zero
  values. There are no per-slice labels or explode offsets.
- Stacked bars with an explicit y domain clip at the plot edge (no clip path);
  out-of-domain geometry is not clipped for any renderer.
- Histogram bins always have equal width over the data range (or explicit x
  domain); no Freedman-Diaconis/Sturges rules.
- Auto x for line/area/step with explicit xs pads 5%; with one point the
  domain is `[-0.5, 0.5]`.
- `ticks_nice` returns at most the grid multiples inside the domain and may
  return fewer ticks than requested.
- Values above 9e15 format as `"0"` to avoid Int overflow in the rounding
  path; domains are assumed sane.
- Marks outside the plot are not clipped; no `<clipPath>` is emitted.
- The y axis label is horizontal at x=8, not rotated.
- No SVG parser/validator; output is text only. Control bytes below 0x20
  other than NUL pass through and may produce markup XML 1.0 rejects.
- Escaping is not idempotent for strings containing `&`.

## 15. Compiler / stdlib notes (v0.64.8)

- Free functions only; no methods, no inline lambdas.
- `Vec[StructType]` (`ChartSeries`, `ChartAnnotation`) works on the pin and is
  used for the model; public struct names are prefixed (`Chart*`) to avoid the
  stdlib type-name collision documented in 0.1.0.
- Str values read from `Vec[Str]` are bound to typed locals before use
  (BUG 17 discipline). The module itself performs no Str comparisons.
- `Float64` casts use `as Float64`; Int rounding uses `to_int`.
- Math imports: `math.log10`, `math.pow`, `math.sin`, `math.cos`,
  `math.atan2`; `num.floor`, `num.ceil`, `num.is_finite`.
- Strings are built by concatenation; byte-level work is confined to
  `chart_escape` (builder) and the hex formatter.
- Tests call checks directly (no fn tables) and use `assert(cond, name)`.
