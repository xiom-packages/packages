# xiom.ssl

> **Status:** `incubating` -- conformance-tested (**23/23 live x2**; **4/4
> SKIP x2** on the compiler pin v0.64.5); **published in `eco-v0.1.189`
> (sha256 `ba42cf2b...`; PULSE top-tier -- TLS headline)**.
> **Scope (phase 1):** libssl-class TLS **context engine** -- server/client
> contexts, cert/key/chain load, handshake driving, ALPN, verify modes,
> clean shutdown, typed errors. Streaming/session reuse/OCSP are later.
> **Deps:** `xiom.std` only (the module imports `xiom.ffi.dl`,
> `xiom.ffi` and `xiom.net.socket`); tests use `xiom.io`,
> `xiom.convert`, `xiom.string.compare`.

## What it is

`xiom.ssl` binds the system **libssl** through a multi-soname dynamic
loader (the shipped `xiom.openssl` pattern applied to the TLS library):
it drives real TLS handshakes and encrypted streams with OpenSSL's context
engine while **nothing is vendored** and **CI without OpenSSL stays
green** (no candidate soname -> SKIP). It composes with the **`xiom.tls`**
record/handshake codec and the **`xiom.openssl`** libcrypto surface rather
than duplicating either.

Load order: `libssl-3-x64.dll`, `libssl-1_1-x64.dll`, `libssl-1_1.dll`,
`libssl.dll`; the libcrypto companion (`libcrypto-3-x64.dll` /
`libcrypto-1_1-x64.dll` / `libcrypto-1_1.dll` / `libcrypto.dll`) is
resolved for the PEM/BIO/error-queue helpers. Classification:
`SSL_LOAD_ABSENT` -> SKIP; `SSL_LOAD_ABI` -> FAIL; operational failures are
typed `SslError { kind, message }`.

## Loader and probe

| Function | Returns | Description |
|---|---|---|
| `ssl_load()` | `Result[SslLibrary, SslError]` | First available candidate (SKIP-safe). |
| `ssl_load_named(soname)` | `Result[SslLibrary, SslError]` | Explicit build (bogus names exercise the SKIP path deterministically). |
| `ssl_close(&lib)` | `Result[Unit, Str]` | Release both handles. |
| `ssl_probe(&lib)` / `ssl_probe_default()` / `ssl_probe_named(n)` | `Result[SslInfo, SslError]` | Companion `OpenSSL_version` string + number. |

## Contexts

| Function | Returns | Description |
|---|---|---|
| `ssl_ctx_new(&lib, server)` | `Result[SslContext, SslError]` | `TLS_server_method` / `TLS_client_method` context. |
| `ssl_ctx_free(&lib, &ctx)` | -- | Free. |
| `ssl_ctx_set_verify(&lib, &ctx, mode)` | -- | `SSL_VERIFY_NONE` / `SSL_VERIFY_PEER` / `SSL_VERIFY_FAIL_IF_NO_PEER_CERT` (default callback). |
| `ssl_ctx_load_verify_locations(&lib, &ctx, cafile, capath)` | `Result[Unit, SslError]` | CA bundle file and/or hashed dir; `""` = skip that parameter (passed as NULL). |

## Certificates and keys (PEM / DER, files and buffers)

