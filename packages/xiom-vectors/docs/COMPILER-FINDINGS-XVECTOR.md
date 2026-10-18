<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

> **Coordination bus (2026-10-10):** cross-lane items live in the
> private `xiom-lang/xiom-relays` repo. As of 2026-10-16 **three XVECTOR
> findings are open, all on v0.64.5**: **XVC-C-16** (linux-x64 HTTP-service
> search miscompile, found on WSL during the archive pass;
> `REL-20261015-2142-xvector`), **XVC-C-17** (imported-type module-level
> var stores drop pointer fields; found building the G-1 sync smoke;
> `REL-20261015-2216-xvector`), and **XVC-C-18** (JSON object Map-key
> reads through a `match` enum binding return garbage; found on Windows
> during the L-3 router slice; `REL-20261016-1541-xvector`). File new
> findings as relay items, not here.

# Compiler findings from the XVECTOR lane

Findings collected while building the xiom-xvector vector database with the
latest toolchain (owner policy: track latest; no fixed pin).

Instrument: **XIOM Compiler v0.64.5** (current pin; released 2026-10-15,
tag `84f761c5`, run 38792051847; installed lane-local on Windows
(`out\toolchain`) and WSL (`~/.xvector-toolchain`); see the isolation note
in `SESSION.md`),
Windows + Linux/WSL; stdlib `E:\xiom-lang\stdlib`
(`/mnt/e/xiom-lang/stdlib` in WSL; tree `ea1c312b` at the v0.64.5 battery);
registry packages consumed:
`xiom.wal` 0.1.0 + `xiom.metrics` 0.2.0 + `xiom.rate` 0.2.0 from the
lane-local package home (`docs/XIOM-WAL-ADOPTION.md` /
`docs/XIOM-METRICS-ADOPTION.md` / `docs/XIOM-RATE-ADOPTION.md`).
All findings below were reported on v0.64.0, re-tested on v0.64.1, and
re-tested again on v0.64.2 (2026-10-09); **XVC-C-08..C-12** were found later
on v0.64.1 (2026-10-08/09) and re-tested on v0.64.2; **XVC-C-13** and
**XVC-C-14** were re-tested on v0.64.3/v0.64.4 and **VERIFIED FIXED on
v0.64.5** (2026-10-15: C-13 prints 65 with the warning gone; C-14's bundle
builds+runs exit 0); **XVC-C-15** was fixed in v0.64.4 (m271) and stays
green on v0.64.5. **v0.64.6: C-16's fix shipped (m339), C-17 (m337;
repro extended with the Semaphore multi-field variant) and C-18 (m346;
the garbage-key repro prints `docs`/`logs` again); BOTH-PLATFORM
verification completed 2026-10-17 -- the WSL repros are green (C-16
acceptance exit 0) and the full WSL battery is ALL GATES GREEN on
stdlib tree `7073a64`; the v0.64.6 re-pin is COMPLETE.**

**Current status (compiler v0.64.7, 2026-10-18): ONE XVECTOR finding open --
XVC-C-19 (module-level function-call / allocating `var` initializers hang the
compiler on v0.64.7; repro `docs/repro/xv-global-init-hang/`, bus
`REL-20261018-1518-xvector`). Everything else VERIFIED FIXED and still green
on v0.64.7: C-16 (m339), C-17 (m337), C-18 (m346); C-13 m320, C-14
m278+m298, C-15 m271, phantom imports m266/m267.** 18 findings total (C-01..C-18), each with a
repro bundle under `docs/repro/`:

| Range | Status |
|---|---|
| XVC-C-01..C-08, C-10 | **verified fixed** (C-01..C-06 in v0.64.1; C-07/C-08 in v0.64.2 after the repro re-runs; C-10 incidentally fixed in v0.64.2 -- inline pad shape no longer segfaults) |
| XVC-C-11, C-12 | **fixed in context** (v0.64.2 re-test of the original failing unit: unguarded `read_file` Str content and 5-byte `read_file_bytes` both clean) |
| XVC-C-09 | **repro green** on WSL + Windows; workaround retained (weaker re-test -- the crash lived in the compiled engine path, not the repro shape) |
| XVC-C-13 | **VERIFIED FIXED on v0.64.5 (m320 `b672a19f`; re-verified 2026-10-15)** -- was: `&Str` parameter types unknown to the checker (`unknown type '&Str' -- defaulting to i64` warning, then silent wrong values). The repro now builds with the warning GONE and prints `first_byte(A)=65` with exit 0 on Windows + WSL (was 167 Win / 63 WSL on v0.64.4). Bus item `REL-20261010-1550-xvector` verified + closed |
| XVC-C-14 | **VERIFIED FIXED on v0.64.5 (m278 `484d9f21` + m298 `c18e550e`; re-verified 2026-10-15)** -- was: two same-named struct types across modules with one layout taking over the other (clang store reject at `xiominput.ll:850` when the shapes differ; silent wrong fields when compatible). The bundle now builds and runs exit 0 with `shim counter=1 tally hits=1` on Windows + WSL. Bus item `REL-20261010-1709-xvector` verified + closed |
| XVC-C-15 | **VERIFIED FIXED on v0.64.4 (m271 `f69b542e`; re-verified 2026-10-12)** -- was: literal stores into `Vec[Float32]` slots skipped numeric narrowing (a Float64 literal stored its raw low 32 bits, `a[1] = 7.0` -> 0.0; an Int literal stored raw bits as the f32 pattern, `b[1] = 7` -> 9.8e-45; struct-field stores corrupted the same way). Repro now exits **0** on Windows + WSL (all six shapes); the lane dropped its `as Float32` workaround (see `probe_quantization`) |
| retained workarounds | C-04 `SearchHits` wrapper (zero-cost public API), C-01 suite dispatch style, C-02 predicate negatives, C-09 local-assign nested writes, C-10 pad function + strict bounds, C-11/C-12 byte parser + `file_size` guard, C-14 single type name program-wide (shim `Counter` retired) |

