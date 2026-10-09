# xiom.openssl -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-09

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic multi-soname loader | Done -- 3.x / 1.1.x / unversioned |
| G2 pin (candidates + entry points + samples) | Done -- `SPEC.md` §3 |
| Version string/number | Done -- OpenSSL 3.2.4 / LibreSSL 3.8.2 proven |
| SHA-256 functional proof | Done -- exact digest match |
| CSPRNG (`RAND_bytes`) | Done |
| EVP digests/ciphers | Phase 2 |
| TLS contexts/BIOs (`libssl`) | Phase 2 |
| Certificates (X509) | Phase 2 |
| Secure memory (`OPENSSL_cleanse`, CRYPTO_secure_malloc) | Phase 2 |

## Phase 2 (next touches)

1. SHA-256 EVP stream helpers (`EVP_MD_CTX_new`/`EVP_DigestInit_ex/Update/
   Final`) over XIOM chunks; SHA-512/HMAC.
2. CSPRNG wrappers: `RAND_bytes`/`RAND_priv_bytes` with Result-typed output
   buffers; error-queue draining (`ERR_get_error`/`ERR_error_string_n`).
3. TLS client: `libssl` loader half (`libssl-3-x64.dll` + `SSL_CTX_new`/
   `TLS_client_method`/`SSL_connect` over memory BIOs) -- gated behind a
   `--link`-free BIO pair; this is the piece PULSE said it does not need
   (proxy terminates TLS) but ecosystem consumers will.
4. Certificates: X509 parse/verify surface once TLS lands.
5. Cleanse/secure-memory helpers.
6. Decide the `xiom.ffmpeg` configuration (LGPL-only vs GPL) with the native
   lane before starting that package (see the session relay recommendation).

## Sector note

Crypto/media sector, package 1 of 2 (`xiom.openssl` this package;
`xiom.ffmpeg` next pending the license-configuration decision).
