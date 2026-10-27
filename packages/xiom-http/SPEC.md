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

### `xiom.http.body` (`src/body.xi`) -- 0.1.9

Pure raw-bytes request-body layer (no FFI, no I/O). It carries the exact body
bytes plus the caller-declared `Content-Length` and validates them before any
transfer starts. Bytes are never UTF-8 encoded, trimmed, or NUL-terminated.

**Types:**
- `HttpBytesBody { bytes: Vec[UInt8]; content_length: Int; }`
- `HttpBodyError = enum { LengthMismatch(declared: Int, actual: Int); NegativeLength(declared: Int); }`

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_bytes_body` | `(bytes: Vec[UInt8], content_length: Int) -> Result[HttpBytesBody, HttpBodyError]` | Validate the span length against the declared length |
| `http_bytes_body_wire` | `(body: &HttpBytesBody) -> Vec[UInt8]` | Exact byte-for-byte copy for the wire (no conversion) |
| `http_body_error_message` | `(err: &HttpBodyError) -> Str` | Deterministic, secret-free error text |

Validation (frozen): a negative `content_length` returns
`HttpBodyError.NegativeLength(declared)`; any mismatch returns
`HttpBodyError.LengthMismatch(declared, actual)` where `actual` is
`bytes.len()`. A matching pair returns the body unchanged, including `0x00`
and `0x80..0xFF`.

---

### `xiom.http.headers` (`src/headers.xi`) -- 0.1.8

Deterministic header-list builder for the client's custom-header path (0.1.8).
Pure: no FFI, no I/O, nothing logged; a client entry that consumes the blob
lives in `xiom.http` (`http_request`).

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_headers_blob` | `(headers: Vec[HttpHeader]) -> Result[Str, Str]` | Render the CRLF wire blob for `http_request` |

Wire shape (frozen): each pair renders as `"Name: value\r\n"`; the blob is the
concatenation in declaration order (so the last line is CRLF-terminated too).
An empty input returns `Ok("")` -- the sentinel for "no custom headers".
Duplicate names are preserved in order; values are not trimmed or re-encoded.

Validation (frozen): names must be non-empty RFC 7230 tokens (ASCII only; no
space, colon, or control characters). Values may be empty and pass through
verbatim (bytes >= 128 included) but CR, LF, NUL, DEL and every other control
character except HTAB are rejected, so header injection cannot be built from
this module. Values never appear in error text or logs; error strings carry
the header name at most:

- `http_headers_blob: empty header name`
- `http_headers_blob: invalid header name: <name>`
- `http_headers_blob: header value contains a control character: <name>`

---

### `xiom.http.options` (`src/options.xi`) -- 0.1.10

Pure, FFI-free per-call transport options. The root client translates the
values into libcurl millisecond options; nothing in this module performs I/O.

**Types:** `HttpRequestOptions { connect_ms: Int; total_ms: Int; }`
(derives `Clone`).

