<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.metrics 0.2.0 adoption -- observability internals on the registry package (2026-10-10)

Second registry-package adoption (after `xiom.wal`), following the lane's
declared intent (`docs/PACKAGE-WISHLIST-XVECTOR.md`): the
`observability.metrics` module keeps its **exported surface** and its
**wire output**, and its internals now run on `xiom.metrics` 0.2.0. The
same slice moved the engine's stat counters onto the package and retired
the core shim's local `Counter` (forced by a new compiler finding,
XVC-C-14; see below).

## Status

- **Consumed:** `xiom.metrics` **0.2.0** is installed on Windows
  (`XIOM_HOME/packages/xiom-metrics-0.2.0`) and WSL
  (`~/.local/share/xiom/packages/xiom-metrics-0.2.0`); the registry signing
  key is already pinned from the `xiom.wal` adoption (`xiom pkg trust`,
  fingerprint `4f:3b:47:f3:ae:17:b1:3c`).
- **Wired:** `xiom.toml` gained `[dependencies] xiom.metrics = "0.2.0"`
  (the dependency-root resolver maps installed package roots; C-PULSE-02
  resolved in v0.64.2).
- **Gated:** new `tests/probes/probe_package_metrics.xi` (12 checks:
  counter/gauge/histogram math over the lane's bounds, stats, reset, the
  labeled registry, Prometheus text exposition, content type; wired into
  both CI batteries -- **34 probes** now) plus the re-gated
  `tests/probes/probe_metrics.xi` (24 checks; the package-stats check
  asserts min/max/mean, which exist only in the package layer).
- **Uniform counters:** `VectorEngine.upserts/deletes` are package
  `Counter`s and the core shim's `Counter` type is **retired** -- one
  `Counter` type in the program (XVC-C-14, below).
- **Wire contract unchanged:** `GET /metrics` output is byte-identical
  (same counters, same `_bucket`/`+Inf`/`_sum`/`_count` lines, same
  p50/p95/p99 lines, same live gauges); the `probe_metrics` expectations
  were extended, not changed.

## Surface map (what the swap changed)

| Axis | Pre-adoption lane (M-O) | Now (xiom.metrics-backed) | Wire impact |
|---|---|---|---|
| Histogram representation | lane struct `{bounds; counts; total_ms; observations}` | package `Histogram {bounds; counts; count; sum; min; max}` behind lane accessors (`histogram_count/_sum/_min/_max/_mean/_bucket_len/_bucket_count/_bounds_len/_bound`) | none |
| Bucket bounds | 1/5/10/50/100/500/1000 ms + `+Inf` | identical (lane passes its bounds to `metric_histogram_new`; the layout stays a lane decision) | none |
| Observe semantics | first-fit bucket + clamp negative to 0 | package first-fit + lane clamp in `histogram_observe` | none |
| Percentiles | lane `histogram_percentile` (rank = ceil(p/100 x n), +Inf bucket reports last bound + 1) | kept lane-owned (package SPEC: no percentile estimation) | none |
| Prometheus histogram block | rendered in `http_service.render_hist_lines` | moved into the lane as `histogram_render_lines` (consumers no longer name the value types) | none (byte-identical) |
| Service counters | shim `Counter {name; value}` with names | package `Counter {value}` via lane seam `service_counter_inc/_value`; render uses the existing literal names | none |
| Counters elsewhere | engine stats on shim counters | engine stats on package counters (`metric_counter_new/_inc`); shim `Counter` deleted | engine counters are write-only today (no reads outside the suite mirror) |
| Gauges | rendered live from the engine | unchanged (package `Gauge` is available but not stored) | none |
| Log ring | lane JSON ring | lane-owned (package has no log ring) | none |
| Labels/Registry/exposition | not present | **evaluated, not adopted this slice** (see below) | none |

## Module-shape note (probed before the swap)

The lane module is `xiom.vector.observability.metrics`, whose last segment
collides with `xiom.metrics`. Verified on v0.64.2 before committing to the
design: the **in-project** module imports `xiom.metrics` and calls the
package functions unqualified -- compiles and runs green (same shipped
shape as PULSE's `xiom.pulse.metrics`). A standalone single-file scratch
unit with a colliding module name (`module xvshadow.metrics` in `out/`)
failed T001 undefined-variable, consistent with the open bindings-4 /
C-PULSE-12 single-file repros. Lane rule since: package calls only from
source-root modules; consumers import **only** the lane module (it is the
seam that names the package types).

## XVC-C-14 -- why the shim Counter had to go

Wiring the package put **two same-named struct types** (`shim.Counter` +
`metrics.Counter`) in one program; the first full build clang-rejected a
store because `VectorEngine`'s fields got the package layout while
`engine_new` produced shim values (all XIOM-level checks had passed).
Minimal 4-module repro pinned at `docs/repro/xv-counter-type-shadow/`:
struct-field layouts resolve by **short name** across modules, one side
takes over the other (silent when the layouts are compatible). Adopted
workaround: one type name, one type -- engine counters on `xiom.metrics`,
shim `Counter` deleted. Filed for the compiler lane (relay Addendum 10).

## Deliberately not adopted (this slice)

- **Labeled registry + `metric_exposition` wire:** the service renders its
  own Prometheus text with lane-specific extras (p50/p95/p99 percentile
  lines). The package's exposition has no percentiles and different
  type/label spellings -- switching would change the wire contract that
  `probe_metrics` gates. Revisit as a presentation slice (H follow-up),
  not as an observability-internals swap.
- **Storing gauges:** collections/points_active/lsn are rendered live from
  the engine at scrape time; no stored gauge state to migrate.

## Evidence

- Batteries after the swap (the `feat(observability)` adoption commit on
  2026-10-10):
  suite 171/171 x2 + sbom (44 modules, unsafe=0) + **34 probes x2** +
  bench smoke, **Windows AND WSL**, ALL GATES GREEN
  (`scripts/ci.ps1` / `scripts/ci.sh`). `probe_package_metrics` 12/12 and
  `probe_metrics` 24/24 on both platforms.
- Engine path unaffected: `probe_engine_hnsw` (24 checks) and the service
  probes re-run green with package counters on `VectorEngine`.

## Follow-ups

1. `xiom.rate` 0.2.0 adoption (next slice): token-bucket internals behind
   the S3 `RateLimiter` API; verify window semantics against
   `probe_service_auth` before swapping.
2. `xiom.router` / `xiom.http` helper evaluation for `api.http_service`
   (byte-level pipeline stays).
3. Presentation evaluation: the package exposition + labels if the
   exposition slice happens (dashboard/alert wiring is the H-phase
   remainder).
4. Porter flow: the shim now carries only error/ids/contracts; the
   metrics part of the `xiom.core` mapping is satisfied by this adoption.
