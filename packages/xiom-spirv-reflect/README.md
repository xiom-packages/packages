# xiom.spirv-reflect

SPIRV-Reflect bindings for XIOM -- SPIR-V shader reflection (shader stage,
descriptor bindings, interface variables, push constants, specialization
constants) for the Vulkan SDK 1.4.350.0 export. The upstream C sources are
vendored into `vendor/` (Apache-2.0) and compiled with the suite via
`--c-source` -- no DLL, no SDK headers at build time, no link-time
dependency.

> **Status:** `incubating` -- vendored runtime path green on the pin
> (xiom v0.64.3; 40/40 x2, resolved=45/45). **Lane:** bindings.

## Quick start

```xiom
use xiom.io;
use xiom.spirvreflect;

fn main() {
  let c = spirv_reflect_create_report();   // create + reflect the embedded fixture
  let b = spirv_reflect_binding_report();  // descriptor bindings/sets
  let v = spirv_reflect_variable_report(); // input/output/interface variables
  if c.rc == 0 && c.stage == 16 && b.binding_count == 1 && v.in_count == 1 {
    io.println("spirv-reflect vendored path OK; entry=" + c.entry_name);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Raw surface | 45 `spirv_reflect.h` declarations (100% of the C API) + 186 constants |
| Module probes (report wrappers) | `spirv_reflect_resolve`, `spirv_reflect_api_count`, `spirv_reflect_create_report`, `spirv_reflect_create2_report`, `spirv_reflect_binding_report`, `spirv_reflect_variable_report`, `spirv_reflect_entry_point_report`, `spirv_reflect_get_report`, `spirv_reflect_alias_report`, `spirv_reflect_change_report`, `spirv_reflect_spec_report`, `spirv_reflect_strings_report`, `spirv_reflect_error_report`, `spirv_reflect_free_chain_report` |

Full details: `SPEC.md`; vendored provenance + per-file SHA256 pins:
`SPEC.md` section 2; oracle/bound/resolved counts: `docs/COVERAGE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.spirv-reflect -TimeoutSec 700
```

Expected: 40 `[PASS]`, `resolved=45/45`, exit 0. The suite reflects two
committed SPIR-V fixtures (fragment + uniform-block modules assembled with
`spirv-as`) through the vendored library: stage/entry/code-size checks,
descriptor binding count (1) and interface variable count (1), the
enumerate/get/change families, spec constants, string copies into
XIOM-owned slots, error paths, and the free chain.