**Errors:** `HttpRequestOptionError.ConnectTimeoutNegative(value)` and
`TotalTimeoutNegative(value)`.

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_request_options_default` | `() -> HttpRequestOptions` | `10000` / `30000` ms defaults |
| `validate_request_options` | `(&HttpRequestOptions) -> Result[Unit, HttpRequestOptionError]` | Reject negative timeouts |
| `effective_connect_ms` | `(&HttpRequestOptions) -> Int` | Resolve `0` to `10000` |
| `effective_total_ms` | `(&HttpRequestOptions) -> Int` | Resolve `0` to `30000` |
| `http_request_option_error_message` | `(&HttpRequestOptionError) -> Str` | Deterministic text |

`0` means "library default" for both fields; positive values are used
verbatim in milliseconds. Validation borrows the options, so callers can keep
using the value after validating it. There is no upper bound beyond `Int`.

---

### `xiom.http` (`http.xi`)

Production HTTP client backed by libcurl. This is the primary entry point for HTTP operations. Defines its own simplified `HttpClientResponse` type with `Str` body.

**Types:** `HttpClientResponse { status: Int; body: Str; headers: Str; }`,
`HttpClientSession { handle: *UInt8; }` (0.1.10).

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `(url: Str) -> Result[HttpClientResponse, Str]` | HTTP GET request |
| `http_post` | `(url: Str, body: Str, content_type: Str) -> Result[HttpClientResponse, Str]` | HTTP POST request |
| `http_put` | `(url: Str, body: Str) -> Result[HttpClientResponse, Str]` | HTTP PUT request |
| `http_delete` | `(url: Str) -> Result[HttpClientResponse, Str]` | HTTP DELETE request |
| `http_download` | `(url: Str, path: Str) -> Result[Unit, Str]` | Download to a file on disk |
| `http_request` | `(url: Str, method: Str, body: Str, headers: Str) -> Result[HttpClientResponse, Str]` | Headers-capable request (0.1.8; see below) |
| `http_request_with_options` | `(url: Str, method: Str, body: Str, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, HttpOptionsRequestError]` | Per-call timeouts (0.1.10) |
| `http_request_bytes` | `(url: Str, method: Str, body: Vec[UInt8], content_length: Int, headers: Str) -> Result[HttpClientResponse, HttpBytesRequestError]` | Binary-safe request body (0.1.9; see below) |
| `http_request_bytes_with_options` | `(url: Str, method: Str, body: Vec[UInt8], content_length: Int, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, HttpBytesRequestError]` | Binary body + per-call timeouts (0.1.10) |
| `session_new` | `() -> Result[HttpClientSession, Str]` | Allocate one reusable easy handle |
| `session_close` | `(session: HttpClientSession)` | `curl_easy_cleanup` exactly once |
| `session_request` | `(&HttpClientSession, url, method, body, headers) -> Result[HttpClientResponse, Str]` | One transfer on the session handle |
| `session_request_with_options` | `(&HttpClientSession, url, method, body, headers, opts) -> Result[HttpClientResponse, HttpOptionsRequestError]` | Session transfer + per-call timeouts |

All one-shot functions:
1. Initialize a libcurl easy handle via `curl_easy_init()`
2. Configure common options: URL, follow redirects, timeouts (30000 ms total / 10000 ms connect via `CURLOPT_TIMEOUT_MS` / `CURLOPT_CONNECTTIMEOUT_MS`; the options entries override these), user agent (`xiom.http/0.1.0` -- a stable compatibility pin, see the 0.1.4 fix pass), accept-encoding (gzip/deflate), no signals, buffer size 64 KiB
3. Set method-specific options (POST fields, custom request verb, etc.)
4. Capture response body and headers into temporary files via `CURLOPT_WRITEDATA` / `CURLOPT_HEADERDATA`
5. Execute via `curl_easy_perform()`
6. Extract HTTP status code via `curl_easy_getinfo(CURLINFO_RESPONSE_CODE)`
7. Read response body and headers from temp files, clean up temp files
8. Free the curl handle via `curl_easy_cleanup()`
9. Return `Ok(HttpClientResponse)` or `Err(message)`

`http_request` (0.1.8) follows the same flow; additionally it builds a
`curl_slist` from the CRLF header blob (the `xiom.http.headers.http_headers_blob`
output) via the bridge helper `xiom_http_headers_build`, sets it with
`CURLOPT_HTTPHEADER`, and frees it with `xiom_http_headers_free` AFTER
`curl_easy_cleanup` -- the order libcurl requires (it references the list until
cleanup). An empty header blob skips `CURLOPT_HTTPHEADER` entirely, keeping the
exact wrapper behavior. The method must be GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS
(any other value returns `Err` before any FFI call); the body applies to
POST/PUT/PATCH and is ignored for GET/DELETE/HEAD/OPTIONS. Header values are
never logged or echoed in error messages.

Per-call timeouts (0.1.10): `http_request_with_options` and
`http_request_bytes_with_options` validate `HttpRequestOptions` before any FFI
call. Negative timeouts return `HttpOptionsRequestError.ConnectTimeoutNegative`
/ `TotalTimeoutNegative` (the bytes entry uses the matching
`HttpBytesRequestError` variants); transport failures wrap the existing libcurl
text in `Transport`. Existing entries keep the 10000 / 30000 ms defaults.

Sessions (0.1.10): `session_new()` allocates one easy handle; each
`session_request` / `session_request_with_options` call configures the URL,
method, headers, body, and timeouts on that same handle, performs one
transfer, and releases per-request resources (header slist via
`CURLOPT_HTTPHEADER = NULL` then `xiom_http_headers_free`, plus C-string
copies). Request-specific options are reset (`CURLOPT_POST = 0`,
`CURLOPT_CUSTOMREQUEST = NULL`, `CURLOPT_POSTFIELDS = NULL`,
`CURLOPT_POSTFIELDSIZE = 0`) before each call so a previous POST cannot leak
into a later GET. libcurl's connection cache lives on the handle, so
sequential requests to the same origin reuse the connection. The handle is
never cleaned up on transfer success or failure; `session_close` performs
exactly one `curl_easy_cleanup`, after which the session must not be used.
One-shot entries are unchanged (init/cleanup per call).

### `xiom.http.client` (`src/client.xi`)High-level HTTP client that delegates to `xiom.http` functions with `Vec[Int]` body types (using `xiom.http.types.HttpResponse`).

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `(url: Str) -> Result[HttpClientResponse, Str]` | Delegates to `xiom.http.http_get` |
| `http_post` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpClientResponse, Str]` | Converts body to Str, delegates |
| `http_put` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpClientResponse, Str]` | Converts body to Str, delegates |
| `http_delete` | `(url: Str) -> Result[HttpClientResponse, Str]` | Delegates to `xiom.http.http_delete` |
| `http_send` | `(request: &HttpRequest, url: &Url) -> Result[HttpClientResponse, Str]` | Serializes request; routes through `http_request` with all declared headers (0.1.8) |

`http_send` work flow (0.1.8):
1. Serialize `Url` to string via internal `url_to_str`
2. Convert `request.body` (`Vec[Int]`) to `Str`
3. Serialize ALL `request.headers` entries to the CRLF blob via
   `xiom.http.headers.http_headers_blob` (a validation failure returns the
   builder's `Err` unchanged)
4. Call `xiom.http.http_request(url, <method verb>, body, blob)` -- the
   declared method is the wire verb (before 0.1.8 PATCH was sent as POST and
   HEAD/OPTIONS as GET, and only Content-Type was consulted, then dropped)

**Surface status (2026-10-16; updated 0.1.10).** Stable for consumers: the five wrappers above, the typed `Err(Str)` taxonomy, response `status` / `body` / `headers` capture, TLS via the libcurl CA bundle, and -- since 0.1.8 -- custom request headers (incl. `Authorization`) via `xiom.http.http_request` (root module) fed by the `xiom.http.headers` builder; `http_send` routes every declared `HttpRequest.headers` entry through that path. Since 0.1.10 the root module also exposes per-call timeouts (`HttpRequestOptions`, `http_request_with_options`, `http_request_bytes_with_options`) and reusable client sessions (`session_new` / `session_request` / `session_request_with_options` / `session_close`). NOT yet in the surface (ROADMAP): streaming bodies, pluggable TLS hook (`xiom.ssl`). `http_post`'s `content_type` argument remains a compatibility no-op; put an explicit `Content-Type` into the header blob instead. Own probes: `tests/probe_client.xi` (refused/malformed deterministic; live + loopback legs SKIP-safe) and `tests/probe_real_libcurl.xi` (0.1.8 live header roundtrip leg, SKIP-safe); `tests/probe_root_module.xi` (0.1.10 timeout/session evidence offline).

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

#### Windows (verified: curl-for-win 8.22.0, `curl-8.22.0_3-win64-mingw`)

```powershell
# Download from https://curl.se/windows/ and extract (e.g. to %TEMP%\kilo\http-libcurl).
# No vcpkg is needed for the verified flow -- see "Build Configuration" below.
```

### Build Configuration (Windows, verified v0.64.2 flow)

The v0.64.2 toolchain runtime ships only `xiom_alloc`, so consumer builds must
compile in `bridge\xiom_http_shims.c` (shipped in 0.1.5). It supplies the other
`xiom_*` helpers the client references -- `xiom_free_ptr`, `xiom_write_byte`,
`xiom_read_byte`, `xiom_str_to_cstr`, `xiom_free_cstr` (plus
`xiom_copy_from_vec`, defined for completeness; today's client does not
reference it) -- and deliberately contains **no libcurl stubs**, so it composes
with the real import library.

```powershell
# 1. lld-link searches for curl.lib; curl-for-win ships lib\libcurl.dll.a.
Copy-Item <kit>\lib\libcurl.dll.a <scratch>\curl.lib

