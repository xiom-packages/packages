# Compiler findings from the packages lane

Findings collected while building conformance-tested packages with the
pinned toolchain (v0.61.3 for findings through 2026-09-28; pins v0.62.0
(09-28) and v0.62.1 (09-29) since, and rows carrying a v0.62.x note were
re-checked on that build).
The packages lane cannot fix these; the
compiler session triages. Format: `| Date | Finding | Evidence | Workaround in packages | Impact |`

## v0.64.2 repin matrix (2026-10-09, native lane)

Install: official `xiom-0.64.2-windows-x64.zip`, SHA256 `05d54f4b92480001e5919a9eda213d7c0850808df2555a557ee66c0095c40c4c`
(verified against the published SHA256SUMS); byte-identical `xiom.exe` deployed; `COMPILER_VERSION` bumped;
repin **522 records**; validate **522/0**; guard **506/483/23/0**. The registry/ops lane independently confirmed the
release digests, the m232 home unification + dep-roots-by-default, and a 7/7 probe fleet (C-PULSE-10/13 shapes green).

Matrix on the official install (native, Windows x64):

| Item | Result |
| --- | --- |
| `res_eq` (m239 acceptance) | **exit 0** -- `Ok(Vec)` content equality real |
| `docs/repro/struct-clone` (clone + push) | green (`cloned len=2` / `second=2:two`) |
| `docs/repro/tuple-vec-set` (2 probes) | `bad=0` both |
| `%TEMP%\kilo\retest-listdir.xi` | exit 0 |
| `xiom.kv` probe (`probe_kv_get_str.xi`) | PASS (10/9/10 bytes; C-PULSE-10 shape clean on Windows) |
| `xiom.grpc` suite | **36/36** |
| win32-gl q1 / q2 | green / **exit 0** (GL 4.6.0 NVIDIA 616.92; B-06+B-09 stay fixed) |
| up/down-name probe | `up=1 down=1` |
| c-pulse-09 mini-app (rebuild x2) | `[PASS] wrap-session` both (C-PULSE-09 stays fixed) |
| enum-payload-nd rebuild loop (B-01, m231) | **3/3 `A=B=C=D=true`** |
| m228 (`--run` exit code) | probe returns 5 -> **exit 5** |
| m229 (`is Ok(<literal>)`) | probe **exit 0** (payload compared) |
| m241 (OOB Vec write trap) | **0xC000001D** under `--overflow-checks` |
| io.read_file_lines empty-read (2026-10-09 row) | 6/6 green; clause still logically false -- workaround stays |
| odbc B-10 (scratch copy, `alloc` local restored) | **FAIL** vs control 5/5 -- **still OPEN on v0.64.2** (keep the `f_` prefix) |
| alloc-guard-spin (B-05) | **still spins** (6.9 CPU-s / 8 s, flat 4.5 MB) -- OPEN (runtime side) |

Retired/relaxed for new code after this matrix: the `Result ==` ban for Vec/container payloads (Map/Set `==` stays a
gap), the `is Ok(<literal>)` ban (payload literals are compared again), the B-01 rebuild-flakiness workarounds, and
the B-08 runner workarounds (`port.ps1` printed-exit counting is kept -- harmless and still needed for older pins).
Still open compiler-side: triplicate sibling exports vs alias-qualified calls; Map/Set `==` (per the relay).

## Open findings

