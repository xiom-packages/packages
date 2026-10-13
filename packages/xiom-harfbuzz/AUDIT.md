# AUDIT: xiom.harfbuzz

## Status (2026-10-13)

Vendored C++ binding at 0.1.0 -- the first `xiom.harfbuzz` release. The
package does not link any system library; the vendored amalgam is compiled
from source at port time.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 (pin) |
| Upstream | harfbuzz 14.6.0 (commit `c7a7457b`, "Old MIT"), vendored `src/**` byte-exact |
| Link model | `--c-source` (amalgam `harfbuzz-subset.cc` + `src/hb_bridge.cpp` + `src/hb_symbols_gen.c`) via `port.args.json`, `--cxx-standard 17`, `--timeout 900` |
| FFI confinement | `unsafe` in XIOM confined to the root module `src/harfbuzz.xi`; `extern "C"` in the bridge/TU only (G5) |
| Declared surface | 571 functions, 592 value constants, 0 skips (`docs/COVERAGE.md`) |
| Suite | `tests/test_conformance.xi`, 27 checks |
| Runs | **PASS 27/27 x2** on the pin (`scripts/port.ps1 -Package xiom.harfbuzz -TimeoutSec 900`) |

## Design notes

- **Generation over hand-picking**: `tools/gen_harfbuzz.py` resolves the
  include closure of the four declared roots (32 headers), extracts every
  `HB_EXTERN` declaration, every enum member and every object-like
  `#define` value, and emits one XIOM module per header plus the
  symbol-table TU and the coverage oracle. `--check` fails on drift.
- **Default-build semantics**: the two guards that change the declared
  surface are modeled exactly (`HB_EXPERIMENTAL_API` undefined by default,
  `HB_NO_SUBSET_DEPEND` defined by default via `hb-config.hh`); their 11
  declarations are excluded and listed -- the linker confirms those
  symbols are genuinely absent from the verified artifact.
- **Scalar-correct ABI**: pointers/handles -> `Int`; `hb_bool_t` /
  `hb_position_t` -> `Int32`; `hb_codepoint_t` / `hb_mask_t` / `hb_tag_t`
  / `hb_ot_tag_t` / `hb_ot_name_id_t` / `hb_color_t` -> `UInt32`;
  `float` -> `Float32`; function-pointer typedefs (and typedef aliases of
  them) -> `Int`.
- **No foreign-pointer reads (B-20/B-24)**: probe results are written by C
  into XIOM-owned 4-byte slots and read byte-indexed little-endian; the
  font bytes flow XIOM -> C (READONLY blob for the call duration). No
  XIOM code dereferences a pointer returned by C.
- **Handles as Int (B-25)**: `xhb_face_open` / `xhb_font_open` return
  pointers as `Int` values; the suite passes them into generated externs
  (`hb_face_get_glyph_count`, `hb_face_get_upem`, `hb_font_get_face`) and
  back into the bridge close functions. No `Int as *UInt8` anywhere.
- **Flat outcomes (B-26)**: `HbshapeOutcome` / `HbfaceOutcome` /
  `HbsubsetOutcome` are flat structs with scalar fields; no
  `Result[Option[T]]` shapes.
- **Str discipline**: the only `Str` comparisons in the suite go through
  `xiom.string.compare.str_compare` (version string + pin identity); C
  string handling never crosses as a bare pointer into XIOM.
- **Module-file convention**: generated module `xiom.harfbuzz.gen.<name>`
  lives in `src/<name>.xi` (package resolver convention; the root module
  `xiom.harfbuzz` lives in `src/harfbuzz.xi` per the repo precedent).

## Fixture

`tests/fixtures/tiny.ttf` is an original 632-byte generated font (three
glyphs, cmap format 4, hmtx advances 500/600, no GPOS/GSUB). It is
regenerable (`tests/fixtures/make_tiny_font.py`) and carries no third-party
license (PROVENANCE.md section 5). Its OS/2 table is v1 (86 bytes) -- v2+
headers with a v1 body fail the harfbuzz subsetter sanitize step (observed
during bring-up; kept as a build-time-verified fixture invariant).

## Non-goals

- No optional backends (FreeType/GObject/ICU/cairo/graphite2/platform
  shapers) -- external dependencies, out of declared scope (SPEC.md
  section 4).
- No upstream test-corpus import; probes assert semantic invariants on the
  generated fixture plus the compile-time pin.
- No dynamic loading and no `runtime_deps`: the package is fully static.
