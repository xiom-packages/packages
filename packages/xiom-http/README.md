<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# xiom.http

HTTP/1.1 types, request/response parsers, client helpers, and a (stub) server shell.

> **Status:** `stable` -- 0.1.4 published in `eco-v0.1.120` (printable ASCII
> renders as characters; variadic LONG options pass values to libcurl). 0.1.5
> ships `bridge/xiom_http_shims.c` and the consumer client build recipe below,
> verified end-to-end against real libcurl 8.22.0 (GET `example.com` -> 200,
> echo POST -> 200). Suite **42/42 x2** + root probe x2 on the pin (v0.64.2).
> Published in `eco-v0.1.125` (sha256 `2d5592af...`). 0.1.6: `eco-v0.1.133`
> (sha256 `bb8a5029...`) adds 507 Insufficient Storage with the documented
> `Unknown` fallback contract. 0.1.7: `eco-v0.1.189`
> (sha256 `b65c44d2...`) client surface stabilisation (probe + docs). 0.1.8:
> custom request headers (`xiom.http.headers.http_headers_blob` +
> `xiom.http.http_request`; `Authorization: Bearer` proven on the wire via the
> shim's curl_slist path). Suite **52/52 x2** on v0.64.6. Published as a
> single tag `xiom-http/v0.1.8` (sha256 `0e707f55...`, 2026-10-16). 0.1.9
> adds the binary-safe body path: `xiom.http.body` + `http_request_bytes`
> transmit `Vec[UInt8]` bytes exactly (no UTF-8 re-encode, NUL-safe) with a
> typed `HttpBytesRequestError`; the Str-body API is unchanged. Suite
> **55/55 x2** on v0.64.6. Published in `eco-v0.1.195` (sha256
> `f7b0c30f...`, 2026-10-17).

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
symbols come from the shipped shim (no libcurl stubs -- it composes with real curl;
0.1.8 adds the header-list helpers, which call the real `curl_slist_append` /
`curl_slist_free_all` and still define no libcurl symbols).
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

## Client surface -- stability + limits

The consumer-facing client surface is the `xiom.http.client` module (method
wrappers over the libcurl bridge; adopting it needs no server-module contact).

Stable today: `http_get` / `http_post` / `http_put` / `http_delete` and the
method-routing `http_send`; **custom request headers since 0.1.8** (incl.
`Authorization: Bearer ...`): build the header list with
`xiom.http.headers.http_headers_blob` and send it through
`xiom.http.http_request`; `http_send` now forwards every declared
`HttpRequest.headers` entry (pre-0.1.8 it consulted Content-Type only and then
dropped it); **binary request bodies since 0.1.9** via
`xiom.http.http_request_bytes(url, method, Vec[UInt8], content_length, blob)`
with typed `HttpBytesRequestError`; typed `Err(Str)` failure taxonomy for the
Str-body wrappers; response `status` / `body` / `headers` capture; TLS through
the libcurl CA bundle (set `CURL_CA_BUNDLE`, recipe above).

```xiom
use xiom.http;
use xiom.http.headers;
use xiom.http.types;
var pairs: Vec[HttpHeader] = Vec[HttpHeader].new();
pairs.push(HttpHeader{ name: "Authorization", value: "Bearer <key>" });
pairs.push(HttpHeader{ name: "Content-Type", value: "application/json" });
match http_headers_blob(pairs) {
  Ok(blob) => { /* http_request(url, "POST", body, blob) */ },
  Err(e) => { /* invalid name or value; fix the pair, nothing was sent */ },
};
```

Binary bodies (0.1.9) use `Vec[UInt8]` plus an explicit Content-Length:

```xiom
use xiom.http;                 // http_request_bytes, HttpBytesRequestError
var gz: Vec[UInt8] = /* exact gzip bytes */;
match http_request_bytes(url, "POST", gz, gz.len(), blob) {
  Ok(resp) => { /* bytes were sent exactly; no UTF-8 re-encode */ },
  Err(HttpBytesRequestError.BodyLengthMismatch(d, a)) => { /* d != a */ },
  Err(HttpBytesRequestError.Transport(msg)) => { /* libcurl failure */ },
  Err(_) => { /* negative length or unsupported method */ },
};
```

The bytes go to libcurl through `CURLOPT_POSTFIELDS`/`CURLOPT_POSTFIELDSIZE`
without a cstr conversion, so `0x00` and `0x80..0xFF` survive. Headers are the
same CRLF blob; set `Content-Encoding` / `Content-Type` there yourself.

Not yet in the surface (tracked in `ROADMAP.md`): keep-alive control,
per-call timeouts, streaming request/response bodies, and a pluggable TLS
hook (arrives with `xiom.ssl`). The libcurl bridge is the transport until
then. `http_post`'s `content_type` parameter remains a compatibility no-op
and `client.http_put` takes no content type -- put an explicit `Content-Type`
into the header blob when the server needs one.

Evidence: `tests/probe_client.xi` -- refused-taxonomy + malformed-url are
offline-deterministic; the live GET and loopback POST legs print `[SKIP]`
(rc 0) when the network/endpoint is absent. `tests/probe_real_libcurl.xi`
adds the 0.1.8 live header roundtrip leg against the loopback echo endpoint
`tests/echo_headers_server.ps1` (SKIP-safe); `tests/probe_root_module.xi`
drives the header path offline through the deterministic probe bridge.

## Modules

| Module | Contents |
|---|---|
| `xiom.http.types` | `HttpHeader`, `HttpHeaders`, `HttpRequest`, `HttpResponse`, `HttpMethod`, `HttpVersion`, `method_from_str`, `version_from_str` |
| `xiom.http.parser` | `http_parse_request`, `http_parse_response`, `http_parse_headers`, `HttpParseError` |
| `xiom.http.status` | status-code helpers |
| `xiom.http.mime` | MIME mapping |
| `xiom.http.url` | URL parsing |
| `xiom.http.cookie` | cookie helpers (see also the `xiom.cookie` package) |
| `xiom.http.body` | raw-bytes body validation + exact wire copy (`http_bytes_body`) |
| `xiom.http.headers` | header-list builder for custom request headers (`http_headers_blob`) |
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

## 0.1.8 changes

Custom request headers (incl. `Authorization`), the xiom.jev live-leg blocker
(jev SPEC section 8):

- New pure module `xiom.http.headers`: `http_headers_blob(Vec[HttpHeader]) ->
  Result[Str, Str]` renders the frozen CRLF wire blob ("Name: value\r\n" per
  pair, declaration order, duplicates kept, empty input -> `Ok("")`). Names
  must be RFC 7230 tokens; values reject CR/LF/other control characters (HTAB
  allowed) so header injection cannot be built; values never appear in error
  text and nothing is logged.
- `bridge/xiom_http_shims.c` gains `xiom_http_headers_build` /
  `xiom_http_headers_free` (real `curl_slist_append` / `curl_slist_free_all`
  via forward declarations -- no libcurl headers needed, no stubs added). The
  list is freed after `curl_easy_cleanup`, the order libcurl requires.
- New client entry `xiom.http.http_request(url, method, body, headers)`
  (methods GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS; body for POST/PUT/PATCH;
  `headers` is the blob). The five existing wrappers are unchanged;
  `http_send` now routes the whole request through it, so every declared
  `HttpRequest.headers` entry reaches the wire (and PATCH/HEAD/OPTIONS keep
  their own request verbs instead of being sent as GET/POST).
- Suite grows 42 -> 52 checks (10 builder goldens including the reject paths
  and a blob -> `http_parse_headers` roundtrip); `probe_root_module.xi` drives
  the header path offline; `probe_real_libcurl.xi` proves the live header
  roundtrip against `tests/echo_headers_server.ps1` (SKIP-safe).

## 0.1.9 changes

Binary-safe request bodies (gzip frames, images, protobuf, ...). The Str-body
entries are unchanged.

- New pure module `xiom.http.body`: `http_bytes_body(bytes, content_length)`
  validates a `Vec[UInt8]` span against an explicit Content-Length and returns
  the typed `HttpBodyError.LengthMismatch` / `NegativeLength` variants;
  `http_bytes_body_wire` copies the bytes exactly (no conversion).
- New root entry `http_request_bytes(url, method, body, content_length,
  headers) -> Result[HttpClientResponse, HttpBytesRequestError]`. The vector
  pointer goes to `CURLOPT_POSTFIELDS` with `CURLOPT_POSTFIELDSIZE =
  content_length`, so libcurl reads exactly those bytes: NUL-safe, high-byte-
  safe, no `xiom_str_to_cstr`. `Transport` wraps the existing libcurl error
  text; the other variants are returned before any FFI call.
- `http_request`'s header/perform internals were factored into
  `setup_request_headers` / `perform_request_common`; its behavior and error
  text are unchanged.
- Suite grows 52 -> 55 checks (binary preservation, mismatch, negative
  length); the offline `probe_root_module` bridge now snapshots
  POSTFIELDS/POSTFIELDSIZE and verifies a `0x00 + 0x80..0xFF` frame byte-for-
  byte through `http_request_bytes` (7 `[PASS]` checks x2).

## Contracts and tests

- `http_parse_request` / `http_parse_response`: `requires: input.len() > 0` (do not call
  with an empty string; an empty input traps as a contract violation).
- Parser KATs (request line, POST body, response line, header parsing, malformed header)
  live in `tests/test_conformance.xi` (55 checks) -- added in 0.1.1 after a consumer-only
  defect (missing import + bare `&mut Int` cursor) shipped green on 0.1.0; the 0.1.4
  checks pin printable-ASCII rendering in `src/url.xi` and `src/types.xi`; the 0.1.8
  checks pin the header-list builder in `src/headers.xi` (goldens, reject rules,
  parser roundtrip).
