# xiom-ffi

Safe C Foreign Function Interface utilities for XIOM.

## Installation

```xiom
# In your package.xi deps:
deps: { "xiom-ffi": "0.1.0" };
```

## Usage

### Safe Pointers

```xiom
let ptr = safe_ptr_alloc(1024)?;
let byte = safe_ptr_read_byte(&ptr, 0)?;
safe_ptr_write_byte(&mut ptr, 0, 42);
safe_ptr_free(ptr);
```

### FFI Buffers

```xiom
let buf = buffer_new(256);
let data = vec![1, 2, 3];
let written = buffer_write(&mut buf, &data)?;
let slice = buffer_read(&buf, 0, 3)?;
buffer_clear(&mut buf);
```

### FFI Error Handling

```xiom
let code = some_c_function();
let result = ffi_check(code, "c_api_call failed")?;

# Or construct errors manually:
let err = ffi_error(-1, "allocation failed");
```

## Modules

| Module | Description |
|---|---|
| `xiom.ffi.ptr` | Safe pointer allocation, read, write, free |
| `xiom.ffi.buffer` | Growable FFI byte buffers with capacity limits |
| `xiom.ffi.result` | FFI error code checking and error construction |

## Design Notes

- All pointer operations are **pure XIOM stubs** — they maintain type safety but do not perform actual memory I/O. Real memory access requires native backend integration.
- Buffer operations are fully functional in pure XIOM using `Vec[Int]` backing storage.
- Contract enforcement (`requires`) provides compile-time verification where supported; runtime checks provide defensive fallbacks.

## License

MIT
