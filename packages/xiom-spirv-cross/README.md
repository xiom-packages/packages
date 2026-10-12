# xiom.spirv-cross

SPIRV-Cross bindings for XIOM: a dynamic loader plus generated typed wrappers
for **100% of the spirv-cross C API** -- every one of the 169 `spvc_*`
functions declared in `spirv_cross_c.h` (SPVC_C_API_VERSION 0.68.0), every
enum member and macro as a constant, and a runtime `resolved=N/N` proof.

The package never links against the SDK. `spirv-cross-c-shared.dll` is
resolved at runtime through `xiom.ffi.dl` (`LoadLibraryA`/`GetProcAddress`);
when the DLL is absent the conformance suite stays green and reports SKIP.

## Status

| Item | Value |
|---|---|
| Oracle (header-declared `spvc_*` functions) | **169** |
| Bound (typed wrappers) | **169** (10 families) |
| Runtime resolved (shipped DLL) | **169/169** |
| DLL-exported but undeclared | 0 |
| Constants | 242 enum members + 19 macros + 17 struct sizes |
| Suite | `tests/test_conformance.xi` -- 20/20 PASS with the DLL, SKIP-green without |
| Stage | incubating -- 0.1.0 published in `eco-v0.1.162` |

## Quick start

```xiom
use xiom.spirv.cross;

fn main() -> Int {
  let r = spirv_cross_load();
  if !r.is_ok {
    // SPVC_LOAD_ABSENT: spirv-cross-c-shared.dll not on PATH (SKIP)
    return 1;
  }
  let lib = r.value;

  var ctx_slot = spvc_slot(8);
  if spvc_context_create(&lib, &mut ctx_slot) != SPVC_SUCCESS { return 2; }
  let ctx = spvc_read_u64_at(&ctx_slot, 0);

  var words = my_spirv_bytes();          // Vec[UInt8], little-endian SPIR-V
  var ir_slot = spvc_slot(8);
  if spvc_context_parse_spirv(&lib, ctx, &mut words, words.len() / 4, &mut ir_slot) != SPVC_SUCCESS { return 3; }
  let ir = spvc_read_u64_at(&ir_slot, 0);

  var comp_slot = spvc_slot(8);
  if spvc_context_create_compiler(&lib, ctx, SPVC_BACKEND_GLSL, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &mut comp_slot) != SPVC_SUCCESS { return 4; }
  let compiler = spvc_read_u64_at(&comp_slot, 0);

  let glsl = spvc_compiler_compile_string(&lib, compiler);   // "#version 450 ... void main ..."
  io.println(glsl);

  spvc_context_release_allocations(&lib, ctx);
  spvc_context_destroy(&lib, ctx);
  spirv_cross_close(&lib);
  return 0;
}
```

## Layout

```
spirv_cross.xi            assembled single module (generated; do not edit)
tools/gen/*.xifrag        generated family fragments (<600 lines each):
                          00_prelude 01_constants 02_loader 03_oracle
                          10_context 11_compiler 12_glsl 13_hlsl 14_msl
                          15_resources 16_type 17_constant 18_buffer
                          19_reflect 20_fixtures
tools/gen_spirv_cross.py  header -> fragments + assembled module
tools/embed_spv_xiom.py   min.frag.spv -> 20_fixtures.xifrag + reassemble
tools/check_exports.py    DLL export table vs header oracle (pure stdlib)
tools/shaders/            committed .spvasm source + assembled .spv fixture
tests/test_conformance.xi conformance suite (x2 green)
docs/COVERAGE.md          oracle / bound / resolved inventory + commands
```

The package compiles as **one** XIOM module. On the pinned compiler
(v0.64.3 slot) cross-module bare-name resolution is broken (see AUDIT.md --
`xiom.durable`/`xiom.grpc` no longer compile), and a `src/` directory beside
the root module breaks even qualified imports; the fragment files keep every
reviewable unit small while shipping the proven single-module shape
(the xiom-sdl3 template).

## Building / running

From this directory:

```
xiom --run tests/test_conformance.xi        # suite (SKIP-green without the DLL)
```

Positive-path proof needs `spirv-cross-c-shared.dll` on `PATH`
(`C:\VulkanSDK\1.4.350.0\Bin`). From the repo root:

```
& scripts\port.ps1 -Package xiom.spirv-cross
```

Regenerate after a header or fixture change:

```
python tools/gen_spirv_cross.py      # header -> fragments + spirv_cross.xi
python tools/embed_spv_xiom.py       # .spv -> 20_fixtures.xifrag + reassemble
python tools/check_exports.py        # export-table proof
```

## License

MIT OR Apache-2.0.
