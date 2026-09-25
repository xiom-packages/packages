# xiom.nbt

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Minecraft NBT (Named Binary Tag) encoding and decoding
> for tag types 1-12: byte, short, int, long, float, double, byte array,
> string, list, compound, int array, long array.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`, `xiom.convert`; tests add `xiom.test`, `xiom.io`,
> `xiom.encoding.hex`).
> No FFI.

## What it is

`xiom.nbt` is a dependency-light NBT codec. `nbt_decode` validates a complete
big-endian NBT document (root TAG_Compound, exact buffer size, bounded
nesting) into an `NbtTree`, a flat node store built from parallel vectors
with contiguous child ranges -- no `Vec[StructType]` tree, no recursion in
the data model. Navigation accessors (`nbt_find_child`, `nbt_child_at`,
`nbt_list_len`, ...) and typed readers (`nbt_get_int`, `nbt_get_str`, ...)
walk that store. The `nbt_add_*` functions build a tree from scratch and
`nbt_encode` writes it back; a decoded document re-encodes byte-for-byte.

Region files, chunk compression (gzip/zlib), schemas and Bedrock
little-endian variants are out of scope (see Limitations).

## API

Tag constants: `NBT_TAG_BYTE` (1) ... `NBT_TAG_LONG_ARRAY` (12),
`NBT_TAG_END` (0), `NBT_MAX_DEPTH` (64).

| Function | Returns | Description |
|---|---|---|
| `nbt_decode(data)` | `Result[NbtTree, Str]` | Decode one complete document (root must be a compound). |
| `nbt_encode(&mut tree)` | `Result[Vec[UInt8], Str]` | Finalize and write a complete document. |
| `nbt_tree_new()` | `NbtTree` | Empty store. |
| `nbt_finalize(&mut tree)` | -- | Rebuild child ranges from parent links. |
| `nbt_add_compound(&mut tree, parent, name)` | `Int` | Add TAG_Compound; parent `-1` for the root. |
| `nbt_add_list(&mut tree, parent, name, elem_type)` | `Int` | Add TAG_List with the declared element type. |
| `nbt_add_byte/short/int/long(&mut tree, parent, name, v)` | `Int` | Add a signed scalar. |
| `nbt_add_float_bits/double_bits(&mut tree, parent, name, bits)` | `Int` | Add a float/double from raw IEEE-754 bits. |
| `nbt_add_str(&mut tree, parent, name, v)` | `Int` | Add TAG_String (u16 length limit at encode). |
| `nbt_add_byte_array/int_array/long_array(&mut tree, parent, name, v)` | `Int` | Add an array tag. |
| `nbt_node_count(&tree)` | `Int` | Number of nodes. |
| `nbt_root(&tree)` | `Int` | Root node index (`-1` when empty). |
| `nbt_tag_type(&tree, node)` | `Int` | Tag type 1-12 (`-1` out of range). |
| `nbt_name(&tree, node)` | `Str` | Node name ("" for list elements). |
| `nbt_parent(&tree, node)` | `Int` | Parent index (`-1` for the root). |
| `nbt_child_count(&tree, node)` | `Int` | Number of children. |
| `nbt_child_at(&tree, node, index)` | `Int` | Child index at `index` (`-1` out of range). |
| `nbt_find_child(&tree, node, name)` | `Int` | First child with that name (`-1` absent). |
| `nbt_list_len(&tree, node)` | `Result[Int, Str]` | TAG_List element count. |
| `nbt_list_element_type(&tree, node)` | `Result[Int, Str]` | Declared list element type (0 = empty). |
| `nbt_list_item(&tree, node, index)` | `Result[Int, Str]` | Element node index at `index`. |
| `nbt_get_byte/short/int/long(&tree, node)` | `Result[Int, Str]` | Signed scalar readers. |
| `nbt_get_float_bits/double_bits(&tree, node)` | `Result[Int, Str]` | Raw IEEE-754 bit patterns. |
| `nbt_get_str(&tree, node)` | `Result[Str, Str]` | UTF-8 string payload. |
| `nbt_get_byte_array(&tree, node)` | `Result[Vec[UInt8], Str]` | Byte array copy. |
| `nbt_get_int_array/long_array(&tree, node)` | `Result[Vec[Int], Str]` | Array copies, sign-decoded. |

## Error model

All failures are `Err(Str)` with deterministic text (full table in SPEC.md):
`nbt: truncated buffer`, `nbt: unknown tag type N`,
`nbt: string length overrun`, `nbt: negative length`,
`nbt: depth exceeded`, `nbt: trailing bytes`,
`nbt: list element type mismatch`, `nbt: root tag is not a compound`,
`nbt: empty tree`, `nbt: node index out of range`,
`nbt: list index out of range`, `nbt: unexpected tag type N`,
`nbt: invalid node structure`.

## Install

```
xiom pkg install xiom.nbt@0.1.0     # once published to the registry
```

## Usage

```xi
use xiom.nbt;
use xiom.io;
use xiom.convert;

