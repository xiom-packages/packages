# xiom.dtb -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.dtb`, version `0.1.0`).
Module: `src/dtb.xi` (`module xiom.dtb`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`); tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI) codec for Flattened Device Tree (DTB) blobs:

- `dtb_parse` validates the 40-byte big-endian header, the memory
  reservation block, the structure-block token stream and the strings
  block, then returns a flat `Dtb` store of parallel vectors;
- accessors report header fields, reservations, node names/depths/parents,
  property owners/names/value spans, plus lookup by property name and by
  absolute node path;
- `dtb_emit` re-serializes a parsed store as the canonical version-17
  blob, byte-identical to the input for canonical input;
- deterministic `Err(Str)` messages for every malformed shape.

Documented target: version 17. Version 16 is accepted on input (see
Version handling). Emitter output is always version 17.

## Non-goals

- Phandle resolution and cross-references (`phandle`, `linux,phandle`,
  `interrupt-parent`, ...): property values stay opaque bytes.
- Overlays / `__symbols__` / `__fixups__` semantics.
- `/chosen` or any other node-level policy.
- DTS/DTSI text parsing or emission (binary blob only).
- Building a blob from scratch; the emitter works from a parsed store.
- Incremental/streaming parsing; the blob is an in-memory
  `Vec[UInt8]`.
- Block-overlap detection, alignment enforcement for block offsets.

## Byte-level layout

### Header (40 bytes, big-endian u32 fields)

| Offset | Field | Notes |
|---|---|---|
| 0 | magic | `0xd00dfeed` |
| 4 | totalsize | total blob size; trailing bytes beyond it are ignored |
| 8 | off_dt_struct | structure-block offset |
| 12 | off_dt_strings | strings-block offset |
| 16 | off_mem_rsvmap | memory reservation block offset |
| 20 | version | 17 target; 16 accepted |
| 24 | last_comp_version | must be `<= version` |
| 28 | boot_cpuid_phys | preserved by the emitter |
| 32 | size_dt_strings | strings-block size |
| 36 | size_dt_struct | structure-block size (v17; ignored for v16 input) |

### Memory reservation block

Zero or more 16-byte entries: u64 address, u64 size, both big-endian,
terminated by the pair `0/0`. The terminator is not stored. The emitter
writes the stored pairs followed by the 16-byte `0/0` terminator.
Values with bit 63 set are held as the same signed two's-complement `Int`
bit pattern and round-trip exactly.

### Structure block

A stream of 4-byte big-endian tokens:

| Token | Name | Payload |
|---|---|---|
| 1 | `FDT_BEGIN_NODE` | NUL-terminated node name, zero-padded to 4 bytes |
| 2 | `FDT_END_NODE` | -- |
| 3 | `FDT_PROP` | u32 value length, u32 strings-block name offset, value, zero-padded to 4 bytes |
| 4 | `FDT_NOP` | -- (skipped, never recorded) |
| 9 | `FDT_END` | -- |

Parsing starts at `off_dt_struct` and stops at `FDT_END` (bytes between it
and the declared block end are ignored). A nested node is open when its
`FDT_BEGIN_NODE` has been seen and not yet closed; properties attach to
the innermost open node. Names and property values keep their exact byte
spans in the source buffer.

### Strings block

A table of NUL-terminated property names, `size_dt_strings` bytes long.
`FDT_PROP.nameoff` is relative to `off_dt_strings` and must address a
NUL-terminated name inside the block. Names are not deduplicated on parse;
`dtb_emit` rebuilds the block by first use (see Canonical form).

## Version handling

- `version` must be 16 or 17 (`dtb: unsupported version` otherwise).
- `last_comp_version > version` is rejected (`dtb: bad last_comp_version`).
- For v17, the structure-block size is the header's `size_dt_struct`.
- For v16 (which predates that field) the size is derived as
  `off_dt_strings - off_dt_struct`; the field at offset 36 is ignored, so
  a v16 blob whose 36..40 bytes are garbage still parses. The 40-byte
  header is still required for both versions.
- Emission always writes version 17 with `last_comp_version 16` and the
  parsed `boot_cpuid_phys`.

## API signatures

All functions are free functions in module `xiom.dtb` (no self methods):

```xi
pub type Dtb = {
  totalsize: Int; version: Int; last_comp_version: Int;
  boot_cpuid_phys: Int; off_dt_struct: Int; size_dt_struct: Int;
  off_dt_strings: Int; size_dt_strings: Int; off_mem_rsvmap: Int;
  rsv_address: Vec[Int]; rsv_size: Vec[Int];
  node_name_off: Vec[Int]; node_name_len: Vec[Int];
  node_depth: Vec[Int]; node_parent: Vec[Int];
  prop_node: Vec[Int]; prop_name_off: Vec[Int];
  prop_value_off: Vec[Int]; prop_value_len: Vec[Int];
}

pub fn dtb_parse(data: &Vec[UInt8]) -> Result[Dtb, Str]
pub fn dtb_emit(data: &Vec[UInt8], d: &Dtb) -> Result[Vec[UInt8], Str]

pub fn dtb_total_size(d: &Dtb) -> Int
pub fn dtb_version(d: &Dtb) -> Int
pub fn dtb_last_comp_version(d: &Dtb) -> Int
pub fn dtb_boot_cpuid_phys(d: &Dtb) -> Int
pub fn dtb_strings_size(d: &Dtb) -> Int
pub fn dtb_mem_rsv_count(d: &Dtb) -> Int
pub fn dtb_mem_rsv_address(d: &Dtb, i: Int) -> Int
pub fn dtb_mem_rsv_size(d: &Dtb, i: Int) -> Int

pub fn dtb_node_count(d: &Dtb) -> Int
pub fn dtb_node_depth(d: &Dtb, i: Int) -> Int
pub fn dtb_node_parent(d: &Dtb, i: Int) -> Int
pub fn dtb_root_name(data: &Vec[UInt8], d: &Dtb) -> Str
pub fn dtb_node_name(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Str, Str]

pub fn dtb_prop_count(d: &Dtb) -> Int
pub fn dtb_prop_node(d: &Dtb, i: Int) -> Int
pub fn dtb_prop_value_len(d: &Dtb, i: Int) -> Int
pub fn dtb_prop_name(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Str, Str]
pub fn dtb_prop_value(data: &Vec[UInt8], d: &Dtb, i: Int) -> Result[Vec[UInt8], Str]

pub fn dtb_find_node(data: &Vec[UInt8], d: &Dtb, path: Str) -> Int
pub fn dtb_find_property(data: &Vec[UInt8], d: &Dtb, node: Int, name: Str) -> Int
```

The raw header fields are public for inspection; callers should prefer the
accessors.

## Semantics

`dtb_parse(data)`
: Validates in this order: header length, magic, totalsize, version,
  `last_comp_version`, struct block bounds, strings block bounds, memory
  reservation block bounds, reservation terminator, structure tokens,
  root presence. Nodes and properties append to the parallel vectors in
  document order; every node vector receives exactly one push per node and
  every property vector one push per property. The reservation pairs are
  read until `0/0`. On `Err`, no partial store escapes.

`dtb_find_node(data, d, path)`
: `""` and `"/"` resolve to the root. Any other path must start with `/`;
  components are separated by `/` and matched byte-for-byte against the
  full node names (unit addresses included). Empty components (`"//"`) are
  invalid; one trailing `/` is accepted. Lookup is case-sensitive and
  depth-first in document order; the first match wins. Returns `-1` when
  the path does not resolve (including for an empty store).

`dtb_find_property(data, d, node, name)`
: Linear scan of the property vectors in document order, restricted to
  `node`; the first byte-exact name match wins, `-1` when none matches or
  the node index is invalid.

`dtb_root_name` / `dtb_node_name` / `dtb_prop_name` / `dtb_prop_value`
: Materialize bytes from `data`. Node/property index accessors report
  out-of-range with `-1`; name/value getters report
  `dtb: node index out of range` / `dtb: property index out of range`;
  `dtb_prop_value` additionally checks the recorded span against `data`
  (`dtb: property value out of bounds`).

`dtb_mem_rsv_address` / `dtb_mem_rsv_size`
: Return the u64 as a signed 64-bit `Int` bit pattern (`-1` for an
  out-of-range index), matching the `xiom.msgpack` uint64 convention.

`dtb_emit(data, d)`
: Refuses a store whose parallel vectors have drifted apart, whose node
  forest is not a preorder tree rooted at node 0, whose spans do not fit
  `data`, whose node names contain a NUL, or whose property name does not
  resolve to a NUL-terminated entry in the strings block: all report
  `dtb: invalid tree`. Otherwise it rebuilds the strings block by first
  use, emits the structure block without NOPs, writes the reservations and
  the header, and returns the bytes.

## Canonical form

`dtb_emit` output is canonical when:

1. the three blocks appear in the order header, memory reservation block,
   structure block, strings block, with `off_mem_rsvmap = 40`;
2. the header is version 17, `last_comp_version 16`, `totalsize`,
   `off_dt_struct`, `off_dt_strings`, `size_dt_strings` and
   `size_dt_struct` recomputed from the emitted bytes, and
   `boot_cpuid_phys` preserved;
3. no `FDT_NOP` token is written; node names end with a NUL and are
   zero-padded to 4 bytes; property values are zero-padded to 4 bytes;
4. the strings block lists each property name once, in first-use document
   order, each entry NUL-terminated with no trailing bytes;
5. the structure block ends with `FDT_END` as its last token.

For an input that already has this form, `dtb_parse` then `dtb_emit` is
byte-identical. Non-canonical inputs (NOPs, other strings-block orderings,
nonzero padding) parse fine and are canonicalized.

## Error string catalog

| Condition | Error text |
|---|---|
| `data.len() < 40` | `dtb: header truncated` |
| magic != `0xd00dfeed` | `dtb: bad magic` |
| `totalsize < 40` or `totalsize > data.len()` | `dtb: totalsize out of range` |
| `version` not 16 or 17 | `dtb: unsupported version` |
| `last_comp_version > version` | `dtb: bad last_comp_version` |
| struct block start < 40, size < 4, v16 offsets inverted, or end > totalsize | `dtb: struct block out of range` |
| strings block start < 40 or end > totalsize | `dtb: strings block out of range` |
| reservation block start < 40 or no room for one pair | `dtb: memory reservation block out of range` |
| no `0/0` terminator before `totalsize` | `dtb: unterminated memory reservation block` |
| node name has no NUL before the structure-block end | `dtb: unterminated node name` |
| second `FDT_BEGIN_NODE` after the root closed | `dtb: multiple root nodes` |
| `FDT_END` reached with no root node | `dtb: missing root node` |
| `FDT_END_NODE` with no open node | `dtb: unbalanced end node` |
| `FDT_END` while nodes are still open | `dtb: unbalanced node nesting` |
| `FDT_PROP` with no open node | `dtb: property outside node` |
| property value bytes run past the structure block | `dtb: property value out of range` |
| `nameoff >= size_dt_strings` | `dtb: property name offset out of range` |
| property name has no NUL inside the strings block | `dtb: unterminated property name` |
| token not in {1, 2, 3, 4, 9} | `dtb: unknown token` |
| token, name pad, prop header or value pad past the structure block | `dtb: truncated structure block` |
| `dtb_emit` on a drifted or malformed store | `dtb: invalid tree` |
| `dtb_node_name` index out of range | `dtb: node index out of range` |
| `dtb_prop_name` / `dtb_prop_value` index out of range | `dtb: property index out of range` |
| `dtb_prop_value` recorded span outside `data` | `dtb: property value out of bounds` |

Bounds checks are performed in the order listed in Semantics, so a blob
with several problems reports the first one in that order (e.g. a bad
totalsize is reported before a bad version).

## Complexity

| Operation | Complexity |
|---|---|
| `dtb_parse` | O(data.len()) |
| `dtb_emit` | O(blob size + properties x strings) |
| count/header/reservation accessors | O(1) |
| `dtb_node_depth` / `dtb_node_parent` / `dtb_prop_*` index accessors | O(1) |
| name/value getters | O(name or value length) |
| `dtb_find_node` | O(nodes x path components) |
| `dtb_find_property` | O(properties x name length) |

## Test plan

`tests/test_conformance.xi` (`module dtb_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). The canonical v17 blob is a hand-computed
299-byte hex literal; the malformed cases are assembled by independent
byte builders. Coverage:

