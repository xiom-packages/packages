# xiom.cpio

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM codec for cpio archive headers: parse and build the
> ASCII `newc` (`070701`) and `odc` (`070707`) entry formats.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.cpio` reads and writes the header layer of cpio archives, the byte
exact container of `cpio -H newc` / `cpio -H odc`:

- `cpio_parse` walks a byte stream of concatenated entries. Each entry's
  magic selects its format; the fixed header fields are parsed as
  eight-digit hexadecimal (`newc`) or octal (`odc`), the NUL-terminated name
  is validated against `namesize`, header+name and data padding is checked,
  and the walk stops at the first entry named exactly `TRAILER!!!`. The
  result is a flat index: names, format codes, one stride-11 metadata
  vector, declared file sizes and the absolute data/next-header offsets.
- `cpio_append` serializes one entry (header, name, alignment padding, data,
  alignment padding) into a caller-owned buffer with all validation done
  before the first byte is written.
- `cpio_build` builds a whole stream from parallel name/data vectors plus a
  flat metadata buffer and appends the canonical trailer.
- `cpio_entry_data` copies one entry's declared data bytes out of the parse
  buffer.

Everything is in-memory and structural: no filesystem I/O, no compression,
no extraction, no device semantics. Values are parsed and re-emitted
verbatim. See SPEC.md for the layout tables, validation order, error catalog
and test plan.

## API

All functions are free functions in module `xiom.cpio`.

| Function | Returns | Description |
|---|---|---|
| `cpio_parse(data)` | `Result[CpioArchive, Str]` | Parse and validate a stream; index every entry up to the trailer. |
| `cpio_detect_format(data)` | `Int` | `CPIO_FORMAT_NEWC`, `CPIO_FORMAT_ODC` or `-1` for the first entry. |
| `cpio_count(a)` | `Int` | Number of parsed entries (the trailer is not counted). |
| `cpio_entry_name(a, i)` | `Str` | Name of entry `i`; `""` out of range. Compare with `str_compare`. |
| `cpio_entry_format(a, i)` | `Int` | `0` = newc, `1` = odc; `-1` out of range. |
| `cpio_entry_field(a, i, k)` | `Int` | Raw metadata field `k` (`CPIO_META_*`); `-1` out of range. |
| `cpio_entry_ino/mode/uid/gid/nlink/mtime/devmajor/devminor/rdevmajor/rdevminor/check(a, i)` | `Int` | Named field accessors; `-1` out of range. |
| `cpio_entry_filesize(a, i)` | `Int` | Declared data size in bytes; `-1` out of range. |
| `cpio_entry_data_offset(a, i)` | `Int` | Absolute offset of entry `i`'s first data byte; `-1` out of range. |
| `cpio_entry_next_offset(a, i)` | `Int` | Absolute offset just past entry `i`'s data padding; `-1` out of range. |
| `cpio_entry_data(data, a, i)` | `Result[Vec[UInt8], Str]` | Copy of entry `i`'s declared data bytes out of `data`. |
| `cpio_append(out, format, name, meta, data)` | `Result[Unit, Str]` | Append one entry; `out` untouched on `Err`. |
| `cpio_append_trailer(out, format)` | `Result[Unit, Str]` | Append the canonical `TRAILER!!!` entry. |
| `cpio_build(format, names, datas, metas)` | `Result[Vec[UInt8], Str]` | Build a whole stream and append the trailer. |

`CpioArchive = { names: Vec[Str]; formats: Vec[Int]; fields: Vec[Int];
filesizes: Vec[Int]; data_offsets: Vec[Int]; next_offsets: Vec[Int]; }` --
one slot per entry, in stream order. `fields` is flat with stride 11:
entry `i` owns `fields[i*11 .. i*11+10]` in the order ino, mode, uid, gid,
nlink, mtime, devmajor, devminor, rdevmajor, rdevminor, check
(`CPIO_META_INO` .. `CPIO_META_CHECK`). `metas` for
`cpio_append`/`cpio_build` uses exactly the same 11-value order.

## Header layouts

`newc` -- magic `"070701"`, then 13 eight-digit hexadecimal fields, then the
name and NUL. The fixed header is 110 bytes.

| Offset | Size | Field |
|---|---|---|
| 0 | 6 | magic `"070701"` |
| 6 | 8 | ino (hex) |
| 14 | 8 | mode (hex) |
| 22 | 8 | uid (hex) |
| 30 | 8 | gid (hex) |
| 38 | 8 | nlink (hex) |
| 46 | 8 | mtime (hex) |
| 54 | 8 | filesize (hex) |
| 62 | 8 | devmajor (hex) |
| 70 | 8 | devminor (hex) |
| 78 | 8 | rdevmajor (hex) |
| 86 | 8 | rdevminor (hex) |
| 94 | 8 | namesize, includes the NUL (hex) |
| 102 | 8 | check (hex, stored verbatim) |
| 110 | `namesize` | name + NUL, then NUL padding to a 4-byte boundary |

`odc` -- magic `"070707"`, then ten octal fields, then the name and NUL. The
fixed header is 76 bytes.

| Offset | Size | Field |
|---|---|---|
| 0 | 6 | magic `"070707"` |
| 6 | 6 | dev (octal, combined device number) |
| 12 | 6 | ino (octal) |
| 18 | 6 | mode (octal) |
| 24 | 6 | uid (octal) |
| 30 | 6 | gid (octal) |
| 36 | 6 | nlink (octal) |
| 42 | 6 | rdev (octal, combined rdev number) |
| 48 | 11 | mtime (octal) |
| 59 | 6 | namesize, includes the NUL (octal) |
| 65 | 11 | filesize (octal) |
| 76 | `namesize` | name + NUL, then NUL padding to a 2-byte boundary |

Alignment: for `newc` the total `110 + namesize` is padded with NUL bytes to
a multiple of 4 and the data is padded to a multiple of 4; for `odc` the
boundary is 2. `cpio_parse` requires every padding byte to be present and
zero and reports `cpio: alignment mismatch` otherwise.

## Errors

`cpio_parse`: `cpio: bad magic`, `cpio: truncated header`,
`cpio: non-hex digit` (newc), `cpio: bad octal` (odc), `cpio: bad namesize`,
`cpio: truncated name`, `cpio: name missing NUL`,
`cpio: alignment mismatch`, `cpio: truncated data`, `cpio: missing trailer`.

`cpio_append` / `cpio_build`: `cpio: bad format`,
`cpio: metadata length mismatch`, `cpio: entry count mismatch`,
`cpio: size overflow`; `cpio_build` surfaces the first per-entry error
unchanged.

`cpio_entry_data`: `cpio: entry out of range`, `cpio: truncated data`.

See SPEC.md for the exact condition behind every message.

## Usage

```xi
use xiom.cpio;
use xiom.io;
use xiom.convert;

