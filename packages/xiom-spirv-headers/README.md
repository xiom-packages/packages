# xiom.spirv.headers

SPIR-V header constants for XIOM, source-generated from the shipped SPIR-V
headers (`spirv.h`) of the **Vulkan SDK 1.4.350.0** (upstream
KhronosGroup/SPIRV-Headers tag `vulkan-sdk-1.4.350.0`). **Constants only** --
no DLL, no FFI, no runtime loader, nothing to resolve: the conformance suite
is pure XIOM and always runs (never a SKIP state).

> **Status:** `incubating` -- **0.1.0**. Suite **10/10 x2** on compiler
> v0.64.4 (spot checks + emitted-count vs manifest). **0.1.0 published in
> `eco-v0.1.165` (sha256 `a77f364a...`)**. **Lane:** bindings
> (`keywords: ["binding"]`); Vulkan SDK 100% program, slice B4.

## Coverage

| Kind | Count |
|------|-------|
| Enum types (`typedef enum Spv*`) | 74 |
| Enum values (enumerators) | 2378 |
| Macros (`SPV_VERSION`, `SPV_REVISION`) | 2 |
| Header static consts (`SpvMagicNumber`, `SpvVersion`, `SpvRevision`, `SpvOpCodeMask`, `SpvWordCountShift`) | 5 |
| **Emitted constants** | **2385** |

Oracle `spirv.h` sha256
`93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E` (the
generator verifies oracle count == emitted count and 61 spot checks; it
fails closed on any drift). Full evidence: `docs/COVERAGE.md`;
provenance: `PROVENANCE.md`.

## Modules

| Module | Constants | Contents |
|--------|-----------|----------|
| `xiom.spirv_headers` | 7 | `SPV_VERSION`/`SPV_REVISION`, the 5 header statics, generated counts (`SPV_ENUM_TYPE_COUNT`, `SPV_ENUM_COUNT`, `SPV_CONST_COUNT`), oracle `SPV_HEADER_SHA256` |
| `xiom.spirv_headers.core` | 212 | source language, execution model/mode, addressing model, memory model, storage class, dim, sampler modes |
| `xiom.spirv_headers.image` | 133 | image formats/orders/types, image-operand masks |
| `xiom.spirv_headers.fp` | 54 | fast-math/rounding/denorm/quantization/overflow/packed/encoding modes |
| `xiom.spirv_headers.decorations` | 369 | `SpvDecoration`, `SpvBuiltIn`, function-parameter attributes, linkage, access qualifiers |
| `xiom.spirv_headers.controls` | 347 | selection/loop/function control, memory semantics/access, scope, group ops, ray flags/queries, cooperative matrix/tensor operands |
| `xiom.spirv_headers.capabilities` | 338 | `SpvCapability` |
| `xiom.spirv_headers.ops_core` | 344 | `SpvOp` opcodes 0..999 |
| `xiom.spirv_headers.ops_4000` | 77 | `SpvOp` opcodes 4000..4999 |
| `xiom.spirv_headers.ops_5000` | 432 | `SpvOp` opcodes 5000..5999 |
| `xiom.spirv_headers.ops_6000` | 72 | `SpvOp` opcodes 6000+ and `SpvOpMax` |

Every module file is generated and stays below 600 lines (family split).

## Usage

```xiom
use xiom.io;
use xiom.spirv_headers;
use xiom.spirv_headers.core;
use xiom.spirv_headers.ops_core;

fn describe_op(op: Int) -> Str {
  if op == SpvOpTypeVoid { return "OpTypeVoid"; }
  if op == SpvOpFunction { return "OpFunction"; }
  return "other";
}

fn main() -> Int {
  io.println("SPIR-V version: " + to_string(SPV_VERSION));  // 0x10600
  io.println("op 19 = " + describe_op(19));                 // OpTypeVoid
  if SpvExecutionModelVertex == 0 && SpvCapabilityShader == 1 {
    io.println("well-known values ok");
  }
  return 0;
}
```

Module namespace note: the modules are `xiom.spirv_headers` (root) and
`xiom.spirv_headers.<family>`, not `xiom.spirv.headers.<family>`. On the
current compiler pin the checker drops all but the last of several sibling
imports of a **four-segment** module path under a three-segment package name
(minimal repro in `AUDIT.md`); three-segment module paths resolve correctly.
The package name (`xiom.spirv.headers`) is unaffected. When the checker
defect is fixed the modules can be re-rooted in a re-carve.

## Re-carve

```powershell
git -C E:\repos\SPIRV-Headers fetch --depth 1 origin tag vulkan-sdk-<VER>
# verify byte-identity, then:
python tools\gen_spirv_headers.py            # regenerate + verify + manifest
python tools\gen_spirv_headers.py --check    # drift gate
```

See `SPEC.md` for the pin/re-pin procedure and `ROADMAP.md` for what is
next (extended-instruction-set header constants, module re-root).
