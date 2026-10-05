# xiom-packages/packages -- Session Handoff

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

**Written:** 2026-10-05 (08:20Z), by the main/debug session (v0.63.0
pin; hardening batches #1-#5 DONE + PUBLISHED across
`eco-v0.1.44`-`eco-v0.1.48` -- 20 stable packages with runtime
contracts + SPEC contract inventories; thermo alone contributes 19
Z3-proven clauses, stl 3, crc 5; Float64 contract expressions verified
working (robotics); 259 stable packages still at zero clauses; grpc
still red on v0.63.0 -- numeric match arms stay blocked until the next
pin; graphql 9/10). Check `git log -1 --format=%h %s` before starting.

## 0. Current state + next-session prompt (read this first)

**STATE AT 2026-10-05 08:20Z (read this first):**
- **`eco-v0.1.48` PUBLISHED (`37281930706` SUCCESS):** hardening batch
  #5 -- `xiom.alerting` 0.1.2 (21/21), `xiom.robotics` 0.1.2 (19/19,
  first Float64 contract expressions), `xiom.thermo` 0.1.2 (24/24,
  **19 Z3-proven**, verifier rc=0), `xiom.audit` 0.1.2 (23/23); all
  stable, x2 green on v0.63.0, live-verified. No allowlist delta, no
  rate window; guard 499 allowlisted / 459 ready / 40 grandfathered /
  0 failures.
- **Hardening progress:** batches #1-#5 = 20 packages published; 259
  stable packages remain at zero clauses. Batch #6 candidates:
  `quantum`, `spectroscopy`, `relativity`, `physics`, `particle`,
  `collation`, `fixed`, `tracing`, `finance`, `option`, ...
- **Verifier tooling on v0.63.0:** proven counts now meaningful --
  exact-formula/definitional clauses discharge (thermo 19/23, crc 5/11,
  stl 3, alerting 1, audit 1); the runtime evaluator still mis-checks
  tuple-component and payload-length-vs-parameter clauses (keep out of
  sources; COMPILER-FINDINGS 2026-10-05).
- **Open findings (compiler-gated; do NOT re-bisect):** grpc
  `Vec[(Str,Str)]` crash/hang (red on v0.63.0), graphql 9/10
  enum-payload in-situ. Compiler main has UNRELEASED fixes -- C001
  root cause `4bf8cf1e` and verifier UNKNOWN handling `6f34e1f0` --
  when the next release lands: re-pin, then re-test grpc/graphql first.
- **Next:** hardening batch #6, or the parked grpc/graphql pair on the
  next pin; next tag `eco-v0.1.49`.

**--- Older state below (history) ---**

**STATE AT 2026-10-05 08:00Z (history):**
- **`eco-v0.1.47` PUBLISHED (`37279267599` SUCCESS):** hardening batch
  #4 -- `xiom.metrics` 0.1.2 (23/23), `xiom.retry` 0.1.2 (21/21),
  `xiom.signal` 0.1.2 (27/27), `xiom.stl` 0.1.2 (17/17); all stable,
  x2 green on v0.63.0, live-verified. Contracts: exact counter/gauge/
  histogram accounting; retry policy/state/circuit invariants; signal
  result-length and zero-crossing bounds; stl byte-range and
  binary-size (3 Z3-proven). No allowlist delta, no rate window; guard
  499 allowlisted / 459 ready / 40 grandfathered / 0 failures.
- **Hardening progress:** batches #1-#4 published; 263 stable packages
  remain at zero clauses. Batch #5 candidates: `quantum`, `alerting`,
  `spectroscopy`, `robotics`, `relativity`, `physics`, `thermo`,
  `audit`, `particle`, `collation`, `fixed`, `tracing`, ...
- **Open findings (compiler-gated; do NOT re-bisect):** grpc
  `Vec[(Str,Str)]` crash/hang (red on v0.63.0), graphql 9/10
  enum-payload in-situ. Compiler main has UNRELEASED fixes -- C001
  root cause `4bf8cf1e` and verifier UNKNOWN handling `6f34e1f0` --
  when the next release lands: re-pin, then re-test grpc/graphql first.
- **Next:** hardening batch #5, or the parked grpc/graphql pair on the
  next pin; next tag `eco-v0.1.48`.

**--- Older state below (history) ---**

**STATE AT 2026-10-05 07:40Z (history):**
- **`eco-v0.1.46` PUBLISHED (`37277579364` SUCCESS):** hardening batch
  #3 -- `xiom.bmp` 0.1.2 (18/18), `xiom.rate` 0.1.2 (19/19), `xiom.lru`
  0.1.2 (16/16), `xiom.tokenizer` 0.1.2 (24/24); all stable, x2 green
  on v0.63.0, live-verified. Contracts: bmp row/pixel/header bounds,
  rate bucket/window invariants, lru capacity/accounting, tokenizer
  count bounds; all solver-unknown (0 refuted). No allowlist delta, no
  rate window; guard 499 allowlisted / 459 ready / 40 grandfathered /
  0 failures.
- **Hardening queue:** 267 stable packages remain at zero clauses;
  batch #4 picks the next smallest (`quantum`, `alerting`,
  `spectroscopy`, `robotics`, `relativity`, `physics`, `stl`,
  `thermo`, `metrics`, ...). Reuse the batch-#3 recipes: capacity and
  counter invariants, count bounds, result ranges; avoid
  tuple-component and payload-length-vs-parameter clauses (runtime
  evaluator artifact, COMPILER-FINDINGS 2026-10-05).
- **Open findings (compiler-gated; do NOT re-bisect):** grpc
  `Vec[(Str,Str)]` crash/hang (red on v0.63.0), graphql 9/10
  enum-payload in-situ; compiler main has UNRELEASED fixes -- C001
  root cause `4bf8cf1e` and verifier UNKNOWN handling `6f34e1f0` --
  wait for the next pin, then re-test grpc/graphql first.
- **Next:** hardening batch #4, or the parked grpc/graphql pair when a
  release with the C001 fix lands; next tag `eco-v0.1.47`.

**--- Older state below (history) ---**

**STATE AT 2026-10-05 06:40Z (history):**
- **`eco-v0.1.45` PUBLISHED (`37272833834` SUCCESS; duplicate trigger
  `37272835135` cancelled):** hardening batch #2 -- `xiom.crc` 0.1.2,
  `xiom.cobs` 0.1.2, `xiom.varint` 0.1.2, `xiom.roman` 0.1.2 (all
  stable; x2 green on v0.63.0; live-verified on the registry).
  Contracts machine-checked: crc 5/11, varint 2/10, roman 1/13, cobs
  0/12 Z3-proven (v0.63.0 emits valid SMT now); unasserted properties
  recorded per package. No allowlist delta, no rate window. Guard: 499
  allowlisted / 459 ready / 40 grandfathered / 0 failures.
- **Runtime contract-evaluator artifact (new tooling finding,
  2026-10-05, `docs/COMPILER-FINDINGS.md`):** spurious runtime
  violations for (a) tuple-component access `result.value.1` on
  `Result[(Int,Int),Str]`, (b) `Result[Vec[UInt8],Str]` payload-length
  vs parameter-length; both properties are true (the cobs bound was
  brute-forced `bad=0` over 65,792 frames) -- clauses omitted and
  documented unasserted instead.
- **Hardening queue:** 268 stable packages remain at zero clauses
  (grandfathered set); pick batch #3 with `scripts/contract-coverage.ps1`.
- **Open findings (compiler-gated; do NOT re-bisect):** grpc
  `Vec[(Str,Str)]` crash/hang (still red on v0.63.0 -- numeric match
  arms stay blocked), graphql 9/10 enum-payload in-situ; `crypto-link`
  and float bitcast remain stdlib-lane opens.
- **Next:** parked grpc/graphql when the compiler lane lands fixes,
  hardening batch #3, or new growth; next tag `eco-v0.1.46`.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 19:10Z (history):**
- **v0.63.0 PINNED (released 2026-10-04 16:34Z):** official
  `xiom-0.63.0-windows-x64.zip`, SHA256 `689881f4...` verified against
  the published SHA256SUMS; deployed into `%LOCALAPPDATA%\xiom.new`
  (`xiom --version` = v0.63.0); `COMPILER_VERSION` bumped; `repin` 514
  records (`e8af6291`); fleet sweep **460/460** (the `l10n-unicode`
  watchdog clip re-ran PASS 24/24 at 42s); all 460 runs re-pointed to
  `fleet-sweep:v0.63.0` (`57fc5a05`). Guard: **499 allowlisted / 459
  ready / 40 grandfathered / 0 failures**.
- **Release-response probes (v0.63.0):** full 18-bundle index re-run --
  byte-at-128, const-tables, const-match, arity, mut-int, str-vec-eq,
  loop-cse, sign-bit, generic-fnptr, struct-field-vec, vec-struct all
  green; **`uninit-local` moved to FIXED** (standalone `bad=0`; graphql
  no longer hangs).
- **grpc still RED on v0.63.0 (compiler lane predicted this):**
  `probe_suite_min.xi` crashes `0xC0000005`; `probe_direct.xi` hangs --
  **numeric match arms stay blocked in `grpc.xi`**; `xiom.grpc` stays
  unpublished. graphql still 9/10 (enum-payload in-situ);
  `crypto-link` and float bitcast remain stdlib-lane opens.
- **No API/behavior breaks observed on the new pin** (timing-only
  changes, as announced).
- **Next:** parked grpc/graphql (compiler-gated), further hardening
  (the grandfathered stable set), or new growth; next tag
  `eco-v0.1.45`.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 16:00Z (history):**
- **`eco-v0.1.44` PUBLISHED (run `37214746199` SUCCESS):** first
  hardening batch -- `xiom.uuid` **0.1.2**, `xiom.csv` **0.1.2**,
  `xiom.bson` **0.1.3**, `xiom.ttl` **0.1.2**, all `stable`, x2 green on
  v0.62.4, live-verified on the registry; runtime contracts + SPEC
  contract inventories (`xiom-verify` solver-unproven -- tooling gaps
  recorded per package). No allowlist delta, no rate window. Registry:
  459 packages + 2 infra = 461 entries; guard 499 allowlisted / 459
  ready / 40 grandfathered / 0 failures.
- **`l10n-unicode` record fix (`8d026842`):** the `stable` stage flip
  from `2d35e3c8` was reverted to `incubating` -- README and the live
  registry both say incubating and the package carries zero contracts
  (stable gate G4 unmet). Slow-suite note kept: watchdog-marginal (45.6s
  idle, 96-107s under load), raise the sweep timeout at next touch. A
  real promotion needs a contracts pass first.
- **Concurrent-lane protocol (added after this handoff ran twice):**
  claim a batch in SESSION.md (LIVE CLAIM block) before editing shared
  packages; check `git log -1 --format=%h %s` before every commit; the
  publish gate is approved per tag by the acting lane.
- **Open findings (compiler-gated; do NOT re-bisect):** graphql 9/10
  enum-payload in-situ; grpc `Vec[(Str, Str)]` 0xC0000005 -- evidence in
  `docs/repro/`. When fixes land: re-test, finish + publish in one batch.
- **Remaining hardening queue:** the grandfathered stable packages with
  zero clauses (see `scripts/contract-coverage.ps1`); packages with
  `tests=unknown` need a suite first.
- **Next:** parked graphql/grpc (compiler-gated), further hardening, or
  new growth; next tag `eco-v0.1.45`.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 15:45Z (history):**
- **v0.62.4 release flow COMPLETE + PUBLISHED (`eco-v0.1.43`):** pin
  SHA256-verified; **fleet sweep 460/460** (one timeout triaged: see
  below); 460 runs re-recorded (`fleet-sweep:v0.62.4`); run
  `37213796292` SUCCESS -> **`xiom.protobuf@0.1.0` live (incubating)**;
  registry **459 packages + 2 infra = 461 entries**; guard **499
  allowlisted / 459 ready / 40 grandfathered / 0 failures**; READMEs
  synced. No ops delta/window was needed.
- **`l10n-unicode` slow-suite finding (v0.62.4, open observation):** the
  60s watchdog flagged it TIMEOUT; it actually passes 24/24 at
  **96-107s (manual) / 45.6s (sweep re-run)** vs 52.3s on v0.62.3 --
  a ~2x slowdown, correctness green. Recorded; needs a >60s timeout
  under load. Reported to the compiler lane.
