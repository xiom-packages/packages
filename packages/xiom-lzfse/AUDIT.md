# xiom-lzfse — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| LZFSE | Latest | Compression library (C source) |
| clang/LLVM | >= 14 | C bridge compilation |
| xiomc | >= v0.45.3 | XIOM compiler |

LZFSE has no external C dependencies beyond the standard library (stdlib.h, string.h).

## LZFSE Source

LZFSE is Apple's open-source compression library implementing the LZFSE algorithm
(LZ-style dictionary compression combined with Finite State Entropy coding).

| Directory | Contents |
|-----------|----------|
| `src/lzfse.h` | Public API header (4 functions) |
| `src/lzfse_internal.h` | Internal encoder/decoder state, block headers, utility functions |
| `src/lzfse_fse.h` | Finite State Entropy (tANS) implementation |
| `src/lzfse_tunables.h` | Tunable compression parameters |
| `src/lzfse_encode_tables.h` | Inverse L/M/D symbol lookup tables |
| `src/lzvn_encode_base.h` | LZVN low-level encoder |
| `src/lzvn_decode_base.h` | LZVN low-level decoder |

The C source compiles into a static or shared library (`lzfse.lib` / `liblzfse.a`).

## Public API Surface

LZFSE exposes exactly **4 C functions** via `lzfse.h`:

| Function | Signature | Returns |
|----------|-----------|---------|
| `lzfse_encode_scratch_size` | `size_t f(void)` | Scratch buffer size for encoding |
| `lzfse_encode_buffer` | `size_t f(uint8_t*, size_t, const uint8_t*, size_t, void*)` | Bytes written, or 0 on failure |
| `lzfse_decode_scratch_size` | `size_t f(void)` | Scratch buffer size for decoding |
| `lzfse_decode_buffer` | `size_t f(uint8_t*, size_t, const uint8_t*, size_t, void*)` | Bytes written, or 0 on failure |

The library internally uses two compression codecs:
- **LZFSE**: Finite State Entropy + LZ-style matching (used for blocks >= 4096 bytes)
- **LZVN**: Simpler dictionary compression (used for blocks < 4096 bytes)

The public API transparently selects the appropriate codec based on input size.

## Package Structure

```
packages/xiom-lzfse/
├── package.xi              # Package manifest (name, version, deps)
├── lzfse.xi                # Module xiom.lzfse — raw FFI + safe wrappers
├── src/
│   └── lzfse_safe.xi       # Module xiom.lzfse.safe — struct-based wrappers
├── examples/
│   └── demo_lzfse.xi       # Module xiom.lzfse.demo — compile-time demo
└── AUDIT.md                # This file
```

## FFI Binding Coverage

### lzfse.xi — Module `xiom.lzfse`

All **4 LZFSE public API functions** from lzfse.h are declared in one `extern "C"` block:

| Category | Functions |
|----------|-----------|
| Scratch Sizes | lzfse_encode_scratch_size, lzfse_decode_scratch_size |
| Encode/Decode | lzfse_encode_buffer, lzfse_decode_buffer |

**6 safe wrapper functions:**
- `encode_scratch_size()`, `decode_scratch_size()` — query scratch buffer requirements
- `encode_buffer()` — compress with explicit scratch buffer (returns Result[Int, Str])
- `decode_buffer()` — decompress with explicit scratch buffer (returns Result[Int, Str])
- `encode_using_malloc()` — compress with internal malloc (passes NULL scratch)
- `decode_using_malloc()` — decompress with internal malloc (passes NULL scratch)

**1 utility function:**
- `compress_bound()` — worst-case compressed size estimate (`src_size + src_size/4 + 64`)

### lzfse_safe.xi — Module `xiom.lzfse.safe`

2 struct-based resource types with inline `extern "C"` block (cross-module resolution workaround):

| Type | Methods | Contracts |
|------|---------|-----------|
| `LzfseCompressor` | create, destroy, compress, compress_oom, scratch_buffer_size | requires: scratch != 0; ensures: scratch != 0 |
| `LzfseDecompressor` | create, destroy, decompress, decompress_oom, scratch_buffer_size | requires: scratch != 0; ensures: scratch != 0 |