| Function | Description |
|---|---|
| `ssl_ctx_use_cert_file` / `ssl_ctx_use_key_file (&lib, &ctx, path, pem)` | Load from file (`pem=false` = `SSL_FILETYPE_ASN1`). |
| `ssl_ctx_use_chain_file(&lib, &ctx, path)` | PEM chain file (leaf + intermediates). |
| `ssl_ctx_use_cert_pem` / `ssl_ctx_use_key_pem (&lib, &ctx, pem)` | Load from a PEM buffer (memory BIO + `PEM_read_bio_*`; temporaries released -- the ctx up-refs). |
| `ssl_ctx_use_cert_der(&lib, &ctx, &der)` | DER buffer via `SSL_CTX_use_certificate_ASN1`. |
| `ssl_ctx_use_key_der(&lib, &ctx, &der)` | DER buffer via `d2i_AutoPrivateKey` (PKCS#8/PKCS#1/SEC1 auto-detected). |
| `ssl_ctx_add_chain_pem` / `ssl_ctx_add_chain_der` | Append an extra chain cert (ownership moves to the ctx on success, add0). |
| `ssl_ctx_check_private_key(&lib, &ctx)` | Certificate/key consistency. |

## Streams, handshake, ALPN, verify

| Function | Returns | Description |
|---|---|---|
| `ssl_new(&lib, &ctx)` / `ssl_free(&lib, &s)` | `Result[SslStream, SslError]` / -- | Stream lifecycle. |
| `ssl_set_fd(&lib, &mut s, fd)` | `Result[Unit, SslError]` | Attach a socket descriptor; the fd is remembered for WANT polling. |
| `ssl_set_bio_mem(&lib, &mut s)` | `Result[Unit, SslError]` | Attach a memory-BIO pair -- **no socket**; transport-agnostic. |
| `ssl_set_hostname(&lib, &s, host)` | `Result[Unit, SslError]` | SNI (`SSL_ctrl` `SSL_CTRL_SET_TLSEXT_HOSTNAME`). |
| `ssl_step(&lib, &s, server)` | `Result[SslStep, SslError]` | One `SSL_accept`/`SSL_connect` step: `done`, or `want` = `SSL_WANT_READ/WRITE`; fatal -> typed error carrying the verify result. |
| `ssl_read(&lib, &s, max)` | `Result[Vec[UInt8], SslError]` | Plaintext; empty vector = clean peer close (close_notify); WANT states wait on a bounded poll (fd streams). |
| `ssl_write(&lib, &s, &data)` | `Result[Int, SslError]` | All bytes (partial-write retry). |
| `ssl_shutdown(&lib, &s)` | `Result[Int, SslError]` | `0` = close_notify sent, `1` = complete; WANT as typed kinds. |
| `ssl_get_version` / `ssl_get_cipher` | `Str` | Negotiated version / cipher suite. |
| `ssl_get_verify_result(&lib, &s)` | `Int` | Raw X509 code (`0` = `X509_V_OK`); `ssl_verify_result_name(code)` names the common ones. |
| `ssl_bio_pending` / `ssl_bio_drain` / `ssl_bio_feed` | `Result[...]` | Memory-BIO pump: drain outgoing bytes, feed incoming ones. |
| `ssl_alpn_wire(&names)` | `Result[Vec[UInt8], Str]` | Pure: build the ALPN wire list. |
| `ssl_ctx_set_alpn_protos(&lib, &ctx, &wire)` | `Result[Unit, SslError]` | Set the client ALPN list (set it **before** `ssl_new`). |
| `ssl_alpn_selected(&lib, &s)` | `Result[Str, SslError]` | Negotiated protocol (`""` = none). |

## Example (client, full handshake over a socket)

```xi
use xiom.ssl;

let lr = ssl_load();
if !lr.is_ok {
  // SKIP path: no libssl on this host.
}
let lib: SslLibrary = lr.value;
let cr = ssl_ctx_new(&lib, false);
let ctx: SslContext = cr.value;
ssl_ctx_set_verify(&lib, &ctx, SSL_VERIFY_NONE);

let sr = ssl_new(&lib, &ctx);
var s: SslStream = sr.value;
let sf = ssl_set_fd(&lib, &mut s, fd);
let hn = ssl_set_hostname(&lib, &s, "example.internal");

// Drive the handshake; poll the fd between steps when a side wants I/O.
var done = false;
while !done {
  let st = ssl_step(&lib, &s, false);
  if st.is_ok { if st.value.done { done = true; } } else { /* typed error */ }
}

let msg = /* Vec[UInt8] */;
let w = ssl_write(&lib, &s, &msg);
let r = ssl_read(&lib, &s, 4096);
```

## SKIP behavior (CI without OpenSSL)

`ssl_load()` tries the four sonames; when none resolves, every live-suite
check collapses into one explicit `SKIP` pass (the SKIP path itself is
exercised deterministically on every host through a bogus soname), and the
pure helpers (ALPN wire golden, verify-name catalog) still run. On this
box the live leg needs `C:\Program Files\Git\mingw64\bin` on `PATH`
(the xiom.openssl SPEC precedent); the default PATH has no libssl.

## Limitations (phase 1)

- **Server-side ALPN selection is out of surface**: OpenSSL selects through
  an `SSL_CTX_set_alpn_select_cb` C callback and the XIOM FFI has no
  callback bridging (lane survey 2026-10). Client set-list + negotiated
  read are bound and tested; a server without a selector negotiates `""`.
- No DTLS, session reuse/tickets API, OCSP, or hostname verification
  (libssl never does hostname checks; inspect certificates with
  `xiom.tls`/`xiom.pki`).
- `ssl_read`/`ssl_write` wait with a bounded poll on socket fds; feed
  memory-BIO streams with `ssl_bio_feed`/`ssl_bio_drain` instead.

## Evidence

- Suite: `scripts/port.ps1 -Package xiom.ssl -TimeoutSec 300` --
  **23/23 x2** live (`OpenSSL 3.2.4`, TLSv1.3 + `TLS_AES_256_GCM_SHA384`,
  real handshake/data/shutdown/verify/memory-BIO) and **4/4 x2** SKIP
  (recorded in `STATUS.json`).
- Oracle and re-carve: `PROVENANCE.md`; pin and samples: `SPEC.md`.
- Lane audit and probes: `AUDIT.md`.
