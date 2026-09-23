# xiom.svg

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** SVG 1.1 document builder: element helpers, escaping, and a
> deterministic renderer for in-memory documents.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.builder`). Tests additionally use
> `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.svg` builds SVG documents as plain `Str` values, with no FFI and no
filesystem access. You create a canvas with `svg_new`, append elements built
by the shape helpers (or by your own code) with `svg_add`, and serialize with
`svg_render`. Output is byte-deterministic: fixed attribute order, LF line
endings, a two-space indent per element line, and an `xmlns`-carrying `<svg>`
root element.

Geometry is integer-only (see Limitations); the module contains no parser, no
layout engine, and no serializer beyond the documented element formats.

## API

| Function | Returns | Description |
|---|---|---|
| `svg_new(width, height)` | `SvgDoc` | Empty canvas; non-positive width/height clamp to `1`. |
| `svg_add(d, element)` | `Void` | Appends a prebuilt element string verbatim. |
| `svg_element_count(d)` | `Int` | Number of appended elements. |
| `svg_rect(x, y, w, h, fill)` | `Str` | `<rect x y width height fill/>`; empty `fill` omits the attribute. |
| `svg_circle(cx, cy, r, fill)` | `Str` | `<circle cx cy r fill/>`; empty `fill` omits the attribute. |
| `svg_ellipse(cx, cy, rx, ry, fill)` | `Str` | `<ellipse cx cy rx ry fill/>`; empty `fill` omits the attribute. |
| `svg_line(x1, y1, x2, y2, stroke, stroke_width)` | `Str` | `<line x1 y1 x2 y2 stroke stroke-width/>`; `stroke` is escaped and always present. |
| `svg_text(x, y, text, font_size, fill)` | `Str` | `<text x y font-size fill>escaped text</text>`; `text` is escaped, empty `fill` omits the attribute. |
| `svg_path(d, fill, stroke)` | `Str` | `<path d fill stroke/>`; `d` and `stroke` escaped, empty `fill`/`stroke` omit their attribute. |
| `svg_escape(s)` | `Str` | Escapes `&` `<` `>` `"` `'` as predefined entities. |
| `svg_render(d)` | `Str` | Header + indented element lines + footer, joined with LF. |

Attribute order is fixed (parameter order). See `SPEC.md` for the exact
formats and the escaping table.

## Usage

```xi
use xiom.svg;
use xiom.io;

fn main() -> Int {
  var d = svg_new(120, 80);
  svg_add(&mut d, svg_rect(0, 0, 120, 80, "#f0f0f0"));
  svg_add(&mut d, svg_circle(60, 40, 20, "steelblue"));
  svg_add(&mut d, svg_text(10, 70, "Hello & goodbye", 12, "black"));
  io.println(svg_render(&d));
  return 0;
}
```

Rendered output:

```
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
  <rect x="0" y="0" width="120" height="80" fill="#f0f0f0"/>
  <circle cx="60" cy="40" r="20" fill="steelblue"/>
  <text x="10" y="70" font-size="12" fill="black">Hello &amp; goodbye</text>
</svg>
```

Custom markup (groups, gradients, filters) can be appended as prebuilt
strings with `svg_add`; they are included verbatim and never reformatted.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.svg
```

Expected tail: 20 `[PASS]` lines, `xiom.svg: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Integer geometry only.** All coordinates, sizes and stroke widths are
  `Int`; there is no `Float64` path. Fractional coordinates must be scaled to
  integers by the caller (e.g. multiply by 10 and keep the scale alongside the
  document).
- **No transforms, gradients, filters, clip paths, patterns, animation or
  styling (CSS).** Only the six element helpers exist; anything else must be
  appended as a prebuilt string.
- **No path-data parsing.** `svg_path` does not validate `d`; it escapes it
  and emits it verbatim.
- **Paint values are not escaped.** `fill` (everywhere) and `stroke` on
  `svg_line` are emitted verbatim; pass trusted values, since quotes there
  would break the attribute.
- **No XML/DOCTYPE header, no pretty-printing options, no round-trip parser.**
- Negative geometry is emitted as-is (only `svg_new` clamps), and an empty
  element string appended with `svg_add` still produces an indented empty
  line.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
