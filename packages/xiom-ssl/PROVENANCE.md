# xiom.ssl -- Provenance

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

## Upstream (oracle, not vendored)

- **Project:** OpenSSL -- https://github.com/openssl/openssl (the libssl
  half of the same upstream as the shipped `xiom.openssl`).
- **Clone:** `E:\repos\openssl`, shallow, pinned **tag `openssl-3.2.4` =
  commit `8ac4271233ecec5aa0468a5e7ae38dd642ebf365`** (the branch point
  release commit; matches the local Git for Windows 3.2.4 DLLs exactly).
- **License:** Apache-2.0 (`LICENSE.txt` in the clone). Read-only oracle;
  the clone is registered in `E:\repos\CLEANUP.md`.
- **Nothing is vendored.** No OpenSSL source, headers, generated files or
  binaries are copied into this repository; the package ships zero C
  sources and links nothing at build time (the loader resolves the system
  DLLs at run time).

## Files studied (declaration oracle)

| Oracle file | What was taken |
|---|---|
| `include/openssl/ssl.h.in` | entry-point names/signatures, `SSL_VERIFY_*`, `SSL_FILETYPE_*` (via `X509_FILETYPE_*`), `SSL_ERROR_*`, `SSL_CTRL_SET_TLSEXT_HOSTNAME`, `SSL_CTRL_EXTRA_CHAIN_CERT`, `SSL_SENT/RECEIVED_SHUTDOWN` |
| `include/openssl/tls1.h` | `TLSEXT_NAMETYPE_host_name` |
| `include/openssl/x509.h.in`, `x509_vfy.h.in` | `X509_FILETYPE_PEM/ASN1`, `X509_V_OK` and the verify-result catalog entries surfaced by `ssl_verify_result_name` |
| `include/openssl/bio.h.in` | `BIO_CTRL_PENDING`, `BIO_new/s_mem/read/write/ctrl/new_mem_buf` prototypes |
| `include/openssl/pem.h`, `evp.h` | `PEM_read_bio_X509` / `PEM_read_bio_PrivateKey` (DECLARE_PEM_rw_cb_ex), `d2i_AutoPrivateKey`, `EVP_PKEY_free` |
| `ssl/ssl_lib.c`, `ssl/s3_lib.c`, `ssl/ssl_rsa.c` | **semantics**, not code: use_certificate/use_PrivateKey up-ref behavior; `SSL_CTRL_EXTRA_CHAIN_CERT` = add0 (ownership transfers only on success); `SSL_CTX_set_alpn_protos` "0 = success" and list validation ("not valid per RFC"); `SSL_get0_alpn_selected` NULL/0 when nothing selected |
| `ssl/statem/statem_srvr.c`, `statem.c` | server ALPN selection requires `alpn_select_cb` (the documented limitation); shutdown return codes 0/1 |
| `doc/man3/SSL_CTX_set_alpn_select_cb.pod` | ALPN wire-format rules encoded in `ssl_alpn_wire` (8-bit length prefixes, 1..255 per name, truncated lists invalid) |

**Derived vs independent:** the *constants* are transcribed numeric values
from the headers above (declared locally in `ssl.xi`; one canonical home
per name). The *code* is independent: hand-written XIOM wrappers over
resolved symbols, XIOM-owned byte slots, and typed-error classification --
no OpenSSL structure layout is replicated and no C is compiled.

## Test fixtures

`tests/fixtures/server-{cert,key}.{pem,der}` are a **self-signed
localhost certificate + private key generated locally for this suite**
(RSA-2048, CN=127.0.0.1, SAN IP:127.0.0.1, 10 years; generated with the Git
For Windows `openssl` CLI). They are test material only: not upstream
data, not secrets, and never reused outside the conformance suite. SHA256s
are pinned in SPEC.md section 3.

## Wire/ABI evidence

- Symbol preflight before writing the module: all 48 entry points resolved
  on the real 3.2.4 DLLs (30/30 libssl + 12/12 libcrypto in the first
  pass; the 6 memory-BIO additions verified in a second pass) via
  LoadLibrary/GetProcAddress probes.
- The suite's functional proof is live traffic, not a call-through: a real
  handshake, encrypted data, verify outcomes and clean shutdown (SPEC
  section 6).

## Re-carve procedure

1. `git fetch` the target tag in `E:\repos\openssl` (shallow clone) and
   re-verify the entry-point set + constants against the pinned headers.
2. Update `ssl.xi` constants/sample tables and both docs in one commit.
3. Re-run both suite legs x2 (default PATH = SKIP; Git mingw64 bin
   prepended = live) and record via `scripts/status.ps1`.

## Rejected alternatives (recorded)

- **Vendoring libssl**: rejected (config/ABI matrix; the fleet's shipped
  `xiom.openssl` established the dynamic-loader pattern for this tree).
- **A C shim exposing an ALPN selector callback**: rejected (adds vendored
  C and a build step for one feature; the limitation is documented instead
  and revisited if the compiler ships callback bridging).
- **Reimplementing TLS-record handling in XIOM**: rejected -- `xiom.tls`
  already owns the record/handshake codec; `xiom.ssl` is the context
  engine and composes with it.
