# xiom.hid -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.hid`, version `0.1.0`).
Module: `src/hid.xi` (`module xiom.hid`).
Depends on `xiom.std`; the library module is dependency-free (no stdlib
imports). Tests add `xiom.test`, `xiom.io`, `xiom.string.compare` and
`xiom.encoding.hex`.
No FFI.

## Scope

A pure-XIOM (no FFI) codec for USB HID report descriptors (HID 1.11,
section 6.2.2) for the documented item subset below:

- `hid_parse` validates a descriptor stream and returns a flat,
  self-contained `HidDescriptor` store of parallel vectors (no
  `Vec[StructType]`), one index per item, in stream order;
- accessors report the item count, type, tag, size, unsigned / per-width
  signed / nibble-signed data values, data bytes, whole-item bytes,
  collection depth, Push/Pop balance, collection kind, usage ID and Usage
  Page;
- `hid_emit` re-serializes a parsed store as the canonical stream,
  byte-identical to the input of the `hid_parse` that produced it;
- deterministic `Err(Str)` messages for every malformed shape (error
  catalog below).

## Non-goals

- Report-field assembly: no report bit offsets, no field extraction, no
  logical/physical scaling, no input/output/feature report layout.
- Usage tables: usage IDs and Usage Pages stay raw numbers; no names, no
  page resolution beyond tracking the current Usage Page.
- Report ID semantics beyond recording the Report ID item.
- Push/Pop global-state replay: only the balance, the Usage Page save/
  restore and the stored items are modelled; Report Size/Count/... are
  recorded but never assembled into state.
- Long-item semantics: the bLongItemTag and payload are preserved verbatim
  and never interpreted.
- HID device IO: no transports, no control transfers, no device handles.
- Unknown/class-specific item semantics; reserved tags are rejected, not
  preserved (the documented subset is closed).

## Byte-level layout

A report descriptor is a flat sequence of items. Every item is either a
short item or a long item; both are self-delimiting, so the stream is walked
until the buffer ends.

### Short items

One prefix byte, then `bSize` data bytes:

| Bits | Field | Meaning |
|---|---|---|
| 1..0 | bSize | 0 -> 0 data bytes, 1 -> 1, 2 -> 2, 3 -> 4 (4-byte form out of subset, rejected) |
| 3..2 | bType | 0 main, 1 global, 2 local, 3 reserved (long item prefix only) |
| 7..4 | bTag | item tag within the type |

The data bytes are little-endian and unsigned; interpreted values are
`b0 + 256*b1` for size 2 and `b0` for size 1.

Field-order note: the positions above follow HID 1.11 section 6.2.2.2 and
are the only ordering consistent with the HID tag codes used by real
descriptors (Usage Page `05 01` is tag 0 / type 1 / size 1; Collection
`A1 01` is tag 10 / type 0 / size 1; Input `81` is tag 8 / type 0 / size 1).
The port brief's sentence that places bTag in the low four bits and bSize
in the top two bits lists the same three fields in the opposite bit order
and is not followed, because reversing the fields would decode every real
HID prefix byte as a reserved tag or an out-of-subset size.

### Long items

| Offset | Field |
|---|---|
| 0 | 0xFE prefix (bTag 0xF, bType 3, bSize 2) |
| 1 | bDataSize (0..255) |
| 2 | bLongItemTag (0..255) |
| 3.. | bDataSize payload bytes |

Long items are stored as `HID_TYPE_LONG` with `item_tag` = bLongItemTag,
`item_size` = bDataSize, `item_data` = 0 and `item_raw` = the payload
verbatim. They never affect depth, Push/Pop balance or Usage Page.

## Documented item subset

### Main items (bType 0)

| Tag | Item | Notes |
|---|---|---|
| 0x8 | Input | data is the main-item flags |
| 0x9 | Output | data is the main-item flags |
| 0xA | Collection | data is the collection kind (0 Physical, 1 Application, 2 Logical, 3 Report, 4 Named Array, 5 Usage Switch, 6 Usage Modifier) |
| 0xB | Feature | data is the main-item flags |
| 0xC | End Collection | size 0 in practice; closes the innermost open collection |

### Global items (bType 1)