| Date | Finding | Evidence | Workaround in packages | Impact |
|---|---|---|---|---|
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **B-09**) | **A large confined `unsafe` block that creates a Win32 window + WGL context poisons the whole binary**: builds exit `-1073740791` (0xC0000409) with no output at all (crash before the first `println`, deterministic 3/3); isolated sub-parts are green (window+`GetDC`+cleanup with the same 12-arg fn-pointer cast runs; folding `ChoosePixelFormat`/`SetPixelFormat`/`wglCreateContext`/`wglMakeCurrent`/string-query into the same function makes every build crash) | runnable repro + control `docs/repro/bindings-pilot/win32-gl-unsafe/` (`probe_q2.xi` crashes 3/3, `probe_q1.xi` control green); full row in `docs/BINDINGS-COMPILER-FINDINGS.md` (B-09), found building the pre-fix `xiom.opengl` pure-XIOM Win32 probe | `xiom.opengl` 0.2.0 moved the probe into the vendored C bridge `src/gl_probe.c` (`--c-source`, no `--link`); the XIOM side is ten one-line `extern` wrappers over safe functions | build-shaped pre-output crash; bounded q1/q2 pair isolates the trigger to the added WGL stage |
| 2026-10-08 (OPEN, v0.64.0; batch #41 probe) | **`Result` equality is unusable in expressions on v0.64.0**: `result == helper(...)` traps at runtime when the payload is a `Vec` (fresh allocations compare unequal) and fails codegen for struct payloads (`icmp eq %struct`) | batch #41 `xiom.tftp` porter probe (2026-10-08), clauses re-expressed as status guard pairs (`helper(...) is Err => result is Err` + the `is Ok` twin) | never compare `Result` values directly; use tag/sentinel guard pairs; SPEC tables note it | silent runtime trap / compile failure on a natural contract shape. **RESOLVED on v0.64.2 (m239; native 2026-10-09): the `res_eq` acceptance probe exits 0 and the struct-clone/tuple-vec-set probes are green -- `Result ==` / `Ok(Vec)` content equality and Vec[Int]/Vec[Str] content equality are real. Map/Set `==` remains the one documented gap; the clause-shape ban is retired for Vec/container payloads.** |
| 2026-10-08 (OPEN, v0.64.0; batch #41 probe) | **`expr is Ok(<literal>)` ignores the literal payload**: it compiles and matches any `Ok` (probe: `tftp_op(data) is Ok(1)` matched an `Ok(2)`-producing input) | batch #41 `xiom.tftp` porter probe (2026-10-08); dispatch clauses re-expressed as `data.len() >= 2 && _u16(data, 0) == N` | destructure or compare the underlying value explicitly; never rely on a payload literal inside an `is` pattern | silent wrong dispatch on legal-looking code. **RESOLVED on v0.64.2 (m229; native 2026-10-09): payload literals are compared again (probe: `Ok(2) is Ok(1)` false, `Ok(1) is Ok(1)` true, Err never Ok; exit 0); the clause-shape ban is retired.** |
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **BIND-ENUM-1**) | **User-enum payload reads miscompile nondeterministically across rebuilds of the same source** -- `SqliteValue` accessors failed in ~50% of rebuilds (11/16 vs 16/16 suite passes; a 4-check micro probe flipped all-false in 1 of 6 builds, i.e. the enum layout itself was wrong in those builds). Same class as the existing `xiom.graphql` enum-payload finding | bindings lane `BINDINGS-SESSION.md` compiler findings (1), 2026-10-08 | tagged struct (`kind` + plain fields) fixed it: 8/8 micro builds, 6/6 suite builds green; re-test the enum model at the next pin | silent wrong values at runtime; workaround is a source-shape change (no diagnostics). **FIXED on v0.64.2 (m231; native 2026-10-09): the bindings enum-payload repro (`docs/repro/bindings-pilot/enum-payload-nd/pkg`) rebuilt 3/3 with `A=true B=true C=true D=true` (previously ~1/3 rebuilds miscompiled); cross-ref B-01 RESOLVED. The enum-rebuild workarounds can be dropped at the next touches.** |
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **BIND-RESOLVER-2**) | **Resolver recursion / compiler stack overflow (exit 0xC00000FD)**: `pub const` references inside confined (`unsafe`) blocks and long const-if chains recurse the resolver in full-catalog builds; cross-module const aliases (`pub const A: Int = other.B`) recurse when referenced | bindings lane `BINDINGS-SESSION.md` compiler findings (2, 3), 2026-10-08 | literals inside `src/ffi.xi` bodies and `error_name`; public consts unchanged; facade consts use literal values | compiler crash on legal-looking const shapes; no workaround for consumers relying on aliases |
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **BIND-ALLOC-3**) | **`xiom.ffi.alloc` inside a confined block + `xiom.ffi.free` spins**: the guard pass rewrites `alloc` to `xiom_guard_alloc` inside the block while `free` stays libc, so the guard heap loops at 100% CPU (flat memory); a hung binary from this lane burned CPU ~21 min (watchdog it) | bindings lane `BINDINGS-SESSION.md` compiler findings (5) + safety note, 2026-10-08 | no malloc/free in confined blocks; C out-params write into an XIOM-owned `Vec[UInt8]` slot; all binding suites run under a memory/time-capped watchdog | hang + resource exhaustion; likely contributor to the 2026-10-08 host restart |
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **BIND-NAME-4**) | **An associated fn whose last path segment is `up` (or `down`) crashes the compiler when `xiom.test` is in the catalog**; **unqualified imports from library modules do not resolve** (`use xiom.sqlite;` then bare `prepare(...)` -> undefined variable; sibling qualification `ffi.prepare(...)` works); `use xiom.ffi;` inside a module named `...ffi` shadows the alias | bindings lane `BINDINGS-SESSION.md` compiler findings (6, 7), 2026-10-08 | methods renamed `migrate_up`/`migrate_down`; always qualify sibling-module calls; avoid the stdlib `xiom.ffi` import in a module whose name ends in `ffi` | compiler crash on a legal method name; silent resolution failures otherwise |
| 2026-10-08 (OPEN, v0.64.0; bindings lane, cross-ref **BIND-EXIT-5**) | **`xiom --run` returned exit 0 for a suite whose program `main` returned 5** (the program exit code is printed on the `exit code:` line but not propagated) | bindings lane `BINDINGS-SESSION.md` compiler findings (8), 2026-10-08 | `port.ps1` counts `[PASS]`/`[FAIL]` markers and parses the printed `exit code:` line, so the runner fails closed | CI false-greens if a runner trusts the compiler exit alone. **RESOLVED on v0.64.2 (m228; native 2026-10-09): `--run` returned the program's exit code (probe `main` returns 5 -> `--run` exit 5); cross-ref B-08 RESOLVED. Keep `port.ps1`'s printed-exit counting -- harmless and still needed for older pins.** |
| 2026-10-08 (OPEN, v0.64.0; cross-ref **C-PULSE-09**) | **Package-aggregate integration crash: a `Vec[SessionStore]` store driven from consumer wrapper modules crashes at runtime (exit -1, no output) while identical calls inline in the consuming module are green** -- found by the PULSE lane adopting `xiom.session` 0.1.0 on the WSL Linux build. Repro pair in the PULSE tree: `tests/probes/probe_adopt_smoke.xi` (crashes at the session step) vs `tests/probes/probe_session_inline.xi` (green, 15 durable steps). Same class suspected as C-PULSE-07 (module-state vs package aggregates) | PULSE `docs/COMPILER-FINDINGS-PULSE.md` delta 2026-10-07; PULSE reverted the session-store swap (local store retained; CSRF still adopted). Packages side is green in isolation: `probe_pkg_session.xi` green, `xiom.session` suites 24/24 x2 on the pin | consumers: keep a package aggregate in the module that owns it (direct calls) until fixed -- do not re-export a store through consumer wrapper modules; PULSE interim: local store retained | blocks `xiom.session` store adoption in wrapped consumers; needs a compiler-lane bisect (Linux + Windows A/B) |
| 2026-10-08 (OPEN, LINUX-TARGET-SPECIFIC; cross-ref **C-PULSE-10**) | **`kv_get` returns an address-like decimal `Str` for every key on the WSL Linux v0.64.0 build; multi-key writes also truncate `kv_get_bytes` (9-byte value read back as 6). Windows v0.64.0 is GREEN for the identical shape** | PULSE consumer repro `E:\xiom-projects\xiom-pulse\docs\repro\kv-get-str-corruption\` (WSL Linux; `kv_get_bytes` + `from_utf8` return the stored text, so records are intact -- the `kv_get` Str reconstruction misbehaves). Packages-lane Windows comparison 2026-10-08: `packages\xiom-kv\tests\probe_kv_get_str.xi` (mirrors the PULSE probe + the multi-key case) fully GREEN on v0.64.0 Windows: `kv_get=abcdefghij`, k2 len 9, re-read after the second write correct, `from_utf8` control correct. `xiom.kv` uses the standard idiom (`kv_get_bytes` -> `match Some(b)` -> `Str::from_utf8(b)`) on both targets | Linux consumers: read through `kv_get_bytes` + `Str::from_utf8` (PULSE workaround); packages: keep `kv_get` as-is (Windows green), add the >=8-byte and multi-key regression cases at the next `xiom.kv` touch | blocks `xiom.kv` adoption on Linux consumers; silent wrong data with no diagnostic; needs a compiler-lane Linux-target bisect |
| 2026-10-08 (OPEN, v0.64.0; cross-ref **C-PULSE-11**) | **A type alias to a package type fails cross-module**: `pub type Store = SessionStore;` in module A is "unknown type 'Store'" in module B, and the build still emits `warning: unknown type 'Store' -- defaulting to i64` and CONTINUES | PULSE session-adoption build log 2026-10-07 (PULSE `docs/COMPILER-FINDINGS-PULSE.md` delta); wrapper-struct workaround used | consumers: do not alias package types across modules -- expose a wrapper struct or use the concrete imported type name; compiler lane: the "defaulting to i64" warning should be a hard error at minimum | silent type-defaulting on a legal-looking alias; corrupt layouts possible wherever a package type is exposed through an alias |
| 2026-10-07 (OPEN, v0.64.0 runtime evaluator) | **Nondeterministic payload-length read on helper-returned `Ok(Vec)`**: a clause `result is Ok => result.value.len() >= N;` on a function whose Ok payload comes from a private helper can alternate pass/fail across runs of the SAME compiled binary | `xiom.spi` batch #37: `spi_encode`'s `result.value.len() >= 5` failed 3/3 ports at 683:12 on the empty transfer; a standalone micro-reproduction of the same shape alternated exit 0/1 run-to-run. Clause dropped; encode's guards re-expressed per-field (mode/size/order) | packages: when a payload-length clause on a helper-returned `Ok(Vec)` is flaky, drop it and re-express the guarantee with per-field guards on the parameters instead | flaky contract evaluations; needs port x2 to surface |
| 2026-10-07 (OPEN, v0.64.0 tooling) | **`xiom-verify` `[OK] VERIFIED` can be vacuous**: when the emitter skips an axiom shape it may still emit `check-sat` under assumptions that quantify over `result` (`forall h i result. i < 0 => result == -1`), which are unsatisfiable -- Z3 then reports `unsat` vacuously. The count of "N proven" clauses is NOT authoritative | `xiom.rpm` batch #37: the four entry-accessor sentinel pairs reported 8 "proven" but were reproduced as vacuous with bundled z3; porter disclaimed them and marked all 61 clauses runtime-checked. Similar shapes were "proven" in earlier batches (maidenhead 5, validation 6, cab 9, bloom 7, miniseed 16, uart 17, ...) and should be treated as unverified against this class | packages: treat `xiom-verify` results as evidence only when the emitted SMT is non-vacuous; prefer marking clauses "runtime-checked" unless a porter demonstrates a real obligation; future porter briefs should not claim Z3-provable from `[OK] VERIFIED` alone | overstated static-provenance claims in SPEC files; no runtime impact |
| 2026-10-07 (OPEN, v0.64.0) | **Contract evaluation binds a shadowing local**: when a function body declares `let <p> = ...` with the SAME name as a parameter its clauses read, the returned-program contract check resolves the name to the (uninitialized on that path) local instead of the parameter -- a clean `contract violated` followed by `0xC0000005` (exit -1073741819) before any output | `xiom.lrc` batch #25: `lrc_parse(text: Str)` had `let text = string.str_slice(...)` inside; its two clauses (`text.len() == 0 => result is Ok` / `result is Err => text.len() > 0`) trapped the suite; renaming the local to `entry_text` made both clauses pass (suite 21/21 x2). No other batch #25 package showed it | packages: never shadow a contracted parameter name with a local in a function carrying clauses (rename the local); porter briefs may add this as a shape rule | silent clause failure / evaluator trap; package-local and mechanical to avoid |
| 2026-10-07 (OPEN; re-confirmed on compiler main m199..m207, v0.64.1 candidate) | **Destructuring a reference to a tuple element yields pointer-like values**: `let (k, v) = &vec[i];` over `Vec[(Str, Str)]` produces `k`/`v` that stringify as decimal addresses and never compare equal to the expected `Str` (`k == &key` false; `compare.str_compare(k, key) == 0` false), so key lookups silently miss. Direct component reads (`vec[i].0 == key`) are correct | `xiom.grpc` finish (2026-10-07): `grpc_metadata_get` returned `None` for a present key and `grpc_metadata_set` appended duplicates instead of overwriting; an in-package diagnostic probe printed `refeq=0`, `cmp=0`, `k=2175265691024`, `v=2175265691024` with `resp.len=1`; with direct reads the suite went **36/36 x2** | packages: read tuple components directly (`vec[i].0` / `vec[i].1`); never destructure a reference to a tuple element. Only `xiom.grpc` used the shape (2 sites, rewritten) | silent lookup failure / duplicated entries; no diagnostic. **Compiler-lane localization (relay 2026-10-07, `5f453b44`/`c3e30175`): `Stmt::Destructure` scalar fallback binds the ptrtoint'd element address to BOTH names; a candidate fix (proper component ref) was reverted because the Eq path derefs only the `&T`-annotated side (`strcmp(pointee(k), key-slot-bytes)`), so `&key` needs symmetric ref-deref first; repro + IR evidence in the lane's bundle for the next session. Compiler main landed the follow-up fix m209 (`ad94b4f1`, 2026-10-07): tuple-ref destructure binds component refs and ref compares deref both sides -- re-test on the next archive. Compiler-lane relay 2026-10-07: at the next pin the never-destructure-a-tuple-ref rule can be dropped; keep it in porter briefs until the official archive re-test passes.** |
| 2026-09-26 | `&mut Int` write-through miscompiles: assignments to a `&mut Int` parameter do not reach the caller | `xiom-upnp/src/upnp.xi` `_version_parts` (fixed): callers kept `-1` after the callee wrote the value; documented independently in `xiom-optimizer` ("the v0.61.3 `&mut Int` calling convention miscompiles simple write-through") | return a plain struct by value (`VersionParts`); `xiom-gbnf` uses `*pos = *pos + 1` deref writes (works there, not in upnp) | silent wrong values; one package already shipped this pattern and needed a rewrite | 
| 2026-09-26 | Loop-carried CSE miscompile: a value derived from a loop variable reuses the first iteration's result | `xiom-amqp/src/amqp.xi:1266` (documented): `ends.push(pos + 4 + sub_len)` returned the first container's end offset in the second iteration, so any two field-tables/arrays in one parent failed `bad table`/`bad array`; found by byte-level bisection | recursive per-container decode function instead of a loop-carried stack | silent wrong offsets; hard to diagnose | 
| 2026-09-25 | Mixed-bracket typos compile silently: `Vec<UInt8>`, `Vec<UInt8]`, `Result<Int]` are accepted | every wave: the file-write tooling reintroduced them (`gif` 16 sites, `mp3`, `flac`, `jpeg`, `sd` 7 sites, `nats` 18 sites, `mongo` 2 authoring waves, `tor` 6 sites, `wireless` 9 test signatures); wave 48/49: `docx` 8 in PARAMETER positions, `pptx` 1, `image` 2, `audio-meta` 6 -- and WIDENED: fully angle-bracket `&Vec<UInt8>` in parameter positions also compiles silently (`video`, 7 sites); wave 51: 14 sites in STRUCT FIELD declarations (`Vec<Int>`/`Vec<Str>` fields) passed the suite green (`cloudlog`) -- the compiler accepts `<...>` in parameter/local/FIELD positions; audit with the byte-level grep only (the Read tool renders `Vec<Int>` as `Vec[Int]`); all caught only by the post-green literal grep | mandatory `Select-String 'Vec<|Result<'` after every write and after green | shape-only; hides real corruption risk |
| 2026-10-02 | A package child module cannot import or call its direct parent module (`module probe.x4.y` + `use probe.x4;` + `hello4()` -> `T001: undefined variable 'hello4'`); sibling and parent->child imports work. Module-qualified FUNCTION calls on the alias are misparsed as method calls (`cannot call 'X' on this expression`); qualified constants work | corroborated by three wave-49 lanes: `helm` (workaround: shared primitives in sibling `xiom.helm.base`), `docker` (minimal probe above; layout moved to sibling `xiom.docker.image`), `vault` (`use xiom.vault as v;` fails identically) | put shared primitives in a SIBLING module; call imported functions unqualified | structural: forces a flat sibling layout; costs a refactor per multi-module package |
| 2026-10-03 | **Child->parent calls re-verified -- the real boundary is `pub` VISIBILITY, not the parent relation.** With `pub fn`, all minimal shapes compile and run on v0.62.2: acyclic child->parent call, cyclic parent<->child (parent imports child + child imports parent), and alias-qualified `use X as p; p.fn()`. Without `pub`, the callee is T001-invisible ("undefined variable") at EVERY module level, including test modules calling package functions. Production corroboration: `xiom.training` re-ran 26/26 PASS 2026-10-03 (children `checkpoint`/`logger`/`schedules` call `pub` parent helpers `_ok_ints`/`_tr_div_round` with no local copies); `xiom.data` (`batch` calls `pub dataset_num_samples`), `xiom.video`, `xiom.serverless` are published green with child->parent `pub` calls | throwaway `xiom.probe-cp` package run+deleted; sources in `docs/repro/child-parent-calls/README.md`. Variant 1 (non-pub) FAILS T001; variants 3 (pub), 4 (cycle+pub), 5 (alias+pub) PASS (`child_call=7` / `alias helper=7`, exit 0) | declare cross-module helpers `pub`; the siblings-only refactor is NOT required for acyclic layouts | removes a per-package refactor rule; wave-49 refactors were most plausibly non-pub visibility reactions (originals not re-checked) |
| 2026-10-02 | Nominal type identity with module qualification: a helper signature `Result[saml.XmlDoc, Str]` does not match a value of type `Result[XmlDoc, Str]` returned by the library (T001 at every call site) | `xiom.saml` (found while building the XML-DSig layer); extended by `xiom.k8s`: annotating a parameter as `selector.LabelParts` yields a distinct type from the canonical `LabelParts` declared in `xiom.k8s.selector` ("expected LabelParts, found selector.LabelParts"); bare `LabelParts` after `use xiom.k8s.selector;` unifies; wave 51 (`xiom.gcp`): qualified STRUCT LITERALS also fail (`storage.GcsPreconditions{...}` -> `unknown type 'storage.GcsPreconditions'` plus the same mismatch) while qualified function calls resolve -- bare imported type names fix it | unqualified type names after `use xiom.saml;` | compile errors only; no silent behavior, but confusing |
| 2026-10-02 | A function whose body ends with a bare `loop { ... }` in which every path returns `X` is still typed as falling through `()` -- `T001` return-type mismatch reported at the body brace | `xiom.terraform` (hit 4 parser/scan loops: `_p_skip_block_comment`, `_p_parse_string`, `_p_skip_string_raw`, `_p_scan_group`) | add an explicit trailing `return <default>;` after the loop | compile errors only; forces an unreachable-looking return |
| 2026-10-02 | Arity is asymmetric: EXTRA arguments are rejected (`T001 ... expects N argument(s)`, `xiom.ml` test code), but MISSING arguments are accepted silently (short calls compile; noted by `xiom.ansible`, `xiom.parser-fw`, `xiom.cfn`, `xiom.chef` all performing manual arity audits) | wave 48/50 reports | manual arity verification at every call site (the trap-14 pass includes it) | silent wrong values if an argument is omitted; **re-verified 2026-10-03: MISSING args now fail `error[T001]` -- row superseded, see resolved table** |
| 2026-10-02 | Spurious negation/comparison diagnostic: `if !bool_call(...) == 1` reports dual T001s ("cannot logically negate type Int" + "cannot compare Bool with Int") for a Bool-returning call | `xiom.phaser` (12/12 occurrences of the single pattern) | rewrite as `bool_call(...) != 1` | compile errors only; confusing message |
| 2026-10-03 | `xiom --emit-ir <file>` OUTSIDE a package context (no `package.xi` ancestor, e.g. a temp-dir probe) fails silently: exit 1, zero stdout/stderr; identical bytes compile green once staged in a package dir | `xiom.xml2` probe workflow | stage probe files inside a package dir | silent failure costs probe time |
| 2026-10-03 | Compiling sources located under `%TEMP%\kilo` can hang the compiler indefinitely (`--emit-ir` and `--run`, no output); identical bytes under the repo tree compile in ~0.6 s | `xiom.rocksdb` probe workflow | keep probes in the repo tree | directory-scanning/module-resolution pathology; needs a repro in a clean dir |
| 2026-10-02 | Match-bound payload mutations on `&mut` enums are silently dropped (no diagnostic): `match obj { Obj(x) => { x.field = ...; } }` leaves the value unchanged | `xiom.json` hardening -- all six mutators were no-ops/corruptors until rebuilt as "construct the replacement payload + `*obj = ...`" | rebuild the payload and assign through the match binding (`*obj = ...`) | silent no-op/wrong state; needs either a diagnostic or a documented rule |
| 2026-10-02 | Deep `clone()` of aggregate payloads returns a corrupt handle: `Vec[T].clone()` / `derive[Clone]` on a type with Object/Array payload; the next `push` crashes `0xC000001D` (scalar payload clones fine) | `xiom.json` hardening -- public `derive[Clone]` on `JsonValue`/`JsonEntry`; worked around with an explicit `json_clone`, derive removed from the public surface | explicit deep-clone functions; never derive Clone on aggregate-payload types | memory-unsafe crash on legal API use. **Widened + re-confirmed on v0.64.0 (2026-10-07): `Vec[Struct].clone()` where the struct is `{ Int; Str }` (no enum payload) aborts `0xC0000005` in an isolated probe (`docs/repro/struct-clone/`; identical operations without the clone exit 0). Packages: never `.clone()` a Vec of structs -- copy element-wise or use an explicit deep-copy function (`xiom.session` `_entries_copy`).** **Re-tested on compiler main m199..m207 (v0.64.1 candidate, 2026-10-07): `probe_struct_clone.xi` STILL aborts `0xC0000005` (control `probe_struct_push.xi` exits 0) -- the batch does not cover `Vec[Struct].clone()`; stays open. Compiler-lane relay 2026-10-07: fix claimed for the NEXT pin -- at that pin the clone-avoidance workaround can be dropped; re-test `probe_struct_clone.xi` at repin FIRST. Compiler main landed m210 (`d7fe6df6`, 2026-10-07): Vec[Struct].clone() keeps the element type -- re-test on the official archive.**
| 2026-10-02 | `xiom-verify` v0.62.2 cannot encode record-field contracts (X7007 `field access on non-datatype receiver`, `unknown constant <T>-<f>`, `xiom_ptr_*` opaque `&T` sorts), if-merge leaves the merge variable unconstrained, X7004 division obligations are path-insensitive, multiple `requires:` clauses emit duplicate `:named` asserts (Z3 abort), and package/cross-module `use` is unresolved; scalar-only contracts DO verify (2/2 and 4/4 proven probes) | `xiom.json`/`xiom.control`/`xiom.sensor` hardening -- 0 of 101 clauses proven; all reported "violations" traced to these encodings (false positives) | merge predicates into single `&&` clauses; document solver-unproven clauses in SPEC; prefer scalar contracts | contract verification is a review aid for record-heavy packages on this pin, not a proof |
| 2026-10-02 | Type laxness beyond brackets: binding a `Str` struct field into a `Vec[UInt8]`-typed local (`let gb: Vec[UInt8] = got.value;`) compiles with zero diagnostics and produces wrong bytes at run time | `xiom.pptx` (found while writing the ZIP reader; the suite went green and a later byte comparison exposed it); wave 51 (`consul`): passing `Result[Bool, Str]` where `Result[Int, Str]` is declared compiled silently and read garbage (caught once test-side) | keep explicit types on every cross-value binding; unit-test byte round-trips; the post-green bracket grep does NOT catch this shape | silent wrong code -- same family as arity/mixed-bracket laxness |
| 2026-10-02 | Stdlib `xiom.crypto.hash._u64_lshr`/`_u64_shr(x, 63)` is wrong when `x` has bit 63 set: it divides by `_pow2(63)` = `Int64_MIN` (negative), so the quotient flips sign and the floor adjustment is skipped (`Int64_MIN` -> 3 instead of 1) | `xiom.web3`: Keccak-256 diverged only for absorbed lanes equal to `0x8000000000000000` (empty/`abc`/`eth` failed; fox/hello/long inputs passed); localized by tracing theta vs a Python oracle to `rotl(C[1], 1)` | special-case `n == 63` in the in-package copy; do not reuse the helper as a general idiom | stdlib-side defect; stdlib callers never shift by 63 (SHA-512/BLAKE2b unaffected) |
| 2026-10-02 | Stdlib `xiom.crypto` / `xiom.crypto.hash` SHA-256 and HMAC SHIP IN SOURCE BUT DO NOT LINK from a package on v0.62.2: `lld-link: undefined symbol: xiom_sha256_hash` | `xiom.aws` (SigV4 needed SHA-256/HMAC; repro `use xiom.crypto; crypto.sha256_hex(&abc)`); `xiom.saml` had already hand-rolled SHA-256 before the source existed | hand-roll SHA-256/HMAC in-package and KAT-pin it (`xiom.aws.base`, `xiom.saml`) | every crypto-adjacent package duplicates crypto; source presence != linkability. **2026-10-05 (v0.63.1): same class as `runtime-link` -- with `XIOM_RUNTIME_DIR` set, both probes link and run (facade prints SHA-256("abc") = `ba7816bf...15ad`, module shape exits 32); the next archive's runtime-discovery fix should link it without the override (sha256_sw.c compiled; sha256_sw.h verified present in the install). Re-test on the next archive, then retire the `aws`/`saml` hand-rolled copies.** **RESOLVED on v0.64.0 (2026-10-05): both probes link and run with no overrides (NIST KAT `ba7816bf...15ad`); `aws`/`saml` retirement moves to the Tier-2 wave.** **Executed (published `eco-v0.1.63`, 2026-10-05, live-verified): `xiom.aws` 0.1.1 and `xiom.saml` 0.1.1 delegate to `xiom.crypto` with all KATs green; the hand-rolled SHA-256/HMAC cores are removed from the fleet.** |
| 2026-10-03 | Module-level const arrays: simple `[N]Int` tables are CORRECT, but **complex initializers mis-materialize** -- a `const NAMES: [3]Str` table reads corrupt strings (`str_len` sums 30 vs 14; `str_compare` fails) and a `const ROWS: [3]Row` struct table reads all fields as zero, deterministically (`bad=5`, 3/3 runs) | `docs/repro/const-tables/probe_const_tables.xi` on v0.62.2: Int `sum=9` correct; Str lens sum 30 vs 14; struct code/name sums 0; runtime controls pass (struct literal `code=9`; `Vec[Str]` lens sum 14). Row 25 follow-up (simple shapes were `bad=0` on 2026-10-02) | keep runtime table builders for Str/struct tables (`merkle`, `l10n-currency`, `l10n-unicode`); Int const tables are usable | silent wrong table data; row 25 not retirable for complex shapes. **FIXED in v0.62.4 (released 2026-10-04): probe `bad=0` -- Int, Str and struct tables all correct; runtime table builders can be dropped at next touch** |
| 2026-10-03 | **Uninitialized local struct + assignment inside a match arm corrupts the value on v0.62.3** (`var x: T;` + `match { Some(v) => { x = v; } }`) -- `Str` fields read as garbage pointers (concat hangs) and `Vec.len()` reads `4294967295` (runaway loops); pre-initializing the local avoids it. Found restoring `xiom.graphql` (`validate_operation`); a second distinct defect remains in that validator (corrupted `Err` payload reads) | in-situ probes: direct `Some(t)` binding, pass-through refs and match-expression `Str` locals all correct (`Query/fields=1`); uninit variant hangs/timeouts; preinit variant reads correctly. Standalone repro `docs/repro/uninit-local/` currently crashes pre-output (`exit -1073741795`) -- minimal repro pending | **always initialize locals at declaration** (`var x: T = <default>;`); never `var x: T;` + later assignment | silent corruption with runaway/hang failure modes; blocks the `graphql`/`rest` restores until isolated. **FIXED and SHIPPED in v0.62.4 (m185 -- real NULL-deref UB); porter-brief rule dropped 2026-10-04** |
| 2026-10-03 | **A test module nested under the package namespace cannot import the package root module on v0.62.3** (`module xiom.pkg.tests` + `use xiom.pkg;` -> every root export is `T001: undefined variable`; 163 errors in `xiom.websocket`); renaming the module to a non-nested name (`websocket_tests`) makes the identical import resolve. Importing *child submodules* from a nested test module works (`xiom.http.tests` imports `xiom.http.types` fine) | A/B in-tree: `xiom-websocket/tests/test_conformance.xi` module line only -- nested: 163 T001s; non-nested: compiles, 10/10 passes. Same nested pattern was present in `xiom.graphql.tests`/`xiom.rest.tests` | name test modules **outside** the package namespace (`pkg_tests`), never `xiom.pkg.tests` | silently blocks package restores; found on `websocket`, `graphql`, `rest`. **FIXED and SHIPPED in v0.62.4 (m184); porter-brief rule dropped 2026-10-04** |
| 2026-10-03 | **`match` arms that use `const` values never match on v0.62.3** -- every arm composed of a named constant falls through to the wildcard, silently returning the default. Found in `xiom.grpc`: `status_to_str` matched 17 `GRPC_STATUS_*` consts and returned `"UNKNOWN"` for every code (0..16) | minimized in `docs/repro/const-match/probe_const_match.xi` (`const TWO: Int = 2`, `match x { TWO => "two", _ => "other" }` -> `two=other`, `bad=1`). Repo-wide scan: 17 const arms total, all in `grpc.xi` | use numeric/string **literals** (or real enum variants) in match arms; `==` comparisons against consts are fine. `grpc.xi` rewritten accordingly | silent wrong results; any future porter matching constants hits it. **FIXED on compiler main (m188), locked with an e2e fixture; restore the const-based arms after the next release pin. RESTORED 2026-10-07 in `grpc.xi` on the v0.64.1 candidate build (suite 36/36 x2); takes effect at the official pin.** |
| 2026-10-04 | **`Vec[(Str, Str)]` read-after-mutation through the library path crashes or hangs (`xiom.grpc`)** -- calling a function that runs `grpc_request_new` + `grpc_metadata_set` and then reads `req.metadata[0].0` crashes `0xC0000005` pre-output (same ops inline hang); removing the read or the call makes it run | minimal subset `packages/xiom-grpc/tests/probe_suite_min.xi` (crash, call-dependent) + `probe_direct.xi` (hang with the `.0` read; passes without it); controls `docs/repro/tuple-vec-set/`; faulting module `ntdll.dll` 0xC0000005 offsets `0x1ff2a`/`0xc4a0f`; reproduces on v0.62.3 **and** local main m184..m187 | until isolated: copy tuple elements to locals before comparing after a library mutation; `xiom.grpc` stays unpublished | blocks the grpc restore; handed to the compiler lane 2026-10-04. **May share the m189 construction path (struct/tuple payload emission); re-test after the m189 build**. **m189 built (`355c69d0`): `probe_suite_min.xi` still crashes `0xC0000005`; `probe_direct.xi` now crashes too (was a hang) -- persists; grpc has no enums/collisions, so the m189 fix does not cover it**. **Re-tested on the released v0.62.4: both probes still crash `0xC0000005` -- fresh finding**. **2026-10-05 relay (compiler lane): strong m192-class candidate -- re-test on the next archive (the repro may run >262k confined entries)**. **Re-tested RED on v0.63.1 (2026-10-05): `probe_suite_min.xi` `0xC0000005`, `probe_direct.xi` hang.** **Re-tested RED on v0.64.0 (2026-10-05): `probe_suite_min.xi` still crashes `0xC0000005`; `probe_direct.xi` now also crashes `0xC0000005` (previously hung). The m192 candidate did NOT clear this shape; grpc stays unpublished.** **Re-tested GREEN on compiler main m199..m207 (v0.64.1 candidate, 2026-10-07; m202 clone-tuple): `probe_suite_min.xi` runs (`start`/`rc=0`, exit 0) and `probe_direct.xi` runs (`start`/`len=1`/`match=ok`, exit 0); the full grpc suite is 36/36 x2 with named-constant arms restored. Publish held for the official archive.** |
| 2026-10-05 (cross-ref **C-PULSE-02**) | **Catalog stage fails for a package whose root module sits outside `src/` when invoked raw from the package dir**: `xiom --run tests\probe_suite_min.xi` inside `packages\xiom-grpc` -> `catalog body [xiom.grpc.types] ... unknown type 'GrpcStatus'` (the type is defined in the package-root `grpc.xi`, reached via `use xiom.grpc;`) on BOTH v0.63.1 and v0.64.0; the same files compile under `port.ps1` and the repo-root `scripts\xiom.ps1` wrapper. PULSE reports the installed-package variant as C-PULSE-02 (module-catalog mapping; `xiom.toml` `source-roots` workaround) | packages-lane runs 2026-10-05 (grpc matrix pre/post candidate): identical catalog error on both pins, wrapper/port compile to the runtime crash | raw `--run` in a package dir: keep modules under `src/` and use explicit item imports; PULSE: list each installed package's `src/` in `xiom.toml` | blocks direct probe invocations and installed-package auto-resolution |
| 2026-10-07 (OPEN, v0.64.0) | **False contract violation: the stdlib `io.xi:943` `ensures` trips in MULTI-MODULE programs** -- `io.read_file_bytes`/`fs_read` abort with an ensures violation when linked with other package modules; the same reads are green in minimal single-module probes | `xiom.kv` build (PULSE wave 3): whole-file reads failed until the module switched to `fs_size` + `fs_read_range` + an exact length check; documented in its SPEC section 6 | packages: on this pin avoid `io.read_file_bytes`/`fs_read` inside multi-module programs; use `fs_read_range` with length checks | blocks stdlib whole-file reads for real programs. **Re-test attempt on compiler main m199..m207 (2026-10-07): a scratch 2-module package (main + helper, both importing `xiom.io`) calling `io.read_file_bytes` reads correctly on BOTH the pinned v0.64.0 and the candidate (`n=3437`, exit 0) -- the original `xiom.kv` shape is not minimized, so the finding could not be reproduced with this probe; stays open pending a faithful repro. **v0.64.2 re-test (native 2026-10-09): the `xiom.kv` probe (whole-file-read shape) is green and the registry lane's fleet probe for the same class is green; no re-fire observed -- keep the `fs_size`/`fs_read_range` workaround until a faithful repro lands.** |
| 2026-10-09 (OPEN, v0.64.1) | **False contract violation: the stdlib `io.read_file_lines` `ensures: result is Ok => result.len() >= 1` (io.xi:1076) trips on a zero-line (empty-file) read** -- fired mid-suite in ONE of two identical official `xiom.wal` port runs (nondeterministic; the other run green); the clause is simply false for an empty file; same false-contract class as the `fs_read` row above | `packages/xiom-wal` extraction: `wal_replay`/`wal_len`/`wal_last_lsn` over empty + missing segments (suite checks "empty file replays to empty", "missing file replays to empty"); workaround adopted in `wal_replay`: `io.read_file` + explicit empty-content early return + `split.str_split` | on this pin, do not use `io.read_file_lines` on possibly-empty files; read the whole file and split lines explicitly | nondeterministic runtime aborts in suites that read empty files; re-test on v0.64.2. **v0.64.2 re-test (native 2026-10-09): 6/6 green runs (a 7th run hung inconclusively while the compiler lane was running a 42-process e2e farm -- not attributable to this clause); the clause is still logically false for a zero-line file, so keep the `wal_replay` workaround and watch for a re-fire.** |
| 2026-10-09 (OPEN, v0.64.2; `xiom.http` 0.1.4 fix pass) | **A function whose whole body is `unsafe { return <cast-expr>; }` miscompiles to null**: `fn make_long_value(v: Int) -> *UInt8 { unsafe { return v as *UInt8; } }` yielded a null pointer instead of the intended value (the porter verified the miscompile directly and used the statement-assignment form), and the whole-body form also needs a `requires` clause to satisfy T007 | `packages/xiom-http/http.xi` `make_long_value` -- the working statement-assignment form: `var p: *UInt8 = ptr_null(); unsafe { p = v as *UInt8; } return p;`; the LONG options are pinned by `tests/probe_bridge.c` (real variadic semantics; a null value fails the probe) | keep casts out of whole-body `unsafe` returns; assign into a typed local inside the block | silent null pointers from a legal-looking function shape; found by the 0.1.4 fix pass |
| 2026-10-09 (OPEN, v0.64.2; false contract) | **`tostring.to_string_char(Char(0))` violates its own `ensures: result.len() >= 1`**: the implementation builds a NUL-terminated buffer (`malloc(blen + 1)` + `xiom.char.encode_utf8`) and the returned Str is C-string-truncated, so `to_string_char(to_char(0))` is `""` and the contract fires; the doc says "single-character UTF-8 string" | probe `%TEMP%\kilo\tstring-char-nul.xi` on the official v0.64.2 install: `contract violated: ensures at 54:12` (tostring.xi), exit 1 | never pass `Char(0)` (callers gate on printable/control bytes -- `xiom.http`'s `byte_to_char` maps 0 explicitly) | runtime contract abort on a valid codepoint; blocks a general Char->Str helper; stdlib fix tracked in `docs/STDLIB-WISHLIST.md` (2026-10-09) |
| 2026-10-09 (OPEN, v0.64.2; bindings lane, consumer-verified end-to-end) | **A registry consumer build does not apply an installed dependency's shipped `port.args.json`**: vendored-C deps (`xiom.sqlite` 0.3.0) resolve via `[dependencies]`, but the consumer must pass `--c-source <installed>\vendor\sqlite3.c` explicitly or the C step never happens (scratch-`XIOM_HOME` test: consumer probe fails without it, passes with it) | `docs/BINDINGS-PACKAGE-WISHLIST.md` section 4 (validated recipe also shipped in `xiom.sqlite`'s README); the lane's repro bundles ride the 2026-10-09 bindings merge | consumers pass `--c-source` per the package README recipe; pure-XIOM packages (`xiom.ffmpeg`) unaffected | vendored-C packages are not drop-in for registry consumers; suggested fix: apply a dependency's `port.args.json` at consumer-build time, or add a `xiom pkg` helper that prints the build args (compiler/pkg lanes) |
| 2026-10-09 (OPEN, v0.64.2; bindings lane, verified in the toolchain source + a live probe) | **No C++ standard flag on the xiom link line: clang 22 defaults to C++14, so vendored C++17 libraries cannot build via `--c-source`** (the staged `xiom.jolt` v5.6.0 vendor generator emits 25 per-directory TUs whose full library compiles under `-std=c++17`) | `crates/xiom/src/lib.rs` (no standard flag passed) + a live probe; the validated generator is staged at `packages/xiom-jolt/tools/combine.py` (no module/tests committed until unblocked) | none for C++17 sources; box2d/imgui (C / C++14-compatible) are unaffected | blocks the staged Jolt generator; request: a `--cxx-standard` passthrough (preferred) or a default bump to `c++17` (compiler lane) |
| 2026-10-04 | **`xiom.l10n-unicode` suite ~2x slower on v0.62.4** -- correctness 24/24 green, but 52.3s (v0.62.3) -> 96-107s manual / 45.6s sweep re-run on identical conditions; the 60s watchdog flagged it TIMEOUT in the fleet sweep. Table-heavy Unicode workload (range/case/decomp tables) | `packages/xiom-l10n-unicode` suite runs on v0.62.4 vs v0.62.3, same machine/load | per-package suite timeout >60s until profiled; no code workaround | perf observation, not a blocker; possibly const-tables materialization or match-codegen cost |
| 2026-10-03 | **Enum payload struct `Str` reads corrupt in `xiom.graphql`'s validator on v0.62.3** -- `GraphQLSelection.Field(selection).name` reads empty/garbage (`|0|`), so a valid operation reports `field_check` failures. In-situ: source struct local reads `hello`; after `operation_add_field` the read-back from `op.selection_set.selections[0]` is `|0|`; constructed+matched in the test module it is empty; `Vec[StructType]` `Str` reads are correct (control) | in-situ instrumentation + controls in `xiom-graphql` tests; **all standalone shapes pass** (single-module, `derive[Clone]`, recursive payload->nested->Vec[enum], `&mut`+push, two-module scratch package) -- see `docs/repro/enum-payload-str/`; minimal repro pending (suspects the 5-field payload with two `Vec` fields + `selection_set` recursion) | until isolated: avoid reading `Str` out of enum payloads in affected shapes (parallel `Vec[Str]`/id scheme) or park; `xiom.graphql` remains WIP 9/10 | silently wrong validation results; blocks the `graphql`/`rest` restores. **Re-run the in-situ case on a build with m184+m185 (next release): both standalone shapes already pass, so this may have been a symptom of the m185 UB**. **RE-RAN 2026-10-04 on a local main build (m184..m187): STILL FAILS -- `validate valid operation` remains corrupt (`|0|`/empty read), so it is NOT an m185 symptom; in-situ evidence stands, minimal repro still pending**. **m189 root cause localized by the compiler lane (2026-10-04, cites this failure): enum struct-payload construction emits invalid IR -- the type registry flattens the payload struct's fields into the enum's field list; fix in flight. Re-test after the m189 build**. **m189 built (`355c69d0`, 2026-10-04): STILL FAILS (9/10) -- graphql has no `type Field`/variant collision, so this is a separate remaining defect**. **Re-tested on the released v0.62.4 (2026-10-04): still 9/10 -- per the compiler lane this is a fresh finding, not m185/m189**. **2026-10-05 relay (compiler lane): C001 `4bf8cf1e` IS in v0.63.1 (ancestor of tag `1b972478`) -- this failure is not explained by C001 and needs a distinct root cause**. **Re-tested RED on v0.63.1 (2026-10-05): still 9/10.** | 
| 2026-10-05 (FIXED in v0.63.1) | Contract runtime evaluator mis-checked two clause shapes on v0.63.0 (spurious `contract violated` at runtime; `xiom-verify` reports the same clauses UNKNOWN, never violated): (a) tuple-component access on a `Result[(Int, Int), Str]` payload -- `ensures: result is Ok => result.value.1 > off` traps at `off == 0` although `next > off` is structurally true; (b) `Result[Vec[UInt8], Str]` payload-length vs parameter-length -- `ensures: result is Ok => result.value.len() <= data.len()` traps on valid frames | varint + cobs hardening 2026-10-05; brute force with `--no-contracts` over all 65,792 frames of length <= 2 prints `bad=0`; clause texts in both SPECs (Contracts sections); uuid's `result.value.len() == 16` (payload vs CONSTANT) checks correctly, so the defect is in dynamic-length/tuple payload expressions | clauses restored on v0.63.1: `result.value.1 > off` in `xiom.varint` (both decoders) and `result.value.len() <= data.len()` in `xiom.cobs`, both x2-green | resolved: the v0.63.1 contract-evaluator fix eliminates the false runtime aborts; no codegen impact |
| 2026-10-05 (OPEN, v0.63.1) | **Contract runtime evaluator RECURSES through postcondition call-cycles and aborts the process with `0xC0000005` (exit `-1073741819`, zero `[PASS]` lines, no diagnostic).** Writing `ensures: !a85_is_valid(text) => result is Err;` on `a85_decode` -- where `a85_is_valid` itself calls `a85_decode` -- killed the suite at startup; removing only that clause restored green | `packages/xiom.ascii85` hardening (batch #14): planned call-guard clause dropped after the crash; the `xiom.iban` porter independently avoided the same cycle (`!iban_is_valid(s) => result is Err` on `iban_parse`); both documented in their SPECs | do NOT write postcondition clauses whose call target transitively calls the callee; the earlier call-condition precedents (crc.xi:151, base58.xi:230) are safe only when the called function does not wrap the function under contract | crash instead of a diagnostic; silently aborts eval builds |
| 2026-10-05 (OPEN, v0.63.1) | **Bare `&mut Int` READS yield the pointer value instead of the pointee** (C-PULSE-04; found by the PULSE consumer lane via registry-installed `xiom.http` 0.1.0: the parser returned `Unexpected end of request line pos=372324169712` on a valid request). IR: `read_bare(p: &mut Int) -> Int { return p; }` emits `ptrtoint i64* %tmp4 to i64; ret i64 %tmp5`, while `return *p;` emits `load i64, i64* %tmp4`. Deref read/write is healthy | PULSE `tests/probes/probe_pkg_http.xi` (installed 0.1.0, sha256 `f8b59d9e...`); packages-lane minimal probe: `read_bare` prints `782904589536` vs `read_deref` `41`; `xiom.http` 0.1.1 fixes the package with explicit deref and its 40/40 parser KATs prove write-through visibility | packages: NEVER read a `&mut` parameter bare -- always `*p` (write-through `*p = ...` was already required) | silently wrong values (addresses) instead of Ints in any consumer reading a `&mut Int` bare |
| 2026-09-26 | No `Vec[Float64]`; no `Int <-> Float64` bitcast in v0.61.3 | `xiom-avro`, `xiom-mkv`, `xiom-amqp` docs; scalar `Float64` works | float/double exposed as raw LE octets; EBML floats decoded as integer milli-units | blocks float-bearing formats from full fidelity (see `docs/STDLIB-WISHLIST.md` `xiom.float`); **re-verified 2026-10-03: `Vec[Float64]` now WORKS (`docs/repro/float-vec`, `bad=0` for push/compare/arith); the bitcast half is still missing -- `xiom.num.float.float_bits`/`bits_to_float` are documented fallback stubs (`ensures: result == 0`), probe prints `float_bits(1.5)=0`; keep raw-octet encodings** | 
| 2026-09-24 | Bit tests on values with the sign bit set are unreliable | `xiom-can`/`xiom-radiotap` notes carried into wave-34/35 briefs; `xiom-sd`/`xiom-eeprom` prefer divisor/modulo extraction | divisor/modulo arithmetic for bit extraction | silent wrong bits | 
| 2026-09-25 | `byte_at(...)` compared to UInt8 constants >= 128 mis-lowers; widening + masking needed | documented trap 3; `png` signature byte 0x89, `jpeg` markers, `ldap` tags 0xA0+ | `(x as Int) & 0xFF` everywhere | silent false compares | 
| 2026-09-25 | `Str` from `Vec[Str]` elements: `==`/`!=` compare pointers; `str_len`/`.len()` unreliable | documented trap 1; test-side slips found in `upnp` t18 | `str_compare` + typed locals | silent wrong compares | 
| 2026-09-22 | `as` is a reserved keyword; `int_to_base` lives in `xiom.convert.int` (not `xiom.convert`); `fn` is also reserved as an identifier (`P001`, wave 51 `xiom.i2p`) | documented trap 17 | import discipline; rename locals | compile errors only | 
| 2026-09-22 | `Int` division truncates toward zero; `(a+b-1)/b` is wrong for negative numerators | documented trap 18 | `q=a/b; r=a%b; if r>0 {q+1} else {q}` | silent wrong ceil | 
| 2026-09-27 | No `Vec[StructType]` (trap 10): struct payload lists need parallel `Vec` fields | `nats` (op stream parsed op-by-op), `i2c` (transaction events modeled as two mirrored `Vec[Int]` arrays) | mirrored parallel Vecs + index discipline | structural noise, drift risk (trap 16) | 
| 2026-09-27 | No auto-borrow at call sites: `&Struct` parameters require an explicit `&op`; omitting it raises E001 moved-value advisories; a read-then-feed-then-read pattern over a `&mut` reader also warns | `nats` tests: 57 E001 "moved value" warnings until helpers took `&NatsOp` and every call site passed `&op`; `tls` ships 7 benign borrow warnings on the reassembly loop; `cassandra` mirrors thrift's `_r_byte_mut` trick to avoid `&` then `&mut` on one reader | explicit `&` at every call site; `_r_byte_mut`-style accessor for mixed borrows | advisory only, but noisy suites; easy to mistake for a real move | 
| 2026-09-27 | Module-level `const` arrays / table initializers mis-materialize | `merkle`: the 64 SHA-256 K constants are rebuilt into a runtime `Vec[Int]` on every hash; `l10n-currency`: the 165-row ISO 4217 table is compiled into comparison chains instead of a module table; **v0.62.2 probe (`xiom.l10n-unicode`, 2026-10-02): simple `[8]Int`/`[64]Int` module-level const arrays with runtime-indexed loop reads, negatives and large values are now CORRECT (`bad=0`) -- the v0.61.3 mis-materialization did not reproduce for these shapes; complex initializers (structs/Str) untested** | rebuild constants at runtime; comparison chains / accessor switches | performance and code size, no correctness impact | 
| 2026-09-27 | No function overloading; a later same-named function silently shadows an earlier definition (no redefinition error) | `l10n-currency`: two `_row` functions (different arities) produced 167 cascading `expected Int, found Str` errors at unrelated call sites until renamed to `_mk_row` | unique function names per module | confusing error storms; possible silent wrong dispatch in other shapes | 
| 2026-09-27 | Bitwise `&`/`^` are unreliable on values with bit 31 or higher set | `bolt`: FNV-1a-64 and freelist/XOR work use an 8-step arithmetic XOR loop; `leveldb`/`proxy` CRC32C loops and `merkle` SHA-256 word ops stay on arithmetic identities | divisor/modulo extraction; arithmetic XOR/AND identities | performance and clarity; any missed conversion is silent wrong data | 
| 2026-09-27 | Omitting the explicit `&mut` at a `Vec` helper call site silently writes to a copy (no diagnostic); also `&result.value` passed into a `&Vec[UInt8]` parameter can read as empty | `bitcoin`: a helper mutating a local `Vec` through a call with no `&mut` compiled clean and did nothing (caught only by tests); `proxy`: `&result.value` binding trap cost one debug cycle | explicit `&mut` at every mutating call site; bind payloads to a local first | silent wrong code -- the most dangerous class of the v0.61.3 issues | 
| 2026-09-27 | Direct comparison of `byte_at(...)` with a `UInt8` constant >= 128 is wrong | `docs/repro/byte-at-128/`: 3 direct-compare failures on `"é"` (C3 A9); untyped/typed local and widen paths correct; **still failing on v0.62.0** (confirmed 2026-09-28, queued) | bind to a typed local, or `(x as Int) & 0xFF` | silent wrong byte classification | 
| 2026-09-27 | Transient compiler crash: empty output, `program_exit=-1`, no diagnostics | `memcached` (first port attempt), `git2` (one intermediate revision), `db2` (coordinator re-run after three green worker runs); **cross-lane corroborated**: the compiler lane sees the same empty-output signature in its e2e (31-32 spurious m35 compiles per run, 0 diagnostics, clean on re-run) -- a real flake class, not machine load | re-run the identical command; all sightings passed unchanged | flaky verification -- must never be recorded as a pass without a re-run | 
| 2026-09-27 | `Vec` capacity cap ~2^24 elements: a single `Vec` aborts past 16,777,216 bytes (16,777,216 OK / +1 crash; two live ~16 MiB vectors also crash) | `mysql` isolated it while designing the >=16 MiB multi-packet test (23:36-23:55 crash window); the live multi-packet round-trip is not executable on v0.61.3 | keep buffers under 16 MiB; document the limit | blocks large-payload live tests (protocols with 16 MiB+ messages) | 
| 2026-09-27 | A local variable named `fn` silently poisons its entire function: errors surface as `undefined variable '<param>'` at parameter reads and `undefined variable '<function>'` at call sites | `l10n-unit` (one local named `fn` produced cascading unrelated errors; renaming fixed the only compile failure) | never name locals after reserved words; add `fn` to the trap list | misleading error storms unrelated to the actual line | 
| 2026-09-27 | `use` is a reserved keyword as a local/field name (forces renames) | `keymgmt` stores the JWK `use` member as `use_val`; `as` is likewise reserved (trap 17) | never name locals/fields `as`, `fn`, `use` | compile errors or forced naming changes | 
| 2026-09-28 | Operator precedence change in v0.62.0: bitwise `&` now binds looser than additive `+` (C conventions); unparenthesized mixes silently change value | `xiom.mssql` t6: `b90 & 0xFF + b91*256 + b92*65536 + b93*16777216` evaluated to `112` (exactly the C parse) where v0.61.3 produced `70000`; fixed by parenthesizing | parenthesize every bitwise/additive mix | silent wrong values in migrated code -- fleet-wide grep found no other occurrence | 
| 2026-09-28 | Stdlib `io.parse_int` fails codegen on v0.62.0: `error[C001]` unresolved `is_empty` (method call on a trimmed `Str`); previously a silent zero auto-stub | `xiom.flags` (only affected package); `is_empty` exists in the stdlib tree (`string.xi`, `array.xi`), so this is a resolution/import bug inside the module | local `flags_parse_int_local` workaround; stdlib lane should fix `io.parse_int` | any package that codegens `io.parse_int` fails to build |
| 2026-10-05 | **AOT native link never sees the production install runtime dir (`<install>\lib\runtime`): `find_runtime_c_files()` (`crates/xiom/src/lib.rs:2111`) candidates cover CWD/walk-up/exe-relative paths but not `xiom.new\lib\runtime`, so the list is EMPTY and the link falls back to `find_runtime_c()` -- the single `xiom_runtime.c`. `async_runtime.c` (and `simd_runtime.c`/`sha256_sw.c`/`xiom_hot_reload.c`) are not linked; any program referencing `xiom_async_now_ms` fails `lld-link: undefined symbol`.** Latent until the v0.63.1 stdlib wave switched `xiom.time.Instant.now()` to the runtime monotonic clock; the stdlib test harness (`xiom/test/harness.xi:116,145,202`, `xiom/test/test.xi:285`) then pulled the symbol into every harness-using suite. The JIT builds the full set (`xiom-jit/src/lib.rs:491-497`), so JIT paths never showed it | Fleet sweep v0.63.1 before the override: `xiom.aws`/`azure`/`cache`/`cancel`/`chaincrypto`/`compliance`/`context`/`countdown`/`curl` FAIL `port: FAIL (passed=0 failed=0 program_exit=1 exit=1)` with `lld-link: error: undefined symbol: xiom_async_now_ms` (`%TEMP%\kilo\sweep-v0631\*.log`); minimal bundle `docs/repro/runtime-link/probe_async_now.xi` (no override = link error; override = `bad=0`, exit 0); the stdlib lane's pin probe `tools/probes/p_pin0631_shapes.xi` fails identically on installed v0.63.1 | `$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"` (checked FIRST at `lib.rs:2113`; globs every `*.c`) -- in-situ `xiom.aws` 27/27 PASS; the fleet sweep was restarted with it set | suites whose closure needs any non-`xiom_runtime.c` runtime symbol fail to link although the stdlib source is present; breaks the v0.63.1 monotonic-Instant wave and any future async-clock user on the released compiler. **RESOLVED on v0.64.0 (2026-10-05): `probe_async_now` prints `bad=0` with `XIOM_RUNTIME_DIR` AND `XIOM_STDLIB` unset (install-layout discriminator); the workaround is retired and the v0.64.0 fleet sweep runs without it.** | 

