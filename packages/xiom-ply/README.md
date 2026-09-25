<!-- XIOM -- xiom.ply README -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.ply

> **Status:** `incubating` -- conformance-tested on compiler v0.61.3 (25/25);
> pure XIOM (no FFI); NOT published yet.
> **Scope:** PLY polygon file format, ASCII subset: header and body parsing,
> scalar value validation, structural accessors and canonical re-emission.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.ply` reads and writes the ASCII form of the PLY polygon file format
in memory, from a `Str` to a `PlyDoc` and back. It validates the full header
grammar (`ply`, `format ascii 1.0`, `comment`, `element <name> <count>`,
`property <type> <name>`, `end_header`), enforces the declared element layout
on every body row, and range-checks every integer value against its declared
scalar type.

Values are never converted: every body token is preserved verbatim as text,
so no precision is lost and no `Vec[Float64]` is needed (this compiler does
not support one). Integer properties additionally offer `ply_value_int`,
which turns the stored text into an `Int`; float/double values stay text and
are the caller's to decode. Parsed documents can be re-emitted in a canonical
form that round-trips byte-exact for canonical input.

## Install / use

The package is not published yet; build it from this repository with the
pinned compiler:

```
.\scripts\port.ps1 -Package xiom.ply
```

Once published, consumers add it to their manifest and use the module:

```
deps: { "xiom.ply": "0.1.0" };
```

## Quick start

```xi
use xiom.ply;
use xiom.io;
use xiom.convert;   // int_to_string