var tree = nbt_tree_new();
let root = nbt_add_compound(&mut tree, -1, "");          // root, empty name
nbt_add_byte(&mut tree, root, "byte", 1);
nbt_add_str(&mut tree, root, "name", "Bananrama");
let bytes = nbt_encode(&mut tree);                       // 32 bytes, big-endian
// bytes.value in hex:
// 0a000001000462797465010800046e616d65000942616e616e72616d6100

let d = nbt_decode(bytes.value);                         // Result[NbtTree, Str]
match d {
  Ok(t) => {
    let r = nbt_root(&t);
    let n = nbt_find_child(&t, r, "name");               // node index (-1 if absent)
    let s = nbt_get_str(&t, n);
    match s {
      Ok(v) => { io.println(v); },                       // "Bananrama"
      Err(e) => { io.println("read error: " + e); },
    }
  },
  Err(e) => { io.println("decode error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.nbt
```

Expected: the section-4 namespace check passes, 26 `[PASS]` lines, and a
final `port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No region files, no compression.** Anvil `.mca` framing, chunk
  compression and palette/schema handling are callers' concerns.
- **No schemas or data-fix upgrades.** The codec is purely structural.
- **No Bedrock little-endian** (varint) NBT; this is the big-endian Java
  Edition format.
- **No Float64 in the API.** XIOM v0.61.3 has no `Int <-> Float64` bitcast
  intrinsic (`xiom.num.float` is a documented zero-returning stub), so
  TAG_Float / TAG_Double are read and written as raw IEEE-754 bit patterns
  (`nbt_get_float_bits`, `nbt_add_double_bits`, ...). The bytes are exact;
  interpreting them as floats is the caller's job. There is also no
  `Vec[Float64]` in XIOM.
- **NUL-termination limit.** Payload bytes live verbatim in the store, so a
  string or name containing a raw `0x00` re-encodes byte-for-byte, but its
  `Str` view (`nbt_get_str`, `nbt_name`) ends at the first NUL: `Str` is
  NUL-terminated, so bytes after a raw NUL cannot be represented. Standard
  NBT writers encode NUL as `C0 80` (modified UTF-8), which is preserved
  like any other byte.
- **UTF-8 is not validated.** Payload and name bytes are copied verbatim
  (matching the `xiom.encoding.hex` decode precedent).
- **Root must be a compound.** Documents whose root tag is not TAG_Compound
  are rejected (`nbt: root tag is not a compound`).
- **Nesting cap: 64 containers** (`NBT_MAX_DEPTH`) for both decode and
  encode; the root compound counts as depth 1.
- **Strings and names are limited to 65535 bytes** (u16 length prefix);
  `nbt_encode` rejects longer payloads with `nbt: string length overrun`.
- **Lists declare their element type once.** Elements are payload-only (no
  tag byte, no name), as NBT defines them; a list that declares TAG_End (0)
  with a non-zero count is rejected as a type mismatch, and `nbt_encode`
  rejects a hand-built list whose child tag differs from the declared type.
- **`int64`/`uint64` payloads above 2^63-1** wrap to the same
  two's-complement `Int` bit pattern (the platform `Int` is signed 64-bit).
- **Builder trees need `nbt_finalize`** before navigation accessors;
  `nbt_decode` and `nbt_encode` finalize automatically. Nodes added with
  `parent = -1` after the first root are stored but unreachable from
  `nbt_root` and are not encoded.
- **In-memory only**, not thread-safe; trees are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
