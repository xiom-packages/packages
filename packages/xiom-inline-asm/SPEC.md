# xiom.inline-asm -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `xiom.inline.asm` (`src/inline_asm.xi`). Pure XIOM, no FFI, no
codegen.

## 1. Scope

A parser and canonical formatter for inline-assembly templates, plus operand
constraint classification and clobber-list parsing:

- `asm_template_parse` reads one template `Str` into an `AsmTemplate`;
- accessors expose chunk kind, text, operand index, operand count, reference
  counts and the highest operand;
- builders (`asm_template_new`, `asm_template_push_literal`,
  `asm_template_push_operand`) construct a template without parsing;
- `asm_template_emit` serializes a template canonically;
- `asm_constraint_class` / `asm_constraint_is_output` /
  `asm_constraint_is_valid` classify constraint strings;
- `asm_clobbers_parse` / `asm_clobbers_emit` handle clobber lists.

The package is a front-end codec: it validates and structures template text,
and it never lowers, encodes, schedules or targets an instruction set.

## 2. Non-goals

- **No codegen or lowering**: no instruction selection, no encoding, no
  backend integration, no `lower`/`targets` functionality.
- **No register allocation**: no register names, classes or hints beyond the
  opaque constraint string and the clobber names.
- **No operand list semantics**: input/output/inout classification of
  *operands* is not modelled; only the constraint string on a template
  reference is stored (callers decide what it means).
- **No target dialects**: the template syntax is dialect-neutral; `%0`,
  `{0}` and other spellings are literal text.
- **No constraint dialect resolution**: classifications use the documented
  exact table (section 6); everything else is `unknown`.
- **No FFI, no file I/O, no assembly execution**; in-memory only.
- No error recovery: the first error aborts the parse with `Err`.

## 3. Data model

`AsmTemplate` is flat because XIOM v0.61.3 cannot hold `Vec[StructType]`:

```xi
pub type AsmTemplate = {
  kinds: Vec[Str];    // "lit" | "op"
  texts: Vec[Str];    // literal bytes (decoded) or the constraint string
  indexes: Vec[Int];  // operand index for "op", -1 for "lit"
  operand_count: Int; // highest referenced operand + 1 (0 when none)
}
```

Chunk `i` is `kinds[i]` / `texts[i]` / `indexes[i]`. The three parallel
vectors are index-aligned; every accessor operates on their shortest length
(`_chunk_count`), so a hand-built template can never be read out of range.
For an `"op"` chunk, `texts[i]` is the constraint string (possibly `""`);
for a `"lit"` chunk it is the literal bytes with every `$$` already decoded
to `$`.

## 4. Exact template grammar

```
template   = *( literal / "$$" / operand )
operand    = "$" digits / "${" digits [ ":" constraint ] "}"
literal    = any byte except "$"
digits     = 1*( "0".."9" )            value <= 1000000000
constraint = 1*( constraint-byte )
constraint-byte = "A".."Z" | "a".."z" | "0".."9" | "=" | "+" | "&" | "*"
                | "%" | "!" | "~" | "^" | "," | "." | "-" | "<" | ">"
```

There is no whitespace significance anywhere: spaces and tabs are ordinary
literal bytes.

## 5. Parsing rules and decisions

1. **Literal runs.** A maximal run of non-`$` bytes becomes one `"lit"`
   chunk, in source order.
2. **Dollar escaping.** `$$` contributes one literal `$` to the current
   literal run (it does not split the run); `$` not followed by `$`, a digit
   or `{` is an error.
3. **Short form.** `$` + digits is an operand with no constraint and no
   braces; the digits run ends at the first non-digit byte, so `$1x` is
   operand 1 followed by literal `x`.
4. **Braced form.** `${` + digits + optional `:` + constraint + `}`. The
   constraint, when the colon is present, must be non-empty and over the
   documented alphabet. `${0}` and `${0:r}` are both valid.
5. **Leading zeros.** Digit runs are decimal and may carry leading zeros:
   `$007` is operand 7. This is deliberate leniency; the canonical emitter
   writes the normalized number.
6. **Index guard.** A digit run whose value exceeds 1,000,000,000 is
   rejected (`operand index overflow`), so indexes cannot wrap.
7. **Literal braces.** `}` outside an operand is a literal byte; `{` outside
   `${` is a literal byte. Templates may contain unmatched braces.