1. canonical header fields: magic/version/last_comp_version/boot_cpuid,
   totalsize 299, off_dt_struct 56, off_dt_strings 256, off_mem_rsvmap 40,
   size_dt_strings 43, size_dt_struct 200, zero reservations;
2. canonical node layout: three nodes, names `""`/`soc@0`/`uart@1000`,
   depths 0/1/2, parents -1/0/1;
3. canonical properties: seven entries with pinned owners, names
   (`compatible`, `model`, `ranges`, `#address-cells`, `reg`), exact
   values including an empty `ranges` and the 16-byte `reg`;
4. property lookup by name per node, exact-match rejection of prefixes,
   missing names/empty name/bad node index;
5. path lookup: `""`, `/`, `/soc@0`, `/soc@0/uart@1000`, trailing slash
   accepted, relative `//`/missing/extra components and case sensitivity
   rejected;
6. out-of-range accessors (`-1` for index accessors, documented `Err`
   texts for getters) and a truncated source buffer for a recorded value
   span;
7. canonical emit: parse -> emit reproduces the 299-byte literal;
8. NOP skipping plus strings-block first-use canonicalization: a blob
   with three FDT_NOPs and the strings block in reverse order emits the
   canonical literal;
9. reservations: two entries including `0x10000000/0x2000` and the bit-63
   u64 `0x8000000000000000/1`, `boot_cpuid_phys` 42, `board` root, and a
   byte-identical emit;
