# xiom.glfw

GLFW (windowing/input) bindings for XIOM via a **dynamic loader**:
`glfw_load()` resolves `glfw3.dll` at runtime and every call goes through
resolved function pointers. No link-time dependency, no vendored code, no
build flags -- and the conformance suite reports **SKIP** (green) when GLFW
is not installed.

> **Status:** `incubating` -- suite green on the pin (v0.64.0): 3/3 x2 without
> GLFW (SKIP path), 9/9 x2 with GLFW 3.4.0.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.glfw;

fn main() {
  let l = glfw_load();
  if !l.is_ok {
    io.println("GLFW unavailable: " + l.error.message);  // SKIP in CI
    return;
  }
  let lib: GlfwLibrary = l.value;
  if glfw_init(&lib) {
    let v = glfw_get_version(&lib);
    io.println("GLFW " + to_string(v / 10000) + "." + to_string((v % 10000) / 100));
    io.println(glfw_get_version_string(&lib));
    glfw_terminate(&lib);
  }
  let cl = glfw_close(&lib);
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `glfw_load`, `glfw_close`, `GlfwLibrary`, `GlfwLoadError` |
| Lifecycle | `glfw_init`, `glfw_terminate` |
| Version | `glfw_get_version` (packed), `glfw_get_version_string` |
| Timer | `glfw_get_time` |
| Errors | `glfw_last_error`, `glfw_last_error_code` |
| Constants | `GLFW_TRUE/FALSE`, `GLFW_KEY_ESCAPE`, `GLFW_PRESS/RELEASE`, `GLFW_CLIENT_API`, `GLFW_NO_API` |
| Kinds | `GLFW_LOAD_ABSENT`, `GLFW_LOAD_NO_PLATFORM`, `GLFW_LOAD_ABI` |

Failure model: absent backend -> SKIP; `glfwInit` failure (headless) ->
SKIP with the GLFW error text; present-but-exports-missing -> FAIL.

## Runtime requirements

Put `glfw3.dll` (3.4.x) on the loader search path: next to the executable or
anywhere on `PATH`. G2 pin (soname + header hash + symbol set): `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.glfw
```

- Without GLFW: 3 `[PASS]` with explicit SKIP labels, exit 0.
- With GLFW: 9 `[PASS]` (init/version/build string/timer/error state/
  terminate/release), exit 0.

Window/input/monitor resources are Phase 2 (`ROADMAP.md`).
