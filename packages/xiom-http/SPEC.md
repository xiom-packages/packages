# xiom.http -- XIOM HTTP Library Specification

## Overview

`xiom.http` is the Layer 3.2 ecosystem package providing HTTP protocol support for XIOM. It covers type definitions, message parsing, status codes, MIME types, URL manipulation, cookies, client/server stubs, and a production HTTP client backed by libcurl.

## Modules

### `xiom.http.types` (`src/types.xi`)

Core HTTP protocol data types and serialization.

**Enums:**
- `HttpMethod` -- GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
- `HttpVersion` -- HTTP09, HTTP10, HTTP11, HTTP20

**Structs:**
- `HttpHeader { name: Str; value: Str; }`
- `HttpHeaders { entries: Vec[HttpHeader]; }`
- `HttpRequest { method: HttpMethod; path: Str; version: HttpVersion; headers: HttpHeaders; body: Vec[Int]; }`
- `HttpResponse { version: HttpVersion; status: Int; reason: Str; headers: HttpHeaders; body: Vec[Int]; }`

**HttpHeaders methods:**
| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `() -> HttpHeaders` | Create empty headers |
| `add` | `(name: Str, value: Str)` | Append header |
| `get` | `(name: Str) -> Option[Str]` | Find header by name |
| `has` | `(name: Str) -> Bool` | Check header existence |
| `remove` | `(name: Str) -> Bool` | Remove first matching header |
| `count` | `() -> Int` | Return number of headers |

**HttpRequest methods:**
| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `(method: HttpMethod, path: Str) -> HttpRequest` | Create request (defaults to HTTP/1.1) |
| `set_header` | `(name: Str, value: Str)` | Add header |
| `set_body` | `(body: Vec[Int])` | Set body bytes |
| `to_str` | `() -> Str` | Serialize to HTTP/1.1 wire format |

**HttpResponse methods:**
| Method | Signature | Description |
|--------|-----------|-------------|
| `new` | `(status: Int) -> HttpResponse` | Create response (defaults to HTTP/1.1) |
| `set_header` | `(name: Str, value: Str)` | Add header |
| `set_body` | `(body: Vec[Int])` | Set body bytes |
| `to_str` | `() -> Str` | Serialize to HTTP/1.1 wire format |

---

### `xiom.http.parser` (`src/parser.xi`)

HTTP message parser operating on raw strings.

**Exports:**
| Function | Signature | Description |
|----------|-----------|-------------|
| `http_parse_request` | `(input: Str) -> Result[HttpRequest, HttpParseError]` | Parse raw HTTP request |
| `http_parse_response` | `(input: Str) -> Result[HttpResponse, HttpParseError]` | Parse raw HTTP response |
| `http_parse_headers` | `(input: Str) -> Result[HttpHeaders, HttpParseError]` | Parse headers block |

**Error type:** `HttpParseError { message: Str; position: Int; }`

Uses `@xiom_str_len` and `@xiom_char_at` intrinsics for character-by-character parsing. Position-counters track progress through the input.

---

### `xiom.http.status` (`src/status.xi`)

HTTP status code classification and reason phrases.

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_status_text` | `(code: Int) -> Str` | Reason phrase (e.g. 200->"OK") |
| `http_is_success` | `(code: Int) -> Bool` | 2xx range |
| `http_is_redirect` | `(code: Int) -> Bool` | 3xx range |
| `http_is_client_error` | `(code: Int) -> Bool` | 4xx range |
| `http_is_server_error` | `(code: Int) -> Bool` | 5xx range |
| `http_status_category` | `(code: Int) -> Int` | Returns 100,200,300,400,500 |

---

### `xiom.http.mime` (`src/mime.xi`)

MIME type mapping from file extensions.

**Types:** `MimeType { main_type: Str; sub_type: Str; }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `mime_from_ext` | `(ext: Str) -> MimeType` | .html->text/html, .json->application/json, etc. |
| `mime_to_str` | `(mime: &MimeType) -> Str` | Format as "type/subtype" |

**Covered extensions:** html/css/js/json/xml/png/jpg/gif/svg/pdf/txt/csv/zip/mp3/mp4/wasm/woff/woff2/ico/webp/ogg

