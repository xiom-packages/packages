<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.http

HTTP/1.1 types, request/response parsers, client helpers, and a (stub) server shell.

## Consumer quickstart (3 lines)

```xiom
use xiom.http.types;    // HttpRequest, HttpResponse, HttpHeaders, HttpMethod, HttpVersion, method_from_str, version_from_str
use xiom.http.parser;   // http_parse_request, http_parse_response, http_parse_headers
// let req = http_parse_request("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n");
```

Since 0.1.1 `xiom.http.parser` imports `xiom.http.types` itself, so a consumer that
imports only the parser module compiles cleanly (0.1.0 shipped 19 T001s in that shape).

## Modules

| Module | Contents |
|---|---|
| `xiom.http.types` | `HttpHeader`, `HttpHeaders`, `HttpRequest`, `HttpResponse`, `HttpMethod`, `HttpVersion`, `method_from_str`, `version_from_str` |
| `xiom.http.parser` | `http_parse_request`, `http_parse_response`, `http_parse_headers`, `HttpParseError` |
| `xiom.http.status` | status-code helpers |
| `xiom.http.mime` | MIME mapping |
| `xiom.http.url` | URL parsing |
| `xiom.http.cookie` | cookie helpers (see also the `xiom.cookie` package) |
| `xiom.http.client` | client-side helpers |
| `xiom.http.server` | **stub** (see below) |
| `xiom.http.demo` | demo helpers |

## Server status (0.1.1): STUB

`src/server.xi` is data + stubs, not a server: `server_new(addr, port)` constructs
`HttpServer { addr, port, running: false }` (no socket/bind); `server_listen` and
`server_handle` unconditionally return
`Err("HTTP server ...: TCP transport layer not yet available (requires Layer 3.1)")`;
`server_close` takes the struct by value and its `running = false` write is not observable
to the caller. There is no accept loop, no routing, no handler registration. Consumers
own their transport today; `xiom.router` (planned) will provide route matching.

## Contracts and tests

- `http_parse_request` / `http_parse_response`: `requires: input.len() > 0` (do not call
  with an empty string; an empty input traps as a contract violation).
- Parser KATs (request line, POST body, response line, header parsing, malformed header)
  live in `tests/test_conformance.xi` (40 checks) — added in 0.1.1 after a consumer-only
  defect (missing import + bare `&mut Int` cursor) shipped green on 0.1.0.
