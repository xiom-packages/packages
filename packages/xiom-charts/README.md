# xiom.charts

> **Status:** `incubating` -- 71/71 conformance checks on the v0.64.8 pin;
> `0.2.0` published as single tag `xiom-charts/v0.2.0` (sha256 `7dddb907...`,
> 2026-10-21; existing name, no scope delta needed).
> **Scope:** a pure-XIOM static-2D chart model plus a deterministic SVG 1.1
> emitter: Float64 scales, linear/log axes, tick locators, gridlines, legends,
> markers, annotations, a colormap-ready color model, and nine chart types.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.convert`, `xiom.format.number`, `xiom.math`, `xiom.num`; tests add
> `xiom.test`, `xiom.io`, `xiom.string.compare`). No FFI, no I/O.

## What it is

`xiom.charts` turns Float64 data series into a complete SVG document as text.
It is the static foundation for the charts/plots program: `xiom.plots` (the
future interactive layer) can consume this package's model, scales, color
model and element emitters without going through a renderer.

0.2.0 is a breaking redesign of the 0.1.0 integer line/bar module. Every
coordinate is Float64; output is quantized to at most three decimals and is
byte-stable across repeated calls.

Highlights:

- **Chart types:** multi-series line, scatter, grouped bar, stacked bar
  (positive and negative), area, step, histogram, pie and doughnut.
- **Axes:** linear and base-10 logarithmic scales, auto or explicit domains,
  "nice" 1/2/2.5/5/10 ticks, power-of-ten log ticks, category tick labels.
- **Layout:** four independent margins, clamped to keep the plot >= 1 x 1.
- **Style:** ten-color palette, viridis/magma colormaps, hex parse/format,
  alpha, five marker shapes.
- **Document:** background, title, gridlines, axes, tick labels, axis labels,
  legend, annotations, and a `chart_svg` kind dispatcher.
- **Safety:** no global state, no filesystem, no FFI, no clocks or randomness.

## Quick start

```xi
use xiom.charts;

fn sample() -> Str {
  var labels = Vec[Str].new();
  labels.push("Mon");
  labels.push("Tue");
  labels.push("Wed");
  var values = Vec[Float64].new();
  values.push(3.0);
  values.push(11.0);
  values.push(7.5);

  var series = Vec[ChartSeries].new();
  series.push(series_cat("visits", labels, values));

  var figure = figure_new(series, chart_layout_default());
  figure_set_title(&mut figure, "Weekly visits");
  figure_set_kind(&mut figure, CHART_BAR);
  return chart_svg(&figure);          // complete <svg>...</svg> text
}
```

Render with `io.println(sample())` or write the string through the caller's
chosen I/O layer; this package never touches the filesystem.

## Chart types

| Kind | Renderer | Notes |
|---|---|---|
| `CHART_LINE` | `chart_line_svg` | one path per series, optional markers |
| `CHART_SCATTER` | `chart_scatter_svg` | markers only; `MARKER_NONE` -> circles |
| `CHART_BAR` | `chart_bar_svg` | grouped categories, negative-aware |
| `CHART_BAR_STACKED` | `chart_bar_stacked_svg` | positive up, negative down |
| `CHART_AREA` | `chart_area_svg` | 30% fill plus outline |
| `CHART_STEP` | `chart_step_svg` | step-post geometry |
| `CHART_HISTOGRAM` | `chart_histogram_svg` | pooled series, equal-width bins |
| `CHART_PIE` | `chart_pie_svg` | first series, positive slices |
| `CHART_DOUGHNUT` | `chart_doughnut_svg` | pie + inner-radius fraction |

`chart_svg(&figure)` dispatches on `figure.kind`; the individual renderers are
public for callers that want to pin a kind explicitly.

## API map

**Model**

| Function | Returns | Description |
|---|---|---|
| `series_new(name, xs, ys)` | `ChartSeries` | numeric x coordinates |
| `series_cat(name, labels, ys)` | `ChartSeries` | category labels, index x |
| `series_len(s)` | `Int` | shortest non-empty parallel vector |
| `series_set_color(s, c)` | -- | explicit color (disables auto palette) |
| `series_set_marker(s, marker)` | -- | `MARKER_*`, invalid -> none |

**Scales / axes / ticks**

| Function | Returns | Description |
|---|---|---|
| `scale_linear(min,max,p0,p1)` | `ChartScale` | linear value -> pixel |
| `scale_log(min,max,p0,p1)` | `ChartScale` | base-10 log value -> pixel |
| `scale_map(s,v)` / `scale_map_unclamped(s,v)` | `Float64` | clamped / extrapolating map |
| `scale_invert(s,px)` | `Float64` | pixel -> value |
| `scale_min/max/span(s)` | `Float64` | domain accessors |
| `axis_auto(label,ticks)` | `ChartAxis` | data-derived domain |
| `axis_linear(min,max,label,ticks)` | `ChartAxis` | explicit linear |
| `axis_log(min,max,label,ticks)` | `ChartAxis` | explicit log |
| `axis_ticks(a)` / `axis_scale(a,p0,p1)` | `Vec[Float64]` / `ChartScale` | axis helpers |
| `ticks_nice(min,max,count)` | `Vec[Float64]` | 1/2/2.5/5/10 locator |
| `ticks_log(min,max)` | `Vec[Float64]` | powers of ten |
| `ticks_category(n)` | `Vec[Float64]` | `0..n-1` |

**Layout / colors / formatting**

| Function | Returns | Description |
|---|---|---|
| `chart_layout(w,h,l,r,t,b)` | `ChartLayout` | explicit margins |
| `chart_layout_uniform(w,h,pad)` | `ChartLayout` | uniform margins |
| `chart_layout_default()` | `ChartLayout` | 640x360 |
| `chart_plot_x0/y0/w/h/x1/y1(l)` | `Float64` | plot rectangle |
| `color_rgb/rgba(...)` | `ChartColor` | construct with clamps |
| `color_none()` | `ChartColor` | SVG `none` paint |
| `color_with_alpha(c,a)` | `ChartColor` | alpha copy |
| `color_from_hex(s)` / `color_to_hex(c)` | `ChartColor` / `Str` | `#rrggbb` |
| `color_lerp(a,b,t)` | `ChartColor` | RGB interpolation |
| `palette_color(i)` | `ChartColor` | ten-color cycle |
| `colormap_viridis(t)` / `colormap_magma(t)` | `ChartColor` | sampled colormaps |
| `chart_format_float(x,decimals)` | `Str` | fixed decimals, trimmed |
| `chart_format_value(x)` | `Str` | magnitude-adaptive |
| `chart_escape(s)` | `Str` | five XML entities |

