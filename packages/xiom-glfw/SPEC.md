# SPEC: xiom.glfw -- GLFW bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.glfw` |
| Version | 0.5.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | GLFW -- https://github.com/glfw/glfw |
| Upstream version pinned | **3.4** (tag `3.4`) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `glfw3.dll`; POSIX soname documented for later phases) |
| Compiler pin | xiom v0.64.3 |

## 2. G2 pin: soname + header hash + symbol set

**Soname (runtime contract):** `glfw3.dll` (Windows; official release binary
name). The loader passes the soname to `LoadLibraryA` through `xiom.ffi.dl`;
there is no link-time dependency and nothing vendored.

**Header pin** (verbatim from
`https://raw.githubusercontent.com/glfw/glfw/3.4/include/GLFW/glfw3.h`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `GLFW/glfw3.h` | 241,826 | `AA370985F6B493BBE0358A36AB49F5780A6397C0209C6D98A62143DEA595B73C` |

**Resolved symbol set (0.5.0):** **124 fail-closed core exports** --
complete GLFW 3.4 public surface (init, version, error, platform, hints,
window lifecycle/attrs/props, events, input, monitors/video modes/gamma,
clipboard, time, GL-context basics, Win32 native, the 20 event-callback
setters and `glfwInitAllocator`) -- plus 5 best-effort Vulkan helper exports
(`glfwVulkanSupported`, `glfwGetRequiredInstanceExtensions`,
`glfwGetInstanceProcAddress`, `glfwGetPhysicalDevicePresentationSupport`,
`glfwCreateWindowSurface`; pointer 0 when the build lacks them, wrappers
return explicit errors).

**Reference runtime used for positive-path runs (NOT the pin):**

| Artifact | Value |
|----------|-------|
| Release archive | `glfw-3.4.bin.WIN64.zip`, 3,284,918 bytes, SHA256 `54EFA829400F2A0537F742B2B3BDD74E437BB4F2F048E4B7D3C5557D11A611E6` |
| DLL | `lib-vc2022\glfw3.dll`, 232,448 bytes, FileVersion 3.4.0, SHA256 `4429ADFF46D4D1038BB5836CECC59661EEF7126E4941DE6FDFDE8855E7C14BB1` |

### Re-pin procedure

1. Pick the new upstream tag; re-fetch `include/GLFW/glfw3.h`, recompute the
   SHA256, update this table and the version rows here and in
   `README.md`/`AUDIT.md` in one commit.
2. When the surface grows, update `glfw_symbol_names()` (fail-closed) or
   `glfw_vulkan_symbol_names()` (best-effort) and the suite in the same
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.glfw` in both configurations
   (backend present and absent) and record the matrix in §4.

## 3. Design: dynamic loader + XIOM-owned slots

- **No link-time dependency.** `glfw_load` resolves `glfw3.dll` through
  `xiom.ffi.dl`; every call is an fn-pointer cast inside `glfw.xi`, the
  ONLY module in the package with `unsafe` (G5). Fail-closed: a missing
  core export closes the handle and returns `GLFW_LOAD_ABI`.
- **B-11 discipline**: every out-param uses an XIOM-owned `Vec[UInt8]` slot
  read back byte-wise (no compiler out-slots, no malloc/free in confined
  blocks). Foreign memory is copied with `ffi.memcpy` into slots
  (`copy_from`) -- no pointer arithmetic.
- **Known compiler issues dodged by design (v0.64.3):**
  - floating-point RETURNS through cast calls are miscompiled
    (0/garbage) -- `glfw_get_time` / `glfw_get_window_opacity` are callable
    but their values are unverifiable; the suite labels the skip; repro in
    `docs/repro/bindings-pilot/glfw-fp-return/` (B-12).
  - fn-typed PARAM values cannot be used as C callbacks (0; finding B-13) --
    the dispatcher + registry design avoids the path entirely.
  - Vec-of-struct element extraction (AV) -- monitors are returned as
    `Vec[Int]` handles and video modes as a raw 24-byte-record buffer
    (`glfw_vidmode_count`/`glfw_vidmode_at`).
  - `Result[Vec[...]]` payload extraction (AV) -- the required Vulkan
    instance extensions return a small `GlfwExtNames` struct instead.
  - f32/f64 slots are decoded with pure bit arithmetic
    (`f32_from_bits`/`f64_from_bits`) after a `Result[Float*]` payload
    miscompile surfaced in the first build.
- **Callback ABI (0.5.0)**: each event type has ONE fixed top-level
  dispatcher whose address (`dispatch as Int`) is handed to the DLL; user
  handlers are stored in module-level `Vec[fn]` registries and invoked by
  the dispatcher (last set wins; window handlers receive the window handle).
  Basis: probe evidence in `docs/repro/bindings-pilot/cb-abi/` -- bare
  top-level fn names marshal correctly through extern and cast-call paths,
  while fn-typed PARAM values marshal to 0 (B-13); registry element push +
  call follows the m130 fn-value ABI.
- **glfwInitAllocator**: `glfw_init_allocator_raw` builds the 32-byte
  `GLFWallocator` struct (allocate/reallocate/deallocate/user) in an
  XIOM-owned byte slot; callbacks are top-level fns cast with `as Int`.
- **`port.args.json`**: none for the loader itself; it only links `user32`
  for the deterministic `PostMessageA` key/close callback round trips in
  the suite.

## 4. Test matrix

| Configuration | Command | Result |
|---------------|---------|--------|
| GLFW absent (CI shape) | `port.ps1 -Package xiom.glfw`, no glfw3.dll on PATH | PASS (loader/smoke SKIP labels, green; 2026-10-11) |
| GLFW 3.4 present | same, with `C:\glfw-3.4.bin.WIN64\lib-vc2022` on PATH | **PASS 37/37 x2** (2026-10-11, compiler v0.64.3; ~15 s/run: full surface + 20 setters + error/key/close callback round trips + allocator cycle) |
| Headless present (init fails) | init-dependent checks SKIP with the GLFW error text | path implemented, not force-tested |

## 5. Scope

0.5.0 -- **full GLFW 3.4 public surface (124/124 core exports)** plus the
best-effort Vulkan helpers (see README/`ROADMAP.md`). Callback handlers are
process-global per event type (last set wins); per-window routing helpers,
POSIX soname handling and file-based CI for the absent case are later items.
