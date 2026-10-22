# xiom.http ROADMAP

## v0.1.10 -- Client transport: timeouts + sessions (shipped 2026-10-22)
- [x] Keep-alive / idle connection reuse via an explicit `HttpClientSession` (`session_new` / `session_request` / `session_request_with_options` / `session_close`): one easy handle per session, so libcurl reuses connections to the same origin; one-shot API unchanged
- [x] Per-call timeouts (connect + total) through `xiom.http.options.HttpRequestOptions` (`connect_ms` / `total_ms`, 0 = default) and `http_request_with_options` / `http_request_bytes_with_options`; typed negative-value errors; values mapped to `CURLOPT_CONNECTTIMEOUT_MS` / `CURLOPT_TIMEOUT_MS`
- [x] Offline evidence: suite 60/60 x2; probe bridge counts handle init/cleanup and snapshots timeout options (12 `[PASS]` checks)
- [ ] Streaming request/response bodies -- deliberately skipped, not pinned
- [ ] Pluggable TLS hook (compose with `xiom.ssl` when it lands) -- deliberately skipped, not pinned
- Compiler note: v0.64.9 miscompiles direct `Err(Enum.Variant(..))` patterns; see `docs/COMPILER-DEFECTS.md`

## v0.1.8 -- Custom request headers (shipped 2026-10-16)
- [x] Custom request headers (incl. `Authorization`) -- required by the xiom.jev live leg (M1 finding 2026-10-16). Shipped: pure builder `xiom.http.headers.http_headers_blob` + new client entry `xiom.http.http_request` (curl_slist via the bridge shims); `http_send` now forwards all declared `HttpRequest.headers`; suite 52/52 x2; live header roundtrip proven against the loopback echo endpoint

## v0.1.7 -- Client surface stabilisation (in progress, 2026-10-16)
- [x] Dedicated client probe `tests/probe_client.xi` (own surface; refused/malformed deterministic, live + loopback legs SKIP-safe) -- xvector lattice ask, REL-20261016-1129-xvector-2
- [x] Documented client stability + limits (README + SPEC)
- [x] Keep-alive control + idle connection reuse for the client -- shipped 0.1.10 as `HttpClientSession`
- [x] Per-call timeouts (connect + total) -- shipped 0.1.10 via `HttpRequestOptions`
- [ ] Streaming request/response bodies -- not pinned; skipped in 0.1.10
- [ ] Pluggable TLS hook (compose with `xiom.ssl` when it lands) -- not pinned; skipped in 0.1.10

## v0.1.4 (historical)
- [x] Fix: printable bytes render as characters, not decimal codes (all module-local copies)
- [x] Fix: libcurl LONG options passed by value (variadic ABI), removing the heap-pointer defect and its per-call leak
- [x] Conformance suite expanded to 42 checks

## v0.1.0 (historical)
- [x] HTTP client via libcurl FFI (GET, POST, PUT, DELETE, download)
- [x] URL parsing (scheme, host, port, path, query, fragment)
- [x] HTTP types (HttpMethod, HttpVersion, HttpHeaders, HttpRequest, HttpResponse)
- [x] Status code classification and text lookup
- [x] MIME type mapping from file extensions
- [x] Header parsing (request, response, headers-only)
- [x] Cookie parsing and serialization
- [x] HTTP server type scaffolding (transport layer pending)
- [x] Contract verification on all public functions
- [x] Conformance test suite (36 tests across all modules)

## v0.2.0 -- Transport & Server
- [ ] TCP transport layer (Layer 3.1 dependency)
- [ ] Full HTTP/1.1 server listen/accept loop
- [ ] Request routing and handler dispatch
- [ ] Keep-alive connection pooling
- [ ] Chunked transfer encoding

## v0.3.0 -- Advanced Features
- [ ] TLS/SSL via OpenSSL FFI
- [ ] HTTP/2 support
- [ ] WebSocket upgrade
- [ ] Streaming request/response bodies
- [ ] Request retry with exponential backoff
- [x] Connection pooling for client -- session-scoped handle/connection reuse shipped 0.1.10

## v1.0.0 -- Production Readiness
- [ ] Full RFC 7230-7235 compliance
- [ ] Rate limiting middleware
- [ ] CORS middleware
- [ ] Compression middleware (gzip/brotli)
- [ ] Structured logging
- [ ] Performance benchmarks
- [ ] Load testing suite
