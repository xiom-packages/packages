# xiom.ext -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ext`, version `0.1.0`).
Module: `src/ext.xi` (`module xiom.ext`).
Depends on `xiom.std`; the library module imports `xiom.string` and
`xiom.encoding.hex` from it (tests add `xiom.test`, `xiom.io`,
`xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) codec for the ext2/3/4 superblock:

- `ext_superblock_parse` decodes the 1024-byte superblock at byte offset
  1024 into a plain `ExtSuperblock` value;
- `ext_superblock_build` writes the canonical 1024-byte block back;
- `ext_superblock_build_image` writes 1024 zero bytes followed by the block,
  so the superblock lands at byte offset 1024 and the result parses;
- one accessor per documented field plus derived helpers and feature-bit
  predicates;
- a documented name table for the common bits of the three feature masks;
- deterministic `Err(Str)` messages for malformed input and for builder
  arguments that cannot be represented on disk.

## Non-goals

- Inode, block-group descriptor, directory, extent and journal parsing.
- Checksum computation/verification (`s_checksum_type` is read raw; no
  checksum is calculated or validated).
- Writing to a device: the package never performs I/O and never mutates a
  buffer in place; callers place the returned bytes.
- Allocation-, mount- or geometry-level interpretation (for example
  group-descriptor placement or `s_first_data_block` consistency).
- Multiple superblock copies/backups: only the primary block at offset 1024
  is read; trailing bytes of the buffer are ignored.
- Full 64-bit count fidelity beyond the documented `Int` range.

## Byte-level layout

The superblock starts at byte offset `EXT_SUPERBLOCK_OFFSET` (1024) and is
`EXT_SUPERBLOCK_SIZE` (1024) bytes, so a complete buffer is at least
`EXT_SUPERBLOCK_MIN_BUFFER` (2048) bytes. Every multi-byte integer is
unsigned little-endian. Offsets below are relative to the start of the
superblock (add 1024 for the volume offset).

| Offset | Width | Field | Notes |
|---|---|---|---|
| 0 | 4 | `s_inodes_count` | must be non-zero |
| 4 | 4 | `s_blocks_count_lo` | low half of the block count |
| 8 | 4 | `s_r_blocks_count_lo` | |
| 12 | 4 | `s_free_blocks_count_lo` | |
| 16 | 4 | `s_free_inodes_count` | |
| 20 | 4 | `s_first_data_block` | raw |
| 24 | 4 | `s_log_block_size` | block size = 1024 << value; 0..6 |
| 28 | 4 | `s_log_cluster_size` | raw |
| 32 | 4 | `s_blocks_per_group` | must be non-zero |
| 36 | 4 | `s_clusters_per_group` | |
| 40 | 4 | `s_inodes_per_group` | must be non-zero |
| 44 | 4 | `s_mtime` | |
| 48 | 4 | `s_wtime` | |
| 52 | 2 | `s_mnt_count` | |
| 54 | 2 | `s_max_mnt_count` | |
| 56 | 2 | `s_magic` | 0xEF53 |
| 58 | 2 | `s_state` | raw |
| 60 | 2 | `s_errors` | raw |
| 62 | 2 | `s_minor_rev_level` | |
| 64 | 4 | `s_lastcheck` | |
| 68 | 4 | `s_checkinterval` | |
| 72 | 4 | `s_creator_os` | raw |
| 76 | 4 | `s_rev_level` | 0 = original, >= 1 = dynamic |
| 80 | 2 | `s_def_resuid` | |
| 82 | 2 | `s_def_resgid` | |
| 84 | 4 | `s_first_ino` | |
| 88 | 2 | `s_inode_size` | >= 128 and <= block size |
| 90 | 2 | `s_block_group_nr` | raw |
| 92 | 4 | `s_feature_compat` | raw mask |
| 96 | 4 | `s_feature_incompat` | raw mask |
| 100 | 4 | `s_feature_ro_compat` | raw mask |
| 104 | 16 | `s_uuid` | exposed as 32 lowercase hex chars |
| 120 | 16 | `s_volume_name` | up to first NUL, trimmed |
| 136 | 64 | `s_last_mounted` | up to first NUL, trimmed |
| 200 | 4 | `s_algo_bitmap` | `s_algorithm_usage_bitmap`, raw |
| 254 | 2 | `s_desc_size` | extension field, read when rev >= 1 |
| 336 | 4 | `s_blocks_count_hi` | extension, read when rev >= 1 |
| 340 | 4 | `s_r_blocks_count_hi` | extension |
| 344 | 4 | `s_free_blocks_count_hi` | extension |
| 348 | 2 | `s_min_extra_isize` | extension |
| 350 | 2 | `s_want_extra_isize` | extension |
| 352 | 4 | `s_flags` | extension, raw |
| 373 | 1 | `s_checksum_type` | extension, raw |

All other bytes of the block are reserved; the builder writes zeros there.

Derived values:

- block size = `1024 << s_log_block_size` for `s_log_block_size` in 0..6
  (1024, 2048, 4096, 8192, 16384, 32768, 65536); the stored value is
  capped at 6, which is why the documented block-size range 1024..65536 is
  checked as a log range. The cap makes every accepted size a power of two.
- combined counts = `lo + hi * 2^32` when the extension fields were read
  (`hi` is 0 otherwise).

## API signatures

All functions are free functions in module `xiom.ext` (no methods):

```xi
pub const EXT_SUPERBLOCK_OFFSET: Int = 1024
pub const EXT_SUPERBLOCK_SIZE: Int = 1024
pub const EXT_SUPERBLOCK_MIN_BUFFER: Int = 2048
pub const EXT_MAGIC: Int = 61267
pub const EXT_MIN_BLOCK_SIZE: Int = 1024
pub const EXT_MAX_BLOCK_SIZE: Int = 65536
pub const EXT_MAX_LOG_BLOCK_SIZE: Int = 6
pub const EXT_MIN_INODE_SIZE: Int = 128
pub const EXT_UUID_LEN: Int = 16
pub const EXT_VOLUME_NAME_LEN: Int = 16
pub const EXT_LAST_MOUNTED_LEN: Int = 64
// plus every documented EXT_FEATURE_* bit (see the name table below)

pub type ExtSuperblock = { ... }   // flat scalar value, no references

pub fn ext_superblock_parse(data: &Vec[UInt8]) -> Result[ExtSuperblock, Str]
pub fn ext_superblock_build(sb: &ExtSuperblock) -> Result[Vec[UInt8], Str]
pub fn ext_superblock_build_image(sb: &ExtSuperblock) -> Result[Vec[UInt8], Str]

// core accessors (one per field)
pub fn ext_inodes_count(sb: &ExtSuperblock) -> Int
pub fn ext_blocks_count_lo(sb: &ExtSuperblock) -> Int
pub fn ext_r_blocks_count_lo(sb: &ExtSuperblock) -> Int
pub fn ext_free_blocks_count_lo(sb: &ExtSuperblock) -> Int
pub fn ext_free_inodes_count(sb: &ExtSuperblock) -> Int
pub fn ext_first_data_block(sb: &ExtSuperblock) -> Int
pub fn ext_log_block_size(sb: &ExtSuperblock) -> Int
pub fn ext_block_size(sb: &ExtSuperblock) -> Int
pub fn ext_log_cluster_size(sb: &ExtSuperblock) -> Int
pub fn ext_blocks_per_group(sb: &ExtSuperblock) -> Int
pub fn ext_clusters_per_group(sb: &ExtSuperblock) -> Int
pub fn ext_inodes_per_group(sb: &ExtSuperblock) -> Int
pub fn ext_mtime(sb: &ExtSuperblock) -> Int
pub fn ext_wtime(sb: &ExtSuperblock) -> Int
pub fn ext_mnt_count(sb: &ExtSuperblock) -> Int
pub fn ext_max_mnt_count(sb: &ExtSuperblock) -> Int
pub fn ext_magic(sb: &ExtSuperblock) -> Int
pub fn ext_state(sb: &ExtSuperblock) -> Int
pub fn ext_errors(sb: &ExtSuperblock) -> Int
pub fn ext_minor_rev_level(sb: &ExtSuperblock) -> Int
pub fn ext_lastcheck(sb: &ExtSuperblock) -> Int
pub fn ext_checkinterval(sb: &ExtSuperblock) -> Int
pub fn ext_creator_os(sb: &ExtSuperblock) -> Int
pub fn ext_rev_level(sb: &ExtSuperblock) -> Int
pub fn ext_def_resuid(sb: &ExtSuperblock) -> Int
pub fn ext_def_resgid(sb: &ExtSuperblock) -> Int
pub fn ext_first_ino(sb: &ExtSuperblock) -> Int
pub fn ext_inode_size(sb: &ExtSuperblock) -> Int
pub fn ext_block_group_nr(sb: &ExtSuperblock) -> Int
pub fn ext_feature_compat(sb: &ExtSuperblock) -> Int
pub fn ext_feature_incompat(sb: &ExtSuperblock) -> Int
pub fn ext_feature_ro_compat(sb: &ExtSuperblock) -> Int
pub fn ext_uuid_hex(sb: &ExtSuperblock) -> Str
pub fn ext_volume_name(sb: &ExtSuperblock) -> Str
pub fn ext_last_mounted(sb: &ExtSuperblock) -> Str
pub fn ext_algo_bitmap(sb: &ExtSuperblock) -> Int

// ext4 extension accessors (0 when s_rev_level == 0)
pub fn ext_blocks_count_hi(sb: &ExtSuperblock) -> Int
pub fn ext_r_blocks_count_hi(sb: &ExtSuperblock) -> Int
pub fn ext_free_blocks_count_hi(sb: &ExtSuperblock) -> Int
pub fn ext_min_extra_isize(sb: &ExtSuperblock) -> Int
pub fn ext_want_extra_isize(sb: &ExtSuperblock) -> Int
pub fn ext_flags(sb: &ExtSuperblock) -> Int
pub fn ext_checksum_type(sb: &ExtSuperblock) -> Int
pub fn ext_desc_size(sb: &ExtSuperblock) -> Int
pub fn ext_has_ext_fields(sb: &ExtSuperblock) -> Bool
pub fn ext_blocks_count(sb: &ExtSuperblock) -> Int
pub fn ext_r_blocks_count(sb: &ExtSuperblock) -> Int
pub fn ext_free_blocks_count(sb: &ExtSuperblock) -> Int

// feature bits
pub fn ext_has_feature_compat(sb: &ExtSuperblock, mask: Int) -> Bool
pub fn ext_has_feature_incompat(sb: &ExtSuperblock, mask: Int) -> Bool
pub fn ext_has_feature_ro_compat(sb: &ExtSuperblock, mask: Int) -> Bool
pub fn ext_feature_compat_name(mask: Int) -> Str
pub fn ext_feature_incompat_name(mask: Int) -> Str
pub fn ext_feature_ro_compat_name(mask: Int) -> Str
```

## Semantics

`ext_superblock_parse(data)`
: Requires `data.len() >= 2048`, then validates in the catalog order below
  and reads every core field. When `s_rev_level >= 1` the extension fields
  are read and `ext_has_ext_fields` is true; when it is 0 the extension
  region is ignored and those fields read as 0. The result holds no
  reference into `data`.

`ext_superblock_build(sb)`
: Validates in the catalog order (including the uuid and name checks), then
  emits exactly 1024 bytes. Extension fields are written exactly when
  `s_rev_level >= 1`; `sb.has_ext` is ignored. `s_magic` is written as
  0xEF53 from the validated `sb.magic`; reserved bytes and NUL padding are
  zero. Nothing is emitted on `Err`.

`ext_superblock_build_image(sb)`
: `ext_superblock_build` followed by a 1024-byte zero prefix; exactly 2048
  bytes, directly accepted by `ext_superblock_parse`.

`ext_has_feature_*(sb, mask)`
: True when every bit set in `mask` is set in the corresponding mask. A
  `mask` of 0 is vacuously true; bits above 31 and unknown bits are handled
  arithmetically (division by powers of two, never shifts), so a mask with
  bit 31 set works.

`ext_feature_*_name(mask)`
: Maps exactly one documented single bit to its kernel-style name; returns
  `""` for 0, for multi-bit masks and for undocumented bits.

`ext_block_size(sb)`
: `1024 << s_log_block_size`, or `-1` when a hand-built struct stores a
  value outside 0..6.

`ext_blocks_count(sb)` / `ext_r_blocks_count(sb)` / `ext_free_blocks_count(sb)`
: `lo + hi * 2^32`; `hi` is 0 for a parsed rev-0 superblock.

## Error string catalog

Parse (`ext_superblock_parse`), first failure wins:

| Condition | Error text |
|---|---|
| `data.len() < 2048` | `ext: truncated buffer` |
| `s_magic != 0xEF53` | `ext: bad magic` |
| `s_log_block_size` outside 0..6 | `ext: bad log block size` |
| `s_inode_size < 128` or `s_inode_size > block size` | `ext: bad inode size` |
| `s_inodes_count == 0` | `ext: bad inode count` |
| combined block count == 0 | `ext: bad block count` |
| `s_blocks_per_group == 0` | `ext: bad blocks per group` |
| `s_inodes_per_group == 0` | `ext: bad inodes per group` |

Builder (`ext_superblock_build`, `ext_superblock_build_image`), first
failure wins; the first eight conditions are the same checks in the same
order, then:

| Condition | Error text |
|---|---|
| `sb.uuid_hex` is not 32 hex characters decoding to 16 bytes | `ext: bad uuid` |
| `sb.volume_name` longer than 16 bytes or contains a NUL | `ext: bad volume name` |
| `sb.last_mounted` longer than 64 bytes or contains a NUL | `ext: bad last mounted path` |
| any scalar outside its unsigned width (`u8`/`u16`/`u32`), negative included | `ext: field out of range` |

For the block count and the extension fields the builder folds the same
values parse would read: `blocks_count_lo + blocks_count_hi * 2^32`, with
the extension fields participating only when `s_rev_level >= 1`.

## Feature name table

| Mask | Name | | Mask | Name |
|---|---|---|---|---|
| compat 1 | `COMPAT_DIR_PREALLOC` | | incompat 1 | `INCOMPAT_COMPRESSION` |
| compat 2 | `COMPAT_IMAGIC_INODES` | | incompat 2 | `INCOMPAT_FILETYPE` |
| compat 4 | `COMPAT_HAS_JOURNAL` | | incompat 4 | `INCOMPAT_RECOVER` |
| compat 8 | `COMPAT_EXT_ATTR` | | incompat 8 | `INCOMPAT_JOURNAL_DEV` |
| compat 16 | `COMPAT_RESIZE_INODE` | | incompat 16 | `INCOMPAT_META_BG` |
| compat 32 | `COMPAT_DIR_INDEX` | | incompat 64 | `INCOMPAT_EXTENTS` |
| compat 512 | `COMPAT_SPARSE_SUPER2` | | incompat 128 | `INCOMPAT_64BIT` |
| compat 1024 | `COMPAT_FAST_COMMIT` | | incompat 256 | `INCOMPAT_MMP` |
| compat 2048 | `COMPAT_STABLE_INODES` | | incompat 512 | `INCOMPAT_FLEX_BG` |
| compat 4096 | `COMPAT_ORPHAN_FILE` | | incompat 1024 | `INCOMPAT_EA_INODE` |
| | | | incompat 4096 | `INCOMPAT_DIRDATA` |
| ro 1 | `RO_COMPAT_SPARSE_SUPER` | | incompat 8192 | `INCOMPAT_CSUM_SEED` |
| ro 2 | `RO_COMPAT_LARGE_FILE` | | incompat 16384 | `INCOMPAT_LARGEDIR` |
| ro 4 | `RO_COMPAT_BTREE_DIR` | | incompat 32768 | `INCOMPAT_INLINE_DATA` |
| ro 8 | `RO_COMPAT_HUGE_FILE` | | incompat 65536 | `INCOMPAT_ENCRYPT` |
| ro 16 | `RO_COMPAT_GDT_CSUM` | | incompat 131072 | `INCOMPAT_CASEFOLD` |
| ro 32 | `RO_COMPAT_DIR_NLINK` | | | |
| ro 64 | `RO_COMPAT_EXTRA_ISIZE` | | | |
| ro 256 | `RO_COMPAT_QUOTA` | | | |
| ro 512 | `RO_COMPAT_BIGALLOC` | | | |
| ro 1024 | `RO_COMPAT_METADATA_CSUM` | | | |
| ro 2048 | `RO_COMPAT_REPLICA` | | | |
| ro 4096 | `RO_COMPAT_READONLY` | | | |
| ro 8192 | `RO_COMPAT_PROJECT` | | | |
| ro 32768 | `RO_COMPAT_VERITY` | | | |
| ro 65536 | `RO_COMPAT_ORPHAN_PRESENT` | | | |

## Complexity

| Operation | Complexity |
|---|---|
| `ext_superblock_parse` | O(1) (bounded 1024-byte block) |
| every accessor / predicate / name lookup | O(1) |
| `ext_superblock_build` | O(1) |
| `ext_superblock_build_image` | O(1) |

## Test plan

`tests/test_conformance.xi` (`module ext_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Every fixture is assembled byte by byte in the
test file, so the codec is exercised against bytes the test controls.
Coverage:

1. hand-built core (rev 0) superblock: every pinned field and accessor,
   including `has_ext` false and the extension accessors reporting 0;
2. buffer bounds: 2047/1024/empty are `ext: truncated buffer`; a
   superblock-shaped block at offset 0 is `ext: bad magic`; 2048 parses;
3. `s_magic` must be exactly 0xEF53 (0 and 0xEF52 rejected);
4. log block size 0..6 maps to 1024..65536 through `ext_block_size`;
   values 7 and 9 are `ext: bad log block size`;
5. inode size: 127 is rejected, 128/256/2048 (block 2048) accepted,
   1024 accepted with a 1024-byte block, 1025/4096 rejected;
6. each documented zero count is rejected with its own message; a zero low
   half with a nonzero high half is a valid 64-bit count;
7. feature predicates: single, multi-bit (all bits required), missing bit,
   and a vacuous mask of 0, on all three masks;
8. rev >= 1 fixture: `has_ext`, all extension accessors, combined
   `ext_blocks_count` = `lo + 2^32`;
9. the same ext4 bytes with rev 0: extension region ignored, accessors 0,
   combined count = `lo`;
10. feature name table: exact names for documented bits and `""` for 0,
    multi-bit and undocumented masks;
11. builder core output is byte-identical to the fixture (1024 bytes,
    magic bytes 0x53/0xEF at offsets 56/57);
12. `ext_superblock_build_image`: 2048 bytes, first 1024 all zero, block
    equal to `ext_superblock_build`, parses back;
13. ext4 build is byte-identical to the fixture and round-trips through
    parse with every extension field preserved;
14. builder rejects bad magic, bad log size, bad inode size, zero counts,
    bad uuid (short, odd, non-hex), over-long names, and out-of-range
    `u16`/`u32`/`u8` scalars with the exact catalog messages;
15. name fields: a full 16-byte name is preserved, NUL-padded and
    space-padded fields are trimmed, an all-NUL field is "";
16. `s_uuid` renders as 32 lowercase hex characters (two pinned vectors);
17. parse -> build reproduces the fixture block and re-parse is stable; a
    trimmed name survives parse -> build -> parse;
18. derived accessors: block-size table (1024..65536), `-1` for a
    hand-built log 7, and the `lo`-only combined counts;
19. high halves of the reserved/free counts fold into the combined
    accessors (`lo + n * 2^32`);
20. extension fields are written exactly when `s_rev_level >= 1`: garbage
    in a rev-0 struct is ignored; rev 1 writes them even when `has_ext`
    was not set by parse.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ext
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Superblock only; no inode/block-group/directory/extent/journal parsing
  and no checksum computation.
- The parser needs at least 2048 bytes (the whole block at offset 1024);
  a bare 1024-byte superblock does not parse. Build images with
  `ext_superblock_build_image` when `ext_superblock_parse` will consume
  them.
- Extension fields are keyed on `s_rev_level` alone; `sb.has_ext` is a
  parse-side report and is ignored by the builder. An ext4 64-bit feature
  mask with rev 0 has its extension fields ignored, matching the pinned
  rule.
- `s_inode_size` below 128 is rejected, so a rev-0 superblock storing 0
  (which ext2 would read as 128) is treated as malformed.
- Combined counts with `hi >= 2^31` exceed `Int` range; only the halves are
  exact there.
- `ext_block_size` reports `-1` for a hand-built struct with log outside
  0..6; the parser can never produce that.
- Name fields are trimmed and decoded as UTF-8; bytes after the first NUL
  are dropped and printability is not validated (the builder does reject
  embedded NULs to keep round trips honest).
- No validation of `s_first_data_block`, `s_log_cluster_size`,
  `s_state`/`s_errors` codes, feature-mask combinations or geometry
  equations; those fields are documented as raw.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_sb`/`_err_sb`/`_ok_bytes`/`_err_bytes`/`_ok_unit`/`_err_unit`
  (constructing Results directly in other functions miscompiles in this
  compiler).
- All little-endian reads/packs are arithmetic (modulo/division) because
  `& 0xFF` on operands with bit 31 set miscompiles; feature bit tests
  divide by powers of two instead of shifting or masking.
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic.
- `&struct.field`/`&result.value` are bound to typed locals before being
  passed to `&Vec` parameters.
- Str comparisons in the tests go through
  `xiom.string.compare.str_compare` (BUG 17: `==` on Str values can lower
  to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI) and no
  `Vec[StructType]`.
