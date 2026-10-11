# AUDIT: xiom.spirv.headers

## Status (2026-10-11)

Constants-only package at **0.1.0**, generated from the shipped SPIR-V
header (`spirv.h`, Vulkan SDK 1.4.350.0 / SPIRV-Headers
`vulkan-sdk-1.4.350.0`). No runtime library, no FFI, no `unsafe`; the suite
is pure XIOM and always runs.

| Item | State |
|------|-------|
| Compiler | v0.64.3 |
| Upstream pin | SPIRV-Headers `vulkan-sdk-1.4.350.0` (commit `ad9184e...`), MIT |
| Oracle | `spirv.h` sha256 `93F82C0B...E24E` (byte-identical to the clone copy) |
| Link model | none -- constants only (no DLL to load, no SKIP state) |
| FFI confinement | trivially satisfied: zero externs, zero `unsafe` |
| Generator | `tools/gen_spirv_headers.py` -- parses the oracle, emits `src/spv_consts_*.xi` + `tools/spirv_manifest.json`; `--check` mode is a drift gate |
| Emitted | 2385 constants = 2378 enumerators + 2 macros + 5 header statics (74 enum types) |
| Suite | `tests/test_conformance.xi`, 10 checks -- spot values + emitted counts vs manifest + oracle sha256 |
| Runs | PASS 10/10 x2 via direct toolchain run + `port.ps1 -Package xiom.spirv.headers` (namespace-check OK, 11 modules, 0 conflicts) |
| File size discipline | every module < 600 lines (largest: `controls` 488, `ops_5000` 444) |

## Gates (binding lane)

- **G0 manifest/marker**: `package.xi` with `keywords: ["binding"]`,
  `license: "MIT OR Apache-2.0"`.
- **G1 compile**: green on the pin.
- **G2 ABI pin**: no soname (no runtime); the pin is the oracle header
  sha256 + upstream tag/commit, recorded in `SPEC.md` §2 and
  `tools/spirv_manifest.json`. Re-pin procedure in SPEC §2.
- **G3 loader smoke**: N/A -- no library.
- **G4 function smoke**: N/A -- no functions; the suite proves the constant
  surface (counts + values).
- **G5 confinement**: N/A -- no FFI; zero `unsafe` in the package.

## Compiler finding (v0.64.3): multi-import of 4-segment module paths

While wiring the suite, a checker defect surfaced and is worked around:

- **Symptom**: with a package named `xiom.foo.bar` and two family modules
  `module xiom.foo.bar.alpha` / `module xiom.foo.bar.beta`, a file with
  `use xiom.foo.bar.alpha; use xiom.foo.bar.beta;` resolves only the
  **last** import's bare constants; the earlier module's constants report
  `T001 undefined variable`. Glob imports behave the same. One import alone
  works; the same structure with three-segment paths
  (`xiom.foo.alpha` + `xiom.foo.beta`) works with any number of imports
  (the azure 8-submodule shape is the in-repo control).
- **Attribution**: minimal repros run against the pin binary
  (`C:\Users\lefte\AppData\Local\xiom.new-20261010-212636\bin\xiom.exe`,
  v0.64.3); the compiled packages `xiom.azure` (3-segment submodules) pass,
  the 4-segment probes fail deterministically (two independent package
  names: `xiom.spirv.headers`, `xiom.foo.bar`).
- **Workaround adopted**: modules are declared as `xiom.spirv_headers` +
  `xiom.spirv_headers.<family>` (three-segment import paths). The package
  name stays `xiom.spirv.headers`.
- **Follow-up**: file to the compiler lane at the next relay; when fixed,
  re-root the modules to `xiom.spirv.headers.<family>` in a re-carve
  (ROADMAP item). Repro scripts: `docs/COVERAGE.md` §"compiler finding".

## Design notes

- The generator fails closed: duplicate constant names, enum/family gaps,
  unknown value forms, spot-check drift, count mismatch, or length overflow
  all abort generation. It also cross-verifies the clone copy against the
  SDK oracle (`--clone-header`) and refuses a byte mismatch.
- An independent line-scan audit count (regex, no structured assumptions)
  must equal the structured enumerator count before anything is written.
- `docs/COVERAGE.md` carries the exact commands and outputs used for the
  recorded run.

## Known limitations

- Non-`Spv*` constant families shipped beside `spirv.h` (extended
  instruction-set headers with `GLSLstd450*`, `OpenCLLIB*`, `NonSemantic*`,
  `DebugInfo*`, TOSA, ...) are not covered in 0.1.0 (ROADMAP item); they
  are separate prefixes, not part of "every `Spv*` enum value and macro".
- The `xiom.spirv_headers.*` module namespace is a workaround for the
  compiler finding above, not the intended long-term namespace.
- Spot checks sample well-known values (61 in the generator, ~90 in the
  suite); full parity is guaranteed by construction (emitted from the
  parsed oracle with a count audit), not by exhaustive test assertions.
