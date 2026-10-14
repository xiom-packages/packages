# ROADMAP: xiom.lz4

## Phase 1 -- shipped in 0.1.0 (2026-10-13, compiler v0.64.4)

- vendored lz4 v1.10.0 `lib/` (BSD-2-Clause) + xxhash;
- complete 1:1 surface: 111/111 functions of `lz4.h` + `lz4hc.h` +
  `lz4frame.h` (stable + deprecated + static-linking-only), generated and
  fail-closed verified (`tools/gen_lz4_ffi.py`);
- ergonomic facade: one-shot block/HC/frame helpers, frame slot builders,
  typed errors with `LZ4F_getErrorName` text;
- conformance suite 81/81 x2: round trips (compressible, incompressible,
  empty), HC levels 2..12, frame checksums (exact
  `ERROR_contentChecksum_invalid`), truncated/invalid typed errors,
  streaming, dictionaries and CDicts, CustomMem creators.

## Phase 2 -- candidates (not scheduled)

- **Callback allocators**: expose nonzero `LZ4F_CustomMem` constructors once
  the toolchain's callback discipline (B-13/B-22) allows XIOM-defined C
  function pointers to be passed safely; today only the default-allocator
  slot is useful.
- **Streaming writer ergonomics**: accumulate frame chunks directly into one
  owned buffer (a bridge-side append loop) to spare callers the manual
  concatenation of `compressBegin/Update/Flush/End` slots.
- **`lz4file.h` stdio layer**: bind `LZ4F_readOpen/writeOpen` if a consumer
  needs upstream's file API; XIOM-side file I/O is the alternative.
- **xxHash exports**: surface `XXH32/XXH64` from the vendored xxhash only if a
  separate `xiom.xxhash` package is not created first (single-vendored-copy
  policy).
- **Zero-copy destination views**: revisit pointer-offset streaming output if
  the compiler gains safe slice/offset support (B-17); the per-call slot
  model is correct but copies chunk data.
