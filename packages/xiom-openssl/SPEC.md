# SPEC: xiom.openssl -- libcrypto bindings (dynamic loader, system-library path)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.openssl` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | OpenSSL (and API-compatible LibreSSL) -- https://www.openssl.org/ |
| Upstream version | floating system builds (3.2.4 / 1.1.1n / 1.1.1g / LibreSSL 3.8.2 samples) |
| Upstream license | Apache-2.0 (OpenSSL); nothing vendored -- constants declared locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname loader) |
| Compiler pin | v0.64.1 |

## 2. Decision: system-library path (not vendored)

OpenSSL's source tree is far too large and configuration-heavy to vendor into
a package (unlike zstd/lzfse/miniaudio), and libcrypto builds are ubiquitous
on Windows (Git for Windows, Python, many applications, and Windows' own
`System32\libcrypto.dll`). The loader therefore tries the common sonames in
order and the suite reports SKIP when none is present.

## 3. G2 pin: candidate sonames + entry-point set + samples

**Candidate sonames (in load order):** `libcrypto-3-x64.dll` (OpenSSL 3.x),
`libcrypto-1_1-x64.dll` (1.1.x x64), `libcrypto-1_1.dll` (1.1.x), and the
unversioned `libcrypto.dll` (captures Windows/mingw builds).

**Resolved entry points:** `OpenSSL_version` (type 0 = `OPENSSL_VERSION`),
`OpenSSL_version_num`, `SHA256`, `RAND_bytes`.

**Functional proof:** SHA-256 of `"abc"` is compared inside the module
against the published digest (four little-endian u64 words:
`-1527000031757436742`, `2531777658719584577`, `-7171393520880516176`,
`-5974868289610903372`), plus a `RAND_bytes(16)` liveness call.  A wrong or
corrupted build fails the suite.

**Local runtime samples used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| `Git\mingw64\bin\libcrypto-3-x64.dll` (OpenSSL 3.2.4, first candidate) | 5,122,716 bytes, SHA256 `9C069DEC902628C5E37F532A06F171C5B82333A3614E57DB0D1429D70ABC9892` |
| `System32\libcrypto.dll` (default-PATH find; LibreSSL 3.8.2 reports via it) | 1,916,416 bytes, SHA256 `7CEA4AC14491DAC72A0DE0692276EC400DA8C1952271A16935282DCA31D88D99` |
| `DaVinci Resolve\libcrypto-1_1-x64.dll` (1.1.1n secondary) | 3,441,664 bytes, SHA256 `C42021799A9EDECFE72799E408081A3504CD22C635FB3E94A99FB39983C41AFC` |
| `Python37\DLLs\libcrypto-1_1.dll` (1.1.1g secondary) | 3,399,200 bytes, SHA256 `594303E2CE6A4A02439054C84592791BF4AB0B7C12E9BBDB4B040E27251521F1` |

Recorded runtime reports: `OpenSSL 3.2.4 11 Feb 2025` (num 807403584 =
0x30200040) with Git's directory prepended; `LibreSSL 3.8.2` (num 536870912 =
0x20000000) on the default PATH via `System32\libcrypto.dll`.

### Re-pin procedure

1. Re-verify the entry-point names/ABI before touching the module (both
   OpenSSL 1.1/3.x and LibreSSL expose them).
2. Update the sample table and version rows in `README.md`/`AUDIT.md` in one
   commit.
3. Re-run `scripts/port.ps1 -Package xiom.openssl` (default and with a
   specific build directory prepended) and record the matrix.

## 4. Design and safe boundary (G5)

`openssl.xi` is the only module with `unsafe`: an `OsslLibrary` loader struct
plus wrappers (`ossl_load(_named)`, `ossl_close`, `ossl_probe(_named/
_default)`). The probe reads the version string/number, computes
SHA-256("abc") into a 32-byte XIOM-owned slot, and calls `RAND_bytes`.
Classification: `OSSL_LOAD_ABSENT` -> SKIP; `OSSL_LOAD_ABI` -> FAIL;
`OSSL_PROBE_FAILED` -> FAIL.  Bridge locals use the `f_` prefix (finding
B-10); `int_to_str` is local.

## 5. Test matrix (recorded 2026-10-09, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Default PATH | `scripts/port.ps1 -Package xiom.openssl` | **PASS 4/4 x2** -- SKIP classification (bogus soname), `LibreSSL 3.8.2`, SHA-256 digest match, `RAND_bytes` |
| Git for Windows 3.2.4 prepended | same | **PASS 4/4** -- `OpenSSL 3.2.4`, digest match, `RAND_bytes` |
| No libcrypto anywhere | not reproducible on this host (`System32\libcrypto.dll` present); bogus-soname classification runs every suite invocation | SKIP path exercised + code-reviewed |

## 6. Scope

Pilot: library identification, SHA-256 and CSPRNG.  EVP/digests beyond
SHA-256, TLS contexts/BIOs, certificates, and secure memory are Phase 2
(`ROADMAP.md`).  The pre-pilot module (22 static externs) is preserved in
git history.
