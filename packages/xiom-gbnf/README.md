# xiom.gbnf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** parse, validate and canonically re-emit GBNF grammars (the
> llama.cpp grammar format) for a documented subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.gbnf` is a byte-wise codec for GBNF grammar text. `gbnf_parse` reads a
grammar into an ordered rule list with one flat expression tree per rule;
`gbnf_emit` renders a parsed grammar back to canonical GBNF text, so
parse -> emit -> parse is stable. Validation is conservative: malformed
constructs, duplicate rule names and unresolved rule references are rejected
with deterministic `Err("gbnf: ...")` messages that carry byte offsets. There
is no left-recursion or reachability analysis and no sample generation or
inference -- see `SPEC.md` for the full grammar, error catalog and non-goals.

Supported constructs: `name ::= alternates` rules; `|` alternation; sequences;
`"..."` string literals with `\"` `\\` `\n` `\t` `\r` and `\xNN` escapes;
character classes `[a-z]` / `[^...]` with `-` ranges and the same escapes plus
`\]` `\-` `\^`; `*` `+` `?` repetition; `( )` grouping; rule references; `#`
comments to end of line; free whitespace and newlines.

## API

| Function | Returns | Description |
|---|---|---|
| `gbnf_parse(text)` | `Result[GbnfGrammar, Str]` | Parse and validate a whole grammar; `Err("gbnf: ...")` on malformed input, duplicates or unresolved references. |
| `gbnf_validate(text)` | `Result[Int, Str]` | Parse and validate without keeping the grammar; `Ok(rule_count)` or the same `Err` messages. |
| `gbnf_emit(g)` | `Str` | Canonical GBNF text: one `name ::= expression` line per rule, normalized whitespace, no comments; `""` for an empty grammar. |
| `gbnf_rule_count(g)` | `Int` | Number of rules in definition order. |
| `gbnf_rule_name(g, i)` | `Str` | Name of rule `i`; `""` out of range. |
| `gbnf_root_name(g)` | `Str` | Name of the first rule (root by convention); `""` for an empty grammar. |
| `gbnf_has_rule(g, name)` | `Bool` | True when the rule name is defined (exact, case-sensitive). |
| `gbnf_node_count(g, i)` | `Int` | Nodes in rule `i`'s expression tree; `-1` out of range. |
| `gbnf_rule_refs(g, i)` | `Vec[Str]` | Rule names referenced by rule `i`, source order, duplicates kept; empty out of range. |

`GbnfGrammar` stores the rule list (`names` / `roots` / `rule_starts`) over one
flat expression-tree pool (`node_kinds`, `node_texts`, `node_starts`,
`node_counts`, `node_children`). Nodes are postfix (children before parents).
`Vec[StructType]` is unsupported in this compiler, so the tree is eight
parallel vectors instead of node objects.

## Usage

```xi
use xiom.gbnf;
use xiom.io;

fn main() -> Int {
  let r = gbnf_parse("# expr\nroot ::= term (\"+\" term)*\nterm ::= [0-9]+ | \"(\" root \")\"\n");
  match r {
    Ok(g) => {
      io.println(gbnf_rule_count(&g));          // 2
      io.println(gbnf_rule_name(&g, 0));        // root
      io.println(gbnf_has_rule(&g, "term"));    // true
      io.println(gbnf_emit(&g));                // canonical text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.gbnf
```

Expected tail: 30 `[PASS]` lines, `xiom.gbnf: all tests passed`, then
`port: PASS (passed=30 failed=0 program_exit=0 exit=0)`.

## Error model

Every failure is `Err(Str)` whose message starts with `"gbnf: "` and, for
parse-time failures, ends with the offending byte offset. Messages are fixed
text, so callers may match them exactly. Duplicate rules and unresolved
references are grammar-level errors: duplicates are reported while reading the
rule list (at the start of the duplicate name), references are resolved only
after the whole grammar is read, so forward references are legal.

`gbnf_validate` is a thin wrapper over `gbnf_parse`; it exists so consumers can
check a grammar without holding the parsed structure.

## Limitations

- Documented subset only: no `\uNNNN` escapes, no `{m,n}` repetition bounds
  and no `.` (any-character) wildcard. See `SPEC.md` for the exact grammar.
- `\x00` is rejected inside string literals because XIOM `Str` cannot carry a
  NUL byte. It is accepted inside character classes (`[\x00-\x1f]`), whose
  canonical spelling stays ASCII.
- Conservative validation only: no left-recursion analysis, no reachability or
  unused-rule diagnostics, no ambiguity checks.
- No generation, sampling, inference or matching engine: this package only
  parses, validates and re-emits grammar text.
- Canonical emission drops comments, normalizes whitespace and rewrites escapes
  (`\x4a` prints as `J`, `[A-z]` ranges keep their endpoints); it is stable
  under parse -> emit -> parse but not byte-identical to arbitrary input.
- A rule body ends at the next `name ::=`, so a reference cannot directly
  precede a new rule definition on the same line without ambiguity.

See `SPEC.md` for the exact grammar, data model, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