8. **Empty template.** `""` parses to a template with zero chunks,
   `operand_count` 0 and `max_operand` `-1`; it emits `""`.
9. **No merging across operands.** An operand chunk always sits between two
   literal runs; the parser never merges the surrounding literals.
10. **Determinism.** The same input always yields the same template or the
    same first error; the input is never mutated.

## 6. Constraint classification

`asm_constraint_class(c)` strips leading output modifiers first (any run of
`=`, `+`, `&`), then matches the remainder exactly:

| Core | Class | Meaning |
|---|---|---|
| `""` (or only modifiers) | `none` | no constraint |
| `r` | `register` | general register |
| `m` | `memory` | memory operand |
| `o` | `offset_memory` | offsetable memory operand |
| `i` | `immediate` | immediate operand |
| `n` | `immediate_integer` | known-integer immediate |
| `g` | `general` | register, memory or immediate |
| `x` | `xmm_register` | SSE/XMM register |
| `rm` | `register_or_memory` | register or memory |
| anything else | `unknown` | not in the documented table |

`asm_constraint_is_output(c)` is true when the first byte is `=` (write-only)
or `+` (read-write); `&` (early-clobber) is not an output modifier for this
predicate. `asm_constraint_is_valid(c)` is true when `c` is non-empty and
every byte is in the alphabet of section 4.

## 7. Canonical emitter

`asm_template_emit(t)` walks the chunks in order:

- `"lit"`: the text verbatim, with every `$` doubled to `$$` (so a re-parse
  yields the identical literal text);
- `"op"`: `${` + the decimal index + (`:` + constraint when non-empty) +
  `}`. The braced form is always used, so an operand chunk immediately
  followed by a literal starting with a digit cannot merge on re-parse;
- unknown kinds are emitted as literals.

Adjacent literal chunks are emitted contiguously and therefore merge into
one chunk on re-parse; this is the only structural canonicalization besides
index normalization and brace insertion. `emit` is idempotent:
`emit(parse(emit(t))) == emit(t)`, and `parse(emit(t))` preserves the chunk
sequence after literal-run merging, every operand index and constraint, and
`operand_count`.

## 8. Error catalog

Template errors are `Err("asm: ...")`; `<pos>` is a byte offset into the
input. All operand-level errors report the offset of the operand's `$`,
except `bad constraint character`, which reports the offset of the offending
byte.

| Condition | Exact message |
|---|---|
| `$` at end of input | `asm: dangling '$' at <pos>` |
| `$x`, `${}`, `${:...}` (no digits after `$` / `${`) | `asm: bad operand index at <pos>` |
| Digit run exceeds 1,000,000,000 | `asm: operand index overflow at <pos>` |
| `${n` / `${n:c` (no closing `}`) | `asm: unterminated operand at <pos>` |
| `${n:}` (colon directly before `}`) | `asm: empty constraint at <pos>` |
| `${n:@}`, `${n:r@}`, `${nx}` (byte outside the alphabet) | `asm: bad constraint character at <pos>` |

Clobber errors are `Err("asm: ...")`; `<pos>` is the byte offset of the
offending entry or byte:

| Condition | Exact message |
|---|---|
| Empty entry (`a,,b`, `,`, trailing comma) | `asm: empty clobber at <pos>` |
| Byte outside `[A-Za-z0-9_.]` | `asm: bad clobber character at <pos>` |
| Repeated name (case-sensitive) | `asm: duplicate clobber at <pos>` |

`asm_clobbers_parse("")` and a whitespace-only text are valid and yield zero
names.

## 9. API contract

```xi
pub fn asm_template_parse(text: Str) -> Result[AsmTemplate, Str]
pub fn asm_template_new() -> AsmTemplate
pub fn asm_template_push_literal(t: &mut AsmTemplate, text: Str)
pub fn asm_template_push_operand(t: &mut AsmTemplate, index: Int, constraint: Str)
pub fn asm_template_chunk_count(t: &AsmTemplate) -> Int
pub fn asm_template_operand_count(t: &AsmTemplate) -> Int
pub fn asm_template_kind(t: &AsmTemplate, i: Int) -> Str
pub fn asm_template_text(t: &AsmTemplate, i: Int) -> Str
pub fn asm_template_index(t: &AsmTemplate, i: Int) -> Int
pub fn asm_template_uses(t: &AsmTemplate, index: Int) -> Int
pub fn asm_template_max_operand(t: &AsmTemplate) -> Int
pub fn asm_template_emit(t: &AsmTemplate) -> Str
pub fn asm_constraint_class(c: Str) -> Str
pub fn asm_constraint_is_output(c: Str) -> Bool
pub fn asm_constraint_is_valid(c: Str) -> Bool
pub fn asm_clobbers_parse(text: Str) -> Result[Vec[Str], Str]
pub fn asm_clobbers_emit(names: &Vec[Str]) -> Str
```