Format: `| Date | Finding | Evidence | Workaround | Impact |`.
Every finding carries a minimal repro bundle under `docs/repro/`.

Reference docs read before reporting (do NOT re-run known bisections; add
delta evidence only): packages `docs/COMPILER-FINDINGS.md`,
`docs/repro/README.md`, PULSE `docs/COMPILER-FINDINGS-PULSE.md`.

## Re-test on v0.64.1 (2026-10-08) -- 6 of 7 FIXED (XVC-C-08..C-12 opened later)

| ID | v0.64.1 verdict | Evidence |
|---|---|---|
| XVC-C-01 | **FIXED** | `probe.xi` compiles; `probe_deref.xi` compiles and runs exit 0 (was clang exit 1 / `-1073741819` crash) |
| XVC-C-02 | **FIXED** | contract violation now prints the message and exits **1** (was 0) |
| XVC-C-03 | **FIXED** | suite compile: **W004 count 0** (was 18+) |
| XVC-C-04 | **FIXED** | full 6-shape matrix correct, incl. `Result[Vec[SR]]` id=42 and `Result[Vec[Str]]` alpha; `Option[Vec[SR]]` id=42 |
| XVC-C-05 | **FIXED** | Windows 3/3 fresh builds exact; WSL 9/9 (default x3, probe_vector_store x3, `--sequential` x3) exact |
| XVC-C-06 | **FIXED** | new pin probe `tests/probes/probe_floatval_roundtrip.xi` green 3/3 Windows + 2/2 WSL (direct bind + payload-store roundtrip bit-exact) |
| XVC-C-07 | **OPEN** | `Str::from_utf8(&kb)` still fails: Windows clang `invalid getelementptr indices`; WSL LLVM verifier same error at `out/r07_lin.exe.ll:648` |

Regression on v0.64.1: suite **165/165 x2** (Windows + WSL), all five
probes green x2, WSL matrix 9/9 -- no new compiler regressions observed.

Workarounds left in place (unwind candidates, not urgent): suite direct
dispatch (C-01), predicate-based negative tests (C-02), `SearchHits`
struct wrapper (C-04), IntVal/TextVal gating with FloatVal diagnostics
(C-06). `Str::from_utf8` calls pass the Vec by value (C-07; reverted to the
`&` spelling on v0.64.2 -- see the re-test section).

## Re-test on v0.64.2 (2026-10-09) -- all relayed XVECTOR fixes verified

Tag `v0.64.2` (compiler repo `c51170a6`), installed Windows + WSL 2026-10-09.
The lane re-ran every repro bundle, then the full batteries: suite
**169/169 x2** (Windows + WSL) + **18 probes x2** (Windows) + WSL spot;
ALL GATES GREEN.

| ID | v0.64.2 verdict | Evidence |
|---|---|---|
| XVC-C-03 | **FIXED (kept)** | suite compile: W004 count **0** (was 18+ on v0.64.0; fixed v0.64.1) |
| XVC-C-06 | **FIXED (kept)** | `probe_floatval_roundtrip` green (pinned); suite FloatVal payloads green |
| XVC-C-07 | **FIXED** | `docs/repro/xv-from-utf8-vec-ref/probe.xi` (`&Vec` spelling) compiles and returns `A` (exit 0); payload codec + suite mirror reverted to `&` |
| XVC-C-08 | **FIXED** | `probe.xi` exit 0 ("hydration-guard: green"); `variants.xi` all 14 variants green (was exit 5); suite hydration mirror restored (168 -> 169 checks) and asserts the trailing `has_payload` flags |
| XVC-C-09 | **repro green** | `docs/repro/xv-wsl-nested-field/probe.xi` green on WSL + Windows; release notes: nested-field mutation writes through. Weaker re-test (the inline pattern was green before); workaround retained |
| XVC-C-10 | **FIXED** | `docs/repro/xv-decode-pad-loop/probe.xi` inline pad shape no longer segfaults at `m=512` (exit 0); lane keeps `pad_adj_slots` + strict bounds |
| XVC-C-11 | **fixed in context** | a copy of the original failing unit (`probe_wal_file`) reads an 11-byte file as Str (`str_bytes` len 11), unguarded: green |
| XVC-C-12 | **fixed in context** | same unit shape: unguarded 5-byte `read_file_bytes` returns 5 bytes (no contract abort) |

Workarounds reverted: the `Str::from_utf8(&Vec)` spelling is back
(`src/payload/payload.xi` + suite mirror) and the suite hydration flag
assertions are restored. Workarounds retained deliberately: `SearchHits`
wrapper (C-04, zero-cost public API), local-assign nested writes (C-09,
also cleaner), `pad_adj_slots` + decode bounds (C-10, bounds are strictness),
byte-wise file parsing + `file_size` guard (C-11/C-12, defense in depth).