## Compiler-lane triage and repro status (2026-09-27, second relay)

Compiler-lane triage relayed to packages:
1. `&mut Int` write-through -- accepted compiler-lane candidate (repro-first).
2. Loop-carried CSE -- accepted compiler-lane candidate (repro-first).
3. Mixed-bracket silent acceptance -- known parser-laxness item; bracket-strictness diagnostics planned.
4. Sign-bit bit tests -- repro requested.
5. `byte_at(...)` vs `UInt8 >= 128` -- repro requested.
6. `Vec[Float64]`/bitcast and `Vec[StructType]` -- stdlib/wishlist scale, not quick fixes.

Packages-side repro batteries committed under `docs/repro/` (status after the
**v0.62.0 migration, 2026-09-28**; the repo pin is now `v0.62.0` with
strict clauses on):
- `arity-laxness/` -- **VERIFIED FIXED on v0.62.0**: control green; the
  missing/extra-arg probes fail with `error[T001] ... expects N argument(s)`.
- `mut-int-write-through/` -- **VERIFIED FIXED on v0.62.0 (R53)**: all
  plain-local variants now write through (`bad=0`); explicit `&mut` still
  correct. The former silent-copy behavior is gone.
- `loop-carry-cse/` -- reductions V1/V2/V3 clean on both v0.61.3 and
  v0.62.0; the exact pre-fix amqp loop fragment is included for a targeted
  retry (still a compiler-queue item).