10. v16 acceptance: version 16 with a bogus `size_dt_struct` field parses
    (size derived as 200) and emits the canonical v17 literal;
    `last_comp_version 17` with version 16 is
    `dtb: bad last_comp_version`;
11. lenient padding: nonzero name-pad and value-pad bytes parse and emit
    canonical zero padding;
12. bytes past `totalsize` are ignored while `totalsize` 5000/39 are
    `dtb: totalsize out of range`;
13. header errors: 39-byte prefix, bad magic, version 18, version 15;
14. block bounds: struct/strings/reservation offsets or sizes outside the
    buffer, and `size_dt_struct` below 4;
15. token errors: `FDT_END_NODE` first, `FDT_END` with an open node,
    unknown token 5, no `FDT_END`, a second root, `FDT_END` with no root;
16. node name without a NUL before the block end;
17. property errors: value overrun, name offset outside the strings block,
    unterminated property name, empty strings block, property outside a
    node;
18. emitter guards: empty store and a store with drifted parallel vectors
    are `dtb: invalid tree`; a valid store still emits.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.dtb
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Phandles, overlays and `/chosen` are not interpreted (documented
  non-goals); values are opaque bytes.
- No builder API: `dtb_emit` requires a store produced by `dtb_parse`.
- v16 is a compatibility alias only (40-byte header required, derived
  structure size); 36-byte v16 headers are out of scope.
