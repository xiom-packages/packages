# xiom.spirv-reflect -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Oracle parser (`tools/oracle_spvreflect.py`: 45 fns + 186 constants) | Done -- 0.1.0 |
| Vendored upstream sources (byte-pinned, per-file SHA256 in SPEC section 2) | Done -- 0.1.0 |
| Bridge + owned-slot probes (B-11..B-20 discipline) | Done -- 0.1.0 |
| Raw 45-function declaration surface | Done -- 0.1.0 |
| `resolved=45/45` + functional suite (40 checks, x2) | Done -- 0.1.0 |
| `docs/COVERAGE.md` (oracle vs bound vs resolved) | Done -- 0.1.0 |
| Consumer shapes over arbitrary SPIR-V blobs (caller-owned byte slots) | backlog |
| Re-pin to the next SDK export | backlog (SPEC section 2 procedure) |

## Phase 2 (next touches)

1. **Arbitrary-module entry point**: a `Vec[UInt8]`-in wrapper that takes a
   caller-owned SPIR-V blob (B-20-safe: C copies it internally, reflect
   results back into owned slots), so consumers are not limited to the two
   committed fixtures.
2. **Entry-point tables**: expose multi-entry-point enumeration as owned
   report rows when a consumer (engine pipeline) asks.
3. **Constant regeneration on re-pin**: `emit-consts` diff is the mechanical
   step in the SPEC section 2 re-pin procedure; keep it zero-diff until the
   SDK moves.
4. **Consumer note**: the Vulkan mini-RHI work (engine ask) can use this
   package for descriptor-set layout extraction; keep report field names
   stable once adopted.
