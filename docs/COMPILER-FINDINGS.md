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
| 2026-10-02 | Deep `clone()` of aggregate payloads returns a corrupt handle: `Vec[T].clone()` / `derive[Clone]` on a type with Object/Array payload; the next `push` crashes `0xC000001D` (scalar payload clones fine) | `xiom.json` hardening -- public `derive[Clone]` on `JsonValue`/`JsonEntry`; worked around with an explicit `json_clone`, derive removed from the public surface | explicit deep-clone functions; never derive Clone on aggregate-payload types | memory-unsafe crash on legal API use |
| 2026-10-02 | `xiom-verify` v0.62.2 cannot encode record-field contracts (X7007 `field access on non-datatype receiver`, `unknown constant <T>-<f>`, `xiom_ptr_*` opaque `&T` sorts), if-merge leaves the merge variable unconstrained, X7004 division obligations are path-insensitive, multiple `requires:` clauses emit duplicate `:named` asserts (Z3 abort), and package/cross-module `use` is unresolved; scalar-only contracts DO verify (2/2 and 4/4 proven probes) | `xiom.json`/`xiom.control`/`xiom.sensor` hardening -- 0 of 101 clauses proven; all reported "violations" traced to these encodings (false positives) | merge predicates into single `&&` clauses; document solver-unproven clauses in SPEC; prefer scalar contracts | contract verification is a review aid for record-heavy packages on this pin, not a proof |
| 2026-10-02 | Type laxness beyond brackets: binding a `Str` struct field into a `Vec[UInt8]`-typed local (`let gb: Vec[UInt8] = got.value;`) compiles with zero diagnostics and produces wrong bytes at run time | `xiom.pptx` (found while writing the ZIP reader; the suite went green and a later byte comparison exposed it); wave 51 (`consul`): passing `Result[Bool, Str]` where `Result[Int, Str]` is declared compiled silently and read garbage (caught once test-side) | keep explicit types on every cross-value binding; unit-test byte round-trips; the post-green bracket grep does NOT catch this shape | silent wrong code -- same family as arity/mixed-bracket laxness |
| 2026-10-02 | Stdlib `xiom.crypto.hash._u64_lshr`/`_u64_shr(x, 63)` is wrong when `x` has bit 63 set: it divides by `_pow2(63)` = `Int64_MIN` (negative), so the quotient flips sign and the floor adjustment is skipped (`Int64_MIN` -> 3 instead of 1) | `xiom.web3`: Keccak-256 diverged only for absorbed lanes equal to `0x8000000000000000` (empty/`abc`/`eth` failed; fox/hello/long inputs passed); localized by tracing theta vs a Python oracle to `rotl(C[1], 1)` | special-case `n == 63` in the in-package copy; do not reuse the helper as a general idiom | stdlib-side defect; stdlib callers never shift by 63 (SHA-512/BLAKE2b unaffected) |
| 2026-10-02 | Stdlib `xiom.crypto` / `xiom.crypto.hash` SHA-256 and HMAC SHIP IN SOURCE BUT DO NOT LINK from a package on v0.62.2: `lld-link: undefined symbol: xiom_sha256_hash` | `xiom.aws` (SigV4 needed SHA-256/HMAC; repro `use xiom.crypto; crypto.sha256_hex(&abc)`); `xiom.saml` had already hand-rolled SHA-256 before the source existed | hand-roll SHA-256/HMAC in-package and KAT-pin it (`xiom.aws.base`, `xiom.saml`) | every crypto-adjacent package duplicates crypto; source presence != linkability |
| 2026-10-03 | Module-level const arrays: simple `[N]Int` tables are CORRECT, but **complex initializers mis-materialize** -- a `const NAMES: [3]Str` table reads corrupt strings (`str_len` sums 30 vs 14; `str_compare` fails) and a `const ROWS: [3]Row` struct table reads all fields as zero, deterministically (`bad=5`, 3/3 runs) | `docs/repro/const-tables/probe_const_tables.xi` on v0.62.2: Int `sum=9` correct; Str lens sum 30 vs 14; struct code/name sums 0; runtime controls pass (struct literal `code=9`; `Vec[Str]` lens sum 14). Row 25 follow-up (simple shapes were `bad=0` on 2026-10-02) | keep runtime table builders for Str/struct tables (`merkle`, `l10n-currency`, `l10n-unicode`); Int const tables are usable | silent wrong table data; row 25 not retirable for complex shapes |
| 2026-10-03 | **Uninitialized local struct + assignment inside a match arm corrupts the value on v0.62.3** (`var x: T;` + `match { Some(v) => { x = v; } }`) -- `Str` fields read as garbage pointers (concat hangs) and `Vec.len()` reads `4294967295` (runaway loops); pre-initializing the local avoids it. Found restoring `xiom.graphql` (`validate_operation`); a second distinct defect remains in that validator (corrupted `Err` payload reads) | in-situ probes: direct `Some(t)` binding, pass-through refs and match-expression `Str` locals all correct (`Query/fields=1`); uninit variant hangs/timeouts; preinit variant reads correctly. Standalone repro `docs/repro/uninit-local/` currently crashes pre-output (`exit -1073741795`) -- minimal repro pending | **always initialize locals at declaration** (`var x: T = <default>;`); never `var x: T;` + later assignment | silent corruption with runaway/hang failure modes; blocks the `graphql`/`rest` restores until isolated. **FIXED on compiler main (m185) -- confirmed real NULL-deref UB, locked; pending the next release pin. Drop the porter-brief rule after that release** |
| 2026-10-03 | **A test module nested under the package namespace cannot import the package root module on v0.62.3** (`module xiom.pkg.tests` + `use xiom.pkg;` -> every root export is `T001: undefined variable`; 163 errors in `xiom.websocket`); renaming the module to a non-nested name (`websocket_tests`) makes the identical import resolve. Importing *child submodules* from a nested test module works (`xiom.http.tests` imports `xiom.http.types` fine) | A/B in-tree: `xiom-websocket/tests/test_conformance.xi` module line only -- nested: 163 T001s; non-nested: compiles, 10/10 passes. Same nested pattern was present in `xiom.graphql.tests`/`xiom.rest.tests` | name test modules **outside** the package namespace (`pkg_tests`), never `xiom.pkg.tests` | silently blocks package restores; found on `websocket`, `graphql`, `rest`. **FIXED on compiler main (m184), locked; pending the next release pin. Drop the porter-brief rule after that release** |
| 2026-10-03 | **`match` arms that use `const` values never match on v0.62.3** -- every arm composed of a named constant falls through to the wildcard, silently returning the default. Found in `xiom.grpc`: `status_to_str` matched 17 `GRPC_STATUS_*` consts and returned `"UNKNOWN"` for every code (0..16) | minimized in `docs/repro/const-match/probe_const_match.xi` (`const TWO: Int = 2`, `match x { TWO => "two", _ => "other" }` -> `two=other`, `bad=1`). Repo-wide scan: 17 const arms total, all in `grpc.xi` | use numeric/string **literals** (or real enum variants) in match arms; `==` comparisons against consts are fine. `grpc.xi` rewritten accordingly | silent wrong results; any future porter matching constants hits it |
| 2026-10-03 | **Enum payload struct `Str` reads corrupt in `xiom.graphql`'s validator on v0.62.3** -- `GraphQLSelection.Field(selection).name` reads empty/garbage (`|0|`), so a valid operation reports `field_check` failures. In-situ: source struct local reads `hello`; after `operation_add_field` the read-back from `op.selection_set.selections[0]` is `|0|`; constructed+matched in the test module it is empty; `Vec[StructType]` `Str` reads are correct (control) | in-situ instrumentation + controls in `xiom-graphql` tests; **all standalone shapes pass** (single-module, `derive[Clone]`, recursive payload->nested->Vec[enum], `&mut`+push, two-module scratch package) -- see `docs/repro/enum-payload-str/`; minimal repro pending (suspects the 5-field payload with two `Vec` fields + `selection_set` recursion) | until isolated: avoid reading `Str` out of enum payloads in affected shapes (parallel `Vec[Str]`/id scheme) or park; `xiom.graphql` remains WIP 9/10 | silently wrong validation results; blocks the `graphql`/`rest` restores. **Re-run the in-situ case on a build with m184+m185 (next release): both standalone shapes already pass, so this may have been a symptom of the m185 UB**. **RE-RAN 2026-10-04 on a local main build (m184..m187): STILL FAILS -- `validate valid operation` remains corrupt (`|0|`/empty read), so it is NOT an m185 symptom; in-situ evidence stands, minimal repro still pending** | 
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


