# xiom.charts

> **Status:** `incubating` -- conformance-tested (28/28); not yet published on the XIOM registry.
> **Scope:** one pure-XIOM module that turns integer data series into
> deterministic SVG line and bar charts: integer layout, linear scaling with
> documented rounding, axis ticks, and XML-escaped text output.
> **Deps:** `xiom.std` only (the module imports `xiom.string`,
> `xiom.string.builder` and `xiom.convert`; tests add `xiom.test`, `xiom.io`
> and `xiom.string.compare`). No FFI.

## What it is

`xiom.charts` is a small, deterministic chart renderer that emits SVG text.
It is the first real implementation behind the `xiom.charts` placeholder:
this release ships **line and bar charts** with a fixed integer layout and a
fixed default palette. Everything is integer arithmetic -- there is no
`Float64` anywhere and no floating-point rounding to reason about:

- an integer data model (`ChartSeries`: parallel label/value vectors),
- an integer layout (`ChartLayout`: canvas size, uniform padding, tick count)
  whose constructor clamps every field so the plot rectangle is always at
  least 1 x 1,
- linear value-to-pixel scaling with round-half-away-from-zero (the exact
  formula is in `SPEC.md`),
- evenly spaced y-axis ticks and gridlines,
- a complete `<svg>` document with axes, tick labels, escaped category labels
  and either one `<rect>` per bar or one `<path>` polyline,
- five-entity XML escaping (`& < > " '`) for every Str that reaches the
  output.

The placeholder's wider inventory (area, pie, doughnut, scatter, bubble,
radar, polar, box, candlestick, histogram, heatmap, treemap, sunburst,
statistical plots) is **not implemented yet**; only `line` and `bar` exist in
this release.

## API

| Function | Returns | Description |
|---|---|---|
| `series_new(labels, values)` | `ChartSeries` | Wrap parallel label/value vectors. |
| `series_len(s)` | `Int` | `min(labels.len(), values.len())` -- the drift guard every reader uses. |
| `chart_min(s)` / `chart_max(s)` | `Int` | Extremes over the usable prefix; `0` for an empty series. |
| `chart_layout(width, height, pad, ticks)` | `ChartLayout` | Clamped layout (size >= 1, pad fits the canvas, ticks >= 2). |
| `chart_plot_x0(l)` / `chart_plot_y0(l)` | `Int` | Plot rectangle origin (= `pad`). |
| `chart_plot_w(l)` / `chart_plot_h(l)` | `Int` | Plot rectangle size (>= 1 x 1). |
| `chart_scale_y(v, dom_min, dom_max, y_bottom, plot_h)` | `Int` | Linear value -> pixel y, clamped to the domain, half-away rounding. |
| `chart_ticks(dom_min, dom_max, count)` | `Vec[Int]` | `max(count, 2)` ascending ticks spanning the domain inclusive. |
| `chart_escape(s)` | `Str` | Escape the five XML metacharacters. |
| `chart_rect_element(x, y, w, h, fill)` | `Str` | `<rect .../>`; empty fill omitted; fill escaped. |
| `chart_line_element(x1, y1, x2, y2, stroke, stroke_width)` | `Str` | `<line .../>`; stroke always emitted and escaped. |
| `chart_path_element(d, fill, stroke, stroke_width)` | `Str` | `<path .../>`; `d` always emitted; empty fill/stroke (and width with it) omitted. |
| `chart_text_element(x, y, text, font_size, fill)` | `Str` | `<text ...>escaped</text>`; empty fill omitted. |
| `chart_bar_svg(s, l)` | `Str` | Complete SVG document: bars + category labels. |
| `chart_line_svg(s, l)` | `Str` | Complete SVG document: one polyline path + category labels. |

```xi
use xiom.charts;

var labels = Vec[Str].new();
labels.push("Mon");
labels.push("Tue");
var values = Vec[Int].new();
values.push(3);
values.push(11);
let s = series_new(labels, values);
let l = chart_layout(120, 60, 12, 3);
io.println(chart_bar_svg(&s, &l));   // complete <svg>...</svg> string
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 28 `[PASS]` lines, then `xiom.charts: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.charts@0.1.0     # consumer (after the registry publish)
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
