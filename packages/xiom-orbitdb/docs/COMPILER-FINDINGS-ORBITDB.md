<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# XIOM ORBITDB -> compiler lane: findings (all RESOLVED on v0.64.2)

**Status 2026-10-09: C-ORBIT-01..05 are all RESOLVED on v0.64.2** -- see the
re-test section below; the workarounds are dropped in commit `6f6c3ba`
(`refactor: drop v0.64.2-fixed workarounds`). One scoping caveat remains for
C-ORBIT-04 in consumer modules (recorded under the re-test).

**Status 2026-10-10: C-ORBIT-06 filed (OPEN on v0.64.2)** -- phantom imports
and undeclared signature types are silently accepted; a same-named foreign
type in the program turns the same file into a hard T001, and bogus W004
"unreachable match arm" warnings misdirect the triage. Found by composing the
ORBITDB + XVECTOR source trees for the hybrid probe (bundle
`docs/repro/phantom-core-import/`). ORBITDB-side fix already applied (the
dead `db_error_from_core`/`database_config_from_core` folds retired); suite
123/123 x2 both platforms.

> **Bus (2026-10-10):** open items now live on `xiom-relays`. C-ORBIT-06 is
> `REL-20261010-1549-packages-4` (cross-filed by packages, cites our repro
> bundle); the standalone-check quirk is `REL-20261010-1550-orbitdb-2`. Below
> is closed history; open new bus items instead of editing this file.

**Status 2026-10-10 (v0.64.3 bump):** re-test green -- seven repro bundles
unchanged and matching the v0.64.2 matrix, suite 130/130 x2 Win + WSL,
WAL/db/block crash + fuzz + 2000-key soak green both platforms. C-ORBIT-06
with-twin still red on v0.64.3 (correction `REL-20261010-1802-orbitdb`);
row `-2` (standalone-check quirk) still open. No new findings.

**Status 2026-10-12 (v0.64.4 bump):** battery green -- seven repro bundles
unchanged, suite **159/159 x2 Win + x2 WSL**, fuzz + WAL crash on both
platforms, 2000-key soak OK. **C-ORBIT-06 and C-ORBIT-07 CLOSED**
(fixed + verified: an unresolved `use` is now the single hard error
`T001: unresolved import`; module-local call precedence holds and the
`probe_fault_sync` workaround name is reverted -- probe green, 57 checks).
C-ORBIT-08 PART B fixed (m260) / PART A open; C-ORBIT-09 still red;
**C-ORBIT-10 filed** (Linux `--check` exits 0 on errors; Windows rc=1);
row `-2` still open. Verdicts on
`release-checks/compiler-compiler-v0.64.4.md` (bus).

**Status 2026-10-15 (v0.64.5 re-verification wave):** ORBITDB adopted
v0.64.5 (Windows shadow `xiom.new.0645` `02f0857887e14e48...`; WSL canonical
`c4aa877a8a4c219f...` == linux tarball) and DROPPED the
`XIOM_RUNTIME_DIR` lane override (the re-vendored stdlib carries wave 139 >>
115/117/118). Bundle matrix re-ran on the STOCK pin, x2 Win + x2 WSL:
- C-ORBIT-08 PART A: **FIXED for the filed shape** (m305) --
  `repro_enum_tuple` prints `n=8` / `custom=5` / `done`, exit 0 both
  platforms (the README's old "expected n=5" line was a miscomputed
  expectation; slot 1 is `n + 3`). PART B stays fixed (m260): the
  `& 0xFF` mask was RETIRED in `tuple2_push_f64_le`. **NEW sub-shape filed
  as C-ORBIT-12** (bus `REL-20261015-2055-orbitdb`): `Result[(Enum, Int),
  Enum]` -- tuple with an enum element whose Result ERROR type is ALSO an
  enum -- still emits two names for one tuple struct
  (`Tuple__<mod>.<Val>__Int` vs `Tuple__<Val>__Int`) -> clang hard error;
  reduced to a self-contained 2-variant repro
  (`docs/repro/enum-tuple-codegen/repro_enum_tuple_enum_error.xi`; the
  Int-error control compiles/runs). The `DbResult[TValue]` position
  workaround therefore STAYS until that bundle is green.
- C-ORBIT-09: **FIXED for the probe shapes** (m302) -- `probe_alias` prints
  `flat elem-assign: src[0]=1 copy[0]=99` and `arena elem-assign:
  src[0]=1 copy[0]=1` on both platforms; controls unchanged. Residual
  caveats recorded by the compiler (by-value call args, `push()` args,
  for-loop element bindings, whole-struct copies with Vec FIELDS still
  share): ORBITDB keeps `node_deep_copy` as the copy-on-write ownership
  guarantee (now design insurance, not a bug workaround).
- C-ORBIT-10: **RETRACTED -- not a compiler defect.** On the official
  v0.64.5 artifacts `--check` exits rc=1 for both probes on Windows AND
  WSL (canonical paths, verified sha256). rc=0 reproduces ONLY with
  `xiom-dbg` (DAP adapter; ignores `--check`; sha256 `8060704c...`) -- the
  WSL side of the original matrix had executed the wrong binary. Harness
  hardened (both dev-env twins resolve the compiler explicitly and report
  version/path); the bundle stays as exit-code regression probes.
- C-ORBIT-11: **FIXED** (m298) -- `probe_compose_collision` prints
  `compose ok`, rc 0 on both platforms ON THE STOCK PIN (the v0.64.5
  re-vendor removed the lane-stdlib dependency for byte-IO).
- Row `REL-20261010-1550-orbitdb-2` (standalone `--check src/engine.xi`):
  **FIXED** (m304) -- rc 0, `Type check PASSED` on both platforms.
- Suite **160/160 x2 Win + x2 WSL** on the final tree (after restoring the
  C-ORBIT-12 position workaround and retiring the 08B masks); db_crash /
  probes / fuzz / bench ride this wrap's battery (SESSION.md).
- Registry consumer pass: `probe_pkg_btree` / `probe_pkg_wal` re-run x2
  platforms; `xiom.btree`/`xiom.wal`/`xiom.vectors` reinstalled additively
  into the Windows registry home (the ops fleet swap had reset it; WSL
  home untouched).

**Status 2026-10-16 (v0.64.6 re-verify, PRE-adoption):** v0.64.6 released
(2026-10-16T20:33Z; stdlib pin `stdlib-v0.64.6` `b81430ba`); the enum-tuple
re-verify on the official artifacts is GREEN x2 platforms for the MINIMAL
shape:
- **C-ORBIT-12 RESOLVED on v0.64.8** (`c6b3362ef` in the release; natural `(TValue, Int)` tuple restored, suite 163/163 x2 Win + x2 WSL, workaround retired; item closed). Historical PARTIAL verdict (v0.64.6/v0.64.7): `repro_enum_tuple_enum_error.xi`
  prints `repro C: sum=110 (expected 110)`, rc 0 on the Windows extract
  (`xiom.new-20261016-233955`, sha256 `0ff5c5c471498d8c...`) AND the WSL
  canonical (`855bd7cc82c0f24f...`); control `n=8`/`custom=5`/`done`; u8
  regression 3x `248` (PART B holds). **BUT the adoption-battery
  workaround drop proves the LARGER-PROGRAM silent-mode shape is STILL
  RED on v0.64.6**: `unknown type 'Tuple__TValue__Int' -- defaulting to
  i64` + 6 typed-value suite tests fail (154/160). Workaround RESTORED
  (160/160); residual filed `REL-20261017-1154-orbitdb` (high); the
  v0.64.6 and v0.64.7 check rows are corrected to PARTIAL. (The earlier
  verified+closed on `REL-20261015-2022-orbitdb` covered the minimal repro
  only.)
