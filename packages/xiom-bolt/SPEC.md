# xiom.bolt -- byte-level specification

This document specifies exactly what `src/bolt.xi` parses. It describes the
on-disk layout of **bbolt** (etcd-io/bbolt) database files as implemented
here, the validation order, the error catalog and the test plan. Everything is
little-endian. All values are parsed into `Int` (64-bit signed); a raw u64
whose bit 63 is set decodes as a negative `Int` (raw two's-complement
convention, same as `xiom.pack`).

The parser is read-only: it takes the whole database image as a
`Vec[UInt8]` and returns offsets/sizes into it. No mmap, no I/O, no writes.

## 1. Page header (16 bytes)

Every page starts with `pageHeaderSize = 16` bytes:

| Offset | Size | Field    | Notes |
|--------|------|----------|-------|
| 0      | 8    | id       | u64 pgid of this page |
| 8      | 2    | flags    | page type bits (below) |
| 10     | 2    | count    | element count for branch/leaf/freelist |
| 12     | 4    | overflow | number of additional pages this page spans |

Flags:

| Bit  | Name            | Meaning |
|------|-----------------|---------|
| 0x01 | branchPageFlag  | branch page (B+tree interior) |
| 0x02 | leafPageFlag    | leaf page |
| 0x04 | metaPageFlag    | meta page |
| 0x10 | freelistPageFlag| freelist page |

`bolt_read_page(data, page_size, pgid)` reads the page at
`offset = pgid * page_size` and fills `BoltPage { page_id, flags, count,
overflow, offset, size, inline=false }`. Validation:

1. `page_size` must be a power of two in `[1024, 65536]` (`_page_size_ok`,
   checked by halving) else `bolt: bad page size`.
2. `pgid` must be `>= 0` and `< data.len() / page_size` (whole pages only),
   else `bolt: page id out of range: <pgid>`.
3. `flags` must be in `1..31` (at least one known bit, no unknown bit), else
   `bolt: unknown page flags at <offset>`. Combined/branch-flag semantics are
   checked by the element readers and the walk, not here.

Auxiliary accessors: `bolt_page_id`, `bolt_page_flags`, `bolt_page_count`,
`bolt_page_overflow`, `bolt_page_offset`, `bolt_page_span`,
`bolt_page_is_inline`.

## 2. Meta page

A bbolt file has two meta pages, at file offsets 0 and `page_size`. Within a
page, the 64-byte meta struct starts after the 16-byte page header:

| Page offset | Meta offset | Size | Field |
|-------------|-------------|------|-------|
| 0  | --  | 8  | page header id (written as `txid % 2`) |
| 8  | --  | 2  | page header flags (`0x04`) |
| 10 | --  | 2  | page header count (0) |
| 12 | --  | 4  | page header overflow (0) |
| 16 | 0   | 4  | magic = `0xED0CDAED` |
| 20 | 4   | 4  | version = 2 |
| 24 | 8   | 4  | pageSize |
| 28 | 12  | 4  | flags |
| 32 | 16  | 8  | root bucket root pgid |
| 40 | 24  | 8  | root bucket sequence |
| 48 | 32  | 8  | freelist pgid |
| 56 | 40  | 8  | pgid (high-water mark) |
| 64 | 48  | 8  | txid |
| 72 | 56  | 8  | checksum (u64) |

The checksum is **FNV-1a-64 over the 56 meta bytes that precede it**
(page offsets 16..72), i.e. the meta struct without its trailing checksum
field -- this is exactly bbolt's `meta.sum64()`. FNV-1a-64 uses the standard
offset basis `0xCBF29CE484222325` and prime `0x100000001B3`; multiplication
wraps modulo 2^64 and the raw bit pattern is compared.

`bolt_meta_read(data)`:

1. Requires at least 80 bytes (`BOLT_META_REQUIRED`), else
   `bolt: truncated meta`.
2. Reads `pageSize` from page 0 offset 24; the power-of-two policy applies,
   else `bolt: bad page size`. (Only meta 0's field is consulted -- there is
   no OS fallback as in bbolt, see section 7.)
