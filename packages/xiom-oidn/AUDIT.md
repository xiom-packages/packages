# AUDIT: xiom.oidn 0.1.0 -- discipline and behavioral audit

Scope: the xiom.oidn package (loader-tier bridge + module + suite) on the
v0.64.4 compiler pin. Every item below was verified empirically during the
0.1.0 build; commands are reproducible.

## 1. Compiler-pin discipline (B-numbers)

| Rule | Where honored | Evidence |
|------|---------------|----------|
| B-25: no `x as *UInt8` handle casts | `oidn.xi` has zero pointer casts in code (the only textual hit is the header comment quoting the rule); handles are `Int` end-to-end; the bridge casts in C (`dev_of`/`buf_of`/`filt_of`/`sem_of`) | `grep "as \*UInt8" oidn.xi` -> comment only |
| B-23: no bare `null` to C | every pointer argument is an owned slot (`as_mut_ptr`), a `Str` (`c_str`), or built inside the bridge (`0` literals are C-side); the only `null` hit in `oidn.xi` is the header comment | `oidn.xi` call sites; bridge `queues[0] = 0`, `semsPtr = 0` only for count 0 |
| B-20/B-24: no foreign-pointer reads | image/buffer data moves only through `xo_oidn_buffer_read/write` into owned slots; `oidnGetBufferData` exposed as an integer address only | suite section 3 checks; `oidn_get_buffer_data_addr` doc |
| B-11/B-16/B-17: byte-indexed slot reads | `xo_rd_u8/i32/u64` read little-endian byte-by-byte; the bridge writes with explicit shifts | `oidn.xi` helpers; bridge `write_i32/u64/u8` |
| B-21: no `&mut` of Result/struct-return temps | `Result` payloads are copied to locals first (`let st = sr.value`), mutations target fresh locals | suite (`let st = sr.value;`, `let info = loaded.value;`) |
| B-26: never `Result[Option[T]]` | outcome types are flat structs (`OidnInfo`, `OidnLoadError`, `OidnError`, `OidnF32Stats`) | `oidn.xi` types section |
| B-13/B-18/B-22 (fn values to C) | no XIOM `fn` value crosses to C: the device error function and the filter progress monitor are bridge-owned C callbacks with hit counters | `xo_oidn_device_set_error_function`, `xo_oidn_filter_set_progress_monitor`; suite checks |
| B-02/B-07 (cross-module const/convert) | the module uses no `xiom.convert`/`xiom.string`; local `oidn_int_to_str` only | `oidn.xi` helpers |
| G5 confinement | `oidn.xi` is the only file with `extern "C"`; `src/oidn_bridge.cpp` is the only compiled C++ TU | `grep -r "extern \"C\"" packages/xiom-oidn --include=*.xi` -> oidn.xi only |

## 2. Interface-ABI findings (recorded for the wave)

1. **`bool` returns need the `bool` type.** OIDN's C API returns `bool` for
   `oidnIs*Supported`, `oidnGet*Bool`. Through a mis-typed `int` pointer the
   upper 32 bits are garbage (observed `1286947585` for `true`). The bridge
   types every entry point with `decltype(&oidnX)` against the vendored
   header, so this class of bug is impossible by construction.
2. **The error queue returns one error per call.** A failed
   `oidnCommitFilter` can leave multiple pending errors ("input image not
   specified" then "changes to the filter are not committed"). The bridge
   drains (bounded loop) *before* each operation so the returned code
   always belongs to that operation.
3. **Handle-returning calls need the error code.** `oidnNewFilter` returns
   NULL and stores the code in the error queue; a plain bridge cannot
   return both. The bridge returns `-code` on failure so the module builds
   a typed `OidnError` with the upstream classification (observed fix:
   unknown filter type reported code 2, not UNKNOWN).
4. **Unknown parameter semantics differ by direction.** `oidnGetDeviceInt`
   with an unknown name throws (error 2); `oidnSetDeviceInt` warns only.
   Filter `set` warns for unknown names; filter `get` throws. The typed
   error tests use the *throwing* directions.
5. **CPU-only device profile is deterministic.** With the CPU device DLL
   present and GPU device DLLs absent: `oidnGetNumPhysicalDevices() == 1`,
   CUDA/HIP/Metal support flags false, `systemMemorySupported` and
   `managedMemorySupported` true, `oidnNewBuffer` defaults to storage
   MANAGED (3).
6. **Denoising is bit-deterministic.** Two runs (blocking vs async
   execute) over the same inputs are bit-identical -- asserted in the
   suite ("repeat determinism").
7. **8x8 is enough.** The RT filter denoises a 384-float image (27 progress
   callbacks, finite 192/192, changed 192/192, 547 changed bytes) in well
   under a second, including runtime load.

## 3. Safety review of the bridge

- `xo_oidn_load_named` frees nothing on failure; `FreeLibrary` only in
  `xo_oidn_unload`. Re-load after unload re-resolves the table.
- `xo_oidn_device_release`/`buffer_release`/`filter_release`/
  `semaphore_release` intentionally do NOT touch the error queue after the
  release call (the handle may be gone).
- Semaphore arrays are bounded (8) and validated (count >= 0, arrays
  non-null when count > 0) before any pointer is built.
- Analysis helpers validate pointers/counts and use `memcpy` for f32
  loads (no alignment assumptions).
- The bridge stores no XIOM pointers; every call is synchronous and
  copies data in/out.

## 4. Reproduce

```
$env:PATH = "E:\repos\oidn-release\cpu;" + $env:PATH   # present profile
.\scripts\port.ps1 -Package xiom.oidn -TimeoutSec 240  # 33/33 PASS (x2)

.\scripts\port.ps1 -Package xiom.oidn -TimeoutSec 240  # absent profile: 4/4 PASS, SKIP-green
```
