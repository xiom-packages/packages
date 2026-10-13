# SPEC: xiom.harfbuzz (binding tier -- G0..G7)

Status: 0.1.0 (incubating). Package: `xiom.harfbuzz`, 34 modules (root
`xiom.harfbuzz` + 33 generated `xiom.harfbuzz.gen.*`).

## 1. Target and model

| Item | Value |
|---|---|
| Upstream | `github.com/harfbuzz/harfbuzz` |
| Pin | tag **14.6.0** = commit `c7a7457b7385f33178e8cf87615ca077a810bbe7` |
| License | "Old MIT" (`vendor/harfbuzz/COPYING`); per-dir COPYINGs verified (see PROVENANCE.md) |
| Model | **vendored source, statically linked** (the `xiom.meshopt` pattern): no system harfbuzz, no DLL, no dynamic loader |
| Build | `--c-source vendor/harfbuzz/src/harfbuzz-subset.cc` (single-TU amalgam: core + subset + instancer) + `src/hb_bridge.cpp` + `src/hb_symbols_gen.c`, `--cxx-standard 17`, compiler `--timeout 900` |
| Toolchain | xiom v0.64.4 (COMPILER_VERSION pin) |
| Platform | `windows-x64` (STATUS.json `platforms`); runtime deps: none |

The prepared model in `docs/prep/codec-wave-b.md` (sec. 6) is followed:
core + subset compile with **no external dependencies**; the optional
backends are not built (see section 4).

## 2. ABI pin (G2) -- headers and hashes

Declared surface root set: `hb.h`, `hb-ot.h`, `hb-subset.h`, `hb-version.h`.
SHA256 (pinned, byte-identical in `vendor/`; `.gitattributes -text`):

| File | SHA256 |
|---|---|
| `hb.h` | `ef495206fe5dcf3c382267d975f45ecc3a158cf447c3760b8cbfa3329b8950ca` |
| `hb-ot.h` | `8caba9b4103239df6ec2a9f9bd8f00926b7942a097ec216c38226b5121b4fdf6` |
| `hb-subset.h` | `b869787fd3c5a4c75a2c9b37a907ecd06c171c48d2659b7f34c45b228ce48af8` |
| `hb-version.h` | `35b058fe35ed719ae04411b63370fe60197298770ab5699a5d56c1320bc45d82` |
| `harfbuzz-subset.cc` (build TU) | `d72687dd06866983f7d28d6eeec33c6a383c24cb48178fda64a55693ee22e509` |
| `COPYING` | `bd836c0ddca8ea0bab54a03cd32b6ff7256cbb3840fca2edc1249a4ed92c5b02` |

The full public-header closure (32 headers reachable from the four roots)
is enumerated in `docs/gen_manifest.json` (`closure_headers`).

## 3. Declared surface and coverage (G7)

- **Declared** = every `HB_EXTERN` function in the include closure of the
  four roots, in a **default build** (no `HB_EXPERIMENTAL_API`, with
  `HB_NO_SUBSET_DEPEND` as hb-config.hh sets it by default): **571
  functions**.
- **Bound** = 571/571 emitted as XIOM `extern "C"` declarations; each
  address is taken in `src/hb_symbols_gen.c`, so the conformance binary
  **links only when all 571 symbols exist**. The suite additionally checks
  `xhb_symbol_count() == 571`, an FNV-1a name hash equal to the generator
  oracle, and a zero null-slot scan.
- **Skips = 0.**
- **Opt-in declarations excluded from the declared surface (11)**, listed
  in `docs/gen_manifest.json` (`opt_in_excluded`): 7
  `HB_EXPERIMENTAL_API`-gated (`hb_shape_justify`,
  `hb_subset_cff*_get_charstring*`, `hb_subset_input_to_string_or_fail`,
  `hb_subset_input_override_name_table`) and 4 `HB_NO_SUBSET_DEPEND`-gated
  (`hb_subset_depend_*`). Both macro families are OFF in a default build:
  the amalgam does not compile them, the headers do not declare them, and
  they carry no ABI promise. (The symbols are genuinely absent from the
  verified artifact -- the linker proves it.)
