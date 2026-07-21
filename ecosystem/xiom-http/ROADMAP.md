# xiom-http ROADMAP

## v0.1.0 (Current)
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

## v0.2.0 — Transport & Server
- [ ] TCP transport layer (Layer 3.1 dependency)
- [ ] Full HTTP/1.1 server listen/accept loop
- [ ] Request routing and handler dispatch
- [ ] Keep-alive connection pooling
- [ ] Chunked transfer encoding

## v0.3.0 — Advanced Features
- [ ] TLS/SSL via OpenSSL FFI
- [ ] HTTP/2 support
- [ ] WebSocket upgrade
- [ ] Streaming request/response bodies
- [ ] Request retry with exponential backoff
- [ ] Connection pooling for client

## v1.0.0 — Production Readiness
- [ ] Full RFC 7230–7235 compliance
- [ ] Rate limiting middleware
- [ ] CORS middleware
- [ ] Compression middleware (gzip/brotli)
- [ ] Structured logging
- [ ] Performance benchmarks
- [ ] Load testing suite
