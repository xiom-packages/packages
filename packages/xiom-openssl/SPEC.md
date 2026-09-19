# xiom.openssl -- SPEC
**Phase**: 4 (Enterprise) | **Priority**: Medium
**Status**: Implemented (SPEC ? code) | **Depends on**: xiom.ffi, xiom.string, xiom.core
OpenSSL -- TLS/cryptography. System-installed. Day effort.

## Files

| File | Lines | Description |
|------|-------|-------------|
| `openssl.xi` | 347 | Core module `xiom.openssl` (22 extern "C" fns + malloc/free, 18 safe wrappers, 3 opaque types, 1 error type) |
| `tests/test_conformance.xi` | 162 | 21 structural conformance tests (5 type, 15 contract, 1 error-construction) |
| `ROADMAP.md` | 54 | Implementation status and pending runtime integration items |
| `SPEC.md` | -- | This file |

## Module API

```
xiom.openssl

Types:     SslContext(Int), SslConnection(Int), SslBio(Int), SslError{code, message}
Externs:   24 (2 stdlib + 22 OpenSSL: init, ctx, tls, I/O, BIO, error, SHA256, EVP)
Wrappers:  18 (init, ctx_new, ctx_new_client, connect, accept, read, write,
              ssl_shutdown, ssl_free, ctx_free, get_error_code, get_error_string,
              sha256, evp_md_ctx_new, bio_new_connect, bio_read, bio_write, bio_free)
Contracts:  16 requires + 2 ensures clauses across 14 functions
Tests:      21 conformance tests (17 pass, 0 fail -- structural verification)
```