3. Requires `data.len() >= 2 * page_size`, else `bolt: truncated meta`.
4. Decodes both pages. A page is **valid** when:
   - `magic == 0xED0CDAED`,
   - `version == 2`,
   - `page_size` field `==` the page size the file was read with,
   - `checksum == FNV-1a-64(page[off+16 .. off+72])`.
5. If neither is valid: `bolt: no valid meta page at offset 0 or <page_size>`.
6. Selection: meta 1 when it is the only valid page or when both are valid
   and `m1.txid > m0.txid`; meta 0 otherwise (ties go to meta 0).
   `BoltMetaPair.selected` is `BOLT_SELECT_META0` / `BOLT_SELECT_META1`.

Reported per page: `offset`, header `page_id`/`page_flags`, all meta fields,
`checksum` (stored), `computed_checksum`, `valid`. Accessors:
`bolt_meta_selected`, `bolt_meta_at`, `bolt_meta_selected_meta`,
`bolt_meta_field`, `bolt_meta_valid`, `bolt_meta_selected_field`,
`bolt_meta_checksum`.

## 3. Branch page elements

`count` (page header) 16-byte elements start at page offset 16:

| Element offset | Size | Field |
|----------------|------|-------|
| 0 | 4 | pos |
| 4 | 4 | ksize |
| 8 | 8 | pgid |

The key bytes are at `element_offset + pos`, `ksize` bytes long (values may
point forward into the page after the element array). `bolt_branch_field`
selectors: `POS`, `KSIZE`, `PGID`, `OFFSET` (absolute element offset),
`KEY_OFFSET`. Every call re-validates: page is a branch page, element index in
`[0, count)`, element and key spans inside the page, `pgid >= 0` and
`pgid < data.len() / page.size`.

### Clarification: the "page pointer array"

The port brief described a u16 offset array at the page end with `0xFFFF`
marking empty slots. That layout does **not** exist in bbolt: the child page
pointer is the **u64 `pgid` field of each branch element**, and branch pages
have no empty slots. `bolt_branch_child_pgids` implements the real child
pointer array (one pgid per element, in element order, each fully validated).

## 4. Leaf page elements

`count` 16-byte elements start at page offset 16:

| Element offset | Size | Field |
|----------------|------|-------|
| 0  | 4 | flags (bit 0: bucket leaf) |
| 4  | 4 | pos |
| 8  | 4 | ksize |
| 12 | 4 | vsize |

Key bytes at `element_offset + pos` (`ksize` bytes); value bytes immediately
after the key (`vsize` bytes). `bolt_leaf_field` selectors: `FLAGS`, `POS`,
`KSIZE`, `VSIZE`, `OFFSET`, `KEY_OFFSET`, `VALUE_OFFSET`. Every call
re-validates the element, key and value spans against the page.

### Bucket leaf values

When `flags % 2 == 1` the value is a bucket:

| Value offset | Size | Field |
|--------------|------|-------|
| 0 | 8 | root pgid |
| 8 | 8 | sequence |

- `bolt_leaf_is_bucket` tests the bucket flag.
- `bolt_leaf_is_inline_bucket` is true when the bucket flag is set **and**
  `vsize > 16`.
- `bolt_leaf_bucket_field` decodes `ROOT` / `SEQUENCE` (value must be at
  least 16 bytes).
- `bolt_inline_page` decodes the inline page image at `value_offset + 16`,
  spanning `vsize - 16` bytes. The returned `BoltPage` has `inline = true`,
  `offset = value_offset + 16`, `size = vsize - 16`; the image must be a leaf
  page with a full 16-byte header. Element accessors then work on the inline
  page with its reduced span.

## 5. Freelist page

Payload words (u64 pgids) start at page offset 16 and, when
`header overflow > 0`, continue across that many following pages.

- Normal list: `count` (u16) payload words are the free pgids.
- Overflow list: the header `count` equals the sentinel `0xFFFF`; the true
  element count is the **first u64 payload word**, and the pgids follow it.

`bolt_freelist_count` validates that the page plus its continuation pages fit
the buffer and that the count fits in the payload span
(`(span - 16) / 8` words, minus the count word for the sentinel), else
`bolt: freelist count out of bounds`. `bolt_freelist_pgid` additionally
requires the pgid to be in `[0, data.len() / page.size)`.
`bolt_freelist_pgids` collects the whole list.

