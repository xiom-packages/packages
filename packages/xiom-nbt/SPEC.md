# xiom.nbt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.nbt`, version `0.1.0`).
Module: `src/nbt.xi` (`module xiom.nbt`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.string.compare`, `xiom.convert`).

## Scope

A pure-XIOM (no FFI) NBT (Named Binary Tag) codec for the Java Edition
big-endian format:

- all twelve tag types (1-12): Byte, Short, Int, Long, Float, Double,
  Byte_Array, String, List, Compound, Int_Array, Long_Array;
- `nbt_decode` of a COMPLETE document into an `NbtTree`: exact-size
  validation (`nbt: trailing bytes`), root-tag validation, bounded nesting;
- an `NbtTree` flat node store: parallel `Vec[Int]` / `Vec[Str]` /
  `Vec[UInt8]` fields plus contiguous child ranges (`child_start`,
  `child_count`, `order`) -- no `Vec[StructType]`;
- navigation accessors (find child by name, child range, list item count,
  typed readers) and a `nbt_add_*` builder;
- `nbt_encode` writing a complete document, byte-exact for any decoded tree;
- deterministic `Err(Str)` messages for the full catalog below.

## Non-goals

- Region files (Anvil `.mca`), chunk framing, gzip/zlib compression.
- Schemas, palette handling, data-fix upgrades, or any Minecraft-version
  semantics.
- Bedrock / little-endian (varint) NBT.
- Modified-UTF-8 encoding or validation: payload bytes are stored verbatim.
- Streaming/incremental decoding; this codec works on in-memory
  `Vec[UInt8]` buffers.
- A recursive `Vec[StructType]` tree or a generic `Value` enum.
- `Float64` values in the public API: XIOM v0.61.3 has no `Int <-> Float64`
  bitcast (see Known limitations); float/double tags are exposed as raw
  IEEE-754 bit patterns.
- Automatic finalization inside read-only accessors: builder trees must call
  `nbt_finalize` before navigation.

## Tag encodings

All multi-byte integers are BIG-endian; the format has no padding or
alignment. Every tag carries a one-byte type id and, when it is a root or
compound child, a name (`u16` byte length + verbatim UTF-8 bytes).

| Type | Id | Payload |
|---|---|---|
| TAG_End | 0 | none; terminates a TAG_Compound, never a standalone tag |
| TAG_Byte | 1 | 1 signed byte |
| TAG_Short | 2 | 2 signed bytes (two's complement) |
| TAG_Int | 3 | 4 signed bytes |
| TAG_Long | 4 | 8 signed bytes |
| TAG_Float | 5 | 4 bytes IEEE-754, exposed as raw bits |
| TAG_Double | 6 | 8 bytes IEEE-754, exposed as raw bits |
| TAG_Byte_Array | 7 | `int32` count then `count` bytes |
| TAG_String | 8 | `u16` byte length then that many UTF-8 bytes |
| TAG_List | 9 | `u8` element type, `int32` count, then `count` element payloads (no per-element tag or name) |
| TAG_Compound | 10 | sequence of complete named tags, terminated by `0x00` |
| TAG_Int_Array | 11 | `int32` count then `count` * 4 signed bytes |
| TAG_Long_Array | 12 | `int32` count then `count` * 8 signed bytes |

A document is: root tag byte (must be 10), root name, compound payload. The
buffer must end exactly after the root's terminator. Minimum document:
`0a 00 00 00` (empty compound named ""). Example ("byte" = 1, "name" =
"Bananrama"):

```
0a 00 00                                        root compound, name ""
01 00 04 62797465 01                            TAG_Byte name "byte" = 1
08 00 04 6e616d65 00 09 42616e616e72616d61      TAG_String "name" = "Bananrama"
00                                              root terminator
```

## API signatures

All functions are free functions in module `xiom.nbt`:

```xi
pub type NbtTree = {
  types: Vec[Int]; names: Vec[Str]; name_off: Vec[Int]; name_len: Vec[Int];
  parent: Vec[Int]; child_start: Vec[Int]; child_count: Vec[Int];
  order: Vec[Int]; values: Vec[Int]; data_off: Vec[Int]; data_len: Vec[Int];
  data: Vec[UInt8]; root: Int;
}

pub const NBT_TAG_BYTE .. NBT_TAG_LONG_ARRAY   // 1..12
pub const NBT_TAG_END                          // 0
pub const NBT_MAX_DEPTH                        // 64

pub fn nbt_decode(data: Vec[UInt8]) -> Result[NbtTree, Str]
pub fn nbt_encode(tree: &mut NbtTree) -> Result[Vec[UInt8], Str]
pub fn nbt_tree_new() -> NbtTree
pub fn nbt_finalize(tree: &mut NbtTree)

pub fn nbt_add_compound(tree: &mut NbtTree, parent: Int, name: Str) -> Int
pub fn nbt_add_list(tree: &mut NbtTree, parent: Int, name: Str, elem_type: Int) -> Int
pub fn nbt_add_byte(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int
pub fn nbt_add_short(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int
pub fn nbt_add_int(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int
pub fn nbt_add_long(tree: &mut NbtTree, parent: Int, name: Str, v: Int) -> Int
pub fn nbt_add_float_bits(tree: &mut NbtTree, parent: Int, name: Str, bits: Int) -> Int
pub fn nbt_add_double_bits(tree: &mut NbtTree, parent: Int, name: Str, bits: Int) -> Int
pub fn nbt_add_str(tree: &mut NbtTree, parent: Int, name: Str, v: Str) -> Int
pub fn nbt_add_byte_array(tree: &mut NbtTree, parent: Int, name: Str, bytes: Vec[UInt8]) -> Int
pub fn nbt_add_int_array(tree: &mut NbtTree, parent: Int, name: Str, values: Vec[Int]) -> Int
pub fn nbt_add_long_array(tree: &mut NbtTree, parent: Int, name: Str, values: Vec[Int]) -> Int

pub fn nbt_node_count(tree: &NbtTree) -> Int
pub fn nbt_root(tree: &NbtTree) -> Int
pub fn nbt_tag_type(tree: &NbtTree, node: Int) -> Int
pub fn nbt_name(tree: &NbtTree, node: Int) -> Str
pub fn nbt_parent(tree: &NbtTree, node: Int) -> Int
pub fn nbt_child_count(tree: &NbtTree, node: Int) -> Int
pub fn nbt_child_at(tree: &NbtTree, node: Int, index: Int) -> Int
pub fn nbt_find_child(tree: &NbtTree, node: Int, name: Str) -> Int

pub fn nbt_list_len(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_list_element_type(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_list_item(tree: &NbtTree, node: Int, index: Int) -> Result[Int, Str]

pub fn nbt_get_byte(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_short(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_int(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_long(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_float_bits(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_double_bits(tree: &NbtTree, node: Int) -> Result[Int, Str]
pub fn nbt_get_str(tree: &NbtTree, node: Int) -> Result[Str, Str]
pub fn nbt_get_byte_array(tree: &NbtTree, node: Int) -> Result[Vec[UInt8], Str]
pub fn nbt_get_int_array(tree: &NbtTree, node: Int) -> Result[Vec[Int], Str]
pub fn nbt_get_long_array(tree: &NbtTree, node: Int) -> Result[Vec[Int], Str]
```

## Node store semantics

`nbt_decode` builds the store depth-first; `_finalize` (called by
`nbt_decode` and `nbt_encode`) derives `child_start` / `child_count` /
`order` from `parent`, so a node's children occupy the contiguous slice
`order[child_start .. child_start + child_count]` in creation order.
`nbt_add_*` maintain only `parent`, which is why builder trees need
`nbt_finalize` before navigation accessors.

Field meaning per tag:

| Field | Scalar 1-6 | Byte_Array 7 | String 8 | List 9 | Compound 10 | Int/Long_Array 11/12 |
|---|---|---|---|---|---|---|
| `values` | payload (bits for 5/6) | element count | byte length | declared element type | -- | element count |
| `data_off` / `data_len` | -- | payload bytes | UTF-8 bytes | -- | -- | payload bytes (count * 4 / count * 8) |
| children | none | none | none | element nodes | named child nodes | none |

`name_off` / `name_len` locate the exact name bytes in `data` (0 / 0 for
list elements and the root when unnamed); `names` holds the `Str` view.

### Depth rule

`NBT_MAX_DEPTH` is 64 container levels. The root compound is depth 1; a
compound child or list element of a depth-N container is depth N+1. Scalars
never count toward the limit. Both `nbt_decode` and `nbt_encode` reject a
container at depth > 64 with `nbt: depth exceeded`; a non-empty list whose
first element would be at depth 65 is rejected the same way.

### List rule

A TAG_List declares its element type ONCE in the header; elements are
payload-only (no tag byte, no name), including compound and list elements.
On decode the declared type must be 0-12 and is stored in `values[list]`;
count > 0 with declared TAG_End (0) is `nbt: list element type mismatch`.
Declared elem type 0 with count 0 is an ordinary empty list. On encode every
element's stored tag must equal the declared type, otherwise
`nbt: list element type mismatch` (this is the only way a per-element
mismatch can arise, since the wire format carries no per-element tag).

### Exact-size rule

`nbt_decode` requires the buffer to end exactly after the root terminator
(`nbt: trailing bytes`). Payload arity is exact: a declared `u16` name or
string length past the buffer end is `nbt: string length overrun`; a scalar,
byte array or int/long array payload that runs past the buffer end is
`nbt: truncated buffer`; a missing compound terminator or missing list
element is `nbt: truncated buffer`; an `int32` count below 0 is
`nbt: negative length`.

### Float / double bits

`nbt_get_float_bits` / `nbt_get_double_bits` return the raw IEEE-754 bit
pattern as an `Int`: 4 bytes for float, 8 for double. A 64-bit pattern with
bit 63 set reads as the corresponding negative `Int` (the platform `Int` is
64-bit two's complement); `nbt_add_double_bits` accepts that same pattern
and writes it back unchanged. No `Float64` value appears anywhere in the
API.

### NUL-termination limit

Payload and name bytes are stored verbatim in `data`, so raw `0x00` bytes
survive a decode/encode round trip exactly. `Str` is NUL-terminated by
construction, so the `Str` view produced by `nbt_get_str` / `nbt_name` ends
at the first raw NUL: bytes after it cannot be represented as a `Str`. The
byte-exact view remains available through `nbt_encode`. Strings that follow
the NBT convention of encoding NUL as `C0 80` (modified UTF-8) round-trip
through both views unchanged.

### Builder contract

`nbt_add_*` with `parent = -1` creates a root; the first root wins, later
`parent = -1` nodes are stored but unreachable from `nbt_root` and are not
encoded. `nbt_encode` finalizes the tree first, so builder trees encode
without an explicit `nbt_finalize`. Navigation accessors on a tree that was
not decoded and not finalized see empty child ranges. Adding a child under
an index that is not a stored node, or corrupting the store by hand, is a
programming error; encode reports `nbt: invalid node structure` when it can
detect it.

## Error string catalog

| Condition | Error text |
|---|---|
| Not enough bytes for a tag, name length, scalar, array payload, list element or compound terminator | `nbt: truncated buffer` |
| A `u16` name/string length exceeds the remaining buffer; encode of a string or name longer than 65535 bytes | `nbt: string length overrun` |
| An `int32` byte/int/long array count or list count is negative | `nbt: negative length` |
| Tag byte outside 1-12 (decode); list declared element type > 12; store node tag outside 1-12 (encode) | `nbt: unknown tag type N` |
| Decode: list declares TAG_End (0) with count > 0. Encode: an element tag differs from the declared list type | `nbt: list element type mismatch` |
| Container depth would exceed NBT_MAX_DEPTH (64) | `nbt: depth exceeded` |
| Decode consumed fewer bytes than the buffer holds | `nbt: trailing bytes` |
| Root tag is not TAG_Compound (decode), or the tree root is not a compound (encode) | `nbt: root tag is not a compound` |
| `nbt_encode` on a store with no root | `nbt: empty tree` |
| Navigation / reader / encoder index outside the store | `nbt: node index out of range` |
| `nbt_list_item` index >= element count (or negative) | `nbt: list index out of range` |
| Typed reader on a node whose tag differs from the requested one | `nbt: unexpected tag type N` |
| Encode-time store inconsistency (bad child index, payload length mismatch); unreachable from decoded trees | `nbt: invalid node structure` |

`N` is the decimal tag type (for example `nbt: unknown tag type 13`).

## Complexity

| Operation | Complexity |
|---|---|
| `nbt_decode` | O(buffer bytes + nodes) |
| `nbt_encode` | O(payload bytes + nodes) |
| `nbt_finalize` | O(nodes) |
| `nbt_add_*` | O(name + payload) |
| `nbt_node_count` / `nbt_root` / `nbt_tag_type` / `nbt_name` / `nbt_parent` | O(1) |
| `nbt_child_count` / `nbt_child_at` | O(1) |
| `nbt_find_child` | O(children) with `str_compare` per name |
| `nbt_list_*` | O(1) |
| scalar `nbt_get_*` | O(1) |
| `nbt_get_str` / `nbt_get_byte_array` / `nbt_get_int_array` / `nbt_get_long_array` | O(payload) |

## Test matrix

`tests/test_conformance.xi` (`module nbt_tests`, 26 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. empty root compound: encode bytes `0a000000`, decode, store facts;
2. byte/short/int/long exact big-endian bytes and readers;
3. negative scalars incl. INT64_MIN two's complement;
4. float/double exact bit patterns (1.0f, 1.0, -0.0);
5. strings: empty, ASCII, 2-byte UTF-8 payload and UTF-8 name;
6. byte/int/long arrays: length prefix, negatives, INT32_MAX;
7. lists: element type byte, count, empty list with type 0;
8. nested compounds and list of strings: bytes, navigation, re-encode;
9. builder tree with all twelve tag types round-trips through decode;
10. decode then re-encode is byte-exact;
11. scalar round trips at every type boundary;
12. navigation accessors (node count, root, parent, child ranges, names);
13. typed readers reject the wrong tag with exact `unexpected tag type N`;
14. truncated payloads and missing terminators are `truncated buffer`;
15. string length overrun; raw NUL payloads re-encode byte-exact;
16. negative array/list lengths;
17. unknown tag type 13 at root, in a compound and as a list element type;
18. nesting capped at 64 containers (decode and encode);
19. list elements are payload-only; TAG_End list with items mismatches;
20. root tag must be a compound; empty tree cannot encode;
21. empty strings, arrays, lists and compounds round-trip;
22. list of compounds: element payloads carry no names;
23. classic hello NBT document (`byte` = 1, `name` = "Bananrama");
24. string byte length 65535 round-trips; 65536 is rejected;
25. high-bit array payloads decode signed without sign bleed;
26. float/double bit patterns with bit 31/63 set re-encode exactly.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.nbt
```

Last verified: compiler 0.61.3,
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Known limitations

- **No `Float64`.** There is no `Int <-> Float64` bitcast intrinsic in XIOM
  v0.61.3 (`xiom.num.float` is a documented zero-returning stub) and FFI is
  out of scope, so float/double values are carried as exact IEEE-754 bit
  patterns and never interpreted. `Vec[Float64]` does not exist either.
- **NUL-truncated Str views** for payloads/names containing raw `0x00`
  (byte-exact re-encode still holds; see the NUL-termination limit above).
- **Root must be a compound**; other root tags are rejected.
- **Nesting cap 64** containers.
- **u16 strings/names** (max 65535 bytes).
- **`uint64` payloads above 2^63-1 wrap** to the signed two's-complement
  pattern.
- **Little-endian (Bedrock) NBT, region framing and compression are out of
  scope.**
- **No UTF-8 validation**; bytes are opaque.
- **Builder trees are not auto-finalized for readers** (only `nbt_encode`
  and `nbt_decode` finalize).
- **Unattached later roots** are stored but ignored by `nbt_root` /
  `nbt_encode`.
- In-memory only; no streaming; trees are plain value types (not
  thread-safe).

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_int`/`_err_int`/`_ok_str`/`_err_str`/`_ok_bytes`/`_err_bytes`/
  `_ok_ints`/`_err_ints`/`_ok_tree`/`_err_tree`.
- All big-endian byte extraction is arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles (the same bug documented
  in `xiom.convert.base58` and `xiom.msgpack`).
- `Str` equality goes through `str_compare` (BUG 17: `==` on Str values read
  from a `Vec` lowers to a pointer compare) and name byte lengths live in a
  parallel `Vec[Int]` so `str_len` is never called on a `Vec[Str]` element.
- `Vec[Int]` element reads are always bound to typed `Int` locals (BUG 17
  family).
- `sb_to_str`'s `result.len() == sb.len()` contract would abort on embedded
  NULs, so `_materialize` truncates at the first raw NUL before calling it.
- No indexed `Vec[fn]` dispatch, no `Vec[StructType]`, no self methods and
  no `mut` bindings in `match` patterns; the reader is a small private
  struct (`NbtCursor`) passed as `&mut`.
- The package declares no `extern "C"` blocks (no FFI).