- **Fresh open findings on v0.62.4 (with the compiler lane; do NOT
  re-run the same bisections):** `graphql` 9/10 enum-payload `Str`
  in-situ (lead: variable-payload ctor flattening); `grpc`
  `Vec[(Str, Str)]` probes crash `0xC0000005` (minimal group
  `packages\xiom-grpc\tests\probe_suite_min.xi` + `probe_direct.xi`,
  evidence `docs\repro\tuple-vec-set\`). When fixes land: re-test; if
  green, finish grpc (restore named-constant arms per m188; x2; record)
  and graphql (x2; record) and publish in one batch.
- **Hardening batch proposal (owner pick):** `uuid` (18 checks) + `csv`
  (20 checks) + `bson`/`ttl` clause top-ups per `docs/PROMOTION.md` --
  no ops delta; owner confirms the set before work starts.
- **Toolchain warning (unchanged):** PATH has a v0.62.3 staging dir
  (`xiom.new-20261004-032140`) ahead of `xiom.new` -- always set
  `$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"`.
- **Next:** the two parked packages (compiler-gated), hardening, or new
  growth; next tag `eco-v0.1.44`.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 13:50Z (history):**
- **v0.62.4 PINNED (released 2026-10-04):** official
  `xiom-0.62.4-windows-x64.zip`, SHA256 `ab1c83d2...` verified against
  the published SHA256SUMS; deployed into `%LOCALAPPDATA%\xiom.new`;
  `COMPILER_VERSION` bumped; `status.ps1 -Action repin` = 514 records.
  **PATH WARNING:** `%LOCALAPPDATA%\xiom.new-20261004-032140\bin` (a
  v0.62.3 staging build) precedes `xiom.new\bin` (official v0.62.4) in
  PATH -- run everything with `$env:XIOM_COMPILER =
  "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"`, or fix the PATH order.
- **v0.62.4 retirements verified:** const-tables **FIXED** (probe
  `bad=0`; Int/Str/struct all correct), nested modules, uninitialized
  locals and const match arms all shipped -- `docs/MAINTENANCE.md`,
  `docs/repro/README.md` and the porter brief updated; batteries green.
- **`protobuf` READY + RECORDED (49/49 x2 on v0.62.4, incubating),
  queued for `eco-v0.1.43`** -- already allowlisted, **no ops delta and
  no rate window**; README says 49/49 (published-at sync after the tag).
- **Fleet sweep v0.62.4 RUNNING:** background
  `bgp_10715b01b001BT37l7PR5IYttb`, logs/summary
  `%TEMP%\kilo\sweep-v0624\` (13:50Z: 81/81 PASS; ETA ~15:00-15:30Z).
  A session wakeup `wku_10716e651001n6WstD7Cm2uEWR` (14:25Z) continues
  the flow if this session is still alive; **if it is not, the next
  session finishes the wrap manually**: wait for the sweep, fix any
  non-PASS (re-run `fleet-sweep.ps1 -Only ...`), then
  `scripts/record-sweep.ps1 -LogDir %TEMP%\kilo\sweep-v0624` (dry-run
  first), validate+guard, commit records, clean stray `a.exe.ll` files,
  then wrap+publish `eco-v0.1.43` (generate_index/report/namespaces,
  **stage ALL pending STATUS.json records before tagging**, tag, push,
  approve the gate, verify live).
- **`l10n-unicode` slow-suite finding (v0.62.4):** the sweep flagged it
  TIMEOUT at the 60s watchdog; manual x2 shows **24/24 PASS but 96-107s**
  (was 52.3s on v0.62.3) -- a ~2x slowdown under the same sweep load,
  **not a hang**. Recorded pass (`packages-lane:v0.62.4-slow-suite`).
  After the main sweep: re-run `fleet-sweep.ps1 -Only xiom.l10n-unicode
  -TimeoutSec 300 -LogDir %TEMP%\kilo\sweep-v0624` to append a PASS row
  before `record-sweep.ps1`. Reported to the compiler lane as a
  performance observation (possible const-tables/materialization or
  match-codegen cost).
- **Fresh open findings on v0.62.4 (relayed to the compiler lane
  2026-10-04; do NOT re-run the same bisections):** `graphql` 9/10
  enum-payload `Str` in-situ (lead: variable-payload ctor flattening);
  `grpc` `Vec[(Str, Str)]` probes crash `0xC0000005` (minimal group
  `packages/xiom-grpc/tests/probe_suite_min.xi` + `probe_direct.xi`,
  evidence `docs/repro/tuple-vec-set/`). When a fix lands: re-test, then
  finish grpc (restore named-constant arms per m188; x2; record) and
  graphql (x2; record) and publish in one batch.
- **Hardening batch proposal (owner pick):** `uuid` (18 checks) + `csv`
  (20 checks) + `bson`/`ttl` clause top-ups per `docs/PROMOTION.md` --
  no ops delta; owner confirms the set before work starts.
- **Ops:** nothing pending.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 13:20Z (history):**
- **v0.62.4 STAGED on compiler main (release commit `959fcd95`, tag not
  yet pushed).** Highlights relevant to us: **constant tables with
  strings/structs FIXED** (our `const-tables` finding), **nested modules
  + same-name payload types FIXED** (m184/m189 -- drop those porter
  rules at the pin), plus script-cache stdin, match-arm codegen, and
  unsigned comparisons (m186). Post-pin flow: verify the official
  archive + SHA256SUMS, deploy, bump `COMPILER_VERSION`, `repin`, fleet
  sweep + `record-sweep.ps1`, re-run the probe index (expect
  `const-tables` `bad=0`; enum-payload in-situ and grpc probes re-check),
  record + publish `protobuf` (49/49 already proven on m189), restore the
  named-constant arms in `grpc.status_to_str` (m188), then wrap
  `eco-v0.1.43`.
- **Compiler-lane analysis to relay (enum-payload persists on m189):**
  m189 fixed the *literal* disambiguation, but the second half of the
  `51a47458` root cause likely still applies to the **variable-payload**
  path -- graphql passes `GraphQLSelection.Field(field)` with a struct
  *variable*, where the registry flattening + ctor spread (payload spread
  into N args; `field_idx` past the struct end; bogus `i8*` struct load)
  would not be reached by the literal-collision fix. Suggest probing
  `compile_enum_constructor` with a non-literal payload arg. grpc is a
  separate shape (`Vec[(Str, Str)]` + library mutation, no enums).
- **protobuf held for the pin:** test expectation fixed
  (`zz_enc(5)-1==zz_enc(-5)`), manifest modules added, **49/49 x2 on
  m189**; record + publish only on the official v0.62.4.
- **Next:** stable hardening batches (279 stable; `bson`/`ttl` only) and
  the remaining grandfathered set (FFI-class skipped); next tag
  `eco-v0.1.43`.
- **Hardening batch proposal (owner pick, read-only scoping done):**
  first batch could be the small foundational stable packages --
  `uuid` (18 checks), `csv` (20 checks), plus clause top-ups for
  `bson`/`ttl` (the only stable packages with clauses today). All are
  already allowlisted/published, so a 2-4 name hardening batch needs no
  ops scope delta and no rate window; contracts + API review per
  `docs/PROMOTION.md`, then patch bump + x2 + record + publish in the
  next eco tag. Owner to confirm the set before work starts.

**--- Older state below (history) ---**

**STATE AT 2026-10-04 00:05Z (history):**
- **`xiom.micro` + `xiom.realtime` RESTORED + PUBLISHED (`eco-v0.1.42`,
  run `37162994341` SUCCESS):** same nested-module + collecting-harness
  treatment; 10/10 x2 each; manifests gained `modules`; README scopes
  corrected (they were stale placeholders). Both live at **`0.1.0`
  incubating**; registry **458 packages + 2 infra = 460 entries**.
  Network stack complete: `http` (36/36), `websocket` (10/10), `rest`
  (10/10), `micro` (10/10), `realtime` (10/10) all published this
  session.
- **`xiom.grpc` PARKED (WIP, not recorded):** fixed along the way --
  unsafe-FFI wrappers for `grpc_init`/`grpc_shutdown`; the missing
  `grpc_server_config`/`grpc_server_address` helpers (in `src/types.xi`,
  avoiding a module cycle); and a **NEW minimized compiler finding**:
  **`const` values as `match` arms never match on v0.62.3**
  (`docs/repro/const-match/`, `two=other`; `status_to_str` returned
  "UNKNOWN" for every code -- fixed with numeric literals; repo-wide scan
  found only grpc affected). Remaining: the suite binary crashes
  (`0xC0000005`) pre-output when the later test group is included --
  bisection exceeded the circuit breaker and is logged in
  `docs/failed_attempts.md` with next hypotheses. Do NOT re-run the same
  bisection blindly.
- **`xiom.graphql`** remains parked 9/10 (enum-payload `Str` corruption).
- **Compiler findings added this session (for the next release):**
  nested test-module import; uninitialized-local corruption;
  enum-payload `Str` corruption; **const match arms never match**
  (minimized). Probe index: `docs/repro/README.md`.
- **Compiler-main status (relayed 2026-10-03 23:55Z):** m184
  (nested test-module import) and m185 (uninitialized-local -- confirmed
  real NULL-deref UB) are **fixed and locked on compiler main**; **m188
  (const match arms) also fixed and locked with an e2e fixture** (restore
  named constants in `grpc.xi` after the next pin); pin when the next
  release ships. **Next-release to-dos:** re-run the
  `enum-payload-str` in-situ case on a build with m184+m185 (possibly a
  symptom of the m185 UB) and drop the two porter-brief rules then.
  Compiler lane also reports `smoke_iter_range` rc 0 on their post-m184
  tree (promote their smoke lock when the next candidate ships) and that
  doctor no longer warns on the stdlib version split (m187:
  MAJOR.MINOR compare). **Enum-payload re-run DONE (2026-10-04): built
  main locally (m184..m187, `cargo build --release -p xiom`,
  `target\release\xiom.exe`) -- the graphql in-situ case STILL FAILS
  (9/10, `|0|` read persists), so it is NOT an m185 symptom; findings
  row updated.** **Stdlib-lane note:** aligning `xiom-std`'s registry
  labels is optional (no correctness need) -- bump `package.xi` and push
  a `stdlib-v*` tag when convenient; the stdlib checkout is at version
  `0.62.0`, last tag `stdlib-v0.62.0`.
- **grpc crash handoff (2026-10-04):** smallest failing subset found and
  ready for the compiler lane -- `packages/xiom-grpc/tests/probe_suite_min.xi`
  (calling the exact metadata-set test -> `0xC0000005` pre-output;
  replacing the call with `let rc: Int = 0;` runs) plus
  `probe_direct.xi` (inline `req.metadata[0].0` read -> hang; without the
  read it runs). Fault data: `ntdll.dll` 0xC0000005, offsets
  `0x1ff2a`/`0xc4a0f`; reproduces on v0.62.3 **and** local main
  m184..m187. Full matrix: `docs/repro/tuple-vec-set/README.md`;
  COMPILER-FINDINGS row added; grpc stays unpublished meanwhile.
- **m189 (compiler main, in flight):** root cause localized and it
  **cites our enum-payload in-situ failure** -- enum struct-payload
  construction emits invalid IR because the type registry flattens the
  payload struct's fields (payload spread into args, bogus GEP/`i8*`
  struct load). Fix direction recorded; not yet committed.
- **Grandfathered triage (2026-10-04, after the network stack):**
  `kafka` suite is green **22/22** on v0.62.3 but stays `ported` (FFI
  stubs: `handle -1`, `poll None`, admin `Err(-999)`) -- a pure-XIOM
  reinterpretation would be a design job, not a restore. `zstd`/`lzfse`
  are **FFI wrapper packages** (libzstd/LZFSE `extern "C"` bindings with
  placeholder null calls, blocked Vec<->ptr marshaling) -- skip them with
  the FFI class; their suites also reference a nonexistent `TestCase`
  framework, but the impls are stubs so a harness rewrite alone would not
  help. `protobuf` **compiles** (2 modules) but crashes `0xC000001D`
  (illegal instruction) pre-output -- fault record: `a.exe` itself,
  exception `0xc000001d`, offset `0x1a809` (different signature from the
  grpc ntdll `0xC0000005` case) -- **suspected m189-family; add to the
  re-test list**.
- **m189 re-test RESULTS (build `355c69d0`, 2026-10-04):** `protobuf`
  crash is **FIXED** -- after correcting one wrong test expectation
  (zigzag: `enc(5)+1` should be `enc(5)-1`; `enc(5)=10`, `enc(-5)=9`)
  the suite is **49/49 x2** on the m189 build; manifest gained its
  `modules` list. **Held for the v0.62.4 pin** (the pinned v0.62.3 still
  crashes; records/publish only on the official pin, then the x2 +
  record + eco batch). **graphql in-situ STILL 9/10 and both grpc probes
  STILL crash/hang on m189** (`355c69d0`) -- no `type Field` collision
  exists in graphql and grpc has no enums, so these are a different,
  still-open defect; reported back to the compiler lane with the build
  hash.
- **m189 re-test list (when the fix build lands):** rebuild
  (`cargo build --release -p xiom`), then `docs/repro/enum-payload-str`
  in-situ (graphql 9/10 case), `packages/xiom-grpc/tests/probe_suite_min.xi`
  + `probe_direct.xi`, and the `protobuf` suite. If green: finish
  grpc (restore const arms) + graphql and publish.
- **Next:** stable hardening batches (279 stable; only `bson`/`ttl` carry
  clauses; `scripts/contract-coverage.ps1`) and/or pick up the parked
  grpc/graphql with the recorded leads; next tag `eco-v0.1.43`.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 23:55Z (history):**
- **`xiom.rest` RESTORED + PUBLISHED (`eco-v0.1.41`, run `37161771429`
  SUCCESS):** same nested-module + runner treatment, plus the v0.62.3
  **unsafe-FFI pattern** from the MCP language guide (`xiom_language_guide`
  unsafe-ffi topic: extern calls need `unsafe { }` blocks; safe fns
  returning raw pointers need `unsafe` in the body; whole-body-unsafe fns
  need `requires`; safe-wrapper = contract + `unsafe`). 10/10 x2,
  brackets 0.
  Live at **`xiom.rest@0.1.0` incubating**; registry **456 packages +
  2 infra = 458 entries** (http/websocket/rest all published this
  session).
- **Growth status of the network stack:** `http` (36/36),
  `websocket` (10/10), `rest` (10/10) published; `graphql` PARKED 9/10
  (enum-payload `Str` corruption, minimal repro pending);
  `grpc`/`micro`/`realtime` untried (likely same nested-module + runner
  pattern; check for the unsafe-FFI rules too).
- **Next:** try `grpc`/`micro`/`realtime` with the established restore
  recipe; graphql waits on the compiler finding; stable hardening
  batches remain; next tag `eco-v0.1.42`.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 23:40Z (history):**
- **Post-release growth wave 2:** `xiom.websocket` RESTORED + PUBLISHED
  (`eco-v0.1.40`, run `37159040739` SUCCESS) -- the implementation was
  complete; the real blockers were the **nested test module**
  (`module xiom.websocket.tests` cannot import the package root; renamed
  to `websocket_tests`) and the missing runner (collecting harness +
  `main`; 10/10 x2, brackets 0). Live at **`xiom.websocket@0.1.0`
  incubating**; registry **455 packages + 2 infra = 457 entries**
  (`xiom.http` published earlier as `eco-v0.1.39`).
- **NEW compiler finding (v0.62.3): uninitialized local struct +
  assignment inside a match arm corrupts the value** -- `Str` fields read
  as garbage pointers (concat hangs), `Vec.len()` reads `4294967295`
  (runaway loops); pre-initializing the local avoids it. Found in
  `xiom.graphql` `validate_operation`; COMPILER-FINDINGS row + probe
  bundle `docs/repro/uninit-local/` (standalone repro crashes pre-output
  -- minimal repro pending). **Porter brief now says: always initialize
  locals at declaration.**
- **`xiom.graphql` WIP (9/10, PARKED):** module rename + collecting
  harness + `validate_operation` contract fix got the suite running; the
  remaining failure is an **enum-payload `Str` corruption** --
  `GraphQLSelection.Field(sel).name` reads `|0|`/empty in the validator,
  while source locals (`hello`) and `Vec[StructType]` reads (`vec`) are
  correct controls. In-situ evidence in COMPILER-FINDINGS +
  `docs/repro/enum-payload-str/`; **all standalone repro shapes pass**
  (single-module, `derive[Clone]`, recursive payload->nested->Vec[enum],
  `&mut`+push, two-module scratch), so the minimal repro is pending.
  Workaround until isolated: parallel `Vec[Str]`/id scheme, or park.
  `xiom.rest` untouched (same nested-module + runner pattern, then real
  API work). Neither recorded/published (records still `tests=unknown`).
- **Next:** isolate the graphql validator defect (minimal repro for the
  findings row), then `graphql`/`rest`; stable hardening batches remain
  available; next tag `eco-v0.1.41`.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 20:55Z (history):**
- **Post-release growth: `xiom.http` RESTORED + PUBLISHED (`eco-v0.1.39`,
  run `37152581124` SUCCESS):** the old code was written for pre-strict
  compilers -- fixed multi-arg `str_concat` (arity T001 errors),
  self-recursive `char_code` -> `xiom.string.char_at`, host:port URL
  parsing (the colon was consumed before `host_end`), `path_join`'s
  contradictory `requires`, and replaced the failure-swallowing `try()`
  harness with a collecting runner (`[PASS]`/`[FAIL]`, **36/36**, suite
  x2, bracket grep 0). Manifest gained its missing `modules` list and
  deps were normalized to `xiom.std`. Live at **`xiom.http@0.1.0`
  incubating**; registry **454 packages + 2 infra = 456 entries**;
  guard **499 allowlisted / 454 ready / 45 grandfathered / 0 failures**.
- **Ops lesson (also added to the operating kit):** `eco-v0.1.38` was
  tagged before http's `STATUS.json` record was committed, so CI's
  readiness guard saw `tests=unknown` and skipped it (no-op run);
  `eco-v0.1.39` carried the record. **Wrap commits must stage all
  pending `STATUS.json` changes.**
- **Compiler install note:** `xiom.new\bin` lost `xiom.exe` again at
  ~20:30Z (external cleanup); redeployed from the SHA-verified archive
  copied at `%TEMP%\kilo\release-0623\extracted`. If `port.ps1` warns
  "falling back to repo-release 0.62.2", redeploy before running.
- **Growth candidates (implementation-heavy, NOT restores):**
  `graphql`/`rest`/`websocket` suites were written against a different
  API generation (102-163 `T001`s; undefined `client_*`/`frame_*`/
  `response_*` names) -- they need API reconciliation + implementation.
  The FFI-class grandfathered set stays skipped.
- **Next:** stable hardening batches, and/or pick up
  `graphql`/`rest`/`websocket`; next tag `eco-v0.1.40`.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 20:20Z (history):**
- **Release day COMPLETE + PUBLISHED (`eco-v0.1.37`):** v0.62.3 pinned
  (official archive, SHA256-verified); fleet sweep **453/453 PASS** once
  `ssh2` was fixed -- v0.62.3 rightly rejects the `Result[Bool,Str]` ->
  `Result[Int,Str]` mismatch, so the suite gained `err_bool_is` and the
  package bumped to 0.1.4; 454 runs re-recorded with source-commit
  provenance (`29c906fa`); guard now **499 allowlisted / 453 ready / 46
  grandfathered / 0 failures**.
- **First promotion wave DONE:** `json` (44/44), `control` (32/32),
  `sensor` (38/38) -> **`stable` 0.1.1** with SPEC promotion notes (G1-G7
  evidence), post-bump x2 on v0.62.3, records + READMEs synced; run
  `37150223414` **SUCCESS attempt 1** -> published
  `xiom.json/control/sensor@0.1.1 stable` + `xiom.ssh2@0.1.4`; all
  live-verified.
- **Registry:** **453 packages + 2 infra = 455 entries** (279 stable /
  174 incubating / 1 empty infra probe); allowlist unchanged 499; no ops
  delta or window was needed.
- **v0.62.3 retirements (next-touch only):** `Vec[Str].push` and
  `&mut Int` rows RETIRED (probes green; no mass refactor wave -- see
  the scoping decision below); complex `Str`/struct const tables remain
  a v0.62.3 **known issue** (runtime builders only); float bitcast still
  a stdlib stub; all other batteries green.
- **Next queue:** stable hardening batches (279 stable, only `bson`/`ttl`
  carry clauses; size with `scripts/contract-coverage.ps1`) and/or a new
  growth wave (v0.62.3 porter brief in the operating kit); registry page
  refresh = policy 1b; next tag `eco-v0.1.38`.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 18:35Z (history):**
- **v0.62.3 PINNED (release landed 18:07Z):** official
  `xiom-0.62.3-windows-x64.zip` downloaded from the GitHub release,
  **SHA256 verified against the published SHA256SUMS** (`011af7dd...`
  MATCH); deployed into `%LOCALAPPDATA%\xiom.new` (`xiom --version` =
  v0.62.3; wrapper resolves `0.62.3 (installed)`); `vcruntime140.dll` +
  `xiom-lsp.exe` left at the prior build (locked by the running VS Code
  LSP, PID 60936 -- editor files only; `xiom.exe` and all tools are new).
  `COMPILER_VERSION` bumped; `status.ps1 -Action repin` = 514 records to
  v0.62.3.
- **Two workaround RETIREMENTS (probe RED -> GREEN on v0.62.3):**
  `Vec[Str].push` global/param -- both probes compile and run
  (`vec_str_push_global` exit 0; `vec_str_push_param` `first=alpha`);
  `&mut Int` bare assignment -- `mut_int_write_drop` prints `st=99`,
  matrix `bad=0`. Rows RETIRED in `docs/MAINTENANCE.md`; resolved rows in
  COMPILER-FINDINGS; repro index + packet README updated. Unchanged:
  complex const tables still broken -- **v0.62.3 release notes list it as
  a known issue**; float bitcast still a stdlib stub; every
  previously-fixed battery still green (arity T001 both directions,
  byte_at `bad=0`, str-vec-eq `bad=0`, vec-struct `bad=0`,
  struct-field/generic-fnptr all exit 0).
- **Fleet sweep v0.62.3 RUNNING:** new `scripts/fleet-sweep.ps1`
  (resumable; child-process capture; per-package logs + `summary.tsv`
  under `%TEMP%\kilo\sweep`) as background
  `bgp_102fed501001zhJdfvwygEuN3h`, over all implemented packages
  (~454). Next: fix non-PASS + re-record green runs, then the
  maintenance wave (workaround removal at next touch), then the FIRST
  PROMOTION WAVE (`json`/`control`/`sensor` -> stable; pre-flight G1-G7
  done -- **re-run G1 x2 on v0.62.3 in-wave**) + publish
  `eco-v0.1.37`.
- **Tier-2 maintenance-wave candidates (for after the sweep):** 25
  packages carry explicit `Vec[Str]`-avoidance comments. Bug-driven
  subset (cite the v0.62.2 mis-lowering; candidates for direct
  `Vec[Str]` use at next touch): `autoscale`, `chromatography`,
  `consensus`, `context`, `defi`, `metadata`, `microscopy`, `svm`,
  `tensor`, `text-markup`; also check `climate`, `docx`, `exchanger`,
  `jpeg`, `oauth`, `pe`, `serverless`, `video`. **Blob+offset models
  (`cloud`, `cloudlog`, `docker`, `k8s`, `pptx`) are valid designs, not
  bug workarounds** -- leave unless touched anyway; `activation` /
  `l10n-unicode` are pure-Int APIs (no change). Retire with identical
  behavior: `refactor:` + suite x2 + trap-14; patch-bump only when
  published code ships the change.
- **Wave scoping decision (2026-10-03, in-session review):** the 25
  candidates are mostly deliberate single-Str / blob+offset designs
  adopted around the bug (`consensus`, `svm`, `cloud`/`cloudlog`/
  `docker`/`k8s`, `pptx`, the trace models). Per the standing rule
  "never a drive-by refactor of a green package", there is **no mass
  refactor wave**: the retirements mean new code may use `Vec[Str]` /
  `&mut Int` freely, and existing sites simplify only at next touch.
  Tier-2 is therefore: sweep + re-record (detector, done when green)
  -> first promotion wave.
- **Current gates:** `validate` 514/0; guard expected unchanged
  **499 allowlisted / 450 ready / 49 grandfathered / 0 failures**; no
  publish pending until the promotion wave; ops needs nothing yet.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 14:30Z (history):**
- **`eco-v0.1.36` PUBLISHED (this session, run `37129059908` SUCCESS
  attempt 1):** manifest module-list fixes + patch bumps -- `stats-ml`
  `xiom.stats-ml` -> `xiom.stats_ml` (invalid hyphen module name; the
  namespace export was double-counting it, so 593 -> 592 is a
  correction), `vault` now declares `client`/`core`/`json`, `web3`
  declares `accounts`/`contract`/`ens`/`keccak`/`provider`; suites
  re-ran green (`stats-ml` 22/22, `vault` 28/28, `web3` 28/28); no ops
  scope delta needed (all three already allowlisted/scoped); all three
  verified live at `0.1.1` stage `incubating`; repo-wide module-list
  re-audit = 0 issues.
- **Wave 56 COMPLETE + PUBLISHED (`eco-v0.1.35`):** category-vocabulary
  sweep `5f469ee5` (all 90 manifests that mixed unknown tokens with
  accepted ones normalized to the 16-token registry vocabulary;
  metadata-only, no version bumps; rescan = 514 manifests / 0 unknown;
  legacy mappings + domain resolutions recorded in `docs/MAINTENANCE.md`);
  owner approved publishing `firebird`/`oracle` (both 22/22, recorded
  `incubating`); ops confirmed **499 live on both entries, zero diff**;
  allowlist **497 -> 499** (`4c7093f7`); run `37123591095` **SUCCESS
  attempt 1** (2m50s, no OIDC expiry) -> `Published xiom.firebird@0.1.0`,
  `Published xiom.oracle@0.1.0`; both spot-verified live at `0.1.0`
  stage `incubating`.
- **Current gates/state:** `validate` **514/0**; guard **499
  allowlisted / 450 ready / 49 grandfathered / 0 failures**; registry
  **450 packages + 2 infra = 452 entries** (276 stable / 174 incubating /
  1 empty infra probe); allowlist **499**; tags `eco-v0.1.35` on
  `4c7093f7` and `eco-v0.1.36` on `5e25ee47`; all pushed.
- **Compiler release:** pin still `v0.62.2`; deployed `xiom.new\bin`
  binaries unchanged (2026-09-30). Compiler lane relayed "closer to
  release but not yet" -- Tier-2 triage, the first promotion wave
  (`json`/`control`/`sensor` stay `ported`), and the 276-record
  grandfathering queue remain release-blocked.
- **Promotion pre-flight (`json`/`control`/`sensor`), release-gated:**
  G1 done -- `port.ps1` **x2 green on v0.62.2** (44/44, 32/32, 38/38);
  byte-level bracket grep = 0 hits across all 15 `.xi` files; SPDX headers
  added to all 15 (they ship with the promotion). G2 -- SPEC+README
  present, no PLACEHOLDER/PENDING text. G4 -- contracts present
  (`requires`/`ensures`: json 13/2, control 15/36, sensor 7/22);
  solver-unproven clauses documented (xiom-verify tooling gap). G5 --
  44/32/38 checks, error paths included. G6 -- applicable registry rows:
  contract-verification (accepted; revisit after Tier-2), json
  enum-payload + derive-Clone (accepted). G7 -- only unpublished
  `graphql`/`rest` declare `xiom.json`; no published dependents. G3 API
  review runs in-wave. `kafka` is the fourth `ported` record and is NOT
  promotion-ready (`excluded_reason: ported only -- librdkafka FFI stubs
  remain: handle -1, poll None, admin Err(-999)`), so the wave is the
  three implemented candidates. Stages stay `ported` until Tier-2
  completes; the wave is 3 names (already allowlisted/scoped -- **no ops
  delta, no rate window**), tag `eco-v0.1.37`.
- **Publish status right now: nothing pending.** Registry `450 packages
  + 2 infra = 452 entries`, manifest-vs-registry version drift = 0, no
  unpublished ready names; promotion wave is the only next batch and it
  is release-gated. No ops ask is due.
- **Parallel lane (`ses_f26cdae1…`):** its stalled README example fixes
  for `mock`/`pwm`/`sectest` were rescue-committed this session (the
  snippets called `io.println` on Int/Bool; now `int_to_string`/`if`;
  Agent Manager extension unreachable, lane idle ~12 h). Re-verified
  port x2 each (20/20, 20/20, 22/22) + bracket triage (the 3 pwm raw
  hits are doc comments). Working tree for those dirs is clean;
  `firebird`/`oracle` completed and published in wave 56 -- coordinate
  before touching any remaining lane dirs.
- **Carry-forwards:** compiler hotfix watch (`docs/COMPILER-FINDINGS.md`);
  Tier-2 + workaround retirement on the next release; first promotion
  wave per `docs/PROMOTION.md`; registry page refresh = policy 1b
  (opportunistic); `-TimeoutSec 60` watchdog; byte-level bracket grep
  only; bump versions only when source changes.
- **README Status-block sync DONE (this session):** all 514 package
  READMEs now match the live registry versions/stages -- 5 were stale
  (`curl`, `xml2`, `rocksdb`, `firebird`, `oracle` said "not yet
  published" while live at `0.1.0`); repo-side only, no republish
  (policy 1b); the earlier "351 names lag" carry-forward is closed
  (verify by comparing each README block against the registry index).
- **Repo-hygiene re-audits (this session):** (a) bracket-debt sweep --
  1712 `.xi` files byte-scanned for `Vec<`/`Result<`/`Option<`/`<]`/`>]`;
  31 raw hits, ALL in comments or XML/string literals -> **0 real
  sites**; the wave-54/55 repair program holds; (b) `&mut Int` audit --
  only `gbnf` (deref form, safe) and `http` (bare form, tests=unknown,
  statically exposed) carry real `&mut Int` params; every other hit is a
  comment or a `&mut Vec` variable named `f64` (apple/mkv tests);
  (c) `byte_at >= 128` battery re-ran `bad=0`/exit 0 on the installed
  v0.62.2 (workaround stays RETIRED); a direct-compare scan found only
  two documented safe sub-128 comments; (d) child->parent module calls
  re-verified -- the boundary is `pub` visibility, not the parent
  relation: acyclic, cyclic and alias-qualified calls all work with
  `pub` (minimal probe bundle `docs/repro/child-parent-calls/README.md`
  + `training` 26/26 re-run); the 2026-10-02 "siblings only" finding is
  superseded in `docs/COMPILER-FINDINGS.md` and the workaround row is
  re-scoped; the siblings-only rule can be relaxed at Tier-2;
  (e) SPDX-header audit + fix: **0 missing** in published packages
  (20 files across `ui`/`meshopt`/`bmp`/`biology`/`streaming`/`geology`/
  `meteorology` got the standard header; all 7 suites re-ran green);
  15 more added for the promotion candidates; the umbrella
  `packages/package.xi` now carries SPDX + a legacy-list note;
  284 remain in 62 grandfathered/skipped dirs -- fix opportunistically
  at next touch;
  (f) manifest-vs-registry version drift: **0 of 450**;
  (g) manifest `modules` vs source declarations: 3 packages drifted
  (`stats-ml` hyphen name, `vault` missing `client`/`core`/`json`,
  `web3` missing `accounts`/`contract`/`ens`/`keccak`/`provider`) --
  fixed and republished in **`eco-v0.1.36`**; repo-wide re-audit = 0
  issues;
  (h) `Str` equality/`str_len` on `Vec[Str]` elements: NOT REPRODUCED
  on v0.62.2 (probe `docs/repro/str-vec-eq/probe_str_vec_eq.xi`,
  `bad=0` for elem==elem, elem==literal, runtime-derived==literal and
  `str_len`; MAINTENANCE row added as a Tier-2 retirement candidate);
  (i) stale build artifacts cleaned -- 389 leftover `a.exe` (215 MB)
  removed; the parallel lane's dirs were left untouched;
  (j) remaining probe batteries re-ran on v0.62.2 -- arity control green
  and both error directions fail with `error[T001]`, loop-carry-cse
  `bad=0`, sign-bit ops exit 0: all at documented status (no README
  changes needed);
  (k) struct-field/Result-payload + generic fn-pointer probe families
  re-ran on v0.62.2 -- **all 10 probes exit 0**
  (`probe_result_value` prints `result payload: 3`, was `0`); both
  families are FIXED on the pin, their workarounds are now **RETIRED**
  in the MAINTENANCE registry, and the probe READMEs + COMPILER-FINDINGS
  resolved table are updated (`docs/repro/struct-field-vec`,
  `docs/repro/generic-fnptr`);
  (l) const/table materialization extended to complex shapes: **NEW
  v0.62.2 defect** -- `const [3]Str` / `const [3]Row` module tables read
  corrupt/zero (probe `docs/repro/const-tables/probe_const_tables.xi`,
  `bad=5`, deterministic 3/3; Int tables and runtime controls pass);
  COMPILER-FINDINGS row added, MAINTENANCE row 25 updated (not retirable
  for complex shapes); packages keep runtime table builders;
  (m) promotion candidates pre-verified on the pin: `json` 44/44,
  `control` 32/32, `sensor` 38/38 (stages stay `ported` until Tier-2);
  (n) crypto-link packet re-verified on the current stdlib checkout:
  both probes still fail link with `undefined symbol: xiom_sha256_hash`
  (packet remains valid for the stdlib lane);
  (o) `Vec[StructType]` (trap 10): NOT REPRODUCED on v0.62.2 (probe
  `docs/repro/vec-struct/probe_vec_struct.xi`, `bad=0`: push/len/
  indexed reads with Str fields/field write/loop push/`&Vec` param all
  correct) -- new registry row + COMPILER-FINDINGS resolved row;
  retirement candidate (parallel-Vec sites simplify at next touch);
  (p) arity contradiction resolved: the 2026-10-02 "missing args
  accepted silently" row is stale -- on v0.62.2 missing-arg calls fail
  `error[T001]` (`'add3' expects 3 argument(s), found 2`), extra-arg
  likewise, exact-arity control green; MAINTENANCE row RETIRED,
  findings open row marked superseded, arity README updated;
  (q) `Vec[Float64]` + bitcast: split status -- **`Vec[Float64]` WORKS**
  on v0.62.2 (probe `docs/repro/float-vec/probe_float_vec.xi` green for
  push/compare/arith); **bitcast still missing**
  (`xiom.num.float.float_bits`/`bits_to_float` are documented fallback
  stubs, `float_bits(1.5)=0`); findings row annotated + registry row
  added; packages keep raw-octet float encodings until the intrinsic
  lands;
  (r) `xiom.std` dependency constraint normalized (audit): 65 legacy
  manifests pinned `"0.1.0"` -- a stdlib version that never existed
  (the registry's stdlib entry is `xiom-std` **0.62.0**); all now use
  the canonical `">=0.60.0 <1.0.0"` (448-file majority), and `glfw`
  gained its missing deps block -> **514/514 consistent**. Of the 65,
  only `meshopt`/`ui` are published (fix rides their next touch,
  policy 1b);   the rest are grandfathered;
  (s) contract-coverage audit (new `scripts/contract-coverage.ps1`,
  read-only, fetches the live registry): **2658 clauses across 66/514
  packages** -- **274 of the 276 grandfathered stable packages carry
  zero** (`bson` 3, `ttl` 1); bulk = 60 unpublished C-binding dirs
  (2396) + 4 `ported` (114) + published `meshopt`/`ui` (144).
  `docs/PROMOTION.md` "packages carry zero" corrected; hardening
  selection inputs are flat (equal fleet-sweep `checked` dates, no
  published dependents) so batch choice stays owner-driven;
  (t) pre-release documentation sync: README-vs-record conformance
  counts = **0 drift** across all published packages (the 60 unheard
  hits are unpublished dirs with no status marker); `docs/repro/README.md`
  index added (14 bundles with current v0.62.2 status); six
  `docs/STDLIB-WISHLIST.md` status cells refreshed with today's verified
  results (`xiom.float` Vec/bitcast split, SHA link still open,
  `str_eq` not reproduced, hardened byte access resolved, categories
  sweep done, `l10n.iso4217` runtime builder still needed).
- **Compiler-evidence refinement (v0.62.2 `&mut Int` write-drop):** the
  drop is the BARE assignment form (`s = 99`) in both call forms (plain
  local and explicit `&mut`); DEREF writes (`*s = ...`) work. Matrix
  probe `docs/repro/v0622-regressions/mut_int_write_drop_matrix.xi` =
  `bad=2`; `gbnf` re-ran **30/30 PASS** on the installed v0.62.2 with
  deref writes (production confirmation).
  `docs/COMPILER-FINDINGS.md` + the `MAINTENANCE.md` workaround row
  updated; Tier-2 can narrow the ban to bare assignments only.

**--- Older state below (history) ---**

**STATE AT 2026-10-03 00:55Z (history):**
- **Waves 54/55 COMPLETE + PUBLISHED (`eco-v0.1.34`):** run
  `37081404845` SUCCESS on attempt 2 (attempt 1 lost the alphabet tail to
  `oidc_token_expired`; rerun --failed + re-approve is idempotent). Batch
  contents: **category harmonization 34 packages** (15 network, 11
  systems, 8 one-offs -- registry `categories: []` fixed); **legacy
  bracket-repair program 24 packages / 94 real sites** (+ modbus 10,
  folded) -- the repo-wide angle-bracket debt found by the corrected
  scan (the earlier 134-site figure was inflated by `>]` in XML
  strings); **growth: `curl` 26/26, `xml2` 24/24, `rocksdb` 24/24**
  (allowlist **494 -> 497**); **parallel-lane integration: `firebird`
  22/22 (5 bracket sites fixed by coordinator), `oracle` 22/22** --
  verified, recorded `incubating`, publish pending owner scope decision;
  `mock`/`pwm`/`sectest` from the parallel lane republished.
- **Current gates/state:** `validate` **514/0**; guard **497
  allowlisted / 448 ready / 49 grandfathered / 0 failures**; registry
  **448 packages + 2 infra = 450 entries** (ops ack 2026-10-03 01:04Z,
  window closed back to 20, nothing open ops-side); allowlist **497**;
  tag `eco-v0.1.34` on `3f196c7b`; docs wrap `00fa58ed`; all pushed.
- **`port.ps1` watchdog FIXED (`07301ee6`):** renamed-timeout path now
  kills only the run's own PID tree -- the old global
  `Get-Process a | Stop-Process` sweep killed other lanes' in-flight
  suites (root cause of the wave's silent empty-output/watchdog flake
  storm, and likely a factor in the historical expat/nbt class). Also
  removes `a.exe`/`a.exe.ll` leftovers per run.
- **Registry category vocabulary (16 tokens, policy in
  `docs/MAINTENANCE.md`):** ai-ml, cloud-infra, concurrency, core,
  crypto-security, data, database, graphics, media, network, science,
  systems, testing, text-nlp, tooling, web. Unknown tokens are dropped
  silently. Legacy mappings documented; **manifests must use only these
  tokens** (the ~90 packages mixing unknown+accepted tokens are
  registry-safe and wait for an opportunistic sweep).
- **New compiler/harness findings (wave 54/55):** `xiom --emit-ir
  <file>` OUTSIDE a package context fails silently (exit 1, no output;
  stage probes in a package); compiling sources under
  `%TEMP%\kilo` can hang the compiler indefinitely (repo tree compiles
  in ~0.6 s); `fn` reserved; mixed-bracket `Vec<X>` still silently
  accepted in field/local positions. All in
  `docs/COMPILER-FINDINGS.md` / the board.
- **Rules reinforced:** bracket audits use the BYTE-LEVEL grep only
  (Read renders `Vec<Int>` as `Vec[Int]`); bump versions ONLY when
  source changes (no metadata-only churn); the maintenance workaround
  registry now also covers enum-payload mutation, aggregate clone, and
  verify-as-review-aid.
- **Parallel lane (separate stream, same worktree):** implements the
  remaining `tests=unknown` placeholders (mock/pwm/sectest committed
  with "(parallel lane, verified)"; firebird/oracle now integrated).
  Coordinate before touching their in-flight files.
- **Program state:** growth EXHAUSTED (FFI reinterpretations done for
  curl/xml2/rocksdb; `aac`/`bridge`/`c-binding`/`icu`/`jansson`/`llvm`/
  `odbc`/`oracle`-DB remain skipped); promotion candidates ready
  (`json`/`control`/`sensor`) for the FIRST PROMOTION WAVE after Tier-2
  compiler maintenance; grandfathering queue = the 276 pre-gate stable
  records (`docs/PROMOTION.md`).
- **Carry-forwards:** compiler release -> Tier-2 triage +
  workaround-retirement wave (crypto/base64 fix-first packet at
  `docs/repro/crypto-link/`); owner decision: scope for
  `firebird`/`oracle`; registry page refresh = policy 1b (opportunistic;
  no dedicated republish program); category spot-sweep for the ~90 mixed
  manifests; `-TimeoutSec 60` watchdog.

### Next-session operating kit (wave pipeline -- proven 6x)

1. **Prep**: `git fetch; git status -sb; git log -1`; gates
   `status.ps1 -Action validate` + `allowlist-guard.ps1`. Toolchain:
   `COMPILER_VERSION` = v0.62.4; official install at
   `%LOCALAPPDATA%\xiom.new\bin` -- **run with `$env:XIOM_COMPILER =
   "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"` because a v0.62.3 staging
   dir (`xiom.new-20261004-032140`) shadows it in PATH**; stdlib
   checkout `E:\xiom-lang\stdlib`.
2. **Select + check**: pick ~10 pure-XIOM placeholders; run
   `& .\scripts\namespace-check.ps1 -Module <names>` (expect 0 conflicts).
3. **Dispatch**: 6 background `task` porters + 4 Agent Manager local
   sessions (`agent_manager` action=null, mode=local, versions=false).
   Brief = the v0.62.4 edition: `Vec[Str].push`, `&mut Int` params,
   nested test modules, uninitialized locals, const match arms AND
   `Str`/struct const tables are all FIXED (probes green; no avoidance
   needed); cross-module helpers just need `pub` (child->parent calls
   are fine); float bitcast is the remaining stdlib stub;
   no builtin/generic-name shadowing; progress-guaranteed loops +
   full-angle bracket grep after green + `port.ps1 -TimeoutSec 60` gate
   + `## stdlib gaps` report. **Unsafe-FFI:** every extern
   call needs an `unsafe { }` block; a safe fn returning a raw pointer
   needs `unsafe` somewhere in the body; a fn whose whole body is one
   unsafe block needs `requires`; safe-wrapper = contract + `unsafe`
   (see the MCP `xiom_language_guide` unsafe-ffi topic). Crash
   recovery: stop the dead AM session and re-dispatch as a `task` with
   `variant: low` + files-first/short-replies directive (worked 5x).
