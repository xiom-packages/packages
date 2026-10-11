# SPEC: xiom.spirv.headers -- SPIR-V header constants (source-generated)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.spirv.headers` (dir `packages/xiom-spirv-headers`) |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`); constants-only -- no runtime library |
| Upstream project | SPIRV-Headers -- https://github.com/KhronosGroup/SPIRV-Headers |
| Upstream pin | tag **`vulkan-sdk-1.4.350.0`**, commit `ad9184e76a66b1001c29db9b0a3e87f646c64de0` |
| Upstream license | MIT (Khronos; `LICENSE`, `LICENSES/MIT.txt`) |
| Package license | MIT OR Apache-2.0 |
| Platform | any (pure constants; generation is OS-independent) |
| Compiler pin | v0.64.3 |

The oracle is the **shipped** header
`C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h`, verified
byte-identical (sha256 `93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E`)
to `include/spirv/unified1/spirv.h` of the upstream clone at the pin. The
companion grammar (`spirv.core.grammar.json`, sha256
`68160153C934EAB387C38B672AA9BADE51234ED6AB1BADA8028C417F580A2F23`) is
shipped and byte-identical too; it is a secondary oracle used for
cross-reference only in 0.1.0 (the constant set comes from `spirv.h`).

## 2. G2 pin: no soname; the header set is the pin

**No runtime artifact.** This package never loads a library: the compiler pin,
the generator, and the committed constants are the whole contract. There is
no soname to record, no `dl` usage, no `unsafe` anywhere in the package (the
G3 loader-smoke and G4 function-smoke gates are **not applicable** by
construction; the suite always runs).

Pinned oracle set (from the SDK `Include\spirv-headers\`):

| File | SHA256 |
|------|--------|
| `spirv.h` (**the oracle**) | `93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E` |
| `spirv.core.grammar.json` (secondary) | `68160153C934EAB387C38B672AA9BADE51234ED6AB1BADA8028C417F580A2F23` |

Per-generated-file hashes are recorded in `tools/spirv_manifest.json`
(oracle sha + upstream tag/commit + counts + spot checks + file hashes), and
the generator refuses to run when any spot check or count drifts.

### Re-pin procedure

1. Clone/fetch the new upstream tag into `E:\repos\SPIRV-Headers`
   (`git clone --depth 1 --branch vulkan-sdk-<VER> ...`) and update
   `UPSTREAM_TAG`/`UPSTREAM_COMMIT` plus the oracle path constant in
   `tools/gen_spirv_headers.py` in one commit.
2. Re-run `python tools\gen_spirv_headers.py`; it re-verifies byte-identity
   with the clone copy (`--clone-header`), re-parses the oracle, asserts the
   spot checks, and writes new `src/` modules + manifest. If any spot check
   changed, the failure is intentional -- review the header diff before
   adjusting `SPOT_CHECKS`.
3. Re-run the suite and `port.ps1` (x2) and record the run
   (`scripts/status.ps1 -Action update`).

## 3. Design

- **Source-generated only.** `tools/gen_spirv_headers.py` parses the oracle:
  every `typedef enum Spv*` enumerator (name and value text verbatim), the
  `#define SPV_VERSION`/`#define SPV_REVISION` macros, and the five
  `static const unsigned int Spv*` header constants. No hand-maintained
  constant lists; no runtime code.
- **Family split.** Constants are emitted into one module per family
  (`core`, `image`, `fp`, `decorations`, `controls`, `capabilities`) plus
  `SpvOp` split by numeric range (`ops_core` 0..999, `ops_4000`,
  `ops_5000`, `ops_6000`+`SpvOpMax`). Every file stays < 600 lines.
- **Root module facts.** `xiom.spirv_headers` carries the header
  `SPV_VERSION`/`SPV_REVISION`, the five static consts, the generated
  coverage counts (`SPV_ENUM_TYPE_COUNT`, `SPV_ENUM_COUNT`,
  `SPV_CONST_COUNT`), and the oracle sha256 as `SPV_HEADER_SHA256`. These
  counts are the emitted-count constants the suite compares against
  `tools/spirv_manifest.json`.
- **Module namespace (compiler workaround).** Modules are declared as
  `xiom.spirv_headers` + `xiom.spirv_headers.<family>`. The checker on
  v0.64.3 drops all but the last of several sibling imports of a
  four-segment module path under a three-segment package name
  (`xiom.spirv.headers.<family>`); three-segment paths resolve correctly.
  The package name is unchanged. Finding + minimal repro: `AUDIT.md`;
  re-root is a ROADMAP item for when the checker fix lands.
- **Zero FFI / zero `unsafe`** (binding-lane G5 confinement trivially
  satisfied): the package contains only `pub const` declarations.

## 4. Coverage

See `docs/COVERAGE.md` for the full evidence table.

| Measure | Count |
|---------|-------|
| Oracle enum types | 74 |
| Oracle enumerators | 2378 |
| Oracle macros | 2 |
| Oracle static consts | 5 |
| **Emitted constants** | **2385** |
| Oracle count == emitted count | yes (generator asserts; audit recount by independent line scan) |

Explicit non-goals for 0.1.0: the other shipped `spirv-headers` files with
their own prefixes (extended instruction sets: `GLSL.std.450.h`,
`OpenCL.std.h`, `DebugInfo.h`, `NonSemantic*.h`, `OpenCLDebugInfo100.h`,
`TOSA.001000.1.h`, `AMD_gcn_shader.h`, `ArmMotionEngine.100.h`, ...) are
not `Spv*` constants and are not covered here; they are a ROADMAP item.

## 5. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Check | Command | Result |
|-------|---------|--------|
| Suite x2 | `. scripts\xiom.ps1; $t=Resolve-XiomToolchain; & $t.Xiom --run <pkg>\tests\test_conformance.xi` | **PASS 10/10 x2**, exit 0 (constants-only; no SKIP states) |
| Canonical gate | `.\scripts\port.ps1 -Package xiom.spirv.headers` | **PASS** (namespace-check 11 modules 0 conflicts; suite 10/10) |
| Generator drift gate | `python tools\gen_spirv_headers.py --check` | no drift |
| Oracle parity | `python tools\gen_spirv_headers.py` | 74/2378 parsed, 2385 emitted, 61 spot checks match |

No `port.args.json` (no C source, no extra flags).

## 6. Compiler notes

- **Finding (v0.64.3): multi-import of 4-segment module paths loses all but
  the last module's bare constants.** Repro: a package named
  `xiom.foo.bar` with `src/alpha.xi` (`module xiom.foo.bar.alpha`,
  `pub const A`) and `src/beta.xi`, imported by one file with
  `use xiom.foo.bar.alpha; use xiom.foo.bar.beta;` -- `A` is undefined
  while `B` resolves. Same with glob imports. Three-segment module paths
  (`xiom.foo.alpha` + `xiom.foo.beta`) are unaffected. Worked around by
  the underscore module namespace (see DESIGN); should be filed to the
  compiler lane at the next batch relay.
- The package deliberately avoids all binding-lane resolver pitfalls: no
  `unsafe`, no externs, no cross-module const aliases, generated files are
  plain top-level `pub const` declarations.

## 7. Scope

0.1.0 covers **100% of the `spirv.h` constant surface** (every `Spv*` enum
value and macro plus the header statics) plus generated counts and the
oracle hash. Remaining items live in `ROADMAP.md`.
