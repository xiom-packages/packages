# AUDIT -- xiom.spirv-cross

Status: **incubating, suite green** (x2 on the pinned compiler v0.64.3 slot;
SKIP-green when the SDK DLL is absent).

## Deliverable checklist

| Item | State |
|---|---|
| Committed generator `tools/gen_spirv_cross.py` parsing the header C declarations | done (169 functions, 23 enums/242 members, 19 macros, 17 structs) |
| Loader entry + generated modules, family-split, files < 600 lines | done -- 15 fragments in `tools/gen/` (largest 3.7 KB/470 lines), assembled into the single compiled module `spirv_cross.xi` (see "Compiler slot finding") |
| `tests/test_conformance.xi`: resolve every oracle name, print `resolved=N/N` | done -- `resolved=169/169` |
| Functional probes (GLSL cross-compile "void main", resources >= 2, entry points, free chain) | done -- see COVERAGE.md |
| SKIP-green when DLL absent | proven (filtered-PATH run, below) |
| `docs/COVERAGE.md`: oracle N vs bound N vs resolved N + commands | done |
| Metadata from the sdl3 template + STATUS.json | done |
| Header-declared but unexported functions listed with resolve proof | empty -- `check_exports.py` proves missing=0 |

## Discipline (B-11..B-20)

- **Byte-indexed slot writes/reads only.** Slot access goes through
  `spvc_read_u32_at`/`spvc_read_i32_at`/`spvc_read_u64_at` and
  `spvc_write_u32_le`/`spvc_write_u64_le` (byte indexing per element);
  no `ffi.ptr_write_*`, no pointer arithmetic anywhere in the package.
- **One owned slot per out-param.** Every out-param wrapper takes a separate
  `&mut Vec[UInt8]`; multi-out functions (e.g.
  `spvc_compiler_get_work_group_size_specialization_constants`,
  `spvc_resources_get_resource_list_for_type`) take one slot per out-param.
- **No foreign reads through pointers.** Out data arrives by C copying into
  XIOM-owned slots (`slot.as_mut_ptr()` passed as `*UInt8`). The only foreign
  reads are `Str::from_c_str` copies of `const char*` results and the error
  dispatcher, each localized in `unsafe` at the copy site.
- **Int address math only.** All addresses (dl handles, opaque handles,
  symbol addresses) are `Int`; the C ABI cast signatures use `Int` for
  integer params and `*UInt8` only for data buffers.
- **Canonical `Vec[UInt8]` brackets, structured ifs, confined locals.**
  Generated code uses `Vec[UInt8]` spelling, `if !x.is_ok { return ... }`
  statements, and per-block `var ig` guards matching the sdl3 template.
- **No stray artifacts.** `.gitignore` covers `*.exe`/`*.ll`; port runs from
  a clean worktree; `git status` clean after each commit.

## Compiler slot finding (why one module, not ten)

The pinned compiler (v0.64.3 slot, `xiom.new-20261010-212636`) has a broken
cross-module name-resolution path: bare and qualified references from one
module to another fail depending on layout. Evidence gathered during this
port (scratch probes, all on the pinned compiler):

- A fresh package whose root module has **no `src/` directory** resolves
  `use xiom.<pkg>;` in the test with bare names (bindings work) -- the
  xiom-sdl3 / xiom-vulkan layout.
- Adding an **empty `src/` directory** flips the same package to
  `unknown type` / `undefined variable` for the root module's items.
- Cross-module references inside module bodies fail with bare names
  (`xiom.durable` 152/152 green on 2026-10-09 now fails to compile with 58
  T001s; `xiom.grpc` test fails with `unknown type 'GrpcStatus'`).
- `use xiom.spirv.tools;`-style sibling imports fail identically.

Consequence: the family split ships as **generated fragments** (`tools/gen/*.xifrag`,
each far below 600 lines, all committed) combined deterministically into the
single compiled module `spirv_cross.xi` -- the proven sdl3 shape. This is a
compiler-slot regression, not a packaging preference; when the compiler's
multi-module resolution is restored, the same fragments can be promoted to
modules by a one-line change to the emit header in the generator.

## Suite evidence

Present (Vulkan SDK 1.4.350.0 `Bin` on PATH), from the repo root:

```
& scripts\port.ps1 -Package xiom.spirv-cross -TimeoutSec 300
port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

Absent (PATH filtered to remove `C:\VulkanSDK\1.4.350.0\Bin`):

```
xiom --run tests\test_conformance.xi
  [PASS] loader: SKIP -- spirv-cross-c-shared.dll not present (resolved=SKIP/169)
  [PASS] functional: SKIP -- parse/compile/reflect probe (no spirv-cross runtime)
xiom.spirv-cross: suite green (DLL absent -- functional probe skipped)
exit code: 0
```

Export proof:

```
python tools\\check_exports.py
exports=169 (spvc_*=169) header=169 missing=0 extra=0
```

## Known limitations

- Windows x64 soname only (`spirv-cross-c-shared.dll`); the loader path is
  otherwise portable through `xiom.ffi.dl`.
- `spvc_context_set_error_callback` ships the ergonomic wrapper (fixed
  dispatcher + `fn(Str) -> Unit` handler) but is not functionally exercised:
  passing XIOM function values as C callbacks is constrained on this
  compiler (B-13 family), and the happy path never invokes it.
- The MSL/HLSL/JSON backends are bound and resolved but the functional probe
  uses the GLSL backend (the fixture is a GLSL-targeted fragment shader).
