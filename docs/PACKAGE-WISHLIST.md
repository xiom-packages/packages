<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Packages-lane wishlist (intake + triage)

Source: PULSE consumer lane relay 2026-10-05
(`E:\xiom-projects\xiom-pulse\docs\PACKAGE-WISHLIST-PULSE.md`, pin v0.63.1,
stdlib `15cb889`). Internal findings are appended here as they are triaged.
Status legend: **IN-FIX** / **APPROVED-NEW** / **EXTEND** / **MERGE-INTO** / **DECIDED**.

## 1. Consumer defects (fix before new packages)

| Item | Triage | Detail |
|---|---|---|
| `xiom.http` 0.1.0 parser (a/b/c) | **FIXED + PUBLISHED** (0.1.1, `eco-v0.1.59`, run `37335349031`; task `ses_ef3474d7...`, 2026-10-05) | (a) missing `use xiom.http.types;` in `src/parser.xi` -> consumer T001s; (b) bare `&mut Int` cursor reads yield the address on v0.63.1 (compiler C-PULSE-04) -> `Unexpected end of request line pos=372324169712`; (c) zero parser tests. Fix = explicit import + `*pos_ref` deref + parser KATs (request/response/headers/malformed). Publish as a single-package hotfix (0.1.1) because registry consumers are blocked. |
| `xiom.http` `src/server.xi` 32-line shell | **DECIDED + DOCUMENTED** (README server-stub section in 0.1.1) | No accept loop/routing; PULSE owns its server today. Owning HTTP serving would need sockets/threads and is deferred to a later scoped decision (possibly 0.2 with `xiom.router`). |

## 2. Proposed packages (PULSE intake, triaged against the registry)

| Proposed | Triage | Notes |
|---|---|---|
| `xiom.router` | **DONE + PUBLISHED** (0.1.0, `eco-v0.1.62`, run `37350671893` rerun SUCCESS after the ops scope extension; feat `67fdb45d`, live-verified) | exact + path-parameter routes, method matching, aggregated 404/405, deterministic first-match; stdlib-only. |
| `xiom.session` | **APPROVED-NEW** (ops delta) | server-side store: id gen via `xiom.crypto`, TTL/expiry, memory backend, cookie binding, rotate-on-login; deps `xiom.cookie` + `xiom.crypto`. |
| `xiom.jwt` v0.2 (HS256) | **DONE + PUBLISHED** (0.2.0, `eco-v0.1.60`, run `37338296689`; task `ses_ef3387e5...`) | HS256 sign/verify on top of existing structural decode: alg allowlist, `exp` required / `nbf` optional, constant-time MAC compare; deps `xiom.crypto` (HMAC links under `XIOM_RUNTIME_DIR`; the 0.64.0 archive should remove that requirement). |
| `xiom.ratelimit` | **DONE + PUBLISHED** -- keyed layer in `xiom.rate` (0.2.0, `eco-v0.1.61`, run `37340030888`; task `ses_ef329199...`) | `xiom.rate` 0.2.0 adds per-IP/route/user keyed buckets and windows plus prune hooks; the 429 envelope lives in `xiom.http.middleware`. |
| `xiom.metrics` | **EXTEND** `xiom.metrics` 0.1.2 -> 0.2.0 | The existing package's non-goals explicitly exclude labels/dimensions and scrape/export formats. Add labels + a Prometheus text exposition module (`xiom.metrics.prometheus`) + scrape helper inside the same package (keeps one metrics name in the ecosystem). |
| `xiom.static` | **APPROVED-NEW** (ops delta) | MIME via stdlib `xiom.net.mime`; ETag/Last-Modified, Range, path-traversal guard, Cache-Control policy. |
| `xiom.kv` | **APPROVED-NEW** (ops delta; queued last) | Embedded pure-XIOM log-structured KV: append-only segments, crash-safe reopen, tombstones, compaction, optional snapshot. PULSE Step 3 needs a durable local store; `xiom.bolt` is read-only, `xiom.sql` unpublished. Build after middleware/session/static. |
| `xiom.http.middleware` | **APPROVED-NEW** (ops delta, after router types) | composable chain over request/response envelopes: request-id, access log, recover-to-500, CORS, CSRF helpers. PULSE order: middleware NEXT, then session. |

## 3. Build order (agreed with PULSE's suggested sequence)

1. `xiom.http` 0.1.1 hotfix (IN-FIX).
2. `xiom.jwt` HS256 (0.2.0) -- unblocks PULSE Step 2 auth.
3. `xiom.router` + `xiom.http.middleware` (PULSE Step 2 skeleton).
4. `xiom.session`, `xiom.rate` keyed layer, `xiom.metrics` 0.2, `xiom.static`.

## 4. Process requirements

- The four new names (`router`, `session`, `static`, `http.middleware`) require the ops scope
  enumeration to be confirmed BEFORE the allowlist delta is appended (policy).
- New packages go through growth waves: port x2 + trap-14, `incubating` records, publish.
- Extensions are minors: `jwt` 0.2.0, `metrics` 0.2.0, `rate` 0.2.0.
- PULSE consumes the registry only; each README gets a 3-line consumer snippet (its explicit ask).
- PULSE positives to keep: `xiom.cookie` 0.1.1 and `xiom.jwt` 0.1.1 both 8/8 consumer probes;
  after the wave: `xiom.jwt` 0.2.0 (HS256) adopted/verified, `xiom.cookie` 0.1.1 verified,
  `xiom.rate` 0.2.0 recorded for its hardening slice (PULSE relay 2026-10-05).
- PULSE scope confirmation (2026-10-05): `router` first (replaces their router), then
  `session` (replaces their store), `static` and `http.middleware` as later slices; the
  registry allowlist delta remains the owner's call.
- PULSE adoption round (2026-10-05 v2): `xiom.router` 0.1.0 adopted cleanly (probe 8/8,
  suites x2 + smoke 44/44; their `src/router.xi` is now a thin wrapper); `xiom.jwt` 0.2.0
  adopted (probe 11/11 + 6 app checks); `xiom.rate` 0.2.0 recorded; PULSE order now
  **middleware next → session → rate adoption → metrics 0.2 (latency histograms) → static
  → kv**; `metrics` 0.2 must serve latency histograms (bounds preset added to the brief).
- PULSE cross-ref **C-PULSE-02** (installed packages absent from the compiler module
  catalog; `xiom.toml` source-roots workaround) -- same class as the packages-lane
  observation that raw `--run` inside a package dir can fail the catalog stage while
  `port.ps1`/the repo-root wrapper compile the same files.
