# xiom-openssl — ROADMAP

**Phase**: 4 (Enterprise) | **Priority**: Medium  
**Status**: SPEC implemented, pending runtime integration  
**Last updated**: 2026-07-21

## Implemented (v0.1)

- [x] `openssl.xi` — core module `xiom.openssl`
  - [x] Opaque types: `SslContext`, `SslConnection`, `SslBio` (all `Int`)
  - [x] Error type: `SslError { code: Int; message: Str }`
  - [x] extern "C" block: 20 OpenSSL functions declared
    - libssl: SSL_library_init, SSL_load_error_strings, TLS_client_method, SSL_CTX_new, SSL_CTX_free, SSL_new, SSL_set_fd, SSL_set_bio, SSL_connect, SSL_accept, SSL_shutdown, SSL_free, SSL_read, SSL_write
    - libcrypto/BIO: BIO_new_connect, BIO_read, BIO_write, BIO_free
    - libcrypto/err: ERR_get_error, ERR_error_string
    - libcrypto/hash: SHA256, EVP_MD_CTX_new
  - [x] Safe wrappers with contract clauses (`requires`, `ensures`):
    - `init()`, `ctx_new(method)`, `ctx_new_client()`
    - `connect(ctx, host, port)`, `accept(ctx, fd)`
    - `read(ssl, buf)`, `write(ssl, data)`
    - `ssl_shutdown(ssl)`, `ssl_free(ssl)`, `ctx_free(ctx)`
    - `get_error_code()`, `get_error_string(error_code)`
    - `sha256(data)`, `evp_md_ctx_new()`
    - `bio_new_connect(host, port)`, `bio_read(bio, buf)`, `bio_write(bio, data)`, `bio_free(bio)`
- [x] `tests/test_conformance.xi` — 21 structural tests
  - 5 type-identity tests
  - 15 contract-clause-verification tests
  - 1 error-construction test
  - Runner: `run_conformance()`

## Pending

- [ ] **Runtime linking**: Wire `xiom.openssl` against system `libssl.so`/`libcrypto.so` (Linux), `libssl.dylib` (macOS), or `libssl-3-x64.dll` (Windows)
- [ ] **Integration tests**: Real TLS handshake against a test server (requires runtime)
- [ ] **Server mode**: `tls_listen()` / `tls_accept()` using `SSL_CTX_use_certificate_file` + `SSL_CTX_use_PrivateKey_file`
- [ ] **Certificate verification**: `SSL_CTX_set_verify`, `SSL_get_verify_result`, `X509_STORE` wrappers
- [ ] **SNI support**: `SSL_set_tlsext_host_name`
- [ ] **Async I/O**: `SSL_set_mode(SSL_MODE_ASYNC)` or integration with `xiom.async`
- [ ] **Platform CI**: Cross-compile to Linux (x86_64/aarch64), macOS, Windows

## Dependencies

| Module | Status |
|--------|--------|
| `xiom.ffi` | Stable (stdlib) |
| `xiom.string` | Stable (stdlib) |
| `xiom.core` | Stable (stdlib) |
| `xiom.test` | Stable (stdlib) |

## Known Limitations

- All handle types are typed `Int` — no compiler-level distinction between `SslContext`, `SslConnection`, `SslBio` at the type level (same as `TcpStream`, `TcpListener` in `xiom.net`)
- Contracts are compile-time: `requires(host.len() > 0)` and `requires(port > 0)` are verified by `xiom` but do not generate runtime checks (by design — v0.49 contract semantics)
- Tests are structural only; runtime tests require a linked OpenSSL shared library