- `sign-bit-ops/` -- clean on both pins (positive bit-31/62, negative and
  wrapped); no reduction yet (family evidence: radiotap/can
  divisor-modulo, bolt's precautionary arithmetic FNV XOR).
- `byte-at-128/` -- **still failing on v0.62.0** (`bad=3`): direct
  `byte_at(...) == 195u8` compares remain wrong; typed locals and the
  `(x as Int) & 0xFF` widen path are correct.

## Resolved / withdrawn

| Date | Finding | Resolution |
|---|---|---|
| 2026-09-26 | "`Vec[Int]` element reads mis-lower to Str compares" | still listed as a trap; no new evidence this session -- keep the typed-local discipline |
| 2026-09-25 | `xiom.gguf` CRC-of-self trap | package-level logic, not compiler (docs/failed_attempts.md) |
| 2026-09-27 | Arity not validated: calls with wrong argument counts compiled (missing args defaulted to 0, extras dropped) | FIXED by the compiler item-3 batch (pin `0c50ac6`, commit `0f3f5083`); **VERIFIED FIXED on v0.62.0** -- `docs/repro/arity-laxness/` control green, missing/extra-arg probes fail with `error[T001]` |
| 2026-09-28 | `&mut` out-params with plain-local calls resolved to a copy (writes lost; struct args corrupted) | **VERIFIED FIXED on v0.62.0 (R53)** -- `docs/repro/mut-int-write-through/` runs all variants correctly (`bad=0`) |
| 2026-10-03 | `&r.value` on `Result[Vec[UInt8], Str]` payloads read an empty vector (v0.61.3 trap 4); generic fn-value / generic-mono ABI family (fn-typed struct field, `[T,U]` callback with `U = Str`, `Vec[U]` maps) | **VERIFIED CLEAN on v0.62.2** -- `docs/repro/struct-field-vec` all 3 probes exit 0 (`probe_result_value` prints `result payload: 3`, was `0`); `docs/repro/generic-fnptr` all 7 probes exit 0 (was compile-fail / corrupted values / exit 23/100 / crash). Local-binding and concrete-callback workarounds are now optional |
| 2026-10-03 | No `Vec[StructType]` (trap 10): struct payload lists needed parallel `Vec` fields | **NOT REPRODUCED on v0.62.2** -- `docs/repro/vec-struct/probe_vec_struct.xi`: push/len/indexed reads (Int + Str fields)/field write through index/loop push with computed values/`&Vec[Row]` params all correct (`bad=0`). Keep existing parallel-Vec sites (no drive-by refactors); retire at the next release sweep |
| 2026-10-03 | Arity asymmetric (2026-10-02 open row): missing args accepted silently | **SUPERSEDED on v0.62.2** -- `docs/repro/arity-laxness/repro_missing_arg.xi` fails `error[T001]: 'add3' expects 3 argument(s), found 2`; the extra-arg probe fails likewise and the exact-arity control is green (`CONTROL OK 3`, exit 0). Free-function calls validate in BOTH directions; the earlier manual-audit guidance was precautionary. Spot-check method/generic call shapes at the next release sweep |
| 2026-10-03 | `Vec[Str].push` on module-level Vecs mis-lowered to a malformed i8 store (`store i8 ... i8*`; clang FAIL on v0.62.2) | **VERIFIED FIXED on v0.62.3** -- `docs/repro/v0622-regressions/vec_str_push_global.xi` and `vec_str_push_param.xi` both exit 0 (`first=alpha`). Workaround row RETIRED in MAINTENANCE |
| 2026-10-03 | `&mut Int` bare assignment (`s = 99`) dropped writes in both call forms (v0.62.2) | **VERIFIED FIXED on v0.62.3** -- `mut_int_write_drop.xi` prints `st=99`; `mut_int_write_drop_matrix.xi` `bad=0` (deref writes were already correct). Workaround row RETIRED in MAINTENANCE |

## Changelog

- 2026-09-27: file created; seeded from the wave-24..35 trap list and this
  session's direct evidence (`&mut Int`, amqp CSE, mixed brackets, sd/gif
  bracket noise).