- Padding bytes are not validated; emit always writes zeros, so a blob
  with nonzero padding is canonicalized rather than preserved.
- Bytes between `FDT_END` and the declared structure-block end, and bytes
  after `totalsize`, are ignored rather than rejected.
- Block overlaps are not detected; only bounds are checked.
- Accessors and `dtb_emit` need the original parse buffer; `Dtb` stores
  spans, not copies.
- `Dtb` is a plain value type built from parallel vectors; callers can
  corrupt its invariants, and `dtb_emit` rejects such stores instead of
  repairing them.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_dtb`/`_err_dtb`/`_ok_str`/`_err_str`/`_ok_bytes`/`_err_bytes`
  (constructing `Result[Dtb, Str]` directly in other functions
  miscompiles).
- All big-endian extraction/packing is arithmetic (modulo/division)
  because `& 0xFF` on operands with bit 31 set miscompiles (same bug
  documented in `xiom.convert.base58` and `xiom.msgpack`); this form is
  exact for negative two's-complement values, which is why bit-63 u64
  fields round-trip.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering `Int` arithmetic.
- Str values are never compared with `==` and never measured with
  `str_len` after coming out of a `Vec` (BUG 17); names and path
  components are compared byte by byte, and every `Vec[Int]` element read
  is bound to a typed local.
- Names are materialized with `xiom.string.builder.sb_to_str`, and
  `_materialize` stops at a NUL byte before calling it, so the builder
  never sees `0x00` in its range (its length contract aborts on NUL).
- Every push on a parallel vector is mirrored on its siblings;
  `dtb_emit` refuses drifted stores (`dtb: invalid tree`).
- The package declares no `extern "C"` blocks (no FFI).
