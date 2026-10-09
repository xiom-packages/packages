# xiom.portaudio

PortAudio bindings for XIOM via a **dynamic loader**: `pa_load()` resolves
`portaudio_x64.dll` at runtime and every call goes through resolved function
pointers. No link-time dependency, no headers, no vendored code -- and the
suite reports **SKIP** (green) when PortAudio is not installed.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 2/2 without
> PortAudio (SKIP path) and 5/5 with the Audacity build (V19.7.0: 52 devices,
> default output/input names).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.portaudio;

fn main() {
  let p = pa_probe_default();
  if !p.is_ok {
    io.println("PortAudio unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: PaInfo = p.value;
  io.println(info.version_text);
  io.println(to_string(info.device_count) + " devices");
  if info.default_output >= 0 {
    io.println("default output: " + info.default_output_name);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `pa_load`, `pa_load_named(soname)`, `pa_close`, `PaLibrary` |
| Probe | `pa_probe(lib)`, `pa_probe_default`, `pa_probe_named(soname)`, `PaInfo` |
| Kinds | `PA_LOAD_ABSENT`, `PA_LOAD_ABI`, `PA_PROBE_FAILED` |
| Constants | `FORMAT_FLOAT32/INT32/INT24/INT16/INT8/UINT8/CUSTOM` |

Failure model: library missing -> SKIP; entry points missing -> FAIL;
initialize failure (serviceless host) -> SKIP-class. A bogus soname exercises
the SKIP path deterministically.

## Tests

```
scripts/port.ps1 -Package xiom.portaudio
```

- Without PortAudio on PATH: 2 `[PASS]` (explicit SKIP labels), exit 0.
- With PortAudio: 5 `[PASS]` (version + device count + default names), exit 0.

Streams and callbacks are Phase 2 (`ROADMAP.md`).
