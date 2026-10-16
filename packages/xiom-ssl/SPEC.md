# SPEC: xiom.ssl -- libssl-class TLS context engine (dynamic loader, system-library path)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.ssl` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | OpenSSL (libssl, the TLS-library half of the same tree as libcrypto) -- https://www.openssl.org/ |
| Upstream version | floating system builds (3.2.4 proven on this box; 1.1.x sonames accepted) |
| Upstream license | Apache-2.0 (OpenSSL); nothing vendored -- constants declared locally from the oracle headers |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname loader) |
| Compiler pin | v0.64.5 |
| Accepted ask | REL-20261015-2211-packages (PULSE TLS context engine; dedupe -2302; naming -20261016-1142-bindings) |

## 2. Decision: system-library path (not vendored)

Same decision as the shipped `xiom.openssl`: OpenSSL's tree is far too
large/configuration-heavy to vendor, and libssl builds are ubiquitous on
Windows (Git for Windows ships `libssl-3-x64.dll` beside
`libcrypto-3-x64.dll`). The loader tries the common sonames in order and
the suite reports SKIP when none is present. The libcrypto companion is
resolved separately (its dependency is already in-process once libssl
loaded) for the PEM/BIO/error-queue helpers. `xiom.ssl` composes with the
live `xiom.tls` (record/handshake codec) and `xiom.openssl` (libcrypto
surface) rather than duplicating them.

## 3. G2 pin: candidate sonames + entry-point set + samples

**Candidate sonames (load order):** `libssl-3-x64.dll` (OpenSSL 3.x),
`libssl-1_1-x64.dll` (1.1.x x64), `libssl-1_1.dll` (1.1.x), `libssl.dll`
(unversioned). **libcrypto companion candidates:** `libcrypto-3-x64.dll`,
`libcrypto-1_1-x64.dll`, `libcrypto-1_1.dll`, `libcrypto.dll`.

**Resolved entry points (48):**

- libssl (31): `TLS_server_method`, `TLS_client_method`, `SSL_CTX_new`,
  `SSL_CTX_free`, `SSL_CTX_ctrl`, `SSL_CTX_set_verify`,
  `SSL_get_verify_result`, `SSL_CTX_use_certificate_file`,
  `SSL_CTX_use_PrivateKey_file`, `SSL_CTX_use_certificate_chain_file`,
  `SSL_CTX_check_private_key`, `SSL_CTX_use_certificate`,
  `SSL_CTX_use_PrivateKey`, `SSL_CTX_use_certificate_ASN1`,
  `SSL_CTX_load_verify_locations`, `SSL_CTX_set_alpn_protos`,
  `SSL_get0_alpn_selected`, `SSL_new`, `SSL_free`, `SSL_set_fd`,
  `SSL_set_bio`, `SSL_accept`, `SSL_connect`, `SSL_read`, `SSL_write`,
  `SSL_shutdown`, `SSL_get_error`, `SSL_get_version`,
  `SSL_get_current_cipher`, `SSL_CIPHER_get_name`, `SSL_ctrl`.
- libcrypto (17): `BIO_new`, `BIO_s_mem`, `BIO_read`, `BIO_write`,
  `BIO_ctrl`, `BIO_new_mem_buf`, `BIO_free`, `PEM_read_bio_X509`,
  `PEM_read_bio_PrivateKey`, `d2i_AutoPrivateKey`, `d2i_X509`, `X509_free`,
  `EVP_PKEY_free`, `ERR_get_error`, `ERR_error_string_n`,
  `OpenSSL_version`, `OpenSSL_version_num`.

Missing entry points after a successful load classify as `SSL_LOAD_ABI`
(FAIL); no candidate soname loading classifies as `SSL_LOAD_ABSENT` (SKIP).

**Functional proof:** the suite runs a real client/server TLS handshake
over a loopback socket (nonblocking fds driven through `ssl_step`) with the
fixture cert/key, asserts TLSv1.3 + a negotiated cipher on both ends,
exchanges encrypted data both directions, shuts down cleanly (0/1/1), and
repeats a full handshake over memory BIOs only (no socket). Verify modes
are proven both ways: trusted CA -> `verify_result == 0`; no CA ->
typed `SSL_ERR_HANDSHAKE` with `verify_result == 18` (self-signed).