# 2. Build/run the consumer with the shim + real libcurl (--c-source needs an
#    absolute path; clang links from a scratch cwd):
xiom --run app.xi `
    --c-source <abs-installed>\bridge\xiom_http_shims.c `
    --link curl --link-path <scratch>

# 3. Runtime: DLL on PATH + CA bundle for TLS:
$env:PATH = "<kit>\bin;$env:PATH"                    # libcurl-x64.dll
$env:CURL_CA_BUNDLE = "<kit>\bin\curl-ca-bundle.crt"
```

Verified end-to-end on 2026-10-10 (pin v0.64.2, curl-for-win 8.22.0): a
consumer-style link without the shim failed with exactly `xiom_free_cstr`,
`xiom_str_to_cstr`, `xiom_read_byte`, `xiom_write_byte`, and `xiom_free_ptr`
(`curl_easy_*` resolved via `--link curl --link-path`; `xiom_alloc` comes from
the runtime); with the shim, GET `https://example.com/` returned status 200
with a 577-byte body and a POST to a local echo server returned 200 `ok`.

`tests/probe_bridge.c` is **suite-only**: it provides the same `xiom_*` helpers
but also stubs libcurl deterministically so the conformance suite stays offline.
It must never be used in a consumer build (the suite never imports the root
`xiom.http` module, so the suite itself needs no shim at all).

