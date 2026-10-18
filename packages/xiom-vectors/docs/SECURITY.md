<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Security -- xiom-xvector (v1.0 programme, M-S4)

Threat model, secure defaults, and the evidence that backs them. Every
claim here names its gate (probe / script / doc). This lane never claimed
TLS, network isolation, or process sandboxing -- those are deployment
concerns (below), and the HTTP module is deliberately transport-agnostic
until the stdlib `xiom.net` proof lands (C-PULSE-02).

## 1. Assets

| Asset | Where | Notes |
|---|---|---|
| Vector + payload data | in-memory engine; WAL checkpoint; sealed segment files | integrity + availability |
| Collection registry (names/configs/params) | in-WAL manifests; `xvector-manifest` file | integrity (drives recovery) |
| API keys (service mode) | process environment (`XVECTOR_API_KEYS`) or programmatic `ServiceAuth` | confidentiality |
| Request/response bytes | `api.http_service` pipeline | input validation surface |
| Build/verification evidence | `out/` logs, `out/sbom.json` | developer trust |

## 2. Trust boundaries

1. **Embedded API (trusted process).** The XIOM facade (`xiom.vector.engine`)
   is a library call: the caller is inside the trust boundary, authentication
   is off, and abuse resistance only needs to be "no accidental foot-guns".
2. **HTTP service path (untrusted input).** `api.http_service` receives raw
   request bytes. Everything from the socket (future) or the caller is
   treated as untrusted: parsed strictly, bounded, authenticated when
   enabled, and rate-limited.
3. **Compiler/platform (trusted TCB).** The XIOM compiler + stdlib own all
   FFI; the project tree contains **no `unsafe`** (gated), and no
   third-party registry dependencies (SBOM).
4. **Operator/owner (trusted).** Config, keys, and file paths come from the
   operator. A wrong path/key is an operator error, not an attacker
   capability, until the network adapter exists.

## 3. Secure defaults

| Default | Value | Rationale / evidence |
|---|---|---|
| Auth | **disabled** in embedded mode | no ambient attacker; service adapter enables it (`probe_service_auth`) |
| API keys | none registered; auth enables on first valid key | explicit opt-in; keys validated 8..128 `[A-Za-z0-9_.-]` |
| Key comparison | constant-time across all keys | `xiom.crypto.mac.constant_time_eq` via `auth_lookup` |
| Scopes | least privilege per route: read < write < admin; `/health` public | `required_scope`; 401/403 matrix in `probe_service_auth` |
| Request size | 64 KiB (`max_request_bytes`) | checked before parsing; 413 (`probe_service_limits`) |
| `top_k` / batch / dim caps | 1000 / 256 / 1024 | 400 named limits / 413; boundaries tested |
| JSON nesting | **64 levels**, pre-parsed guard `json_depth_ok` | M-S4 finding: unbounded nesting overflows the stack (see below) |
| Rate limiting | disabled by default; token bucket when enabled | capacity + refill/sec; 429 `rate_limited` |
| Errors | `{error, kind, status}`; no stack traces or internals | stable kinds mapped from `CoreError` |
| Shutdown | `http_service_shutdown` = drain + whole-file WAL checkpoint | false on unwritable path, never a crash |
| Paths/names | collection names `[A-Za-z0-9_.-]` (1..64); ids are Ints | prevents layout/path surprises in files |

## 4. Threats and controls