| Tag | Item |
|---|---|
| 0x0 | Usage Page |
| 0x1 | Logical Minimum |
| 0x2 | Logical Maximum |
| 0x3 | Physical Minimum |
| 0x4 | Physical Maximum |
| 0x5 | Unit |
| 0x6 | Unit Exponent (nibble-signed) |
| 0x7 | Report Size |
| 0x8 | Report ID |
| 0x9 | Report Count |
| 0xA | Push |
| 0xB | Pop |

### Local items (bType 2)

| Tag | Item |
|---|---|
| 0x0 | Usage |
| 0x1 | Usage Minimum |
| 0x2 | Usage Maximum |
| 0x3 | Designator Index |
| 0x4 | Designator Minimum |
| 0x5 | Designator Maximum |
| 0x7 | String Index |
| 0x8 | String Minimum |
| 0x9 | String Maximum |
| 0xA | Delimiter |

Any other tag of any type, the reserved short type (bType 3 outside 0xFE)
and the 4-byte short size are rejected.

## API signatures

All functions are free functions in module `xiom.hid` (no self methods):

```xi
pub type HidDescriptor = { /* 8 flat fields; see src/hid.xi */ }

pub fn hid_max_collection_depth() -> Int

pub fn hid_parse(data: &Vec[UInt8]) -> Result[HidDescriptor, Str]
pub fn hid_emit(d: &HidDescriptor) -> Result[Vec[UInt8], Str]

pub fn hid_item_count(d: &HidDescriptor) -> Int
pub fn hid_item_type(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_tag(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_size(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_data(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_data_signed(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_data_nibble_signed(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_data_bytes(d: &HidDescriptor, i: Int) -> Result[Vec[UInt8], Str]
pub fn hid_item_bytes(d: &HidDescriptor, i: Int) -> Result[Vec[UInt8], Str]
pub fn hid_item_depth(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_stack(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_collection_kind(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_usage(d: &HidDescriptor, i: Int) -> Int
pub fn hid_item_usage_page(d: &HidDescriptor, i: Int) -> Int
```

Exported constants: `HID_TYPE_MAIN`, `HID_TYPE_GLOBAL`, `HID_TYPE_LOCAL`,
`HID_TYPE_LONG`, `HID_LONG_ITEM_PREFIX`, `HID_MAIN_INPUT`,
`HID_MAIN_OUTPUT`, `HID_MAIN_COLLECTION`, `HID_MAIN_FEATURE`,
`HID_MAIN_END_COLLECTION`, `HID_GLOBAL_USAGE_PAGE`,
`HID_GLOBAL_LOGICAL_MIN`, `HID_GLOBAL_LOGICAL_MAX`,
`HID_GLOBAL_PHYSICAL_MIN`, `HID_GLOBAL_PHYSICAL_MAX`, `HID_GLOBAL_UNIT`,
`HID_GLOBAL_UNIT_EXPONENT`, `HID_GLOBAL_REPORT_SIZE`,
`HID_GLOBAL_REPORT_ID`, `HID_GLOBAL_REPORT_COUNT`, `HID_GLOBAL_PUSH`,
`HID_GLOBAL_POP`, `HID_LOCAL_USAGE`, `HID_LOCAL_USAGE_MIN`,
`HID_LOCAL_USAGE_MAX`, `HID_LOCAL_DESIGNATOR_INDEX`,
`HID_LOCAL_DESIGNATOR_MIN`, `HID_LOCAL_DESIGNATOR_MAX`,
`HID_LOCAL_STRING_INDEX`, `HID_LOCAL_STRING_MIN`, `HID_LOCAL_STRING_MAX`,
`HID_LOCAL_DELIMITER`.

The `HidDescriptor` fields are public for inspection but are implementation
details; callers should prefer the accessors.

## Semantics

### Item store conventions

For item index `i` (0-based, stream order; a short item and a long item each
occupy exactly one index):

- `item_type[i]`: `HID_TYPE_MAIN` (0), `HID_TYPE_GLOBAL` (1),
  `HID_TYPE_LOCAL` (2) or `HID_TYPE_LONG` (3).
- `item_tag[i]`: the bTag (0..15) for short items, the bLongItemTag
  (0..255) for long items.
- `item_size[i]`: the number of data bytes -- 0, 1 or 2 for short items,
  the bDataSize (0..255) for long items.
