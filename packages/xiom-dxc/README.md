# xiom.dxc

DirectX Shader Compiler **capability probe** for XIOM via a dynamic loader:
`dxc_probe()` resolves `dxcompiler.dll` at runtime (no `dxcapi.h`, no import
library, no link-time dependency), creates an `IDxcCompiler3` instance and
compiles a trivial `ps_6_0` pixel shader to a DXIL object.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 3/3 with
> DXC 1.9.0.5347 (Vulkan SDK), SKIP classification exercised every run.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.dxc;

fn main() {
  let p = dxc_probe();
  if !p.is_ok {
    io.println("DXC unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: DxcInfo = p.value;
  io.println("shader compiled to a " + to_string(info.object_size) + "-byte DXIL object");
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `dxc_probe`, `dxc_probe_named(soname)` |
| Types | `DxcInfo` (object_size), `DxcLoadError` (kind/message) |
| Kinds | `DXC_LOAD_ABSENT`, `DXC_LOAD_ABI`, `DXC_COMPILE_FAILED` |
| Constants | `DXC_SONAME` |

Failure model: compiler missing -> SKIP; missing `DxcCreateInstance` or
refused instance -> FAIL; present-but-compile-failure -> FAIL (the probe
shader is trivial; a failure is an ABI/SDK mismatch). A bogus soname
exercises the SKIP path deterministically.

## Build note

`port.args.json` compiles the header-free probe bridge
(`--c-source ${PACKAGE_DIR}/src/dxc_probe.c`); no `--link` flags. Direct run:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\dxc_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.dxc
```

Expected: 3 `[PASS]`, exit 0 (2,532-byte DXIL blob). G2 pin + re-pin:
`SPEC.md` §2.
