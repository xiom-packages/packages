# xiom-rest -- Specification

> **Status: v0.1.0 implemented.** Core types, client/request builders, libcurl FFI declarations, convenience HTTP methods, response helpers, and error constructors are implemented in `rest.xi`. Full libcurl transport integration and resource routing layer are planned for future versions.

## Overview

`xiom-rest` layers resource-oriented REST conventions on top of the `xiom-http` transport. It provides a typed REST client backed by libcurl, with request/response types, URL construction, method dispatch, status classification, and structured error types. Future versions will add resource routing, pagination, filtering, sorting, versioning, content negotiation, and OpenAPI generation.

## Module

- **Module:** `xiom.rest`
- **Version:** 0.1.0
- **Dependencies:** `xiom.string`, `xiom.convert`, `xiom.ptr`

---

## Implemented Types (v0.1.0)

### `RestMethod` (enum)

```xiom
pub enum RestMethod {
  GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
} derive[Clone]
```

### `RestClient`

```xiom
pub type RestClient = {
  base_url: Str;
  timeout_ms: Int;
  follow_redirects: Bool;
  default_headers: Vec[RestHeader];
} derive[Clone]
```

### `RestResponse`

```xiom
pub type RestResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]
```

### `RestHeader`

```xiom
pub type RestHeader = {
  name: Str;
  value: Str;
} derive[Clone]
```

### `RestRequest`

```xiom
pub type RestRequest = {
  method: RestMethod;
  path: Str;
  query_params: Vec[RestQueryParam];
  headers: Vec[RestHeader];
  body: Str;
} derive[Clone]
```

### `RestQueryParam`

```xiom
pub type RestQueryParam = {
  key: Str;
  value: Str;
} derive[Clone]
```

### `RestError`

```xiom
pub type RestError = {
  code: Str;
  status: Int;
  message: Str;
} derive[Clone]
```

---

## Implemented API (v0.1.0)

### Client Builder

| Function | Signature | Description |
|----------|-----------|-------------|
| `client_new` | `(base_url: Str) -> RestClient` | Create client with defaults (30s timeout, follow redirects) |
| `client_set_timeout` | `(client: &mut RestClient, ms: Int)` | Set request timeout in ms |
| `client_set_follow_redirects` | `(client: &mut RestClient, follow: Bool)` | Toggle redirect following |
| `client_add_header` | `(client: &mut RestClient, name: Str, value: Str)` | Add default header |
| `client_remove_header` | `(client: &mut RestClient, name: Str) -> Bool` | Remove default header by name |
| `client_get_default_header` | `(client: &RestClient, name: Str) -> Option[Str]` | Look up default header value |

### Request Builder

| Function | Signature | Description |
|----------|-----------|-------------|
| `request_new` | `(method: RestMethod, path: Str) -> RestRequest` | Create request |
| `request_add_header` | `(req: &mut RestRequest, name: Str, value: Str)` | Add per-request header |
| `request_add_query_param` | `(req: &mut RestRequest, key: Str, value: Str)` | Add query parameter |
| `request_set_body` | `(req: &mut RestRequest, body: Str)` | Set request body |
| `request_build_url` | `(req: &RestRequest, base: Str) -> Str` | Construct full URL (path joining, query string) |

### Method Conversion

| Function | Signature | Description |
|----------|-----------|-------------|
| `method_to_str` | `(method: RestMethod) -> Str` | GET -> "GET", etc. |
| `method_from_str` | `(s: Str) -> RestMethod` | "POST" -> POST, unknown -> GET |

### Convenience Methods

| Function | Signature |
|----------|-----------|
| `client_get` | `(client: &RestClient, path: Str) -> Result[RestResponse, Str]` |
| `client_post` | `(client: &RestClient, path: Str, body: Str) -> Result[RestResponse, Str]` |
| `client_put` | `(client: &RestClient, path: Str, body: Str) -> Result[RestResponse, Str]` |
| `client_delete` | `(client: &RestClient, path: Str) -> Result[RestResponse, Str]` |
| `client_patch` | `(client: &RestClient, path: Str, body: Str) -> Result[RestResponse, Str]` |

All delegate to `client_execute` which initializes libcurl, sets URL, and returns an Ok(200) stub.

### Response Classification

| Function | Signature | Description |
|----------|-----------|-------------|
| `response_is_success` | `(resp: &RestResponse) -> Bool` | 200-299 |
| `response_is_client_error` | `(resp: &RestResponse) -> Bool` | 400-499 |
| `response_is_server_error` | `(resp: &RestResponse) -> Bool` | 500-599 |
| `response_status_category` | `(resp: &RestResponse) -> Int` | 200, 400, 500, etc. |

