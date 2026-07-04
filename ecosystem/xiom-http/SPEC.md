# xiom-http — XIOM HTTP Library Specification

## Overview

`xiom-http` is the Layer 3.2 ecosystem package providing HTTP protocol support for XIOM. It covers type definitions, message parsing, status codes, MIME types, URL manipulation, cookies, and client/server stubs.

## Modules

### `xiom.http.types` (`src/types.xi`)

Core HTTP protocol data types and serialization.

**Enums:**
- `HttpMethod` — GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
- `HttpVersion` — HTTP09, HTTP10, HTTP11, HTTP20

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

Uses `@axiom_str_len` and `@axiom_char_at` intrinsics for character-by-character parsing. Position-counters track progress through the input.

---

### `xiom.http.status` (`src/status.xi`)

HTTP status code classification and reason phrases.

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_status_text` | `(code: Int) -> Str` | Reason phrase (e.g. 200→"OK") |
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
| `mime_from_ext` | `(ext: Str) -> MimeType` | .html→text/html, .json→application/json, etc. |
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

### `xiom.http.client` (`src/client.xi`)

HTTP client stubs. These return errors until Layer 3.1 (TCP) is available.

| Function | Signature | Description |
|----------|-----------|-------------|
| `http_get` | `(url: Str) -> Result[HttpResponse, Str]` | GET request (stub) |
| `http_post` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]` | POST request (stub) |
| `http_put` | `(url: Str, body: Vec[Int], content_type: Str) -> Result[HttpResponse, Str]` | PUT request (stub) |
| `http_delete` | `(url: Str) -> Result[HttpResponse, Str]` | DELETE request (stub) |
| `http_send` | `(request: &HttpRequest, url: &Url) -> Result[HttpResponse, Str]` | Main send entry point (stub) |

---

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

## Design Notes

### String Parsing
Without a full stdlib, string manipulation uses `@axiom_str_len` for length queries and `@axiom_char_at` for character access. All parsing maintains position counters and builds substrings via character-by-character concatenation.

### `to_str` Serialization
Both `HttpRequest.to_str()` and `HttpResponse.to_str()` produce valid HTTP/1.1 wire format with `\r\n` line endings. Integer-to-string conversion is done via manual digit extraction (no `sprintf`-like functionality).

### Future Integration
Client and server stubs expect integration with `xiom.net.tcp` (Layer 3.1). Once available, `http_send` will:
1. Open a TCP connection to `url.host:url.port`
2. Serialize the request via `request.to_str()`
3. Send and receive raw bytes
4. Parse the response via `http_parse_response`
