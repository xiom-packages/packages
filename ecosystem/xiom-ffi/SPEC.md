# xiom-ffi SPEC

## Package Overview
`xiom-ffi` provides safe abstractions over C Foreign Function Interface (FFI) patterns for the XIOM language. It wraps raw pointers, buffers, and FFI error codes into type-safe, contract-enforced APIs.

## Modules

### `xiom.ffi.ptr` — Safe Pointer Wrappers
| Function | Signature | Contracts |
|---|---|---|
| `safe_ptr_alloc` | `(size: Int) -> Result[SafePtr, Str]` | `requires: size > 0` |
| `safe_ptr_free` | `(ptr: SafePtr)` | — |
| `safe_ptr_read_byte` | `(ptr: &SafePtr, offset: Int) -> Result[Int, Str]` | `requires: offset >= 0, offset < ptr.size` |
| `safe_ptr_write_byte` | `(ptr: &mut SafePtr, offset: Int, val: Int)` | `requires: offset < ptr.size` |

**Type:** `SafePtr = { ptr: Int; size: Int; owned: Bool; }`

All pointer read/write operations are pure XIOM stubs that maintain type safety but do not perform actual memory access. Memory read returns `0`; writes are no-ops.

### `xiom.ffi.buffer` — FFI Byte Buffers
| Function | Signature | Contracts |
|---|---|---|
| `buffer_new` | `(capacity: Int) -> FFIBuffer` | `requires: capacity > 0` |
| `buffer_write` | `(buf: &mut FFIBuffer, data: &Vec[Int]) -> Result[Int, Str]` | `requires: data fits within capacity` |
| `buffer_read` | `(buf: &FFIBuffer, offset: Int, len: Int) -> Result[Vec[Int], Str]` | `requires: offset >= 0, offset+len <= data.len()` |
| `buffer_clear` | `(buf: &mut FFIBuffer)` | — |

**Type:** `FFIBuffer = { data: Vec[Int]; capacity: Int; }`

Full implementation with bounds checking and capacity enforcement. Uses recursive iteration (no `for` loops per XIOM constraints).

### `xiom.ffi.result` — FFI Error Handling
| Function | Signature | Description |
|---|---|---|
| `ffi_check` | `(code: Int, msg: Str) -> Result[Int, FFIError]` | Returns `Err` if code < 0, else `Ok(code)` |
| `ffi_ok` | `() -> Int` | Returns 0 (success code) |
| `ffi_error` | `(code: Int, msg: Str) -> FFIError` | Constructs an FFIError value |

**Type:** `FFIError = { code: Int; message: Str; }`

## Error Handling
All fallible operations return `Result[T, Str]` or `Result[T, FFIError]`. Bounds violations produce descriptive error strings. The `FFIError` type carries a numeric error code for C interop compatibility.

## Dependencies
- `xiom-std` (0.1.0): Vec, Int, Str, Bool, Result, Option types and basic operations.

## Design Constraints
- No `for` loops — all iteration uses tail-recursive helpers.
- No generic constraints — types are monomorphized at the module level.
- Methods use no `self` keyword — receiver passed as explicit first parameter.
- `Match` uses bare variant names (no qualified paths in arms).
