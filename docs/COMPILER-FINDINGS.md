# Compiler findings from the packages lane

Findings collected while building conformance-tested packages with the
installed toolchain (v0.61.3). The packages lane cannot fix these; the
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
  CSE/sign-bit still queue items. Fleet-wide strict-clause sweep launched.
