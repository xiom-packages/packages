# xiom.ffi — FFI Standard Library

**Module**: `xiom.ffi` | **Source**: `stdlib/xiom/ffi.xi` | **Version**: v0.3.0

The foundational FFI module for all XIOM C-binding packages. Provides safe memory management, struct marshalling, and C error code translation.

## Quick Start

```xiom
use xiom.ffi;

fn main() -> Int {
  // Raw C interop
  let ptr = ffi.alloc(1024);
  ffi.memcpy(ptr, source_ptr, 1024);
  ffi.free(ptr);

  // Safe pointer with bounds tracking
  let sp = ffi.safe_ptr_alloc(256);
  match sp {
    Ok(safe_ptr) => {
      let byte = ffi.safe_ptr_read_byte(&safe_ptr, 0);
      ffi.safe_ptr_free(safe_ptr);
    }
    Err(e) => { /* handle error */ }
  }

  // FFI error checking
  let result = ffi.ffi_check(c_function_return_code, "operation name");
  match result {
    Ok(value) => { /* success */ }
    Err(ffi_err) => { io.println(ffi_err.message); }
  }

  return 0;
}
```

## Architecture

```
xiom.ffi
├── Raw C interop       → alloc, free, memcpy (extern "C")
├── SafePtr             → Owned pointer with bounds tracking
├── FFIBuffer           → Growable byte buffer with capacity guard
├── FFIError            → C error code translation
└── Marshal             → byte-offset write primitives
```

## Dependencies

- **libc** — System-installed (msvcrt on Windows, glibc on Linux)
- **libm** — System-installed (optional, for math functions)

No additional packages required. Part of the XIOM standard library.

## Building

`xiom.ffi` is a stdlib module — it compiles as part of the standard library. No separate build step needed.

For the C runtime bridge (`ecosystem/runtime/`):
```powershell
clang -c ffi_bridge.c -o ffi_bridge.obj
```

## Used By

All production XIOM C-binding packages:
- **xiom-vulkan** (10/10) — GPU API
- **xiom-imgui** (10/10) — GUI toolkit
- **xiom-glfw** (10/10) — Windowing
- 30+ SPEC-only packages awaiting implementation
