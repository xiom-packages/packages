# xiom-http — System Dependencies & Build Notes

## System Requirements

### libcurl
| OS | Package | Command |
|----|---------|---------|
| Windows | vcpkg | `vcpkg install curl:x64-windows` |
| Ubuntu/Debian | libcurl4-openssl-dev | `sudo apt install libcurl4-openssl-dev` |
| Fedora | libcurl-devel | `sudo dnf install libcurl-devel` |
| macOS | curl | `brew install curl` |

### XIOM Runtime Bridge
The FFI bridge provides `xiom_alloc`, `xiom_free_ptr`, `xiom_write_byte`, `xiom_read_byte`, `xiom_str_to_cstr`, `xiom_free_cstr`, and `xiom_copy_from_vec`. Link with:
```bash
xiom ... --c-source ../runtime/ffi_bridge.c -l curl
```

## Build Command Example
```bash
# Windows
xiom http.xi src/types.xi src/parser.xi ../runtime/ffi_bridge.c -l curl -o http_client.exe

# Linux/macOS
xiom http.xi src/types.xi src/parser.xi ../runtime/ffi_bridge.c -l curl -o http_client
```

## Compilation Status

### Pure-XIOM modules (type-check PASS):
- `src/types.xi` — HTTP enums, structs, headers manipulation
- `src/parser.xi` — RFC 7230 HTTP message parser
- `src/url.xi` — URL parsing, serialization, encoding
- `src/cookie.xi` — RFC 6265 cookie parsing
- `src/status.xi` — Status code helpers (32 codes)
- `src/mime.xi` — MIME type mapping (21 extensions)
- `src/server.xi` — Server stub types (awaiting TCP layer)

### FFI-dependent module (needs manual fix):
- `http.xi` — libcurl-backed HTTP client (GET/POST/PUT/DELETE/download)
  - **Known issue:** Uses `+` operator for string concatenation (`"prefix: " + err`); XIOM requires `string.str_concat(a, b)` for Str concatenation. All error/status message construction chains must be converted.
  - **Known issue:** Uses `Int as *UInt8` casts for libcurl option values. These must be replaced with `xiom_alloc`+`xiom_write_byte` buffer construction (see `int_as_ptr()` pattern in fixed version).
  - **Known issue:** CURLOPT_HTTPHEADER requires `curl_slist_append` which is not yet wired in the FFI. Content-Type headers are not sent for POST/PUT requests.
  - **Known issue:** Temp file response capture (`__xiom_http_body.tmp`, `__xiom_http_headers.tmp`). In-memory callback-based capture is planned for future versions.

### Caller modules (depend on http.xi):
- `src/client.xi` — High-level client wrapper; uses `xiom.http.http_*` functions
- `src/demo.xi` — Integration demos against httpbin.org

## Future Work
1. Replacing temp-file capture with in-memory CURLOPT_WRITEFUNCTION callbacks
2. Wiring `curl_slist_append` for custom HTTP headers
3. Native HTTP server transport via xiom-net TCP layer
4. Streaming/chunked response support
5. Multipart form upload support
