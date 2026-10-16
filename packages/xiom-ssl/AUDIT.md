# xiom.ssl -- Lane audit (build, probes, evidence)

> Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
> SPDX-License-Identifier: MIT OR Apache-2.0

Toolchain: compiler pin **v0.64.5** (`$env:LOCALAPPDATA\xiom.new\bin\xiom.exe`),
stdlib `E:\xiom-lang\stdlib`, worktree `feat/tls-binding`. Date: 2026-10-16.

## 1. Pre-implementation probes (all green before the module was written)

| Probe | Result |
|---|---|
| 45-field loader struct + `Int`->`*UInt8` null cast + `Vec[UInt8].with_len(64)` + byte write + fn-pointer call through `dl_open`/`dl_sym` against the real `libssl-3-x64.dll` | compiled and ran green (`TLS_server_method` non-zero) |
| `dl_open("libssl-3-x64.dll")` with Git mingw64 bin NOT on PATH | fails with loader error 126 -> the ABSENT/SKIP classification is real on this box |
| Symbol preflight via LoadLibrary/GetProcAddress: 30 libssl + 12 libcrypto names (first set) | 30/30 + 12/12 |
| Symbol preflight second set (memory-BIO surface: `SSL_set_bio`, `BIO_new`, `BIO_s_mem`, `BIO_read`, `BIO_write`, `BIO_ctrl`) | 6/6 |

Local runtime: `libssl-3-x64.dll` 930,460 bytes
`A9169D9B...F73F706C`, `libcrypto-3-x64.dll` 5,122,716 bytes
`9C069DEC...ABC9892` (identical hash to the xiom.openssl SPEC row), both
3.2.4.

## 2. Oracle-verified semantics encoded in the module

- `SSL_CTX_use_certificate` / `SSL_CTX_use_PrivateKey` up-ref the object
  (`SSL_up_ref` in `ssl_rsa.c` `ssl_set_cert`/`ssl_set_pkey`) -> the
  temporaries created from PEM/DER buffers are freed in `ssl.xi`.
- `SSL_CTX_ctrl(SSL_CTRL_EXTRA_CHAIN_CERT)` = add0: pushes raw pointer,
  ownership transfers to the ctx **only on success** (`s3_lib.c`
  `ssl3_ctx_ctrl`); the module frees the X509 on the failure path only.
- `SSL_CTX_set_alpn_protos` returns **0 on success**, non-zero on
  failure, and validates the wire list (`alpn_value_ok`,
  `ssl_lib.c`); `ssl_alpn_wire` pre-validates the same rules.
- Server ALPN selection requires `alpn_select_cb`
  (`statem_srvr.c` `tls_handle_alpn`) -> documented limitation (no
  callback bridging in the current FFI; lane survey found no shipped
  package passing an XIOM function pointer to C).
- `SSL_get0_alpn_selected` sets data NULL / len 0 when nothing selected.
- `SSL_shutdown` returns 0 (sent, peer pending) then 1 (complete); the
  suite's 0/1/1 sequence is the live proof.
- `SSL_CTX_ctrl` for chain returns 1 via the `ssl3_ctx_ctrl` tail after
  `break`; verified before relying on `rc == 1`.

## 3. B-series discipline notes

- Handles and symbols are `Int` fields; casts happen only at call sites
  (`lib.p_* as fn(...)`), one call site per symbol.
- Out-parameters are XIOM-owned `Vec[UInt8]` slots written byte-indexed;
  the ALPN foreign buffer copies out through `xiom.ffi` `SafePtr`
  bounds-checked reads (no ad-hoc pointer arithmetic in the package).
- No bare `assert`; Str equality in the suite goes through
  `compare.str_compare` (recorded toolchain discipline); no
  `Result[...tuple...]` returns anywhere (avoids the known tuple-mangling
  family); `int_to_str` is local inside the confined module (BINDINGS-
  COMPILER-FINDINGS lane pattern).
- All `unsafe`/FFI in the single module `ssl.xi` (G5).

## 4. Suite evidence (v0.64.5, 2026-10-16)

| Leg | Command | Run 1 | Run 2 | Logs |
|---|---|---|---|---|
| Live (`C:\Program Files\Git\mingw64\bin` prepended) | `scripts/port.ps1 -Package xiom.ssl -TimeoutSec 300` | PASS 23/23 (exit 0) | PASS 23/23 (exit 0) | `%TEMP%\kilo\ssl-runs\live-2.log` |
| SKIP (default PATH) | same | PASS 4/4 (exit 0) | PASS 4/4 (exit 0) | `%TEMP%\kilo\ssl-runs\skip-2.log` |

Live highlights: `OpenSSL 3.2.4 11 Feb 2025` (num 807403584); handshake 2
rounds -> `TLSv1.3` + `TLS_AES_256_GCM_SHA384` both ends; ping/pong
byte-exact; ALPN negotiated empty (no server selector, as documented);
shutdown 0/1/1; verify trusted `0`, untrusted `18` with typed
`SSL_ERR_HANDSHAKE`; memory-BIO handshake 4 rounds + data.

## 5. Process notes for the next agent

- Fixture reads are cwd-relative; `port.ps1` runs suites with the package
  dir as cwd, so `tests/fixtures/...` paths work. The DER fixtures are
  real committed files (generated with the Git `openssl` CLI; hashes in
  SPEC section 3) -- if they are missing the suite fails one explicit
  fixture check.
- The live leg needs the Git mingw64 bin on PATH (the xiom.openssl SPEC
  precedent); the SKIP leg must run **without** it (System32 has no
  libssl, so a plain run is a true absent leg).
- No new compiler findings were produced by this build; the constructor
  patterns used are all proven shapes.

## 6. Re-verify

```powershell
$env:PATH = "C:\Program Files\Git\mingw64\bin;$env:PATH"   # live leg
.\scripts\port.ps1 -Package xiom-ssl -TimeoutSec 300
# SKIP leg: new shell without that prepend
.\scripts\port.ps1 -Package xiom-ssl -TimeoutSec 300
```