- **C-ORBIT-09 probes + C-ORBIT-11 compose:** green x2 on v0.64.6 (outputs
  unchanged from the v0.64.5 verdicts; `compose ok`).
- **Ops recurrence** (filed `REL-20261016-2120-orbitdb`): the v0.64.6 fleet
  swap clobbered the Windows shared registry home AGAIN (`xiom.btree`/`wal`
  unresolved on BOTH pins during the re-verify window); additive reinstall
  (`xiom.btree@0.1.1`, `xiom.wal@0.1.0`, checksums verified) restored the
  probes; WSL home untouched.
- Adoption (pin swap in `dev-env.*`) is owner-coordinated; until then the
  Windows pin stays `xiom.new.0645` and the suite stays green there.

**Status 2026-10-11: C-ORBIT-07 filed (OPEN on v0.64.3)** -- a consumer-defined
function silently hijacks an unqualified call to a module-PRIVATE same-named
helper inside an imported module (the ORBITDB M2.1 fault probe's `arm` ran
from inside `fault.xi` instead of `fault.xi`'s own private zero-arg `arm`,
with empty-string args; surfaced as a contract panic at `os/env.xi:29:13`).
Bundle `docs/repro/consumer-fn-hijack/`; bus `REL-20261011-1124-orbitdb`;
workaround applied (distinct helper name `probe_arm`).

**Status 2026-10-11: C-ORBIT-08 filed (OPEN on v0.64.3)** -- two codegen
traps found by the M5.1 typed-values codec: (A) a tuple containing an ENUM
(`Result[(TValue, Int)]`) miscompiles -- warning `unknown type
'Tuple__TValue__Int' -- defaulting to i64`, hard crash or silently skipped
match arms; (B) fixed-size `[N]UInt8` element `as Int` sign-extends
(0xF8 -> -8; `Vec[UInt8]` is correct). Bundle
`docs/repro/enum-tuple-codegen/`; workarounds applied in `tuple.xi`
(`DbResult[TValue]` + explicit advance; `(b[i] as Int) & 0xFF`).

**Status 2026-10-11: C-ORBIT-09 filed (OPEN on v0.64.3)** -- element
assignment through a copied Vec handle writes through to the SOURCE buffer
(`v[i] = x` lacks the copy-on-write check that push/pop perform), so a
struct/Vec "copy" silently aliases its source; two live handles suffice, no
use-after-move involved. Found by the M3 snapshot-pin COW (the shadow copy of
a node still shared `keys`/`values`/`children` buffers with the pinned
original; pinned reads returned post-write values). Bundle
`docs/repro/vec-copy-alias/`; workaround applied (`node_deep_copy` in
`src/engine.xi` rebuilds every vector). Bus item `REL-20261011-1659-orbitdb`.

**Status 2026-10-11 (doorbell): v0.64.4 stack STAGED** -- compiler batches
1-6 complete (m261-m271, `REL-20261011-1731-compiler`); the fixes targeting
our open findings are committed on compiler main: **C-ORBIT-07 -> m261/m262
(`677d65a7`; bus item `REL-20261011-1124-orbitdb` moved to `fixed`)** and
**the C-ORBIT-06 phantom/core-ask gate -> m266/m267 (`0b1c6374`; rows
1802 + packages-4)**. No archive yet: **workarounds stay**. When v0.64.4
ships, re-run `docs/repro/consumer-fn-hijack/` (expect `svc: private arm()
ran` on BOTH import orders) and `docs/repro/phantom-core-import/` before
moving anything to verified/closed.

**Status 2026-10-11 21:00Z (doorbell): stack PUSHED, archive imminent** --
owner-authorized doorbell push landed: origin/main `677d65a7 -> 87c6ca3c`
(m254-m274; the wave added m272-m274 fn-value/ABI fixes found by Gate A and
the bindings verdicts, no open regressions known). stdlib is cleared to
dispatch the **v0.64.4 dry-run archive** (witness/revert/battery/tag
sequence); the compiler pin follows the `stdlib-v0.64.4` tag. Nothing
testable from our side yet -- same verification plan as above on landing.

**Status 2026-10-12 00:00Z (doorbell): v0.64.4 PINNED; owner tag last** --
`REL-20261011-1731-compiler` updates 4+5: m275 (`4c42fc0a`) fixed the
stdlib-2045 wave regression and was pushed; stdlib verified and tagged
`stdlib-v0.64.4` = `3df0843` (refresh run: corpus 954/954, probes 288/288,
modules 509/509); compiler `STDLIB_VERSION` pinned, release notes + gate
record done, origin/main = `df493530` (release commit). LAST STEP is
owner-gated: tag `v0.64.4` on `df493530` -> release run -> assets; then the
reporter verdict wave. No archive on this machine yet: same verification
plan (hijack both import orders + phantom bundle) at the archive.

