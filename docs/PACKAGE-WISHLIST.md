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
| `xiom.router` | **APPROVED-NEW** (ops delta) | exact + path-parameter routes, method matching, aggregated 404/405, deterministic first-match; stdlib-only. |
| `xiom.session` | **APPROVED-NEW** (ops delta) | server-side store: id gen via `xiom.crypto`, TTL/expiry, memory backend, cookie binding, rotate-on-login; deps `xiom.cookie` + `xiom.crypto`. |
| `xiom.jwt` v0.2 (HS256) | **EXTEND** `xiom.jwt` 0.1.1 -> 0.2.0 | HS256 sign/verify on top of existing structural decode: alg allowlist, `exp`/`nbf`, constant-time MAC compare; deps `xiom.crypto` (HMAC links under `XIOM_RUNTIME_DIR`; the candidate archive may remove that requirement). |
| `xiom.ratelimit` | **MERGE-INTO** `xiom.rate` 0.1.2 | `xiom.rate` already ships token bucket + fixed window + `retry_after` with explicit clocks. Add a keyed layer (per-IP/route/user) and let the 429 envelope live in `xiom.http.middleware`. `xiom.rate` -> 0.2.0. |
| `xiom.metrics` | **EXTEND** `xiom.metrics` 0.1.2 -> 0.2.0 | The existing package's non-goals explicitly exclude labels/dimensions and scrape/export formats. Add labels + a Prometheus text exposition module (`xiom.metrics.prometheus`) + scrape helper inside the same package (keeps one metrics name in the ecosystem). |
| `xiom.static` | **APPROVED-NEW** (ops delta) | MIME via stdlib `xiom.net.mime`; ETag/Last-Modified, Range, path-traversal guard, Cache-Control policy. |
| `xiom.http.middleware` | **APPROVED-NEW** (ops delta, after router types) | composable chain over request/response envelopes: request-id, access log, recover-to-500, CORS, CSRF helpers. |

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
- PULSE positives to keep: `xiom.cookie` 0.1.1 and `xiom.jwt` 0.1.1 both 8/8 consumer probes.