- 2026-09-27: wave-34 straggler evidence appended (`nats` 18 mixed-bracket
  sites, no-auto-borrow E001 behavior, mirrored parallel-Vec modeling from
  `i2c`).
- 2026-09-27: wave-36 evidence appended (module-level const/table
  mis-materialization from `merkle`/`l10n-currency`; same-name function
  shadowing from `l10n-currency`).
- 2026-09-27: wave-38 evidence appended (bitwise `&`/`^` high-bit
  unreliability from `bolt`; silent copy without explicit `&mut` and the
  `&result.value` empty-read trap from `bitcoin`/`proxy`; `wireless`
  mixed-bracket count).
- 2026-09-27: second compiler relay -- arity row moved to Resolved (pin
  `0c50ac6` / commit `0f3f5083`, local-only); repro batteries added for
  `&mut`-param write-through (**reproduced**), `byte_at >= 128`
  (**reproduced**), loop-carried CSE (not reduced) and sign-bit ops (not
  reduced).
- 2026-09-27: wave-39 evidence appended (transient empty-output crash
  `program_exit=-1` across `memcached`/`git2`/`db2`; `Vec` ~2^24-element
  cap aborting past 16 MiB isolated by `mysql`; `fn`-named local poisoning
  from `l10n-unit`).
- 2026-09-27: wave-40 evidence appended (`use` reserved-keyword rename
  from `keymgmt`; `windows` re-observed the extra-arg drop that the
  compiler item-3 batch fixes; transient `program_exit=-1` re-sighted by
  `monitoring`).