---

### `xiom.http.url` (`src/url.xi`)

URL parsing, encoding, and path utilities.

**Types:** `Url { scheme: Str; host: Str; port: Int; path: Str; query: Str; fragment: Str; }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `url_parse` | `(input: Str) -> Result[Url, Str]` | Parse URL string |
| `url_to_str` | `(url: &Url) -> Str` | Serialize URL |
| `url_encode` | `(s: Str) -> Str` | Percent-encode string |
| `url_decode` | `(s: Str) -> Result[Str, Str]` | Percent-decode string |
| `path_join` | `(base: Str, relative: Str) -> Str` | Join URL path segments |

---

### `xiom.http.cookie` (`src/cookie.xi`)

HTTP cookie parsing and serialization.

**Types:** `Cookie { name: Str; value: Str; domain: Str; path: Str; secure: Bool; http_only: Bool; max_age: Int; }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `cookie_new` | `(name: Str, value: Str) -> Cookie` | Create basic cookie |
| `cookie_parse` | `(set_cookie_header: Str) -> Result[Cookie, Str]` | Parse Set-Cookie header |
| `cookie_to_str` | `(cookie: &Cookie) -> Str` | Format as cookie string |
| `cookie_parse_all` | `(cookie_header: Str) -> Vec[Cookie]` | Parse Cookie header (multiple cookies) |

---

### `xiom.http` (`http.xi`)

Production HTTP client backed by libcurl. This is the primary entry point for HTTP operations. Defines its own simplified `HttpClientResponse` type with `Str` body.

**Types:** `HttpClientResponse { status: Int; body: Str; headers: Str; }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `(url: Str) -> Result[HttpClientResponse, Str]` | HTTP GET request |
| `http_post` | `(url: Str, body: Str, content_type: Str) -> Result[HttpClientResponse, Str]` | HTTP POST request |
| `http_put` | `(url: Str, body: Str) -> Result[HttpClientResponse, Str]` | HTTP PUT request |
| `http_delete` | `(url: Str) -> Result[HttpClientResponse, Str]` | HTTP DELETE request |
| `http_download` | `(url: Str, path: Str) -> Result[Unit, Str]` | Download to a file on disk |

All functions:
1. Initialize a libcurl easy handle via `curl_easy_init()`
2. Configure common options: URL, follow redirects, timeouts (30s/10s), user agent (`xiom.http/0.1.0` -- a stable compatibility pin, see the 0.1.4 fix pass), accept-encoding (gzip/deflate), no signals, buffer size 64 KiB
3. Set method-specific options (POST fields, custom request verb, etc.)
4. Capture response body and headers into temporary files via `CURLOPT_WRITEDATA` / `CURLOPT_HEADERDATA`
5. Execute via `curl_easy_perform()`
6. Extract HTTP status code via `curl_easy_getinfo(CURLINFO_RESPONSE_CODE)`
7. Read response body and headers from temp files, clean up temp files
8. Free the curl handle via `curl_easy_cleanup()`
9. Return `Ok(HttpClientResponse)` or `Err(message)`

### `xiom.http.client` (`src/client.xi`)

High-level HTTP client that delegates to `xiom.http` functions with `Vec[Int]` body types (using `xiom.http.types.HttpResponse`).

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `(url: Str) -> Result[HttpResponse, Str]` | Delegates to `xiom.http.http_get` |
| `http_post` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]` | Converts body to Str, delegates |
| `http_put` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]` | Converts body to Str, delegates |
| `http_delete` | `(url: Str) -> Result[HttpResponse, Str]` | Delegates to `xiom.http.http_delete` |
| `http_send` | `(request: &HttpRequest, url: &Url) -> Result[HttpResponse, Str]` | Serializes request, dispatches by method |

`http_send` work flow:
1. Serialize `Url` to string via internal `url_to_str`
2. Convert `request.body` (`Vec[Int]`) to `Str`
3. Extract `Content-Type` from `request.headers`
4. Dispatch: GET->http_get, POST->http_post, PUT->http_put, DELETE->http_delete, PATCH->http_post with JSON content type, HEAD/OPTIONS->http_get

### `xiom.http.demo` (`src/demo.xi`)

Demonstration module exercising the HTTP client against httpbin.org.

| Function | Signature | Description |
|----------|-----------|-------------|
| `demo_get` | `() -> Result[Unit, Str]` | GET `https://httpbin.org/get`, verifies 200 + non-empty body |
| `demo_post` | `() -> Result[Unit, Str]` | POST JSON to `https://httpbin.org/post`, verifies 200 |
| `demo_rest_api` | `() -> Result[Unit, Str]` | Full CRUD: GET, POST (create), PUT (update), DELETE, download PNG image |