### Clarification: the "count u32"

The brief mentioned a u32 count field. bbolt has no such field: the count is
the **u16 page-header count**, and the overflow sentinel stores the true count
as a **u64 payload word**. That is what is implemented.

## 6. Bounded tree walk

`bolt_walk_tree(data, page_size, root_pgid, max_depth)` performs an explicit
depth-first, in-order traversal:

- Children of a branch page are pushed in reverse element order so child 0 is
  processed first; leaf entries are appended in element order. For a
  well-formed bbolt tree (sorted pages, no shared pages) this yields the
  global key order.
- Depth 1 is the root. Before pushing a child at depth `d + 1`,
  `d + 1 > max_depth` fails.
- A page id visited twice fails (`bolt: page revisited in walk: <pgid>`).
- Leaf keys must compare non-decreasing byte-wise against the previous key
  (across page boundaries too), else
  `bolt: leaf keys out of order at page <pgid> element <i>`.
- Meta and freelist pages reached by the walk fail
  (`bolt: not a tree page at <pgid>`).

Result `BoltWalk` is flat parallel vectors, always pushed together:
`page_ids`, `depths`, `key_offsets`, `key_sizes`, `value_offsets`,
`value_sizes`, `elem_flags` (one entry per leaf element, in key order) plus
`leaf_count`. Accessors: `bolt_walk_count`, `bolt_walk_leaf_count`,
`bolt_walk_field` (selectors `KEY_OFFSET`, `KEY_SIZE`, `VALUE_OFFSET`,
`VALUE_SIZE`, `FLAGS`, `PAGE_ID`, `DEPTH`), `bolt_walk_key_str`,
`bolt_walk_value_str`.

## 7. Documented deviations and limitations

1. **Branch child pointers** are u64 element `pgid` fields, not a u16 offset
   array (section 3).
2. **Freelist count** is the u16 header count / first u64 payload word, not a
   standalone u32 (section 5).
3. **Checksum policy**: bbolt's own `meta.validate()` skips the check when the
   stored checksum is 0 (compatibility with pre-checksum files). This parser
   always verifies: a zero checksum matches only if the computed hash is
   itself zero.
4. **Page-size discovery** uses meta page 0 only. bbolt falls back to the OS
   page size when meta 0 is unreadable; here a corrupt page-size field is
   fatal (`bolt: bad page size`) because there is no OS to ask.
5. **Whole pages only**: every page access requires the complete page (and
   the complete continuation span for a freelist) in the buffer. Truncated
   files are rejected rather than partially parsed.
6. **`BoltMeta.page_size` equality**: a meta page whose own page-size field
   differs from the file's page size is reported invalid. bbolt would use
   meta 0's field for mmap and still accept a differing meta 1; this parser
   treats the difference as a consistency failure.
7. **No UTF-8 validation** in `bolt_span_str` / `bolt_walk_*_str`: bytes are
   copied verbatim into a `Str`.
8. `BOLT_PGID_NO_FREELIST` documents bbolt's `0xFFFFFFFFFFFFFFFF` pgid
   (decodes as -1) written when freelist syncing is disabled; it is only a
   constant, no policy is applied.

## 8. Error catalog

All errors are `Err(<Str>)` with a `bolt: ` prefix; offsets/page ids are
decimal.

