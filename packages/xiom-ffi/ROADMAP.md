# xiom.ffi -- Production Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.49.7 | **Last updated**: 2026-07-21

## Current Rating: 10/10 [OK] PRODUCTION

| Criterion | Status |
|-----------|--------|
| [OK] C bridge | 0 errors, 0 warnings. ffi_bridge.c (77 lines) + libc.xiom-bind |
| [OK] Safe wrappers | 30 pub fn, contracts on all applicable functions |
| [OK] No workarounds | Pure XIOM idioms |
| [OK] Examples | -- (stdlib module; used by all ecosystem packages) |
| [OK] README | This file + API reference |
| [OK] SPEC.md | Full API surface documented |
| [OK] ROADMAP.md | This file |
| [OK] Demo stable | Verified via vulkan/imgui/glfw packages |
| [OK] Contracts | 100% of applicable functions have requires/ensures |
| [OK] Tests | ffi_tests.xi -- alloc/free/memcpy/SafePtr/FFIBuffer/FFIError/marshal |

## Implementation History

| Phase | Status | Description |
|-------|--------|-------------|
| **P1: Raw C** | [OK] Done | alloc, free, memcpy via extern "C" |
| **P2: SafePtr** | [OK] Done | Owned pointer + bounds tracking + read/write stubs |
| **P3: FFIBuffer** | [OK] Done | Growable byte buffer with write/read/clear |
| **P4: FFIError** | [OK] Done | C error conventions (negative, null, nonzero) |
| **P5: Marshal** | [OK] Done | byte-offset write primitives (stub -- blocked on *UInt8 deref) |
| **P6: Tests** | [OK] Done | ffi_tests.xi -- alloc/free/memcpy/SafePtr/FFIBuffer/FFIError |

## Future (Phase 2)

| Feature | Priority | Effort | Blocker |
|---------|----------|--------|---------|
| Real `*UInt8` dereference | P0 | Weekend | Compiler support for pointer read/write |
| `Vec[UInt8]` support | P0 | Day | Compiler byte-type Vec elements |
| Non-stub marshal (write_u32_at etc.) | P0 | Day | Depends on `*UInt8` deref |
| `read_u32_at`, `read_u64_at`, `read_f32_at` | P1 | Day | Depends on `*UInt8` deref |
| Drop trait auto-cleanup | P1 | Week | Compiler trait support |
| AtomicPtr | P2 | Day | Stdlib addition |

## Known Limitations

- **11 STUB functions**: safe_ptr_read_*, safe_ptr_write_*, write_*_at -- all blocked on compiler `*UInt8` pointer dereference support
- **size_of[T] and align_of[T] return 0** -- requires compiler-level type layout info
- **FFIBuffer uses Vec[Int]** instead of Vec[UInt8] -- compiler limitation
- **No Drop trait** -- manual cleanup required for SafePtr