### `xiom.http.server` (`src/server.xi`)

HTTP server types and stubs. These return errors until Layer 3.1 (TCP) is available.

**Types:**
- `HttpServer { addr: Str; port: Int; running: Bool; }`
- `HttpHandler { path: Str; method: HttpMethod; }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `server_new` | `(addr: Str, port: Int) -> HttpServer` | Create server config |
| `server_listen` | `(server: &mut HttpServer) -> Result[Unit, Str]` | Start listening (stub) |
| `server_handle` | `(server: &mut HttpServer, method: HttpMethod, path: Str) -> Result[Unit, Str]` | Register handler (stub) |
| `server_close` | `(server: HttpServer)` | Shutdown server (stub) |

---

## libcurl Setup

### System Dependencies

The `xiom.http` module links against **libcurl** (version 7.80+ recommended). The FFI declarations are in `libcurl.xiom-bind`.

#### Linux (Debian/Ubuntu)
```bash
sudo apt-get install libcurl4-openssl-dev
```

#### Linux (RHEL/Fedora)
```bash
sudo dnf install libcurl-devel
```

#### macOS
```bash
brew install curl
# If XIOM links against system curl:
# No extra steps -- macOS ships libcurl.
```

#### Windows
```bash
# Via vcpkg
vcpkg install curl:x64-windows

# Or download prebuilt from https://curl.se/windows/
# Place libcurl.dll and libcurl.lib in the linker search path.
```

### Build Configuration

XIOM links libcurl at compile time. Ensure the linker can find `libcurl`:

```json
// In project build config or kilo.json:
{
  "link": {
    "libraries": ["curl"]
  }
}
```

### Verifying the Build

```bash
# Compile the xiom.http package
xiom build --package xiom.http