#### Linux / macOS

Link with `--link curl`; the platform linker finds the system libcurl installed
above (`libcurl4-openssl-dev`, `libcurl-devel`, or Homebrew curl). The same
`bridge/xiom_http_shims.c` applies -- the v0.64.2 runtime ships only `xiom_alloc`
on every platform.

### Verifying the Build

```bash
# The 0.1.5 consumer recipe above is the verification: build the consumer with
# the shim + real libcurl and run a GET/POST probe. The offline conformance
# suite (tests/test_conformance.xi) needs no shim and no network.
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
| `curl_slist_append` | Wired (0.1.8) | Custom request headers (`CURLOPT_HTTPHEADER`) via the bridge helpers `xiom_http_headers_build` / `xiom_http_headers_free` (forward-declared real libcurl slist calls; no libcurl headers needed at compile time, no stubs added to the shim). |
| Function pointer callbacks | Not yet wired | `CURLOPT_WRITEFUNCTION` and `CURLOPT_HEADERFUNCTION` are not used; file-based capture via `CURLOPT_WRITEDATA`/`CURLOPT_HEADERDATA` with default `fwrite` callback is used instead. |

### curl Option Constants Used

| Constant | Value | Purpose |
|----------|-------|---------|
| `CURLOPT_URL` | 10002 | Request URL |
| `CURLOPT_FOLLOWLOCATION` | 52 | Follow HTTP redirects |
| `CURLOPT_TIMEOUT_MS` | 155 | Total request timeout in ms (default 30000) |
| `CURLOPT_CONNECTTIMEOUT_MS` | 156 | Connection timeout in ms (default 10000) |
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

---

## 0.1.5 consumer-recipe pass (2026-10-10)

The PULSE consumer lane reported (2026-10-10) that building against the published
`xiom.http` client fails at link with `undefined symbol: curl_easy_*` plus
`xiom_read_byte` unless the consumer supplies a C bridge. This pass ships that
bridge, documents the flow, and proves it end-to-end. No `.xi` source, public
API, or dependency change.

### Shipped artifact

`bridge/xiom_http_shims.c` -- the `xiom_*` helpers only (adapted from the 0.1.4
local pilot `%TEMP%\kilo\http-libcurl\bridge_nocurl.c`): `xiom_free_ptr`,
`xiom_write_byte`, `xiom_read_byte`, `xiom_str_to_cstr`, `xiom_free_cstr`,
`xiom_copy_from_vec`. No libcurl stubs, so it composes with the real import
library; `xiom_alloc` is deliberately not defined (runtime-provided; a
duplicate symbol would fail the link). Every helper is documented in the file
header.

### Evidence (pin v0.64.2, curl-for-win 8.22.0)

- Consumer-style link without the shim (curl linked via `--link curl
  --link-path`) failed with exactly `xiom_free_cstr`, `xiom_str_to_cstr`,
  `xiom_read_byte`, `xiom_write_byte`, `xiom_free_ptr`; `curl_easy_*` resolved,
  `xiom_alloc` came from the runtime. `xiom_copy_from_vec` was not referenced
  by today's client.
- End-to-end pilot (`%TEMP%\kilo\http-consumer-pilot`, vendored 0.1.5 package
  as a consumer source root): with the shipped shim, GET
  `https://example.com/` returned status 200 with a 577-byte body; POST to the
  local echo server returned status 200 body `ok`, and the server captured
  `CL=20;READ=20;BODY=xiom-http-echo-probe;REQLINE=POST /echo HTTP/1.1`.
  Green x2 (one run inline, one following the README recipe verbatim).
