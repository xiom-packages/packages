# Relay: ORBITDB -> compiler lane (paste-ready)

**From:** ORBITDB lane (`E:\xiom-projects\xiom-orbitdb`, embedded database
engine). **Pin:** compiler v0.64.0, stdlib `a677338` (2026-10-08).

Hi compiler lane -- ORBITDB is a new consumer lane (formerly xiom-db). Full
details and repro bundles are in the lane repo:

- `docs/COMPILER-FINDINGS-ORBITDB.md` (findings + variant matrices)
- `docs/repro/ok-method-receiver/`, `docs/repro/option-vec-assign/`,
  `docs/repro/nested-field-mut/` (plus ruled-out controls)

Three open findings from building a real storage engine on v0.64.0:

1. **C-ORBIT-01 -- cross-module generic `Result` alias payload unresolved.**
   `pub type DbResult[T] = Result[T, DbError]` as a return type: the
   match-bound `Ok(payload)` loses its type at the consumer. Method calls
   drop the receiver (`'get_column' expects 2 argument(s), found 1`),
   zero-arg methods reach codegen as an unresolved symbol (C001), and
   codegen warns `unknown type 'DbResult' -- defaulting to i64`. App
   evidence: `io.read_file_lines` payload printed raw stack addresses until
   rebound; our 93-test suite had 4 T001 + a C001 from one `tuple_decode`
   call site. Workaround in production: `let d: Row = decoded;` before any
   access. NOTE: your lane commit `0c5337e0` (m216 alias resolution) may
   already cover this -- the repro bundles are ready for a re-test.
2. **C-ORBIT-02 -- `Vec[Option[T]]` element assignment poisons the slot.**
   After `v.push(None); v[0] = Some(x);` the element matches NEITHER `None`
   nor `Some(_)`; every match silently runs no arm, no diagnostic. Also for
   Some->Some, `Option[Str]`, None->None. `Vec[Int]`, enum vecs, and struct
   fields are fine. This broke our BufferPool in production.
3. **C-ORBIT-03 -- nested-field `&mut` method receivers mutate a copy.**
   `o.inner.bump()` and `eng.buffer_pool.put(page)` lose the write-back; the
   explicit `Inner.bump(&mut o.inner, ...)` and copy-mutate-writeback forms
   are correct. This broke `StorageEngine.cache_page`.

Impact framing: all three are silent-wrong-value defects on the path of any
collection/storage code; the database suite and crash probes are green only
because of in-repo workarounds. Also minor: a W004 false "unreachable match
arm" on a valid two-arm enum match (`docs/repro/option-vec-assign/probe2.xi`).

**Re-test recipe (next archive):** `scripts/run.ps1
docs/repro/ok-method-receiver/probe_import.xi` (expect no T001; variants
A/B/C broken -> green), `probe_only_i.xi`, `probe2.xi` in
option-vec-assign, `nested-field-mut/probe.xi` (A/C must be 1). Findings
flip to RESOLVED only when the bundles are green unchanged.

**New finding since the first message -- C-ORBIT-04 (enum variant collision,
hard compile failure):** with `xiom.db.txn.transaction`'s
`pub enum WALOp { Insert, Update, Delete }` and `xiom.db.wal_file`'s
`pub enum WALOpKind { Insert, Update, Delete, ... }` in one compilation
unit, unqualified `return Update;` inside `wal_op_from_code` lowered as the
txn module's `%struct.WALOp` while the function is declared `-> WALOpKind`:

```
error: clang failed with exit code 1
xiominput.ll:71073:25: error: '%tmp10' defined with type
    '%struct.WALOp = type { i64 }' but expected '%struct.WALOpKind = type { i64 }'
71073 |   ret %struct.WALOpKind %tmp10
```

