# xiom-ffi — Production Roadmap

**Current rating: 2/10**

**CRITICAL FINDING**: stdlib `xiom.ffi` (54 lines at `stdlib/xiom/ffi.xi`) already has real `extern "C"` `malloc`/`free`/`memcpy` with native `*UInt8` pointers and `requires`/`ensures` contracts. The ecosystem `xiom-ffi` package does NOT use it — it reimplements everything with `Int` opaque handles and `ptr: 0` stubs.

**Path to 10/10**: Rebuild xiom-ffi on top of stdlib `xiom.ffi`, adding SafePtr wrappers, buffer management, error translation, and struct marshalling. The ecosystem package should ADD safety layers to the stdlib primitives, not duplicate them.

---

## Phase 1: Rebuild on stdlib `xiom.ffi` (2 → 5/10)

### FF-01: Add `use xiom.ffi` dependency, remove local `malloc`/`free` stubs
**CRITICAL** | All source files
Replace `ptr: Int = 0` stubs with real stdlib `xiom.ffi.alloc()`/`free()` calls. `SafePtr.ptr` becomes `*UInt8` (native pointer type), not `Int`.

### FF-02: Wire `safe_ptr_alloc` → `xiom.ffi.alloc(size)`
**CRITICAL** | `src/ptr.xi`
`safe_ptr_alloc(1024)` must call `xiom.ffi.alloc(1024)` and store the returned `*UInt8`. The `owned: Bool` flag tracks lifecycle.

### FF-03: Wire `safe_ptr_free` → `xiom.ffi.free(ptr)`
**CRITICAL** | `src/ptr.xi`
Must check `owned == true` before calling `xiom.ffi.free()`. Set `owned = false` after free.

### FF-04: Add `safe_ptr_read_i32/write_i32`, `safe_ptr_read_f32/write_f32`
**CRITICAL** | `src/ptr.xi`
Use `xiom.ffi.memcpy` for multi-byte reads/writes with bounds checking. Return `Result[T, Str]` on error.

### FF-05: Add `safe_ptr_from_raw(ptr: *UInt8, size: Int)` — wrap external C pointer
**CRITICAL** | `src/ptr.xi`
Set `owned = false` for pointers received from C libraries (caller manages lifetime).

### FF-06: Fix `safe_ptr_write_byte` to return `Result[Unit, Str]`
**CRITICAL** | `src/ptr.xi`
Currently silently no-ops on bounds violation.

### FF-07: Add formal `requires`/`ensures` contracts to ALL public functions
**HIGH** | All modules
The SPEC documents contracts that don't exist in source code.

### FF-08: Add `buffer_as_ptr(buf: &FFIBuffer) -> *UInt8`
**HIGH** | `src/buffer.xi`
Required to pass buffer data to C functions.

### FF-09: Fix `buffer_new(capacity: Int)` — add runtime guard for `capacity > 0`
**HIGH** | `src/buffer.xi`

---

## Phase 2: Contracts + Invariants (5 → 7/10)

### FF-10: Add `invariant` on `SafePtr` — `ptr == null` XOR `owned == true`
### FF-11: Add `invariant` on `FFIBuffer` — `data.len() <= capacity`
### FF-12: Add `ensures` postconditions on write operations
### FF-13: Add drop guard — prevent use-after-free via `owned` flag

---

## Phase 3: Complete API (7 → 9/10)

### FF-14: Struct marshalling primitives — `src/marshal.xi`
Move `write_u32_at`/`write_f32_at`/`read_u32_from` from `vulkan_structs.xi` (1306 lines) here. This is the single most duplicated code across all ecosystem packages.

### FF-15: C string conversion — `src/string.xi`
`cstr_to_string(ptr: *UInt8) -> Str`, `string_to_cstr(s: Str) -> SafePtr`

### FF-16: `buffer_resize`/`buffer_grow` — growable C buffers
### FF-17: Null pointer sentinel — `is_null()`, `null_ptr()`
### FF-18: `ffi_try` — multiple C error conventions (code<0, ptr==0, code!=0)
### FF-19: Bulk `safe_ptr_copy(src, dest, count)` via `xiom.ffi.memcpy`

---

## Phase 4: Ecosystem Integration (9 → 10/10)

### FF-20: Migrate xiom-vulkan to use `xiom.ffi` + `xiom_ffi`
### FF-21: Migrate xiom-imgui to use `xiom.ffi` + `xiom_ffi`
### FF-22: Unit tests — `tests/` with 100% coverage of public API
### FF-23: Thread safety — `AtomicPtr` for shared C pointers
### FF-24: Zero-copy slice views over C memory
### FF-25: Performance benchmarks (bounds-check overhead vs raw C)
### FF-26: Package `exports` field — explicit module listing
### FF-27: Documentation — complete C calling convention reference

---

## Compiler/Stdlib Blockers

| Gap | Impact | Status |
|-----|--------|--------|
| `*UInt8` pointer type | Required for real C interop. Available in stdlib `xiom.ffi`. | ✅ Present |
| `Vec[UInt8]` | Buffer backing storage. Currently using `Vec[Int]` workaround. | Partial |
| G-28 E001 extern out-param moved | `safe_ptr_write_*` triggers warnings | P2 non-fatal |
| `Drop` interface | Auto-cleanup of SafePtr when scope ends | Not yet implemented in compiler |

## Target State (10/10)

```
xiom-ffi/  ← ecosystem package, depends on stdlib xiom.ffi
├── src/ptr.xi       ← SafePtr[UInt8] with real alloc/free, i32/f32 r/w, contracts
├── src/buffer.xi    ← FFIBuffer with as_ptr, resize, contracts
├── src/result.xi    ← FFIError with ffi_try, multiple conventions
├── src/string.xi    ← C string ⇄ XIOM Str conversion
├── src/marshal.xi   ← Struct field read/write at byte offsets (moved from vulkan_structs)
├── src/atomic.xi    ← Thread-safe pointer operations
└── tests/           ← 100% coverage
```