- `scripts/port.ps1 -Package xiom-http -TimeoutSec 240`: **42/42 x2** PASS
  (suite unchanged); root probe (`tests/probe_root_module.xi` +
  `tests/probe_bridge.c`) **x2** exit 0 with both `[PASS]` checks.
- Byte-level bracket scan (5 shapes: `Vec<`, `Result<`, `Option<`, `<]`, `>]`)
  of all 14 `.xi` files in the package: **0 hits**.
- Repo-wide scan note (1769 `.xi` files): 34 raw hits, 31 in comments/strings
  and 3 real trap-14 sites outside this package (`xiom-metrics/src/metrics.xi`
  `&mut Vec<UInt8>` parameter types at lines 468/513/528); untouched -- out of
  this porter's scope, flagged for the owning lane.

### 0.1.6 -- consumer-wishlist pass (2026-10-10; `REL-20261010-2002-xvector`)

- `http_status_text` gains **507 -> "Insufficient Storage"** (RFC 6585; the
  xvector server emits it) and the module documents the fallback contract:
  unmapped codes fall back to `"Unknown"` and consumers that need different
  text adapt above the helper, never inside it.
- Suite stays 42 checks (the 507 assert lives in `status text`); the
  `xiom.router` SPEC status line was refreshed to "published 0.1.0" in the
  same pass (registry-served since `eco-v0.1.98`-era adoption).
- Evidence: `port.ps1 -Package xiom-http -TimeoutSec 240` **42/42 x2** on
  v0.64.3; published in `eco-v0.1.133` (sha256 `bb8a5029...`).

### Packaging

`package.xi` -> 0.1.5; `STATUS.json` test fields reset to unknown (nulls) for
the record run; stage/publish unchanged.

---

## 0.1.8 -- custom request headers (2026-10-16)

The ROADMAP 0.1.7 row "Custom request headers (incl. `Authorization`)" --
filed for the xiom.jev live leg (its SPEC section 8 documents the blocker: no
way to attach `Authorization: Bearer` on the wire). Minimal viable pass: one
new pure module, two bridge helpers, one new client entry; the five existing
wrappers and every existing check are unchanged.

### Pure layer: `xiom.http.headers`

`http_headers_blob(Vec[HttpHeader]) -> Result[Str, Str]` renders the frozen
CRLF blob (exact shape and reject rules in the module section above).
Deterministic, pure, no secrets in any output; a full entry never renders
when any pair is invalid.

### C layer: bridge helpers, no libcurl symbols added

- `bridge/xiom_http_shims.c` gains `xiom_http_headers_build` (blob ->
  `curl_slist*` via the real `curl_slist_append`, one node per CRLF-terminated
  line with the separator stripped; NULL for an empty blob or on allocation
  failure, with the partial list freed before returning) and
  `xiom_http_headers_free` (real `curl_slist_free_all`). The two libcurl entry
  points are forward-declared, so the shim still needs no libcurl headers on
  the include path and still defines no libcurl symbols.
- `tests/probe_bridge.c` keeps its own copy plus deterministic
  `curl_slist_append` / `curl_slist_free_all` stubs; the probe copy
  additionally validates each split line ("Name: " required) so a malformed
  blob fails the offline probe instead of slipping through.

### XIOM layer: one new entry

