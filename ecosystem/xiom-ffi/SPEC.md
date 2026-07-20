# xiom.ffi — SPEC

**Phase**: Foundation (stdlib) | **Priority**: CRITICAL
**Status**: PRODUCTION — v0.3.0, 30 public functions, verified with v0.49.7
**Location**: `stdlib/xiom/ffi.xi` (280 lines)

## What it is
The foundational FFI module for all XIOM C-binding packages. Provides:
- Raw C interop (malloc, free, memcpy) via `extern "C"`
- SafePtr — owned pointer with bounds tracking
- FFIBuffer — growable byte buffer with capacity guard
- FFIError — C error code translation (negative/null/nonzero conventions)
- Struct marshalling — byte-offset write primitives (write_u32_at, write_u64_at, write_f32_at, write_str_at)
- Compile-time utilities — size_of[T], align_of[T], extern_c

## Dependencies

| What | How | Size |
|------|-----|------|
| libc | System-installed (msvcrt / glibc) | — |
| libm | System-installed (optional) | — |

## Bundling strategy
**Never bundled.** Part of the XIOM standard library. Always available via `use xiom.ffi;`.

## Architecture
```
stdlib/xiom/
├── ffi.xi              # 30 public functions, 3 types
│   ├── Raw C interop   # alloc, free, memcpy (extern "C")
│   ├── SafePtr         # Owned pointer with bounds
│   ├── FFIBuffer       # Growable byte buffer
│   ├── FFIError        # C error code translation
│   └── Marshal         # byte-offset write primitives
│
ecosystem/runtime/
├── ffi_bridge.h        # XiomVec, bridge signatures
├── ffi_bridge.c        # C runtime bridge
└── README.md           # Build instructions
│
tests/stdlib/
└── ffi_tests.xi        # Conformance tests
```

## API

### Raw C Interop
```xiom
pub fn alloc(size: Int) -> *UInt8       requires: size > 0
pub fn free(ptr: *UInt8)                requires: ptr != null
pub fn memcpy(dest: *UInt8, src: *UInt8, size: Int)
```

### SafePtr (owned pointer with bounds)
```xiom
pub type SafePtr = { ptr: *UInt8; size: Int; owned: Bool }

pub fn safe_ptr_alloc(size: Int) -> Result[SafePtr, Str]
pub fn safe_ptr_from_raw(ptr: *UInt8, size: Int) -> Result[SafePtr, Str]
pub fn safe_ptr_free(ptr: SafePtr)
pub fn safe_ptr_read_byte(ptr: &SafePtr, offset: Int) -> Result[Int, Str]
pub fn safe_ptr_write_byte(ptr: &mut SafePtr, offset: Int, val: Int) -> Result[Unit, Str]
pub fn safe_ptr_read_i32(ptr: &SafePtr, offset: Int) -> Result[Int, Str]
pub fn safe_ptr_write_i32(ptr: &mut SafePtr, offset: Int, val: Int) -> Result[Unit, Str]
pub fn safe_ptr_read_f32(ptr: &SafePtr, offset: Int) -> Result[Float32, Str]
pub fn safe_ptr_write_f32(ptr: &mut SafePtr, offset: Int, val: Float32) -> Result[Unit, Str]
```

### FFIBuffer (growable byte buffer)
```xiom
pub type FFIBuffer = { data: Vec[Int]; capacity: Int }

pub fn buffer_new(capacity: Int) -> Result[FFIBuffer, Str]
pub fn buffer_write(buf: &mut FFIBuffer, data: &Vec[Int]) -> Result[Int, Str]
pub fn buffer_read(buf: &FFIBuffer, offset: Int, len: Int) -> Result[Vec[Int], Str]
pub fn buffer_clear(buf: &mut FFIBuffer)
pub fn buffer_len(buf: &FFIBuffer) -> Int
pub fn buffer_is_empty(buf: &FFIBuffer) -> Bool
```

### FFIError (C error translation)
```xiom
pub type FFIError = { code: Int; message: Str }

pub fn ffi_check(code: Int, msg: Str) -> Result[Int, FFIError]
pub fn ffi_check_ptr(ptr: *UInt8, msg: Str) -> Result[*UInt8, FFIError]
pub fn ffi_check_nonzero(code: Int, msg: Str) -> Result[Int, FFIError]
pub fn ffi_ok() -> Int
pub fn ffi_error(code: Int, msg: Str) -> FFIError
```

### Struct Marshalling (byte-offset writes)
```xiom
pub fn write_u32_at(dest: Int, offset: Int, value: Int)
pub fn write_u64_at(dest: Int, offset: Int, value: Int)
pub fn write_f32_at(dest: Int, offset: Int, value: Float32)
pub fn write_str_at(dest: Int, offset: Int, s: Str)
```

### Compile-time Utilities
```xiom
pub fn size_of[T]() -> Int
pub fn align_of[T]() -> Int
pub fn extern_c(name: Str) -> Int
```

## Verified
- alloc/free/memcpy round-trip: ✅ (memory_tests.xi)
- FFIError translation: ✅
- SafePtr lifecycle (alloc/from_raw/free): ✅
- FFIBuffer write/read/clear: ✅
- Used by: xiom-vulkan, xiom-imgui, xiom-glfw (all production)