# Run the demo
xiom run --module xiom.http.demo --fn demo_get
```

### Runtime Requirements

The libcurl FFI layer requires the following runtime features from XIOM's C interop:

| Feature | Status | Description |
|---------|--------|-------------|
| `Str.c_str()` | Available | Converts XIOM `Str` to null-terminated `*UInt8` |
| `Str.from_c_str(ptr)` | Available | Creates XIOM `Str` from C string pointer |
| `as Int` pointer cast | Required | Casts `*UInt8` pointer to `Int` for passing through `curl_easy_setopt` (Int API surface) |
| `malloc` / `free` | Available | Via `xiom.ffi` -- used for response code extraction buffer |
| Temp file I/O | Available | `fopen`/`fclose`/`fread`/`fwrite`/`fseek`/`ftell`/`remove` -- used for response body and header capture |
| `curl_slist_append` | Not yet wired | Required for custom request headers (`CURLOPT_HTTPHEADER`). POST with Content-Type falls back to libcurl defaults until this is available. |
| Function pointer callbacks | Not yet wired | `CURLOPT_WRITEFUNCTION` and `CURLOPT_HEADERFUNCTION` are not used; file-based capture via `CURLOPT_WRITEDATA`/`CURLOPT_HEADERDATA` with default `fwrite` callback is used instead. |

### curl Option Constants Used

| Constant | Value | Purpose |
|----------|-------|---------|
| `CURLOPT_URL` | 10002 | Request URL |
| `CURLOPT_FOLLOWLOCATION` | 52 | Follow HTTP redirects |
| `CURLOPT_TIMEOUT` | 13 | Total request timeout (30s) |
| `CURLOPT_CONNECTTIMEOUT` | 78 | Connection timeout (10s) |
| `CURLOPT_POST` | 47 | Enable POST method |
| `CURLOPT_POSTFIELDS` | 10015 | POST/PUT body data |
| `CURLOPT_POSTFIELDSIZE` | 60 | POST/PUT body size in bytes |
| `CURLOPT_CUSTOMREQUEST` | 10036 | Custom method string (PUT, DELETE) |
| `CURLOPT_HTTPHEADER` | 10023 | Custom request headers (requires curl_slist) |
| `CURLOPT_WRITEDATA` | 10001 | FILE* for response body output |
| `CURLOPT_HEADERDATA` | 10029 | FILE* for response header output |
| `CURLOPT_SSL_VERIFYPEER` | 64 | Verify TLS certificate |
| `CURLOPT_SSL_VERIFYHOST` | 81 | Verify TLS hostname |
| `CURLOPT_USERAGENT` | 10018 | User-Agent header |
| `CURLOPT_NOSIGNAL` | 99 | Disable signals (required for threaded use) |
| `CURLOPT_ACCEPT_ENCODING` | 10102 | Accept-Encoding header |
| `CURLOPT_BUFFERSIZE` | 98 | Internal transfer buffer size |
| `CURLOPT_FAILONERROR` | 45 | Treat HTTP 4xx/5xx as errors |
| `CURLOPT_TCP_KEEPALIVE` | 213 | Enable TCP keepalive |
| `CURLOPT_VERBOSE` | 41 | Verbose debug output |
| `CURLINFO_RESPONSE_CODE` | 2097154 | Extract HTTP status code |
| `CURLINFO_CONTENT_TYPE` | 2097186 | Extract Content-Type header |
| `CURLINFO_TOTAL_TIME` | 3145731 | Total transfer time |

---

## Design Notes

### String Parsing
Without a full stdlib, string manipulation uses `@xiom_str_len` for length queries and `@xiom_char_at` for character access. All parsing maintains position counters and builds substrings via character-by-character concatenation.

### `to_str` Serialization
Both `HttpRequest.to_str()` and `HttpResponse.to_str()` produce valid HTTP/1.1 wire format with `\r\n` line endings. Integer-to-string conversion is done via manual digit extraction (no `sprintf`-like functionality).

### libcurl Response Capture Strategy
Instead of using `CURLOPT_WRITEFUNCTION` callbacks (which require function pointer support in XIOM's FFI layer), the client captures response body and headers into temporary files:

1. Open `__xiom_http_body.tmp` and `__xiom_http_headers.tmp` via `fopen("wb+")`
2. Set `CURLOPT_WRITEDATA` to the body FILE* and `CURLOPT_HEADERDATA` to the header FILE*
3. libcurl's default `fwrite` callback writes response data directly to these files
4. After `curl_easy_perform()`, `fseek` + `ftell` to get file sizes, `fread` into a `malloc` buffer, convert to `Str` via `Str.from_c_str`
5. `fclose` both files, `remove` both temp files

### Future Integration
When XIOM's FFI layer gains function pointer support, the temp-file approach will be replaced with an in-memory write callback:

```xiom
fn write_callback(data: *UInt8, size: UInt, nmemb: UInt, userdata: *UInt8) -> UInt {
  // Append data to Vec[UInt8] buffer stored in userdata
}
```

This will eliminate disk I/O for response capture and improve performance.

### Client/Server TCP Integration
Client and server stubs in `src/client.xi` and `src/server.xi` delegate to `xiom.http` where possible. The `http_send` function uses manual URL serialization and method dispatch. Future integration with `xiom.net.tcp` (Layer 3.1) will allow direct socket-based HTTP without libcurl for platforms where libcurl is unavailable.

---

## Roadmap / Planned Core Modules

The modules documented above are the **implemented** surface of `xiom.http`: the libcurl-backed client, HTTP message types, parser, URL, cookie, MIME, and status helpers. The following core modules are **design-stage** -- specified in [ARCHITECTURE.md](ARCHITECTURE.md) but not yet built. They are listed here so the spec reflects the intended shape of the lean native core.

| Planned module | Directory | Responsibility | Status |
|----------------|-----------|----------------|--------|
| Router | `src/router/` | Method + path matching with typed path params and wildcards; per-module route tables merged explicitly at startup. | Design-stage |
| Middleware | `src/middleware/` | Onion-model chain with explicit `next` closures; built-in middleware (logger, cors, compress, rate_limit, timeout, recover). | Design-stage |
| Plugin | `src/plugin/` | Fastify-style scope encapsulation -- child scopes inherit from parents but not the reverse; no global mutable app state. | Design-stage |
| JSON codec | `src/json/` | Schema-first encode/decode driven by native XIOM types rather than a runtime JSON Schema interpreter. | Design-stage |
| Contracts | `src/contracts/` | Contract-at-the-edge request/response validation via `requires`/`ensures` at the HTTP boundary. | Design-stage |
| Static files | `src/static/` | Static file serving with MIME resolution as an explicit module (not implicit-fallthrough middleware). | Design-stage |

### Native server transport

The planned native server (`src/server.xi` beyond its current stub) will accept connections and dispatch requests through the router and middleware chain using **`xiom.net` (TCP, Layer 3.1)** as its transport -- not libcurl. libcurl remains exclusively the **client** transport. This keeps the server free of the libcurl dependency and allows platforms without libcurl to still run a server.

See [ARCHITECTURE.md](ARCHITECTURE.md) -> "Current State vs Target" for the full implemented-vs-planned breakdown.

---

## Contracts (ensures-only pass, 2026-10-09)

Runtime-checkable `ensures:` clauses added to `http.xi` (the package-root `xiom.http` module; compiler v0.64.1; no version bump): **38 clauses over 33 private helpers** (27 constant accessors + 6 string/response helpers). The five public entry points, the FFI helpers, and the two dead functions (`str_to_cstr_or_err`, `check_url`) are unchanged; no `requires:` clause was added. The 0.1.4 fix pass below re-pins `byte_to_char`/`char_to_str` (38 -> 37 clauses).

Z3-provable: **no** for every clause in this pass. No Z3 proof was attempted, and `xiom-verify` would be vacuous for the FFI-backed helpers here (the `extern "C"` functions have no bodies, so obligations over their results say nothing about the implementation). All clauses are runtime-checked.

The 40-check `tests/test_conformance.xi` suite never imports the root module, so these clauses get no runtime exercise there. They are exercised by `tests/probe_root_module.xi`, a fast-fail `http_get("http://127.0.0.1:1/")` probe (closed port) that drives the helper chain `str_to_cstr -> setup_common_options -> perform_and_collect -> get_response_code -> read_file_to_str -> curl_error_string -> cstr_to_str -> byte_to_char -> char_to_str`. The probe links `tests/probe_bridge.c` because the v0.64.2 toolchain ships no FFI bridge symbols and no libcurl (see the probe header for the exact invocation). The suite grows to 42 checks in the 0.1.4 fix pass.

Two clauses were refined from the pre-plan because the pre-plan bound does not hold for this source: `cstr_to_str` and `read_file_to_str` guarantee `result.len() <= 196608`, not `<= 65536` -- under the pre-0.1.4 numeric `char_to_str` each of the 65536 loop iterations could append a 3-character numeric string via `byte_to_char`/`char_to_str`. Since the 0.1.4 character-rendering fix every appended unit is at most one character, so `<= 65536` would now also hold; the bound is left at the (true, now slack) `<= 196608` to keep the fix pass scoped to the two defect clauses.

| Function | Clause(s) added | Z3-provable | Runtime-checked |
|---|---|---|---|
| `CURLOPT_URL` | `result == 10002` | no | yes |
| `CURLOPT_FOLLOWLOCATION` | `result == 52` | no | yes |
| `CURLOPT_TIMEOUT` | `result == 13` | no | yes |
| `CURLOPT_CONNECTTIMEOUT` | `result == 78` | no | yes |
| `CURLOPT_POST` | `result == 47` | no | yes |
| `CURLOPT_POSTFIELDS` | `result == 10015` | no | yes |
| `CURLOPT_POSTFIELDSIZE` | `result == 60` | no | yes |
| `CURLOPT_CUSTOMREQUEST` | `result == 10036` | no | yes |
| `CURLOPT_HTTPHEADER` | `result == 10023` | no | yes |
| `CURLOPT_SSL_VERIFYPEER` | `result == 64` | no | yes |
| `CURLOPT_SSL_VERIFYHOST` | `result == 81` | no | yes |
| `CURLOPT_USERAGENT` | `result == 10018` | no | yes |
| `CURLOPT_WRITEDATA` | `result == 10001` | no | yes |
| `CURLOPT_HEADERDATA` | `result == 10029` | no | yes |
| `CURLOPT_NOSIGNAL` | `result == 99` | no | yes |
| `CURLOPT_FAILONERROR` | `result == 45` | no | yes |
| `CURLOPT_ACCEPT_ENCODING` | `result == 10102` | no | yes |
| `CURLOPT_TCP_KEEPALIVE` | `result == 213` | no | yes |
| `CURLOPT_TCP_KEEPIDLE` | `result == 214` | no | yes |
| `CURLOPT_TCP_KEEPINTVL` | `result == 215` | no | yes |
| `CURLOPT_BUFFERSIZE` | `result == 98` | no | yes |
| `CURLINFO_RESPONSE_CODE` | `result == 2097154` | no | yes |
| `SEEK_SET` | `result == 0` | no | yes |
| `SEEK_END` | `result == 2` | no | yes |
| `BUF_SIZE` | `result == 65536` | no | yes |
| `TEMP_BODY` | `result.len() == 20` | no | yes |
| `TEMP_HEADERS` | `result.len() == 23` | no | yes |
| `curl_error_string` | `result.len() > 0` | no | yes |
| `cstr_to_str` | `result.len() <= 196608` | no | yes |
| `byte_to_char` | `b == 0 => result.len() == 0`; `b == 9 \|\| b == 10 \|\| b == 13 \|\| b == 32 => result.len() == 1`; `b >= 33 && b <= 126 => result.len() == 1`; `b != 0 && b != 9 && b != 10 && b != 13 && b != 32 && (b < 33 \|\| b > 126) => result.len() == 1` | no | yes |
| `char_to_str` | `result.len() <= 4` | no | yes |
| `read_file_to_str` | `result.len() <= 196608` | no | yes |
| `get_response_code` | `result >= 0`; `result <= 65535` | no | yes |

Source-shape notes pinned by the clauses:

- `byte_to_char`'s length clauses pin the character-rendering behavior of `char_to_str` (`tostring.to_string_char(c)`): a printable byte renders as the actual character ("A" for 65), exactly one character for every 33..126 byte. The pre-0.1.4 numeric-string shape (`len() == 2` / `len() == 3`) is gone, as anticipated by this note.
- `char_to_str`'s `result.len() <= 4` clause is the shape that is true for every `Char` (UTF-8 is 1-4 bytes); the earlier `result.len() >= 1` is deliberately NOT used because `to_string_char(to_char(0))` renders the empty string -- the stdlib helper is C-string based, so the leading NUL terminates it. `byte_to_char` never routes byte 0 through `char_to_str`, so the printing path always yields >= 1 char.
- The constant pins are inlined literals (no module constants in clauses); the value is checked each time the accessor runs, call site or not.
- Memory-safety fixes from the 0.1.3 pass are intact: the `setup_common_options` `p1` double-free was removed, and `http_download` calls `remove(path_cstr)` before `xiom_free_cstr(path_cstr)` on both the perform-error and the non-2xx paths (previously remove-after-free). The 0.1.4 pass additionally removed the `xiom_alloc`/`xiom_free_ptr` dance at every LONG option site (values are passed by cast), so those sites can neither leak nor double-free. The probe bridge uses a real libc `free`, so the double-free removal is exercised at runtime.

---

## 0.1.4 fix pass (2026-10-09)

Two live defects fixed; public API signatures, dependencies, and `libcurl.xiom-bind` are unchanged.

### Fix A -- character rendering (`byte_to_char` / `char_to_str`, all copies)

`char_to_str` previously returned `to_string(to_int_from_char(c))`, so a printable byte rendered as its decimal code ("65" for 'A'). Every copy now renders the actual character for printable ASCII 33..126 via the stdlib helper `xiom.convert.tostring.to_string_char` (module `xiom.convert.tostring`; it encodes the Char as 1-4 UTF-8 bytes with `xiom.char.encode_utf8`, O(1)). A stdlib function was chosen over a local encoder to avoid duplicating UTF-8 logic. Copies updated:

| File | Helper | Change |
|---|---|---|
| `http.xi` | `char_to_str`, `byte_to_char` | numeric -> `tostring.to_string_char`; clauses re-pinned |
| `src/url.xi` | `char_to_str` | hardcoded map -> `tostring.to_string_char`; now also covers 91..96 and 123..126 (previously "?") |
| `src/client.xi` | `byte_to_char` | hardcoded map -> `tostring.to_string_char`; covers 123..126 (previously "?") |
| `src/types.xi` | `byte_to_char` | hardcoded map -> `tostring.to_string_char`; covers 123..126 (previously "?") |

Special mappings are preserved per copy: root `0 -> ""`, 9 -> "\t", 10 -> "\n", 13 -> "\r", 32 -> " "; `src/url.xi` keeps 32 -> " " only; `src/client.xi`/`src/types.xi` keep 0 -> "\0". Non-printable, non-special bytes keep the per-copy fallback (all four fall back to "?").

Clause changes (runtime-checked; not Z3-proved -- the callee is a stdlib function and the FFI-adjacent helpers have no provable bodies): `byte_to_char`'s `len() == 2` (33..99) and `len() == 3` (100..126) clauses became `b >= 33 && b <= 126 => result.len() == 1`. `char_to_str`'s `result.len() >= 1` was weakened to `result.len() <= 4`; the old clause does not hold for every `Char` because `to_string_char(to_char(0))` renders the empty string (C-string NUL terminator) and UTF-8 is at most 4 bytes otherwise.

Suite: `tests/test_conformance.xi` grows from 40 to 42 checks, adding `url parse printable ascii` (`src/url.xi`: path `~ | { }` plus a space) and `response to_str body chars` (`src/types.xi`: body bytes 126, 124 -> "~|"). Both fail on the old mapping and pass on the new one.

### Fix B -- variadic LONG options (`make_ptr_value` -> `make_long_value`)

libcurl's `curl_easy_setopt` is variadic; for CURLOPTTYPE_LONG options the third argument is the long value itself. The old helper allocated 8 heap bytes, stored the value there, and passed the pointer, so real libcurl stored the ADDRESS (TIMEOUT=30 / CONNECTTIMEOUT=10 / POSTFIELDSIZE=len became address-sized values, effectively ignored; FOLLOWLOCATION only worked by accident), and every call leaked. The helper is now `make_long_value`, an Int -> *UInt8 value cast (`v as *UInt8` into a null-initialized local inside `unsafe`; the whole-body-`return` form miscompiles to null on v0.64.2). The LONG sites -- FOLLOWLOCATION, TIMEOUT, CONNECTTIMEOUT, NOSIGNAL, BUFFERSIZE, POST, POSTFIELDSIZE (POST and PUT) -- pass the bare value with no allocation or free. STRINGPOINT/OBJECTPOINT sites (URL, ACCEPT_ENCODING, USERAGENT, POSTFIELDS, CUSTOMREQUEST, WRITEDATA, HEADERDATA) keep real pointers and their frees.

`tests/probe_bridge.c` now emulates the variadic ABI: the stub reads the LONG argument as an integer value (never dereferencing it) and rejects implausible values with CURLE_BAD_FUNCTION_ARGUMENT (43), pinning the configured values (FOLLOWLOCATION/NOSIGNAL/POST = 1, TIMEOUT = 30, CONNECTTIMEOUT = 10, BUFFERSIZE = 65536). The pre-0.1.4 heap-pointer code fails this probe.

### User-Agent

The literal `"xiom.http/0.1.0"` is left unchanged: the SPEC has always documented it as the client identifier, it survived the 0.1.1..0.1.4 version bumps, and it is therefore treated as a compatibility pin rather than a mirror of `package.xi`'s version.