**Status 2026-10-12 (v0.64.4 verdict wave): C-ORBIT-06 + C-ORBIT-07
VERIFIED FIXED and closed** -- the hijack witness prints `svc: private
arm() ran` on both import orders PLUS a new same-signature variant (Win +
WSL); the phantom bundle now fails with exactly ONE clear unresolved-import
error (silent acceptance and the bogus W004s are gone; with-twin
match-pattern T001 gone). **C-ORBIT-10 filed** (the Linux build's
`xiom --check` exits 0 even for syntax errors -- official artifacts;
ci-gate false-pass; bundle `docs/repro/check-exit-code/`, bus
`REL-20261012-1358-orbitdb`). **C-ORBIT-11 filed** (xiom.btree + 
xiom.db.engine cannot be co-imported: same-named types resolve the engine's
own field-method calls against the foreign declaration, hard C001; bundle
`docs/repro/same-named-struct-compose/`, bus `REL-20261012-1956-orbitdb`).
C-ORBIT-08/09 re-ran unchanged (bundles' expected rc on v0.64.4); row
`REL-20261010-1550-orbitdb-2` still open. The `probe_arm` workaround is
REVERTED -- `probe_fault_sync.xi` now runs the original collision shape and
is GREEN x2 Win + WSL on v0.64.4.

**Status 2026-10-12 (production relay):** lane requirements for a
production-grade DB posted per lane (stdlib `REL-20261012-1945-orbitdb`,
compiler `-2`, packages `-3`), grounded in the acked IO cluster + the
reference study.

**Relay:** hand this file to the compiler-lane session together with the
matching `docs/repro/<bundle>/` directories from the ORBITDB repo
(`E:\xiom-projects\xiom-orbitdb`). ORBITDB is a consumer lane; it does not
edit the compiler tree. Read-only compiler-source references below were
located while triaging and are evidence, not patches.

**Pins (updated 2026-10-09):**

| Component | Version / hash |
|---|---|
| compiler | **v0.64.2** (2026-10-09; installed in place, Windows `%LOCALAPPDATA%\xiom.new` + WSL) |
| compiler history | v0.64.0 (2026-10-08) -> v0.64.1 (same-day re-test) -> v0.64.2 (this re-test) |
| stdlib | `E:\xiom-lang\stdlib` @ `e7896ff` (2026-10-09; lane wave 97 + wishlist sweep + relay consumption) |
| compiler lane | `d9f146cb` (`v0.64.2-2-gd9f146cb`; the v0.64.2 tag is cut) |
| env | `XIOM_STDLIB=E:\xiom-lang\stdlib`; `XIOM_RUNTIME_DIR` retired (env-free, installed R65 layout) |

## Re-test v0.64.1 (2026-10-08) -- all four findings still open; lane green

| Finding | Bundle | v0.64.1 result |
|---|---|---|
| C-ORBIT-01 | `docs/repro/ok-method-receiver/probe_import.xi` | **OPEN** -- identical 4 T001 sites (lines 34/36/53/69): `'get_column' expects 2 argument(s), found 1` / `expected Row, found Int`; A/B/C still fail, D/E/F/G green |
| C-ORBIT-02 | `docs/repro/option-vec-assign/probe.xi` + `probe2.xi` | **OPEN** -- V1/V3/V6/V8/V9 still print nothing (no arm runs); V2/V4/V5/V7/V10 fine |
| C-ORBIT-03 | `docs/repro/nested-field-mut/probe.xi` | **OPEN** -- A=0 (lost), C=0 (lost); B=1, D=1 |
| C-ORBIT-04 | suite with the qualification workaround temporarily reverted | **OPEN** -- same clang failure: `'%tmp10' defined with type '%struct.WALOp' but expected '%struct.WALOpKind'` (IR line 71079) |

Positive on v0.64.1: the whole lane regressed clean -- conformance **104/104**,
WAL/page/DB crash tests GREEN, CRC32C/FSM/tuple/page-file probes unchanged.
The false `W004 unreachable match arm` seen on v0.64.0
(`docs/repro/option-vec-assign/probe2.xi`) was **not emitted** on v0.64.1 --
treat as fixed, keep watching.

**Consumer impact in one line:** the conformance suite of a database engine
did not compile on v0.64.0 (218 type errors, then a codegen C001); after
working around the findings below it is **104/104 green on v0.64.1**
(Windows + WSL), and the crash/reopen WAL/page/DB probes are green on both.
These defects are on the critical path of any storage/collection code that
uses `Vec[Option[T]]` caches, cross-module `Result` aliases, nested-field
`&mut` methods, or same-named enum variants across modules.

## Re-test v0.64.2 (2026-10-09) -- all five findings RESOLVED

Compiler relay (archived): `docs/relay-archive/COMPILER-RELAY-2026-10-09-v0.64.2.md` (m223 alias
payloads, m224 nested-field receivers, m225 enum-variant module scope, m226
`Vec[Option/Result]` element assignment, m235 loop-body alloca, plus
m228/m231/m234/m239).

**Acceptance (relay ask): the C-ORBIT-04 qualification workaround REVERTED.**
`src/wal_file.xi` again constructs and matches unqualified variants
(`return Update;`, `match op { Insert => ... }`) and the suite compiles and
runs green -- m225 resolves variants to the declaring module.

**Workaround reverts verified by the full matrix (commit `6f6c3ba`):**

| Finding | Revert | Result |
|---|---|---|
| C-ORBIT-01 | typed rebinds removed in `src/wal_file.xi` replay + every `src/storage/page_file.xi` reader (`lines` used directly, matched `p` used directly) | green |
| C-ORBIT-02 | no app-side workaround remains (BufferPool uses parallel vectors by design); bundle unchanged | green |
| C-ORBIT-03 | `StorageEngine.cache_page/lookup_page` call `eng.buffer_pool.put/get(...)` directly (no copy-out/write-back) | green |
| C-ORBIT-04 | variants unqualified in `src/wal_file.xi`; engine keeps qualification (see caveat) | green |
| C-ORBIT-05 | `page_log_read_all` restored to the nested `Vec[Page]` dedup with `out.push(all[k])` | green |

**Repro bundles unchanged (Windows + WSL):**

| Bundle | v0.64.1 | v0.64.2 |
|---|---|---|
| nested-field-mut | A=0, C=0 (writes lost) | A=1 B=1 C=1 D=1 |
| option-vec-assign | V1/V3/V6/V8/V9 silent | V1..V5 SOME/OK; no silent slots |
| option-param / option-ref-write / ok-method-receiver | mix of reds per earlier matrix | all labelled OK (D2=NONE, bits=0 controls) |
| vec-option-match | Some arms dropped | A=5 B=5 C=9 D=7 (correct) |
| vec-push-nested | variant D aborts `0xC0000005` | A/B/C/D all ok |

**Lane regression on v0.64.2 with the workarounds reverted:** conformance
120/120 x2 Win + WSL, db_crash 25/25 x2, WAL crash 4/4 x2, page crash 4/4 x2,
fuzz `seeds=4 ops/seed=4000` OK, 2000-key policy soak OK (9 checkpoints).
Bench: `wal_replay` of 20k records 61.6 s -> 9.9 s (stdlib linear
`read_file_lines`; see the stdlib wishlist).

**Bonus verification:** deep container equality (m239) is live --
`Vec[Int] == Vec[Int]` and `Str == Str` compare by content on v0.64.2 (the
v0.64.2 release-notes "Known issues" line claiming pointer identity is
stale).

### v0.64.3 re-test (2026-10-10, bump procedure step 2)

Compiler v0.64.3 (Windows shadow `%LOCALAPPDATA%\xiom.new.0643`; WSL
canonical v0.64.3). All seven C-ORBIT bundles re-run **unchanged and
matching the v0.64.2 green matrix** (nested-field-mut A=1 B=1 C=1 D=1;
option-vec-assign no silent slots; option-param / option-ref-write /
ok-method-receiver all OK; vec-option-match A=5 B=5 C=9 D=7; vec-push-nested
A/B/C/D ok). Lane regression: **suite 130/130 x2 Win + WSL** (includes the
S2/S3 v2 tests), WAL crash 4/4 x2 Win + WSL, db_crash 25/25 Win, block crash
8/8 Win, fuzz OK Win + WSL, 2000-key soak OK Win + WSL (9 checkpoints).

C-ORBIT-06 on v0.64.3: `probe_alone.xi` unchanged (silent pass + 2x W004);
`probe_with_twin.xi` **still fails T001 30:5** -- the release-check row
`REL-20261010-1549-packages-4` verdict ("twin gone; probe passes") is not
reproducible from the committed bundle; correction filed as
`REL-20261010-1802-orbitdb`. **RESOLVED as invocation-dependent (compiler,
18:45Z):** the packages pass reproduces only in the bare-filename form
(`cd docs/repro/phantom-core-import; xiom --check probe_with_twin.xi`) -- a
bare filename's empty parent was indexed as the source dir, so the file's
own directory never reached the catalog (sibling module unresolved). Fixed
on compiler main by **m255** (`13115d64`, unpushed as of 2026-10-10);
**re-verify the bundle on the next archive**. The twin half stays open on
v0.64.3 via the documented path invocation; the phantom-acceptance core ask
is queued for v0.64.4. Release-check row `REL-20261010-1550-orbitdb-2`
(standalone `--check` quirk): **still open** on v0.64.3 (same T001 class at
1206/1211/1216). No C-ORBIT regressions; no new findings.

### Residual caveat -- C-ORBIT-04 scope (consumer modules)

Unqualified resolution now binds to the module that DECLARES the enum. In a
consumer module that imports one enum while the program also contains a
structurally identical enum from another import (our suite imports both
`wal_file.WALOpKind` and `txn.WALOp`), an unqualified variant still resolves
to the wrong twin: `wal_file_append(&mut w, Insert, ...)` in the suite
lowered against txn's `WALOp` -> `T001 expected WALOpKind, found WALOp`
(no ambiguity diagnostic). ORBITDB therefore keeps qualification in consumer
modules (`src/engine.xi`, the suite) and files this follow-up request:
scope unqualified resolution to the importing module's import set and/or
emit an ambiguity error.

## Open findings (all RESOLVED on v0.64.2 -- kept as history)

The rows below describe the v0.64.1 state and the workarounds that were
applied then; every one is resolved on v0.64.2 (see the re-test above).

| Date | Finding | Evidence | Workaround in ORBITDB | Impact |
|---|---|---|---|---|
| 2026-10-08 | **C-ORBIT-01: a cross-module generic type alias in return position (`pub type DbResult[T] = Result[T, DbError]`) is not resolved at the consumer.** A match-bound `Ok(payload)` loses its type: method calls drop the receiver (`'get_column' expects 2 argument(s), found 1` / `expected Row, found Int`), zero-arg methods on the raw binding reach codegen as an unresolved symbol (`C001 'column_count'`), and codegen warns `unknown type 'DbResult' -- defaulting to i64` (10x per suite run). | `docs/repro/ok-method-receiver/probe_import.xi` (A/B/C broken, D/E/F/G green); `probe_rebind.xi` (H broken at codegen, I green); `probe_only_i.xi` green. App: conformance suite 4 T001 -> C001 -> green after rebind; `probe_wal_file.xi` read_file_lines payload printed raw addresses until rebind. | rebind the payload through an explicitly typed local before any access: `let d: Row = decoded;` (probe_only_i), or call the explicit receiver form `Row.get_column(&decoded, 0)` | silent wrong values / no-arg methods emit garbage symbols; breaks every consumer of aliased cross-module `Result` returns (stdlib `io.read_file_lines`, packages) |
| 2026-10-08 | **C-ORBIT-02: assigning an Option into a `Vec[Option[T]]` element poisons the slot.** After `v.push(None); v[0] = Some(x);` (or any Option-to-slot write: Some->Some, Option[Str], None->None) the element matches NEITHER `None` NOR `Some(_)`; every `match` over it silently runs no arm and execution falls through. No diagnostic. `Vec[Int]` writes, enum-vector writes and struct-field Option writes are all fine. | `docs/repro/option-vec-assign/probe.xi` (V1/V3 silent, V2/V4/V5 green); `probe2.xi` (V6 Some->Some silent, V8 Option[Str] silent, V9 None->None silent, V7 enum fine, V10 untouched slot fine). App: BufferPool.put corruption -> `buffer_pool` + `storage_engine` suite failures; `tests/probes/probe_write_drop2.xi`. | never index-assign an Option into a Vec element; rebuild the Vec and assign the Vec (`src/storage/page.xi BufferPool.put`); struct fields are safe | silent wrong behavior + broken exhaustiveness in caches/pools/option-vectors; would corrupt any `Vec[Option[T]]` structure |
| 2026-10-08 | **C-ORBIT-03: a method call whose receiver is a nested field mutates a temporary copy.** `o.inner.bump()` inside a method, and `eng.buffer_pool.put(page)` anywhere, execute on a copy; the `&mut` write-back is lost. Explicit `Inner.bump(&mut o.inner)` and copy-mutate-writeback work. No diagnostic. | `docs/repro/nested-field-mut/probe.xi`: A=0 (lost), C=0 (lost), B=1, D=1 (green). App: `StorageEngine.cache_page` -> `storage_engine: cache/lookup` suite failure; `src/storage/page.xi`. | copy the field to a local, mutate, write it back (`var bp = eng.buffer_pool; bp.put(page); eng.buffer_pool = bp;`); or use the explicit receiver form with `&mut` on the field | silent data loss for every nested-field mutation, including struct-of-struct state machines and adapters |
| 2026-10-08 | **C-ORBIT-04: unqualified enum-variant construction resolves against ANOTHER module's structurally identical enum.** With `xiom.db.txn.transaction`'s `pub enum WALOp { Insert, Update, Delete }` and `xiom.db.wal_file`'s `pub enum WALOpKind { Insert, Update, Delete, ... }` in one compilation unit, `return Update;` inside `wal_op_from_code` lowered as txn's `%struct.WALOp` while the function is declared `-> WALOpKind`; clang rejects the module. Variant patterns may silently compare equal tags instead of failing. | Hard failure with IR evidence (below); suite build broke only when engine imported wal_file AND the suite imported the txn module. | module-qualify variants everywhere (`return WALOpKind.Update;`, `match op { WALOpKind.Insert => ... }`) -- verified compiling and green | hard build failure today; potential silent wrong-enum construction/matching for any two enums sharing variant names (very common: Insert/Update/Delete) |
| 2026-10-08 | **C-ORBIT-05: a nested loop over a `Vec` of structs with Vec fields (`Vec[Page]`) aborts with an access violation when the outer loop also pushes elements into another `Vec[Page]`.** No diagnostic; the process dies with `0xC0000005` (stdout buffered, prints lost). Each ingredient alone is green: the same nested loop over `Vec[Int]`, a single push loop over `Vec[Page]`, and the nested loop over `Vec[Page]` with no push. Observed at n=418; minimum not bisected. | `docs/repro/vec-push-nested/probe.xi` (A/B/C green, D aborts before its print; the marker file names the last variant); app context: `page_log_read_all` dedup aborted on a 418-entry snapshot log, so the policy soak crashed at reopen at N>=400 | rewrite the dedup as an Int-only keep-set pass (nested loop over `Vec[Int]`) + a single non-nested push pass (`src/storage/page_file.xi`); keep struct copies out of nested loops that push | process abort (access violation) in collection code that dedups/filters struct-with-Vec vectors -- looks like memory corruption, no diagnostic |

### Secondary observations (no repro bundle needed)

- `warning[W004]: unreachable match arm` is emitted for a valid two-arm enum
  match where the second arm runs correctly at runtime
  (`docs/repro/option-vec-assign/probe2.xi` line 39, enum `E{A,B}`: `B`
  printed despite the warning). Cosmetic today; do not trust W004 for
  single-variant-looking enums until checked.
- `unknown type 'DbResult' -- defaulting to i64` belongs to C-ORBIT-01; if
  alias resolution is fixed generically, the warning should disappear with
  it.

## C-ORBIT-01 -- details

- **Where (read-only inspection):** `crates/xiom-check/src/lib.rs`
  `value_member_resolves` (~4485) requires `lookup_local` to know the
  receiver's type; for an unresolved match-bound payload it returns false,
  `check_module_call` is attempted on the value-rooted path, and the
  method path then classifies the receiver oddly (`is_static_call` ~7688),
  producing the wrong expected arity (`~7770`). Codegen additionally warns
  the alias is unknown and emits an unresolved symbol for a zero-arg method
  invoked on the raw binding.
- **Repro matrix (v0.64.0):**

  | Variant | Shape | Result |
  |---|---|---|
  | A | match-bound payload from `tuple_decode` (alias result) + `decoded.column_count()`/`get_column(0)` | **T001** |
  | B | same, plain rebind `let d = decoded;` | **T001** |
  | C | explicit `let r: DbResult[Row] = ...` annotation | **T001** |
  | D | direct `let row = Row.new(...)` + 1-arg method | ok |
  | E | direct + zero-arg method first | ok |
  | F | direct + explicit `let row: Row` annotation | ok |
  | G | explicit receiver `Row.get_column(&row, 0)` | ok |
  | H | match-bound + explicit receiver, but zero-arg method on the raw binding | **C001 codegen** |
  | I | match-bound + annotated rebind `let d: Row = decoded;` then all access via `d` | **ok (workaround)** |

- **App-context evidence (strongest):** `io.read_file_lines` returns
  `Result[Vec[Str], IOError]`; in `tests/probes/probe_wal_file.xi` the
  match-bound `Ok(lines)` printed `lines[i]` as raw stack addresses
  (`dbg line=[2380695695584]`) until the payload was rebound through
  `let all: Vec[Str] = lines;`. This is stdlib IO funneling through the
  same defect -- every consumer of `read_file_lines` is affected.
- **Suggested direction:** make the alias transparent to the checker and
  codegen (expand `pub type X[T] = ...` at use sites, or teach
  `lookup_local`/`value_member_resolves` about payloads bound from aliased
  cross-module returns); the compiler-lane commit `0c5337e0` (m216 alias
  resolution) may already cover the Vec-element case -- re-run
  `probe_import.xi` and `probe_only_i.xi` on the next archive.

## C-ORBIT-02 -- details

- **Repro:** `docs/repro/option-vec-assign/probe.xi`:

  | Variant | Shape | v0.64.0 |
  |---|---|---|
  | V1 | `Vec[Option[Int]]`: push(None); `v[0] = Some(44)`; match | **no arm runs** |
  | V2 | push(Some(44)); match | SOME |
  | V3 | local `Some(55)` assigned into a None slot | **no arm runs** |
  | V4 | struct field `s.o = Some(66)` | SOME |
  | V5 | `Vec[Int]`: push(0); `n[0] = 77` | OK |

  `probe2.xi`: V6 Some->Some silent; V7 `Vec[E]` A->B fine;
  V8 `Vec[Option[Str]]` None->Some silent; V9 None->None silent;
  V10 untouched sibling slot fine.
- **App-context evidence:** `src/storage/page.xi BufferPool.put` did
  `pool.pages[idx] = Some(page)`; `bp.misses` incremented but `bp.get(id)`
  returned None and the slot inspected as None/would-not-match
  (`tests/probes/probe_core_diag.xi`). Buffer-pool + storage-engine suite
  tests failed until the rebuild workaround.
- **Suggested direction:** the element-write lowering for enum payloads
  (drop-old + write-new path) appears to lose the discriminant for
  `Option` payloads; an `--emit-ir` diff of V1 vs V2 should show it.

## C-ORBIT-03 -- details

- **Repro:** `docs/repro/nested-field-mut/probe.xi`:

  | Variant | Shape | v0.64.0 |
  |---|---|---|
  | A | `o.inner.bump()` inside `Outer.bump` | 0 (lost) |
  | B | `Inner.bump(&mut o.inner)` explicit | 1 |
  | C | `c.inner.bump()` from `main` | 0 (lost) |
  | D | copy field -> mutate -> write back | 1 |

- **App-context evidence:** `StorageEngine.cache_page` called
  `eng.buffer_pool.put(page)`; the pool never saw the page
  (`storage_engine: cache/lookup` suite failure) until the copy-writeback.
- **Suggested direction:** auto-ref through field projections in method
  receivers (pass `&mut <projection>`, not a value copy), or at minimum
  emit a diagnostic when a `&mut` method is invoked on a projection.

## C-ORBIT-04 -- details

- **Symptom (exact):**
  ```
  error: clang failed with exit code 1
  xiominput.ll:71079:25: error: '%tmp10' defined with type
      '%struct.WALOp = type { i64 }' but expected '%struct.WALOpKind = type { i64 }'
  71079 |   ret %struct.WALOpKind %tmp10
  ```
  (line 71073 on v0.64.0, 71079 on v0.64.1; still reproducible on v0.64.1)
  The body just above constructs `%struct.WALOp` (`alloca %struct.WALOp` ...
  `store i64 1, ...` `load %struct.WALOp`) inside
  `define %struct.WALOpKind @db.wal_file.wal_op_from_code(i64)`.
- **Trigger:** a compilation unit containing both modules (engine now
  `use xiom.db.wal_file;` and the conformance suite imports
  `xiom.db.txn.transaction`). `probe_wal_file.xi` alone compiled and ran
  green for hours -- the collision only appears when both enums are in the
  graph and variant resolution picks the first-registered enum with that
  variant name.
- **Minimal repro sketch (two modules):**
  ```
  // a.xi
  module example.a
  pub enum AKind { Insert, Update }
  pub fn a_make() -> AKind { return Update; }     // lowered as ...?
  // b.xi
  module example.b
  pub enum BKind { Insert, Update, Delete }
  pub fn b_make() -> BKind { return Update; }
  ```
  Compile both plus a caller; expect one function to construct the other
  module's enum (`--emit-ir`, look for the `%struct.` name in `ret`).
- **Impact:** clang catches the return mismatch here, but a variant
  *pattern* against the wrong structural twin would compare equal i64 tags
  and silently take the wrong branch. Treat as high-priority.
- **Workaround (verified clean, 104/104 suite):** module-qualify every
  variant in constructors and patterns in the affected module
  (`src/wal_file.xi`), e.g. `return WALOpKind.Update;` and
  `match op { WALOpKind.Insert => ... }` -- both forms compile and behave.
- **Suggested fix:** unqualified variant resolution must be scoped to the
  current module's declarations first (and error on genuine ambiguity),
  the same way type names are; or intern enum variants by
  (module, name, tag) instead of name only.

## C-ORBIT-05 -- details

- **Symptom (exact):** exit code `0xC0000005` (access violation) with no
  diagnostic and no output (stdout buffering swallows prints).
- **Repro:** `docs/repro/vec-push-nested/probe.xi`, n=418:

  | Variant | Shape | v0.64.1 |
  |---|---|---|
  | A | nested loop over `Vec[Int]`, push ints | ok |
  | B | single loop over `Vec[Page]`, push pages | ok |
  | C | nested loop over `Vec[Page]`, counter only (no push) | ok |
  | D | nested loop over `Vec[Page]` + push `all[k]` into another `Vec[Page]` | **ABORT** |

- **App-context evidence:** `page_log_read_all` (page-log dedup) aborted on a
  418-entry (58 KB) snapshot log; a standalone diagnostic probe crashed on the
  first `page_log_read_all` call after reading the file, while the identical
  algorithm over `Vec[Int]` was green. Policy soaks with N >= 400 aborted on
  reopen until the dedup was rewritten.
- **Workaround (verified):** compute the keep-set over a parallel `Vec[Int]`
  of ids (nested loop over ints), then select pages in a single non-nested
  pass; see `src/storage/page_file.xi` `page_log_read_all`.
- **Suggested direction:** `--emit-ir` diff of D vs C around the element copy
  (struct containing Vec fields) inside the nested loop; the copy appears to
  clobber a loop/allocator register at larger iteration counts.

## C-ORBIT-06 -- phantom import silently accepted; foreign twin turns it hard (OPEN, filed 2026-10-10)

- **Bundle:** `docs/repro/phantom-core-import/` (`probe_alone.xi`,
  `probe_with_twin.xi`, `twin.xi`, README with exact outputs).
- **Symptom A (silent):** a `use` of a module that exists nowhere
  (`xiom.core.error`) plus an undeclared type in a signature (`&CoreError`)
  type-checks green -- with two misleading `W004 unreachable match arm`
  warnings (29:5, 30:5) pointing at match arms instead of the import.
- **Symptom B (hard):** with any reachable module declaring a same-named
  type (`twin.CoreError`; the composite used `xiom.vector.core.shim`'s inline
  `CoreError`), the very same file fails:
  `error[T001]: 30:5: match pattern 'Corruption' belongs to 'DbError', not
  'CoreError'` -- the scrutinee name binds across modules while the bare
  pattern resolves to the same-module enum; no ambiguity diagnostic.
- **Impact:** a consumer lane can ship code that cannot type-check in any
  multi-package composition, while every standalone build is green. The
  ORBITDB `xiom.db.error` fold was silently dead for months this way.
- **Workaround (applied):** never keep a `use`/type that does not resolve;
  removed the dead folds + phantom imports (`2026-10-10`); the composite
  hybrid probe builds and passes.
- **Suggested fix:** error on unresolvable `use` (or undeclared types in
  signatures/field access); prefer the scrutinee's enum for bare pattern
  variants over the same-module enum when both exist, with an ambiguity
  diagnostic.

## C-ORBIT-07 -- consumer fn silently hijacks a module-private same-named call (OPEN, filed 2026-10-11)

- **Bundle:** `docs/repro/consumer-fn-hijack/` (`mod_svc.xi`, `probe_hijack.xi`,
  `probe_clean.xi`, README with exact outputs).
- **Symptom (silent, runtime):** `mod_svc.xi` has a module-private zero-arg
  `arm()` that its `pub fn ping()` calls unqualified; the consumer module
  defines its own `arm(a: Str, b: Str, c: Str)` and calls `ping()`. Observed
  on v0.64.3 (Win + WSL identical): the CONSUMER's `arm` runs with
  empty-string args -- `probe: consumer arm(a=[] b=[] c=[])` instead of
  `svc: private arm() ran`. No error, no warning; `--check` passes both
  files. The zero-arg call reaches the 3-arg function with missing arguments
  materialized as empty values.
- **App-context evidence:** the ORBITDB M2.1 fault probe defined a helper
  `arm(Str,Str,Str)`; `fault.xi`'s own `arm()` calls inside `fault_armed()` /
  `fault_gate()` were redirected to it, feeding empty values into
  `env.set_var` and tripping a runtime contract panic
  (`contract violated: ensures at 29:13` = `os/env.xi:29:13`, cstr's
  `result != null` on an empty value) -- with no file name in the message and
  no compile-time diagnostic. Bisected via `--emit-ir` (the check is in the
  inlined `cstr` body of `env.var_opt`) and a scratch control that passed;
  renaming the probe helper to `probe_arm` made suite + probe green.
- **Impact:** any composed program can silently redirect a module's private
  helper calls when another module defines the same function name; the
  service module cannot defend itself (no way to module-qualify an
  intra-module call). Same family as the m225 consumer-scope caveat
  (C-ORBIT-04 residual note), extended from enum variants/types to functions.
- **Workaround (applied):** keep consumer/probe helper names distinct from
  functions inside imported modules (`probe_arm`); suite 136/136 x2 +
  probe GREEN x2 Win + WSL afterwards.
- **Suggested fix:** resolve unqualified calls to the declaring module's own
  function (mirror the m225 fix direction) and emit an ambiguity diagnostic
  when a same-named function exists in another module of the program.
  Secondary: include the source file in contract-violation messages
  (currently `line:col` only).

## C-ORBIT-08 -- enum-in-tuple miscompile + `[N]UInt8` element cast sign-extension (v0.64.5: PART A fixed for the filed shape / PART B fixed; sub-shape split to C-ORBIT-12)

**Verdict 2026-10-15 (v0.64.5, both platforms):** PART A GREEN for the filed
shape (m305: `repro_enum_tuple` -> `n=8`/`custom=5`/`done`, exit 0; note the
terminal-1 value is `n + 3`, the old README expected-line was miscomputed).
PART B GREEN (m260; the `& 0xFF` mask retired in `tuple2_push_f64_le`).
**A sub-shape remains RED** (enum-in-tuple + enum ERROR type; both are enums)
-> reduced + filed as **C-ORBIT-12** (`repro_enum_tuple_enum_error.xi`), so
the `DbResult[TValue]` position workaround stays.

- **Bundle:** `docs/repro/enum-tuple-codegen/` (`repro_enum_tuple.xi`,
  `repro_u8_cast.xi`, `repro_enum_tuple_enum_error.xi`, README with exact
  outputs on both platforms).
- **Part A (enum in a tuple -- HARD failure):** `Result[(Color, Int), Int]`
  compiles with the warning `unknown type 'Tuple__Color__Int' -- defaulting
  to i64. This may produce incorrect code.` and then: Windows exit code
  -2147483645 (0x80000003 STATUS_BREAKPOINT) with no output at all; WSL exit
  -1/255. In the ORBITDB codec (`DbResult[(TValue, Int)]`) the failure mode
  was even quieter -- `Ok` match arms silently did not execute (neither arm
  printed), which is how it was found. Workaround: never put an enum in a
  tuple; return the enum alone (`DbResult[TValue]`) and advance positions
  with `tuple2_value_len(v)`.
- **Part B (fixed-array byte cast -- silent data corruption):** a
  `[8]UInt8` element read with `as Int` SIGN-EXTENDS high bytes (0xF8 ->
  -8) on both platforms; `Vec[UInt8]` element reads are correct (248) --
  so `byte_io`/block-store readers are unaffected. The storage byte
  convention is 0..255: code reading through fixed-size arrays had to mask
  (`(b[i] as Int) & 0xFF`; applied in `tuple2_push_f64_le`, RETIRED
  2026-10-15 after the m260 fix re-verified on v0.64.5).
- **Impact:** any program moving enums through tuples (a natural API shape)
  or reading bytes out of fixed-size arrays (a natural codec shape) gets
  crashes or silently wrong values with no type error.
- **Suggested fix:** type the tuple shape correctly (no default-to-i64
  escape hatch), and zero-extend `UInt8 -> Int` casts for fixed-size array
  element reads.

## C-ORBIT-12 -- enum-in-tuple with an enum ERROR type (RESOLVED on v0.64.8, verified + closed 2026-10-19)

- **Bundle:** `docs/repro/enum-tuple-codegen/repro_enum_tuple_enum_error.xi`
  (minimal: two variants suffice; no Str/Vec/Float payloads needed).
- **Symptom (v0.64.5, both platforms):** `Result[(Val, Int), Err]` with BOTH
  `Val` and `Err` enums emits two names for one tuple struct --
  `%struct.Tuple__<mod>.<Val>__Int` (module-qualified element key) and
  `%struct.Tuple__<Val>__Int` (bare) -- and clang hard-fails:
  `error: '%tmp17' defined with type '%struct.Tuple__<mod>.<Val>__Int ...'
  but expected '%struct.Tuple__<Val>__Int ...'`, rc 1, no binary.
- **Control:** the identical shape with an INT error type
  (`Result[(Val, Int), Int]`) compiles and runs correctly (sum=110, exit 0).
  Inside larger programs the shared shape also degrades to the old
  `unknown type 'Tuple__TValue__Int' -- defaulting to i64` warning + silent
  misdecode (ORBITDB's typed-value suite failed 6 tests when the position
  workaround was provisionally dropped: decode returned `Err`).
- **Impact:** the `DbResult[(TValue, Int)]` position-tuple shape stays
  retired in `src/storage/tuple.xi` (workaround: return the value alone,
  advance via `tuple2_value_len(v)`); m305 fixed the ctor-call/Int-error
  family but not this one.
- **Suggested fix:** m305's tuple-element namers must canonicalize the
  enum's key IDENTICALLY on the definition and the use side (the
  module-qualified rename for injected/identity-collision types leaks into
  only one of the two namers when the Result error arm is an enum).