## Findings

| Date | Finding | Evidence | Workaround | Impact |
|---|---|---|---|---|
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-01: calling a `&fn() -> T` parameter as `f()` emits invalid LLVM IR** (`%tmp = inttoptr i64* %tmp5 to i64 ()*` -- `inttoptr` needs an integer operand, gets a pointer) -> `clang failed with exit code 1`, `invalid cast opcode for cast from 'ptr' to 'ptr'`. The `(*f)()` spelling **compiles** but the call then uses a wrong signature (`i64 (i64)*` for a `fn() -> Int`) and **crashes at runtime** (Windows exit `-1073741819` / access violation). A `fn()` pointer in a **struct field** (`(op.f)(&x)`) is GREEN (the packages-lane `generic-fnptr` fix covers that shape; this is the *reference-parameter* call shape). | `docs/repro/xv-fnptr-call-inttoptr/probe.xi` (clang exit 1, IR at line offset: `inttoptr i64* %tmp5 to i64 ()*`); `probe_deref.xi` compiles but exits `-1073741819`; control `probe_local.xi` same crash; `probe_struct_fnfield` (packages lane) exit 0. Hit by the conformance suite: 126 test-function pointers dispatched through `fn run_one_test(fn_ptr: &fn() -> TestResult)`. | None for the call itself: **do not use `&fn()` parameters with call syntax**. Evaluate at the call site (`run_one_test(test_fn())` with a `TestResult` parameter) or use a struct-field fn pointer. The suite was rewritten to direct dispatch. | blocks all higher-order test harnesses/trampolines using `&fn()` parameters; silent runtime crash for the `(*f)()` form |
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-02: a runtime `requires` violation aborts the process with exit code 0.** A contract failure prints `contract violated: requires at <line>:<col>` (stdout AND stderr) and terminates with exit 0, even when `main` would have returned a nonzero value on the same path. CI/scripts gating on the process exit code cannot see contract failures; a test suite dies silently-green. | `docs/repro/contract-trap-exit0/probe.xi`: `fn take_positive(x: Int) requires: x > 0`; `main` returns `take_positive(-5)`. Expected: continue with `-5` (exit 251) or trap nonzero. Observed: violation message, `EXIT=0` (`cmd /c ... & echo %ERRORLEVEL%`). Caught in vivo: the conformance suite called `engine_create_collection(&mut eng, 0, ...)` in a negative test -> suite aborted mid-run at 86/126 lines and reported exit 0. | Never call a contracted entry point with arguments that violate its `requires` (test the predicate instead). Scripts should also treat contract text on stdout as failure (XVPOLICY note: grep for `contract violated` in runner logs). | silent-green CI on contract violations; any harness that intentionally exercises error paths traps |
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-03: W004 false positives on unit-enum `match` -- "unreachable match arm (an earlier arm already matches these values)" is emitted for EVERY arm after the first**, on matches over all-unit enums. 18+ occurrences in the conformance suite (lines 354-355, 583-588, 607, 614, 926-927, 961-962, 2299-2301, 2441...). All arms are distinct variants; `--explain W004` semantics do not apply. A real unreachable arm would be buried in the noise. | `tests/test_conformance.xi` compile log: `warning[W004]` on `match metric { Cosine, DotProduct, Euclidean }`, on the 7-arm `SegmentStateKind` map, and on 3-arm `AnnIndexKind` / `DistanceMetric` maps; no duplicate arms exist. | None needed (warning-level); do not rely on W004 to find dead arms on this pin. | warning noise hides genuine unreachable-arm diagnostics; checker treats distinct unit variants as equal patterns |
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-04: a `Result[T, E]` / `Option[T]` whose payload is DIRECTLY a `Vec[non-scalar]` loses element field data at the caller**: the length survives, but struct element fields read as `0` and `Str` element fields read as address-like integers. `Result[Vec[Int], E]`, `Result[Int, E]`, `Result[Struct{Int,Float32}, E]`, direct `Vec[SR]` / direct `Vec[Str]` returns and `Option[Struct-with-Vec-field]` are all GREEN -- the broken shapes are `Result[Vec[SR], E]`, `Result[Vec[Str], E]`, `Option[Vec[SR]]`. Wrapping the Vec in a struct repairs the payload (`Result[Hits{items: Vec[SR]}, E]` -> correct). Found when `engine_search` returned `Result[Vec[SearchResult], CoreError]` and a consumer read `Ok(hits)` with every `id`/`distance` zeroed. (Regression/extension of the v0.62.2-fixed generic-fnptr ABI family -- do not fold into it; the fixed probes only cover the struct-field fn shape and scalar `Vec[U]`.) | `docs/repro/xv-result-vec-struct/probe.xi` (direct vs wrapped: `id=42` vs `id=0`); `probe_matrix.xi` (6-shape matrix: only the two `Result[Vec[non-scalar]]` rows corrupt); `probe_workaround.xi` (wrapper green, `Option[Vec[SR]]` red). Engine consumer A/B: `tests/probes/probe_vector_store.xi` search hit ids 1,2 with zero distances before the wrapper. | Wrap the Vec in a struct payload (`type SearchHits = { items: Vec[SearchResult]; }`) -- adopted by `src/engine.xi` (`SearchHits`) and mirrored in the suite (`test_search_hits_shape` is the regression guard). **Per-build pin added 2026-10-08: `tests/probes/probe_result_shapes.xi`** (all six shapes + Option + wrapper + real engine path; 8/8 Windows + 2/2 WSL fresh builds green). Decision (2026-10-08): keep the wrapper for now -- the C-08/C-09 context-sensitive family is still open; revisit at the next archive. | silent wrong query results for any API returning `Result[Vec[Row]]`; exactly the shape a vector DB returns |
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-05 (major): per-build nondeterministic codegen -- Float32 arithmetic on `Vec[Float32]` elements can be lowered as INTEGER arithmetic on the IEEE-754 bit patterns.** In `probe_failing.xi`, a red build's `vector_dot(p2, q)` returns double `1.13319008125164e+18` = `1063675494 x 1065353216` = `0x3F666666 x 0x3F800000` -- the f32 **bit patterns** of `0.9` and `1.0` multiplied as `Int`s; `p2.data[0]` prints as `1063675494.0` (the integer of `0x3F666666`). Green builds of the same bytes are exact. Correctness flips **per compilation**: irrelevant byte changes (a comment, the module name) and the `--sequential` flag all perturb which lowering is emitted, in BOTH directions. Smaller sibling probes importing the SAME engine module (`evidence_debug_cosine.xi`, `evidence_bisect_a/b/c.xi`) were green in every compile; a self-contained control is green. So the trigger is compilation-unit shape + emission order, not the source semantics. Same family as the packages-lane "nondeterministic payload-length read" note. | Bundle `docs/repro/xv-f32-int-miscompile/`: `probe_failing.xi` (flaky), `evidence_debug_cosine.xi` + `evidence_bisect_a/b/c.xi` + `evidence_debug_search.xi` (green controls), `control_selfcontained_min.xi` (green self-contained), `linux_matrix.sh` (WSL matrix runner). Measured 2026-10-08, v0.64.0: Windows same-bytes default **1/3, 2/3 and 1/3 red** across three 3x batches (never stable); Windows `--sequential` **2/3 red then 3/3 green on earlier bytes** (not a fix); WSL Linux default **3/3 red** on earlier bytes, **3/3 green** after a comment-only change; WSL `--sequential` 3/3 red on the later bytes. Full raw-bits decode in the bundle README. | **No reliable flag workaround.** Treat a red numeric check as a build rejection: every evidence build must run its own numeric assertions (the suite/probe do); rebuild and re-verify rather than trusting a binary. `scripts/build.ps1 -Sequential` / `XVECTOR_SEQUENTIAL=1 scripts/build.sh` remain as A/B diagnostics only. | silent wrong numeric results in any production unit -- a vector DB's distance kernel is exactly this shape; needs compiler-lane localization of the int/float lowering decision (watch for a unit-hash/order dependency) |
| 2026-10-08 | **[FIXED v0.64.1]** **XVC-C-06: Float32 enum payloads can read as 0 in a given compilation unit/build** (tag intact, payload zeroed) -- same per-build family as XVC-C-05. Observed while adding payload filtering: in the 156-check suite unit a directly constructed `FieldValue.FloatVal(10.0)` extracted as `0.0` (float_bits=0) with `field_value_kind == "float"`; the engine-import probe `probe_filtered_search.xi` failed FloatVal Range/And checks in 2 of 3 builds (`diag FloatVal(2.5) roundtrip bits=0`, expected 4612811918334230528), while IntVal/TextVal/Bool payloads were stable in the same units. Flips green/red across builds like XVC-C-05; small standalone probes with identical code were green (minimal reduction pending). | `docs/repro/xv-f32-payload-zero/README.md` (suite DBG evidence `direct_f=0 stored_f=0 kind=float` + probe diagnostic + rebuild recipe). Lane impact: the suite's Range tests moved to IntVal fields and the probe's FloatVal roundtrip is now a diagnostic print, not a gate. | Do not put Float32 payloads in gating assertions on this pin (metadata with float prices/scores can silently read 0); use IntVal/TextVal for gates and keep FloatVal as a build-verified diagnostic; rebuild + re-verify per build (XVC-C-05 rule). | float-typed metadata silently zeroes in affected builds -- exactly the payload type a vector DB filters on |
| 2026-10-08 | **[FIXED v0.64.2]** **XVC-C-07: `Str::from_utf8(&Vec[UInt8])` type-checks but emits invalid LLVM IR** -- clang `error: invalid getelementptr indices` (`getelementptr %struct.Vec*, %struct.Vec** %tmp, i32 0, i32 0`). Passing the Vec **by value** is correct and is what the stdlib does (`convert/cstring.xi:47`, `convert/escape.xi:577`, `compress/compress.xi:526`). Found while implementing the XVECTOR payload WAL codec; compile fails loudly (no silent wrong code observed). | `docs/repro/xv-from-utf8-vec-ref/` (`probe.xi`: `Str::from_utf8(&kb)` -> clang exit 1; `Str::from_utf8(kb)` -> green). | v0.64.1: pass the Vec by value (stdlib convention). v0.64.2 fixed the `&Vec` spelling (re-verified; the lane reverted to `&`). | blocked a natural API spelling |
| 2026-10-08 | **[FIXED v0.64.2]** **XVC-C-08: a trailing scalar after a Vec-bearing field in a `Vec[Struct]` element reads as uninitialized garbage in some compilation units** (observed: `Bool` reads `true` when stored `false`; `Int` also affected, so not Bool-specific). Found while landing `SearchRequest`-driven search with `with_payload` hydration: `hydrate_hits` pushes `SearchHit{ id; distance; payload: Payload; has_payload: Bool }`. The **same source** is correct in its own module (`tests/probes/probe_search_request.xi`, green 8/8 fresh builds) but miscompiles in the big conformance-suite unit (hydration flags read true) and in the standalone reduction. Trigger matrix (`variants.xi`): needs the Vec-bearing field plus surrounding machinery in a loop; scalar-only and plain-push shapes are green (V1-V4, V6, V8); an `if` + `Option[non-scalar]` match in the loop is present in all red shapes, but sign/`Int` flag variants are red too; declaring the scalar **before** the Vec is green in the bundle (V13) -- yet the same reorder in the suite unit produced an access violation (`0xC0000005`), so layout workarounds are context-sensitive in both directions. | `docs/repro/xv-trailing-field-vec/`: `probe.xi` -> exit 1 `BAD detach count`, 5/5 Windows builds; `variants.xi` -> exit 5 (first failing variant: V5/V7/V10/V11/V12/V14 red, `code 2` = second element's flag true; V13 green); `min.xi` scalar control green. | v0.64.1: do not trust trailing-scalar reads in affected units; hydrate flags were gated in the real-module probe only. v0.64.2 fixed the layout (repro exit 0, all 14 variants green); the suite hydration assertions are restored (169 checks). | silent wrong metadata (historical) |
| 2026-10-08 | **[repro green on v0.64.2; workaround retained]** **XVC-C-09: a compiled function that mutates a nested struct field through another module in a loop can segfault on WSL while Windows is green** -- `engine_set_index` (module `xiom.vector.engine.core`) assigns `eng.graph = hnsw_new(...)` and loops `hnsw_insert_ref(&mut eng.graph, ...)` while reading sibling fields; after the HNSW id-map fields landed, the call segfaulted on WSL 3/3 runs (no output past the previous line) with the Windows build green 6/6. The identical steps inlined in the probe unit, and the raw-store build loop, are green on WSL -- context-sensitive lowering, same family as XVC-C-08. | `docs/repro/xv-wsl-nested-field/` (probe + README; revision-pinned to `bca8b7f`: WSL segfault at `engine_set_index`, Windows + inline steps green; green everywhere after the fix commit). | Build the nested value in a LOCAL variable and assign the field once at the end; re-verify on WSL (WSL spot is part of every wrap). | silent platform divergence: a revision can pass Windows and crash Linux without a diagnostic |
| 2026-10-08 | **[FIXED v0.64.2]** **XVC-C-10: `hnsw_decode`'s inline pad loop (`while pad < m` pushing zeros into `g.adj`) segfaults at `m >= 512`** (Windows + WSL), even on otherwise pristine streams and with a forced `None` return afterwards. Found by the new deterministic fuzz probe. Control experiments (712k standalone `Vec[Int]` pushes; the same nested pad loop alone; interleaved pushes into two struct `Vec` fields) are all green -- context-sensitive lowering, family of XVC-C-08/C-09. | `docs/repro/xv-decode-pad-loop/` (probe + README, revision-pinned: pre-fix `e0b1f7f` segfaults after "decode start"; post-fix exits 0). General gate: `tests/probes/probe_fuzz_codecs.xi`. | v0.64.1: pad step behind a function boundary (`pad_adj_slots`) + strict bounds (`m <= 512` = AnnParams max degree; `count <= words.len()`). v0.64.2 fixed the crash (inline shape re-verified green); the bounds stay as strict-decode hygiene. | crash on malformed graph-codec input (historical) |
| 2026-10-09 | **[fixed in context on v0.64.2]** **XVC-C-11: `io.read_file` content does not survive in some compilation units** -- `Ok` for a written file, but the returned Str's content is broken in affected units (`slice.str_bytes(s)` = 0 bytes for an 11-/1771-byte file; silent wrong data). `Str::from_utf8` shows the same class (correct lengths, address-like digits when split/printed). Same APIs are GREEN in a minimal control unit -- unit-context-sensitive, family of XVC-C-08. | `docs/repro/xv-stdlib-file-read-defects/` (`probe_str_content.xi` green in its own unit; the broken context was `probe_wal_file`'s unit while building the file-backed WAL). | Read bytes via `read_file_bytes` and parse byte-wise; never handle file content as a Str (v0.64.2 re-tested green in the original context; the pattern stays as defense in depth). | silent wrong file content for any component reading files as text (historical) |
| 2026-10-09 | **[fixed in context on v0.64.2]** **XVC-C-12: `io.read_file_bytes` aborts on files of <= 8 bytes** -- `contract violated: ensures at 947:12` (the ensures `result is Ok => result.len() >= 0` cannot be false for a successful read); zero-byte files included; 9+ bytes read fine. The same call is GREEN in a minimal control unit (unit-context-sensitive). | `docs/repro/xv-stdlib-file-read-defects/` (`probe_tiny_read.xi` green in its own unit; the abort context was `probe_wal_file`'s unit). | Guard with `io.file_size` and skip reads shorter than the shortest valid input (WAL guard `< 25`, semantically exact; v0.64.2 re-tested green in context -- the guard stays as defense in depth). | fatal abort for ordinary small-file reads in affected units (historical) |
| 2026-10-09 | **[OPEN, v0.64.2]** **XVC-C-13: `&Str` parameter types are unknown to the type checker** -- `xiom: warning: unknown type '&Str' -- defaulting to i64. This may produce incorrect code.`; the function body then reads the parameter as an integer (`first_byte("A")` returns **71 on Windows / 127 on WSL** instead of 65; no crash). Found while adding the M-D2 manifest file: `manifest_name_valid(name: &Str)` made every name validate as invalid (`slice.str_bytes` on the i64 yields no bytes), so `manifest_persist` refused every registry. Every stdlib/lane Str parameter is by value, so the shape had never been exercised. | `docs/repro/xv-str-ref-param/probe.xi` (warning present on both builds; Windows 71 / WSL 127, both exit nonzero). | Pass `Str` **by value** (lane + stdlib convention); the manifest validator is by-value. | warning-loud but value-silent: a `&Str` parameter compiles and returns garbage |
| 2026-10-10 | **[OPEN, v0.64.2]** **XVC-C-14: two same-named struct types across modules -- one layout takes over the other** -- found in the `xiom.metrics` 0.2.0 adoption: the xvector core shim's `Counter` and the package `Counter` coexisted in one program. `VectorEngine` (declared in `xiom.vector.engine.core`, importing only the shim) was emitted with `%struct.xiom.metrics.Counter` field layouts while `engine_new` produced shim values -- clang rejected the store (`xiominput.ll:20528`, `'%tmp24' ... shim.Counter ... but expected xiom.metrics.Counter`); all XIOM-level checks passed first. The minimal repro (4 modules) shows the reverse direction: `repro.tally` (importing `xiom.metrics`) gets the **shim** layout for its `Tally.hits` field while `metric_counter_new()` returns the package type. Trigger (tested): two modules each declare a struct field typed by the same short name, resolving to different same-named types; a single such struct stays green. The winning side is program-order dependent; when the two layouts are compatible the wrong fields compile silently. | `docs/repro/xv-counter-type-shadow/` (mini-project + `xiom.toml`; Windows + WSL identical: clang `xiominput.ll:850:36` store mismatch; WSL `opt` prints "LLVM IR verification failed" first and keeps the IR). | One type name, one type: the engine stat counters moved onto `xiom.metrics` and the shim `Counter` was retired in the adoption slice (single `Counter` type program-wide; batteries green). Keep the repro as the regression gate. | struct-field layout silently resolved by short name across modules; wrong fields when the layouts are compatible, clang error only when they differ |
| 2026-10-11 | **[FIXED v0.64.4 (m271 `f69b542e`); verified 2026-10-12]** **XVC-C-15: literal stores into `Vec[Float32]` slots skip numeric narrowing** -- `a[1] = 7.0` (Float64 literal) stores the raw low 32 bits of the f64 constant (**0.0**); `b[1] = 7` (Int literal) stores the raw integer bits as the f32 pattern (**9.80908925027372e-45**); struct-field stores (`vector.data[1] = 7.0`) corrupt the same way. A Float32 variable, an explicit `... as Float32`, and `push(...)` all convert correctly (`Vec[Float64]` slots are also fine). Silent data corruption: no warning, no clang error. Found by `probe_quantization`'s constant-dimension check (a `c[1] = 7.0` setup line made training see 0). | `docs/repro/xv-f32-slot-literal-write/probe.xi` (6-shape matrix: A/B/E corrupted pre-fix, C/F/G controls green; v0.64.3 Windows exit **3**; **v0.64.4: exit 0, Windows + WSL**). | None needed post-fix: the repro exits 0 and the explicit `as Float32` workaround in `probe_quantization` was dropped 2026-10-12 (23 checks green x2; the constant-dim assertion is the unguarded regression line). | silent wrong values wherever a float literal is stored into a float vector element -- feeds training/encoding paths garbage |
| 2026-10-15 | **[VERIFIED FIXED v0.64.6 (m339), both platforms]** **XVC-C-16: the HTTP service `/search` path miscompiles on linux-x64** -- the WSL full battery went RED on 6 service/search gates (`probe_http_service` 6 failed checks, `probe_service_limits` 3, `probe_service_auth` 3, `probe_http_fuzz` 1, `probe_metrics` 3, `probe_http_server` 3) while everything else (suite 177/177 x2, 38 other probes x2, sbom 44 modules unsafe=0, bench smoke, kill matrix) is green; the Windows battery on the same tree is ALL GATES GREEN. Symptom: every `/search` request through `http_service_handle` misbehaves although the collection exists -- knn/offset/batch/empty-collection -> 404 `{"error":"not found"}`, `mode:"range"` with no pagination fields -> 400 `"range mode does not support pagination"`. Direct controls in the same program are GREEN under the failing compiler (`select_collection` Ok; `search_request_new` + `search_with_request` -> 2 hits with exact field readback; json extraction -> "docs"), and the failure reproduces with the compiler's BUNDLED stdlib => context-sensitive miscompile of the service module's search-handler lowering (XVC-C-08/C-09 family), not the stdlib tree. Bisect: linux green v0.64.4 / red v0.64.5 (m313-m333 window; m328-m333 pin-gate round a candidate). | `docs/repro/xv-http-service-linux/` (probe + README with the full A/B table): v0.64.4 linux (sha256 72a131cc) exit 0; v0.64.5 linux (246e5e82) exit 3; v0.64.5 windows (bd71e2d3) exit 0; `probe_http_service` 0 fails vs 6 fails | none -- the v0.64.5 re-pin is **HELD** (Windows battery green, WSL red); filed `REL-20261015-2142-xvector` (high) | WSL/linux acceptance of the service read path red until fixed; smoke-only impact (engine probes + suite green) |
| 2026-10-16 | **[VERIFIED FIXED on v0.64.6 (m337), both platforms]** **XVC-C-17: imported-type module-level var stores drop pointer fields** -- `var GA: mutex.SyncMutex = ...; GA = mutex.SyncMutex{ locked: <non-null> }` reads back `locked == null`; same with `GA = mutex_new()`. A LOCAL type with identical shapes keeps the pointer (and scalar fields persist in both cases). Found building the G-1 thread + sync smoke: the natural global-lock pattern silently breaks (stdlib `requires` aborts "contract violated" or, without checks, an unshared lock = data race). Ruled out: pointer value magnitude/source, local-local copies, helper-read paths. Trigger = imported-type global declaration + whole-struct store. Cross-ref: engine W2 "&mut struct FIELD writes miscompile" (`REL-20261015-1538-engine`); hypothesis = declared-layout vs store-layout mismatch (XVC-C-14 class). | `docs/repro/xv-global-ptr-field/` (probe + README): v0.64.5 Windows + WSL exit 1 (A/B drop, local-type controls pass). No v0.64.4 A/B possible (cannot compile the current stdlib tree; bundled lib predates `SyncMutex`) | lane ships the Int-handle workaround (validated: spinlock exact across 4 real threads; `tests/probes/probe_thread_sync.xi`); filed `REL-20261015-2216-xvector` (high) | blocks global lock/handle sharing; defers the G-1 channel cross-thread leg |
| 2026-10-16 | **[VERIFIED FIXED on v0.64.6 (m346), both platforms]** **XVC-C-18: JSON object Map-key reads through a `match` enum binding return garbage Strs** -- iterating `entries.keys[i]` where `entries` is bound by `match cv { Object(entries) => ... }` (the keys of a parsed JSON object) reads pointer-shaped garbage instead of the key text; a `Str` charset validator therefore rejects VALID keys (found in `router_mapping_load`, L-3 slice: a valid mapping was refused with "collection name invalid"). Extra datum: `name.len()` on the inferred local is rejected at COMPILE time (`error[T001]: cannot call 'len' on this expression` -- receiver type unresolved) while the same value still coerces into a `Str` parameter => silent garbage instead of a type error. Controls that read correctly: an explicitly-typed local, and copy-out of `entries.keys` into a local Vec before the loop. | `docs/repro/xv-object-key-iter/` (probe + README): v0.64.5 Windows prints `key=[1946864332608]` -> exit 1; expected `key=[docs]`/`[logs]` -> exit 0. No v0.64.4 A/B (tree incompatibility); suspected C-09/C-14/C-16 family, sort against the m339 wave | lane ships the copy-out workaround (`var ks = entries.keys; var name = ks[i];`) -- `probe_router_2shards` 72/72 green; filed `REL-20261016-1541-xvector` (high) | silent wrong string data + valid inputs refused wherever object keys are consumed through match bindings |
| 2026-10-18 | **[OPEN on v0.64.7]** **XVC-C-19: module-level function-call / allocating `var` initializers hang the compiler** -- a 15-line module with `var G_CH: channel.Channel[Int] = channel.channel_new[Int](4);` or `var G_V: Vec[Int] = Vec[Int].new();` + `var G_CALL: Int = five();` compiles >2 min with no output and no exit (orphaned compiler processes; watchdog-class kill). SHAPE-SENSITIVE: the same channel-call initializer COMPILED inside the much larger `probe_thread_sync` module, whose process then HUNG AT STARTUP before `main` printed (the global initializer appears to run before the runtime/heap is ready). Null-only literal globals are fine. | `docs/repro/xv-global-init-hang/` (probe + README; deliberately NOT in the battery -- it hangs the build). v0.64.7 Windows, 2026-10-18. | lane G-1 probe uses scalar-only globals + a single-slot mailbox under the shared spinlock (14 checks green x2 both platforms); filed `REL-20261018-1518-xvector` (high); channel handle form wished to stdlib (`REL-20261018-1518-xvector-2`) | build-blocker class for any consumer with non-trivial global initializers; the natural global-handle pattern is unusable |

## Notes for the compiler lane

- C-15 repro (XVC-C-15, now a regression gate): `docs\repro\xv-f32-slot-literal-write\probe.xi` --
  `.\scripts\build.ps1 docs\repro\xv-f32-slot-literal-write\probe.xi -Name repro_f32_slot_literal`
  then run `out\repro_f32_slot_literal.exe` (v0.64.3: exit 3; shapes A/B/E
  corrupt; **v0.64.4: exit 0, all six shapes narrow**).
- Re-run recipe (Windows):
  `.\scripts\build.ps1 docs\repro\xv-f32-int-miscompile\probe_failing.xi -Name pf`
  then run `out\pf.exe`; repeat 3x — expect nondeterminism on Windows.
  `-Sequential` is the A/B switch. On WSL:
  `bash scripts/build.sh docs/repro/... <name>` (set `XVECTOR_SEQUENTIAL=1` for the flag).
- The conformance suite is `tests/test_conformance.xi` (169 checks, self-contained; does not import `src/engine.xi`).
  Run: `scripts\run-suite.ps1` / `bash scripts/run-suite.sh`.
- The critical-primitive probe is `tests/probes/probe_vector_store.xi` (imports `src/engine.xi` via `xiom.toml` roots;
  exercise with `scripts\run-probe.ps1 tests\probes\probe_vector_store.xi -Sequential`).
- Phase 3 filtering probe: `tests/probes/probe_filtered_search.xi` (engine-import unit; prints the XVC-C-06
  FloatVal diagnostic; run with `scripts\run-probe.ps1 tests\probes\probe_filtered_search.xi -Runs 2`).
- SearchRequest/hydration probe: `tests/probes/probe_search_request.xi` (real-module hydration gate;
  XVC-C-08 fixed in v0.64.2, the suite asserts the flags again too;
  run with `scripts\run-probe.ps1 tests\probes\probe_search_request.xi -Runs 2`).
- `&Str` repro (XVC-C-13, FIXED v0.64.5 / m320): `docs/repro/xv-str-ref-param/probe.xi` --
  `.\scripts\build.ps1 docs\repro\xv-str-ref-param\probe.xi -Name strref`
  then run `out\strref.exe` (v0.64.4: prints 167, exit 1; WSL 63; **v0.64.5:
  no warning, prints 65, exit 0 on both platforms**).
- Short-name type-shadow repro (XVC-C-14, FIXED v0.64.5 / m278+m298):
  `docs/repro/xv-counter-type-shadow/` is a mini-project (own `xiom.toml`);
  run from that directory with `src\main.xi` (v0.64.4: clang store mismatch
  at `xiominput.ll:850`, exit 1; **v0.64.5: builds + runs exit 0, output
  `shim counter=1 tally hits=1`, Windows + WSL**). See its README for the
  full recipe.
- Linux service-search repro (XVC-C-16, OPEN on v0.64.5 linux):
  `docs/repro/xv-http-service-linux/probe.xi` --
  `bash scripts/build.sh docs/repro/xv-http-service-linux/probe.xi repro_service_search`
  then `./out/repro_service_search` (v0.64.5 linux: exit 3 -- the three wire
  checks fail with 404/400 bodies; v0.64.4 linux + v0.64.5 windows: exit 0).
  The probe prints each response body plus the direct-API controls.
- Global pointer-field store repro (XVC-C-17, OPEN on v0.64.5 both
  platforms): `docs/repro/xv-global-ptr-field/probe.xi` --
  `.\scripts\build.ps1 docs\repro\xv-global-ptr-field\probe.xi -Name repro_global_ptr`
  then `out\repro_global_ptr.exe` (v0.64.5: exit 1 -- the imported-type
  global stores drop the pointer; the local-type controls pass; WSL
  identical). Workaround pattern in `tests/probes/probe_thread_sync.xi`.
- Object-key read repro (XVC-C-18, OPEN on v0.64.5 Windows):
  `docs/repro/xv-object-key-iter/probe.xi` --
  `.\scripts\build.ps1 docs\repro\xv-object-key-iter\probe.xi -Name xv_object_key_iter`
  then `out\xv_object_key_iter.exe` (v0.64.5: exit 1 -- prints
  `key=[1946864332608]` garbage; workaround: copy `entries.keys` into a
  local Vec first; `.len()` on the raw read is a compile-time T001).
- Bump procedure when the next archive lands: re-run all repro bundles FIRST,
  then the suite x2 + the probes, then re-pin in `SESSION.md` (done for
  v0.64.2 on 2026-10-09 -- see the re-test section).
- Relay state: `docs/RELAY-COMPILER.md` Addenda 1-12 (9 = XVC-C-13,
  10 = XVC-C-14, 11 = XVC-C-15); the v0.64.5 wave (C-13/C-14 closures +
  C-16/C-17 filings) is bus-routed (`REL-20261015-2142-xvector`,
  `REL-20261015-2216-xvector`, and the closed items). C-01/C-02/C-04 stay
  as deliberate lane choices.
- Archive status (2026-10-16): **v0.64.5** installed lane-local on Windows
  + WSL (release run `38792051847`, tag `84f761c5`; assets sha256-verified:
  win `bd71e2d3`, linux `246e5e82`). Full re-test: thread gate GREEN on
  BOTH platforms (acceptance closed; evidence on the thread items); C-13
  VERIFIED FIXED (65 both platforms); C-14 VERIFIED FIXED (bundle exit 0
  both platforms); C-15 + phantom controls stay green; 19-probe repro
  sweep green; Windows battery ALL GATES GREEN. **WSL battery RED on
  XVC-C-16** (linux service-search miscompile; re-pin HELD). **G-1 slice
  landed on top:** `tests/probes/probe_thread_sync.xi` (45th probe, both
  batteries) -- spawn/join acceptance + mutex-guarded counter + atomic
  counter all exact across real threads on both platforms; the channel
  cross-thread leg is blocked by XVC-C-17. Verdicts + closures on the bus
  (`-1550` verified+closed, `-1709` verified+closed, `-2142`/`-2216` open;
  check rows updated on `release-checks/compiler-compiler-v0.64.4`).
- Soak / mixed-workload gate: `tests/probes/probe_soak_mixed.xi`
  (600 deterministic ops with bookkeeping invariants + recovery).
