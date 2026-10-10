<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.http

HTTP/1.1 types, request/response parsers, client helpers, and a (stub) server shell.

> **Status:** `stable` -- 0.1.4 published in `eco-v0.1.120` (printable ASCII
> renders as characters; variadic LONG options pass values to libcurl). 0.1.5
> ships `bridge/xiom_http_shims.c` and the consumer client build recipe below,
> verified end-to-end against real libcurl 8.22.0 (GET `example.com` -> 200,
> echo POST -> 200). Suite **42/42 x2** + root probe x2 on the pin (v0.64.2).
> Published in `eco-v0.1.125` (sha256 `2d5592af...`).

## Consumer quickstart (3 lines)

```xiom
use xiom.http.types;    // HttpRequest, HttpResponse, HttpHeaders, HttpMethod, HttpVersion, method_from_str, version_from_str
use xiom.http.parser;   // http_parse_request, http_parse_response, http_parse_headers
// let req = http_parse_request("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n");
```

Since 0.1.1 `xiom.http.parser` imports `xiom.http.types` itself, so a consumer that
imports only the parser module compiles cleanly (0.1.0 shipped 19 T001s in that shape).

## Consumer client build recipe (Windows; verified v0.64.2 + curl-for-win 8.22.0)

The v0.64.2 runtime ships only `xiom_alloc`, so the client's other `xiom_*` bridge
symbols come from the shipped shim (no libcurl stubs -- it composes with real curl).
lld-link searches for `curl.lib`, while curl-for-win ships `lib\libcurl.dll.a` -- copy
it to a scratch dir as `curl.lib`:

    xiom --run app.xi --c-source <installed>\bridge\xiom_http_shims.c --link curl --link-path <scratch-with-curl.lib>

Put the kit's `bin\libcurl-x64.dll` on `PATH` at runtime and set
`CURL_CA_BUNDLE=<kit>\bin\curl-ca-bundle.crt` for TLS. `<installed>` is the installed
package dir (e.g. `%LOCALAPPDATA%\xiom\packages\xiom-http-0.1.5\xiom-http`); pass it
absolute -- clang links from a scratch cwd.

```xiom
use xiom.http;
let r = http_get("https://example.com/");                        // Ok => 2xx + non-empty body
let p = http_post("http://127.0.0.1:18094/echo", "hi", "text/plain");
```

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

## 0.1.4 changes

Two live defects from the 0.1.3 line are fixed (public API and dependencies unchanged):

- **Character rendering**: `byte_to_char`/`char_to_str` in `http.xi`, `src/url.xi`,
  `src/client.xi`, and `src/types.xi` now render printable ASCII as the actual
  character (`"A"` for byte 65) via `xiom.convert.tostring.to_string_char` instead of
  the decimal code (`"65"`); `~ | { }` are no longer flattened to `"?"`. Non-printable
  fallbacks and the 0/9/10/13/32 special mappings are unchanged.
- **libcurl LONG options**: `make_ptr_value` (a heap buffer whose pointer libcurl
  stored as the option value, breaking timeouts/POST size and leaking) is now
  `make_long_value`, passing the long value itself per libcurl's variadic ABI.

See `SPEC.md` -> "0.1.4 fix pass" for the clause re-pins and the probe-bridge changes.

## 0.1.5 changes

Consumer-recipe pass; no source or API change. Ships `bridge/xiom_http_shims.c`
(the `xiom_*` runtime helpers, **no** libcurl stubs) plus the verified build
recipe above; `tests/probe_bridge.c` stays suite-only (it also stubs curl
offline). The consumer-style link without the shim fails on exactly
`xiom_free_ptr`, `xiom_write_byte`, `xiom_read_byte`, `xiom_str_to_cstr`, and
`xiom_free_cstr` (`xiom_alloc` ships in the runtime); `curl_easy_*` resolve via
`--link curl --link-path`.

## Contracts and tests

- `http_parse_request` / `http_parse_response`: `requires: input.len() > 0` (do not call
  with an empty string; an empty input traps as a contract violation).
- Parser KATs (request line, POST body, response line, header parsing, malformed header)
  live in `tests/test_conformance.xi` (42 checks) — added in 0.1.1 after a consumer-only
  defect (missing import + bare `&mut Int` cursor) shipped green on 0.1.0; the 0.1.4
  checks pin printable-ASCII rendering in `src/url.xi` and `src/types.xi`.