- **Verdict 2026-10-16 (v0.64.6, both platforms): FIXED for the MINIMAL
  repro** (m336: canonical payload namers + bare-key mapping for the
  string-fed readers; compiler ledger `80ca1862`/`75268b53`, cherry-picked
  `0009303c`/`312743d0`). `repro_enum_tuple_enum_error.xi` -> `repro C:
  sum=110 (expected 110)`, rc 0; control + u8 regression green.
- **CORRECTION 2026-10-17 (v0.64.6 adoption battery): the LARGER-PROGRAM
  silent-mode shape is STILL RED.** Dropping the workaround (natural
  position tuple `DbResult[(TValue, Int)]` in `src/storage/tuple.xi`)
  emits `unknown type 'Tuple__TValue__Int' -- defaulting to i64` and fails
  6 typed-value suite tests (154/160: tuple-v2 roundtrip, schema_row
  roundtrip/rejects/bool-empty, typed-query ops/persistence). Workaround
  RESTORED (160/160); residual filed `REL-20261017-1154-orbitdb` (high)
  with the exact evidence; the v0.64.6 + v0.64.7 check rows are corrected
  to PARTIAL. Acceptance = suite 160/160 WITH the position tuple on the
  next archive. The m336 fix covers the reduced shape only.
- **UPDATE 2026-10-18 (relay `REL-20261018-1650-compiler`, received on the
  doorbell; closed by the compiler lane):** the requested self-contained
  extraction was no longer needed -- the compiler reproduced the residual
  with a TWO-MODULE minimal (module-qualified alias + a consumer reading
  `p.1`), the same shape our split now formalizes. Fix `c6b3362ef`
  registers unresolved tuple names on demand; the compiler lane reports our
  suite 160/160 with the natural position tuple restored on branch
  `f779c23` (their tree). NOT in v0.64.7: the workaround stays here until an
  archive carrying the fix is adopted, then re-run the acceptance.

