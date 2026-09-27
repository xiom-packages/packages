# Compiler findings from the packages lane

Findings collected while building conformance-tested packages with the
installed toolchain (v0.61.3). The packages lane cannot fix these; the
compiler session triages. Format: `| Date | Finding | Evidence | Workaround in packages | Impact |`

## Open findings

| Date | Finding | Evidence | Workaround in packages | Impact |
|---|---|---|---|---|
| 2026-09-26 | `&mut Int` write-through miscompiles: assignments to a `&mut Int` parameter do not reach the caller | `xiom-upnp/src/upnp.xi` `_version_parts` (fixed): callers kept `-1` after the callee wrote the value; documented independently in `xiom-optimizer` ("the v0.61.3 `&mut Int` calling convention miscompiles simple write-through") | return a plain struct by value (`VersionParts`); `xiom-gbnf` uses `*pos = *pos + 1` deref writes (works there, not in upnp) | silent wrong values; one package already shipped this pattern and needed a rewrite | 
| 2026-09-26 | Loop-carried CSE miscompile: a value derived from a loop variable reuses the first iteration's result | `xiom-amqp/src/amqp.xi:1266` (documented): `ends.push(pos + 4 + sub_len)` returned the first container's end offset in the second iteration, so any two field-tables/arrays in one parent failed `bad table`/`bad array`; found by byte-level bisection | recursive per-container decode function instead of a loop-carried stack | silent wrong offsets; hard to diagnose | 
| 2026-09-25 | Mixed-bracket typos compile silently: `Vec<UInt8>`, `Vec<UInt8]`, `Result<Int]` are accepted | every wave: the file-write tooling reintroduced them (`gif` 16 sites, `mp3`, `flac`, `jpeg`, `sd` 7 sites, `nats` 18 sites, `mongo` 2 authoring waves, `tor` 6 sites) | mandatory `Select-String 'Vec<|Result<'` after every write and after green | shape-only; hides real corruption risk | 
| 2026-09-26 | No `Vec[Float64]`; no `Int <-> Float64` bitcast in v0.61.3 | `xiom-avro`, `xiom-mkv`, `xiom-amqp` docs; scalar `Float64` works | float/double exposed as raw LE octets; EBML floats decoded as integer milli-units | blocks float-bearing formats from full fidelity (see `docs/STDLIB-WISHLIST.md` `xiom.float`) | 
| 2026-09-24 | Bit tests on values with the sign bit set are unreliable | `xiom-can`/`xiom-radiotap` notes carried into wave-34/35 briefs; `xiom-sd`/`xiom-eeprom` prefer divisor/modulo extraction | divisor/modulo arithmetic for bit extraction | silent wrong bits | 
| 2026-09-25 | `byte_at(...)` compared to UInt8 constants >= 128 mis-lowers; widening + masking needed | documented trap 3; `png` signature byte 0x89, `jpeg` markers, `ldap` tags 0xA0+ | `(x as Int) & 0xFF` everywhere | silent false compares | 
| 2026-09-25 | `Str` from `Vec[Str]` elements: `==`/`!=` compare pointers; `str_len`/`.len()` unreliable | documented trap 1; test-side slips found in `upnp` t18 | `str_compare` + typed locals | silent wrong compares | 
| 2026-09-22 | Compiler does not validate arity of user function calls | documented trap 14 family | manual argument-count review; grep audits | calls compile with wrong arity | 
| 2026-09-22 | `as` is a reserved keyword; `int_to_base` lives in `xiom.convert.int` (not `xiom.convert`) | documented trap 17 | import discipline | compile errors only | 
| 2026-09-22 | `Int` division truncates toward zero; `(a+b-1)/b` is wrong for negative numerators | documented trap 18 | `q=a/b; r=a%b; if r>0 {q+1} else {q}` | silent wrong ceil | 
| 2026-09-27 | No `Vec[StructType]` (trap 10): struct payload lists need parallel `Vec` fields | `nats` (op stream parsed op-by-op), `i2c` (transaction events modeled as two mirrored `Vec[Int]` arrays) | mirrored parallel Vecs + index discipline | structural noise, drift risk (trap 16) | 
| 2026-09-27 | No auto-borrow at call sites: `&Struct` parameters require an explicit `&op`; omitting it raises E001 moved-value advisories | `nats` tests: 57 E001 "moved value" warnings until helpers took `&NatsOp` and every call site passed `&op` | explicit `&` at every call site | advisory only, but noisy suites; easy to mistake for a real move | 
| 2026-09-27 | Module-level `const` arrays / table initializers mis-materialize | `merkle`: the 64 SHA-256 K constants are rebuilt into a runtime `Vec[Int]` on every hash; `l10n-currency`: the 165-row ISO 4217 table is compiled into comparison chains instead of a module table | rebuild constants at runtime; comparison chains / accessor switches | performance and code size, no correctness impact | 
| 2026-09-27 | No function overloading; a later same-named function silently shadows an earlier definition (no redefinition error) | `l10n-currency`: two `_row` functions (different arities) produced 167 cascading `expected Int, found Str` errors at unrelated call sites until renamed to `_mk_row` | unique function names per module | confusing error storms; possible silent wrong dispatch in other shapes | 

## Compiler-lane triage and incoming fixes (2026-09-27)

Compiler lane triage relayed to packages (severity order for their follow-ups):
1. `&mut Int` write-through miscompile (row above; `xiom.upnp` rewrite evidence).
2. Loop-carried CSE miscompile (`xiom.amqp` recursive-decode workaround).
3. Sign-bit masking and mixed-bracket silent acceptance (parser diagnostic).
4. `byte_at(...)` vs `UInt8 >= 128` widening.

**Row 8 (arity validation) is reported FIXED by the compiler item-3 batch.**
Packages-side re-test is committed at `docs/repro/arity-laxness/`
(`control_exact_arity.xi` must stay green; `repro_missing_arg.xi` and
`repro_extra_arg.xi` must fail to compile once the next build is installed).
Re-run after the commit lands and update this file; the compiler lane will
relay a short resolution note.

## Resolved / withdrawn

| Date | Finding | Resolution |
|---|---|---|
| 2026-09-26 | "`Vec[Int]` element reads mis-lower to Str compares" | still listed as a trap; no new evidence this session -- keep the typed-local discipline |
| 2026-09-25 | `xiom.gguf` CRC-of-self trap | package-level logic, not compiler (docs/failed_attempts.md) |

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