Out-of-range accessors: `asm_template_kind` / `asm_template_text` -> `""`,
`asm_template_index` -> `-1`, `asm_template_uses(<negative>)` -> `0`.

Builders are deliberately unvalidated: `push_literal` ignores empty text,
`push_operand` ignores negative indexes and stores the constraint verbatim
(an out-of-alphabet constraint or an oversized index is emitted as given and
may not re-parse). Complexity: parsing and emission are O(input length);
accessors are O(1) except `uses` / `max_operand`, which are O(chunks);
clobber parsing is O(input length * entries).

## 10. Test matrix

`tests/test_conformance.xi` (module `inline_asm_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All string comparisons go through `str_compare`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | mixed template | rules 1, 3, 4, 9 |
| t2 | `$n` / `${n}` / leading zeros | rules 3, 4, 5 |
| t3 | `$$` decoding | rule 2 |
| t4 | literal braces/commas/percent | rule 7 |
| t5 | empty and literal-only inputs | rule 8 |
| t6 | constraint classes | section 6 |
| t7 | constraint validity | section 6 alphabet |
| t8 | output modifiers | section 6 |
| t9 | canonical bracing | section 7 |
| t10 | dollar re-escaping | section 7 |
| t11 | round trips | sections 5, 7 |
| t12 | dangling `$` | catalog |
| t13 | bad operand index | catalog |
| t14 | unterminated operand | catalog |
| t15 | empty constraint | catalog |
| t16 | bad constraint character | catalog |
| t17 | index overflow | rule 6 |
| t18 | accessor bounds | section 9 |
| t19 | clobber split/trim | section 8 |
| t20 | clobber errors | section 8 |
| t21 | clobber emit round trip | section 8 |
| t22 | builder | section 9 |
| t23 | operand use counting | section 5 |
| t24 | modifier constraint round trip | sections 4, 6 |

## 11. Known limitations

- No lowering, targets, register allocation or operand-list semantics.
- Constraint classification is an exact-match table; combined dialect
  constraints are `unknown`.
- Operand indexes are capped at 1,000,000,000; larger values are rejected
  rather than wrapped.
- Builders do not validate; only `asm_template_parse` produces templates
  whose canonical emission is guaranteed to re-parse.
- Clobber names are not resolved to registers or register classes.
- Literal-run merging means a hand-built template with two adjacent literal
  chunks re-parses into one chunk (the emitted bytes are unchanged).

## 12. Compiler / stdlib notes (v0.61.3)

Free functions only, flat parallel `Vec`s instead of `Vec[StructType]`,
byte-wise scanning with `xiom.string.byte_at` / `str_slice`, and `Result`
construction confined to the leaf helpers `_ok_template` / `_err_template` /
`_ok_names` / `_err_names`. Every `Str` read from a `Vec[Str]` element is
bound to a typed local and compared with `str_compare` (BUG 17), `Int`
element reads are bound to typed locals before comparison, and widened bytes
are masked (`(b as Int) & 0xFF`). No `&struct.field` is passed as a `&Vec`
parameter; literal accumulation uses the proven `Vec[UInt8]` +
`Str::from_utf8` pattern of the sibling packages. No compiler workarounds
beyond these documented patterns were required.

## Contracts (batch #32 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/inline_asm.xi` in the
batch #32 hardening pass (compiler v0.64.0; `package.xi` is bumped by the
coordinator at integration). 36 clauses across the 17 public entry points;
all are `ensures:` (no `requires:`), so the accepted-input domain is
unchanged. Two consecutive `& .\scripts\port.ps1 -Package xiom.inline-asm
-TimeoutSec 60` runs ended `port: PASS (passed=24 failed=0 program_exit=0
exit=0)` with the clauses active (5.6 s and 5.1 s); the 24-check
conformance suite exercises every entry point and no clause trapped. No
clause was dropped and none was probe-gated.