- 2026-09-28: **v0.62.0 migration** -- repo pin raised to `v0.62.0`
  (strict clauses on; toolchain deployed to the resolver's release dir).
  Batteries re-run: arity + R53 verified fixed; byte-at still open;
  CSE/sign-bit still queue items. **Fleet sweep complete: 329/397
  packages pass on v0.62.0; 60 failures are non-publishable
  incubating/declaration-only; 8 verified packages broke and are fixed
  (6 arity restorations, 1 precedence parenthesization, 1 stdlib
  `io.parse_int` workaround), all re-recorded `incubating`.**
- 2026-09-28: **wave-41 evidence** (10 packages: `l10n-date`, `l10n-time`,
  `l10n-address`, `l10n-name`, `locale`, `dimred`, `semaphore`,
  `lockfree`, `hashchain`, `config`; sessions paused mid-wave by a
  runtime event at 22:33Z, resumed 23:08Z). Sessions resolved an
  installed **v0.62.1** (`%LOCALAPPDATA%\xiom.new\bin`) over the v0.62.0
  repo-release -- the resolver prefers an installed copy >= pin; all ten
  suites are green on 0.62.1, most also forced-green on the pinned
  repo-release 0.62.0. Pin bump + targeted re-sweep queued per
  `docs/MAINTENANCE.md`. `hashchain` re-confirmed the stdlib FFI link
  failure (`xiom.crypto.sha256` -> `undefined symbol: xiom_sha256_hash`
  on both 0.62.0 and 0.62.1) and mirrored `merkle`'s private pure-XIOM
  SHA-256. No new compiler miscompiles surfaced in wave 41; the trap list
  is unchanged on v0.62.1.
- 2026-09-29: **pin bump v0.62.0 -> v0.62.1** (compiler release
  `f965bd1c`: numeric parsing + foreign-call safety + tooling fixes;
  stdlib stays `stdlib-v0.62.0`). Batteries re-run on the installed 0.62.1
  build: arity `error[T001]` both directions, R53 `&mut` write-through
  `bad=0`, loop-carry CSE `bad=0`, sign-bit probe exit 0 -- all hold;
  **byte_at direct comparison still `bad=3`** (the compiler's item-10
  "VERIFIED FIXED" covers the explicit `as Int` zext path only; the
  direct `byte_at(x) == UInt8 >= 128` shape stays miscompiled -- battery
  README updated, keep the widen+mask workaround). **Fleet sweep:
  347/407 pass; 60 failures are all declaration-only (0 regressions)**;
  275 fleet records re-pointed to `fleet-sweep:v0.62.1`, worker
  provenance preserved, validate 407/0, guard 392 allowlisted / 0
  failures.
- 2026-09-29 (relay): compiler main `f4af5f64` **fixes the `byte_at`
  >= 128 direct comparison** -- the fix is not in v0.62.1; re-run
  `docs/repro/byte-at-128/probe_byte_at.xi` at the next compiler release
  (expect `bad=0`) and retire the widen+mask workaround from the briefs
  only after that. Compiler backlog order: **row 25 (module-level
  const/table materialization)** is next -- the family behind the
  per-call table rebuilding that `l10n-address`/`l10n-date` documented.
- 2026-09-29: **wave-43 evidence** (10 packages: `cancel`, `stm`,
  `worker`, `messaging`, `plugin`, `countdown`, `diagrams`, `charts`,
  `parsing`, `ast`; the four AM-session packages report no new
  miscompiles). Two new findings:
  - **Builtin shadowing (new, `worker`):** a user free function named
    `size_of` silently resolved to the compiler builtin
    `xiom.core.size_of[T]()` -- it compiled clean and returned the type
    size (8) instead of calling the wrapper. No diagnostic; renamed the
    wrapper. A reserved-builtin lint (or a shadow warning) is the ask.
  - **Library-only `--emit-ir` C001 (`countdown`):** `xiom --emit-ir
    src\countdown.xi` fails with `C001: unresolved 'Vec.clear'/'Vec.push'`
    -- identical on `xiom.timer\src\timer.xi`, so it is a toolchain
    artifact of emit-IR without a test harness, not a package defect;
    the `port.ps1` suite path is authoritative and green.
  - Tooling note (not compiler): the XIOM MCP `xiom_xiom_stdlib_reference`
    call failed with "No stdlib directory found; Set XIOM_STDLIB" in all
    worker sessions (and `xiom_check_xiom_syntax` timed out for some);
    workers fell back to on-disk `E:\xiom-lang\stdlib` + the pinned CLI.
    Worth fixing in the MCP server's stdlib discovery.
  - `sb_push_int` INT_MIN defect and the non-trapping byte-peeker gap were
    routed to `docs/STDLIB-WISHLIST.md` (stdlib side).
- 2026-09-30: **pin bump v0.62.1 -> v0.62.2** (compiler release with the
  byte_at direct-comparison fix from main `f4af5f64`; repo release dir
  `E:\xiom-lang\xiom\target\release` = v0.62.2, deployed into
  `%LOCALAPPDATA%\xiom.new\bin`; repo-local stdlib checkout tracks
  `stdlib-perf1` / `06d0ee7`). **byte_at battery re-run:
  `docs/repro/byte-at-128` is `bad=0`, exit 0 -- FIXED; the widen+mask
  workaround is retired for new code.** `status.ps1 -Action repin`
  aligned 435 records to v0.62.2; the fleet sweep re-run with
  `run_by: fleet-sweep:v0.62.2` follows per `docs/MAINTENANCE.md`.
- 2026-09-30: **v0.62.2 fleet sweep (439 implemented packages) --
  2 real regressions among ready/published packages, 57 known-class
  failures (32 TYPECHECK + 9 DECL-ONLY + 16 FFI/system-lib stubs),
  4 load-flakes re-run green.** The two real ones:
  - **`xiom.expat` silent exit -1 (whole suite).** `xiom --run
    tests\test_conformance.xi` compiles and the binary exits `-1` with
    no output; direct `a.exe` run reproduces. Inserting
    `io.flush_stdout();` after every println in the SAME main makes it
    print and pass **25/25** -- i.e. the code is fine and the failure
    is in the exit/flush path (buffered stdout never flushed; process
    reports exit code -1). Same shape in `xiom.nbt`.
  - **`xiom.nbt` is the same silent -1, plus one genuine check fails
    once flushed: `t5` "strings: u16 length prefix, UTF-8 bytes,
    UTF-8 names" ([FAIL])** -- 25/26. A minimal probe shows
    `Vec[UInt8]` high-byte element compares (`195u8`/`169u8`, typed
    and direct) are all CORRECT on v0.62.2, so the failing sub-check is
    inside nbt's string round-trip (encode/decode + name lookup), not
    basic UInt8 compare.
  - Repro artifacts: `%TEMP%\kilo\sweep-v0622\*.log` (original),
    `%TEMP%\kilo\sweep-v0622-rerun\*.log` (serial),
    `%TEMP%\kilo\expat-inst.log` / `nbt-inst2.log` (flushed variants).
  - Suspects: v0.62.2 codegen changes m163/m164/m165 or the exit path;
    stdlib-perf1 is atomics-only and unlikely. Compiler lane to
    bisect (v0.62.1 still green for both packages in the README batch
    records).
- 2026-09-30: **wave-45 evidence (build on v0.62.2).** `xiom.consensus`
  found a **third v0.62.2 issue: `Vec[Str].push(s)` mis-lowers.** The
  generated IR declares the element as stride 8 but emits an `i8` store;
  clang rejects it (`'%tmp' defined with type 'ptr' but expected 'i8'`).
  `--emit-ir` alone is CLEAN -- the failure only surfaces at the clang
  link/compile stage, so library-only checks miss it. Workaround used:
  a single `Str` plus a parallel `Vec[Int]` of line-start offsets
  (documented in   `xiom.consensus` SPEC 7/11). Repro: build
  `xiom.consensus` without the workaround (the original trace used
  `Vec[Str].push`). The other nine wave-45 packages ported green with no
  new compiler findings (`compliance` added a stdlib one, see the
  wishlist). Filed alongside the `nbt`/`expat` silent-exit regressions.
- 2026-10-01: **wave-46 evidence -- FOURTH v0.62.2 issue: `&mut Int`
  parameters mis-lower (silent wrong results).** `xiom.svm` found it
  empirically: `_svm_shuffle(order: &mut Vec[Int], state: &mut Int)`
  silently dropped mutations to `state` -- every seed produced the same
  shuffle and retraining the same seed produced *different* models
  (state never advanced). `&mut Vec` parameters were already known to
  need explicit call-site `&mut`; `&mut Int` requires the same *and*
  does not propagate writes in this build. Workaround: thread scalar
  state through the return value (`fn shuffle(v: &mut Vec[Int], state:
  Int) -> Int`). No diagnostic; KATs were needed to catch it. Compiler
  lane: this is another silent-miscompile for the v0.62.2 bug batch
  (alongside `Vec[Str].push` stride/i8 and the `nbt`/`expat` silent
  exit -1).
  - **Minimal repro pinned (2026-10-01):** `fn set99(s: &mut Int) { s =
    99; }` + `var st: Int = 10; set99(&mut st);` prints `st=10` on
    v0.62.2 (expected 99), exit 0, no diagnostics;
    `docs/repro/v0622-regressions/mut_int_write_drop.xi`. The
    `let v = byval(s); s = v;` variant also drops the write (`st=10,
    st2=10` vs expected `11, 12`), and `&mut Vec` writes at the same
    call sites are unaffected.
  - **Narrowing (wave 47, `xiom.tensor`/`xiom.autoscale` probes):** the
    defect is **scalar `&mut Int` parameters only** -- `&mut Struct`
    FIELD writes DO propagate correctly at the same call sites
    (verified with throwaway probes in two packages). Design guidance
    meanwhile: thread scalar state through return values; struct
    out-params are safe.
  - **Write-form boundary pinned (2026-10-03, packages lane):** the drop
    is the **bare assignment** through the parameter (`s = 99`) -- it
    drops in BOTH call forms (plain local `set(st)` and explicit
    `set(&mut st)`); **deref writes (`*s = 99`) propagate correctly in
    both call forms**. Probe:
    `docs/repro/v0622-regressions/mut_int_write_drop_matrix.xi`
    (`plain+bare: 10`, `explicit+bare: 10`, `plain+deref: 99`,
    `explicit+deref: 99`, `bad=2`, exit 2). Production confirmation:
    `xiom.gbnf` (`*pos = *pos + 1`, plain call sites) re-ran
    **30/30 PASS on the installed v0.62.2** (2026-10-03). Repo exposure to
    the bare form: `xiom-http/src/parser.xi` (`pos_ref = ...`,
    tests=unknown -- statically exposed, not yet executed); every other
    `&mut Int` hit in the repo is a comment. Tier-2 can narrow the
    workaround from "no `&mut Int` params" to "no bare assignments to
    `&mut Int` params" once the compiler fixes the bare form.
- 2026-10-01: **`Vec[Str].push` trigger isolated -- MODULE-LEVEL global
  `Vec[Str]`.** A local `Vec[Str]` with the same literal pushes compiles
  and runs correctly; a module-level `var v: Vec[Str] = Vec[Str].new();`
  + `v.push("alpha")` fails clang on v0.62.2 with `'%tmp1035' defined
  with type 'ptr' but expected 'i8'` and IR `store i8 %tmp1035, i8*
  %tmp1034` (element stride 8; only the stored value type is wrong).
  Repro bundle: `docs/repro/v0622-regressions/` (`vec_str_push_global.xi`
  minimal, `vec_str_push_param.xi` consensus shape; README also covers
  the expat/nbt silent-exit repro and the registry artifact download
  endpoints). Relayed to the compiler lane 2026-10-01.
- 2026-10-02: **wave-48 evidence (10 packages on v0.62.2: `climate`,
  `nuclear`, `training`, `web3`, `l10n-unicode`, `docx`, `pptx`, `xlsx`,
  `image`, `data`; 6 `task` + 4 AM lanes, all double-verified).**
  - **Type laxness beyond brackets (new, `pptx`):** `let gb: Vec[UInt8] =
    got.value;` with `got.value: Str` compiled clean and produced wrong
    bytes at run time -- a silent-wrong-code shape the bracket grep
    cannot catch. Row added to Open findings.
  - **Stdlib `_u64_lshr` n=63 defect (new, `web3`):** see the Open
    findings row; Keccak-256 required an in-package `n == 63` special
    case. Routed to the wishlist as well.
  - **Const/table materialization probe (`l10n-unicode`):** simple
    module-level `[8]Int`/`[64]Int` const arrays with loop-indexed reads
    are CORRECT on v0.62.2 (`bad=0`); row 25 annotated, complex shapes
    still to test.
  - **Trap 14 re-offended silently three times:** `docx` emitted 8
    mixed-bracket `Vec<UInt8>,` signatures in PARAMETER positions and
    went green; `image` 2 (`_img_is_tga`/`_img_jpeg_scan`); `pptx` 1
    (`let rb: Vec<UInt8] = rr.value;`). All caught only by the mandatory
    post-green `Vec<`/`Result<` grep and fixed.
  - **Positive confirmations on v0.62.2:** concrete multi-arg fn-pointer
    callbacks (`fn(&Int,&Int)->Int` named callbacks, `training`);
    intra-package submodule imports + `src\<last-segment>.xi` resolution
    and cross-module pub types (`training`, `data`, `web3`); `&mut
    Struct` Vec-field pushes persist; `UInt32 -> Int` via `as`
    zero-extends (CRC KAT `crc32("123456789") = 3421780262`); 4-byte
    UTF-8 and `sb_to_str` with control bytes round-trip.
  - **Tooling notes:** the XIOM MCP stdlib lookup still fails without
    `XIOM_STDLIB` (workers fall back to `E:\xiom-lang\stdlib`);
    `xiom_compile_and_analyze` compiles the whole workspace and reports
    unrelated pre-existing broken packages, so per-file `--emit-ir` /
    `port.ps1` remain authoritative. `namespace-check.ps1` counts any
    `.xi` under the package tree as a module (a scratch probe file
    inflated the count once).
  - Deflate/ZIP porting note: block headers and length/distance extra bits
    are LSB-first while Huffman codes are MSB-first; one shared
    accumulator silently mis-inflates.
- 2026-10-02: **expat/nbt silent `-1` ROOT-CAUSED to the sweep harness --
  withdrawn as a compiler issue.** The compiler lane could not reproduce
  (deployed v0.62.2, both stdlib checkouts); the packages lane re-ran both
  on the same machine and they are green (`expat` 25/25 in 20.0 s, `nbt`
  26/26 in 21.3 s incl. t5). Cause: `fleet-sweep.ps1` ran 4 chunks in
  parallel and every chunk executed `Get-Process a | Stop-Process -Force`
  after each package, killing other chunks' in-flight `a.exe`; the driver
  then reports `exit code: -1` and the child's buffered stdout is lost. The
  `-1` in the sweep logs is the driver's line (a green run prints
  `exit code: 0` there); the sweep-time port.ps1 (`f1d34ff6`) already
  printed `TIMEOUT after ...` on a watchdog hit and none of the four logs
  contains it. The "flushed variant" passing is explained by running
  serially. Details: `docs/repro/v0622-regressions/HARNESS-NOTES.md`
  (UPDATE section). nbt t5 is green now; watch only.
