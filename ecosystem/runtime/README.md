# XIOM FFI Bridge Runtime

Minimal C bridge library that enables XIOM ecosystem packages to call system C libraries (SQLite3, OpenSSL, libcurl, Winsock2).

## Build

```bash
# Compile the bridge as a static library
clang -c ffi_bridge.c -o ffi_bridge.o
ar rcs libxiomffi.a ffi_bridge.o

# Or compile alongside your XIOM program
xiomc program.xi ffi_bridge.c -l sqlite3 -l crypto -l curl -l ws2_32
```

## Functions

| Function | Purpose |
|----------|---------|
| `xiom_vec_ptr(vec)` | Extract raw data pointer from XIOM Vec |
| `xiom_vec_len(vec)` | Get Vec length |
| `xiom_alloc(size)` | Allocate zeroed native memory |
| `xiom_free_ptr(ptr)` | Free native memory |
| `xiom_read_byte(buf, off)` | Read byte from C buffer |
| `xiom_write_byte(buf, off, val)` | Write byte to C buffer |
| `xiom_copy_from_vec(c_buf, vec, off, cnt)` | Copy XIOM Vec → C buffer |
| `xiom_copy_to_vec(vec, c_buf, cnt)` | Copy C buffer → XIOM Vec |
| `xiom_vec_from_c(data, len)` | Wrap C buffer as XIOM Vec |
| `xiom_str_to_cstr(xiom_str, len)` | XIOM Str → null-terminated C string |
| `xiom_free_cstr(cstr)` | Free C string |

## XIOM Vec Layout

XIOM's `Vec[Int]` compiles to: `{ void* data; int64_t len; int64_t cap; }`
Each element is 8 bytes. `data[i]` = `((int64_t*)data)[i]`.

## Supported Platforms

- Windows (MSVC / MinGW-w64)
- Linux (glibc)
- macOS