## C-ORBIT-09 -- element assignment through a copied Vec handle writes through to the source (FIXED on v0.64.5 by m302; residual caveats documented)

- **Bundle:** `docs/repro/vec-copy-alias/` (`probe_alias.xi`,
  `probe_clean.xi`, README with exact outputs).
- **Symptom:** after `var copy = src;` (or after extracting a handle from a
  containing `Vec`/struct), `copy[i] = x` mutates `src[i]` too; `push`/`pop`
  on the same handle DO copy-on-write. Observed:
  `src[0] = 99` after `copy[0] = 99`; `src.len` stays 2 after `copy.push(3)`
  (copy len 3) and after `work.pop()` on an arena handle (local 1,
  store-copy 2). Exit 0, no diagnostics beyond unrelated move warnings when
  a moved-from struct is read.
- **Mechanism:** Vec handles share the underlying buffer through assignment;
  element assignment skips the sharing check that structural ops perform.
- **Impact:** silent aliasing for any "clone then mutate in place" pattern.
  ORBITDB's M3 COW shadows corrupted pinned snapshot views until the copy
  rebuilt every vector (`node_deep_copy`).
- **Workaround (applied):** build owned copies explicitly (fresh vectors +
  push loops, nested vectors included).
- **Suggested fix:** make element assignment perform the same copy-on-write
  check as push/pop (or deep-copy on assignment), and consider a diagnostic
  when writing through a shared handle.