- **Constants**: 592 value constants (enum members + object-like
  `#define`s: version, tags, flags, style/metric tags); 0 unresolved.
- Coverage table: `docs/COVERAGE.md` (generated). Oracle:
  `docs/gen_manifest.json`; regenerate with `python tools/gen_harfbuzz.py`,
  verify with `--check` (fails on any drift).

## 4. Out of declared scope (documented reasons)

`hb-ft.h`, `hb-gobject.h`, `hb-icu.h`, `hb-cairo.h`, `hb-graphite2.h`,
`hb-uniscribe.h`, `hb-directwrite.h`, `hb-coretext.h`, `hb-gdi.h`,
`hb-wasm-api.h`, `hb-raster.h`, `hb-vector.h`, `hb-gpu.h` are **not
reachable** from the four roots. The four named in the wave brief (FT,
gobject, ICU, cairo) each require an external dependency the package
deliberately does not link:

| Header | External dependency | Disposition |
|---|---|---|
| `hb-ft.h` | FreeType | out of scope (no FT runtime) |
| `hb-gobject.h` | GObject/glib | out of scope |
| `hb-icu.h` | ICU | out of scope |
| `hb-cairo.h` | cairo | out of scope |

The remaining headers are platform backends (DirectWrite/Uniscribe/GDI/
CoreText), experimental GPU/vector/raster APIs, or the WASM guest API --
all out of the declared surface by construction of the four roots.

## 5. Safe boundary (G5)

`extern "C"` lives in `src/hb_bridge.cpp`, `src/hb_symbols_gen.c` (C), and
the generated `xiom.harfbuzz.gen.*` modules; `unsafe` in XIOM is confined
to the root module `src/harfbuzz.xi` (the only XIOM module with `unsafe`
calls). Discipline (v0.64.4, `docs/BINDINGS-COMPILER-FINDINGS.md`):

- pointers/handles cross as `Int`; no `Int as *UInt8` casts (B-25);
- C writes results into XIOM-owned 4-byte slots, read little-endian
  byte-indexed on the XIOM side (B-20/B-24);
- no bare `null` to C (B-23); nullable arguments are produced inside C;
- flat outcome structs only -- `HbshapeOutcome` / `HbfaceOutcome` /
  `HbsubsetOutcome`; no `Result[Option[T]]` shapes (B-26);
- `Str` equality via `xiom.string.compare.str_compare` (suite).

Error mapping: probe entry points return `0` or a negative code; the
XIOM wrappers surface `ok/rc` in the flat outcome structs. The C bridge
never throws across the boundary.

## 6. Re-pin procedure

1. `git -C E:\repos\harfbuzz fetch --depth 1 origin <tag>` then
   `git checkout <commit>` (shallow clones cannot see new tags).
2. Re-vendor: copy `src/**` + `COPYING` over `vendor/harfbuzz/`
   (byte-exact; `vendor/** -text` is already set).
3. Re-run `python tools/gen_harfbuzz.py` (regenerates modules, symbols TU,
   manifest, coverage; `--check` must pass).
4. Update the hashes in section 2 + PROVENANCE.md pin; update the
   version-pin literals in `src/harfbuzz.xi` (generated `surface.xi`
   constants + suite expectations S1.x/S2.1).
5. Re-run `scripts/port.ps1 -Package xiom.harfbuzz -TimeoutSec 900` x2;
   record via `scripts/status.ps1 -Action update`.

## 7. G-gate status

| Gate | Status |
|---|---|
| G0 manifest marker (`keywords` contains `binding`) | PASS |
| G1 compile on the pinned toolchain | PASS (v0.64.4) |
| G2 ABI pin (section 2) | PASS |
| G3 loader smoke | N/A -- statically linked (probe = version pin) |
| G4 function smoke | PASS (shape/subset/face probes; 27-check suite) |
| G5 confinement | PASS (section 5) |
| G6 upstream-first / PROVENANCE.md | PASS (`PROVENANCE.md`) |
| G7 coverage 100% of declared surface | PASS (571/571, skips 0) |