"Z3-provable" marks the scalar-shape family the SMT backend can discharge
without executing the function; runtime-checked clauses read `Str`/`Vec`
lengths, `@pre` snapshots through `&mut`, or public accessor cross-calls on
a struct result. The only cross-call used in a clause is the public
`asm_template_chunk_count(t)`; the private `_chunk_count` never appears in
a clause.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `asm_template_parse` | `ensures: text.len() == 0 => result is Ok`; `ensures: result is Err => text.len() > 0` | Z3-provable (guard pair; `Result` tag + `Str` length) |
| `asm_template_new` | `ensures: asm_template_chunk_count(result) == 0`; `ensures: asm_template_operand_count(result) == 0` | runtime-checked (struct result via public accessor cross-calls) |
| `asm_template_push_literal` | `ensures: text.len() == 0 => t.kinds.len() == t.kinds.len()@pre`; `ensures: t.kinds.len() <= t.kinds.len()@pre + 1` | runtime-checked (`@pre` length frame through `&mut`) |
| `asm_template_push_operand` | `ensures: index < 0 => t.kinds.len() == t.kinds.len()@pre`; `ensures: index >= 0 => t.kinds.len() == t.kinds.len()@pre + 1`; `ensures: t.operand_count >= t.operand_count@pre` | runtime-checked (`@pre` length/count frames through `&mut`) |
| `asm_template_chunk_count` | `ensures: result >= 0`; `ensures: result <= t.kinds.len()` | Z3-provable (scalar-shape count) |
| `asm_template_operand_count` | `ensures: result >= 0` | Z3-provable (pure scalar) |
| `asm_template_kind` | `ensures: i < 0 => result.len() == 0`; `ensures: i >= asm_template_chunk_count(t) => result.len() == 0`; `ensures: result.len() > 0 => i >= 0 && i < asm_template_chunk_count(t)` | runtime-checked (empty-`Str` sentinel trio; public chunk-count cross-call) |
| `asm_template_text` | `ensures: i < 0 => result.len() == 0`; `ensures: i >= asm_template_chunk_count(t) => result.len() == 0`; `ensures: result.len() > 0 => i >= 0 && i < asm_template_chunk_count(t)` | runtime-checked (empty-`Str` sentinel trio; public chunk-count cross-call) |
| `asm_template_index` | `ensures: i < 0 => result == -1`; `ensures: i >= asm_template_chunk_count(t) => result == -1`; `ensures: result != -1 => i >= 0 && i < asm_template_chunk_count(t)` | runtime-checked (-1 sentinel trio; public chunk-count cross-call) |
| `asm_template_uses` | `ensures: index < 0 => result == 0`; `ensures: result >= 0`; `ensures: result <= asm_template_chunk_count(t)` | runtime-checked (count + public chunk-count cross-call) |
| `asm_template_max_operand` | `ensures: result >= -1`; `ensures: asm_template_chunk_count(t) == 0 => result == -1` | runtime-checked (empty-guard + public chunk-count cross-call) |
| `asm_template_emit` | `ensures: asm_template_chunk_count(t) == 0 => result.len() == 0` | runtime-checked (empty-guard only) |
| `asm_constraint_class` | `ensures: result.len() > 0`; `ensures: c.len() == 0 => result.len() == 4` | runtime-checked (`Str` lengths; `"none"` is 4 bytes) |
| `asm_constraint_is_output` | `ensures: c.len() == 0 => !result`; `ensures: result => c.len() > 0` | Z3-provable (guard pair on `Str` length) |
| `asm_constraint_is_valid` | `ensures: c.len() == 0 => !result`; `ensures: result => c.len() > 0` | Z3-provable (guard pair on `Str` length) |
| `asm_clobbers_parse` | `ensures: text.len() == 0 => result is Ok`; `ensures: result is Err => text.len() > 0` | Z3-provable (guard pair; `Result` tag + `Str` length) |
| `asm_clobbers_emit` | `ensures: names.len() == 0 => result.len() == 0` | runtime-checked (empty-guard only) |

Deliberately not claimed: `Str` equality (BUG 17; only `.len()`); literal
text identity or round-trip clauses; vector indexing anywhere in a clause;
`result.value` payload field reads; struct-result payload field reads; any
clause calling a function that wraps its callee. `asm_template_emit` and
`asm_clobbers_emit` carry only their empty-guard clause, and no clause
strengthens a guard beyond what hand-built structs satisfy.
