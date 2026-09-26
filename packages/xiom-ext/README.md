# xiom.ext

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM ext2/3/4 superblock codec: parse and build the
> 1024-byte superblock that lives at byte offset 1024 of the volume.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` and
> `xiom.encoding.hex` from it; the tests add `xiom.test`, `xiom.io` and
> `xiom.string.compare`. No FFI.

## What it is

`xiom.ext` decodes the ext2/ext3/ext4 superblock and can write a canonical
one back. `ext_superblock_parse` validates the magic, the block-size and
inode-size rules and the documented non-zero counts, then exposes every core
field plus the ext4 extension fields (read when `s_rev_level >= 1`) through
free accessors. The uuid is returned as 32 lowercase hex characters,
`s_volume_name`/`s_last_mounted` are read up to the first NUL and trimmed,
and feature masks are raw `u32` values with a documented name table and
bit predicates.

`ext_superblock_build` emits the canonical 1024-byte block for the same
field set; `ext_superblock_build_image` prepends 1024 zero bytes so the
block lands at byte offset 1024 and the result parses directly.

## API

| Function | Returns | Description |
|---|---|---|
| `ext_superblock_parse(data)` | `Result[ExtSuperblock, Str]` | Parse the superblock at byte offset 1024 (buffer >= 2048). |
| `ext_superblock_build(sb)` | `Result[Vec[UInt8], Str]` | Emit the canonical 1024-byte superblock block. |
| `ext_superblock_build_image(sb)` | `Result[Vec[UInt8], Str]` | Emit 1024 zero bytes + the block (2048 bytes). |
| `ext_has_feature_compat(sb, mask)` | `Bool` | Every bit of `mask` set in `s_feature_compat`. |
| `ext_has_feature_incompat(sb, mask)` | `Bool` | Every bit of `mask` set in `s_feature_incompat`. |
| `ext_has_feature_ro_compat(sb, mask)` | `Bool` | Every bit of `mask` set in `s_feature_ro_compat`. |
| `ext_feature_compat_name(mask)` | `Str` | Kernel-style name of one documented bit (`""` otherwise). |
| `ext_feature_incompat_name(mask)` | `Str` | Same for `s_feature_incompat`. |
| `ext_feature_ro_compat_name(mask)` | `Str` | Same for `s_feature_ro_compat`. |

Core-field accessors (all `O(1)`): `ext_inodes_count`,
`ext_blocks_count_lo`, `ext_r_blocks_count_lo`, `ext_free_blocks_count_lo`,
`ext_free_inodes_count`, `ext_first_data_block`, `ext_log_block_size`,
`ext_block_size` (derived `1024 << value`, `-1` outside `0..6`),
`ext_log_cluster_size`, `ext_blocks_per_group`, `ext_clusters_per_group`,
`ext_inodes_per_group`, `ext_mtime`, `ext_wtime`, `ext_mnt_count`,
`ext_max_mnt_count`, `ext_magic`, `ext_state`, `ext_errors`,
`ext_minor_rev_level`, `ext_lastcheck`, `ext_checkinterval`,
`ext_creator_os`, `ext_rev_level`, `ext_def_resuid`, `ext_def_resgid`,
`ext_first_ino`, `ext_inode_size`, `ext_block_group_nr`,
`ext_feature_compat`, `ext_feature_incompat`, `ext_feature_ro_compat`,
`ext_uuid_hex`, `ext_volume_name`, `ext_last_mounted`, `ext_algo_bitmap`.

Extension accessors (0 when `s_rev_level == 0`): `ext_blocks_count_hi`,
`ext_r_blocks_count_hi`, `ext_free_blocks_count_hi`, `ext_min_extra_isize`,
`ext_want_extra_isize`, `ext_flags`, `ext_checksum_type`, `ext_desc_size`,
`ext_has_ext_fields`, and the derived `ext_blocks_count`,
`ext_r_blocks_count`, `ext_free_blocks_count`
(`lo + hi * 2^32`).

Public constants: `EXT_SUPERBLOCK_OFFSET` (1024), `EXT_SUPERBLOCK_SIZE`
(1024), `EXT_SUPERBLOCK_MIN_BUFFER` (2048), `EXT_MAGIC` (0xEF53), the
documented block-size range (`EXT_MIN_BLOCK_SIZE`, `EXT_MAX_BLOCK_SIZE`,
`EXT_MAX_LOG_BLOCK_SIZE`) and every documented feature bit
(`EXT_FEATURE_COMPAT_*`, `EXT_FEATURE_INCOMPAT_*`,
`EXT_FEATURE_RO_COMPAT_*`).

Errors: `ext: truncated buffer`, `ext: bad magic`,
`ext: bad log block size`, `ext: bad inode size`, `ext: bad inode count`,
`ext: bad block count`, `ext: bad blocks per group`,
`ext: bad inodes per group`, `ext: bad uuid`, `ext: bad volume name`,
`ext: bad last mounted path`, `ext: field out of range`
(see SPEC.md for the exact conditions and check order).

## Usage

```xi
use xiom.ext;
use xiom.io;

// Parse a 2048-byte prefix read from offset 0 of the volume.
let data = read_prefix();
let r = ext_superblock_parse(&data);
match r {
  Ok(sb) => {
    io.println("block size: " + xiom.convert.int_to_string(ext_block_size(&sb)));
    io.println("uuid: " + ext_uuid_hex(&sb));
    io.println("volume: " + ext_volume_name(&sb));
    if ext_has_feature_incompat(&sb, EXT_FEATURE_INCOMPAT_64BIT) {
      io.println("blocks: " + xiom.convert.int_to_string(ext_blocks_count(&sb)));
    }
  },
  Err(e) => { io.println("not an ext superblock: " + e); },
}
```

```xi
// Build a canonical ext2-style block and its 2048-byte image.
let br = ext_superblock_build(&sb);
if br.is_ok {
  let image = ext_superblock_build_image(&sb);  // superblock at offset 1024
  // write image to the volume prefix
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ext
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Superblock only.** No inode, block-group, directory, extent or journal
  parsing, and no checksum computation or verification.
- **Buffer >= 2048.** The parser needs the whole 1024-byte superblock at
  offset 1024, so a buffer of at least 2048 bytes is required; a 1024-byte
  block alone is not enough (use `ext_superblock_build_image` to build an
  image that parses).
- **Extension fields are keyed on `s_rev_level` only.** They are read and
  written exactly when `s_rev_level >= 1` (as the task pins); the builder
  ignores `sb.has_ext`.
- **Strict `s_inode_size`.** Values below 128 are rejected. A revision-0
  superblock that stores 0 (which ext2 interprets as 128) is rejected as
  malformed; this is a documented simplification of the pinned spec.
- **Names are trimmed.** `s_volume_name`/`s_last_mounted` stop at the first
  NUL, drop everything after it and are trimmed of ASCII whitespace; bytes
  are not validated for printability and are decoded as UTF-8.
- **Combined 64-bit counts.** `ext_blocks_count` and friends fold
  `hi * 2^32 + lo` into an `Int`; a value with `hi >= 2^31` is not
  representable.
- **UUID as text.** The uuid is exposed as a lowercase hex string, not as
  raw bytes.
- The parsed `ExtSuperblock` is a plain value snapshot; it holds no
  references into the parse buffer and is never written back implicitly.
- Not thread-safe; the type is a plain value.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
