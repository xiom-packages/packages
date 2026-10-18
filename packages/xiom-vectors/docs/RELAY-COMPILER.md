<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# RELAY -> COMPILER (from XVECTOR, 2026-10-08)

**From:** XVECTOR lane, `E:\xiom-projects\xiom-xvector` (private; owner relays).
**Toolchain:** XIOM Compiler v0.64.0 on Windows (`%LOCALAPPDATA%\xiom.new\bin\xiom.exe`)
and WSL Ubuntu (`~/.local/bin/xiom`); stdlib lane `E:\xiom-lang\stdlib` (`9e64302`).

**Please read:** `docs/COMPILER-FINDINGS-XVECTOR.md` in the xvector repo, with
minimal repro bundles under `docs/repro/`:
- `docs/repro/xv-fnptr-call-inttoptr/`
- `docs/repro/contract-trap-exit0/`
- `docs/repro/xv-result-vec-struct/`
- `docs/repro/xv-f32-int-miscompile/` (includes a WSL matrix runner)

**Five findings, all reproducible on the shipped v0.64.0:**

| ID | One-liner | Severity |
|---|---|---|
| XVC-C-01 | `fn(f: &fn() -> T)` called as `f()` -> invalid IR (`inttoptr ptr to ptr`, clang exit 1); `(*f)()` -> runtime access violation. Struct-field fn pointers are green. | high |
| XVC-C-02 | A runtime `requires` violation prints `contract violated: ...` and **exits 0** (silent-green CI; our suite died mid-run once). | high |
| XVC-C-03 | W004 "unreachable match arm" false-positive on every unit-enum arm after the first (18+ in our suite). | low (noise) |
| XVC-C-04 | `Result[Vec[non-scalar], E]` / `Option[Vec[non-scalar]]` payload loses element fields (structs read 0, Str address-like); wrapping the Vec in a struct is green. | high |
| XVC-C-05 | **Priority.** Per-build nondeterministic lowering: Float32 arithmetic on `Vec[Float32]` becomes **integer arithmetic on the IEEE-754 bit patterns** (red build computes `0x3F666666 x 0x3F800000`); flips green/red with irrelevant byte changes and with `--sequential` in both directions, Windows and WSL. | critical |

**Re-run recipe (Windows, from the repo root):**

```powershell
. .\scripts\dev-env.ps1
1..3 | % { & $env:XIOM_COMPILER -o "out\pf$_.exe" docs\repro\xv-f32-int-miscompile\probe_failing.xi; & "out\pf$_.exe" | Select-String "diag p2 dot" }
```

plus the per-bundle READMEs. WSL: `bash docs/repro/xv-f32-int-miscompile/linux_matrix.sh 3`.

**Asks:** (1) triage XVC-C-05 first (silent wrong numerics; we suspect a
unit-hash/emission-order dependency in the int/float lowering decision);
(2) re-test all five bundles at the next archive so XVECTOR can re-pin and
report per-row deltas. No XVECTOR-side changes are needed to reproduce.

**Addendum (2026-10-08, later same day): XVC-C-06.**
While implementing payload filtering, a sixth finding joined the family:
**Float32 enum payloads can read as 0 in a given compilation unit/build**
(tag intact). Evidence: in the suite unit a directly constructed
`FieldValue.FloatVal(10.0)` extracted as `0.0`; the engine-import probe
`tests/probes/probe_filtered_search.xi` failed FloatVal Range checks in 2 of 3
builds (`diag FloatVal(2.5) roundtrip bits=0`), IntVal/TextVal/Bool stable.
Same per-build flip behaviour as XVC-C-05. Repro + recipe:
`docs/repro/xv-f32-payload-zero/README.md`. Lane workaround: FloatVal is
diagnostic-only in gates until fixed.

**Addendum 2 (2026-10-08): XVC-C-07.**
`Str::from_utf8(&Vec[UInt8])` type-checks but emits invalid LLVM IR (`invalid
getelementptr indices`); passing the Vec **by value** is correct (stdlib
convention). Minimal repro: `docs/repro/xv-from-utf8-vec-ref/`. Found while
writing the payload WAL codec; compile fails loudly.

**Addendum 3 (2026-10-08): v0.64.1 re-test -- 6 of 7 FIXED.**