| Message | Raised by |
|---------|-----------|
| `bolt: bad page size` | `bolt_read_page`, `bolt_meta_read`, `bolt_walk_tree` |
| `bolt: page id out of range: <pgid>` | `bolt_read_page` |
| `bolt: unknown page flags at <off>` | `bolt_read_page` |
| `bolt: truncated meta` | `bolt_meta_read` |
| `bolt: no valid meta page at offset 0 or <ps>` | `bolt_meta_read` |
| `bolt: meta page out of bounds` | `bolt_meta_checksum` |
| `bolt: meta index out of range` | `bolt_meta_at` |
| `bolt: bad field selector` | all `*_field` readers |
| `bolt: not a branch page` | `bolt_branch_field`, `bolt_branch_child_pgids` |
| `bolt: branch element index out of range` | `bolt_branch_field` |
| `bolt: branch element out of page bounds at <off>` | `bolt_branch_field` |
| `bolt: branch element key out of page bounds at <off>` | `bolt_branch_field` |
| `bolt: branch element page id out of range at <off>` | `bolt_branch_field` |
| `bolt: not a leaf page` | `bolt_leaf_field` |
| `bolt: leaf element index out of range` | `bolt_leaf_field` |
| `bolt: leaf element out of page bounds at <off>` | `bolt_leaf_field` |
| `bolt: leaf element key out of page bounds at <off>` | `bolt_leaf_field` |
| `bolt: leaf element value out of page bounds at <off>` | `bolt_leaf_field` |
| `bolt: leaf element is not a bucket` | bucket readers |
| `bolt: bucket value too short` | `bolt_leaf_bucket_field` |
| `bolt: bucket is not inline` | `bolt_inline_page` |
| `bolt: truncated inline page at <off>` | `bolt_inline_page` |
| `bolt: inline page is not a leaf page at <off>` | `bolt_inline_page` |
| `bolt: not a freelist page` | `bolt_freelist_*` |
| `bolt: bad freelist overflow` | `_freelist_avail` |
| `bolt: freelist out of bounds at <off>` | `_freelist_avail` |
| `bolt: freelist count out of bounds` | `bolt_freelist_count` |
| `bolt: freelist index out of range` | `bolt_freelist_pgid` |
| `bolt: freelist page id out of range at <off>` | `bolt_freelist_pgid` |
| `bolt: bad walk depth cap` | `bolt_walk_tree` |
| `bolt: root page id out of range: <pgid>` | `bolt_walk_tree` |
| `bolt: page revisited in walk: <pgid>` | `bolt_walk_tree` |
| `bolt: tree too deep at page <pgid> (cap <n>)` | `bolt_walk_tree` |
| `bolt: not a tree page at <pgid>` | `bolt_walk_tree` |
| `bolt: leaf keys out of order at page <pgid> element <i>` | `bolt_walk_tree` |
| `bolt: walk index out of range` | `bolt_walk_field`, `bolt_walk_*_str` |
| `bolt: span out of bounds` | `bolt_fnv1a64`, `bolt_span_bytes`, `bolt_span_str` |

## 9. Test plan (`tests/test_conformance.xi`, 18 checks)

All fixtures are assembled byte by byte inside the test (independent of
`src/bolt.xi`), and every expected value is a pinned constant or an exact
error string.

| Test | Covers |
|------|--------|
| t1 | FNV-1a-64 known vectors (offset basis, `"a"`, 56 zeros, 4 zeros) and span bounds |
| t2 | meta pair: fields, `page_id = txid % 2`, checksum = `bolt_meta_checksum`, higher-txid selection, selector errors |
| t3 | invalid meta fallback (either side), checksum mismatch reported, txid tie -> meta 0 |
| t4 | meta errors: bad magic pair, page-size policy, truncation, checksum bounds |
| t5 | page-size boundaries 1024/2048/4096/65536 accepted; 0/512/1000/3000/131072 rejected |
| t6 | page header fields/accessors, unknown flags, page-id bounds |
| t7 | branch selectors, child pointer array, index/type/selector errors |
| t8 | branch consistency: corrupt key pointer, out-of-range/negative pgid, element span |
| t9 | leaf selectors, key/value spans, non-bucket errors |
| t10 | leaf consistency: corrupt value pointer, element span, span-copy bounds |
| t11 | bucket values: header, inline page decode, inline leaf element, non-inline bucket |
| t12 | freelist count/pgids/index/type |
| t13 | freelist pgid bounds, count overflow, continuation span bounds |
| t14 | 0xFFFF sentinel: count word, zero count, huge/negative count, 200-entry continuation list |
| t15 | walk order, spans, depths, page ids, direct leaf root |
| t16 | depth cap: 3-level chain at cap 3 and cap 2, cap 0 |
| t17 | out-of-order keys, cycle, bad child pointer, meta/freelist roots, root bounds |
| t18 | multi-byte/prefix keys, empty value, walk accessors, span bounds |
