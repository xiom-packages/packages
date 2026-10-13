# xiom.harfbuzz

HarfBuzz **14.6.0** bindings for XIOM -- text shaping and font
subsetting, vendored and statically linked (no DLL, no system harfbuzz).

- **Full declared surface**: 571/571 functions of the `hb.h` + `hb-ot.h` +
  `hb-subset.h` + `hb-version.h` include closure, generated from the
  pinned headers (`tools/gen_harfbuzz.py`); 592 value constants;
  **skips = 0**. Coverage: `docs/COVERAGE.md`.
- **Vendored source**: `vendor/harfbuzz/src/**` at tag `14.6.0`
  (`c7a7457b7385f33178e8cf87615ca077a810bbe7`, "Old MIT"), compiled as
  the single-TU amalgam `harfbuzz-subset.cc`. See `PROVENANCE.md`.
- **Discipline**: pointers/handles cross as `Int` (B-25), C writes into
  XIOM-owned slots (B-20/B-24), flat outcome structs (B-26). See
  `SPEC.md` section 5.

## Usage

```xiom
use xiom.harfbuzz;            // safe probes + pin helpers
use xiom.harfbuzz.gen.buffer; // full generated surface (externs + consts)

// Shape over caller-owned font bytes (Vec[UInt8] kept alive by the caller):
let p = hb_shape_probe(&mut font_bytes, font_bytes.len(), 0); // 0 = "AV"
if p.ok {
  // p.glyph_count, p.direction, p.first_glyph, p.advance0, p.advance_sum, p.upem
}
```

The generated modules also expose the raw API for advanced use, e.g.
`version.hb_version_atleast(...)`, `face.hb_face_get_glyph_count(face)`,
`blob.hb_blob_get_length(blob)`. Handles returned by the bridge
(`hb_face_open_probe` / `hb_font_open_probe`) are `Int` values that can be
passed straight back into generated externs.

Module map (34 modules):

| Module | Content |
|---|---|
| `xiom.harfbuzz` | root: bridge wrappers, flat outcome structs, pin helpers, surface bookkeeping |
| `xiom.harfbuzz.gen.version` | `HB_VERSION_*`, `hb_version*` |
| `xiom.harfbuzz.gen.common` | tags, direction/script/language basics |
| `xiom.harfbuzz.gen.blob`, `gen.buffer`, `gen.face`, `gen.font` | lifetimes, buffers, faces, fonts |
| `xiom.harfbuzz.gen.shape`, `gen.shape_plan`, `gen.unicode`, `gen.style` | shaping pipeline |
| `xiom.harfbuzz.gen.ot_layout`, `gen.ot_math`, `gen.ot_meta`, `gen.ot_metrics`, `gen.ot_name`, `gen.ot_shape`, `gen.ot_var`, `gen.ot_color`, `gen.ot_font`, `gen.ot_fetch` | OpenType layout/introspection |
| `xiom.harfbuzz.gen.subset`, `gen.subset_serialize`, `gen.subset_depend` | subsetting |
| `xiom.harfbuzz.gen.set`, `gen.map`, `gen.paint`, `gen.draw`, `gen.deprecated`, `gen.ot_deprecated`, `gen.script_list`, `gen.surface`, `gen.hb`, `gen.ot` | sets/maps, paint/draw, deprecated surfaces, oracle |

## Tests

`tests/test_conformance.xi` (27 checks, vendored runtime):

- **S1 version pin** -- `HB_VERSION_*` constants, runtime `hb_version()`,
  `hb_version_string()`, `hb_version_atleast(14,6,0)` through the
  generated extern.
- **S2 surface coverage** -- declared count 571, linked symbol count,
  FNV-1a name hash vs the generator oracle, zero null slots.
- **S3 fixture + face** -- bundled `tests/fixtures/tiny.ttf` (original
  generated 3-glyph font) loads; face probe (upem 1000, 3 glyphs, A=1,
  V=2); handle round-trips through generated externs; sfnt table lengths
  (head/cmap/glyf/hmtx present, GPOS absent).
- **S4 shaping** -- `"AV"` shapes to 2 LTR glyphs with advances 500 + 600;
  `"A"` to gid 1 with advance 500; Arabic U+0627 guesses RTL and maps to
  .notdef.
- **S5 subset + re-shape** -- subset to U+0041 serializes (588 bytes),
  re-shapes to 1 glyph at advance 500, and `"AV"` on the subset drops V
  to .notdef (advance sum 1000).

Run:

```powershell
.\scripts\port.ps1 -Package xiom.harfbuzz -TimeoutSec 900
```

The first build dominates (~30 s for the 7 MB amalgam); the compiler
`--timeout 900` in `port.args.json` covers it.

## Out of scope (by construction)

`hb-ft.h` (FreeType), `hb-gobject.h` (GObject), `hb-icu.h` (ICU),
`hb-cairo.h` (cairo) require external dependencies and are not part of the
declared surface; `HB_EXPERIMENTAL_API` / `HB_NO_SUBSET_DEPEND` opt-in
declarations are excluded (11 functions, listed in
`docs/gen_manifest.json`). Full rationale: `SPEC.md` section 4.