`pub fn http_request(url: Str, method: Str, body: Str, headers: Str) ->
Result[HttpClientResponse, Str]` -- method whitelist
(GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS; anything else returns `Err` before
any FFI call), body for POST/PUT/PATCH, `headers` is the builder blob. Owns
the slist lifecycle: build -> `CURLOPT_HTTPHEADER` -> `curl_easy_cleanup` ->
free (libcurl's required order). An empty blob keeps the exact wrapper
behavior (no `CURLOPT_HTTPHEADER` call). `src/client.xi` `http_send` now routes
every request through this entry, so ALL declared `HttpRequest.headers`
entries reach the wire (the pre-0.1.8 path consulted Content-Type only and
then dropped it); PATCH/HEAD/OPTIONS keep their declared verbs instead of
being sent as POST/GET. No new contract clauses: `http_request` carries the
same `requires` shape as the public wrappers, and the new private helper
(`cleanup_http_request`) is a pure FFI-lifecycle cleanup.

### Tests and evidence (compiler v0.64.5, 2026-10-16)

- `tests/test_conformance.xi`: **52/52 x2** via `port.ps1 -Package xiom-http
  -TimeoutSec 180` (program_exit=0 both runs). The 10 new checks pin the
  builder: empty/single/order+duplicates/`Authorization: Bearer`/empty
  value/token-name-edge/whitespace goldens, invalid-name and invalid-value
  (CR/LF/NUL) reject paths with exact error strings, and a blob ->
  `http_parse_headers` roundtrip. All 42 pre-existing checks are untouched
  and green.
- `tests/probe_root_module.xi` (offline, `tests/probe_bridge.c`) x2 exit 0:
  5 `[PASS]` checks -- the original two plus unsupported-method rejection,
  the header path through the deterministic slist stubs, and the
  empty-blob wrapper path.
- `tests/probe_real_libcurl.xi` x2 exit 0 against curl-for-win 8.22.0 with
  `tests/echo_headers_server.ps1` running: example.com GET 200 with a
  577-byte body, and the loopback header roundtrip (`X-Xiom-Probe` +
  `Authorization: Bearer ...` reflected by the echo endpoint) -- the jev
  Authorization shape proven on the wire through real libcurl.
- `xiom --check` green for `probe_all_modules.xi` (now covering
  `xiom.http.headers`), `probe_client.xi`, `probe_root_module.xi`, and
  `probe_real_libcurl.xi`.

### Consumer note (xiom.jev live leg)

`system_one` can now build `Authorization: Bearer <api_key>` (plus
`Content-Type: application/json`) with `xiom.http.headers.http_headers_blob`
and POST it through `xiom.http.http_request(endpoint, "POST", body, blob)` --
the 401-until-headers note in jev SPEC section 8 can be retired once jev
switches its transport call to this entry.

---

## 0.1.9 -- raw-bytes request bodies (2026-10-17)

The Str-body client entries re-encode a `Str` via `encoding.utf8_encode` and
`xiom_str_to_cstr` before handing it to libcurl, corrupting binary payloads
(surfaced by the xiom.jev S8 gzip frame). This pass adds a bounded second
path; the existing Str-body entries are untouched and byte-identical.

### New entry

`xiom.http.http_request_bytes(url, method, body: Vec[UInt8], content_length:
Int, headers: Str) -> Result[HttpClientResponse, HttpBytesRequestError]`.

- `body` is the exact byte span; `content_length` is the caller-declared
  Content-Length. Validation runs before any FFI call through
  `xiom.http.body.http_bytes_body`.
- The vector's data pointer goes straight to `CURLOPT_POSTFIELDS`, and
  `CURLOPT_POSTFIELDSIZE` is set to `content_length`. libcurl therefore reads
  exactly those bytes: no UTF-8 conversion, no cstr conversion, no NUL
  truncation. A frame containing `0x00` and `0x80..0xFF` reaches the transport
  unchanged.
- Methods and the body-carrying set are the same as `http_request`
  (POST/PUT/PATCH send a body; GET/DELETE/HEAD/OPTIONS ignore it but still
  validate the length).
- `headers` is the unchanged `http_headers_blob` CRLF blob, so callers set
  `Content-Type` / `Content-Encoding` themselves; libcurl forwards the lines
  verbatim.
- The transport internals shared with `http_request` were factored into
  `setup_request_headers` / `perform_request_common`; `http_request`'s
  observable behavior and error text are unchanged.

### Typed errors

`HttpBytesRequestError = enum { BodyLengthMismatch(declared, actual);
BodyLengthNegative(declared); UnsupportedMethod(method); Transport(message); }`.

`BodyLengthMismatch` / `BodyLengthNegative` / `UnsupportedMethod` are returned
before any FFI call; `Transport` wraps the existing libcurl error text. The
typed variants are the primary contract; `xiom.http.body.http_body_error_message`
renders deterministic text where a string is needed.

### Evidence (compiler v0.64.6)

- `tests/test_conformance.xi`: **55/55 x2** via
  `port.ps1 -Package xiom.http -TimeoutSec 240` (program_exit=0 both runs).
  Three new checks: a gzip-like frame with `0x00`/`0x7F`/`0x80`/`0x81`/`0xFE`/
  `0xFF` is preserved byte-for-byte through `http_bytes_body_wire`; the
  mismatch and negative-length typed variants with their golden messages.
- `tests/probe_root_module.xi` + `tests/probe_bridge.c` x2 exit 0, now with
  seven `[PASS]` checks. The bridge stub snapshots the bytes at
  `CURLOPT_POSTFIELDSIZE` (libcurl's exact-read contract) and exposes
  `xiom_probe_last_body_len` / `xiom_probe_last_body_byte`; the new offline leg
  sends the same binary frame through `http_request_bytes` to a closed port and
  asserts every byte is exact, plus the typed `LengthMismatch(8, 9)` rejection
  before any FFI call.
- No bridge production change was needed: `Vec[UInt8].as_mut_ptr()` already
  supplies a raw `*UInt8` that stays alive through `curl_easy_perform`, so the
  cstr/FFI seam does not obstruct exact binary transmission.


---

## 0.1.10 -- client transport: per-call timeouts + sessions (2026-10-22)

### Per-call timeouts

`xiom.http.options` is the pure half. `HttpRequestOptions` has `connect_ms`
and `total_ms`; `0` resolves to the library defaults (10000 / 30000 ms).
`validate_request_options(&opts)` returns
`HttpRequestOptionError.ConnectTimeoutNegative` /
`TotalTimeoutNegative` for negative values and borrows the options.

`http_request_with_options` and `http_request_bytes_with_options` validate
before any FFI call, then pass the effective values through
`setup_common_options` to `CURLOPT_CONNECTTIMEOUT_MS` (156) and
`CURLOPT_TIMEOUT_MS` (155). Every pre-0.1.10 entry uses
`http_request_options_default()` and therefore keeps the exact 10 s / 30 s
behavior (now expressed in milliseconds).

Typed outcomes:

- `HttpOptionsRequestError = { ConnectTimeoutNegative(value);
  TotalTimeoutNegative(value); UnsupportedMethod(method); Transport(message); }`
- `HttpBytesRequestError` keeps its 0.1.9 variants and adds
  `InvalidConnectTimeout(value)` / `InvalidTotalTimeout(value)` for the
  bytes-with-options entry.

### Sessions and connection reuse

`HttpClientSession` wraps one `curl_easy_init` handle.
`session_new()` allocates it, `session_request(&session, ...)` (and the
with-options form) performs one transfer on it, and `session_close(session)`
cleans it up exactly once. Per call the session:

1. resets `CURLOPT_POST`, `CURLOPT_CUSTOMREQUEST`, `CURLOPT_POSTFIELDS`, and
   `CURLOPT_POSTFIELDSIZE` so request state does not leak between calls;
2. re-applies URL, redirects, timeouts, encoding, user agent, and buffer size;
3. installs the header slist and body, performs, captures status/body/headers;
4. clears `CURLOPT_HTTPHEADER` and frees the slist plus C-string copies.

libcurl retains its connection cache on the easy handle, so sequential
requests to the same origin reuse the established connection. The handle is
kept open on both success and transport failure; only `session_close` releases
it. The one-shot API remains one-handle-per-call.

### Evidence (compiler v0.64.9)

- `tests/test_conformance.xi`: **60/60 x2** via
  `port.ps1 -Package xiom.http -TimeoutSec 300`; five new pure checks cover
  defaults, the zero sentinel, custom effective values, and both negative
  variants with golden messages.
- `tests/probe_root_module.xi` + `tests/probe_bridge.c`: 12 `[PASS]` checks.
  The bridge counts `curl_easy_init` / `curl_easy_cleanup` and snapshots the
  `CURLOPT_TIMEOUT_MS` / `CURLOPT_CONNECTTIMEOUT_MS` values. The probe proves
  two session requests create no second handle and clean up only at
  `session_close`, custom timeouts 1234 / 5678 reach the bridge, defaults are
  10000 / 30000, and invalid timeouts are rejected before any handle exists.
- Compiler defect v0.64.9: direct `Err(Enum.Variant(..))` patterns were
  miscompiled (the first `Err` arm won). Fixed in v0.65.2; the 0.1.10
  two-level workaround is retired in the tree. `docs/COMPILER-DEFECTS.md`
  records the history; `docs/probe_match_result_enum_defect.xi` is the
  minimized reproducer/regression witness.

### Deliberately not in 0.1.10

Streaming request/response bodies and a pluggable TLS hook remain unpinned on
the ROADMAP; no partial API was added.