4. **Integrate as they report** (don't wait for all 10): write a
   two-row CSV (Name, Dir, Session=`task:ses_...`/`agentmgr:ses_...`) and
   run `powershell -File %TEMP%\kilo\verify-wave43.ps1 -WaveCsv <csv>`
   (port x2 + trap-14; fix mixed brackets; kill `a.exe` leftovers).
   Then per package: `git add` exact files -> feat commit -> `status.ps1
   -Action update -Package X -Stage incubating -TestsStatus pass -Passed N
   -Failed 0 -RunBy <lane id> -Commit <feat sha> -ExcludedReason "publish
   pending: next scope delta"` -> record commit.
5. **Wrap + publish**: ops scope ask (+N) and WAIT for "<total> live"
   before editing the allowlist; append `.github/publish-allowlist.txt`;
   regenerate; **stage ALL pending `packages/*/STATUS.json` record
   changes in the wrap commit -- the tag commit is what CI's readiness
   guard reads (`eco-v0.1.38` tagged before `xiom.http`'s record and
   the guard skipped it; corrected in 39)**; `generate_index.ps1`,
   `status.ps1 -Action report`, validate,
   `allowlist-guard.ps1`, `export-namespaces.ps1`; commit + push; `git
   tag eco-v0.1.40` (next number) + push; approve the gate:
   `gh api repos/xiom-packages/packages/actions/runs/<id>/pending_deployments
   -X POST --input <{"state":"approved","environment_ids":[22424011031],
   "comment":"..."}>`; monitor; on `oidc_token_expired` rerun the failed
   job once + re-approve; verify each name's `latest` on the registry.
   No rate window needed for <=20 names (ops policy).
6. **Docs at every wrap**: append `docs/STDLIB-WISHLIST.md` rows +
   changelog; `docs/COMPILER-FINDINGS.md` for new compiler evidence;
   refresh this SESSION.md block + paste prompt.
7. **Carry-forwards**: (a) compiler hotfix watch -- when a new release
   lands (v0.62.3+), re-pin per `docs/MAINTENANCE.md`: bump
   `COMPILER_VERSION`, deploy release -> `xiom.new\bin` (exe + wasm dll),
   `status.ps1 -Action repin`, fleet sweep re-record, re-run
  `docs/repro/byte-at-128` AND all `docs/repro/v0622-regressions/`
   probes (the open v0.62.2 issues: Vec[Str].push global-Vec
   mis-lower, &mut Int scalar write-drop, mixed-bracket + widened
   full-angle laxness, type laxness beyond brackets, child->parent
   module import, nominal module-qualified type identity; expat/nbt
   silent -1 is RESOLVED -- sweep-harness race, do not re-file);
  (b) README Status-block
   sync for the 351 README-refresh names (one patch behind); (c)
   category harmonization = owner decision; (d) keep the port watchdog
   discipline.

### PASTE PROMPT FOR THE NEXT PACKAGES SESSION

```
You are the packages session for xiom-packages/packages (local
E:\xiom-packages\packages, remote github.com/xiom-packages/packages,
private). Read SESSION.md first -- the 2026-10-05 08:20Z STATE block and
the "Next-session operating kit" in section 0 are the live handoff
(v0.63.0 pinned + SHA256-verified; hardening batches #1-#5 published:
`eco-v0.1.44` uuid/csv/bson/ttl, `eco-v0.1.45` crc/cobs/varint/roman,
`eco-v0.1.46` bmp/rate/lru/tokenizer, `eco-v0.1.47`
metrics/retry/signal/stl, `eco-v0.1.48` alerting/robotics/thermo/audit
-- all with runtime contracts, thermo 19 Z3-proven; 259 stable packages
still at zero clauses; registry 459 packages + 2 infra; allowlist 499;
grpc `Vec[(Str,Str)]` STILL RED on v0.63.0 -- numeric match arms stay
blocked until a release carries the C001 root-cause fix; graphql 9/10;
`l10n-unicode` needs a >60s suite timeout and stays incubating).
Repo-local identity must be
"Lefteris Notas <lefterisnotas@gmail.com>". Publishing policy:
PRODUCTION-DIRECT batches (this session approves the registry-publish
gates); ops opens the publish-rate window ONLY for waves >20 names
(default 20/min otherwise); the ops scope enumeration must be confirmed
BEFORE appending an allowlist delta. New/next-touched records use stage
`incubating` (`stable` only via `docs/PROMOTION.md`).

Start by running: git fetch; git status -sb; git log -1; then
$env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"   # PATH
shadowing: a v0.62.3 staging dir precedes xiom.new
& .\scripts\status.ps1 -Action validate; & .\scripts\allowlist-guard.ps1

Then do, in order:
1. Open findings (with the compiler lane; do NOT re-run the same
   bisections -- both were re-tested RED on v0.63.0): graphql 9/10
   enum-payload in-situ (lead: variable-payload ctor flattening) and
   grpc `Vec[(Str, Str)]` 0xC0000005 (minimal group
   `packages\xiom-grpc\tests\probe_suite_min.xi` + `probe_direct.xi`,
   evidence `docs\repro\tuple-vec-set\`). When fixes land: re-test; if
   green, finish grpc (restore named-constant arms per m188, x2, record)
   and graphql (x2, record), then publish in one batch.
   `l10n-unicode` stays incubating; needs a >60s suite timeout under
   load (42-45s idle).
2. Hardening track: batches #1-#5 DONE + PUBLISHED (`eco-v0.1.44`
   uuid/csv/bson/ttl; `eco-v0.1.45` crc/cobs/varint/roman;
   `eco-v0.1.46` bmp/rate/lru/tokenizer; `eco-v0.1.47`
   metrics/retry/signal/stl; `eco-v0.1.48` alerting/robotics/thermo/
   audit). Next: batch #6 from the remaining grandfathered stable
   carriers (259 at zero clauses; see `scripts/contract-coverage.ps1`)
   per `docs/PROMOTION.md` -- contracts + API review; x2 on the pin;
   patch bump; record; publish. No ops delta. Claim the batch in
   SESSION.md before editing (concurrent-lane protocol). Watch the
   contract runtime-evaluator artifact (COMPILER-FINDINGS 2026-10-05):
   keep payload-length-vs-parameter-length and tuple-component clauses
   out of package sources until it is fixed.
3. Growth (optional): the remaining grandfathered set is FFI-class
   (skipped) except `kafka` (green suite but FFI stubs; needs a pure-XIOM
   redesign) and `zstd`/`lzfse` (FFI stubs).
4. Carry-forwards: keep the `-TimeoutSec 60` watchdog (raise per package
   when needed, e.g. `l10n-unicode`); byte-level bracket grep ONLY (Read
   lies about `Vec<Int>`); bump versions ONLY when source changes;
   `docs/repro/README.md` probe index for compiler evidence; registry
   page refresh = policy 1b; update SESSION.md at the wrap with a fresh
   paste prompt.
```

**--- Older state below (history) ---**

**STATE AT 2026-10-01 23:00Z (history):**
- **Wave 46 COMPLETE + PUBLISHED (`eco-v0.1.27`):** 10 new + the pending
  3 = 13 names: `chaincore` 24/24, `chaincrypto` 19/19, `defi` 28/28,
  `exchanger` 24/24, `geom3d` 27/27, `svm` 23/23, `nft` 20/20,
  `mechanics` 24/24, `materials` 26/26, `chromatography` 24/24, plus
  `sectest` 22/22, `mock` 20/20, `pwm` 20/20 (all verified port x2 +
  trap-14 on v0.62.2, records `incubating`; allowlist **432 -> 445**
  after ops confirmed the +3 was still pending from the previous day).
- **Current gates/state:** `validate` **460/0**; guard **445
  allowlisted / 396 ready / 49 grandfathered / 0 failures**; registry
  **396 packages + 2 infra = 398 entries**; allowlist **445**; all
  pushed.
- **FOURTH v0.62.2 compiler issue (filed + relayed):** `&mut Int`
  parameters DROP WRITES (silent wrong results; found by `xiom.svm`'s
  shuffle state). Workaround: thread scalar state through returns.
  `docs/COMPILER-FINDINGS.md` (2026-10-01 entry). The compiler lane's
  v0.62.2 bug batch now holds: `nbt`/`expat` silent exit -1,
  `Vec[Str].push` stride/i8 at clang, and this `&mut Int` write-drop.
- **Session-recovery pattern (repeatable):** output-limit crashes
  ("model hit its output limit while reasoning") are fixed by
  re-dispatching the lane with reasoning `variant: low` + a files-first,
  short-replies directive (worked for `lemmatization`, `consensus`,
  `boosting`, `materials`). AM sessions can't take a variant on resume:
  stop the AM session, re-dispatch as a `task` with `variant: low`.
- **New stdlib rows (wave 46):** saturating Int arithmetic, pinned
  rounding helpers (`div_round`/`div_ceil`), fixed-point multiply
  kernels, fixed-point trig + `isqrt`, typed-vector copy, table
  interpolation, group-by-key folds.
- **Follow-ups:** compiler lane bisecting the four v0.62.2 issues;
  README `Status` blocks for the 351 README-refresh names still lag one
  patch; category harmonization owner-decided; keep `-TimeoutSec 60`
  watchdog discipline; wave-47 candidates from the remaining
  pure-XIOM backlog: `context`, `metadata`, `icu`/`l10n-unicode`
  (table-heavy -- watch const-array materialization), `svm`-siblings,
  `actor`-siblings, `exchanger`-siblings (insurance/risk?), `web3`/
  `defi`-siblings, `chromatography`-siblings, `geom3d`-siblings.

**--- Older state below (history) ---**

**STATE AT 2026-09-30 19:25Z (history):**
- **Wave 45 COMPLETE + PUBLISHED (`eco-v0.1.26`):** all 10
  (`consensus` 20/20, `discovery` 22/22, `actor` 28/28, `itest` 24/24,
  `codegen-fw` 23/23, `compliance` 22/22, `legacy-proto` 24/24,
  `environment` 23/23, `boosting` 20/20, `optimizer-fw` 25/25) built on
  compiler **v0.62.2** + stdlib-perf1 by 5 `task` + 4 AM lanes
  (+1 task resume, +1 AM->task re-dispatch after output-limit crashes),
  port x2 + trap-14 verified, records `incubating`.
- **Current gates/state:** `validate` **450/0**; guard **432
  allowlisted / 383 ready / 49 grandfathered / 0 failures**; registry
  **383 packages + 2 infra = 385 entries**; allowlist **432**; all
  pushed.
- **THIRD v0.62.2 compiler issue found (wave 45):** `Vec[Str].push(s)`
  mis-lowers (stride 8, `i8` store -> clang rejects the IR; `--emit-ir`
  is clean, so it only surfaces at clang). Recorded in
  `docs/COMPILER-FINDINGS.md` with the workaround (single `Str` +
  parallel `Vec[Int]` offsets, as in `xiom.consensus`). Already relayed
  to ops/compiler alongside the `nbt`/`expat` silent-exit regressions
  (still with the compiler lane to bisect).
- **New stdlib defect row:** `xiom.string.index_of`/`str_contains`
  empty-needle runtime contract violation (`compliance` hit it); row in
  `docs/STDLIB-WISHLIST.md`.
- **Session-recovery pattern that works:** output-limit crashes ("model
  hit its output limit while reasoning") are recovered by re-running the
  lane with reasoning `variant: low` and a files-first, short-replies
  directive (confirmed on `lemmatization`, `consensus`, `boosting`).
  AM sessions cannot take a variant on resume -- stop the AM session and
  re-dispatch as a `task` with `variant: low` (done for `boosting`).
- **Follow-ups:** compiler lane to bisect `nbt`/`expat` (silent exit -1)
  and `Vec[Str].push`; README `Status` blocks for the 351
  README-refresh names still lag one patch; category harmonization
  owner-decided; ports keep the `-TimeoutSec 60` watchdog discipline.
- **Wave-46 candidates (remaining placeholder backlog):** `itest`-style
  utilities are exhausted; natural set: `context`, `chaincore`,
  `chaincrypto`, `exchanger`, `defi`, `nft`, `web3`, `geom3d`,
  `materials`, `mechanics`, `chromatography`, `metadata`, `icu`
  /`l10n-unicode` (table-heavy -- watch the const-array materialization
  row), `svm` (integer), `actor`-siblings.

**--- Older state below (history) ---**

**STATE AT 2026-09-30 (morning, history):**
- **Compiler re-pin v0.62.1 -> v0.62.2 DONE.** `COMPILER_VERSION` =
  `v0.62.2`; repo release `E:\xiom-lang\xiom\target\release` (v0.62.2)
  deployed into `%LOCALAPPDATA%\xiom.new\bin`; stdlib checkout tracks
  `stdlib-perf1` (`06d0ee7`). **byte_at battery
  `docs/repro/byte-at-128` = `bad=0`, exit 0 -- FIXED; the widen+mask
  workaround is RETIRED for new code.** `status.ps1 -Action repin`
  aligned 435 records to v0.62.2.
- **v0.62.2 fleet sweep DONE (439 implemented packages):** 376 green
  re-pointed to `fleet-sweep:v0.62.2` (`commit 984fc2f`). **2 real
  regressions among ready packages: `xiom.nbt` + `xiom.expat`** (silent
  `exit -1`, no stdout; flushed variants run expat 25/25 and nbt 25/26
  with one genuine UTF-8 strings failure in nbt); reported to the
  compiler lane via relay 2026-09-30 and documented in
  `docs/COMPILER-FINDINGS.md`. Everything else failing = the known
  declaration-only/FFI class (32 TYPECHECK + 9 DECL-ONLY + 14
  FFI/system stubs) + 5 load-flakes that re-ran green
  (`bibtex`/`badger`/`sectest`/`physics`/`xpm`).
- **Wave 44 COMPLETE + PUBLISHED:** all 10 (`lemmatization` 44/44,
  `layers` 22/22, `macro` 25/25, `stub` 22/22, `stats-tests` 25/25,
  `stats-ml` 22/22, `wallet` 20/20, `randomforest` 24/24,
  `smartcontract` 22/22, `formatter-fw` 23/23) built by 6 `task` +
  4 AM lanes (with two PC-shutdown resume rounds), port x2 + trap-14
  verified, recorded `incubating`, published: `eco-v0.1.23` (7),
  `eco-v0.1.24` (formatter-fw/randomforest/smartcontract),
  `eco-v0.1.25` (`formatter-fw` 0.1.1 manifest module normalization
  `xiom.formatter-fw` -> `xiom.formatter_fw`).
- **Current gates/state:** `validate` **440/0**; guard **422
  allowlisted / 373 ready / 49 grandfathered / 0 failures**; registry
  **373 packages + 2 infra = 375 entries**; all pushed (HEAD after the
  final wrap commit); nothing uncommitted except generated files
  committed at the wrap.
- **port.ps1 watchdog (must-keep):** `scripts/port.ps1` now enforces
  `-TimeoutSec` (default 120) per compiler invocation and tree-kills the
  run on timeout; `formatter-fw`'s runaway suite (stale work-stack index
  -> infinite push -> ~94GB RAM -> PC crashes) is the reason. Never run
  a package suite without the watchdog.
- **Follow-ups:** compiler lane to bisect `nbt`/`expat` v0.62.2
  regressions (repro logs under `%TEMP%\kilo\sweep-v0622*`); README
  `Status` blocks for the 351 README-refresh names still lag one patch
  (`published at v0.1.0` vs live `0.1.1`/`0.1.2`) -- sync at next
  refresh; category harmonization (invalid registry-category tokens)
  still owner-decided; `macro`/`stub` final reports lost to the
  2026-09-30 shutdowns (files verified green); wave-45 candidates from
  the remaining placeholder backlog (`itest`, `layers`-style utility
  names are exhausted -- next natural set: `itest`, `environment`,
  `discovery`, `compliance`, `legacy-proto`, `chaincore`, `wallet`-
  siblings, `codegen-fw`, `optimizer-fw`, `boosting`).
- **Policy unchanged:** incubating-by-default; `stable` by explicit
  promotion; PRODUCTION-DIRECT batches (this lane approves the
  registry-publish gates); staging only on explicit ask; ops scope ask
  BEFORE appending the allowlist delta; publish loop publishes every
  allowlisted unpublished name at its tag; "batch done" relay closes the
  rate window.

**--- Older state below (history) ---**

**STATE AT 2026-09-29 22:05Z (history):**
- **README-refresh program COMPLETE (`eco-v0.1.15..eco-v0.1.22`, pushed,
  owner window closed):** all **351** affected published names were
  patch-bumped and republished (298 -> `0.1.1`, 53 -> `0.1.2`); the
  `da3289f` READMEs are now live on the registry pages (7 batches of ~50
  + a 1-name tail `xiom.zookeeper` under `eco-v0.1.22`). Staging-first
  canaries (2 per batch, `xiom.acpi`/`adler32`/`cron`/`csv`/`geo`/
  `geography`/`locale`/`lockfree`/`packet`/`pagination`/`resolv`/
  `retry`/`template`/`term`) all verified before each production tag;
  ops held `PUBLISH_RATE_MAX=600` through the program and restores 20 on
  the "batch done" relay (sent 22:02Z).
- **Wave 43 COMPLETE + PUBLISHED:** all 10 (`cancel` 24/24, `stm` 20/20,
  `worker` 26/26, `messaging` 20/20, `plugin` 25/25, `countdown` 22/22,
  `diagrams` 34/34, `charts` 28/28, `parsing` 28/28, `ast` 24/24) built
  by 6 background `task` porters + 4 AM local sessions, rescue-integrated
  (port x2 + trap-14, AM reports extracted from `kilo.db`), recorded
  `incubating`, allowlist **402 -> 412**, published inside
  `eco-v0.1.18` at `0.1.0`.
- **Current gates/state:** pin `v0.62.1`; `validate` **430/0**; guard
  **412 allowlisted / 361 ready / 51 grandfathered / 0 failures**;
  registry **363 = 276 stable / 85 incubating / 2 infra**; allowlist
  **412**; working tree clean, `main` pushed at `7080fdb`; tags
  `eco-v0.1.15..22` (latest `eco-v0.1.22` on `7080fdb`). `xiom.hello`
  graduated grandfathered -> ready during the batches (suite green).
- **Publish-run quirks (recorded):** 50-name runs at 4s pacing outlive
  the 6-min OIDC token; tail reruns needed: 3, 1, 0, 13, 1, 0 names
  (`gh run rerun <id> --failed` + re-approve the gate; skips are fast).
  One benign `version_exists` skip-miss (`xiom.bech32` in
  `eco-v0.1.22`; registry index lag made the skip check think it was
  missing) -- rerun clean, nothing to fix.
- **New evidence recorded + committed (`9099575`):** COMPILER-FINDINGS:
  builtin shadowing (`worker`: `fn size_of` silently bound to
  `xiom.core.size_of[T]`), library-only `--emit-ir` C001
  (`Vec.clear`/`Vec.push`, same on `timer`), MCP stdlib discovery failing
  ("No stdlib directory found") + `xiom_check_xiom_syntax` timeouts;
  STDLIB-WISHLIST: `xiom.semver`, `xiom.string.xml`, `xiom.text.pos`,
  strict quoted-string/identifier codecs, `Vec[Str]` dedup, slot pools,
  latch/cancellation primitives, AST traversal, `sb_push_int` INT_MIN
  defect; `result`/`test.dispatch` requesters extended.
- **Follow-ups (carry forward):** `byte_at >= 128` direct-compare battery
  at the **next compiler release** (fixed on main `f4af5f64`, NOT in
  v0.62.1; keep the widen+mask workaround until then); **row 25
  (module-level const/table materialization)** next in the compiler
  backlog; `.github` OIDC per-run token; `tftp`/`tap` same-version
  decisions **RESOLVED** by the batches (both republished at bumped
  versions); registry-stage lags **self-corrected** (0 empty-stage
  packages remain -- 276/85/2); **README Status blocks now lag one
  patch** ("published at `v0.1.0`" while `0.1.1` is live) -- sync
  `published at` at the next README refresh (or next touch per
  MAINTENANCE.md); category harmonization (109 invalid registry-category
  tokens across ~70 manifests; registry ignores them) still owner-decided
  -- `adc`'s "engineering" rides its next bump; growth docs append at
  every wave.
- **Maintenance loop:** `docs/MAINTENANCE.md` (release-triggered, no
  lockstep versions); publish-batch trigger includes README sync; the
  registry ruling ("no version-less refresh, no registry dependency") is
  written into it.
- **Policy:** incubating-by-default; `stable` by explicit promotion only;
  PRODUCTION-DIRECT batches (this lane approves the publish gates);
  staging only on explicit ask -- the README-refresh batches were
  staging-first per the ruling.
- **Mechanics gotchas:** gate `port.ps1` on exit code; version bumps via
  the Edit tool per file; `fn`/`use`/`as` reserved; v0.62.1 binds `&`
  looser than `+`; `STATUS.json` machine-written (`ConvertTo-Json
  -Depth 6` shape); `status.ps1 -Action update` preserves the stage when
  `-Stage` is omitted (pass it anyway for batch refreshes); hashtable
  splatting when calling repo scripts from helper scripts (array splat
  binds positionally and fails ValidateSet); task/AM sessions can pause
  mid-wave (resume via task id / Agent Manager prompt; AM finals are
  readable from `kilo.db` part table); batch commits must stay surgical
  (`git add` exactly the batch's files) when other lanes write in the
  same tree; the publish loop publishes *every* allowlisted unpublished
  name at its tag -- never append an allowlist delta before ops confirms
  the scope enumeration.

**PASTE PROMPT FOR THE NEXT PACKAGES SESSION:**
```
You are the packages session for xiom-packages/packages (local
E:\xiom-packages\packages, remote github.com/xiom-packages/packages,
private). Read SESSION.md first -- the 2026-09-29 22:05Z STATE block at
the top of section 0 is the live handoff. Repo-local identity must be
"Lefteris Notas <lefterisnotas@gmail.com>". Publishing policy:
PRODUCTION-DIRECT batches (this session approves the registry-publish
gates); staging only on explicit ask. New/next-touched records use stage
`incubating` (`stable` only by explicit promotion).

Start by running: git fetch; git status -sb; git log -1; then
& .\scripts\status.ps1 -Action validate and & .\scripts\allowlist-guard.ps1.

Then do, in order:
1. README Status-block sync for the 351 republished names ("published at
   `v0.1.0`" now lags their `0.1.1`/`0.1.2`) -- decide with the owner
   whether to fold it into the next wave or a final chunked refresh.
2. Next wave from the SESSION backlog / owner ask: namespace-check new
   names, dispatch porters with the canonical 18-trap v0.62.1 briefs +
   XIOM MCP tools + no-commit rules + `stdlib gaps` reports, integrate
   as they report (port x2 + trap-14), scope ask to ops BEFORE allowlist
   append, wrap (allowlist, index/report/namespaces).
3. Growth + maintenance: append worker evidence at every wave; run the
   release-triggered loop in docs/MAINTENANCE.md on compiler/stdlib
   releases (targeted, no lockstep versions).
4. Follow-ups: `byte_at` battery at the next compiler release (fixed on
   main f4af5f64, not v0.62.1); row 25 next in the compiler backlog; OIDC
   per-run token; category harmonization when the owner rules.
```

**--- STATE AT 2026-09-29 17:35Z below (history; the program it
describes is complete -- see the 22:05Z block above) ---**

- **README-refresh republishes APPROVED -- hold lifted (owner relay
  17:31Z):** registry ruling = **no version-less refresh, no registry
  dependency**. Proceed with **chunked patch-bump republishes from
  `packages@da3289f`**, latest-version scope, **~50/batch, staging
  first**; ops supports the batches (publish-rate window +
  staging-first checks). **This is the next big task** (full recipe in
  the paste prompt below).
  - Affected set: **350 published packages** whose READMEs changed in
    `da3289f` (recompute: `git show --name-only da3289f` READMEs under
    `packages/*/`, intersected with the registry index).
  - Per package: next version = current latest + 1 patch (0.1.0 ->
    0.1.1; 0.1.1 -> 0.1.2); bump via the Edit tool per `package.xi`,
    re-run `port.ps1` green, refresh the record (same stage, fresh
    run/commit/checked), commit, wrap, tag, publish.
  - Known quirk: the full-allowlist loop (~9 min) can outlive the 6-min
    OIDC token; on `oidc_token_expired`, rerun the failed job once
    (skips are fast) -- 50-name batches may need 2 runs.
- **Current gates/state:** pin `v0.62.1`; validate **420/0**; guard
  **402 allowlisted / 350 ready / 52 grandfathered / 0 failures**;
  allowlist **402**; registry **353 = 242 stable / 73 incubating / 38
  empty**; `eco-v0.1.14` published 10/10 (wave 42); all 420 repo
  READMEs synced (`da3289f`); nothing uncommitted.
- **Wave 43 PREPPED, NOT dispatched:** 10 names namespace-checked clean
  (0 conflicts): `cancel`, `stm`, `worker`, `messaging`, `plugin`,
  `countdown`, `diagrams`, `charts`, `parsing`, `ast`. Deliverables:
  package.xi, src, conformance tests, README, SPEC, .gitignore; then
  6 background `task` porters + 4 AM local sessions with the canonical
  18-trap briefs (v0.62.1 edition; byte-at trap still live) + XIOM MCP
  tools + no-commit rules + `stdlib gaps` reports; integrate as they
  report; wrap (allowlist 402 -> 412 + scope ask to ops).
- **Compiler relay (recorded in `COMPILER-FINDINGS`):** `byte_at >= 128`
  direct compare **fixed on compiler main `f4af5f64`** (NOT in v0.62.1)
  -- re-run `docs/repro/byte-at-128` at the **next release**; only then
  retire the widen+mask workaround. **Row 25 (module-level const/table
  materialization)** is next in the compiler backlog.
- **Open follow-ups:** `.github` OIDC per-run token (above); `tftp`/`tap`
  same-version republish decisions (owner); registry-stage lags
  (`snapshot`, `mkv`, `snmp`, `imap`, `coverage`) self-correct at their
  next bump -- the README batches trigger exactly that; registry
  publish-time warning (accepted); `dimred` category fix rides its next
  bump; growth docs append at every wave.
- **Maintenance loop:** `docs/MAINTENANCE.md` (release-triggered, no
  lockstep versions); publish-batch trigger includes README sync; the
  registry ruling is written into it.
- **Policy:** incubating-by-default; `stable` by explicit promotion
  only; PRODUCTION-DIRECT batches (this lane approves the publish
  gates); staging only on explicit ask -- README-refresh batches are
  **staging-first** per the ruling.
- **Mechanics gotchas:** gate `port.ps1` on exit code; version bumps via
  the Edit tool per file; `fn`/`use`/`as` are reserved; v0.62.1 binds
  `&` looser than `+`; `STATUS.json` is machine-written (same
  `ConvertTo-Json -Depth 6` shape); task/AM sessions can pause (resume
  via task id / Agent Manager prompt); a parallel packages lane may work
  in this same tree (check `git status` before wraps; rescue
  green-but-unrecorded work per the 2026-09-29 pattern).

**--- History below (chronological, oldest first) ---**

**STATE AT 2026-09-29 00:55Z (history):**
- **Compiler field refresh DONE (`2183ac4`, pushed):** all 338 records
  still at `v0.61.3` now say `v0.62.0`. The 275 green records were
  re-pointed at the fleet sweep (`run_by: "fleet-sweep:v0.62.0"`,
  `commit: "ebf8ef2"`, `checked` = that package's sweep line time from
  `%TEMP%\kilo\sweep\v2-chunk*.log`); the 63 declaration-only/incubating
  records changed compiler-only (`validate` forbids run fields under
  `tests.status: unknown`). `validate` 397/0, `allowlist-guard` 379/0.
- **Correction-batch wrap DONE (`b6b0ba1`, pushed):** index.json /
  PACKAGE_STATUS.md / PACKAGE-NAMESPACES.txt regenerated (397 packages,
  421 modules); **`eco-v0.1.12`** tagged on the wrap commit.
- **`eco-v0.1.12` PUBLISHED (run `36491183775`, SUCCESS):** gate approved
  as soon as it waited; **53/53 `Published xiom.*@0.1.1`**, 0 failures.
  Every corrected name spot-verified in the registry at `0.1.1` with
  version-stage **incubating**. **Registry index now 330 = 239 stable /
  53 incubating / 38 empty** -- the stage correction is live; the 38
  legacy empty-stage entries ride natural bumps.
- **Wave 41 COMPLETE + WRAPPED (2026-09-28 23:31Z):** all 10 names
  integrated and recorded `incubating`; wrap commit `f65d301` (allowlist
  379 -> **392**: `inline-asm`, `pool`, `backoff` + `l10n-date`,
  `l10n-time`, `l10n-address`, `l10n-name`, `locale`, `dimred`,
  `semaphore`, `lockfree`, `hashchain`, `config`; index/report/namespaces
  regenerated) and **tag `eco-v0.1.13`** pushed; publish run
  `36498363143` approved at the gate. feats/records: semaphore
  `32b643a`/`d53081c`, l10n-address `1640406`/`eefd09e`, l10n-name
  `360cef3`/`f362580`, l10n-date `792b7d0`/`1ea5537`, locale
  `b70591b`/`e7cb4f9`, l10n-time `bb6e135`/`c002973`, config
  `0eb2fdd`/`d582f7c`, dimred `1cbbfe3`/`edc8323`, lockfree
  `4815569`/`d3c4035`, hashchain `5f78df6`/`cfc2ea7`. Tests: 18-28 each,
  double-run green; trap-14 clean on all ten. **History note:** the four
  l10n packages were renamed to the hyphenated publish convention in the
  wrap commit (modules stay dotted). Worker sessions were paused by a
  runtime event at 22:33Z and resumed at ~23:08Z (recovery: resume
  prompts via `task` and Agent Manager).
- **`eco-v0.1.13` PUBLISHED (run `36498363143`, SUCCESS):** **13/13
  `Published xiom.*@0.1.0`**, 0 failures (`inline-asm`, `pool`, `backoff`
  stable + the ten wave-41 incubating; 328 already-published skips).
  **Registry now 343 = 242 stable / 63 incubating / 38 empty.** Only
  warning: `dimred` category `math` ignored -- manifest corrected to
  `ai-ml`+`data` for its next bump (recorded in `STDLIB-WISHLIST`).
  **Next: relay the 392 allowlist bump to ops for the exact set
  re-verification; no rate window needed.**
- **Scope delta LIVE (ops relay 2026-09-28 22:51Z): 392 scopes on BOTH
  entries** (production `eco-release`, staging `eco-canary`), including
  `inline-asm`, `pool`, `backoff` + the wave-41 ten. Our allowlist is now
  **392** too (appended in `f65d301`) -- **relay the 392 bump to ops for
  the exact set re-verification**. No rate window was needed (13 names at
  4s pacing stayed under the 20 limit); `PUBLISH_RATE_MAX` stays 20.
  `tap` is already scoped (its restyle is same-version, tftp-class --
  owner decision later).
- **Follow-ups kept:** registry publish-time warning (accepted on the
  registry side, pending their 2.4.x item); `byte-at-128` battery queued
  compiler-side behind the flake-capture batch; `.github` OIDC per-run
  token re-mint finding (one token minted per run; >6 min batches can
  expire it); `xiom.tftp@0.1.0` version collision (owner decision: later
  bump or accept).
- **Maintenance loop (owner request 2026-09-28):** release-triggered and
  targeted -- no lockstep versions. Documented in `docs/MAINTENANCE.md`:
  compiler release -> repin + fleet sweep + fixes; stdlib release ->
  affected/`STDLIB-WISHLIST` packages; ops change -> allowlist + wrap +
  tag; dependents checked when a package publishes; every touch rides the
  next batch with a patch bump.
- **Policy unchanged:** incubating-by-default for new/next-touched
  records; `stable` only by explicit promotion; strict clauses ON;
  toolchain resolver source `repo-release` v0.62.0 (installed copy still
  0.61.3, bypassed; backup `%LOCALAPPDATA%\xiom\bin-0.61.3-backup`).
- **Pin bumped to v0.62.1 (2026-09-29 ~00:16Z):** compiler release
  `f965bd1c` confirmed (stdlib stays `stdlib-v0.62.0`). Batteries on the
  installed 0.62.1: arity T001 both directions, R53 `bad=0`, loop-CSE
  `bad=0`, sign-bit exit 0 -- all hold; **byte-at direct comparison still
  `bad=3`** (the compiler's item-10 "VERIFIED FIXED" covers only the
  explicit `as Int` cast path; keep the widen+mask workaround). **v3
  fleet sweep: 347/407 pass, 60 declaration-only, 0 regressions**; 407
  records refreshed (275 fleet-repointed to `fleet-sweep:v0.62.1` @
  `aec8efe`, worker provenance preserved, 132 compiler-only). validate
  407/0, guard 392/340/0.
- **Wave 42 DISPATCHED (2026-09-29 00:19Z, running):** 10 names,
  namespace-check clean (0 conflicts): `feature`, `loss`, `ensemble`,
  `streaming`, `linter`, `lexer-fw` (6 background `task` porters:
  `ses_f1578f59…`, `ses_f1578e62…`, `ses_f1578d79…`, `ses_f1578c52…`,
  `ses_f1578b48…`, `ses_f1578a1b…`) + `clustering`, `barrier`,
  `forkjoin`, `executor` (4 AM local sessions; request
  `am-1790641156596-9o3vll`). Briefs: canonical 18-trap list (v0.62.1
  edition; byte-at trap still live), XIOM MCP tools, no-commit rules,
  `stdlib gaps` reports. Integrate as they report; wrap when green
  (allowlist 392 -> 402 with the +10 scope ask at wrap, ops set
  re-verification due).
- **Wave 42 COMPLETE + WRAPPED (2026-09-29 ~00:55Z):** all 10 integrated
  and recorded `incubating` (feats/records on top of `e9b9fbb`); wrap
  commit this turn (allowlist 392 -> **402**; index/report/namespaces
  regenerated; validate **420/0**, guard **402 allowlisted / 350 ready /
  0 failures**). Tests 20-28 each, double-run green; trap-14 clean.
  **Rescue note:** a parallel packages lane (`ses_f26cdae1…`) ported
  `sectest`/`mock`/`pwm` (22/22, 20/20, 20/20) and stalled unrecorded at
  ~00:42Z; this session re-verified (port x2 each) and integrated them so
  the gates stay green -- their records use
  `agentmgr:ses_f26cdae1…`. **Scope ask: 392 -> 402 (+10) to ops.**
- **`eco-v0.1.14` PUBLISHED (run `36583479344`, rerun SUCCESS):** ops
  enumerated the +10 (402 confirmed on both entries, zero diff); the
  rerun published **10/10 `Published xiom.*@0.1.0`** (barrier,
  clustering, ensemble, executor, feature, forkjoin, lexer-fw, linter,
  loss, streaming), every version-stage `incubating`. **Registry now
  353 = 242 stable / 73 incubating / 38 empty.** Lesson: the first
  attempt failed `403 scope_denied` on all 10 because the enumeration
  hadn't landed yet; scope-denied retries also burn the 6-min OIDC token
  (secondary) -- confirm enumeration, then rerun.
- **README sync + registry-page caveat (2026-09-29):** all **420 repo
  READMEs synced** to records + live registry (`da3289f`): status blocks
  now state the true stage / conformance / published version; install
  sections point at the registry; **0 stale "NOT published" remain in
  published packages**. Caveat: **registry pages render the README
  frozen inside each published version** -- a page only changes when a
  new version is published. **Decision (owner 2026-09-29): ask ops first.**
  Ops answer (16:40Z): **no server-side metadata refresh exists** --
  pages render the README from the stored artifact (immutable by design);
  a refresh mechanism would be a registry-lane feature (conflicts with
  artifacts-as-source-of-truth + the upcoming C5 index digest) and is
  with them. **HOLD the chunked patch-bump until the registry lane
  answers**; if they decline, the 0.1.1 republish is the
  design-consistent fix and ops will support it with a publish-rate
  window + staging-first checks. Affected set = published packages whose
  READMEs changed in `da3289f` = **350 names** (recomputable:
  `git show --name-only da3289f` intersected with the registry index).
- **Mechanics gotchas:** gate `port.ps1` on its **exit code** (the PASS
  line is Write-Host, invisible to in-process capture); version bumps via
  the Edit tool per file; `fn`/`use`/`as` are reserved names; v0.62.0
  binds `&` looser than `+` (parenthesize bitwise/additive mixes);
  `STATUS.json` is machine-written -- refresh it through the same
  `ConvertTo-Json -Depth 6` shape (see `scripts/status.ps1`).

**PASTE PROMPT FOR THE NEXT PACKAGES SESSION:**

```
You are the packages session for xiom-packages/packages (local
E:\xiom-packages\packages, remote github.com/xiom-packages/packages,
private). Read SESSION.md first -- the 2026-09-29 17:35Z STATE block at
the top of section 0 is the live handoff. Repo-local identity must be
"Lefteris Notas <lefterisnotas@gmail.com>". Publishing policy:
PRODUCTION-DIRECT batches (this session approves the registry-publish
gates); staging only on explicit ask -- note the README-refresh batches
are STAGING FIRST per the registry ruling. New/next-touched records use
stage `incubating` (`stable` only by explicit promotion).

Start by running: git fetch; git status -sb; git log -1; then
& .\scripts\status.ps1 -Action validate and & .\scripts\allowlist-guard.ps1.

Then do, in order:
1. README-refresh republishes (hold lifted, owner relay 17:31Z). Chunked
   patch bumps + republishes for the 350 published packages whose READMEs
   changed in `da3289f`; ~50 per batch; staging first; ops supports with
   a publish-rate window.
   Recipe per batch:
   a. Compute the batch list: `git show --name-only da3289f` READMEs
      intersected with the registry index; pick ~50; for each, next
      version = current latest + 1 patch (0.1.0 -> 0.1.1, 0.1.1 -> 0.1.2).
   b. Bump each `package.xi` with the Edit tool (one file at a time --
      the version-bump rule), re-run
      `& .\scripts\port.ps1 -Package <pkg>` until green (gate on exit
      code), then refresh each record via `status.ps1 -Action update`
      with the same stage and fresh run/commit/checked.
   c. Commit bumps + records; wrap: `generate_index.ps1`,
      `status.ps1 -Action report`, validate, allowlist-guard,
      `export-namespaces.ps1`; commit.
   d. Ping ops for the publish-rate window (relay wording in session
      history); tag `eco-v0.1.x`; push; approve the gate as soon as it
      waits; monitor; verify the "Published xiom." lines and the
      registry count. The full loop (~9 min) can outlive the 6-min OIDC
      token -- on `oidc_token_expired`, rerun the failed job once (skips
      are fast); 50-name batches may need 2 runs. Do ops's staging
      check first if the window instructions say so.
2. Wave 43 (prepped, 10 names namespace-checked clean): `cancel`,
   `stm`, `worker`, `messaging`, `plugin`, `countdown`, `diagrams`,
   `charts`, `parsing`, `ast`. Dispatch 6 background `task` porters + 4
   AM local sessions with the canonical 18-trap v0.62.1 briefs + XIOM
   MCP tools + no-commit rules + `stdlib gaps` reports; integrate as
   they report; wrap when green (allowlist 402 -> 412 + scope ask to
   ops). If a parallel lane stalls green-but-unrecorded and blocks the
   gates, rescue-integrate it (verify port x2 + trap-14, then feat +
   record with the lane's session id -- the 2026-09-29 pattern).
3. Growth + maintenance: append worker `stdlib gaps` / compiler evidence
   at every wave and regenerate `docs/PACKAGE-NAMESPACES.txt` at wrap;
   run the release-triggered loop in `docs/MAINTENANCE.md` on
   compiler/stdlib releases (targeted, no lockstep versions).
4. Follow-ups: `byte_at` battery at the next compiler release (fixed on
   main `f4af5f64`); row 25 next in the compiler backlog; OIDC per-run
   token; `tftp`/`tap` same-version decisions; registry-stage lags
   self-correct at the README-batch bumps; registry publish-time warning.
```

- **Wave 34 (dispatched 2026-09-26 23:31Z; COMPLETE for greens):** names
  `webp, jpeg, flac, eeprom, i2c, nats, ldap, upnp, golden, meteorology`.
  The `task` subagent provider hit **"Insufficient Balance"** ~23:45Z and
  killed all six background tasks (environmental; Agent Manager local
  sessions were unaffected and carried the wave). Nine packages are green
  and pushed -- `webp` 20/20, `flac` 18/18, `jpeg` 16/16, `eeprom` 17/17,
  `meteorology` 22/22, `upnp` 18/18, `ldap` 20/20 -- and tagged:
  the six greens ride `eco-v0.1.4`; `ldap` rides `eco-v0.1.5`. Coordinator
  and AM fixes were needed: `jpeg` (SOF-family predicate rejected the
  supported SOF0/1/2; DRI length 4 -> 2; `app_length` stores the declared
  segment length; in-scan FF fill semantics; Nf=0 order; baseline Se
  offset; test fixtures), `flac` (test sync-byte typo + docs), `upnp`
  (v0.61.3 `&mut Int` write-through miscompile -> value-returning
  `VersionParts`; test offsets). Trap-14 audits clean. Still unbuilt:
  `i2c, nats, golden` (re-dispatched to AM sessions); docs for
  `jpeg`/`meteorology` also re-dispatched.
- **Wave 35 (dispatched 2026-09-27 00:45Z; COMPLETE (10/10)):**
  `spi` 22/22, `uart` 21/21, `adc` 18/18, `rtc` 18/18, `bonjour` 24/24,
  `multicast` 18/18, `orc` 33/33, `coverage` 22/22, `pgp` 22/22, `sd`
  21/21 -- 239 tests, all recorded, allowlisted, and tagged as `eco-v0.1.5`
  (with `ldap`). AM-only wave (task subagents still balance-dead); one
  trap-14 fix (`sd` had 7 malformed `Vec<UInt8]`/`Vec<UInt8>` brackets).
  `scripts/namespace-check.ps1` now skips `.kilo`/`.git` paths (a stale
  Agent Manager worktree inside the stdlib repo broke the scan).
- 341 implemented dirs / 191 README-only placeholders; **274 stable / 4
  ported / 63 incubating**; **278 green suites / ~5,984 recorded tests**;
  allowlist **326** (274 ready + 52 grandfathered); `validate` = 341/0.
  Wave-35 wrap commit `55cc303`; wave-33 wrap `471c5e3`.
- **Wave 33: COMPLETE (10/10).** `imap` 18/18, `avro` 20/20, `mp3` 21/21,
  `gif` 20/20, `mkv` 20/20, `amqp` 21/21, `png` 17/17, `mp4` 33/33,
  `snmp` 19/19, `thrift` 24/24 -- 213 tests, all seeded `stable` with
  RunBy/Commit records, allowlisted by the wrap. Trap-14 audits clean on
  every package (the write tooling reintroduced mixed brackets in `gif` and
  `mp3`; both fixed pre-commit).
- **Wave 32: COMPLETE (10/10).** `xiom.rpm` was recovered on the third
  attempt (skeleton-first brief; 19/19; `b7fc365` + record `d9f12a2`; the
  resolution is recorded in `docs/failed_attempts.md`). Wave-32 wrap commit
  `dccebd1` added **9** allowlist names (`pop3, smtp, ftp, passwd, efi, hid,
  cab, pci, rpm`); `xiom.tftp` was already allowlisted since wave 15
  (`f4ff9fa`), so the intended 10-name append was 9 net-new. Index/report
  regeneration was deferred to the wave-33 wrap so the wrap commit would
  not capture the ten in-flight wave-33 dirs as `(none)` rows.
- **Production `eco-v0.1.1`: SUCCESS** -- attempt 3, 15:02Z, run
  `36240424222`; registry index 231 packages at that point.
- **Production `eco-v0.1.2` (waves 31+32, 19 new names): SUCCESS --
  attempt 4, 17:23:22Z, run `36251091427`.** Attempts 1-3 failed with
  registry `scope_denied` (403) because the publisher entry lacked the 19
  names; ops enumerated them (299 scopes = waves 18-30 superset 280 + the
  19; production `eco-release` and staging `eco-canary`, both services
  recreated) and attempt 4 published all 19 in ~4 minutes. **Registry index
  now carries 250 packages**; the waves 18-32 production set is fully
  published. "Batch done" confirmed to ops (rate limit restores to 20/min).
- **Production `eco-v0.1.3` (wave 33, 10 names): SUCCESS (2026-09-26
  23:06:41Z).** Tag `eco-v0.1.3` on `471c5e3`; run `36278244028` published
  all 10 (`png, gif, mp3, mp4, mkv, snmp, imap, amqp, thrift, avro`) in
  ~3 min, each with `stage: "stable"` stamped from STATUS.json. **Registry
  index now carries 260 packages.**
- **Production `eco-v0.1.4` (wave-34 greens, 6 names): CUT, BLOCKED on the
  scope delta (2026-09-27 00:34Z).** Tag `eco-v0.1.4` on the interim wrap
  `9820db7` (allowlist + `webp, flac, jpeg, eeprom, meteorology, upnp`);
  run `36282607173` failed 00:34Z with HTTP 403 `scope_denied` for
  `xiom.eeprom`, `xiom.flac`, `xiom.jpeg` etc. -- the **309 -> 319 delta
  pre-requested at 23:31Z is not live yet**. Rerun `36282607173` after ops
  enumerates; do not re-cut the tag. The other four wave-34 names
  (`i2c, nats, golden, ldap`) ride `eco-v0.1.5` once green.
- **Production `eco-v0.1.5` (wave-35 + ldap, 11 names): CUT, run waiting at
  the gate (2026-09-27 ~12:15Z).** Tag on the wave-35 wrap `55cc303`; run
  `36318371174` is deliberately left **unapproved** (waiting) because the
  scopes are still missing -- approving now would only fail with
  `scope_denied` (as `eco-v0.1.4` did). Approve the moment ops confirms; it
  publishes 11 names and skips anything already published.
- **Ops lane settled (2026-09-27 12:50Z)**: batch-done acknowledged --
  production index **277**, all 17 new names live, both runs clean.
  `PUBLISH_RATE_MAX` restored to the normal **20** (D5) with a
  badge/visual/A1 rebuild; both publisher entries remain at **326 scopes**
  (`eco-release` production, `eco-canary` staging). Nothing pending from
  the packages side until the next wave group.
- **Wave-34 stragglers COMPLETE (2026-09-27 ~14:15Z):** `golden` 35/35
  (`9ce3a53`/`07a0022`), `i2c` 20/20, `nats` 21/21 -- integrated by the
  parallel lane, re-verified here (ports + trap-14 clean); wrap `93a9f82`,
  tag **`eco-v0.1.6`** (run `36325286939`, waiting at the gate).
- **Wave 36: COMPLETE (10/10), owned by the parallel lane.** `pki` 20/20,
  `merkle` 22/22, `apple` 21/21, `geology` 26/26, `biology` 18/18,
  `l10n-currency` 24/24, `gpio` 21/21, `interrupt` 20/20, `flash` 20/20,
  `tls` 20/20 -- 212 tests; integrated, recorded, wrapped (allowlist 339,
  index/report/namespaces regenerated, commit `d0ecf72`) and tagged
  **`eco-v0.1.7`** (run `36327834576`, queued in the concurrency group
  behind `eco-v0.1.6`). The lane also appended the wave-36 `stdlib gaps` +
  compiler evidence to the growth files (`fcd2c01`, `1380d78`). Checkpoint
  spot-verified `tls`/`pki`/`gpio` by re-running ports; trap-14 audit clean
  across all ten.
- **Wave 37: COMPLETE (10/10), parallel lane.** `mongo, memcached,
  cassandra, ssh2, tor, oauth, ethereum, zigbee, nlp, zookeeper`
  (per-package counts in STATUS records; e.g. nlp 27/27, oauth 25/25,
  cassandra 24/24, zookeeper 24/24); wrapped in `2c13f20` (allowlist **349**,
  index/report/namespaces regenerated), tagged **`eco-v0.1.8`** (run
  `36334928264`, pending in the concurrency group). The lane also appended
  the wave-37 stdlib gaps/compiler evidence and added a **public README**
  (`776e369`, website relay).
- **Wave 38: COMPLETE (10/10) and wrapped (2026-09-27 17:58Z).**
  `bitcoin` 20/20, `proxy` 20/20, `pulsar` 27/27, `bolt` 18/18,
  `wireless` 33/33, `leveldb` 18/18, `logging` 22/22, `dac` 20/20,
  `timer` 21/21, `aviation` 21/21 -- 220 tests, all stable with
  RunBy/Commit records, trap-clean. `wireless` and `proxy` brief tables
  (control subtypes, TLV registry) were corrected to the IEEE/HAProxy
  canonical tables pre-commit; `bitcoin`/`leveldb`/`bolt` corrected
  their own brief details to upstream. Wrap `a96235b`: allowlist 349 ->
  **359**, validate 374/0, guard 359/0 (307 ready), namespaces 374 pkgs /
  398 modules. Growth docs: all ten wave-38 reports appended
  (`188505d`, `a96235b`).
- **Wave 40: COMPLETE (10/10) and PUBLISHED (2026-09-28 00:45Z).**
  `parquet` 20/20, `pdf` 25/25, `etcd` 26/26, `windows` 25/25, `perf`
  20/20, `geography` 21/21, `dynamo` 21/21, `keymgmt` 20/20, `auth`
  24/24, `monitoring` 24/24 -- 226 tests. Wrap `bd4ea78`: allowlist
  369 -> **379**, validate 397/0, guard 379/0 (327 ready), namespaces
  397 pkgs / 421 modules. **`eco-v0.1.10` published the wave-39 ten and
  `eco-v0.1.11` the wave-40 ten: 20 names, 0 failures.** A parallel lane
  also left `inline-asm` (24/24), `pool` (22/22), `backoff` (22/22) and a
  cosmetic `tap` restyle, all integrated as stable in `2f0c4b0..b53215e`
  but **not allowlisted** -- they head the next scope request (target
  **382**).
- **Publish-metadata correction (registry relay, 2026-09-28 15:10Z):** the
  registry reports (and the production index confirms) **330 published
  packages: 292 `stage: stable`, 38 empty, 0 incubating** -- so first-party
  ports render as "Official package, signed by the publisher" with no
  incubation signal. Mechanism verified: `scripts/status.ps1` records every
  conformance-green package as `stable` (its written rule), and
  `publish-registry.yml` writes that stage into the manifest and only
  publishes `stage=stable && tests=pass` to production (an incubating
  publish path exists only via the staging-only `stage badge canary`
  override). Registry has no backfill: a real published stage beats display
  overrides, so corrected metadata requires patch-version republishes.
  **Decision pending (owner):** default published stage for first-party
  packages (incubating vs stable), the affected set, and republish urgency;
  the registry offers a publish-time warning (stable + incubator-repo
  provenance) as a 2.4.x safety net. Evidence: `registry.xiom-lang.org/index.json`
  (330/292/38/0).
- **Publish-metadata policy DECIDED and implemented (2026-09-28 15:20Z):**
  owner chose **incubating-by-default** for first-party packages; corrected
  republishes **start with today's 53** (`0.1.9`+`0.1.10`+`0.1.11` sets) and
  ride each package's next version bump for the rest; registry warning
  accepted. Pipeline updated: `status.ps1` (publish=true allows
  incubating|stable), `allowlist-guard.ps1` (ready = incubating|stable +
  tests=pass), `publish-registry.yml` readiness rule + header, README
  maturity section. **New integration records must use
  `-Stage incubating`** unless the owner promotes a package; the 53-package
  correction batch bumps to 0.1.1, re-runs, records `incubating`, and ships
  as the next tag(s). The 38 empty-stage legacy entries ride natural bumps.
- **v0.62.0 migration (2026-09-28 18:45Z):** compiler lane shipped v0.62.0
  (strict clauses ON); toolchain deployed to the resolver release dir
  (`E:\xiom-lang\xiom\target\release`; installed copy left below pin,
  backup at `%LOCALAPPDATA%\xiom\bin-0.61.3-backup`), pin bumped to
  `v0.62.0` (`25506bf`). Batteries re-run: **arity VERIFIED fixed**
  (`error[T001]` both directions; control green), **R53 `&mut`
  plain-local write-through VERIFIED fixed** (`bad=0`), `byte-at-128`
  still open (`bad=3`), CSE/sign-bit clean (queue items). **Fleet sweep
  COMPLETE: 329/397 pass on v0.62.0.** 60 failures are non-publishable
  incubating/declaration-only (expected). **8 verified packages broke
  and are fixed + re-recorded as `incubating` (`a57f40b`):** six arity
  restorations (`coverage`, `imap`, `l10n-currency`, `mkv`, `snapshot`,
  `snmp`), one precedence parenthesization (`mssql`: `&` now binds
  looser than `+`), one stdlib workaround (`flags`: `io.parse_int` fails
  codegen with unresolved `is_empty` -- report to the stdlib lane).
  Mixed-bracket strictness still pending (flip held one release).
- **Compiler ack (2026-09-28 20:28Z):** arity + R53 confirmations received;
  **byte-at-128 stays queued behind the transient `program_exit=-1`
  capture batch** (our battery at `docs/repro/byte-at-128/` stands ready).
- **Correction batch (stage-corrected republish) -- NEXT WORK, mechanics
  pinned:** target = the 53 names published by today's runs
  (`36338915735` + `36354376232` + `36364462846`; re-derive from their
  logs). Per package: bump `version: "0.1.0"` -> `"0.1.1"` in
  `package.xi` (Edit tool per file; no scripted text munging), re-run
  `port.ps1` until green, record `-Stage incubating -TestsStatus pass`
  with the bump commit, commit feat+record, push per slice (~13/wakeup).
  Then regenerate index/report, wrap, cut `eco-v0.1.12`, and publish --
  the names are already within the live 379 scopes, so no ops ask is
  needed for the corrected versions.
- **Correction batch COMPLETE (2026-09-28 21:55Z): 53/53 done.** All four
  slices (`parquet`..`monitoring`; `golden`..`memcached`;
  `cassandra`..`leveldb`; `logging`, `dac`, `aviation`, `timer`, `git2`,
  `mysql`, `mssql`, `db2`, `expat`, `zkp`, `cache`, `l10n-phone`,
  `l10n-unit`, `badger`) are at **0.1.1**, green on v0.62.0, recorded
  `incubating` (`722a912` .. `a778967`). **Remaining: the final wrap
  (regenerate + commit + push + tag `eco-v0.1.12`) and the gate approval
  (names already scoped).**
- **Gate queue (ops confirmed 2026-09-27 21:56Z / 379 live 22:25Z):**
  production `eco-release` = **379 scopes** (staging same), ops HEAD
  `525fff6`; registry production 2.3.0 -> **2.4.2** (accounts SQLite +
  admin hierarchy), email on, rate restored to 20 then re-opened to 600
  for this batch window. **`eco-v0.1.9` (33 names), `eco-v0.1.10`
  (wave-39 ten) and `eco-v0.1.11` (wave-40 ten) all completed SUCCESS --
  53 names published across the three runs with 0 failures; production
  registry ~330.** No runs pending; the next scope ask is **382** for
  `inline-asm`/`pool`/`backoff` plus any wave-41 names. **`eco-v0.1.12`
  (correction batch, 53 names at 0.1.1/incubating) is to be cut on the
  next wrap -- approve its gate as soon as it waits (already scoped).**
  Never re-cut tags.
- **Totals (2026-09-27 ~17:58Z):** 374 tracked / **307 stable / 4 ported /
  63 incubating**; allowlist **359**; registry 277 until the gates clear.
  Registry `/health`: last restart 12:47:16Z v2.2.0 (predates the scope
  requests -- scopes unconfirmed).
- **Batch wrap 1 (2026-09-27 14:16Z, lane `ses_f1cfdad42ffe`):** `i2c`
  (feat `177a3c4` + record `d5e1bfb`, 20/20) and `nats` (feat `b3fc3f5` +
  record `b1f228d`, 21/21; trap-14 sweep normalized 18 `Vec<...>` sites
  pre-record) are integrated; jpeg/meteorology docs are committed
  (`902dc05`/`642ea45`). Wrap `93a9f82`: allowlist 326 -> **329**
  (`i2c, nats, golden`), index/report/namespaces regenerated; validate
  344/0, allowlist-guard 329/0 (277 ready). **`eco-v0.1.6` is cut on
  `93a9f82`; run `36325286939` is WAITING at the registry-publish gate.**
- **Wave 36: COMPLETE (10/10) and wrapped (2026-09-27 14:58Z).**
  `pki` 20/20, `merkle` 22/22, `apple` 21/21, `geology` 26/26,
  `biology` 18/18, `l10n-currency` 24/24, `gpio` 21/21, `interrupt`
  20/20, `flash` 20/20, `tls` 20/20 -- 212 tests, all `stable` with
  RunBy/Commit records, trap-14 clean (worker greps verified + re-run by
  the coordinator). Wrap `d0ecf72`: allowlist 329 -> **339**, validate
  354/0, guard 339/0 (287 ready), namespaces 354 pkgs / 378 modules.
  **`eco-v0.1.7` is cut on `d0ecf72`; run `36327834576` is PENDING at
  the registry-publish gate.**
- **Scope delta history:** 326 -> 329 (`eco-v0.1.6`) -> 339 (requested
  for `eco-v0.1.7`) -> **349** (current, `eco-v0.1.8`; see the scope
  bullet below).
- **Worker-report extraction channel (new):** AM final reports and their
  `stdlib gaps` sections are readable from
  `C:\Users\lefte\.local\share\kilo\kilo.db` (SQLite `part` table,
  `$.text` parts joined to `message` on role; use the Android SDK
  `sqlite3.exe`) -- avoids transcript re-reads. All straggler + wave-36
  reports were appended to `docs/STDLIB-WISHLIST.md` and
  `docs/COMPILER-FINDINGS.md`.
- **Wave notes:** `l10n-currency`'s manifest is `xiom.l10n-currency` but
  the module must be `xiom.l10n.currency` (v0.61.3 rejects `-` in module
  names, `error[P001]`); documented in its README/SPEC. `tls` ships 7
  benign E001 borrow warnings in tests (stable, exit 0).
  `l10n-currency`'s session briefly stopped stray `xiom` processes that
  belonged to a concurrently running stdlib smoke batch (it respawned; no
  repo files touched) -- watch for cross-lane process collisions.
- **Wave 37: COMPLETE (10/10) and wrapped (2026-09-27 16:54Z).**
  `mongo` 23/23, `memcached` 22/22, `cassandra` 24/24, `ssh2` 24/24,
  `tor` 20/20, `oauth` 25/25, `ethereum` 23/23, `zigbee` 26/26, `nlp`
  27/27, `zookeeper` 24/24 -- 238 tests, all stable with RunBy/Commit
  records, trap-14 clean. Recipe restored: **6 background `task` porters +
  4 AM sessions**. Wrap `2c13f20`: allowlist 339 -> **349**, validate
  364/0, guard 349/0 (297 ready), namespaces 364 pkgs / 388 modules.
  **`eco-v0.1.8` is cut on `2c13f20`; run `36334928264` is PENDING at the
  registry-publish gate.**
- **Public README added (2026-09-27 16:56Z, website-lane relay):**
  `README.md` owns the method (AI-assisted porting under review, the
  conformance/pinning/gate process) and frames `SESSION.md` + `docs/` as
  the internal record kept public on purpose. Commit `776e369`. Tone is
  matter-of-fact by request; if the framing needs changing, raise it with
  the website lane rather than editing it halfway.
- **Wave 38 dispatched (2026-09-27 ~16:56Z):** `bitcoin, proxy, pulsar,
  bolt, wireless, leveldb, logging, dac, aviation, timer` -- all
  namespace-check clean on 1644 stdlib namespaces. **6 background `task`
  porters** (bitcoin, proxy, pulsar, bolt, wireless, leveldb) + **4 AM
  sessions** (logging, dac, aviation, timer). Integrate + wrap as they
  report; next tag `eco-v0.1.9`, scope target 359.
- **Scope delta: 326 -> 359 (current).** 326 + 3 stragglers + 10 wave-36 +
  10 wave-37 + 10 wave-38 = **359**; wave 38 adds `xiom.bitcoin`,
  `xiom.proxy`, `xiom.pulsar`, `xiom.bolt`, `xiom.wireless`,
  `xiom.leveldb`, `xiom.logging`, `xiom.dac`, `xiom.aviation`,
  `xiom.timer`. **After ops confirms 359, approve `36325286939` (0.1.6)
  first, then `36338915735` (0.1.9) when it starts; 0.1.7/0.1.8 were
  concurrency-cancelled and need no rerun -- the newest loop publishes
  every allowlisted unpublished name. Never re-cut a tag.**
- **`task` subagent lane restored (2026-09-27):** the global
  `kilo.jsonc` still pointed `subagent_model`, `subagent_variant_overrides`
  and the `explore` agent at the nonexistent
  `deepseek-v4-flash/deepseek-v4-flash`; all references corrected to
  `deepseek/deepseek-flash` (variant `max`) and the duplicate override key
  deduped. Probe returns `PROBE OK`; wave 37 uses the 6 + 4 mix again.
- **Compiler relay handled (2026-09-27):** compiler lane reports row 8
  (arity validation) fixed in its item-3 batch; the packages re-test is
  committed at `docs/repro/arity-laxness/` (v0.61.3 baseline re-confirmed:
  control green; missing/extra-arg probes print `SILENT-ACCEPT` and exit
  10/12). Their severity-ordered follow-ups are recorded in
  `docs/COMPILER-FINDINGS.md`; a resolution note will be relayed once
  item 3 is committed. Re-test and update the findings doc when the new
  build is installed.
- **Compiler relay #3 handled (2026-09-27 21:30Z):** compiler lane confirmed
  the transient `program_exit=-1` flake (empty output, 0 diagnostics, green
  on re-run) matches its own e2e silent-failure signature (31-32 spurious
  m35 compiles per run) -- recorded in `docs/COMPILER-FINDINGS.md` as a
  cross-lane-corroborated flake class, not machine load. Website lane was
  told the `W001` dual-stdlib noise originates from
  `%TEMP%\kilo\stdlib_ws\compiler_main3`. **Production greenlight granted
  (owner, 21:19Z): `eco-v0.1.6` approved and publishing; `eco-v0.1.9`
  approved when it reaches the gate.**
- **Compiler relay #2 handled (2026-09-27 20:10Z):** row 8 is **RESOLVED**
  by pin `0c50ac6` / commit `0f3f5083` (local-only until the release push)
  -- moved to `docs/COMPILER-FINDINGS.md` Resolved, re-test ready at
  `docs/repro/arity-laxness/` for the next installed build. Four repro
  batteries added per their triage: `mut-int-write-through/` **REPRODUCED**
  (plain calls to `&mut T` params write to a copy; 6/7 variants; explicit
  `&mut` correct -- upnp's VersionParts family), `byte-at-128/`
  **REPRODUCED** (direct `byte_at(...) == 195u8` compares wrong),
  `loop-carry-cse/` (reductions clean; exact pre-fix amqp fragment
  included) and `sign-bit-ops/` (clean incl. negatives/wrapped; family
  evidence radiotap/can). CSE and `&mut` remain accepted compiler-lane
  repro-first candidates; mixed-bracket strictness is planned.
- **Wave 39: COMPLETE (10/10) and wrapped (2026-09-27 22:10Z).** `git2`
  24/24, `mysql` 20/20, `mssql` 20/20 (MS-TDS type tokens corrected
  pre-commit), `db2` 22/22 (verified DRDA codepoints), `expat` 25/25,
  `zkp` 20/20, `cache` 26/26, `l10n-phone` 23/23, `l10n-unit` 24/24,
  `badger` 21/21 -- `badger` was rewritten after integration to real
  upstream v1.6.2 layouts (`0a881c0`, verified against fetched sources;
  the brief-layout version was superseded pre-publish). Wrap `8286b12`:
  allowlist 359 -> **369**, validate 384/0, guard 369/0 (317 ready),
  namespaces 384 pkgs / 408 modules. **`eco-v0.1.10` is cut on `8286b12`;
  run `36354376232` is WAITING at the gate -- request the +10 scopes
  (369) from ops, then approve.**
- **Wave 35 (dispatched 2026-09-27 ~00:45Z; COMPLETE (10/10), AM-only):**
  `spi` 22/22, `uart` 21/21, `adc` 18/18, `rtc` 18/18, `bonjour` 24/24,
  `multicast` 18/18, `orc` 33/33, `coverage` 22/22, `pgp` 22/22, `sd`
  21/21 -- 239 tests, recorded and allowlisted. One trap-14 fix (`sd`, 7
  malformed brackets). `task` subagents still balance-dead; AM-only until
  the provider balance is topped up.
- **Workflow finding (secondary):** the publish job mints **one** OIDC
  token at job start and reuses it for every package; runs longer than
  ~6 min fail every remaining publish with `oidc_token_expired` (the retry
  storm on the 19 blocked names is what pushed `eco-v0.1.2` past the token
  life). Re-minting per attempt (or on 401) is a
  `.github/workflows/publish-registry.yml` fix for the .github session.
- **tftp version collision (owner decision):** `xiom.tftp@0.1.0` in the
  registry is the 2026-09-24 build published by `eco-v0.1.1` from tag
  `a6e678e` (STATUS record `be38152`); the wave-32 rewrite (`ae3c233`)
  carries the same version and cannot republish (versions immutable).
  Either accept the published build or bump tftp to 0.1.1 in a later batch.
- **Production-direct policy is in force** (owner standing instruction,
  section 5): one `eco-*` tag per ready batch, gate approvals handled by
  this session; staging only when the owner explicitly asks for it.

**Next actions, in order:**
1. **Relay the registry/ops scope enumeration (blocking both tags)**: the
   six wave-34 greens `xiom.webp, xiom.flac, xiom.jpeg, xiom.eeprom,
   xiom.meteorology, xiom.upnp` plus the wave-35 set `xiom.ldap, xiom.spi,
   xiom.uart, xiom.adc, xiom.rtc, xiom.bonjour, xiom.multicast, xiom.orc,
   xiom.coverage, xiom.pgp, xiom.sd` (309 -> 326). On confirmation:
   (a) approve the pending `eco-v0.1.5` gate (run `36318371174`, waiting
   unapproved on purpose), and (b) `gh run rerun 36282607173` + approve
   (`eco-v0.1.4`). Both skip published versions.
2. Integrate the wave-34 stragglers as the AM sessions report: `i2c, nats,
   golden` (allowlist +3, wrap, own tag) and the jpeg/meteorology docs
   (commit `docs:` changes; no gate impact).
3. Badge-override follow-up (registry lane): audited, display-only
   override for historic empty-stage entries -- decision sent (`9da3143`,
   section 5); needs the generated name->stage list from `STATUS.json`
   handed over if they build it.
4. `task` subagents remain balance-dead; AM sessions only until the
   provider balance is topped up.

**Ecosystem growth coordination (2026-09-27, owner request; hand-to-hand with the stdlib session):**
- `docs/STDLIB-WISHLIST.md` -- the shared idea dump from packages to the
  stdlib session: missing helpers/modules that N packages re-implement,
  with requesters and today's local workarounds. Workers report gaps in
  the final message of their task; the coordinator appends them (do not
  have parallel workers edit the file directly -- it is a single-writer
  artifact). The stdlib session pulls from it in its own lane.
- `docs/COMPILER-FINDINGS.md` -- packages-lane compiler evidence for the
  compiler session (`&mut Int` write-through miscompile, loop-carried CSE,
  mixed-bracket tolerance, no `Vec[Float64]`/bitcast, bit-test signing,
  ...) with workarounds and impact.
- `docs/MAINTENANCE.md` -- the release-triggered maintenance loop (owner
  request 2026-09-28): what to touch on each compiler/stdlib/ops event,
  the staleness triage order, cadence rules (independent versions, no
  lockstep), and the evidence channels.
- `docs/PACKAGE-NAMESPACES.txt` + `scripts/export-namespaces.ps1` -- the
  package/module namespace snapshot the stdlib session cross-checks
  against. **Regenerate at every wave wrap**:
  `& .\scripts\export-namespaces.ps1`.
- Two-way name uniqueness: packages check the stdlib (plus all package
  manifests) with `namespace-check.ps1 -Module <name>` before dispatching
  any new package; the stdlib session checks new module names against the
  snapshot above. Nothing new is dispatched until both checks pass.

**Copy-paste prompt for the next session:**

```text
You are the packages session for xiom-packages/packages (local
E:\xiom-packages\packages, remote github.com/xiom-packages/packages,
private). Read SESSION.md first -- sections 0 and 5 are the live handoff.
Repo-local identity must be "Lefteris Notas <lefterisnotas@gmail.com>".
Publishing policy: PRODUCTION-DIRECT by default (one eco-* tag per ready
batch; this session handles the registry-publish gate approval). Staging
only when the owner explicitly asks.

Start by running: git fetch; git status -sb; git log -1; then
& .\scripts\status.ps1 -Action validate and & .\scripts\allowlist-guard.ps1.

Then do, in order:
1. Gate queue: see the live **Gate queue** bullet in the current handoff
   section at the top of this file. In short (2026-09-27 21:36Z): owner
   greenlight granted; `eco-v0.1.6` ran and failed with `scope_denied`
   (ops delta not live); `eco-v0.1.9` (run `36338915735`) is now the head
   and WAITING at the gate -- approve it once ops confirms. Scope target
   **359**, rising to **369** when wave 39 wraps as `eco-v0.1.10`. Never
   re-cut a tag.
2. Wave 38 is in flight by the parallel lane: `bitcoin, bolt, dac,
   leveldb, logging, proxy, pulsar, timer, wireless` (+1). Check the
   package dirs and session list first; continue that lane's work rather
   than re-dispatching. Standard recipe: AM-only while `task` subagents
   are balance-dead; full 18-trap + XIOM MCP briefs; each brief asks for a
   `stdlib gaps` section. Integrate + wrap + tag waiting at the gate as
   they report; extend the scope request with each wave's names.
3. Growth coordination: append worker-reported stdlib gaps to
   `docs/STDLIB-WISHLIST.md` and compiler evidence to
   `docs/COMPILER-FINDINGS.md`; regenerate `docs/PACKAGE-NAMESPACES.txt`
   at every wrap so the stdlib session can cross-check names.
4. Keep the registry-lane badge-override follow-up (section 5) and the
   .github OIDC token re-mint finding.
```

**Mission:** turn this monorepo into real, production-grade package repos.
Start from small packages that can reach production grade quickly, port the
legacy code in dependency order, and graduate stable packages to
`xiom-packages/xiom-<name>` with OIDC publishing and enumerated scopes.

---

## 1. State (all pushed to origin/main)

- Repo: `xiom-packages/packages`, local `E:\xiom-packages\packages`, private
  (Free org). Remote `https://github.com/xiom-packages/packages.git`.
- Identity: repo-local `Lefteris Notas <lefterisnotas@gmail.com>`. Org-wide
  decision: gmail is the author identity in every repo; never the work email.
- Folder inventory (2026-09-26, waves 32+33 complete): **324 implemented
  dirs (with `package.xi`) + 197 README-only placeholders + the umbrella
  `packages/package.xi`**. Since the 2026-09-23 handoff: 257 new packages
  were implemented (placeholder conversions + brand-new dirs); the four
  deprecated dirs were deleted and `xiom-core` renamed to `xiom-durable`.
  Wave 27's `gguf` circuit-breaker was resolved the same session by direct
  coordinator implementation (`docs/failed_attempts.md`, 10/10 shipped).
  Wave 20 added 10 (conversions `dhcp`, `ntp`, `socks`, `irc`, `mqtt`; new
  `ical`, `vcf`, `dns`, `modbus`, `can`). Wave 21 added 10 (conversion `ble`;
  new `gbnf`, `fits`, `stun`, `bencode`, `ply`, `dimacs`, `syslog`, `tga`,
  `cpio`). Wave 22 added 10 all-new dirs (`netstring`, `ar`, `vdf`, `cron`,
  `pgn`, `vtt`, `nbt`, `hl7`, `gpx`, `bibtex`). Wave 23 added 10 more all-new
  dirs (`cbor`, `bloom`, `wkt`, `ico`, `base32`, `quotedprintable`, `aiff`,
  `m3u`, `sgf`, `ntriples`). Wave 24 added 10 more all-new dirs (`iso8583`,
  `ulid`, `pcx`, `cue`, `pbm`, `gcode`, `lrc`, `ris`, `iban`, `fnv`), all
  balanced across the ecosystem categories. Wave 25 added 10 more all-new
  dirs (`plist`, `geohash`, `murmur3`, `tap`, `xbm`, `pam`, `srt`, `pls`,
  `ean`, `junit`). Wave 26 added 10 more all-new dirs (`smtlib`,
  `safetensors`, `dbase`, `systemd`, `gemtext`, `radix`, `luhn`, `fletcher`,
  `farbfeld`, `hostfile`), all balanced across the ecosystem categories.
  Wave 27 added 10 all-new dirs (`adler32`, `lcov`, `snbt`, `robots`, `edl`,
  `fstab`, `marc`, `fix`, `xpm`, `gguf`). Wave 28 added 10 more all-new dirs
  (`sarif`, `zonefile`, `gedcom`, `pem`, `maidenhead`, `rtf`, `ldif`, `spf`,
  `bech32`, `mbox`). Wave 29 added 10 more all-new dirs (`nii`, `hcl`, `dds`,
  `tzif`, `au`, `sbv`, `ktx`, `osrelease`, `duration`, `tcx`). Wave 30 added
  10 more all-new dirs (`elf`, `pe`, `dtb`, `pcapng`, `gpt`, `radiotap`,
  `woff`, `qoi`, `miniseed`, `ass`). Wave 31 added 10 more all-new dirs
 (`ext`, `acpi`, `usb`, `smbios`, `mbr`, `sparse`, `uboot`, `psf`, `pcf`,
 `resolv`). Wave 32 added 10 dirs (placeholder conversions `tftp`, `pop3`,
 `smtp`, `ftp`, `passwd`, `efi`, `hid`, `cab`, `pci`, plus new `rpm`).
 Wave 33 added 10 dirs (`png`, `gif`, `mp3`, `mp4`, `mkv`, `snmp`,
 `imap`, `amqp`, `thrift`, `avro`; 213 tests across the ten).
- `STATUS.json` totals: **257 stable, 4 ported, 63 incubating**;
  **261 green suites, 5,634 recorded tests**.
  - stable = the greenfield packages plus conversions. Waves 18-30, 31+32
    and 33 are all **published to production** by `eco-v0.1.1`/`.2`/`.3`
    (registry index **260 packages**). New stable packages still carry
    `publish: false` until the next scope delta / tag.
  - ported = `xiom.sensor`, `xiom.control`, `xiom.json` (pure, promotable) and
    `xiom.kafka` (librdkafka FFI stubs remain; keep `ported`).
  - incubating = 63 legacy packages (includes `xiom.durable`, the renamed
    core, not yet ported).
- `.github/publish-allowlist.txt`: **309 names** = 257 stable ready + 52
  grandfathered legacy names (`.github/allowlist-baseline.txt`, warn-only in
  the guard). `scripts/allowlist-guard.ps1`: 0 failures (2026-09-26, after
  the wave-33 +10).
- Namespace audit **resolved**: `namespace-check` reports **324 packages,
  422 modules, 0 conflicts** (2026-09-26, wave-33 wrap).
- Toolchain: pin `COMPILER_VERSION` = **v0.61.3**; installed compiler
  v0.61.3 (`C:\Users\lefte\AppData\Local\xiom\bin`); repo release dir has
  v0.61.1; GitHub releases v0.61.1 + v0.61.3 exist. Stdlib
  `E:\xiom-lang\stdlib` (1627 module namespaces, still evolving).
- Signing: `XIOM_SIGNING_KEY` is SET; staging/production artifacts share the
  first-party key `4f3b47f3ae17b13c...`.
- Licensing: `LICENSE-MIT`, `LICENSE-APACHE`, `NOTICE` and a pointer
  `LICENSE` are committed per LICENSING.md §2. SPDX pass repo-wide and the
  §1 `.md` header block remain .github-session scope.
- 562 commits landed since the previous handoff (`b2bdde1..`).

### Commit trail (recent milestones)

| Commit | What |
|---|---|
| this | SESSION.md refresh: waves 1-33 all published (eco-v0.1.3 success, registry 260) |
| 76e64fa | bump `xiom.algo` to 0.1.1 for the staging badge canary |
| 9da3143 | stage-badge canary verification (xiom.algo 0.1.1) + override decision |
| c914e53 | staging config-validation canary (xiom.rpm) record |
| 16b6afe | eco-v0.1.2 success state refresh (registry 250) |
| 471c5e3 | allowlist wave 33 (+10) + index/report regeneration (completes the wave-32 deferral) |
| aa0eda0 / c72c85d / c563fe9 / 3366016 | wave-33 feat commits (png, mp4, snmp, thrift) |
| f48a76b / 24b0827 / aeea0b8 / 69c6d80 | wave-33 STATUS records (png, mp4, snmp, thrift) |
| cefa9eb | ops rate-limit note + eco-v0.1.2 attempt 2 scope re-test |
| 1392110 | ignore XIOM MCP tool local state (`.xiom_ai.json`, `.xiom_ai_cache/`) |
| b14fadf | `docs/failed_attempts.md` rpm abort/resolution entry |
| b7fc365 / d9f12a2 | `xiom.rpm` recovered on attempt 3 (19/19) + STATUS record |
| dccebd1 | allowlist wave 32 (+9 names) |
| e36ae67 / 24fc00b / 6edcde7 / 0b8d1a5 / e873c3e / fe5ad54 | wave-33 STATUS records (imap, avro, mp3, gif, mkv, amqp) |
| c7e4412 / 32841d7 / 3f31106 / c47c1b4 / 5ca6457 / 6617dce | wave-33 feat commits (imap, avro, mp3, gif, mkv, amqp) |
| 9ac83d3 | allowlist wave 31 + index/report regeneration |
| b0d97fd..2bb8c14 | wave 31 per-package `feat:`/`chore:` pairs (10 packages) |
| a0d7fc4 | `port.ps1` fails closed when a suite reports zero checks |
| a6e678e | staging canary ledger complete (130/130 success); `eco-v0.1.1` tagged |
| 4fb356f / c68013f / 8f7e58e | staging batch list + runner (serialized protocol) |
| da1a851 | allowlist wave 30 + index/report regeneration |
| 7cc082a | allowlist wave 29 + index/report regeneration |
| 456c3da..e88b8b1 | wave 29 per-package `feat:`/`chore:` pairs (10 packages) |
| 0637303 | allowlist wave 28 + index/report regeneration |
| 465d181..bd2ffd4 | wave 28 per-package `feat:`/`chore:` pairs (10 packages) |
| 674b728 / 631030c / 8bff9ab | `xiom.gguf` direct implementation, record, allowlist + breaker resolution |
| 36b25eb | allowlist wave 27 + index/report regeneration |
| 4b05f0f | `docs/failed_attempts.md` created (xiom.gguf triple-abort) |
| c3bb8d4 | allowlist wave 21 + index/report regeneration |
| 7e76af7 | allowlist wave 20 + index/report regeneration |
| e66afc7 | allowlist wave 19 + index/report regeneration |
| bb7d18b | bounded staging badge-canary override (`allow_unready`) |
| ad13b07 | allowlist wave 18 + index/report |
| 7e77457 | publish loop enforces readiness (skip/refuse) |
| c6690cb / 2080fda | badge `stage` written from STATUS.json into packaged manifests |
| cfe2b40 | readiness guard workflow + 6 allowlist additions (registry v2 names) |
| 8946171 / bcabb9c | `status.ps1 -Action repin` + pin bump to v0.61.3 |
| 54c241f | LICENSE-MIT/LICENSE-APACHE/NOTICE per LICENSING.md §2 |
| be6d1ec | Phase 0 harness (xiom/status/namespace-check/port) + STATUS seed |
| b2bdde1 | previous handoff (2026-09-23) |

Per-package commits (`feat: add <pkg>...` + `chore: record <pkg>...`) are in
`git log`; each package's `STATUS.json` names its `run_by` subagent/session id
and the tested commit.

---

## 2. Key paths and harness

| Path | What |
|---|---|
| `scripts/xiom.ps1` | toolchain resolver (`XIOM_COMPILER` -> installed >= pin -> repo release), sets `XIOM_STDLIB`; dot-sourceable |
| `scripts/port.ps1 -Package <name>` | namespace gate + compile + run conformance suite; `-Quiet` for scripted runs; `-NoRun` = `--emit-ir` compile-only; never writes STATUS |
| `scripts/status.ps1` | `-Action list` / `validate` / `seed` / `repin` / `report` / `update`; `update` records runs and enforces the readiness gates |
| `scripts/namespace-check.ps1` | the §3 rule; `-Package` for implemented names, `-Module` for proposed names |
| `scripts/allowlist-guard.ps1` | CI guard: allowlist entries must be `stable`+green; baseline names warn-only |
| `scripts/port.ps1` + `status.ps1` + `docs/PACKAGE_STATUS.md` | `status.ps1 -Action report` regenerates the doc |
| `generate_index.ps1` | legacy index generator; run after manifest changes |
| `.github/workflows/publish-registry.yml` | OIDC publish: `eco-v*` batch, `xiom-<folder>/v<version>` single package, dispatch canary |
| `.github/workflows/readiness-guard.yml` | CI guard on allowlist/STATUS/report changes |
| `docs/repro/generic-fnptr/` | committed compiler repros (fn-value ABI sprint evidence) |
| `ecosystem/` | historical reports -- do NOT edit |
| `.kilo/worktrees/second-sprout` | stale clean worktree at `7ca0cd3`; can be pruned |

Standard commands (repo root):

```powershell
& .\scripts\xiom.ps1 -Info
& .\scripts\port.ps1 -Package xiom.lru            # verify one package
& .\scripts\status.ps1 -Action validate           # 305/0 expected
& .\scripts\allowlist-guard.ps1                   # 290 allowlisted, 0 failures
& .\scripts\namespace-check.ps1                   # 0 conflicts expected
& .\generate_index.ps1 ; & .\scripts\status.ps1 -Action report
```

Publish gate recap: only allowlisted + `STATUS.json` `stage: stable` with
`tests.status: pass` publishes (batches skip unready with a warning; explicit
tag/dispatch targets on unready names are refused). Default target is
**production** per the owner standing instruction in section 5; staging
dispatches happen only when the owner explicitly requests a staging run
(site/feature testing). The bounded staging badge canary
(`workflow_dispatch` + `allow_unready=true` + explicit `package` + staging
registry) remains available for that case; tags and batches can never use it.

---

## 3. Namespace audit -- RESOLVED (history)

**Rule (still enforced): a package may not declare modules equal to, or
nested under, a stdlib module namespace** (a shared first two dotted
segments is a collision; sharing only `xiom` is not).

Resolution executed 2026-09-23/24 under owner confirmation:

- `xiom.math`, `xiom.log`, `xiom.net`, `xiom.test`: deprecated and **deleted**
  (folders removed; not in the allowlist).
- `xiom.core` -> **`xiom.durable`**: folder, package ident, all 21 module
  namespaces, docs, umbrella list; `STATUS.json` notes "port to current
  stdlib pending". Registry scope pre-provisioned.

`namespace-check` now reports 0 conflicts. New names must pass
`namespace-check.ps1 -Module <name>` before a package is added (the wave
prompts all did).

---

## 4. Readiness model (implemented)

Per-package `STATUS.json` (see §5 example in the previous handoff) with
`stage` in `incubating | ported | stable | deprecated`, `tests.status` in
`unknown | pass | fail`, `publish`, `excluded_reason`. Enforced rules:
`publish: true` requires `stable`; `stable` requires a recorded green run
(`run_by` + `commit` + `checked` + counts). The working agent runs the suite;
the coordinator records it. `status.ps1 -Action repin` realigns `compiler`
after a pin change; `-Action report` regenerates `docs/PACKAGE_STATUS.md`,
which is the human-facing status list (green-light checklist included).

Pin change note: all recorded runs above were made on installed v0.61.3,
which is also the current pin, so records are consistent.

---

## 5. Publishing / registry state (2026-09-26)

**OWNER STANDING INSTRUCTION (2026-09-26, supersedes the canary-first flow):**
publish directly to **production** by default. Staging is now only for
site/feature testing when the owner explicitly asks for it -- it is no
longer a package-code gate. Mechanism: after a wave wrap, cut one `eco-*`
tag for the ready batch (the tag batch publishes every `stable` + green +
allowlisted name at that commit; grandfathered names are skipped) and
approve the `registry-publish` gate via the pending_deployments API
(production approvals are handled by this session under this instruction).
Report `name -> run ID` (batch runs report the single run ID + the
batch commit). Never overlap a tag run with a dispatch batch (shared
concurrency group). Production tags so far: `eco-v0.1.0`, `eco-v0.1.1`
(SUCCESS), `eco-v0.1.2` (cut, blocked on the registry scope delta).

- **Staging**: rebuilt from main (`06f6977`, registry 2.0.0) with the
  xiom-packages/packages entry carrying the **full 290-name allowlist**
  (`staging-scopes.txt/.json` from the registry lane) and
  `PUBLISH_RATE_MAX=600`. All pre-batch canaries (78 scoped names + wave
  16/17 samples + the `xiom.algo` badge canary) remain verified.
- **Wave 18-30 staging batch: 130/130 SUCCESS (2026-09-26)**. Ledger with
  every `name -> run id -> state` is committed at `docs/staging-batch-runs.txt`
  (final commit `a6e678e`); the batch list is `docs/staging-batch.txt` (130
  names). Runner: `scripts/staging-batch.ps1` (staging-only guard, dry-run
  default, serialized pipeline).
  - **Concurrency finding (important)**: the workflow has a repo-level
    concurrency group (`registry-publish`, `cancel-in-progress: false`).
    GitHub cancels a previously *pending* run when a newer run joins the
    same group, so bulk-dispatching the whole batch at once cancelled 128
    of 130 runs (only the first and last survived). Batches must be
    dispatched through the serialized runner (at most one `pending` run),
    and the eco tag must never overlap a dispatch batch.
  - Approvals: staging runs are approved by this session via
    `POST /actions/runs/<id>/pending_deployments` with a JSON body
    `{"state":"approved","environment_ids":[<env id>],"comment":"..."}`
    (the GET returns only pending entries and has no `state` field;
    `-f` sends strings and fails -- use `--input <tempfile>`).
- **Production: `eco-v0.1.1` SUCCESS (2026-09-26)**. Tag `eco-v0.1.1` on
  `a6e678e` (waves 18-30); run `36240424222` completed on attempt 3 at
  15:02Z after two 30-min job-ceiling cancellations (the loop is idempotent
  and skips published versions). Registry index 231 packages at that point.
- **Production `eco-v0.1.2`: SUCCESS (2026-09-26)**. Tag `eco-v0.1.2` on
  `dccebd1` (wave-32 wrap; waves 31+32 = 19 new names:
  `ext, acpi, usb, smbios, mbr, sparse, uboot, psf, pcf, resolv` plus
  `pop3, smtp, ftp, passwd, efi, hid, cab, pci, rpm`). Run `36251091427`
  failed attempts 1-3 with `scope_denied` (403) because the publisher entry
  lacked the 19 names; after ops enumerated them, **attempt 4 completed
  17:23:22Z and published all 19** (~4 min). **Registry index now carries
  250 packages.** "Batch done" confirmed to ops at 17:24Z.
- **Production `eco-v0.1.3`: SUCCESS (2026-09-26 23:06:41Z)**. Tag on the
  wave-33 wrap `471c5e3` (10 names: `png, gif, mp3, mp4, mkv, snmp, imap,
  amqp, thrift, avro`); run `36278244028`, gate approved, published in
  ~3 min at the restored 20/min with no retries. All ten record
  `stage: "stable"`. **Registry index 260 packages.** "Batch done"
  confirmed to ops (D5 restore).
- **Workflow finding (secondary)**: `publish-registry.yml` mints **one**
  OIDC token at job start (`XIOM_REGISTRY_TOKEN` via `$GITHUB_ENV`) and
  reuses it for every package; runs longer than ~6 min fail all remaining
  publishes with `oidc_token_expired`. Re-mint per attempt (or on 401) is a
  .github-session fix.
- **tftp version collision (owner decision)**: `xiom.tftp@0.1.0` published
  by `eco-v0.1.1` is the 2026-09-24 build (`be38152`); the wave-32 rewrite
  (`ae3c233`) carries the same version and cannot republish. Accept the
  published build or bump tftp to 0.1.1 in a later batch.
- **Scope ledger**: waves 18-33 are fully covered -- **309 scopes** = waves
  18-30 superset (280) + the 19 wave 31+32 names + the 10 wave-33 names, on
  `eco-release` (production) and `eco-canary` (staging); ops synced their
  repo to match. The next scope request is the wave-34 delta. `xiom.durable`
  is deliberately not scoped until it is stable + allowlisted (Phase 2).
- **Ops rate-limit notes (2026-09-26, relays via the owner)**: ops first
  reported the 15:02Z stall as the restored 20/min default and "re-raised"
  `PUBLISH_RATE_MAX=600`; the corrected root cause (16:54Z relay) is that
  `PUBLISH_RATE_MAX` was **never declared** in the production service
  block, so both the bump and the planned restore were inert and the
  service ran the default **20/min** all along. Deploy `394db71` declares
  all rate-limit knobs; production now genuinely runs `PUBLISH_RATE_MAX=600`
  (ops verified with `printenv`; registry `/health` shows the restart at
  16:54:38Z, v2.1.0). Ops restores **20** on "batch done" (registry §21
  D5). Rate-limit config does **not** affect the `scope_denied` 403:
  attempt 3 ran against the new config and still failed on scopes, with no
  429s. Batches **done** (`eco-v0.1.2` 17:24Z, `eco-v0.1.3` 23:07Z); ops
  restores 20/min after each. Later ops relay: the patch added the 19 names
  on top of the waves 18-30 superset (299), then the wave-33 delta brought
  it to **309 scopes** on both `eco-release` (production) and `eco-canary`
  (staging), services recreated (publisher config is read at boot), ops repo
  re-synced. Standing batch protocol: say the word and ops raises
  `PUBLISH_RATE_MAX` to 600 for the publish window, restores 20 on
  "batch done" (D5 batch profile).
- **Stage-badge verification (2026-09-26 21:29Z)**: the registry lane asked
  for a fresh badge canary. Packages side: `xiom.algo` was bumped to 0.1.1
  and published to staging via the bounded canary path (`allow_unready=true`,
  run `36273039745`) -- the per-version entry records
  `stage: "incubating"` and is `latest` on staging (commit `76e64fa`).
  Registry side: re-ran `xiom-lang/registry`'s `oidc-canary.yml` (run
  `36272937345`); its new version `0.0.0-canary.1790457993406` records
  `stage: ""` because the fixture manifest in `scripts/oidc-canary.js` has
  no `stage` field (relayed back; one line there or a server-side default).
  **Stage-override decision: yes to the audited, display-only maintainer
  override** for historic empty-stage entries (production: 38 = 35 locally
  stable + 1 incubating `xiom.hello` + 2 specials `xiom.staging-e2e-probe`,
  `xiom.std`; staging: 83), sourced from `STATUS.json` at a pinned commit,
  never affecting publish authorization; per-version stage from real
  publishes always wins. Version-bump republishing for 35+ stable names was
  rejected as version burn for a cosmetic badge.
- **Staging config-validation canary (2026-09-26 18:03Z)**: `xiom.rpm` was
  dispatched to staging (`workflow_dispatch`, explicit package, staging
  registry; run `36261177048`) to validate the patched `eco-canary` entry
  (299 scopes, post rate-limit patch) end-to-end. Published 18:03:44Z,
  signed with the first-party key, staging index now 219 packages. This is
  an ops-requested config check, not a package-code gate (the
  production-direct policy is unchanged); ops runs the staging live-check
  on top of it.
- **Environment**: `registry-publish` requires reviewer `Lefteris-Notas`
  (owner); per the 2026-09-26 standing instruction this session approves
  both staging canary deployments and production batch gates via the API
  (the `eco-v0.1.1` attempt-3, `eco-v0.1.2` and `eco-v0.1.3` gates were
  approved this way).
- **Production**: `eco-v0.1.0` (owner-account), `xiom-flags/v0.1.0`
  (per-package tag), `eco-v0.1.1` (waves 18-30, 15:02Z), `eco-v0.1.2`
  (waves 31+32, 17:23Z) and `eco-v0.1.3` (wave 33, 23:06Z) have succeeded;
  the registry index is at **260 packages**. Nothing in this repo publishes
  to production without the `eco-*` tag or an explicit workflow dispatch.
- Ops note: OIDC canaries are unrelated to browser sign-in; the **OAuth
  callback URL check remains a separate outstanding owner item** (do not fold
  it into publish relays).

---

## 6. Roadmap status

1. **Phase 0 -- toolchain + harness + triage: DONE.** Scripts above, STATUS
   seeded for every implemented package, pin v0.61.3, licenses, badge/guard
   pipeline, bounded badge canary.
2. **Phase 1 -- small greenfield packages: DONE and expanded.** 257
   packages built, conformance-tested, `stable`, allowlisted (waves 1-33).
   All pass the namespace rule; each has SPEC/README/tests and a STATUS
   record. Waves 18-30, 31+32 and 33 are all published by
   `eco-v0.1.1`/`.2`/`.3` (registry 260 packages).
3. **Phase 2 -- foundations port: NEXT.** `xiom.durable` (renamed; not yet
   ported) first, then the pure legacy set (`xiom.algo` etc.). 63 incubating
   package remain; the legacy compile triage is in the previous handoff's
   triage report and `ecosystem/`. The pure head starts are `xiom.algo` and
   the `graphql`/`micro`/`realtime` dependency chain; the mechanical
   `expected ';'` cluster and the T007/FFI clusters need compiler-side
   decisions first.
4. **Phases 3-5 (network/data/bridges): pending**; FFI ABI freeze with the
   compiler/stdlib sessions is the gate for the bridge batch.
5. **Phase 6 graduation:** publish first from the monorepo, promote later
   (filter-repo per §5.6 of the ops runbook, hooks, CI, per-repo OIDC) when a
   package's API is stable and it has consumers/cadence.

Port definition of done: dotted manifest + metadata; compiles on the pinned
compiler + current stdlib; conformance suite green (run by the working
agent); no not-linked paths; honest README/SPEC; `STATUS.json` stable +
publish; one staging publish installed back.

---

## 7. Porter conventions and compiler traps (v0.61.3)

Proven per-package recipe (see `docs/repro/generic-fnptr/`): spawn one
background `task` subagent per package (general agent) with a self-contained
brief: read `packages/xiom-hello` + a sibling of the same kind, deliver
`package.xi`, `src/<x>.xi` (module `xiom.<x>`), `tests/test_conformance.xi`,
`README.md`, `SPEC.md`, `.gitignore` (copy of xiom-hello's); iterate with
`scripts/port.ps1 -Package <name>` until `port: PASS (program_exit=0)`.
Every brief should also ask for a short `stdlib gaps` section in the final
report (missing helpers/modules the package had to hand-roll) -- the
coordinator appends those to `docs/STDLIB-WISHLIST.md`.
Subagents must not commit, must not touch STATUS.json, must not publish.
The coordinator then: verify (re-run), commit, run on the commit, record with
`status.ps1 -Action update ... -RunBy <task id> -Commit <sha>`, commit the
record, allowlist the wave, regenerate index + report, push. Optional
**Agent Manager local sessions** (visible in the UI) work the same way and
have succeeded repeatedly; keep waves at ~10 packages.

Language traps that must be in every porter brief:

1. BUG-17 family: never `==` on Str values read from `Vec[Str]` elements, and
   `str_len`/`.len()` is unreliable on them -- use `str_compare` from
   `xiom.string.compare` and typed locals `let e: Str = v[i];`.
2. Untyped `Vec[Int]` element reads can mis-lower to Str compares; always
   `let x: Int = v[i];`.
3. Never compare `byte_at(...)` directly to a UInt8 constant >= 128; widen
   `(x as Int) & 0xFF`.
4. Passing `&struct.field` (e.g. `&result.value`) into a `&Vec[UInt8]`
   parameter yields an empty vector on the installed compiler; bind to a local
   first. The compiler session reports this fixed in the **next** build; it is
   NOT yet installed (re-verified 2026-09-25, wave 26: probe B still returns
   `result payload: 0`, exit 10, on `0.61.3` / pin `v0.61.3`). Keep the local
   binding until the pin bump, then re-run `docs/repro/struct-field-vec/`.
5. Indexed `Vec[fn]` calls miscompile (access violation): no table-driven
   test dispatch; call tests directly or via `run_test_at(index)`.
6. Do not construct `Ok`/`Err` inside struct-returning functions; use leaf
   helper constructors. Scalar payloads (`Result[Int, Str]`, `Result[Str, Str]`)
   accept direct `Ok`/`Err`; struct payloads (`Result[Doc, Str]`) need the
   leaf helpers (wave 25 `xiom.plist`).
7. Generic fn-pointer limits: single-`T` generics with named callbacks are
   fine; `[T,U]` type-changing callbacks miscompile/crash -- use concrete
   specializations.
8. No `mut` bindings in match patterns; matches must be exhaustive; `module`
   headers take no `;`, `use` statements require one.
9. No `Vec[Float64]` (scalar `Float64` is fine); prefer integer/fixed-point
   units and document rounding.
10. Free functions only; no `self` methods, no inline lambdas, no
    `Vec[StructType]` (parallel `Vec` fields instead). Avoid a free function
    named `log` (collides with libm). E001 borrow warnings are advisory.
11. Every `.xi` starts with the copyright + SPDX lines.
12. `&mut Vec` parameters need an explicit `&mut` at every call site: passing
    the value silently copies and the mutation is lost (wave 21 `xiom.tga`;
    same family as trap 4).
13. Widened `UInt8` constants >= 128 must be masked too: `239u8 as Int`
    sign-extends to -17; write `(C as Int) & 0xFF` for constants (wave 21
    `xiom.syslog` BOM handling).
14. The compiler is lax about arity and punctuation: a call with fewer args
    than declared compiles (missing args default to 0) and mixed brackets
    (`-> Vec<UInt8]`) compile too -- including in **parameter and local**
    type positions, not just returns (wave 22 `xiom.ar`; wave 26
    `xiom.fletcher` found 6; wave 30 found 17 more across `gpt` 13, `qoi` 2,
    `radiotap` 1, `pcapng` 1). Verify argument counts and types explicitly;
    grep signatures for `Vec<`/`Result<` **after every write and again after
    green**; do not rely on the compiler to reject them.
15. Never build a `Str` via `xiom.string.builder.sb_to_str` from bytes that
    may contain `0x00`: its length contract aborts at run time (wave 23
    `xiom.aiff` validates chunk ids/types/names as printable ASCII before
    building any `Str`). Trap 4 extends to `Result` payload fields: bind
    `result.value` to a local before passing it to a `&Vec[UInt8]` parameter
    (wave 23 `xiom.quotedprintable`, `xiom.aiff`). Also, `\0` inside a `Str`
    **literal** truncates it (`"abc\0def"` measures 3, and a literal NUL byte
    cannot be represented at all) -- wave 27 `xiom.robots`; a NUL anywhere in
    a literal truncates from that point (`"\x00\x01"` measures 0, wave 28
    `xiom.ldif`). Test other control bytes with
    `\u{0001}`/`\u{000B}`/`\u{001F}`/`\u{007F}` escapes.
16. Never let parallel Vecs drift: every push on one array must be mirrored
    on all sibling arrays, and emit/accessors must guard mismatched lengths.
    `xiom.lrc` (wave 24) crashed with an access violation when one
    timestamped line pushed `times` without a matching `texts` entry; the AV
    was nondeterministic and stdout buffering hid all prior output, so pin
    the invariants in tests and treat exit codes as the signal.
17. `as` is a reserved keyword (`let as: Int` is `error[P001]`), and
    `xiom.convert` re-exports `int_to_string` but not `int_to_base` (that
    lives in `xiom.convert.int`) -- wave 24 `xiom.gcode`.
18. `Int` division truncates toward zero (LLVM sdiv), so the common
    ceil-division idiom `(a + b - 1) / b` is WRONG for negative numerators
    (`-28 / 3` is `-8`, ceil is `-9`). Use
    `let q = a / b; let r = a % b; if r > 0 { q + 1 } else { q }` (wave 28
    `xiom.maidenhead`; the naive form would have produced off-by-one cell
    minima across the western/southern hemisphere).

---

## 8. Open decisions (owner) / outstanding items

1. **Registry/ops scope delta needed (blocker)**: production publish scopes
   for the 19 wave 31+32 names (`ext, acpi, usb, smbios, mbr, sparse,
   uboot, psf, pcf, resolv`, `pop3, smtp, ftp, passwd, efi, hid, cab, pci,
   rpm`). Evidence: run `36251091427`, HTTP 403 `scope_denied` (section 5).
   After the scopes land, `gh run rerun 36251091427` + gate approval.
2. **`eco-v0.1.1`: DONE** (run `36240424222`, attempt 3, 15:02Z). Standing
   instruction from the owner: production-direct publishing from now on
   (section 5); waves 31+32 ride `eco-v0.1.2` (cut; blocked on item 1);
   wave 33 rides the next tag after its wrap.
3. **Repo protection closure**: the required-reviewer environment is live;
   confirm this satisfies the §8.3 decision.
4. **OAuth callback URL check** (owner): both GitHub OAuth app callback URLs,
   outstanding from the earlier relay; kept separate from publish relays.
5. **tftp version decision (owner)**: accept the published 2026-09-24
   `xiom.tftp@0.1.0` or bump the wave-32 rewrite to 0.1.1 in a later batch
   (section 5).
6. **Wave 34+ queue**: 197 placeholders remain; strong small candidates are
   more format/protocol codecs and hardware/file formats. Owner relayed the
   ecosystem page's canonical categories (Data and storage; Networking and
   web; AI and machine learning; Scientific computing; Graphics and games;
   Systems and tooling; Interoperability and bridges; Verification and
   analysis) -- use them to balance wave selection. Manifest `categories:`
   tokens still mix `network` vs `networking` etc.; harmonizing them is an
   owner decision.
6b. **Provider balance for `task` subagents is exhausted (2026-09-26
   ~23:45Z, "Insufficient Balance")** -- background `task` workers fail
   immediately for every model call. Agent Manager local sessions are
   unaffected and are the current workhorse; top up the provider balance to
   restore the 6-background-task half of the standard recipe.
7. **Repo-wide SPDX/`.md` header pass** and the 71 legacy manifests still
   using `authors: ["XIOM Team"]` -- .github-session scope. The publish
   workflow OIDC token-lifetime finding (section 5) is also theirs.
8. **`xiom.durable` port** (Phase 2 opener) and the pure legacy frontier.
9. Note: the local Kilo build rejects new `.kilo/agent`/command frontmatter
   (`No context found for instance`); persistent agent definitions were
   removed to keep config clean. Use `task` subagents / Agent Manager local
   sessions instead.
10. **`xiom.gguf` and `xiom.rpm` circuit breakers -- RESOLVED** (wave 27/28
    and wave 32 respectively): both recovered after silent subagent aborts
    (`docs/failed_attempts.md`). Post-breaker fallback: coordinator
    implements directly; delegate aborts are environmental.

---

## 9. Guardrails (do not violate)

- Never publish manually; publish only through the workflow, only allowlisted
  names, only with a recorded green run. Versions are immutable forever.
- Namespace rule: run `namespace-check.ps1 -Module` before adding a name.
- The readiness filter stays: batches skip unready names, explicit targets
  are refused; the only override is the staging badge canary described in §2.
- Do not rename folders except the already-done `xiom-core` ->
  `xiom-durable`; do not touch `deps:`/`dev-deps:` except dotted-name fixes.
- No history rewrites, no force pushes. Conventional commits, atomic,
  commit + push to `main`.
- No tokens in chat, repo, or commit messages; publishing uses OIDC in CI.
- Leave `ecosystem/` historical reports alone. (SESSION.md is the live
  handoff and is updated by the packages session.)
- PowerShell gotcha: `"$name: text"` parses as a drive-qualified variable;
  write `"${name}: text"`.

---

## 10. Coordination contracts

- **Registry/ops session:** **scope delta needed now** -- production publish
  scopes for the 19 wave 31+32 names (section 5 evidence: run `36251091427`,
  `scope_denied`), plus optionally re-mint the publish OIDC token per
  attempt (workflow finding). Publisher identity is
  `xiom-packages/packages`, workflow `publish-registry.yml`,
  `refs/heads/main`, event `workflow_dispatch` (staging canaries) or tag
  pushes (production). Staging canaries remain available on request;
  production runs directly per the owner standing instruction.
- **Compiler session:** accepted the three fn-value/ABI repros
  (`docs/repro/generic-fnptr/`) into their unification sprint; findings to
  relay: `&struct.field` -> `&Vec[UInt8]` empty-vector misbehavior, `str_len`
  on `Vec[Str]` elements, the `Vec[fn]` dispatch miscompile, bitwise AND on
  bit-31 operands (wave 20 `xiom.can` used descending subtraction instead),
  the ABI NUL-termination of `Str` that makes DNS wire labels containing
  `0x00` unrepresentable (wave 20 `xiom.dns` rejects them); and wave 21's
  `&mut Vec` auto-copy at call sites (`xiom.tga`) plus `UInt8` constant
  sign-extension (`239u8 as Int` = -17, `xiom.syslog`). Wave 22 added: arity
  laxness (fewer args than declared compiles, missing args default 0) and a
  `-> Vec<UInt8]` bracket typo compiling (`xiom.ar`); `io.println` accepts
  only `Str` -- ints need `xiom.convert.int_to_string` (`xiom.pgn`); an
  immutable accessor before a `&mut` call on the same struct raises an E001
  advisory (`xiom.netstring`); `&struct.field` only misbehaves for `&Vec`
  parameters (plain `&Struct` params are fine, `xiom.pgn`). `xiom.ar` bytes
  were interop-checked with `llvm-ar`. Wave 23 added: `sb_to_str` aborting at
  run time on `0x00` in the built range (`xiom.aiff`); trap 4 extending to
  `Result.value` fields (`xiom.quotedprintable`, `xiom.aiff`); the masked
  widening trap biting raw UTF-8 (`(b as Int) & 0xFF` needed even for
  `< 0x20` checks, `xiom.ntriples`); E001 advisories at `&mut` call sites
  remain benign (pinned by `xiom.ntriples` t22). Wave 24 relay #2 result:
  arity laxness CONFIRMED (no exact-count validation on the primary path;
  extras dropped; silent-wrong-code; fix recorded), `Vec<UInt8]` mixed
  brackets CONFIRMED (parser accepts any opener/closer pairing; fix recorded:
  remember the opener and require its closer),
  `io.println` Str-only confirmed by design, E001 shape NOT reproduced --
  instead a by-value method receiver leaves the Vec field unchanged (same
  Vec-handle copy class), and `&struct.field` -> `&Vec` NOT reproduced in the
  simple shape. Our answer: `docs/repro/struct-field-vec/` (commit `6310dba`)
  shows the simple struct field is GREEN, `Result[Vec[UInt8], Str]` payload
  `&r.value` is the broken minimal repro (reads empty; bound local reads 3),
  and a struct field one hop deeper (`&r.value.data`) is GREEN. Compiler
  fixes are scheduled for the next release. Wave 25 relay #3 (strict-parser
  prep): a precise scan of this repo for mixed-bracket type syntax found
  **0 sites** (`Vec<X]` / `Vec[X>` patterns; the 18 sites across 7 files are
  stdlib-owned, incl. the `io/fs.xi` block); `xiom.cell` is not in this repo;
  the only receiver-style declaration here, `SqliteValue.is_null(val:)`, is
  called statically with exact arity (`xiom-sqlite`, so not the offset bug).
  Wave 26 relay #4/#5: compiler confirmed **packages #3 = 0 mixed-bracket
  sites, ready for the strict flip**; trap 6 refinement recorded; trap 4
  closure claimed for the next build but **still reproduces on the installed
  0.61.3** (see trap 4 / `docs/repro/struct-field-vec/`). New porting note
  from the wave-26 board: mixed brackets silently compile in parameter and
  local type positions too (`xiom.fletcher` fixed 6 in its own tests); the
  whole repo re-scanned clean afterwards. Wave 27: the trap-14
  parameter-position finding was independently confirmed by `xiom.snbt`
  (3 private emit-helper params) and `xiom.fletcher` (6 sites); `xiom.robots`
  added the `\0`-literal truncation finding (now in trap 15); indexed writes
  to `Vec[Int]` struct fields (`v[i] = v[i] + 1`) work (`xiom.lcov`).
  `xiom.gguf` triple-abort is logged in `docs/failed_attempts.md` (resolved
  by direct implementation). Wave 28: the ceil-division trap is now trap 18
  (`xiom.maidenhead`); RTF semantics: the space after a control word is a
  consumed delimiter and `\uNNNN` is DECIMAL (`\u66` = `B`); `xiom.spf`
  confirmed nested `&mut`/`&` forwarding and `break` work; `xiom.bech32`
  sharpened decode errors (`wrong variant` vs `bad checksum`; BIP-350
  ambiguity cannot occur). Wave 29: `xiom.hcl` confirmed mutual recursion,
  `while true` + `break` and discarded `Vec.pop()` under v0.61.3;
  `xiom.ktx` self-caught an identifier-table off-by-one; `xiom.nii` supports
  both sizeof_hdr endiannesses; `xiom.tcx` disambiguates same-named elements
  by the open-element stack. Two more delegate silent aborts (`tcx` #1,
  `hcl` #1) recovered by one retry each. Wave 30: trap 14's parameter/local
  bracket laxness is now the most-hit trap -- `xiom.gpt` alone found and
  fixed 13 sites after a green run (`qoi` 2, `radiotap` 1, `pcapng` 1);
  GREP `Vec<`/`Result<` AFTER EVERY WRITE, not just once. Bit tests on
  values with the sign bit set are unreliable -- `xiom.radiotap` used
  divisor/modulo arithmetic end-to-end (same family as `xiom.can`'s
  bit-31 note). UEFI/CRC: a stored CRC field must be treated as zero while
  computing its own CRC (`xiom.gpt`). `xiom.pcapng` needed an explicit
  LE/BE branch for 64-bit composition; `xiom.miniseed` corrected the
  brief's non-existent sample-count field (derived accessor), tenths range
  0..9999, and BE-only stance; `xiom.ass` hit the benign E001
  borrow-in-struct advisory when a Vec is both borrowed and moved. Two
  more delegate silent aborts (`pcapng` #1 recovered by one retry).
  Wave 31 added: trap 14 keeps recurring in **parameter** positions
  (`xiom.usb` found 8 after a green run, `xiom.mbr` 1) -- the post-green
  grep is mandatory. `str_len`/`byte_at` DO work on a typed local bound
  from a `Vec[Str]` element (`xiom.usb` probe; the dtb caution was
  over-broad), while `==` still must be avoided. USB strings:
  `bLength = 4 + 2*text_units` (the string index counts as one UTF-16
  unit). `xiom.gpt`: a stored CRC field must be zero while computing its
  own CRC. `xiom.miniseed`: no sample-count field in the fixed header,
  tenths range 0..9999, BE-only. Working patterns (not bugs):
  module-scope `pub const` resolves unqualified in importers; nested plain
  structs and `Vec[Vec[UInt8]]` struct fields compile and mutate; `--run`
  leaves a gitignored `a.exe` in the package dir.
  Wave 32: `xiom.rpm` recovered on the third attempt with the skeleton-first
  brief (19/19); the real RPM header prefix is 4-byte magic/version + 4
  reserved bytes, then count/store-size (not "magic + 8 reserved").
  Wave 33: the file-write tooling introduced mixed brackets again -- `gif`
  fixed 16, `mp3` several -- both verified clean by the post-green grep
  (trap 14 remains the top trap). `xiom.amqp` found a **loop-carried
  miscompile** on v0.61.3: a stack decoder reusing `ends.push(pos + 4 +
  sub_len)` returned the first container's end offset in the second
  iteration (any two containers in one parent failed with `bad table`/`bad
  array`, found by byte bisection); the workaround decodes nested containers
  with a recursive per-container function (comment at `src/amqp.xi:1266`).
  `xiom.mkv` treats an unknown-size Cluster end as a documented boundary
  heuristic and decodes EBML floats as fixed-point integer milli-units;
  `xiom.avro` accepts non-minimal varints <=10 bytes (spec does not require
  shortest form) and exposes float/double as raw LE octets (`Vec[Float64]`
  banned, no Int<->Float64 bitcast).
- **Harness/tooling (this session):** `scripts/port.ps1` now **fails closed**
  when a suite prints zero `[PASS]` markers (a quiet run had accepted an
  interrupted suite as green; see `a0d7fc4`). PowerShell scripting pitfalls
  hit while running the publish lane: variable-colon parsing
  (`"$RunId:"` needs `${RunId}:`), `[int]` overflow on GitHub run IDs
  (use `[long]`), and `--input -` stdin pipes for JSON bodies are
  unreliable from background PowerShell (use a temp file).
- **.github session:** licensing pass done here (LICENSE-MIT/APACHE/NOTICE,
  canonical holder); SPDX/`.md` header pass and rulesets remain theirs.
  New: `publish-registry.yml` should re-mint the OIDC token per publish
  attempt (or on 401) -- the single job-start token expires in ~6 min and
  fails long runs (section 5, run `36251091427`).
- **Owner:** relays, scope deltas, production greenlight, OAuth callback
  check, Phase 2 direction; new decisions queued: tftp 0.1.0 collision and
  the registry scope delta for waves 31+32.