// Build a one-entry newc archive (mode 0100644, nlink 1, everything else 0).
var names = Vec[Str].new();
names.push("hello.txt");
var datas = Vec[Vec[UInt8]].new();
var body = Vec[UInt8].new();
body.push(104 as UInt8);   // 'h'
body.push(105 as UInt8);   // 'i'
datas.push(body);
var metas = Vec[Int].new();  // ino, mode, uid, gid, nlink, mtime,
metas.push(1);               // devmajor, devminor, rdevmajor, rdevminor, check
metas.push(33188);
metas.push(0); metas.push(0); metas.push(1); metas.push(0);
metas.push(0); metas.push(0); metas.push(0); metas.push(0); metas.push(0);

let built = cpio_build(CPIO_FORMAT_NEWC, &names, &datas, &metas);
match built {
  Ok(bytes) => {
    match cpio_parse(&bytes) {
      Ok(a) => {
        io.println("entries: " + convert.int_to_string(cpio_count(&a)));      // 1
        io.println("name:    " + cpio_entry_name(&a, 0));                     // hello.txt
        io.println("size:    " + convert.int_to_string(cpio_entry_filesize(&a, 0))); // 2
      },
      Err(e) => { io.println("parse error: " + e); },
    }
  },
  Err(e) => { io.println("build error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.cpio
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Header codec only.** No filesystem I/O, no archive extraction or
  creation on disk, no file content transformation. Data bytes are copied
  verbatim.
- **newc and odc only.** The old binary format, the `crc` (`070702`) format,
  and every other cpio variant are not recognized; `cpio: bad magic` is
  reported instead.
- **No compression.** gzip/bzip2/xz/zstd wrappers are not detected.
- **No device semantics.** `odc` carries combined `dev`/`rdev` numbers; they
  are exposed through `cpio_entry_devmajor`/`cpio_entry_rdevmajor` and the
  minor accessors return `-1`. No major/minor packing is performed.
- **Metadata is opaque.** mode bits, uid/gid, mtime and link counts are
  stored and returned as parsed; file types, hardlinks, symlinks and device
  nodes are not modeled.
- **Names are NUL-terminated strings.** The bytes before the NUL are
  returned as a `Str`; NUL cannot occur inside a name, and the bytes are not
  validated as UTF-8.
- **Strict padding.** Header+name and data padding must be NUL bytes; some
  writers leave stale data there and would be rejected.
- **The trailer ends the archive.** Parsing stops at the first entry named
  exactly `TRAILER!!!`; the trailer's own metadata is ignored, its padding
  is not required to be present, and every following byte is ignored (GNU
  cpio pads archives to 512-byte blocks). A stream without a trailer is
  `cpio: missing trailer`.
- **Width-limited fields.** `newc` fields are 32-bit (8 hex digits) and
  `odc` fields are 18-bit (`ino`/`mode`/... 6 octal digits) or 33-bit
  (`mtime`/`filesize` 11 octal digits); larger values are rejected on build
  with `cpio: size overflow`.
- The whole archive and every copied payload live in memory. Not
  thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