All seven bundles were re-run on **v0.64.1** (Windows + WSL):

- **XVC-C-01 FIXED** -- both `f()` and `(*f)()` compile and run exit 0.
- **XVC-C-02 FIXED** -- contract violation now exits **1**.
- **XVC-C-03 FIXED** -- W004 count 0 in the suite (was 18+).
- **XVC-C-04 FIXED** -- all six matrix shapes correct, incl.
  `Result[Vec[SR]]` and `Option[Vec[SR]]`.
- **XVC-C-05 FIXED** -- Windows 3/3 and WSL 9/9 builds (incl.
  `--sequential`) produce exact Float32 results.
- **XVC-C-06 FIXED** -- new pin probe
  `tests/probes/probe_floatval_roundtrip.xi` green 3/3 Windows + 2/2 WSL.
- **XVC-C-07 OPEN** -- `Str::from_utf8(&kb)` still fails: Windows clang
  `invalid getelementptr indices`; WSL LLVM verifier same at
  `out/r07_lin.exe.ll:648`. Repro: `docs/repro/xv-from-utf8-vec-ref/`.

Regression on v0.64.1: suite **165/165 x2** (Windows + WSL), all five probes
green x2, WSL matrix 9/9; no new regressions. The lane re-pinned to v0.64.1
and will re-test `xv-from-utf8-vec-ref` at the next archive.

Context: the lane builds a durable vector database; its distance kernel was
exactly the XVC-C-05 shape, and its test harness was exactly the XVC-C-01
shape (both worked around, see SESSION.md).

**Addendum 4 (2026-10-08, evening): XVC-C-08 -- new silent-wrong-result shape on v0.64.1.**

While landing `SearchRequest`-driven search with `with_payload` hydration, a
new shape surfaced: **a trailing scalar after a Vec-bearing field in a
`Vec[Struct]` element can read as uninitialized garbage** (`Bool` -> true,
`Int` -> nonzero) depending on the compilation unit. The same source
(`hydrate_hits` in `src/query/search_service.xi`) is correct in its own module
(`tests/probes/probe_search_request.xi` green 8/8 fresh builds) but
miscompiles in the big conformance-suite unit (hydration flags read true) and
in a standalone reduction. Deterministic repro + variant matrix:
`docs/repro/xv-trailing-field-vec/` (`probe.xi` exit 1 `BAD detach count`;
`variants.xi` exit 5 -- V5/V7/V10/V11/V12/V14 red, V1-V4/V6/V8 scalar/plain
shapes green, V13 flag-declared-first green in-bundle -- **but the same
reorder in the suite unit produced an access violation 0xC0000005**, so
layout workarounds are context-sensitive in both directions). Lane
mitigation: hydration flags are gated only in the real-module probe; the
suite mirror documents the defect and drops trailing-flag assertions. This is
a silent wrong-metadata defect (a hydrated result can claim a payload it does
not have) -- please triage alongside XVC-C-05/C-06 at the next archive.

**Addendum 5 (2026-10-08, later): XVC-C-09 -- WSL-only segfault on nested-field mutation across modules.**

Found while adding the HNSW id -> position map. At commit `bca8b7f`,
calling `engine_set_index` (module `xiom.vector.engine.core`) -- which
assigns a nested struct field (`eng.graph = hnsw_new(...)`) and then loops
mutating it through another module's function
(`hnsw_insert_ref(&mut eng.graph, ...)`) while reading sibling fields --
**segfaults on WSL 3/3 runs** while the same revision is green on Windows
(probe x2 + 6/6 stress). The identical steps inlined in the probe unit are
green on WSL; the raw-store build loop is green too: context-sensitive
lowering (layout-sensitive, same family as XVC-C-08). Repro (revision-
pinned): `docs/repro/xv-wsl-nested-field/` (probe + README). Workaround
adopted: build the graph in a local variable, assign the field once --
green on Windows + WSL afterwards. Please prioritize the whole
context-sensitive family (C-05/C-06/C-08/C-09); it makes cross-platform
verification unreliable.

**Addendum 6 (2026-10-08, later): XVC-C-10 -- `hnsw_decode` segfaults on large pad volume.**

