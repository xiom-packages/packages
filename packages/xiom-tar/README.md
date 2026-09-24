# xiom.tar

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** POSIX ustar archive codec: parse and build uncompressed tar files.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.tar` reads and writes uncompressed POSIX ustar archives. `tar_parse`
walks the 512-byte header blocks, validates the ustar magic and the unsigned
checksum, parses the octal fields, joins the `prefix` and `name` fields with
`/` and returns a `TarArchive` index whose `data_offsets`/`sizes` locate every
payload inside the source buffer. `tar_build` emits canonical ustar headers
(typeflag `'0'`, mode `0644`, uid/gid 0, mtime 0), pads each payload to a
512-byte boundary and terminates the archive with two 512-byte zero blocks.

All validation is structural and purely in-memory: the API never touches the
filesystem and never decompresses anything. See SPEC.md for the byte layout,
validation order, error catalog and test plan.

## API

All functions are free functions in module `xiom.tar`.

| Function | Returns | Description |
|---|---|---|
| `tar_parse(data)` | `Result[TarArchive, Str]` | Parse and validate an uncompressed ustar archive; indexes every entry. |
| `tar_entry_count(a)` | `Int` | Number of parsed entries. |
| `tar_entry_name(a, i)` | `Str` | Entry name (prefix joined with `/` when present); `""` out of range. |
| `tar_entry_size(a, i)` | `Int` | Declared payload size in bytes; `0` out of range. |
| `tar_entry_data(data, a, i)` | `Result[Vec[UInt8], Str]` | Copy of entry `i`'s payload bytes out of `data`. |
| `tar_build(names, payloads)` | `Result[Vec[UInt8], Str]` | Build a ustar archive (each entry a regular file, mode `0644`, mtime 0). |

`TarArchive = { names: Vec[Str]; types: Vec[Int]; sizes: Vec[Int]; modes:
Vec[Int]; mtimes: Vec[Int]; data_offsets: Vec[Int]; }` -- one element per
entry, in file order. `types` maps the raw typeflag byte to `0` for a regular
file (`'0'` or NUL), `5` for a directory (`'5'`) and to the raw byte value
otherwise (`'2'` symlink -> 50, ...).

## ustar header layout (512 bytes)

All numeric fields are ASCII octal digits (leading NULs/spaces are skipped;
a NUL or space terminates a field). Offsets are decimal.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 100 | name | NUL-terminated (may fill the field); joined with `prefix`. |
| 100 | 8 | mode | Octal; `tar_build` writes `0000644\0`. |
| 108 | 8 | uid | Octal; `tar_build` writes `0000000\0`. |
| 116 | 8 | gid | Octal; `tar_build` writes `0000000\0`. |
| 124 | 12 | size | Octal; 11 digits + NUL in `tar_build` output. |
| 136 | 12 | mtime | Octal; `tar_build` writes 0. |
| 148 | 8 | chksum | 6 octal digits + NUL + space in `tar_build` output. |
| 156 | 1 | typeflag | `'0'`/NUL regular, `'5'` directory, raw otherwise. |
| 157 | 100 | linkname | Not interpreted. |
| 257 | 6 | magic | `"ustar\0"` (POSIX) or `"ustar "` (GNU); required. |
| 263 | 2 | version | Not validated (`"00"` in output). |
| 265 | 32 | uname | Not interpreted. |
| 297 | 32 | gname | Not interpreted. |
| 329 | 8 | devmajor | Not interpreted (`0000000\0` in output). |
| 337 | 8 | devminor | Not interpreted (`0000000\0` in output). |
| 345 | 155 | prefix | Joined with `name` through `/` when non-empty. |
| 500 | 12 | pad | Ignored. |

Checksum rule: the unsigned sum of all 512 header bytes with the checksum
field read as eight spaces (0x20); `tar_parse` compares it with the stored
octal value and rejects a mismatch.

## Errors

`tar_parse`: `Err("tar: truncated header")` (partial non-zero header block),
`Err("tar: bad magic")`, `Err("tar: bad octal")` (checksum/mode/size/mtime
field), `Err("tar: bad checksum")`, `Err("tar: truncated data")` (declared
size beyond the buffer).

`tar_build`: `Err("tar: name too long")` (name above 100 bytes),
`Err("tar: payload count mismatch")`.

`tar_entry_data`: `Err("tar: entry out of range")`,
`Err("tar: truncated data")`. See SPEC.md for the full catalog.

## Usage

```xi
use xiom.tar;
use xiom.io;
use xiom.convert;

var names = Vec[Str].new();
names.push("hello.txt");
var payloads = Vec[Vec[UInt8]].new();
var body = Vec[UInt8].new();
body.push(104 as UInt8);
body.push(105 as UInt8);
payloads.push(body);

let built = tar_build(&names, &payloads);
match tar_parse(&built) {
  Ok(ar) => {
    io.println("entries: " + convert.int_to_string(tar_entry_count(&ar)));
    io.println("name:    " + tar_entry_name(&ar, 0));
    io.println("size:    " + convert.int_to_string(tar_entry_size(&ar, 0)));
  },
  Err(e) => { io.println("error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.tar
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **ustar only**: GNU long names (`././@LongLink`), GNU sparse entries and PAX
  extended headers (`PaxHeaders.*`) are neither parsed nor emitted. `tar_build`
  rejects names longer than the 100-byte name field instead of splitting a
  prefix or emitting a GNU longname entry. Exactly 100-byte names are stored
  without a NUL terminator.
- **No compression**: this is the uncompressed tar container only. gzip,
  bzip2, xz and zstd streams are not detected or decoded.
- **No link semantics**: linkname, uname, gname, devmajor/devminor and the
  version bytes are ignored; `types` exposes only the raw typeflag mapping.
- **No path safety**: parsed names are returned verbatim (absolute paths and
  `..` segments are not sanitized); a caller that extracts entries to disk
  must apply its own traversal checks.
- **mtime is not preserved by `tar_build`** (always 0) and the build path
  never emits a prefix field; the parse path does join prefixes.
- Sizes are 11 octal digits at most (8^11 - 1 bytes, ~8 GiB); the whole
  archive and every payload copy live in memory.
- Not thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