- 2026-10-02: **wave-49 evidence (10 packages on v0.62.2: `deep`, `ml`,
  `saml`, `helm`, `audio-meta`, `docker`, `inference`, `serverless`,
  `video`, `vault`; 6 task + 4 AM lanes, all double-verified; two task
  lanes first aborted silently and passed on a `variant: low` files-first
  retry).** New findings:
  - **Child module importing its direct parent (T001)** -- minimal repro
    and cross-lane corroboration; Open findings row added. Also
    module-qualified FUNCTION calls misparse as method calls; qualified
    constants work.
  - **Nominal type identity with module qualification** (`saml`):
    `Result[saml.XmlDoc, Str]` != `Result[XmlDoc, Str]`; Open findings row
    added.
  - **Trap-14 family widened:** fully angle-bracket `&Vec<UInt8>` in
    parameter positions compiles silently (`video`, 7 sites post-green);
    mixed brackets recurred in `docx` (8), `audio-meta` (6), `image` (2),
    `pptx` (1).
  - **Arity enforcement re-confirmed firing** (`ml` test code rejected a
    3-arg call with `T001 ... expects N argument(s)`), consistent with the
    v0.62.0 fix.
  - **`--emit-ir` cannot resolve package-sibling modules** (`video`:
    `store.xi` alone reports `VideoStream`/constants undefined; `data`
    `batch.xi` reproduces) -- `port.ps1 -NoRun` is not a valid gate for
    multi-module packages; the `--run` graph resolves imports fine.
  - `var b = a; b[i] = ...` mutates `a`'s buffer (Vec handle aliasing
    reconfirmed, `video`).
  - MCP notes: `xiom_compile_and_analyze` lacks `XIOM_STDLIB` (all stdlib
    symbols reported undefined) and compiles modules standalone without
    package context; `port.ps1` remains authoritative.
  - Positive: `&mut Struct` params + nested `&mut` forwarding work;
    cross-module direct field access on `pub type`s works; intra-package
    `use` resolves via the manifest `modules:` list; local `Vec[Str]`
    pushes inside struct fields work.
- 2026-10-02: **wave-50 evidence (10 packages on v0.62.2: `translate`,
  `parser-fw`, `jit-fw`, `terraform`, `k8s`, `cfn`, `ansible`, `chef`,
  `elastic`, `aws`; 6 task + 4 AM lanes, all double-verified; `elastic`
  hit its output limit with ZERO files, was stopped and re-dispatched as
  a `variant: low` files-first task, green on retry).** New findings:
  - **Bare `loop` return typing** (`terraform`) -- Open row added.
  - **Arity asymmetry** (missing args accepted, extra rejected;
    `ml` vs `ansible`/`parser-fw`/`cfn`/`chef`) -- Open row added.
  - **Module-qualified type names across modules unreliable** (`k8s`
    extends the `saml` row; `selector.LabelParts` != bare `LabelParts`);
    bare names after `use` unify.
  - **Stdlib crypto link failure** (`lld-link: undefined symbol:
    xiom_sha256_hash` from package context) -- Open row added;
    `xiom.crypto`/`xiom.crypto.hash` source presence is not linkability.
  - Tooling: MCP compile/analyze + stdlib reference fail without
    `XIOM_STDLIB` (repeated, environmental); `xiom_compile_and_fix`
    timed out once; `scripts/xiom.ps1 --run` positional args do not bind
    under PowerShell 5.1 (`-Stdlib` swallows `--run`); direct compiler
    invocation emits `W001` duplicate-module warnings from shadowing
    stdlib worktrees plus a stale `%TEMP%\kilo\stdlib-rel` copy
    (harmless; `port.ps1` unaffected).
  - **No mixed/full-angle bracket recurrences in wave 50** -- the
    post-write + post-green literal grep held across all ten packages.
  - Positives: `Vec[Str]` struct fields + local push + indexed writes +
    `&mut` element replacement; `&mut T` -> `&` coercion; nested struct
    literals; single-`&mut`-struct field mutation; multi-vector
    pop-to-truncate; field-indexed writes; `Result[Str, Int]` leaves.
- 2026-10-02: **wave-51 evidence (8 packages on v0.62.2: `puppet`,
  `azure`, `gcp`, `salt`, `cloudlog`, `consul`, `i2p`, `phaser`; 5 task
  + 3 AM lanes, all double-verified).** New findings:
  - **Qualified struct literals fail T001** (`gcp`) -- nominal-identity
    row extended; bare imported type names required.
  - **Trap-14 recurrence in STRUCT FIELD positions** (`cloudlog`, 14
    sites) -- compiled silently and passed the suite green; the
    compiler accepts `<...>` in parameter/local/FIELD positions. Audit
    with the byte-level grep only: the Read tool renders on-disk
    `Vec<Int>` as `Vec[Int]`.
  - **Type laxness:** `Result[Bool, Str]` passed where
    `Result[Int, Str]` is declared compiled silently and read garbage
    (`consul`, caught test-side).
  - **`fn` is reserved as an identifier** (`P001`) in addition to `as`
    (`i2p`).
  - **Spurious negation/comparison diagnostic** (`phaser`):
    `if !bool_call(...) == 1` reports dual T001s including a bogus
    "cannot logically negate type Int".
  - One non-reproducible `--run` `program_exit=-1` with no captured
    output (`i2p`) while the compiled `a.exe` ran correctly; the machine
    was saturated by the compiler repo's e2e batch (`salt` also saw
    compile times inflate). Watch only -- do not re-file unless it
    reproduces with preserved `%TEMP%\xiom-run-*.out/.err`.
  - Positives: 9 sibling modules in one package compile cleanly
    (`azure`); struct-field `Vec[Str].push` (35 sites) and indexed
    `Vec[Str]` writes stable (`consul`); base64/base32 hand-rolled and
    KAT-pinned pending the crypto/base64 link fix (`i2p`; see
    `docs/repro/crypto-link/`).