The new deterministic fuzz probe (payload codec / graph codec / WAL replay
with random + mutated + truncated streams) found a crash inside
`hnsw_decode`: the inline pad step (`while pad < m` pushing zero adjacency
slots) segfaults at `m >= 512` on Windows AND WSL, even on a pristine
stream and with a forced `None` return (so not the struct-return path).
Control experiments are green: 712k standalone `Vec[Int]` pushes, the same
nested pad loop alone, interleaved pushes into two struct Vec fields --
context-sensitive lowering again. Repro (revision-pinned):
`docs/repro/xv-decode-pad-loop/`; general gate
`tests/probes/probe_fuzz_codecs.xi`. Workaround adopted: pad step behind
`pad_adj_slots` + strict-decode bounds (`m <= 512`, `count <= words.len()`);
green on both platforms afterwards. This is the fourth member of the
context-sensitive family (C-05/C-06/C-08/C-09/C-10) -- a single root cause
investigation would unlock a lot for us.

**Addendum 7 (2026-10-09): XVC-C-11 / XVC-C-12 -- unit-context stdlib file-read defects.**

Found while landing the file-backed WAL (`src/durability/wal_file.xi`). Both
are stdlib `io` read paths that behave correctly in a minimal unit and break
in a larger unit -- the context-sensitive family again (the defect is the
per-unit lowering, not the stdlib contracts).

- **XVC-C-11: `io.read_file` content does not survive in some units.** In
  `tests/probes/probe_wal_file.xi`'s unit, `io.read_file(path)` returns `Ok`
  for a file written byte-exactly via `io.write_file_bytes`, but the returned
  Str's content is broken: `slice.str_bytes(s)` = 0 bytes for an
  11-/1771-byte file, and `Str::from_utf8` shows the same class in that unit
  (correct lengths, element content reads back as address-like digits when
  split/printed). Silent wrong data. The same calls are GREEN in the minimal
  control `docs/repro/xv-stdlib-file-read-defects/probe_str_content.xi`.
- **XVC-C-12: `io.read_file_bytes` aborts on files of <= 8 bytes.**
  `contract violated: ensures at 947:12` (the ensures is
  `result is Ok => result.len() >= 0`, which cannot be false for a
  successful read); zero-byte files included; 9+ bytes read fine. Green in
  the minimal control `probe_tiny_read.xi`; aborts in the file-WAL unit --
  a fatal abort for ordinary small-file reads.

Evidence: both controls pass in their own units (re-verified 2026-10-09);
the failing context is the file-WAL probe's unit before the workarounds
(git history around `c84ccbc`); repro bundle
`docs/repro/xv-stdlib-file-read-defects/` (README + both controls + recipe).

Workarounds adopted (green on Windows + WSL, suite + 18 probes x2):
never handle file content as a Str -- read bytes via `read_file_bytes` and
parse byte-wise; guard with `io.file_size` and skip reads shorter than the
shortest valid input (the WAL guard `< 25` is also semantically exact).
Please triage alongside the C-08/C-10 family: one root cause for the
unit-context-sensitive lowering would unlock trustworthy file I/O and let
the lane drop several workarounds at once.

**Addendum 8 (2026-10-09): v0.64.2 re-test -- C-03/C-06/C-07/C-08 confirmed fixed, workarounds reverted.**

v0.64.2 (tag `c51170a6`, installed Windows + WSL) verified end-to-end; every
repro bundle re-run first, then the full batteries. Results:

- **XVC-C-03:** suite compile W004 count **0** (stays fixed).
- **XVC-C-06:** `probe_floatval_roundtrip` green (pinned); suite FloatVal
  payloads green.
- **XVC-C-07:** `Str::from_utf8(&Vec[UInt8])` compiles and returns correctly
  (repro exit 0). The lane **reverted the by-value workaround** in
  `src/payload/payload.xi` and the suite mirror back to the `&` spelling.
- **XVC-C-08:** trailing-scalar repro green (`probe.xi` exit 0,
  "hydration-guard: green"; all 14 `variants.xi` green, was exit 5). The
  suite's hydration mirror test is **restored**: it asserts the trailing
  `has_payload` flags in the large unit again (suite 168 -> 169 checks).