**Local runtime samples used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `Git\mingw64\bin\libssl-3-x64.dll` (3.2.4, first candidate) | 930,460 bytes, SHA256 `A9169D9B4350C934570C6912614DC76EDADFAE64469DE802D5529B65F73F706C` |
| `Git\mingw64\bin\libcrypto-3-x64.dll` (3.2.4, companion) | 5,122,716 bytes, SHA256 `9C069DEC902628C5E37F532A06F171C5B82333A3614E57DB0D1429D70ABC9892` (identical to the xiom.openssl SPEC row) |

Recorded runtime reports: `OpenSSL 3.2.4 11 Feb 2025` (num 807403584 =
0x30200040) via the libcrypto companion; handshake negotiated `TLSv1.3` +
`TLS_AES_256_GCM_SHA384` both ends.

**Test fixtures (self-signed, tests only; not upstream, not secrets):**

| File | SHA256 |
|------|--------|
| `tests/fixtures/server-cert.pem` (CN=127.0.0.1, SAN IP:127.0.0.1, RSA-2048, 10y) | `F2D6E6AFDC0D498D152A51162EAF64ADB97B1F3655C97E4B0F6531D8E9EC05DB` |
| `tests/fixtures/server-key.pem` (PKCS#8) | `AE9490F5796CEF8E2B388C8FFC3F2F6D579EAC0B832D28C6D9A580943CDBD91B` |
| `tests/fixtures/server-cert.der` | `4AEEC3BBE8D95BA93D409A8B74E38287E7B20F5DC65801AEFB2CE0C3DD3901F6` |
| `tests/fixtures/server-key.der` (PKCS#8 DER) | `5F4B9CF42CF8B390B985C8F8FC84AB7098FDCD9D715A4281BC123C43ADCCCCFA` |

### Re-pin procedure

1. Re-verify the entry-point names/ABI against the oracle clone (or the
   build's own headers) before touching the module.
2. Update the sample table + README/SPEC rows in one commit.
3. Re-run `scripts/port.ps1 -Package xiom.ssl` on both legs (default PATH
   = SKIP; Git mingw64 bin prepended = live) and record the matrix.

## 4. Design and safe boundary (G5)

`ssl.xi` is the only module and holds every `unsafe` block: an
`SslLibrary` loader struct (52 Int fields: 4 identity + 48 entry points),
context/stream wrappers, and a step-driven handshake. Every call is an
fn-pointer cast over `xiom.ffi.dl`; handles and symbols are Ints (never
cast to pointers outside the call site). Out-parameters are XIOM-owned
byte slots (`Vec[UInt8].with_len`) read byte-indexed (`rd_u64_le` /
`rd_u32_le`); the foreign ALPN buffer copies out through the ffi `SafePtr`
bounds-checked reader; DER-pointer in-slots are byte-indexed writes (B-10
`f_`-style bridges are not needed because the module keeps one call site
per symbol).

Ownership rules verified against the oracle source and encoded:
`SSL_CTX_use_certificate`/`use_PrivateKey` up-ref (temporaries freed here);
`SSL_CTX_ctrl(SSL_CTRL_EXTRA_CHAIN_CERT)` is add0 -- ownership moves to the
context on success only; `SSL_set_bio` takes ownership of both memory BIOs
(`SSL_free` releases them); `SSL_set_fd` remembers the fd for the bounded
WANT polling inside `ssl_read`/`ssl_write`.

Classification: `SSL_LOAD_ABSENT` -> SKIP; `SSL_LOAD_ABI` -> FAIL;
operational failures -> typed `SslError { kind, message }` with kinds
ALLOC / CERT / ALPN / HANDSHAKE / WANT_READ / WANT_WRITE / IO. Handshake
failures carry the X509 verify result when non-OK
(`verify_result=18: self-signed certificate`).

## 5. Declared surface (phase 1)

- loader: `ssl_load`, `ssl_load_named`, `ssl_close`, `ssl_probe`,
  `ssl_probe_named`, `ssl_probe_default`;
- contexts: `ssl_ctx_new(server)`, `ssl_ctx_free`, `ssl_ctx_set_verify`,
  `ssl_ctx_load_verify_locations`;
- cert/key/chain (PEM/DER x files/buffers): `ssl_ctx_use_cert_file`,
  `ssl_ctx_use_key_file`, `ssl_ctx_use_chain_file`,
  `ssl_ctx_check_private_key`, `ssl_ctx_use_cert_pem`,
  `ssl_ctx_use_key_pem`, `ssl_ctx_use_cert_der`, `ssl_ctx_use_key_der`,
  `ssl_ctx_add_chain_pem`, `ssl_ctx_add_chain_der`;
- streams: `ssl_new`, `ssl_free`, `ssl_set_fd`, `ssl_set_bio_mem`,
  `ssl_set_hostname` (SNI), `ssl_step` (SSL_accept/SSL_connect with
  WANT_READ/WANT_WRITE), `ssl_read`, `ssl_write`, `ssl_shutdown`,
  `ssl_get_version`, `ssl_get_cipher`, `ssl_get_verify_result`;
- memory-BIO pump: `ssl_bio_pending`, `ssl_bio_drain`, `ssl_bio_feed`;
- ALPN: `ssl_alpn_wire` (pure), `ssl_ctx_set_alpn_protos`,
  `ssl_alpn_selected`;
- catalogs: `ssl_verify_result_name`.

**Documented limitations (explicit non-goals in phase 1):**

- **Server-side ALPN SELECTION is out of surface.** OpenSSL selects the
  server protocol only through an `SSL_CTX_set_alpn_select_cb` C callback;
  the XIOM FFI has no callback bridging (2026-10 lane survey: no shipped
  package passes an XIOM function pointer to C). Client set-list +
  negotiated read are fully bound and tested; a server without a selector
  negotiates ALPN "none" (`alpn_selected == ""`), which the suite asserts.
- No DTLS, no session reuse/tickets API, no OCSP, no hostname
  verification helper (libssl does not do hostname checks; use
  `xiom.pki`/`xiom.tls` for certificate inspection).
- `ssl_read`/`ssl_write` wait on WANT states with a bounded poll
  (fd-bound streams); a memory-BIO stream reports WANT as a typed error so
  the caller drives the byte pump.
- Readiness polling uses `xiom.net.socket` poll; stream fds must be
  sockets for the internal waiting (a caller can always use `ssl_step`-level
  primitives directly instead).

## 6. Test matrix (recorded 2026-10-16, compiler v0.64.5)

| Configuration | Command | Result |
|---------------|---------|--------|
| Git mingw64 bin prepended (libssl 3.2.4 live) | `scripts/port.ps1 -Package xiom.ssl -TimeoutSec 300` | **PASS 23/23 x2** -- probe `OpenSSL 3.2.4`; PEM/DER files+buffers; chain; CA load + typed absent-file error; real loopback handshake (TLSv1.3, `TLS_AES_256_GCM_SHA384`), ping/pong, ALPN set + negotiated-empty, shutdown 0/1/1; verify-peer trusted (0) and untrusted (18, typed failure); memory-BIO handshake + data |
| Default PATH (no libssl anywhere) | same | **PASS 4/4 x2** -- SKIP classification (bogus soname), pure ALPN-wire golden, verify catalog, live SKIP |

## 7. Scope

Phase 1 (this version): the accepted ask surface -- contexts, cert/key/chain
load, handshake driving over a stream fd and memory BIOs, ALPN, verify
modes, clean shutdown, typed errors, SKIP-safe loading. Streaming facade
wiring over `xiom.transport`, session reuse, OCSP and the ALPN callback
(if/when the compiler ships C-callback bridging) are Phase 2 (ROADMAP.md).
