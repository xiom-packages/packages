# Compiler findings from the packages lane

Findings collected while building conformance-tested packages with the
pinned toolchain (v0.61.3 for findings through 2026-09-28; pins v0.62.0
(09-28) and v0.62.1 (09-29) since, and rows carrying a v0.62.x note were
re-checked on that build).
The packages lane cannot fix these; the
compiler session triages. Format: `| Date | Finding | Evidence | Workaround in packages | Impact |`

## Open findings

| Date | Finding | Evidence | Workaround in packages | Impact |
|---|---|---|---|---|
| 2026-09-26 | `&mut Int` write-through miscompiles: assignments to a `&mut Int` parameter do not reach the caller | `xiom-upnp/src/upnp.xi` `_version_parts` (fixed): callers kept `-1` after the callee wrote the value; documented independently in `xiom-optimizer` ("the v0.61.3 `&mut Int` calling convention miscompiles simple write-through") | return a plain struct by value (`VersionParts`); `xiom-gbnf` uses `*pos = *pos + 1` deref writes (works there, not in upnp) | silent wrong values; one package already shipped this pattern and needed a rewrite | 
| 2026-09-26 | Loop-carried CSE miscompile: a value derived from a loop variable reuses the first iteration's result | `xiom-amqp/src/amqp.xi:1266` (documented): `ends.push(pos + 4 + sub_len)` returned the first container's end offset in the second iteration, so any two field-tables/arrays in one parent failed `bad table`/`bad array`; found by byte-level bisection | recursive per-container decode function instead of a loop-carried stack | silent wrong offsets; hard to diagnose | 
| 2026-09-25 | Mixed-bracket typos compile silently: `Vec<UInt8>`, `Vec<UInt8]`, `Result<Int]` are accepted | every wave: the file-write tooling reintroduced them (`gif` 16 sites, `mp3`, `flac`, `jpeg`, `sd` 7 sites, `nats` 18 sites, `mongo` 2 authoring waves, `tor` 6 sites, `wireless` 9 test signatures) | mandatory `Select-String 'Vec<|Result<'` after every write and after green | shape-only; hides real corruption risk | 
| 2026-09-26 | No `Vec[Float64]`; no `Int <-> Float64` bitcast in v0.61.3 | `xiom-avro`, `xiom-mkv`, `xiom-amqp` docs; scalar `Float64` works | float/double exposed as raw LE octets; EBML floats decoded as integer milli-units | blocks float-bearing formats from full fidelity (see `docs/STDLIB-WISHLIST.md` `xiom.float`) | 
| 2026-09-24 | Bit tests on values with the sign bit set are unreliable | `xiom-can`/`xiom-radiotap` notes carried into wave-34/35 briefs; `xiom-sd`/`xiom-eeprom` prefer divisor/modulo extraction | divisor/modulo arithmetic for bit extraction | silent wrong bits | 
| 2026-09-25 | `byte_at(...)` compared to UInt8 constants >= 128 mis-lowers; widening + masking needed | documented trap 3; `png` signature byte 0x89, `jpeg` markers, `ldap` tags 0xA0+ | `(x as Int) & 0xFF` everywhere | silent false compares | 
| 2026-09-25 | `Str` from `Vec[Str]` elements: `==`/`!=` compare pointers; `str_len`/`.len()` unreliable | documented trap 1; test-side slips found in `upnp` t18 | `str_compare` + typed locals | silent wrong compares | 
| 2026-09-22 | `as` is a reserved keyword; `int_to_base` lives in `xiom.convert.int` (not `xiom.convert`) | documented trap 17 | import discipline | compile errors only | 
| 2026-09-22 | `Int` division truncates toward zero; `(a+b-1)/b` is wrong for negative numerators | documented trap 18 | `q=a/b; r=a%b; if r>0 {q+1} else {q}` | silent wrong ceil | 
| 2026-09-27 | No `Vec[StructType]` (trap 10): struct payload lists need parallel `Vec` fields | `nats` (op stream parsed op-by-op), `i2c` (transaction events modeled as two mirrored `Vec[Int]` arrays) | mirrored parallel Vecs + index discipline | structural noise, drift risk (trap 16) | 
| 2026-09-27 | No auto-borrow at call sites: `&Struct` parameters require an explicit `&op`; omitting it raises E001 moved-value advisories; a read-then-feed-then-read pattern over a `&mut` reader also warns | `nats` tests: 57 E001 "moved value" warnings until helpers took `&NatsOp` and every call site passed `&op`; `tls` ships 7 benign borrow warnings on the reassembly loop; `cassandra` mirrors thrift's `_r_byte_mut` trick to avoid `&` then `&mut` on one reader | explicit `&` at every call site; `_r_byte_mut`-style accessor for mixed borrows | advisory only, but noisy suites; easy to mistake for a real move | 
| 2026-09-27 | Module-level `const` arrays / table initializers mis-materialize | `merkle`: the 64 SHA-256 K constants are rebuilt into a runtime `Vec[Int]` on every hash; `l10n-currency`: the 165-row ISO 4217 table is compiled into comparison chains instead of a module table | rebuild constants at runtime; comparison chains / accessor switches | performance and code size, no correctness impact | 
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