## C-ORBIT-10 -- RETRACTED: `xiom --check` exit codes are correct on Linux (not a compiler defect; closed 2026-10-15)

**Original report (v0.64.4 wave, for history):** "the Linux build's
`--check` exits 0 even when it reports errors; the Windows build exits 1."
The compiler lane's triage (2026-10-13) already found the documented Linux
artifact exits rc=1 across 20+ invocation variants and localized rc=0 to
`xiom-dbg`; ORBITDB's v0.64.5 re-run confirmed that verdict on the official
artifacts.

**Verdict 2026-10-15 (v0.64.5, official artifacts):** `--check` exits `rc 1`
for both probes on Windows AND WSL (canonical paths, sha256-verified
binaries). `rc=0` reproduces ONLY with `xiom-dbg` (the DAP debug adapter;
ignores `--check`, prints "GDB/MI backend", sha256 `8060704c...`): the WSL
side of the original v0.64.4 matrix had executed the wrong binary. Lane
harness hardened (dev-env twins resolve + report the compiler explicitly);
bundle kept as exit-code regression probes; README rewritten. See
`docs/repro/check-exit-code/README.md`.

## C-ORBIT-11 -- same-named types across modules break consumers at codegen (FIXED on v0.64.5 by m298; compose ok both platforms)

