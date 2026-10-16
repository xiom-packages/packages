# xiom-http -- System Dependencies & Build Notes

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
- `src/types.xi` -- HTTP enums, structs, headers manipulation
- `src/parser.xi` -- RFC 7230 HTTP message parser
- `src/url.xi` -- URL parsing, serialization, encoding
- `src/cookie.xi` -- RFC 6265 cookie parsing
- `src/status.xi` -- Status code helpers (32 codes)
- `src/mime.xi` -- MIME type mapping (21 extensions)
- `src/server.xi` -- Server stub types (awaiting TCP layer)

### FFI-dependent module (links libcurl):
- `http.xi` -- libcurl-backed HTTP client (GET/POST/PUT/DELETE/download)
  - All `Str` concatenation goes through `string.str_concat`.
  - LONG curl options (FOLLOWLOCATION, TIMEOUT, CONNECTTIMEOUT, NOSIGNAL, BUFFERSIZE, POST, POSTFIELDSIZE) pass the value itself through an Int -> *UInt8 value cast (`make_long_value`) per libcurl's variadic ABI (fixed in 0.1.4). Do NOT reintroduce `xiom_alloc`+`xiom_write_byte` buffers for these -- libcurl reads a `long`, not a pointer.
  - STRINGPOINT/OBJECTPOINT options (URL, ACCEPT_ENCODING, USERAGENT, POSTFIELDS, CUSTOMREQUEST, WRITEDATA, HEADERDATA) pass real pointers from `xiom_str_to_cstr` / `FILE*`; those are freed after `curl_easy_setopt` returns.
  - **Custom request headers (0.1.8):** `CURLOPT_HTTPHEADER` is fed a
    `curl_slist` built by the bridge helpers `xiom_http_headers_build` /
    `xiom_http_headers_free` (real `curl_slist_append` / `curl_slist_free_all`,
    forward-declared in the shim -- no libcurl headers or stubs). The list is
    freed after `curl_easy_cleanup`; blob shape and validation live in
    `xiom.http.headers` (`src/headers.xi`) and are consumed by `http_request`.
    `http_post`'s `content_type` argument remains a compatibility no-op (pass
    an explicit `Content-Type` header through the new entry instead).
  - **Known issue:** Temp file response capture (`__xiom_http_body.tmp`, `__xiom_http_headers.tmp`). In-memory callback-based capture is planned for future versions.

### Caller modules (depend on http.xi):
- `src/client.xi` -- High-level client wrapper; uses `xiom.http.http_*` functions
- `src/demo.xi` -- Integration demos against httpbin.org

## Future Work
1. Replacing temp-file capture with in-memory CURLOPT_WRITEFUNCTION callbacks
2. Native HTTP server transport via xiom-net TCP layer
3. Streaming/chunked response support
4. Multipart form upload support