**Elements / annotations / figures**

| Function | Returns | Description |
|---|---|---|
| `chart_rect_element` / `chart_circle_element` / `chart_line_element` | `Str` | SVG leaves |
| `chart_path_element` / `chart_text_element` / `chart_text_anchor_element` | `Str` | SVG leaves |
| `chart_polygon_element` / `chart_polyline_element` | `Str` | flat point pairs |
| `chart_svg_open(w,h)` / `chart_svg_close()` | `Str` | root open/close |
| `annotation_text/arrow/hline/vline(...)` | `ChartAnnotation` | data-coordinate annotations |
| `figure_new(series,layout)` | `ChartFigure` | auto axes, y-grid, legend |
| `figure_set_title/axes/kind/grid/legend(...)` | -- | figure setup |
| `figure_add_annotation(f,a)` | -- | append annotation |
| `chart_line_svg` ... `chart_doughnut_svg` | `Str` | renderers |
| `chart_svg(f)` | `Str` | kind dispatcher |

`SPEC.md` has the exact formulas, attribute order, document ordering, auto-
domain rules, coverage table (`t01..t71`), and limitations.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 71 `[PASS]` lines, `xiom.charts: all tests passed`, exit 0. The
suite is pure: exact document snapshots for line/bar/pie, exact element
strings, numeric model checks, and determinism checks for every renderer.

## Design for `xiom.plots`

The package keeps three layers separate:

1. **model** -- `ChartColor`, `ChartSeries`, `ChartAxis`, `ChartScale`,
   `ChartAnnotation`, `ChartFigure`;
2. **geometry** -- scales, tick locators, layout, formatting;
3. **render** -- element emitters and static renderers.

There is no global state and no hidden cache. `xiom.plots` can build model
values, use `scale_*`/`ticks_*` for interaction math, and reuse
`chart_*_element` for its own SVG export without invoking the full static
renderers.

## Non-goals (later phases)

Heatmap/imshow/contour/candlestick/box/violin/error bars, 3D projection and
surfaces (charts 0.3), interactive pan/zoom/pick plus figure/gridspec and
OpenGL backends (`xiom.plots`), SVG parsing/DOM/CSS/defs/gradients, text
metrics, time axes, and scientific notation.

## Install / publish

```
xiom pkg install xiom.charts@0.2.0      # after the lane lands the publish request
xiom pkg publish                        # maintainer (needs XIOM_REGISTRY_TOKEN)
```

`0.2.0` was published on 2026-10-21 as single tag `xiom-charts/v0.2.0`
(sha256 `7dddb907...`); later versions re-run the normal allowlist/publish flow.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
