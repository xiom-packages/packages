<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.router / xiom.http helper evaluation (+ xiom.http.status adoption) -- 2026-10-10

Scope: evaluate `xiom.router` 0.1.0 and `xiom.http` 0.1.4 as helpers for
`api.http_service` (the S3 server), under the lane rule: keep the
byte-level pipeline and the strict framing/error model; adopt only where
the gate-visible wire behavior is preserved.

## Verdicts

| Surface | Verdict | Why |
|---|---|---|
| `xiom.http.status.http_status_text` | **ADOPTED** (lane adapter) | Reason phrases we emit are byte-identical; one duplicated table deleted. |
| `xiom.http.status` category predicates (`http_is_success` / `_redirect` / `_client_error` / `_server_error` / `http_status_category`) | available, not used | The service's status logic is structural (specific codes in the error model), not category-based; no call site wants them today. |
| `xiom.router` | **EVALUATED, NOT ADOPTED** | See below. |
| `xiom.http` parser / types / client / cookie / mime / url | **NOT ADOPTED** | Client- and generic-parser-oriented (libcurl client is the package's center of gravity). Our server owns a deliberately strict, fuzz-gated byte pipeline (`probe_http_fuzz`, `probe_http_service`); a generic parser swap would risk the framing/limits/error guarantees for zero operational gain. MIME lookup is unnecessary (two fixed content types). |

### Why `xiom.router` was not adopted

- The service has **7 static routes** with hand-rolled dispatch that is
  small, byte-strict, and pinned by probes (`probe_http_service` routing
  checks, `probe_http_fuzz` framing/property checks). The router's value
  (large tables, `:name` params, Allow-lists) does not apply.
- **Semantics differ where it would matter**: router matching is
  registration-order with 404/405 + `router_allowed_methods`, while the
  service's error model is our JSON `{error, kind, status}` with
  auth-before-routing ordering (an unknown route still requires a key --
  pinned by `probe_service_auth`). Adopting it would be a behavior swap,
  not a helper swap.
- Our `path_segments` edge behavior (trailing/interior slashes, query
  stripping) is gate-pinned; the router's `_split_path` has its own
  documented edge rules. Aligning them would change wire behavior.
- Kept as a **porter-flow reference**: if the lane ever grows a dynamic
  route table, this package is the natural base (same stdlib-only style,
  no I/O, no globals).

### The adoption in detail

- `xiom.toml`: `[dependencies] xiom.http = "0.1.4"`.
- `src/api/http_service.xi`: `use xiom.http.status;` and `status_text` is
  now a 3-line adapter:

  ```xi
  fn status_text(status: Int) -> Str {
    var t = http_status_text(status);
    if t != "Unknown" { return t; }
    if status == 507 { return "Insufficient Storage"; }
    return "Error";
  }
  ```

- **Lane delta (deliberate, documented upstream gap):** the package has
  **no 507 entry** (returns `"Unknown"`) and its fallback differs from
  the lane's `"Error"`. Every code the service emits keeps its
  pre-adoption text byte-for-byte; `probe_http_service` now pins the raw
  `HTTP/1.1 507 Insufficient Storage` status line (it was previously
  un-pinned anywhere), and `probe_package_http` locks the upstream 507
  gap as a tripwire (if upstream adds/changes 507, the probe flags the
  drift for a re-sync). Upstream fix requested via the relay bus
  (`REL-20261010-2002-xvector`, wishlist: add 507).
- New gate `tests/probes/probe_package_http.xi` (5 checks: both
  lane-emitted phrase groups, the 507 gap lock, category predicates and
  mapping) wired into both batteries -- **36 probes** now.
- Wire evidence: `probe_http_service` 41/41 (new 507 line check PASS),
  `probe_service_limits` 27/27, full batteries (suite 171/171 x2 + sbom
  + **36 probes x2** + bench smoke) green on **Windows AND WSL**.

### Re-sync to 0.1.6 (2026-10-11)

Upstream closed the filed gap: `xiom.http` **0.1.6** adds
`507 -> "Insufficient Storage"` and documents the `"Unknown"` fallback
for codes outside the table (wishlist item `REL-20261010-2002-xvector`
fixed by the packages lane; sha256 `bb8a5029...` verified on install,
registry key pinned in the lane-local home).

- `xiom.toml`: `xiom.http = "0.1.6"`.
- `src/api/http_service.xi`: the 507 special-case is **retired**; the
  adapter only keeps the lane's `"Unknown" -> "Error"` fallback delta
  (pre-adoption wire text for codes outside the table).
- `probe_package_http`: the 507 tripwire flipped to pin the **native**
  entry (`http_status_text(507) == "Insufficient Storage"`) plus a new
  check for the documented `"Unknown"` fallback contract (6 checks).
- `probe_http_service` still pins the raw
  `HTTP/1.1 507 Insufficient Storage` status line; wire behavior is
  byte-identical (probe_http_service + probe_service_limits re-run).

### Environment notes

- Builds with the lane-local toolchain emit benign `W001` duplicate-
  module warnings (stdlib present both in the `XIOM_STDLIB` checkout and
  the toolchain's vendored `lib/`; the env checkout wins deterministically).
- `xiom.router`'s SPEC still says "incubating / not published" while the
  registry serves 0.1.0 -- noted for the packages lane (metadata drift).
