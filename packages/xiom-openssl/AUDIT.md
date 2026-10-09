# AUDIT: xiom.openssl

## Status (2026-10-09)

System-library dynamic-loader implementation at 0.2.0. The pre-pilot module
(22 static `extern "C"` declarations + malloc/free + 18 structural wrappers)
required link-time OpenSSL and is preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Decision | **system-library path** (see `SPEC.md` §2) |
| Pin | candidate sonames + entry points + local samples (`SPEC.md` §3) |
| Link model | none at build time; runtime `xiom.ffi.dl` (multi-soname) |
| FFI confinement | all `unsafe` in the root module `openssl.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | default PATH: **PASS 4/4 x2** (LibreSSL 3.8.2); Git 3.2.4 first: **PASS 4/4**; deterministic SKIP classification per run |

## Design notes

- The unversioned `libcrypto.dll` candidate picks up Windows' own
  `System32\libcrypto.dll` (a LibreSSL-based build) on the default PATH --
  the API-compatible subset used by the probe works unchanged, which is a
  useful real-world robustness signal.
- SHA-256 verification is byte-exact inside the module (four little-endian
  u64 words compared to the published digest), so a corrupted or
  mis-linked build fails loudly.
- `OpenSSL_version_num` returns a 32-bit unsigned value on Windows LLP64;
  the extern is typed `UInt32` to avoid reading garbage high bits.
- Bridge locals use the `f_` prefix (finding B-10); `int_to_str` is local.
- No `port.args.json`: pure-XIOM loader.

## Known limitations

- Pilot scope: version + SHA-256 + RAND_bytes; EVP, additional digests,
  TLS/BIOs, certificates and secure memory are Phase 2.
- Only the first four soname candidates are tried; a build under an unusual
  name needs `ossl_load_named`.
- LibreSSL's numeric version identifies LibreSSL, not OpenSSL (documented;
  the suite does not pin a single version string).
