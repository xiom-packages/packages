# xiom.hcl

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** structural HCL2 subset parsing and canonical emitting;
> in-memory `Str` only, expressions are captured raw and never evaluated.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.hcl` parses a documented HCL2 subset into a flat `HclDoc`: attributes
(`name = <expression>`, expression captured as raw text through nested
strings and brackets), blocks (`type "label" "label2" { ... }`, nested to any
depth), all three HCL comment forms, and whitespace/newline tolerance. It
exposes counts, per-body navigation (parent index, child blocks, child
attributes, body byte ranges) and first-match attribute lookup, and emits a
canonical form with two-space indentation. Everything is structural: nothing
is evaluated, no schema is applied, and no files are read.

## API

| Function | Returns | Description |
|---|---|---|
| `hcl_parse(text)` | `Result[HclDoc, Str]` | Parse a whole document; `Err("hcl: ...")` on a syntax error. |
| `hcl_emit(d)` | `Str` | Canonical text: 2-space indent, `name = value`, `type "label" {`, `{}` for empty bodies, LF line endings. |
| `hcl_attr_count(d)` / `hcl_attr_count_in(d, parent)` | `Int` | Top-level / per-body attribute count. |
| `hcl_block_count(d)` / `hcl_block_count_in(d, parent)` | `Int` | Top-level / per-body block count. |
| `hcl_attr_total(d)` / `hcl_block_total(d)` | `Int` | Totals across all nesting levels. |
| `hcl_attr_name/value/line/parent(d, idx)` | `Str`/`Str`/`Int`/`Int` | Attribute fields; parent is the owning block (`-1` top level). |
| `hcl_attr_lookup(d, name)` | `Int` | Index of the first top-level attribute with that name, or `-1`. |
| `hcl_attr_lookup_in(d, block, name)` | `Int` | Same, scoped to one body. |
| `hcl_attr_value_in(d, block, name)` | `Option[Str]` | Value of the first matching attribute, or `None`. |
| `hcl_block_type/label_count/parent/line(d, idx)` | `Str`/`Int`/`Int`/`Int` | Block fields; parent `-1` means top level. |
| `hcl_block_label(d, idx, k)` / `hcl_block_labels(d, idx)` | `Str` / `Vec[Str]` | Decoded labels in header order. |
| `hcl_block_body(d, idx)` | `Str` | Verbatim source text between the block's braces. |
| `hcl_block_body_start/end(d, idx)` | `Int` | Byte offsets of the body range (`{`-exclusive / `}`-inclusive). |
| `hcl_child_block/attr(d, block, k)` | `Int` | Global index of the k-th direct child, or `-1`. |
| `hcl_child_total(d, block)` | `Int` | Direct child count (attributes plus blocks). |

## Usage

```xi
use xiom.hcl;
use xiom.io;

fn main() -> Int {
  let src = "resource \"aws_instance\" \"web\" {\n  ami = \"ami-1\"\n\n  tags = {\n    env = \"prod\"\n  }\n}\n";
  let r = hcl_parse(src);
  match r {
    Ok(d) => {
      io.println(hcl_block_type(&d, 0));            // resource
      io.println(hcl_block_label(&d, 0, 1));        // web
      match hcl_attr_value_in(&d, 0, "ami") {
        Some(v) => { io.println(v); },              // "ami-1"
        None => {},
      }
      io.println(hcl_emit(&d));                     // canonical text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.hcl
```

Expected tail: 26 `[PASS]` lines, `xiom.hcl: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- No expression evaluation, type checking or schema validation: values are raw
  text and `hcl_emit` writes them back verbatim.
- No heredocs (`<<EOF`, `<<-EOF`), no functions/for-expressions, no
  interpolation; a heredoc is rejected with
  `hcl: heredocs are not supported at line N`.
- Comments are parsed and dropped; emit never writes comments and normalizes
  whitespace, so only canonical input round-trips byte-for-byte.
- Duplicate attributes in one body are allowed and `hcl_attr_lookup` returns
  the first; duplicate labels inside one block header are an error, while
  repeated blocks with identical type and labels are allowed.
- Only `\"` and `\\` escapes are recognized in block labels; expressions are
  raw text, so string escapes inside them are not decoded.
- Unquoted `//` starts a comment, so quote URLs; a `#` or `/*` at bracket
  depth 0 likewise ends the expression text.
- NUL bytes anywhere in the input are rejected
  (`hcl: NUL byte in input at line N`) so `sb_to_str` can never truncate.
- No file I/O and no registry integration; errors carry 1-based line numbers
  but no columns.

See `SPEC.md` for the full grammar, storage invariants, error strings and
test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