The same module (wal_file) compiled and ran green for hours when the txn
module was NOT in the graph -- the collision only appears when both enums
are present. Variant *patterns* against the wrong structural twin would
compare equal i64 tags and silently take the wrong branch, so this is
high-priority even though clang caught the constructor case here.
Workaround verified in our build: module-qualify variants in constructors
AND patterns (`return WALOpKind.Update;`,
`match op { WALOpKind.Insert => ... }`) -- suite back to 104/104.
Full details + IR snippet in `docs/COMPILER-FINDINGS-ORBITDB.md`
(section C-ORBIT-04). Suggested fix: scope unqualified variant resolution to
the current module first (or intern variants by module+name+tag) and error
on real ambiguity.

Thanks -- ORBITDB keeps tracking the latest compiler and will re-run these
every release.

**Update 2026-10-08 -- re-tested on v0.64.1 (installed in place, Windows +
WSL): all four findings still reproduce.** C-ORBIT-01: identical 4 T001
sites in `probe_import.xi` (m216 did not cover the match-bound alias
payload). C-ORBIT-02: V1/V3/V6/V8/V9 still silent. C-ORBIT-03: A=0, C=0.
C-ORBIT-04: same clang mismatch (IR line 71079) with the qualification
workaround reverted. Lane regression on v0.64.1 is clean otherwise
(conformance 104/104, WAL/page/DB crash tests GREEN), and the false W004
"unreachable match arm" from v0.64.0 no longer appears -- thanks for that.

**New finding on v0.64.1 -- C-ORBIT-05 (process abort, access violation):**
a nested loop over a `Vec` of structs with Vec fields (`Vec[Page]`) aborts
with exit `0xC0000005` when the outer loop also pushes elements into another
`Vec[Page]`. The same nested loop over `Vec[Int]`, a single push loop over
`Vec[Page]`, and the nested loop over `Vec[Page]` without a push are all
green. Repro: `docs/repro/vec-push-nested/probe.xi` (variant D aborts; the
marker file `vec-push-nested.mark` names the last completed variant).
Production hit: a page-log dedup over a 418-entry snapshot crashed a soak at
reopen (N>=400). Workaround: keep-set over a parallel `Vec[Int]` + a single
non-nested push pass. This one aborts the process rather than miscompiling a
value, so it is the highest-severity shape we have seen from the collection
family. Details in `docs/COMPILER-FINDINGS-ORBITDB.md` (C-ORBIT-05).

**Confirmed 2026-10-09 -- v0.64.2 re-test: all five findings RESOLVED.**

- Acceptance as asked: the C-ORBIT-04 qualification workaround is reverted in
  `src/wal_file.xi` (unqualified constructors and patterns) and the lane is
  green on v0.64.2. The C-ORBIT-01 (typed rebinds in `src/wal_file.xi` +
  `src/storage/page_file.xi`), C-ORBIT-03 (copy-out/write-back in
  `StorageEngine`) and C-ORBIT-05 (Int-only dedup) workarounds are reverted
  too: suite 120/120 x2 Win + WSL, db_crash 25/25 x2, WAL/page crash x2,
  fuzz OK, 2000-key soak OK; commit `6f6c3ba`.
- All seven repro bundles are green unchanged on both platforms
  (nested-field-mut A=1; option-vec-assign V1..V5 readable; vec-option-match
  A=5/B=5/C=9/D=7; vec-push-nested variant D ok).
- One residual scoping note on m225 (not a red): unqualified resolution now
  binds to the DECLARING module, but a consumer module in a program that also
  contains another same-named enum still resolves to the wrong twin -- our
  suite (imports both `wal_file.WALOpKind` and `txn.WALOp`) failed with
  `T001 expected WALOpKind, found WALOp` for `wal_file_append(&mut w, Insert,
  ...)` and keeps qualification. Request: scope resolution to the importing
  module's import set and/or emit an ambiguity error; no reds otherwise.
- Bonus: deep container equality (m239) verified working (`Vec[Int] ==`
  content-true, `Str ==` content-true); the v0.64.2 release-notes "Known
  issues" line claiming pointer identity looks stale.
- Thanks for the batch; full matrix in `docs/COMPILER-FINDINGS-ORBITDB.md`
  (v0.64.2 re-test section).
