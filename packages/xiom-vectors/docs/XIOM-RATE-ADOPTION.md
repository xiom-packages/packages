<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.rate 0.2.0 adoption -- token-bucket internals on the registry package (2026-10-10)

Third registry-package adoption (after `xiom.wal` and `xiom.metrics`),
following the S3 plan's preference ("`xiom.rate` if suitable, else a
minimal token bucket") and the lane's adoption pattern: the service keeps
its `RateLimiter` API and its wire behavior (429 path + counters), and the
token-bucket mechanics now come from `xiom.rate` 0.2.0.

## Status

- **Consumed:** `xiom.rate` **0.2.0** is installed on Windows
  (`XIOM_HOME/packages/xiom-rate-0.2.0`) and WSL
  (`~/.local/share/xiom/packages/xiom-rate-0.2.0`); the registry signing
  key is pinned from the `xiom.wal` adoption.
- **Wired:** `xiom.toml` gained `[dependencies] xiom.rate = "0.2.0"`.
- **Gated:** new `tests/probes/probe_package_rate.xi` (14 checks: bucket
  drain/refill/remainder carry/rate 0/clamping/retry/cost, fixed window,
  keyed bucket + keyed window layers; wired into both CI batteries --
  **35 probes** now). The lane-side gates (`probe_service_auth` 24 checks,
  `probe_metrics` 24 checks) are unchanged and stay green: every
  gate-visible boundary matches the pre-adoption behavior.
- **Surface unchanged for consumers:** `RateLimiter`, `rate_limiter_new`,
  `rate_limiter_disabled`, `rate_limiter_allow` keep their names and
  signatures; `ServiceState.rate` and `http_service_handle_state` are
  untouched.

## Surface map (what the swap changed)

| Axis | Pre-adoption lane (S3) | Now (xiom.rate-backed) | Wire impact |
|---|---|---|---|
| Representation | lane struct `{enabled; capacity; refill_per_sec; tokens; last_ms}` | lane wrapper `{enabled; bucket: TokenBucket}` (package value type) | none |
| Construction policy | `capacity < 1` -> disabled limiter | identical (the wrapper keeps the disabled policy; the package's own constructor clamps to >= 1 for enabled buckets) | none |
| Refill truncation | whole tokens per call, **remainder discarded** (`last_ms = now_ms`) | package truncation policy: unearned milliseconds are **carried**; `last_ms` advances only by the milliseconds the granted tokens are worth | none at gate boundaries; strictly more accurate at sub-second call rates |
| Clamp | tokens capped at capacity | package ensures `tokens <= capacity` (saturation clamp) | none |
| Lazy start | `last_ms = -1` set on first allow | bucket constructed full with `last_ms = 0`; the first allow sees a saturated bucket either way | none (first call always admits) |
| Rate 0 / negative rate | never refills | package clamps negative to 0 and never refills at 0 | none |
| Retry hints | not used (`429` without `Retry-After`) | `rate_bucket_retry_after_ms` available for a future header | none today |

### Behavioral delta (documented, gated)

The pre-adoption lane limiter consumed the whole elapsed span on every
call and discarded sub-token remainders, so calls arriving faster than
`1000 / refill_per_sec` ms **never** refilled. The package carries the
remainder: e.g. capacity 1 at 1 token/s, calls at 0/500/1000 ms admit,
deny, admit (a token lands at exactly +1000 ms). The PACKAGE gate pins the
carried-remainder case (`probe_package_rate`: "fractional refill carried
exactly"). The lane probes pin the unchanged boundaries (capacity drain,
rate 0, whole-second refill) -- this is an accuracy fix, not a
compatibility break: no existing gate or wire assertion changed.

## Deliberately not adopted (this slice)

- **Fixed-window layer (`WindowLimit`)** -- the service uses a single
  burst+refill bucket; a window limiter is a different policy and nothing
  in the S3 surface asks for it.
- **Keyed layers (`KeyedBuckets`/`KeyedWindows`)** -- per-API-key
  limiting is a plausible S3 extension (the package makes it a small
  slice: key by the presented API key, `rate_keyed_*`, prune on auth
  rotation). Not adopted now; noted as a follow-up candidate.
- **`Retry-After` response header** -- `rate_bucket_retry_after_ms` gives
  the value; adding the header changes the wire contract and deserves its
  own slice + probe updates.

## Evidence

- Lane gates after the swap: `probe_service_auth` 24/24 and
  `probe_metrics` 24/24 green (rate checks: capacity 2 no-refill, 1/s
  refill, service 429 + counter).
- Package gate: `probe_package_rate` 14/14 green, first build.
- Full batteries (the `feat(deps)` slice commit on 2026-10-10): suite
  171/171 x2 + sbom + **35 probes x2** + bench smoke, Windows AND WSL,
  ALL GATES GREEN (see `SESSION.md` for the wrap record).

## Follow-ups

1. `xiom.router` / `xiom.http` helper evaluation for `api.http_service`
   (the byte-level pipeline and wire contract stay; evaluate only the
   helper surface).
2. Optional S3 extension slices: per-API-key limiting via `KeyedBuckets`;
   `Retry-After` on 429.
3. The compiler re-pin to v0.64.3 (released 2026-10-10) runs as its own
   pass after this adoption wrap; XVC-C-13/C-14 verdicts go to the
   release-check rows.
