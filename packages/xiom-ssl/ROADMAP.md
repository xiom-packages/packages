# xiom.ssl -- Roadmap

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

## Phase 1 -- shipped in this package (0.1.0)

Server + client contexts; cert/key/chain load (PEM/DER via paths AND
buffers); handshake driving over a stream fd (`ssl_step`) and over memory
BIOs (`ssl_set_bio_mem` + `ssl_bio_drain`/`ssl_bio_feed`);
ALPN (wire helper + set + negotiated read); verify modes (none/peer +
failure reporting with X509 result); clean shutdown (0/1/1);
typed `SslError`; SKIP-safe multi-soname loading.

## Phase 2 -- queued (in rough order)

1. **Server-side ALPN selection.** Requires passing an XIOM function as a
   C callback (`SSL_CTX_set_alpn_select_cb`) or a compiler-provided
   callback bridge. Revisit when the toolchain ships callback support;
   until then the limitation is documented in SPEC/README.
2. **Streaming facade over `xiom.transport`.** A `SslTransport` that wraps
   a `xiom.transport` handle: drain into `ssl_progress`-style steps and
   feed `ssl_bio_feed` from received frames -- the memory-BIO path already
   exists precisely for this seam; only the adapter is missing.
3. **Session reuse / tickets.** `SSL_CTX_set_session_cache_mode`,
   `SSL_SESSION_*`, `SSL_get1_session`/`SSL_set_session`,
   `SSL_CTX_sess_set_new_cb` (callback-gated like item 1 for the server
   notification; client-side reuse is callback-free).
4. **OCSP stapling read + post-handshake auth.** `SSL_get_tlsext_status_ocsp_resp`
   (out-buffer), `SSL_CTX_set_tlsext_status_type`; verify the response
   with `xiom.oscp`-class parsing (none shipped yet -- coordinate).
5. **Certificate store surface.** `X509_STORE_add_cert`,
   `SSL_CTX_set_cert_store`, `SSL_CTX_get0_cert_store` for programmatic
   trust management (buffer-loaded CAs without temp files).
6. **DTLS** (`DTLS_server_method`/`DTLS_client_method` + datagram BIO or
   `xiom.transport.udp`): same loader shape; pin after a live use case.
7. **Hostname verification helper.** libssl does not verify hostnames;
   expose `X509_check_host`/`X509_check_ip` bindings + a wrapper that
   combines them with `ssl_get_verify_result` (or delegate to a future
   `xiom.pki` checker).

## Non-goals

- Reimplementing TLS records/handshake parsing (owned by `xiom.tls`) or
  the libcrypto crypto surface (owned by `xiom.openssl`).
- Vendoring OpenSSL (the system-library path is the fleet decision; see
  SPEC section 2).
