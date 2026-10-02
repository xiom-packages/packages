# xiom.inline-asm

> **Status:** `stable` -- conformance-tested (24/24); published at `v0.1.1` on the XIOM registry.
> **Scope:** inline-assembly template parsing, operand constraint
> classification and clobber-list parsing for the dialect-neutral subset in
> `SPEC.md`; no codegen, no lowering, no target backends.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.
>
> Naming note: the manifest name is `xiom.inline-asm`; the module is
> `xiom.inline.asm` because v0.61.3 module names cannot contain `-`.

## What it is

`xiom.inline-asm` parses an inline-assembly template string into a flat
`AsmTemplate` and answers the structural questions a compiler front end asks
before lowering: which operands a template references, at which positions,
with which constraint strings, and where the literal text sits. It also
classifies operand constraints and parses clobber lists. It is a pure text
codec: it never executes, encodes or targets an instruction set.

Supported template syntax (documented subset):

```
template = *( literal / "$$" / operand )
operand  = "$" digits / "${" digits [ ":" constraint ] "}"
```

- `$0`, `$12` -- positional operand reference, short form;
- `${0}`, `${12}` -- positional reference, braced form (required when the
  literal text that follows starts with a digit);
- `${0:r}`, `${0:=r}` -- positional reference with a constraint string;
- `$$` -- one literal dollar sign;
- every other byte (including `{`, `}`, `,`, `%`) is literal text.

`asm_template_emit` writes a canonical form: operands are always braced
(`${n}` / `${n:c}`) and every literal `$` is written `$$`, so
`parse -> emit -> parse` is structure-preserving and `emit` idempotent.

## API

| Function | Returns | Description |
|---|---|---|
| `asm_template_parse(text)` | `Result[AsmTemplate, Str]` | Parse a template; `Err` carries an `asm: ...` message with a byte offset. |
| `asm_template_new()` | `AsmTemplate` | An empty template. |
| `asm_template_push_literal(t, text)` | nothing | Append a literal chunk; empty text is ignored. |
| `asm_template_push_operand(t, index, constraint)` | nothing | Append an operand chunk; negative indexes are ignored. |
| `asm_template_chunk_count(t)` | `Int` | Number of literal/operand chunks. |
| `asm_template_operand_count(t)` | `Int` | Distinct operands referenced (highest index + 1). |
| `asm_template_kind(t, i)` | `Str` | `"lit"` or `"op"`; `""` out of range. |
| `asm_template_text(t, i)` | `Str` | Literal bytes (decoded) or constraint; `""` out of range. |
| `asm_template_index(t, i)` | `Int` | Operand index, `-1` for literals and out of range. |
| `asm_template_uses(t, index)` | `Int` | Times an operand is referenced; `0` for a negative index. |
| `asm_template_max_operand(t)` | `Int` | Highest operand index; `-1` when none. |
| `asm_template_emit(t)` | `Str` | Canonical template text. |
| `asm_constraint_class(c)` | `Str` | `none` / `register` / `memory` / `offset_memory` / `immediate` / `immediate_integer` / `general` / `xmm_register` / `register_or_memory` / `unknown`. |
| `asm_constraint_is_output(c)` | `Bool` | True when `c` starts with `=` or `+`. |
| `asm_constraint_is_valid(c)` | `Bool` | True when `c` is non-empty over the documented alphabet. |
| `asm_clobbers_parse(text)` | `Result[Vec[Str], Str]` | Comma-separated clobber names; duplicates, empty entries and bad bytes are `Err`. |
| `asm_clobbers_emit(names)` | `Str` | Names joined with `", "`. |

## Usage

```xi
use xiom.inline.asm;
use xiom.io;

fn main() -> Int {
  let r = asm_template_parse("${0:r} = ${1:r} + ${2:i}");
  match r {
    Ok(t) => {
      io.println(asm_template_operand_count(&t));   // 3
      io.println(asm_template_uses(&t, 1));         // 1
      io.println(asm_constraint_class(asm_template_text(&t, 2))); // immediate
      io.println(asm_template_emit(&t));            // canonical replay
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.inline-asm
```

Expected tail: 24 `[PASS]` lines, `xiom.inline-asm: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- No codegen, lowering, register allocation or target-specific behaviour:
  the template is opaque text plus structure.
- No operand *definitions* (input/output/inout lists) and no implicit
  operand numbering beyond the template's own references; `push_operand`
  stores what it is given, unvalidated.
- Constraint strings are classified by the documented exact-match table;
  combined or target-specific constraint dialects report `unknown` (the
  validity check still accepts them).
- Clobber names are identifiers only (`[A-Za-z0-9_.]`); no alias resolution
  or register-class expansion happens.
- An operand index is capped at 1,000,000,000 by the overflow guard.
- In-memory only: no file I/O, no FFI.

See `SPEC.md` for the exact grammar, error catalog and test matrix. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