- 2026-10-02: **wave-52 promotion-prep evidence (`json`, `control`,
  `sensor` hardening; contracts mandatory for stable per
  `docs/PROMOTION.md`).** New silent/unsafe findings (Open rows added,
  commit `25cf8c62`):
  - **Match-bound payload mutations on `&mut` enums are silently
    dropped** (`json`: all six mutators no-ops until rebuilt as payload
    replacement + `*obj = ...`).
  - **Aggregate-payload `derive[Clone]` corruption:** deep clone of
    Object/Array payloads returns a corrupt handle; next `push` crashes
    `0xC000001D` (scalar payloads fine). Public derive removed from the
    container-backed types; `json_clone` is the supported deep copy.
  - **`invariant:` placement ambiguity:** `json` hit P001 in every
    documented placement while `control` generated `invariant_check`
    functions -- canonical placement ruling needed.
  - **`xiom-verify` v0.62.2 encoding gaps (0/101 clauses proven across
    the three packages; false-positive "violations"):** record-field
    selectors emit `unknown constant <T>-<f>`; `&T` becomes opaque
    `xiom_ptr_*`; if-merge leaves the merge variable unconstrained;
    X7004 division obligations are path-insensitive; multiple
    `requires:` emit duplicate `:named` asserts (Z3 abort, merge with
    `&&`); cross-module `use` unresolved; writes
    `xiom_verify_output.smt2` into cwd. Scalar-only probes verify
    (2/2, 4/4 proven) -- encoding work, not solver availability.
  - Hardening also fixed real legacy defects in `json` (`0.05` parsed as
    `0.5`; `stringify_frac` recursion; exponent hang; partial-write
    `set_path`; non-atomic merge) -- the promotion gate catching exactly
    what it is for.
- 2026-10-03: **wave-54/55 evidence + HARNESS ROOT CAUSE.** The wave's
  cross-lane flake storm (silent empty-output + `program_exit=-1` on
  first runs, retry-green) was root-caused to **`scripts/port.ps1`'s
  watchdog cleanup**: on timeout it ran a global
  `Get-Process a | Stop-Process -Force`, killing OTHER concurrently
  running lanes' in-flight suites. Fixed (`07301ee6`): PID-tree kill of
  the run's own process only, plus per-run `a.exe`/`a.exe.ll` cleanup;
  the flake vanished in subsequent verifications. `xiom.curl` observed
  the same signature under overlapping invocations -- consistent.
  - Category harmonization: 34 published packages had unknown category
    tokens (registry shows `categories: []`); all mapped to the 16-token
    vocabulary (`docs/MAINTENANCE.md`).
  - Legacy bracket repair: repo-wide byte-level scan found **24
    packages / 94 real sites** (`Vec<`/`Result<`/`Option<`/`&Vec<`) --
    all canonicalized. Note: the naive `>]` probe false-positives on
    XML/DOCTYPE strings; scan with the four prefix forms only. Read
    renders `Vec<Int>` as `Vec[Int]` -- byte-level grep mandatory.
    `assimp`/`dxc` source-fixed but remain untestable (FFI bridge /
    pre-existing test wiring).
  - New silent-failure rows added above (`--emit-ir` outside a package;
    `%TEMP%\kilo` hang). `fn` reserved confirmed again; mixed-bracket
    field/local positions still compile silently.
  - No new miscompile findings from the 27 repaired packages; all
    bracket edits preserved behavior (counts unchanged, port x2 green).



## v0.64.1 official battery (2026-10-08, native lane; pin 53c1fbac->4e12f80a)

Install SHA256-verified byte-identical to the release archive; probes re-run
through the repo wrapper / raw compiler with hard watchdogs.

FIXED on v0.64.1 (workaround retirements):
- `Vec[(Str, Str)]` read-after-mutation crash/hang (`xiom.grpc`): `probe_suite_min`
  rc=0 (`start`), `probe_direct` len=1/match=ok; tuple-vec-set probes `bad=0`.
  `xiom.grpc` restored named-constant arms and shipped 0.1.0 (36/36 x2).
- Named-constant `match` arms (m188): covered by the same grpc restoration.
- Win32/WGL confined mega-block (B-09): `probe_q2` prints `q2-start` + GL
  `4.6.0 NVIDIA 616.92`, exit 0 (was a pre-output 0xC0000409); B-06 also fixed
  per the bindings-lane sweep.
- Session store behind consumer wrapper modules (C-PULSE-09): minimized app
  builds and prints `[PASS] wrap-session`, exit 0 (was a silent crash); PULSE
  should re-run its full suite on the repin.
- `up`/`down` associated-fn name crash: probe prints `up=1 down=1` (the
  unqualified-import and ffi-alias-shadowing parts remain open).
- Multi-module `io` list-dir false ensures (m211): `retest-listdir.xi` green.
- Struct-clone props (`probe_struct_clone`/`probe_struct_push` green): the
  `Vec[Struct].clone()` avoidance is retired; aggregate-payload deep clone
  (`json_clone` guidance) still stands.

STILL OPEN on v0.64.1 (evidence re-run):
- `Result` equality: no longer traps, but two equal `Ok(Vec[UInt8])` pairs
  compare FALSE quietly (fresh allocations) -- keep tag guard pairs.
- `is Ok(<literal>)` still ignores the payload literal (`pick(2) is Ok(1)` true).
- Ref-destructure `let (k, v) = &vec[i]` (row 2026-10-07): no positive probe;
  `xiom.grpc` sources keep the direct-component-read discipline -- RULE STAYS.
- C-PULSE-10 Linux `kv_get` (Windows path PASS in-package probe); C-PULSE-11
  type-alias defaulting; dep-roots dotted keys (WSL re-test pending): PULSE /
  compiler lanes.
- `io.xi:943` multi-module re-test: clean (`n=3437`, no false violation).

## v0.64.1 consumer sweep (2026-10-08 evening)

- **C-PULSE-10 -- CLOSED on Linux v0.64.1** (fixed by m217, per PULSE): kv-mode smoke
  73/73 + 20m store soak green (756 writes/0 fail, counts stable across compact/reopen).
  Windows was already green (`packages\xiom-kv\tests\probe_kv_get_str.xi`). No further
  action; keep the >=8-byte + multi-key regression cases as a next-touch item.
- **C-PULSE-13 (NEW, OPEN; compiler/installer, Unix-only):** `xiom pkg` installs to
  `$HOME/xiom/packages` while the compiler's `xiom_home()` resolves the canonical
  `~/.local/share/xiom` (CRB-3c first-existing-candidate) -> dependency roots resolve
  zero; `xiom doctor` reports "No packages". Windows agrees on `%LOCALAPPDATA%\xiom`.
  Evidence: PULSE Linux sweep (install output + doctor + m212 dep-roots gate red/repair
  logs). Ask: unify the resolver (prefer `xiom_graph::paths::xiom_home().join("packages")`
  for installs), or add a "candidate containing packages/" tiebreak, or create/point
  `$XIOM_HOME/packages` in the Unix installer; regression = `xiom doctor` on a fresh
  Unix install.
- **v0.64.1 enforces extern-unsafe confinement in catalog bodies -- published `xiom.http`
  0.1.1 violates it** (67 T001s: extern calls without `unsafe`, and safe fns returning
  `*UInt8`; any project with `xiom-http-0.1.1/src` on the catalog path fails). PULSE
  pruned the package; compat republish in flight (unsafe-wrapped internals -> 0.1.2).
  **Fleet sweep (static, 2026-10-08):** 44 packages carry `extern "C"` outside tests;
  published FFI set -- `http` rawptr_returns=8/unsafe_refs=0 (red), `rest` 8/7,
  `grpc` 0/2, `protobuf` 0/1, `sqlite` 5/26, `opengl` 6/33, `vulkan` 3/21.
  **Catalog-dep rehearsal sweep (consumer harness, 2026-10-08 evening):** `rest`,
  `protobuf`, `sqlite`, `opengl`, `vulkan` are **COMPILE-CLEAN** as catalog deps (0
  errors with an import-only consumer on v0.64.1); **`grpc` FIXED in 0.1.1** -- the 6 T001
  "ambiguous function exported by multiple imported modules" came from grpc.xi's raw extern
  declarations colliding with the thin submodule wrappers (`src/client|server.xi`); the fix
  renames the wrappers (`srv_*`/`cli_*`) and keeps every raw extern name (linker symbols
  unchanged -- a first pass that renamed the externs was rejected: v0.64.1 has no
  `link_name`/alias and it would have broken real libgrpc linkage). Acceptance rerun:
  consumer harness 0 T001, port 36/36 x2 (`82fac130`). Harness caveat: source-roots should list each module dir once;
  http's root-located module needs the package root, not `src/`.

## v0.64.1 extern-unsafe enforcement -- follow-ups (2026-10-08, xiom.http compat pass)

- **`xiom.http` 0.1.2 is the fix** (`548e31b9`): 64 extern call sites wrapped in
  `unsafe { }`; the 3 raw-pointer-returning helpers became **unsafe-internal** (safe
  signature kept, unsafe body); 10 discard shapes reshaped. Consumer rehearsal (scratch
  project, `source-roots` -> package): pre-fix **67 T001** (64 extern + 3 raw-ptr) ->
  post-fix compiles and runs exit 0; package suite 40/40 x2; PULSE `probe_pkg_http`
  should flip green on the republish.
- **NEW finding: `unsafe fn` is a hard `P001` parse error on v0.64.1.** The T003 message
  points at the right shape ("only unsafe-internal helpers may return pointers"): keep
  the function safe and put the `unsafe { }` in its body. Sibling FFI packages must not
  reach for `unsafe fn`.
- **NEW finding: `let _ = unsafe { call() };` emits invalid IR** for pointer/Str/struct
  returns in project builds (`trunc i64 -> i32` then `ret i8*`; clang: "defined with type
  'i32' but expected 'ptr'"). Shape fix: `unsafe { let _ = call(); }` (behavior-identical).
- **`xiom.http` defects RESOLVED (0.1.3 + 0.1.4 fix passes):** 0.1.3 removed the
  `setup_common_options` `p1` double-free and the `http_download` remove-after-free UAF.
  **0.1.4 (native, 2026-10-09, commit `6649cb7f`) fixed `char_to_str`/`byte_to_char`
  (printable ASCII now renders as the actual character via `tostring.to_string_char`;
  clauses 38 -> 37; suite 40 -> 42 checks) and `make_long_value` (variadic LONG options
  now pass the value, not a heap pointer; the probe bridge is faithful to libcurl's ABI).
  Proof: port 42/42 x2 + root probe x2, plus real libcurl 8.22.0 present-path --
  GET `https://example.com/` status 200, POST echo captured `CL=5;READ=5;BODY=hello`
  (pre-fix POSTFIELDSIZE would be address-sized). Flag for the next touch:
  `src/client.xi` + `src/demo.xi` carry pre-existing `Result[HttpResponse, Str]` vs
  `Result[HttpClientResponse, Str]` T001 drift (dead modules, no suite closure includes
  them). Consumer-layout caveat: the module lives at the package root (`http.xi`), not
  `src/`, so catalog rehearsals need a root-module path or an identical `src/` copy.

## Bindings B-10 (2026-10-08/09): alloc-named local fn-pointer silently redirected

- **A local fn-pointer variable named `alloc` inside a confined block has its calls
  silently rewritten to the guard allocator.** ODBC's `SQLAllocHandle` call through a
  loaded fn-pointer named `alloc` "succeeded" while the out-param stayed 0 (the guard
  allocator was called instead of the real symbol); renaming the local to `f_alloc` fixed
  the entire probe. The guard pass should exclude non-builtin locals from the `alloc`
  rewrite. Evidence: bindings batch 15 (`packages/xiom-odbc`, 5/5 x2 after the rename),
  full row in `docs/BINDINGS-COMPILER-FINDINGS.md`; workaround `f_` prefix on fn-pointer
  locals applies to every loader-style binding.