- Extra re-tests beyond the relayed set: **XVC-C-10** -- the inline pad
  shape no longer segfaults at `m=512` (lane keeps `pad_adj_slots` + strict
  bounds; the bounds are strict-decode hygiene); **XVC-C-11/C-12** --
  unguarded `io.read_file` (Str content) and 5-byte `io.read_file_bytes`
  are green in a copy of the original failing unit (lane keeps the byte
  parser + `file_size` guard as defense in depth); **XVC-C-09** -- repro
  green on WSL + Windows (workaround retained; weaker re-test since the
  inline pattern was green before the crash-only-in-engine path).
- Full batteries with the reverted code: suite **169/169 x2** + 18 probes
  x2 on Windows and WSL -- ALL GATES GREEN.

No residual reds from this lane. The C-01/C-02/C-04 workarounds stay as
deliberate choices (public API shape, test-harness style), not compiler
blockers.

**Addendum 9 (2026-10-09): XVC-C-13 (new, OPEN) -- `&Str` parameter types are unknown to the checker.**

Found while landing M-D2 (manifest file): a helper declared with a
`name: &Str` parameter compiled with

```
xiom: warning: unknown type '&Str' -- defaulting to i64. This may produce incorrect code.
```

and took the i64 fallback path -- `slice.str_bytes` then read no bytes, so
every collection name validated as invalid and `manifest_persist` refused
every registry. Minimal repro
`docs/repro/xv-str-ref-param/probe.xi` (`first_byte("A")`, expect 65):
**Windows returns 71, WSL returns 127**, both builds emit the warning and
the probe exits nonzero. No crash observed.

Lane position: every Str parameter in the stdlib and in this lane is
**by value**, so this shape had never been exercised until the manifest
codec; the validator now takes `Str` by value (green: suite 171/171 x2 +
21 probes x2, Windows + WSL). Please make `&Str` a hard type error (or
implement it) at the next archive; the silently wrong value behind a
warning is the hazard.

Re-run recipe:

```powershell
.\scripts\build.ps1 docs\repro\xv-str-ref-param\probe.xi -Name strref
.\out\strref.exe; "exit=$LASTEXITCODE"        # v0.64.2: prints 71, exit 1
```

**Addendum 10 (2026-10-10): XVC-C-14 (new, OPEN) -- two same-named struct types across modules: one layout takes over the other.**

Found in the `xiom.metrics` 0.2.0 adoption. With the package `Counter` and
the xvector core shim's `Counter` both in the program, `VectorEngine`
(module `xiom.vector.engine.core`, importing only the shim) was emitted
with the package `Counter` layout for its `upserts`/`deletes` fields while
`engine_new` still produced shim values:

```
clang ... xiominput.ll:20528:38: error: '%tmp24' defined with type
'%struct.xiom.vector.core.shim.Counter = type { ptr, i64 }'
but expected '%struct.xiom.metrics.Counter = type { i64 }'
```