- `item_data[i]`: the unsigned little-endian value of the short item's data
  bytes (0 for size 0); always 0 for long items, whose bytes stay in
  `item_raw[i]`.
- `item_raw[i]`: the verbatim long-item payload (empty for short items).
- `item_depth[i]`: the number of enclosing open collections. A Collection
  item records the depth of the collection it opens and its End Collection
  records the depth of the collection it closes (the same value); items
  directly inside a top-level collection have depth 1.
- `item_stack[i]`: the Push/Pop balance *after* processing item `i`: a Push
  records the incremented balance, a Pop the decremented one, every other
  item the unchanged balance.
- `item_usage_page[i]`: the Usage Page global in effect for item `i` (next
  section).

The store holds no spans into the parse buffer: `item_raw` and `item_data`
are copies, so the accessors and `hid_emit` never need the source bytes
again.

### Signed interpretations

`hid_item_data(d, i)` returns the unsigned little-endian value.

`hid_item_data_signed(d, i)` sign-extends from the item's byte width, which
is the interpretation used for Logical/Physical Minimum and Maximum, Report
Size/Count and the other signed integer items:

| Size | Range | Examples |
|---|---|---|
| 0 | 0 | any size-0 item |
| 1 | -128..127 | `15 81` -> -127, `25 7F` -> 127 |
| 2 | -32768..32767 | `16 FF FF` -> -1, `26 00 80` -> -32768 |
| long | 0 (long payloads are opaque) | |

`hid_item_data_nibble_signed(d, i)` takes the low four bits (`data % 16`)
and sign-extends from 4 bits (-8..7), which is the interpretation used for
the global Unit Exponent item: `65 0F` -> -1, `65 07` -> 7, `65 F8` -> -8.
It is defined for every item and yields 0 for size 0 and long items.

Neither signed accessor validates the item tag: interpretation is a property
of the data width, not of the tag. Out-of-range indexes yield 0 from all
three data accessors (documented sentinel; 0 is also a legal data value, so
check the index or the item fields when that matters).

### Usage and Usage Page tracking

The Usage Page is the only global state this codec tracks:

- a global Usage Page item sets the page to its data value, and reports its
  own new page from `hid_item_usage_page`;
- Push saves the current page on the push stack; Pop restores it (so the Pop
  item reports the restored page);
- every other item reports the page currently in effect;
- before the first Usage Page item the page is 0.

`hid_item_usage(d, i)` returns the item's data value when the item is a local
Usage, Usage Minimum or Usage Maximum item, and -1 otherwise (a legal usage
ID is never negative, so -1 is unambiguous). With the 4-byte form out of the
subset there are no 32-bit extended usages; a usage is always the recorded
value plus the page from `hid_item_usage_page`.

### Parsing and validation order

`hid_parse(data)` walks the buffer from offset 0. For each item, the first
failing check wins, in this order:

1. a 0xFE prefix enters the long-item path: fewer than two bytes after the
   prefix (bDataSize and bLongItemTag) or a payload running past the buffer
   end -> `hid: truncated long item`; a long item is recorded verbatim and
   changes no state;
2. a short item with bSize = 3 (the 4-byte form) ->
   `hid: reserved item size`;
3. a short item with bType = 3 (reserved outside the long prefix) ->
   `hid: reserved item type`;
4. a short tag outside the documented set for its type ->
   `hid: reserved item tag`;
5. a short item whose 1 + bSize bytes run past the buffer end ->
   `hid: truncated item`;
6. structural checks: opening a Collection at depth >=
   `hid_max_collection_depth()` (32) ->
   `hid: collection nesting exceeds limit of 32`; an End Collection with no
   open collection -> `hid: end collection without collection`; a Pop with
   an empty push stack -> `hid: pop without push`;
7. the item is recorded with its computed depth, Push/Pop balance and Usage
   Page.

After the walk: a still-open collection -> `hid: unterminated collection`,
then an unmatched Push -> `hid: unbalanced push` (the collection check runs
first when both are open). An empty buffer is a valid store with zero items.

Consequences of the order: `0xFE` is never reported as a reserved size or
type; `FF` (bSize 3, bType 3) is reported as `reserved item size` because
the size check precedes the type check; `0E` (bType 3, bSize 2) is reported
as `reserved item type`; `00` (main tag 0) is reported as `reserved item
tag`; a truncated `05` (valid Usage Page missing its data byte) is reported
as `truncated item` only after the tag checks pass.

