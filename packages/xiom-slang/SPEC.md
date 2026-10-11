# SPEC: xiom.slang -- Slang C API bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.slang` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Slang -- https://github.com/shader-slang/slang |
| Upstream version pinned | Vulkan SDK 1.4.350.0 build, runtime tag **2026.8** (`spGetBuildTagString`) |
| Upstream license | Apache-2.0 with LLVM exception (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (loader path is OS-agnostic in design; soname here is `slang.dll`) |
| Compiler pin | v0.64.3 |

## 2. G2 pin: header hashes + DLL hash

**Soname (runtime contract):** `slang.dll` (Windows). The loader passes this
exact name to `LoadLibraryA` through `xiom.ffi.dl`; there is no link-time
dependency, no import library, and nothing vendored.

`slang.dll` in the Vulkan SDK is a **pure-forwarder proxy**: all 435 of its
exports are forwarder entries to `slang-compiler.dll` (31 MB, same `Bin`
directory). Windows resolves the forwarders via the DLL search path, so the
SDK `Bin` directory must be on PATH at run time (the suite documents this).

| Artifact | Bytes | SHA256 |
|----------|-------|--------|
| `Include\slang\slang.h` | 200,920 | `80CA5B8DBFC6061AAF9D28D376FD4625FEFE3B36272597BA97FF1384EC84C94D` |
| `Include\slang\slang-deprecated.h` | 73,113 | `A764D633FEA9FF3DBCC30DA1E9551E671B2D684BBB1CAFFC3903853B78580C60` |
| `Bin\slang.dll` | 71,608 | `3B36EDE98C2C58BAB5EFDA3914CAAE0698C2E0F815C3E1A896CA1DBA8439DA00` |
| `Bin\slang-compiler.dll` | 31,122,360 | `CFDC9C0067942608757CBB343B53302BD7DA1C6B945E9DD343C9474941F9830B` |

`slang.h` is the top header (it `#include`s `slang-deprecated.h`, which
declares the legacy `sp*` API); the two files together are the header oracle.

**Upstream source pin (upstream-first policy, `PROVENANCE.md`):** the SDK
headers are byte-identical (after LF normalization) to upstream
`shader-slang/slang` tag **v2026.8**, commit
`d88cc8fff35baf96cf30d242b2572564cf8043b6` (clone `E:\repos\slang`,
Apache-2.0 WITH LLVM-exception). `include/slang.h` blob `955c510a...`,
`include/slang-deprecated.h` blob `765e3283...`; the X-macro enum source
`include/slang-image-format-defs.h` blob `5e7922f4...` (43 entries).

### Re-pin procedure

1. Pick the new SDK build; re-hash the four artifacts above; update this
   table and `docs/COVERAGE.md` §5 in one commit.
2. Re-run `python tools/gen_slang.py`; the generator re-parses both headers
   and the DLL export table and rewrites the manifest. It fails if the DLL
   exports a C name the headers do not declare.
3. Re-run the suite on a machine with the SDK on PATH and record the run
   (`scripts/status.ps1 -Action update`). The suite asserts every exported
   oracle name resolves and reports the runtime build tag.

## 3. Design: generated dynamic-loader facade

- **No link-time dependency.** The package never declares `extern "C"` Slang
  symbols; `slang_load()` resolves the DLL at runtime via `xiom.ffi.dl` and
  every call is a fn-pointer cast executed inside the generated family
  wrappers (the only `unsafe` in the package).
- **100% export coverage.** `tools/gen_slang.py` (committed; deterministic)
  emits: the symbol table (`xiom.slang.syms`), per-family resolvers
  (`xiom.slang.res_*`: fail-fast `resolve_*` + per-name `count_*` probe),
  one typed wrapper per exported function (`xiom.slang.wrap_*`, 277 in 12
  families), constants (`xiom.slang.const_1`, 382 literals), and the loader
  entry (`xiom.slang`). No hand-maintained function lists.
- **SKIP semantics.** When the DLL cannot be loaded, `slang_load` returns
  `Err(kind = SLANG_LOAD_ABSENT)` and the suite reports SKIP under `[PASS]`
  markers (the runner counts markers and fails a run with zero markers).
  **ABI mismatch is a failure**: a present DLL missing any of the 277
  symbols closes the handle and returns `Err(kind = SLANG_LOAD_ABI)`.
- **Confinement (B-11..B-20 discipline).** Pointer values and out-param
  addresses cross the FFI boundary as `Int`; out-params are XIOM-owned
  `Vec[UInt8]` slots (one slot per out-param; byte-indexed readback; no
  pointer arithmetic anywhere in generated code); the only foreign-pointer
  reads are runtime C-string copies (`Str::from_c_str`) of the build tag and
  diagnostic output. `bool` returns are masked with `& 255` (the pinned DLL
  leaves garbage in the upper RAX bits -- see §5).
- **C typedefs** are exported as XIOM aliases (`xiom.slang.types`); C enums
  are 32-bit and cross as `Int`.

## 4. Public API

- Loader: `xiom.slang` -- `slang_load`, `slang_close`,
  `slang_resolved_count`, `SlangLibrary` (one resolved-address struct per
  family), `SlangLoadError`.
- Symbols/counts: `xiom.slang.syms` -- `SLANG_SYMBOLS`,
  `SLANG_SYMBOL_COUNT`, `SLANG_HEADER_ONLY(_COUNT)`, `SLANG_FORWARD_TARGET`.
- Wrappers: `xiom.slang.wrap_<family>` -- one pub fn per exported C
  function, named snake_case after the C symbol (`spCompile` ->
  `sp_compile`, `slang_createGlobalSession` -> `slang_create_global_session`),
  taking `s: &<Family>Syms` plus one `Int` per C parameter.
- Constants: `xiom.slang.const_1` -- 382 `pub const SLANG_*: Int`.

Consumer pattern (see README):

```xiom
use xiom.slang;
use xiom.slang.wrap_legacy_top_p1;

let lib = slang_load();          // Result[SlangLibrary, SlangLoadError]
// let l = lib.value;
// let session = sp_create_session(&l.legacy_top_p1, 0);
```

## 5. Test matrix (recorded 2026-10-11, compiler v0.64.3)

| Configuration | Command | Result |
|---------------|---------|--------|
| slang.dll present (2026.8) | `port.ps1 -Package xiom.slang -TimeoutSec 900`, SDK on PATH | **PASS 20/20 x2** (`resolved=277/277`, compile code size 296, error rc=0x80004005 + 645-byte diagnostics) |
| slang.dll absent (CI shape) | same with the SDK dir filtered from PATH | **PASS 3/3 x1** (`loader: SKIP ... code 126`) |

No `port.args.json` is needed: the suite compiles no C source and needs no
extra compiler flags.

## 6. Compiler notes

- **Measured on the pin:** C functions declared with `bool` return do not
  clear the upper bits of RAX (`slang_isRecordLayerEnabled` returned
  pointer-sized garbage in the high bytes); the generated wrappers therefore
  declare `-> Int` and mask `& 255`. This is robust under both truncating and
  non-truncating declared-width codegen (the m263+ truncation family).
- `Int32`/`UInt32` returns are declared at their C width and widened with
  `as Int`; 64-bit returns (`size_t`, `SlangInt`, `SlangUInt`) are `Int`.
- All fn-pointer locals inside confined blocks use the `f_` prefix (B-10
  discipline); no `alloc`/`malloc`-class names appear anywhere.
- The parent module imports its family modules (parent -> child); no child
  imports the parent (B-04 guidance). No stdlib-alias collisions (B-07).

## 7. Scope

C API only: the flat `SLANG_API` surface (`slang_*` + legacy `sp*`), its
enums and integer macros. The C++ COM interfaces (`slang::IGlobalSession`,
`ISlangBlob`, ...) are not FFI surfaces (program-plan documented C++
exclusion); C++ objects they return (blobs, sessions, writers) are handled
as opaque `Int` handles, passed back into C API calls, and released by the
caller only when the API says so.

Deliberately not bound (documented in `docs/COVERAGE.md` §3): the 9
header-declared functions the DLL does not export.