All XIOM-level checks passed; clang caught it only because the layouts
differ. Minimal repro `docs/repro/xv-counter-type-shadow/` (4 tiny modules
+ `xiom.toml`; run from the bundle dir): `repro.tally` (which imports
`xiom.metrics`) gets the **shim** layout for its `Tally.hits` field while
`metric_counter_new()` returns the package type -- same store mismatch at
`xiominput.ll:850`, Windows + WSL identical (WSL `opt` reports "LLVM IR
verification failed" first and keeps the IR). Tested trigger: two modules
each declare a struct field typed by the same short name resolving to
different same-named types; a single such struct stays green, and the
winning side is program-order dependent. When the two layouts are
compatible this compiles **silently wrong** -- the hazard for any consumer
that defines a type sharing a short name with a consumed package
(`Counter`, `Histogram`, `Registry`, ...).

Lane workaround (adopted): one type name, one type. The engine stat
counters moved onto `xiom.metrics` and the shim `Counter` was retired in
the adoption slice; full batteries green (suite 171/171 x2 + sbom + 34
probes x2 + bench smoke, Windows + WSL). Ask: make struct-field type
resolution strictly module-scoped, or reject duplicate short names across
modules at check time.

Re-run recipe:

```powershell
. .\scripts\dev-env.ps1
Push-Location docs\repro\xv-counter-type-shadow
& $env:XIOM_COMPILER -o $env:TEMP\xv_counter_shadow.exe src\main.xi
Pop-Location        # v0.64.2: clang exit 1 (store mismatch, line 850)
```

Archive status (updated 2026-10-10 evening): **v0.64.3 RELEASED** (run
`38071481303`; tag on `a5b87965`) and installed lane-local on Windows +
WSL by xvector; **C-13 and C-14 re-tested on it: both UNCHANGED** (C-13:
`first_byte("A")` = 71 Win / 127 WSL; C-14: clang store mismatch at
`xiominput.ll:850`, Windows + WSL); verdicts filed on
`release-checks/compiler-compiler-v0.64.3`; items remain open.

**Addendum 11 (2026-10-11): XVC-C-15 (new, OPEN) -- literal stores into
`Vec[Float32]` slots skip numeric narrowing.**

Found while landing the Q-a quantization slice (`probe_quantization`'s
constant-dimension setup). `a[1] = 7.0` on a local `Vec[Float32]` stores
the raw low 32 bits of the f64 constant (**0.0**); `b[1] = 7` stores the
raw integer bits as the f32 pattern (**9.80908925027372e-45**); struct
field stores (`vector.data[1] = 7.0`) corrupt the same way. A Float32
variable, an explicit `... as Float32`, and `push(...)` all convert
correctly; `Vec[Float64]` slots are fine. No warning, no clang error --
silent corruption wherever a float literal is written into a float vector
element (training/encoding paths get garbage values).

Repro: `docs/repro/xv-f32-slot-literal-write/` (6-shape matrix; v0.64.3
Windows exit **3**: shapes A/B/E corrupt, C/F/G controls green;
deterministic across runs).

Lane workaround (adopted): explicit narrow (`c[1] = 7.0 as Float32;`) or
write from a typed variable; one probe setup site was affected and fixed.
Ask: perform the numeric conversion at indexed/field stores the way
`push` does, or reject the implicit literal narrowing at check time.

Re-run recipe:

```powershell
. .\scripts\dev-env.ps1
.\scripts\build.ps1 docs\repro\xv-f32-slot-literal-write\probe.xi -Name repro_f32_slot_literal
.\out\repro_f32_slot_literal.exe   # v0.64.3: exit 3
```

---

**Addendum 12 (2026-10-12): v0.64.4 archive re-verification -- C-15 FIXED;
phantom imports FIXED; C-13/C-14 unchanged; thread gate still red.**

v0.64.4 (tag `df493530`, release run 38256358845, assets sha256-verified)
installed lane-local on Windows + WSL. Results:

- **XVC-C-15 (m271 `f69b542e`): VERIFIED FIXED.** The repro exits 0 on
  Windows + WSL (all six shapes narrow; was exit 3); the lane dropped its
  `as Float32` workaround and `probe_quantization` stays green (23 checks
  x2; the constant-dim assertion is now the unguarded regression line).
- **Phantom imports (m266/m267 `0b1c6374`, item
  `REL-20261010-2124-xvector`): VERIFIED FIXED.** Both controls fail at the
  import with exactly ONE clear `error[T001]: unresolved import '<path>'`
  (exit 1, no binary). The hard error immediately caught stale pre-swap
  imports in this repo (bench harness + repro evidence copies; repaired in
  `390c7a4`) -- exactly the silent-root-cause class the item asked to
  expose.
- **XVC-C-13: still red** (Win `first_byte('A')=167` / WSL `63`; the
  `unknown type '&Str'` warning unchanged). **XVC-C-14: still red** (clang
  store mismatch at `xiominput.ll:850` unchanged, Windows + WSL).
- **Thread gate (`REL-20261011-1627-xvector`): still red** -- the real-spawn
  probe compiles (m263-m265 fixed the marshal half) but still AVs at the
  worker entrypoint (Windows `0xC0000005` / WSL SIGSEGV; last mark
  `M2: spawn returned`); evidence re-filed as `REL-20261012-1402-xvector`.
- Batteries: ALL GATES GREEN both platforms (suite 177/177 x2 + sbom 42
  modules unsafe=0 + 41 probes x2 + bench smoke, Windows; WSL suite 177/177
  x2 + quantization/codec/memory probes x2 + strbytes repro); the 19-probe
  repro sweep is green except the two known reds (`ctrap` exits 1 = fixed
  symptom).

Verdicts filed on `release-checks/compiler-compiler-v0.64.3` (XVECTOR
verdicts block); C-15 and the phantom item are verified + closed on the bus.
