# xiom.charts -- Roadmap

Static-first charting for XIOM. The package is deliberately split from the
future interactive layer so that deterministic SVG export, the data model and
the geometry remain usable without a GUI.

## 0.1.0 -- integer line/bar (published)

- Integer `ChartSeries`, fixed `ChartLayout`, linear scaling with
  half-away-from-zero rounding, integer ticks, five-entity XML escaping.
- `chart_bar_svg` and `chart_line_svg`.
- 28 conformance checks.

## 0.2.0 -- P1 static 2D core (this release)

- Float64 model: numeric x or category labels, series name/color/marker/
  opacity, drift guard.
- Linear and base-10 log scales with clamping/inversion; auto and explicit
  axes; nice linear ticks, power-of-ten log ticks, category ticks.
- Layout with four margins; gridlines; title/axis labels; legend.
- Color model with alpha and `none`, ten-color palette, viridis/magma
  colormaps, interpolation and hex I/O.
- Markers (circle/square/diamond/cross/triangle) and data-coordinate text,
  arrow, horizontal and vertical annotations.
- Nine renderers: line, scatter, grouped bar, stacked bar, area, step,
  histogram, pie, doughnut; `chart_svg` dispatcher.
- Deterministic formatting (3-decimal coordinates, `-0` normalized,
  non-finite -> `0`) and byte-stable documents.
- 71 conformance checks, including exact snapshots for line/bar/pie.
- Publish stays `false` until the lane files the P1 scope-delta request.

## 0.2.x -- maintenance

- Bug fixes and documentation only; the public surface is frozen for the
  P2 work unless a correctness issue requires an additive fix.
- Keep the 0.2.0 API stable for `xiom.plots` consumers.

## 0.3.0 -- P2 static 3D projection

- 3D axis model (x/y/z), orthographic and perspective camera parameters,
  depth sorting rules.
- Surface, wireframe, scatter3d and line3d emitters as static SVG
  projections.
- Shared color/colormap model and tick locators with the 2D code.
- No interaction; camera is data, output remains byte-stable.

## `xiom.plots` (separate package) -- P3 interactive

- Figure/gridspec/axes hierarchy, multiple panels, constrained layout.
- Backends: SVG export via `xiom.charts`; OpenGL via `xiom.opengl`.
- Pan/zoom/pick/hover, animated updates, event routing, camera control for
  3D.
- Owns interactive state; `xiom.charts` stays pure and stateless.

## Explicit non-goals for later phases

Deferred beyond 0.3.0 unless separately scoped:

- heatmap/imshow/contour/quiver/streamplot/spectrogram,
- candlestick/OHLC, box/violin, error bars, regression/statistical plots,
- treemap/sunburst/radar/polar/dual axes,
- SVG parsing, DOM, CSS, gradients/filters/clip paths, text shaping or
  measurement, time/date axes, locale formatting,
- file I/O, registry integration, threading, randomness.

## Quality gates

Every release: two clean suite runs on the pinned compiler, no filesystem/FFI
in the package, public API coverage table in `SPEC.md`, and STATUS updated
with the exact pass count. Publishing is a separate lane action; this package
never toggles `publish` on its own.
