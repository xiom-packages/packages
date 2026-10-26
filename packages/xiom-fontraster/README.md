# xiom.fontraster

## Status

- Stage: **incubating**; registry **LIVE** -- `xiom.fontraster` 0.1.0, single tag `xiom-fontraster/v0.1.0` (2026-10-24; sha256 `b945aff7...`).
- **0.1.1 (prepared, publish pending owner GO):** adds `#[owns_return]` to
  `font_shape`, `font_glyph_raster`, and `font_face_metrics`. The compiler
  drops the transient `buf`/`slots` buffers and the caller drops the returned
  `TextRun.glyphs` / `GlyphRaster.pixels` aggregate fields; this is the
  per-frame UI soak fix (engine `xiom.toml` pins `0.1.1`). Conformance is
  **11/11 PASS** on the working compiler.
- Conformance: `tests/test_conformance.xi` -- **11/11 PASS x2** (compiler v0.65.0); installed 2-level consumer (consumer -> fontraster -> harfbuzz) **PASS x2** with no undefined `hb_*`, from both the tree install and the registry artifact.
- Source: engine package `packages/xiom-fontraster` at `E:\xiom-projects\xiom-engine`
  (carved verbatim; same module and native ABI).

Runtime glyph rasterizer for the engine-owned UI2 stack. It uses HarfBuzz
(installed `xiom.harfbuzz` package, linked symbols) for TTF/OTF parsing,
OpenType shaping and outline extraction, then rasterizes 8-bit coverage
with a non-zero-winding scanline fill (8 sub-scanlines, exact horizontal
coverage).

## API (`module xiom.fontraster`)

- `font_face_open(bytes: &mut Vec[UInt8]) -> FontFace` -- the caller's
  bytes must outlive the face (HarfBuzz blob is READONLY, caller-owned).
- `font_face_close(&mut FontFace)`
- `font_face_metrics(&FontFace, px) -> FontMetrics` (1/64 px)
- `font_glyph_index(&FontFace, codepoint) -> Int` (-1 if unmapped)
- `font_glyph_raster(&FontFace, glyph, px) -> GlyphRaster` (coverage,
  bearing, advance in 1/64 px)
- `font_shape(&FontFace, text: Str, px) -> TextRun` (glyph ids, clusters,
  advances, offsets; UTF-8, bidi/ligatures/kerning via HarfBuzz)

`font_glyph_raster` creates a fresh `hb_font_t` per call, so one face handle
is safe to use from several workers; the engine's glyph cache is currently
single-threaded (`engine/ui2/text.xi`).

## Source / build

This tree entry is `packages/xiom-fontraster` in the registry repository. The
native shim is `src/fontraster.c`; it declares only the small HarfBuzz ABI it
needs, so no HarfBuzz headers or source are vendored into this package.
`port.args.json` compiles only `${PACKAGE_DIR}/src/fontraster.c`; on compiler
v0.65.0 the dependency walk applies `xiom.harfbuzz`'s shipped
`port.args.json` (its vendored amalgamation, C++17) transitively, so the link
resolves `hb_*` for both the in-tree suite and an installed consumer (m1511
closure; `-1511` / `-1615` verified on the v0.65.0 archive). Compiler v0.64.8
and earlier do not apply a dependency's `port.args.json`, so this package
cannot build on those pins.
Registry install: `xiom pkg install xiom.fontraster@0.1.0` -- lands as
`XIOM_HOME/packages/xiom-fontraster-0.1.0` (registry dash form) and pulls
`xiom.harfbuzz` as the one transitive dependency. Engine A13 should use the
registry install, not `xiom-pkg install --root`. The 0.1.1 artifact is not
published yet; install it from the tree for the current test candidate.

## Test fixture / licensing

`tests/fixtures/Inter_Regular.ttf` is the Inter Regular face from the engine
asset set, used only by the conformance suite (face/metrics, cmap, shaping at
32 px, 8-bit AA raster, and the typed error arms). It is distributed under the
SIL Open Font License 1.1; the verbatim license text travels beside it as
`tests/fixtures/LICENSE.Inter.txt`. See <https://rsms.me/inter/>. The suite is
SKIP-safe when the fixture is absent.

## Evidence

`tests/test_conformance.xi`: face/UPEM/metrics, cmap (mapped + control),
`shape("AV")`/`shape("")`, raster('A', 32) coverage, empty-bytes none-face,
raster on a closed face, invalid glyph id, idempotent close; PASS 11/11 x2 on
v0.64.8. Engine-side probes (not part of this package's suite) remain at
`tests/probes/probe_fontraster.xi` and `tests/probes/probe_ui2_text.xi` in the
engine tree.