fn main() -> Int {
  let text = "ply\nformat ascii 1.0\ncomment example\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty uchar n\nproperty int v0\nproperty int v1\nproperty int v2\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n";
  let r = ply_parse(text);
  match r {
    Ok(doc) => {
      io.println(int_to_string(ply_element_count(&doc)));   // 2
      io.println(ply_element_name(&doc, 1));                // face
      io.println(ply_row_value(&doc, 0, 1, 0));             // 1 (vertex 1, x)
      io.println(ply_row_value(&doc, 0, 1, 2));             // 0 (vertex 1, z)
      let v = ply_value_int(&doc, 1, 0, 3);                 // face corner 2
      match v {
        Ok(idx) => { io.println(int_to_string(idx)); },     // 2
        Err(e) => { io.println(e); },
      }
      let rebuilt = ply_build(&doc);
      match rebuilt {
        Ok(out) => { io.println(out); },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API summary

| Function | Returns | Description |
|---|---|---|
| `ply_parse(text)` | `Result[PlyDoc, Str]` | Parse a whole ASCII PLY document (header and body). |
| `ply_build(doc)` | `Result[Str, Str]` | Canonical re-emission: header plus body rows, LF endings, one trailing LF. |
| `ply_build_header(doc)` | `Str` | Canonical header text only (`ply` through `end_header`). |
| `ply_element_count(doc)` | `Int` | Number of declared elements. |
| `ply_element_name(doc, e)` | `Str` | Name of element `e`; `""` out of range. |
| `ply_element_rows(doc, e)` | `Int` | Declared (and accepted) row count of element `e`; `0` out of range. |
| `ply_element_property_count(doc, e)` | `Int` | Properties of element `e`; `0` out of range. |
| `ply_element_property(doc, e, j)` | `Int` | Global property index of slot `j` in element `e`; `-1` out of range. |
| `ply_property_name(doc, p)` | `Str` | Name of global property `p`; `""` out of range. |
| `ply_property_type(doc, p)` | `Int` | Type code `1..8` of property `p`; `0` out of range. |
| `ply_property_element(doc, p)` | `Int` | Element owning property `p`; `-1` out of range. |
| `ply_property_index(doc, e, name)` | `Int` | Global index of the first property named `name` in element `e`; `-1` when absent. |
| `ply_token_count(doc)` | `Int` | Total body values stored. |
| `ply_comment_count(doc)` | `Int` | Comments preserved from the header. |
| `ply_comment(doc, i)` | `Str` | Text of comment `i`; `""` out of range. |
| `ply_row_value(doc, e, r, j)` | `Str` | Stored text token at row `r`, property slot `j`; `""` out of range. |
| `ply_value_int(doc, e, r, j)` | `Result[Int, Str]` | Integer conversion of a stored token (integer properties only). |
| `ply_type_name(code)` | `Str` | `"char"`..`"double"` for codes 1..8; `""` otherwise. |
| `ply_type_code(name)` | `Int` | Code 1..8 for the eight scalar names; `0` otherwise. |
| `ply_type_is_integer(code)` | `Bool` | True for `char`, `uchar`, `short`, `ushort`, `int`, `uint`. |

`PlyDoc` is a struct of flat parallel vectors (no `Vec[StructType]` in this
compiler): `elem_names`, `elem_counts`, `elem_prop_starts`, `elem_prop_ends`,
`prop_types`, `prop_names`, `comments` and `tokens`. Element `e` owns the
properties `[elem_prop_starts[e], elem_prop_ends[e])`; the tokens of element
`e` are the `elem_counts[e] * property_count(e)` consecutive entries of
`tokens` that follow the tokens of the earlier elements.

## Supported grammar

| Statement | Handling |
|---|---|
| `ply` | Required first line, exactly one token. |
| `format ascii 1.0` | Required second line, exactly these three tokens. |
| `comment <text>` | Preserved; text is trimmed; an empty text is allowed. |
| `element <name> <count>` | Declares `count` body rows; count is digits only, leading zeros allowed. |
| `property <type> <name>` | Scalar property of the enclosing element; eight types below. |
| `property list ...` | Rejected: `ply: unknown property type at line N`. |
| `end_header` | Ends the header; exactly one token. |
| body row | Exactly one whitespace-separated token per declared property, in declaration order. |
| anything else | Rejected, not skipped. |

Scalar types and integer ranges:

| Type | Code | Range | Validation |
|---|---|---|---|
| `char` | 1 | -128..127 | integer, range-checked |
| `uchar` | 2 | 0..255 | integer, range-checked |
| `short` | 3 | -32768..32767 | integer, range-checked |
| `ushort` | 4 | 0..65535 | integer, range-checked |
| `int` | 5 | -2147483648..2147483647 | integer, range-checked |
| `uint` | 6 | 0..4294967295 | integer, range-checked |
| `float` | 7 | IEEE-754 binary32 | syntax only, kept as text |
| `double` | 8 | IEEE-754 binary64 | syntax only, kept as text |

## Error model

Errors are `Result[..., Str]` with deterministic `ply: `-prefixed messages and
1-based physical line numbers; the first error stops the parse and no partial
document is returned.

| Message | Condition |
|---|---|
| `ply: missing magic` | no first line, or the first line is not exactly `ply`. |
| `ply: unsupported format line` | no second line, or it is not exactly `format ascii 1.0` (binary and other versions included). |
| `ply: unknown header record at line N` | unrecognized header keyword, an empty header line, or `end_header` with extra tokens. |
| `ply: malformed element at line N` | `element` without name/count, or a count that is not digits only. |
| `ply: malformed property at line N` | `property` with fewer than two tokens, a well-typed line with a wrong token count, or a property before the first element. |
| `ply: unknown property type at line N` | type token outside the eight scalar names (includes `list`). |
| `ply: missing end_header` | input ends while the header is open. |
| `ply: element count mismatch` | the body ends before every declared row was read. |
| `ply: row token-count mismatch at line N` | a row's token count differs from its element's property count. |
| `ply: malformed value at line N` | a token is not an integer (for integer types) or not a valid float (for `float`/`double`). |
| `ply: bad integer range at line N` | an integer token is outside its declared type range (or beyond Int64). |
| `ply: trailing rows at line N` | non-declared lines follow the last accepted row. |

`ply_build` fails with `ply: element count mismatch` when a document's
declared counts and token stream disagree; `ply_value_int` adds
`ply: property out of range`, `ply: value out of range`,
`ply: value is not an integer`, `ply: malformed value` and
`ply: bad integer range` for accessor misuse.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ply
```

Expected tail: 25 `[PASS]` lines, `xiom.ply: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ASCII only.** Binary PLY (`binary_little_endian`, `binary_big_endian`) is
  rejected as an unsupported format line.
- **Scalar properties only.** `property list` is not part of the subset
  (and fails as an unknown property type). Faces with varying arity cannot be
  represented directly; a document must declare a fixed-width scalar layout
  (for example `vertex_count` plus per-corner `int` slots) and mixed-size
  faces need their own layout or an outer format.
- **No topology and no geometry math.** There is no triangulation, adjacency,
  edge or normal computation, bounding box, deduplication or index
  remapping; only structure and scalar values.
- **Values stay text.** Integer conversion is explicit (`ply_value_int`);
  float and double values are never parsed, so there is no rounding,
  normalization or IEEE-754 special-value handling (`nan`, `inf` and hex
  floats are rejected as malformed tokens).
- **Strict parsing.** The first error aborts; element counts must match
  exactly; anything after the last declared row is `ply: trailing rows`; the
  only tolerated variations are CRLF, extra space/TAB separators, leading
  zeros in integers and comments anywhere in the header.
- **Canonical output.** `ply_build` always writes LF, single spaces and
  comments immediately after the format line, so byte-exact round-trips hold
  for canonical input; other input is normalized rather than refused.
- **Byte-oriented.** The input is treated as bytes; no UTF-8 decoding, no BOM
  stripping. Lines end at LF, and one CR immediately before the LF is
  dropped.
- **Whole-document, in-memory.** There is no streaming, file I/O or error
  recovery; the token stream is the size of the body.
- **Element counts are Int-sized.** A count is scanned as a non-negative
  Int64; values above that are a malformed element. Integer values allow at
  most 19 significant digits.

See `SPEC.md` for the exact grammar, type table, API contract, error catalog
and test matrix. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