**Verdict 2026-10-15:** `tests/pkg/probe_compose_collision.xi` prints
`compose ok`, rc 0 on both platforms ON THE STOCK PIN (no lane-stdlib
dependency after the v0.64.5 re-vendor). The two-program digest pattern
stays as interop testing design; co-composition is no longer blocked.

- **Bundle:** `docs/repro/same-named-struct-compose/` (real repro:
  `tests/pkg/probe_compose_collision.xi`; a minimal two-struct pair is
  included as negative evidence -- it does NOT reproduce).
- **Symptom:** co-importing `xiom.btree` (package) with
  `xiom.db.engine` fails at codegen:
  `error[C001]: unresolved function symbol(s): 'xiom.btree.BTreeNode.pop'
  ... from @db.engine.split_child, 'xiom.btree.BTreeNode.push' ... from
  @db.engine.insert_at_pos`. The engine's own `payloads.pop()` /
  `payloads.push()` calls (a field only the engine's BTreeNode has) resolve
  against the package's same-named type. m267 rightly rejects unresolved
  symbols; the trigger here is only the name collision.
- **Impact:** registry packages cannot be co-composed with source modules
  whose public type names overlap (BTreeNode/NodeStore/BTree). The
  xiom.btree consumer pass had to be split into two programs with a shared
  digest. Related: `REL-20261010-1709-xvector` (layout shadowing), the
  C-ORBIT-04/m225 consumer-scope family.
- **Workaround (applied):** never co-import modules with colliding type
  names; verify packages in package-only programs and compare via external
  digests (`probe_pkg_btree.xi` + `probe_pkg_btree_engine.xi`).
- **Suggested fix:** resolve field/method access against the module-local
  type definition; emit a clean "no field on <Type>" diagnostic when a
  field is genuinely missing.

## C-ORBIT-13 -- `&mut` on a >=3-level nested field path copies Int/nested-struct state (FIXED in v0.64.8, verified 2026-10-19)

**Filed 2026-10-19** as relay `REL-20261019-1209-orbitdb` (orbitdb -> compiler,
severity high). Repro bundle: `docs/repro/nested-mut-path/` (self-contained).

Shape: `bump(&mut t.store.bs)` where `T -> NS -> BS` is a three-field-segment
path. It compiles, but the callee receives a COPY: Int and nested-struct
fields in `t` keep their old values, while Vec element writes still leak
through the shared buffer (so the defect is silent and partial). Two-level
paths are correct; direct assignment and local-copy-then-write-back are
correct; no warning is emitted.

Evidence: v0.64.7 Windows (`592aa125...`) and WSL lane (`302d3192...`) print
`two-level: PASS`, `three-level: n=1 g=0 v=1` / `FAIL`, `workaround: PASS`.
Found while landing M1.1b: `snap_flush_v2` committed via
`&mut tree.store.bs`, so each spill used a stale `block_count`, overwrote the
same block, and dropped the header update -- the checkpoint returned success
but replayed keys were lost on reopen (typed_mvcc 14/15). **Workaround stays**
in `snap_flush_v2` (local copy + write-back) until a release carries a fix;
re-run the repro + suite on the next archive. **Additional hit (A5):**
`&mut db.tree.store` (also 3 levels) silently copied in
`db_file_snapshot_end`, so `ns_release_pending` saw 655 pending entries stay
forever; fixed with BTree-level wrappers (`btree_release_pending`,
`ns_bs_put`/`ns_bs_commit`). The checkpoint workaround moved from a copied
BlockStore to these helpers because a copied store loses cache-spill
`block_count` updates and the two writers overwrite blocks once evictions
occur (caught by the new GC suite test). **RESOLVED on v0.64.8:** the natural nested `&mut` calls were restored (helpers removed) and the repro prints all PASS on Win + WSL; suite 163/163 x2 both, crash 25/25 x2 both, hybrid green. Item closed.

## C-ORBIT-14 -- `let`/`var` binding of a Vec returned through a match truncates (FIXED on compiler main 478e06f8b; v0.64.8 predates it)

**Filed 2026-10-21** as relay `REL-20261021-1136-orbitdb` (orbitdb -> compiler,
severity high). Repro bundle: `docs/repro/vec-match-binding/` (self-contained).
**Compiler fixed it the same day on main (`478e06f8b`, m1136):** block-tailed
match arms (`Ok(x) => { x }`) inferred the result slot as i64 before the
binding existed, so the arm stored the Vec data pointer as an integer and the
let-bound value lost its length (`via_let=1`). The exact repro is green on
main; **v0.64.8 predates the fix**, so the Station's declare-then-assign
workaround stays until the next archive, then re-run the bundle and drop it.

Shape:

```xi
let v = match make_vec() {     // make_vec() -> Result[Vec[Int], Int]
  Ok(x) => { x }
  Err(_) => { return -1; }
};
return v.len();                // 1, expected 3
```

The `var`-assignment form and returning the Vec directly from the match arm are
correct (`via_var=3`, `direct_len=3`; `via_let=1` and `via_var_init=1`). Both
a `let` and a `var` initializer over the match corrupt the Vec length; only
declare-then-assign is safe. This is silent data
truncation, likely the same receiver/scratch family as the module-level
`Vec.pop` no-op (m2057 / `029595080`): the Vec's length is corrupted when a
`let` binds a Vec returned through a `match`/`Result`. Found while building
the Station `frame_encode`: a 38-byte header was reported as 1 byte and the
encoded frame shrank 61 -> 24 bytes. Workaround applied in the Station codec:
assign through a `var` or return the Vec directly from the arm. Re-run the
repro on the next archive; drop the workaround only when `via_let=3`.
**Compiler fix landed on main (`478e06f8b`, 2026-10-21); v0.64.8 predates it.**

## C-ORBIT-15 -- a UTF-8 BOM on a module file breaks catalog discovery (FIXED on compiler main 18415ede2; v0.64.8 predates it)

**Filed 2026-10-21** as relay `REL-20261021-1157-orbitdb` (orbitdb -> compiler,
severity medium). Repro bundle: `docs/repro/utf8-bom-module/` (the fixture's
`sub/impl.xi` is intentionally committed WITH the BOM). **Compiler fixed it
the same day on main (`18415ede2`):** the catalog's quick header scan
(`ModuleCatalog::read_module_header`) did not strip a leading U+FEFF; it now
mirrors the lexer's BOM strip. Exact repro is green on main; **v0.64.8
predates the fix**, so keep sources BOM-free until the next archive, then
re-run the bundle unchanged and close.

Shape: a module file that starts with the valid UTF-8 BOM (`EF BB BF`) and
declares a module path that does not match its file name
(`station/src/protocol.xi` -> `xiom.station.protocol`) is not indexed by the
catalog: `use xiom.station.protocol` fails with `T001: unresolved import` and
no BOM diagnostic. Stripping the three BOM bytes makes the identical file
compile. A BOM is tolerated when the import resolves by file name in the
entry's directory (the path lookup wins), which is why simple repros can
mask this. Windows tooling (`Set-Content -Encoding UTF8` in PowerShell 5.1)
writes a BOM by default, so consumers hit this silently. Found while adding
the Station wire module; workaround: save sources without a BOM (recipe in
the bundle README). The compiler should strip a leading BOM before
tokenization or emit a specific diagnostic. Re-run the bundle on the next
archive; close when `main.xi` prints `v=7` with the BOM fixture unchanged.

## Bump procedure used by this lane

1. Update `scripts/dev-env.ps1/.sh` pins (compiler path/version only; stdlib
   path is fixed to the lane checkout).
2. Re-run: `scripts/suite.ps1` (x2; WSL: `scripts/suite.sh`),
   `scripts/crash_test.ps1 -Events 20` (x2) and the 200-record soak,
   `.sh` twins from WSL, then the repro bundles.
3. A finding flips to RESOLVED only when its probe bundle is green
   unchanged; record the result in this file and SESSION.md.
4. Then run the relay-acceptance pass: revert the app-side workaround on a
   branch, re-run suite x2 + crash x2 + fuzz + soak on both platforms, and
   merge only if green (v0.64.2 did this in commit `6f6c3ba`). A finding
   whose revert regresses keeps its workaround and stays open.