### Error Constructors

| Function | Signature | Code | Status |
|----------|-----------|------|--------|
| `error_not_found` | `(message: Str) -> RestError` | NOT_FOUND | 404 |
| `error_bad_request` | `(message: Str) -> RestError` | BAD_REQUEST | 400 |
| `error_internal` | `(message: Str) -> RestError` | INTERNAL | 500 |
| `error_unauthorized` | `(message: Str) -> RestError` | UNAUTHORIZED | 401 |
| `error_to_response` | `(err: &RestError) -> RestResponse` | -- | Preserves status |

---

## libcurl FFI Layer (v0.1.0)

### Declared `extern "C"` Functions

```xiom
extern "C" {
  fn curl_easy_init() -> *UInt8;
  fn curl_easy_setopt(handle: *UInt8, option: Int, value: *UInt8) -> Int;
  fn curl_easy_perform(handle: *UInt8) -> Int;
  fn curl_easy_getinfo(handle: *UInt8, info: Int, arg: *UInt8) -> Int;
  fn curl_easy_cleanup(handle: *UInt8);
  fn curl_easy_strerror(code: Int) -> *UInt8;
  fn curl_slist_append_all(headers: *UInt8, header: *UInt8) -> *UInt8;
  fn curl_slist_free_all(list: *UInt8);
}
```

### Declared XIOM FFI Bridge

```xiom
extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
}
```

### CURL Option Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `CURLOPT_URL` | 10002 | Request URL |
| `CURLOPT_FOLLOWLOCATION` | 52 | Follow HTTP redirects |
| `CURLOPT_TIMEOUT` | 13 | Total request timeout |
| `CURLOPT_CONNECTTIMEOUT` | 78 | Connection timeout |
| `CURLOPT_POST` | 47 | Enable POST method |
| `CURLOPT_POSTFIELDS` | 10015 | POST body data |
| `CURLOPT_POSTFIELDSIZE` | 60 | POST body size |
| `CURLOPT_CUSTOMREQUEST` | 10036 | Custom method (PUT, DELETE, etc.) |
| `CURLOPT_SSL_VERIFYPEER` | 64 | Verify TLS certificate |
| `CURLOPT_SSL_VERIFYHOST` | 81 | Verify TLS hostname |
| `CURLOPT_USERAGENT` | 10018 | User-Agent header |
| `CURLOPT_ACCEPT_ENCODING` | 10102 | Accept-Encoding header |

---

## Planned Modules (Future Versions)

The modules documented below are design-stage -- specified in [ARCHITECTURE.md](ARCHITECTURE.md) but not yet built.

| Module | File | Status |
|--------|------|--------|
| Resource builder | `src/resource.xi` | Planned |
| Router | `src/router.xi` | Planned |
| Route builder | `src/route_builder.xi` | Planned |
| Versioning | `src/versioning.xi` | Planned |
| Pagination | `src/pagination.xi` | Planned |
| Filtering | `src/filtering.xi` | Planned |
| Sorting | `src/sorting.xi` | Planned |
| Content negotiation | `src/negotiation.xi` | Planned |
| Error mapping | `src/errors.xi` | Planned |
| HATEOAS links | `src/links.xi` | Planned |
| OpenAPI generation | `src/openapi.xi` | Planned |
| Response envelopes | `src/response_shape.xi` | Planned |
| Test harness | `src/testing/` | Planned |

---

## Design Decisions

### libcurl as Client Transport

`xiom-rest` declares its own `extern "C"` libcurl FFI block rather than delegating to `xiom-http`. This keeps the REST client self-contained and allows it to evolve independently. The `curl_slist_append_all` / `curl_slist_free_all` functions are declared for future custom header injection support.

### Stub Transport

`client_execute` in v0.1.0 initializes a curl handle but returns a stub `Ok(200)` response without performing actual HTTP requests. Full transport integration is planned for v0.2.0 following the same temp-file response capture strategy used by `xiom-http`.

### Method Enum

All seven standard HTTP methods are represented in the `RestMethod` enum with string conversion helpers. Unknown strings default to GET to fail safely.

### Error Model

`RestError` uses a `code: Str` field for machine-readable error codes (NOT_FOUND, BAD_REQUEST, etc.) alongside an HTTP `status: Int` and a human-readable `message: Str`. This maps cleanly to RFC 7807 Problem Details when needed.

### URL Construction

`request_build_url` handles path joining (trailing/leading slash normalization) and query parameter serialization. It is pure XIOM with no external dependencies.