### Collection depth cap

`hid_max_collection_depth()` is 32. A top-level Collection item opens a
collection at depth 0, so the deepest accepted collection is opened at depth
31 (a 32nd nested collection); opening one at depth 32 or deeper is
rejected. The cap error text embeds the literal 32.

### Canonical form and the emitter

Every item accepted by `hid_parse` has exactly one byte encoding, so
`hid_emit` reproduces the input of the producing `hid_parse` byte-for-byte:

- short items: prefix = `size + type*4 + tag*16`, then `size` little-endian
  data bytes (arithmetic only, no bitwise operators);
- long items: `0xFE`, bDataSize, bLongItemTag, then the stored payload;
- items are emitted in stream order; short data bytes are synthesized from
  `item_data` and the size, long payloads are copied from `item_raw`.

An empty store emits zero bytes. Concatenating `hid_item_bytes(d, i)` over
`i` in `[0, hid_item_count(d))` also reproduces the stream exactly (the
tests check both).

`hid_emit` refuses a store that cannot have come from `hid_parse`
(`hid: invalid store`): parallel vectors of different lengths, a short
item's type/tag/size outside the documented domain, a short data value
outside its byte width, a nonzero data value for a size-0 short item or a
long item, a long payload whose length disagrees with `item_size`, or
`item_depth` / `item_stack` / `item_usage_page` values that do not match a
fresh walk of the stored items (including collection and Push/Pop balance).

## Error string catalog

| Condition | Error text |
|---|---|
| short item shorter than 1 + bSize bytes | `hid: truncated item` |
| 0xFE missing bDataSize/bLongItemTag or payload past the buffer | `hid: truncated long item` |
| short bSize = 3 (4-byte form) | `hid: reserved item size` |
| short bType = 3 outside the 0xFE prefix | `hid: reserved item type` |
| short tag outside the documented set for its type | `hid: reserved item tag` |
| Pop with an empty push stack | `hid: pop without push` |
| End Collection with no open collection | `hid: end collection without collection` |
| Collection opening at depth >= 32 | `hid: collection nesting exceeds limit of 32` |
| open collection at end of stream | `hid: unterminated collection` |
| unmatched Push at end of stream | `hid: unbalanced push` |
| accessor index negative or >= item count | `hid: item index out of range` |
| emitter called on a drifted or out-of-domain store | `hid: invalid store` |

When several problems coexist, the first one in the documented order wins.

## Complexity

| Operation | Complexity |
|---|---|
| `hid_parse` | O(data.len()) |
| `hid_emit` | O(emitted size) |
| `hid_item_count` and all O(1) accessors | O(1) |
| `hid_item_data_bytes` / `hid_item_bytes` | O(data size) |

## Documented decisions (summary)

1. The documented subset is closed: reserved tags, the reserved short type
   and the 4-byte short size are rejected on parse instead of being
   preserved. This keeps classification total (every stored item is one of
   the documented ones) and the emitter's domain exact.
2. Long items are first-class raw data, so vendor-specific long payloads
   never break a parse and always re-emit.
3. The store is self-contained (data values and long payloads are copied,
   not spanned), which makes `hid_emit` a real reconstruction rather than a
   copy of the input buffer.
4. Depth is recorded per item with the pairing convention in the item store
   section (a Collection and its End Collection report the same depth), so
   consumers can rebuild the collection tree or match pairs directly.
5. Push/Pop tracking is deliberately minimal: balance is validated and the
   Usage Page is saved/restored, but no other global state is modelled.
6. Signed interpretation is width-based and exposed separately from the
   unsigned value; Unit Exponent gets the nibble-signed form.
7. Usage Page is a per-item recorded value (Push/Pop aware) rather than a
   scan of preceding items, so the accessor is O(1) and correct across
   state restores.

## Test plan

