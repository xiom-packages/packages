# SPEC: xiom.glfw -- GLFW bindings via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.glfw` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | GLFW -- https://github.com/glfw/glfw |
| Upstream version pinned | **3.4** (tag `3.4`) |
| Upstream license | zlib (bindings only; no code vendored) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (soname `glfw3.dll`; POSIX soname documented for Phase 2) |
| Compiler pin | xiom v0.64.0 |

## 2. G2 pin: soname + header hash + symbol set

**Soname (runtime contract):** `glfw3.dll` (Windows; official release binary
name). POSIX equivalent `libglfw.so.3` is documented for Phase 2 but not
resolved yet. The loader passes the soname to `LoadLibraryA` through
`xiom.ffi.dl`; there is no link-time dependency and nothing vendored.

**Header pin** (fetched verbatim from
`https://raw.githubusercontent.com/glfw/glfw/3.4/include/GLFW/glfw3.h`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `GLFW/glfw3.h` | 241,826 | `AA370985F6B493BBE0358A36AB49F5780A6397C0209C6D98A62143DEA595B73C` |

**Resolved symbol set** (the smoke API this package depends on):
`glfwInit`, `glfwTerminate`, `glfwGetVersion`, `glfwGetVersionString`,
`glfwGetTime`, `glfwGetError`.

**Reference runtime sample used for local positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| Release archive | `glfw-3.4.bin.WIN64.zip`, 3,284,918 bytes, SHA256 `54EFA829400F2A0537F742B2B3BDD74E437BB4F2F048E4B7D3C5557D11A611E6` |
| DLL | `lib-vc2022\glfw3.dll`, 232,448 bytes, FileVersion 3.4.0, SHA256 `4429ADFF46D4D1038BB5836CECC59661EEF7126E4941DE6FDFDE8855E7C14BB1` |
| Runtime report | version 3.4.0, build string `3.4.0 Win32 WGL Null EGL OSMesa VisualC DLL` |

### Re-pin procedure

1. Pick the new upstream tag; re-fetch `include/GLFW/glfw3.h` and recompute
   its SHA256; update this table and the version rows in `README.md`/
   `AUDIT.md` in one commit.
2. If the smoke API grows (new resolved symbols), update `glfw_load` and the
   suite in the same commit; the loader fails closed (`GLFW_LOAD_ABI`) when
   an expected export is missing.
3. Re-run `scripts/port.ps1 -Package xiom.glfw` in both configurations
   (backend present and absent) and record the matrix in §4.

## 3. Design: dynamic loader (same pattern as xiom.sdl3)

- **No link-time dependency.** `glfw_load` resolves `glfw3.dll` at runtime
  through `xiom.ffi.dl`; every call is an fn-pointer cast inside
  `glfw.xi` (module `xiom.glfw`), the ONLY module in the package with
  `unsafe` (G5).
- **Classification**: backend missing -> `GLFW_LOAD_ABSENT` (SKIP);
  `glfwInit` fails (headless/platform) -> `GLFW_LOAD_NO_PLATFORM` (SKIP);
  present-but-exports-missing -> `GLFW_LOAD_ABI` (FAIL). The suite prints
  explicit SKIP labels under `[PASS]` markers so a run with zero markers
  never occurs.
- **Public API (safe)**: `glfw_load`, `glfw_close`, `glfw_init`,
  `glfw_terminate`, `glfw_get_version` (packed `major*10000 + minor*100 +
  rev`), `glfw_get_version_string`, `glfw_get_time`,
  `glfw_last_error_code`, `glfw_last_error`, plus constants.
- **Out-params** (`glfwGetVersion` int*, `glfwGetError` const char**) use
  XIOM-owned `Vec[UInt8]` slots read back byte-wise; no malloc/free in
  confined blocks (binding-lane finding B-05).
- **No `port.args.json`**: pure-XIOM loader, no C source, no extra flags.
- The pre-pilot module declared `module xiom.glwf` (typo) and called a C
  bridge linked against GLFW headers/import libs; that could not satisfy the
  SKIP-when-absent gate and is preserved in git history only.

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.0)

| Configuration | Command | Result |
|---------------|---------|--------|
| GLFW absent (CI shape) | `port.ps1 -Package xiom.glfw`, no glfw3.dll on PATH | **PASS 3/3 x2** (`loader: SKIP ... code 126`, `smoke: SKIP`) |
| GLFW 3.4 present | same, with the official win64 `lib-vc2022` dir prepended to PATH | **PASS 9/9 x2** (init, version 3.4.0, build string, timer, clean error state, terminate, release) |
| Headless present (init fails) | not reproducible on this host; init-dependent checks SKIP with the GLFW error text, version checks still run | path implemented + code-reviewed, not force-tested |

## 5. Scope

Pilot smoke only (init/terminate, version, timer, error accessor). Window,
input, and monitor resources over this loader are Phase 2 (`ROADMAP.md`).
