# xiom.openssl

OpenSSL (libcrypto) bindings for XIOM via a **multi-soname dynamic loader**:
`ossl_load()` tries the common libcrypto builds at runtime and every call
goes through resolved function pointers. No link-time dependency, no headers,
no vendored code -- and the suite reports **SKIP** (green) when no build is
present.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1):
> **4/4** on the default PATH (`LibreSSL 3.8.2` via `System32\libcrypto.dll`)
> and **4/4** with Git for Windows' `OpenSSL 3.2.4` first; real SHA-256
> digest check plus `RAND_bytes`.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.openssl;

fn main() {
  let p = ossl_probe_default();
  if !p.is_ok {
    io.println("OpenSSL unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: OsslInfo = p.value;
  io.println(info.version);
  if info.sha256_ok {
    io.println("sha256 verified");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Loader | `ossl_load`, `ossl_load_named(soname)`, `ossl_close`, `OsslLibrary` |
| Probe | `ossl_probe(lib)`, `ossl_probe_default`, `ossl_probe_named(soname)`, `OsslInfo` |
| Kinds | `OSSL_LOAD_ABSENT`, `OSSL_LOAD_ABI`, `OSSL_PROBE_FAILED` |
| Constants | `OSSL_VERSION_TYPE_OPENSSL` |

Candidate sonames: `libcrypto-3-x64.dll`, `libcrypto-1_1-x64.dll`,
`libcrypto-1_1.dll`, `libcrypto.dll`.  The probe reports the version
string/number and verifies SHA-256("abc") against the published digest.

## Tests

```
scripts/port.ps1 -Package xiom.openssl
```

Expected (on this host): 4 `[PASS]`, exit 0 -- a system libcrypto is found on
the default PATH.  A machine without any candidate prints explicit SKIP
labels.  EVP/TLS/certificates are Phase 2 (`ROADMAP.md`).
