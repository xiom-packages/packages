# xiom.spirv-tools

SPIRV-Tools C API bindings for XIOM via a **dynamic loader**:
`spirv_tools_load()` resolves `SPIRV-Tools-shared.dll` at runtime and every
call goes through resolved function pointers. No link-time dependency on the
SDK, no vendored code -- and the conformance suite reports **SKIP** (green)
when the DLL is not installed.

The bindings are **generated** from the public C header
(`Include\spirv-tools\libspirv.h`) by the committed generator
`tools/gen_spirv_tools.py` and cross-checked against the shipped DLL's
export table (committed dump in `tools/`). Counts at the current pin
(Vulkan SDK 1.4.350.0):

| Metric | Count |
|---|---|
| Oracle: declared `extern "C"` `spv*` functions | **67** |
| Bound: typed XIOM wrappers (one per oracle function) | **67** |
| Resolved at runtime against the shipped DLL | **55/67** (`resolved=55/67`) |
| Documented shipping gap (declared, not exported) | **12** (see `docs/COVERAGE.md`) |
| Generated constants (enum members + file constants) | **222** (11 enums) |

> **Status:** `incubating` -- 0.1.0 initial generated binding. Suite
> **39/39 x2** with the SDK DLL on PATH + **3/3 x2** with the SDK `Bin`
> filtered out of PATH (SKIP-green). 0.1.0 published in `eco-v0.1.162`
> (sha256 `24012686...`). **Lane:** bindings
> (`keywords: ["binding"]`). See `docs/COVERAGE.md` for the evidence trail.

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.spirv_tools;
use xiom.spirv_tools.core;

fn main() -> Int {
  let l = spirv_tools_load();
  if !l.is_ok {
    io.println("SPIRV-Tools unavailable: " + l.error.message);  // SKIP in CI
    return 0;
  }
  let lib: SpirvToolsLibrary = l.value;
  io.println("SPIRV-Tools " + st_spv_software_version_string(&lib.syms));
  io.println("missing (shipping gaps): " + convert.int_to_string(spirv_tools_missing_count(&lib)));
  let cl = spirv_tools_close(&lib);
  return 0;
}
```

Assemble + validate + disassemble (the functional probe shape; out-params
ride in owned `Vec[UInt8]` slots, C-owned structs are copied out through
`xiom.spirv_tools.readout`):

```xiom
use xiom.spirv_tools;
use xiom.spirv_tools.core;
use xiom.spirv_tools.codec;
use xiom.spirv_tools.readout;
use xiom.spirv_tools.constants;

let ctx = st_spv_context_create(&lib.syms, SPV_ENV_UNIVERSAL_1_0);
let asm = "OpCapability Shader\n...\n";
var bin_slot = st_slot_new(8);
var diag_slot = st_slot_new(8);
let rc = st_spv_text_to_binary(&lib.syms, ctx, asm.c_str(), asm.len(), bin_slot.as_mut_ptr(), diag_slot.as_mut_ptr());
let bin = st_binary_view(st_slot_read_u64(&bin_slot, 0));   // {code, word_count}
var cb = st_slot_new(16);                                   // spv_const_binary_t
st_slot_write_u64(&mut cb, 0, bin.code);
st_slot_write_u64(&mut cb, 8, bin.word_count);
let vrc = st_spv_validate(&lib.syms, ctx, cb.as_mut_ptr(), st_slot_new(8).as_mut_ptr());
```

## API

| Module | Contents |
|--------|----------|
| `xiom.spirv_tools` | Loader: `spirv_tools_load`, `spirv_tools_close`, `SpirvToolsLibrary`, `SpirvToolsLoadError`, `spirv_tools_resolved` / `spirv_tools_missing_*` |
| `xiom.spirv_tools.symbols` | `StSymbols` (one `p_<c_name>` handle per declared function), `st_declared_count`, `st_resolved_count` |
| `xiom.spirv_tools.resolve` | `st_resolve_symbols` (full-surface resolver), `st_probe_names` (name-driven runtime probe), oracle/exported/gap name tables |
| `xiom.spirv_tools.core` | 7 wrappers: version strings, target-env description + parsers, context create/destroy |
| `xiom.spirv_tools.validator` | 15 wrappers: `spvValidatorOptions*` (create/destroy/13 setters) |
| `xiom.spirv_tools.optimizer` | 17 wrappers: `spvOptimizerOptions*` (7) + `spvOptimizer*` (10; not exported at this pin -- gated) |
| `xiom.spirv_tools.reducer_fuzzer` | 13 wrappers: `spvReducerOptions*` (5) + `spvFuzzerOptions*` (8) |
| `xiom.spirv_tools.codec` | 13 wrappers: text->binary (+ options), binary->text, validate (+ options/raw), diagnostics create/destroy/print, opcode string, binary parse |
| `xiom.spirv_tools.operand` | 2 wrappers: `spvOperandIsConcrete*` (not exported at this pin -- gated) |
| `xiom.spirv_tools.constants` | 222 source-generated values (`SPV_*`, `spv_validator_limit_*`, `K_DEFAULT_MAX_ID_BOUND`) |
| `xiom.spirv_tools.readout` | Copy-out helpers for C-owned structs (`spv_binary_t`, `spv_text_t`, `spv_diagnostic_t`) over `src/st_probe_bridge.c` |

## Build + run

```powershell
# from the repo root (PATH must include C:\VulkanSDK\1.4.350.0\Bin for the
# present-path run; the suite SKIPs green without it)
& scripts\port.ps1 -Package xiom.spirv-tools -TimeoutSec 700

# regenerate the bindings after moving the SDK pin
python packages\xiom-spirv-tools\tools\gen_spirv_tools.py
python packages\xiom-spirv-tools\tools\gen_spirv_tools.py --check   # drift guard
```

`port.args.json` appends `--c-source src/st_probe_bridge.c` (the two-function
copy bridge). The core loader does not need the bridge; only
`xiom.spirv_tools.readout` does.

## License

MIT OR Apache-2.0 (this package). The upstream SPIRV-Tools project is
Apache-2.0; the package binds it dynamically through its public C API only
(no code vendored, no link-time dependency).