`tests/test_conformance.xi` (`module hid_tests`, 16 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are hand-built hex literals:

- 50-byte canonical mouse descriptor (`05 01 09 02 A1 01 09 01 A1 00 ...`
  with a 3-button block, a 2-axis block and two nested collections), 26
  items;
- 12-byte Push/Pop fixture (`05 01 09 30 A4 05 09 09 01 B4 09 31`), 7
  items, where the Button page is saved and restored;
- 11-byte long-item fixture (`09 01 FE 04 55 DE AD BE EF 81 02`), 3 items,
  plus an empty long item (`FE 00 FF`);
- 51-byte every-documented-tag fixture, 27 items;
- 16-byte signed-interpretation fixture (`15 81`, `25 7F`, `16 FF FF`,
  `26 00 80`, `65 0F`, `65 07`, `65 F8`), 7 items;
- generated nested-collection fixtures at the depth cap boundary.

1. canonical mouse: 26 items, pinned headers, whole-item reassembly,
   byte-exact round-trip;
2. collection depth pinned (0/1/2, End Collection pairing, out of range);
3. Usage Page pinned across the fixture;
4. collection kinds (1 Application, 0 Physical, -1 elsewhere) and usage IDs
   (Usage / Usage Min / Usage Max vs -1);
5. unsigned, per-width signed and nibble-signed interpretations, including
   2-byte sign extension and the size-0/long sentinels;
6. Push/Pop fixture: per-item balance, page save/restore, usage resolution
   after the Pop, round-trip; balanced `A4 B4` pair;
7. `B4` -> pop without push; `A4` -> unbalanced push;
8. `C0` -> end collection without collection; `A1 00` -> unterminated
   collection; `A1 00 C0` parses and round-trips;
9. depth cap: 32 nested collections accepted and round-trip, 33 rejected
   with the exact message, 32 unclosed -> unterminated;
10. long items: type/tag/size/data/raw pinned, data-byte and whole-item
    copies exact, round-trip; empty payload;
11. long-item bounds: `FE`, `FE 00`, short payload, one-byte-short payload;
12. short truncation (`05`, `95`, `1A`) and reserved size (`03`, `83`,
    `FF`), reserved type (`0E`), reserved tags (`00`, `68`, `C4`);
13. out-of-range accessors and the empty descriptor (counts 0, `-1`/0
    sentinels, empty emit);
14. emitter drift guard: tag pop, depth push, raw push, type overwrite all
    `hid: invalid store`; the good store still emits;
15. every documented tag parses, is classified and round-trips;
16. data-byte and whole-item byte copies are exact (size 1, size 2, size 0).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.hid
```

Last verified: compiler 0.61.3,
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The documented subset only; reserved tags and the 4-byte short form are
  rejected instead of preserved or narrowed.
- No builder API from scratch: items are only produced by `hid_parse`
  (a hand-built store can be emitted, but it must satisfy the same
  invariants as a parsed one).
- No report-field assembly, usage tables, Report ID semantics or device IO.
- Push/Pop does not replay the full global item state; only balance and
  Usage Page are tracked.
- Long items are opaque byte payloads; their tag is never interpreted.
- Usage IDs are at most 16-bit (the 4-byte extended usage form is out of
  the subset).
- The depth cap (32) rejects descriptors nested deeper; it is a documented
  subset limit, not a HID specification limit.
- `HidDescriptor` is a plain value type built from parallel vectors; callers
  can corrupt its invariants, and `hid_emit` rejects such stores instead of
  repairing them.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_desc`/`_err_desc`/`_ok_bytes`/`_err_bytes` (constructing struct
  payloads such as `Result[HidDescriptor, Str]` directly in other functions
  miscompiles).
- Vector-of-struct is avoided entirely: the store is eight flat
  scalar/vector fields, each push mirrored through `_add_item`, and
  `hid_emit` refuses drifted stores (`hid: invalid store`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF`; the item
  prefix is decoded and encoded with division/modulo only
  (`size = prefix % 4`, `type = (prefix % 16) / 4`, `tag = prefix / 16`),
  so no bitwise operator touches a value with a sign bit set.
- Every `Vec[Int]` element read is bound to a typed local.
- The library module declares no `use` and no `extern "C"` blocks (no FFI,
  no stdlib imports).
- All parameter type brackets are `Vec[...]` / `Result[...]`; a grep audit
  for `Vec\s*<` / `Result\s*<` after the final green run found none (the
  v0.61.3 compiler accepts malformed angle-bracket parameter types
  silently).