Error type: `LzfseError` with `code: Int` and `message: Str`.

### demo_lzfse.xi — Module `xiom.lzfse.demo`

Compile-time demonstration showing both API patterns:
- Procedural API (`xiom.lzfse`) with scratch size queries and compress bound
- Struct-based API (`xiom.lzfse.safe`) with `LzfseCompressor` / `LzfseDecompressor` lifecycle

## Build Pipeline

```
1. Compile LZFSE C source
   clang -c lzfse_encode.c lzfse_decode.c lzfse_fse.c → lzfse_*.obj
   → liblzfse.lib (static library)

2. XIOM Compilation + Link (xiomc + clang)
   lzfse.xi + src/lzfse_safe.xi + examples/demo_lzfse.xi + liblzfse.lib
   → lzfse_demo.exe
```

## Compiler Gaps Documented

### 1. Cross-module extern resolution (T001)
**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called from module B via `use` import.
**Workaround:** `src/lzfse_safe.xi` duplicates the `extern "C"` block it needs inline.
**Impact:** 8-line duplicate extern block in lzfse_safe.xi.

### 2. Int→Int32 coercion (T001)
**Symptom:** Integer literals default to `Int` and do not auto-coerce to `Int32`.
**Workaround:** Not applicable — LZFSE API uses `size_t` (maps to `Int`). Explicit `as Int` casts used where needed.
**Impact:** Minor — only affects `compress_bound` division.

### 3. No hex literals
**Symptom:** Hex literals (`0x00000001`) cause parse errors.
**Workaround:** Not applicable — LZFSE has no flag constants requiring hex.
**Impact:** None.

### 4. No `()` unit type in Result
**Symptom:** `Result[(), Error]` is not supported.
**Workaround:** Not applicable — LZFSE functions return `size_t` (Int), naturally mapped to `Result[Int, Err]`.
**Impact:** None.

### 5. No pointer-sized allocation from XIOM
**Symptom:** XIOM cannot directly call `malloc` or allocate memory at the pointer level.
**Workaround:** Scratch buffers must be allocated by the C bridge layer. The `LzfseCompressor` / `LzfseDecompressor` types store the scratch pointer but cannot allocate it themselves; the C bridge must provide allocation.
**Impact:** Struct-based wrappers depend on a C allocation shim or pre-allocated memory.

### 6. No `to_string()` for `Int` in all contexts
**Symptom:** `Int.to_string()` may not be universally available depending on the stdlib build.
**Workaround:** Used only in demo for diagnostic output.
**Impact:** Affects demo diagnostic output only.

## XIOM Type Mapping

| C Type | XIOM Type | Notes |
|--------|-----------|-------|
| `size_t` | `Int` | Size and return values |
| `uint8_t*` | `Int` | Raw pointer to output buffer |
| `const uint8_t*` | `Int` | Raw pointer to input buffer |
| `void*` | `Int` | Scratch workspace pointer (NULL = use malloc) |

## Known Limitations

- LZFSE requires a C compiler (clang) to produce the linkable library
- Scratch buffer allocation must be handled by C code or a memory allocation bridge
- The LZFSE C library internally calls `malloc`/`free` when scratch is NULL
- No native XIOM memory bridge exists yet — requires a C shim for buffer allocation
- LZFSE compression ratio depends on tuning parameters in `lzfse_tunables.h`
- LZFSE falls back to LZVN for inputs < 4096 bytes (transparent to the API)

## Compile Status (2026-07-15)

| File | Lines | Contents |
|------|-------|----------|
| `package.xi` | 13 | Package manifest |
| `lzfse.xi` | 128 | 4 extern C FFI declarations, 6 safe wrappers, 1 utility |
| `src/lzfse_safe.xi` | 172 | 2 struct resource types with create/destroy contracts, inline extern block |
| `examples/demo_lzfse.xi` | 109 | Procedural + struct-based API demo |
| `AUDIT.md` | — | This file |

**Total: 422 lines.**