| Threat | Control | Gate |
|---|---|---|
| Malformed/random input crashes or hangs the parser | strict CRLF/Content-Length framing; every failure is a well-formed HTTP response | `probe_http_fuzz` (2500 seeded/random inputs, well-formedness + bounding) |
| **Stack exhaustion via deep JSON nesting** (found in S4) | `json_depth_ok(body, 64)` pre-scan rejects deeper payloads with 400 before `json_parse`; the stdlib gap is filed in `docs/STDLIB-WISHLIST-XVECTOR.md` | `probe_http_fuzz` `t-unbalanced`/`t-nest` cases |
| Oversized requests / batches | size + batch limits (413), evaluated before/at routing | `probe_service_limits` |
| Header floods / 30 KB header lines | bounded per-line scans; no quadratic joins | `probe_http_fuzz` flood cases |
| Slow-path abuse (many sequential requests) | token bucket RateLimiter -> 429 | `probe_service_auth` |
| Unauthorized access / privilege escalation | API keys + ordered scopes; 401/403; `/health` only public | `probe_service_auth` |
| Key leakage by timing | constant-time compare over all keys | `auth_lookup` + stdlib comparator |
| Credential leakage in logs/errors | keys never echoed; error bodies carry only stable kinds/messages | `probe_service_limits` error model |
| Data corruption on disk | torn-tail-safe prefix loaders (WAL/manifest/segment), atomic temp+rename writers, kill-recovery prefix exactness | `probe_wal_file`, `probe_manifest_file`, `probe_segment_file`, `probe_kill_recovery` |
| Silent codec drift | strict decoders; fuzz gates over codecs | `probe_fuzz_codecs`, `probe_reference_oracle` |
| Unsafe/FFI in project code | zero `unsafe` in `src/` | `scripts/sbom.ps1` / `sbom.sh` (CI gate) |
| Third-party dependency risk | none: compiler + stdlib only; SBOM emitted per battery | `out/sbom.json` |

## 5. Dependency pinning + SBOM

- Project dependencies: **none** (registry `[dependencies]` empty in
  `xiom.toml`; stdlib + inline core substrate only). C-PULSE-02 caveat:
  registry deps are not yet mapped by the compiler, so keeping zero is also
  the only sound state today.
- Toolchain pins: compiler **v0.64.2** (tag `c51170a6`), stdlib lane HEAD
  recorded per SBOM run, packages lane pin recorded in `SESSION.md`.
- `scripts/sbom.ps1` and `scripts/sbom.sh` emit `out/sbom.json`:
  project name/version, compiler version, stdlib pin, registry-dependency
  list, the `unsafe` count (must be 0), and one `{path, sha256}` entry per
  `src/**/*.xi` module (43 modules at the S4 wrap). Both CI batteries run
  the SBOM + unsafe gate; a non-zero `unsafe` count fails the battery.

## 6. `unsafe` audit statement

The project tree contains **no `unsafe` blocks, no FFI declarations, and no
raw pointer code** (verified: 0 matches for `unsafe` under `src/`, enforced
by the SBOM gate). All syscalls, allocation, and I/O go through the
compiler/stdlib that the platform owns. The lane's compiler findings and
workarounds are tracked in `docs/COMPILER-FINDINGS-XVECTOR.md` and never
require unsafe constructs.

## 7. Out of scope / known gaps (honest list)

- **No network adapter yet**: `api.http_service` is a byte-level pipeline;
  binding the stdlib `xiom.net` server is gated on the C-PULSE-02 proof.
  TLS, mTLS, and IP allowlists belong to the deployment (reverse proxy or
  the future adapter).
- **No encryption at rest**: WAL/segment files are plain text; disk
  encryption is a deployment concern.
- **fsync gap**: durability bounds depend on the stdlib fsync chain
  (`docs/STDLIB-WISHLIST-XVECTOR.md`); acknowledged `wal_persist` writes are
  atomic but not yet fsync-grade.
- **Stdlib JSON depth cap**: till the stdlib adds one, the HTTP edge guard
  is the only protection for callers that hand untrusted bodies to
  `json_parse` outside this service.
- **Rate limiter scope**: one process-local bucket; it is a backstop, not a
  distributed quota.

## 8. Reporting and process

- Threat-model changes land with the slice that changes behavior (this doc
  is updated in the same commit; the checklist row S4 names the gates).
- New abuse cases belong in `tests/probes/probe_http_fuzz.xi` (deterministic
  seeds; add a targeted case plus a phase `mark()` so a future crash is
  pinpointed by `out/fuzz_mark.txt`).
- New findings against the platform (compiler/stdlib) are filed in
  `docs/COMPILER-FINDINGS-XVECTOR.md` / `docs/STDLIB-WISHLIST-XVECTOR.md`
  and relayed through the lane relay docs.
