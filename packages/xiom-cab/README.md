# xiom.cab

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** Microsoft Cabinet (CAB) header and directory codec: parse and
> build the `CFHEADER`/`CFFOLDER`/`CFFILE` structures of a cabinet file.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.cab` reads and writes the index structures of Microsoft cabinet files
(`[MS-CAB]`, signature `MSCF`):

- `cab_parse` validates the header (signature, the three reserved zero
  words, `cbCabinet`, the version, folder/file counts, flags, the optional
  `setID`/`iCabinet` pair, the optional reserve descriptor and header
  reserve span, the optional prev/next cabinet strings) and the directory
  (CFFOLDER entries with their per-folder reserve spans, CFFILE entries with
  their NUL-terminated names), then returns a flat `CabArchive` index built
  from parallel vectors.
- The `cab_*` accessors read back cabinet size, version, flags, setID /
  iCabinet, folder `coffCabStart`/`cCFData`/`typeCompress`/reserve offsets,
  file name/size/offset/folder/date/time/attribs/UTF flag and all reserved
  spans.
- `cab_build` emits a canonical version-1.3 header plus directory for
  uncompressed files: one folder with `typeCompress` 0 (none) and
  `cCFData` 0, then one CFFILE per name with running `uoffFolderStart`
  offsets.
- `cab_compression_known` and `cab_compression_code` classify the raw
  compression word, and `cab_dos_date_*` / `cab_dos_time_*` decode the
  packed MS-DOS date/time.

Everything is structural and in-memory: **CFDATA records are not parsed, no
MSZIP/Quantum/LZX decompression is performed and no file is extracted.**
Unknown compression codes parse on purpose (raw pass-through). See SPEC.md
for the byte layout tables, validation order, error catalog and test plan.

## API

All functions are free functions in module `xiom.cab`.

| Function | Returns | Description |
|---|---|---|
| `cab_parse(data)` | `Result[CabArchive, Str]` | Parse and validate a cabinet; index every folder and file. |
| `cab_cabinet_size(a)` | `Int` | `cbCabinet` from the header. |
| `cab_version_major(a)` / `cab_version_minor(a)` | `Int` | CFHEADER version bytes. |
| `cab_flags(a)` | `Int` | Raw flags word (`CAB_FLAG_*`). |
| `cab_set_id(a)` / `cab_i_cabinet(a)` | `Int` | Optional fields, `-1` for cabinets below version 1.3. |
| `cab_folder_count(a)` / `cab_file_count(a)` | `Int` | Directory entry counts. |
| `cab_reserved_header_len(a)` | `Int` | `cbCFHeader`. |
| `cab_reserved_folder_len(a)` | `Int` | `cbCFFolder`. |
| `cab_reserved_data_len(a)` | `Int` | `cbCFData` (per-CFDATA reserve; CFDATA itself is not parsed). |
| `cab_reserved_header_offset(a)` | `Int` | Absolute offset of the header reserve span. |
| `cab_folder_start(a, i)` | `Int` | Folder `coffCabStart`; `-1` out of range. |
| `cab_folder_data_count(a, i)` | `Int` | Folder `cCFData`; `-1` out of range. |
| `cab_folder_compression(a, i)` | `Int` | Raw `typeCompress` word; `-1` out of range. |
| `cab_folder_reserve_offset(a, i)` | `Int` | Start of folder `i`'s reserve bytes (entry + 8); `-1` out of range. |
| `cab_file_name(a, i)` | `Str` | Name without the NUL; `""` out of range. Compare with `str_compare`. |
| `cab_file_size(a, i)` | `Int` | `cbFile`; `-1` out of range. |
| `cab_file_offset(a, i)` | `Int` | `uoffFolderStart`; `-1` out of range. |
| `cab_file_folder(a, i)` | `Int` | `iFolder`; `-1` out of range. |
| `cab_file_date(a, i)` / `cab_file_time(a, i)` | `Int` | Raw packed DOS values; `-1` out of range. |
| `cab_file_attribs(a, i)` | `Int` | Raw `attribs` word; `-1` out of range. |
| `cab_file_utf(a, i)` | `Bool` | True when the 0x80 UTF-name bit is set; `false` out of range. |
| `cab_compression_code(t)` | `Int` | Low nibble of `typeCompress` (`CAB_COMPRESSION_*`); `-1` for negative input. |
| `cab_compression_known(t)` | `Bool` | True for codes 0..3. |
| `cab_version_has_setid(major, minor)` | `Bool` | The documented "1.3 or greater" rule. |
| `cab_dos_date_year/month/day(d)` | `Int` | Packed date fields. |
| `cab_dos_time_hour/minute/second(t)` | `Int` | Packed time fields (second in two-second units). |
| `cab_build(names, sizes)` | `Result[Vec[UInt8], Str]` | Canonical directory-only cabinet (one uncompressed folder). |

`CabArchive` stores the header scalars plus flat parallel columns: `names`,
`file_sizes`, `file_offsets`, `file_folders`, `file_dates`, `file_times`,
`file_attribs`, `folder_starts`, `folder_data_counts`, `folder_compress`,
`folder_offsets` -- one element per entry, in directory order (no per-entry
structs).

## Cabinet layout

All integers are little-endian. Offsets are decimal.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | signature `"MSCF"` |
| 4 | 4 | reserved1 (must be 0) |
| 8 | 4 | cbCabinet (total size) |
| 12 | 4 | reserved2 (must be 0) |
| 16 | 4 | coffFiles (first CFFILE offset) |
| 20 | 4 | reserved3 (must be 0) |
| 24 | 1 | versionMinor |
| 25 | 1 | versionMajor |
| 26 | 2 | cFolders |
| 28 | 2 | cFiles |
| 30 | 2 | flags (`CAB_FLAG_*`) |
| 32 | 2 | setID (only version 1.3+) |
| 34 | 2 | iCabinet (only version 1.3+) |
| 36 | 2 | cbCFHeader (only with the reserve flag) |
| 38 | 1 | cbCFFolder (only with the reserve flag) |
| 39 | 1 | cbCFData (only with the reserve flag) |
| 40 | cbCFHeader | header reserve bytes (raw span) |
| ... | n | prev/next cabinet + disk names, NUL-terminated (skipped) |

A CFFOLDER entry is 8 bytes -- `coffCabStart` u32, `cCFData` u16,
`typeCompress` u16 -- followed by `cbCFFolder` reserve bytes. A CFFILE entry
is 16 fixed bytes -- `cbFile` u32, `uoffFolderStart` u32, `iFolder` u16,
`date` u16, `time` u16, `attribs` u16 -- followed by the NUL-terminated
`szName`. The folder array starts right after the header; the file array
starts at `coffFiles`; folder data would follow at `coffCabStart`.

`typeCompress` uses the low nibble as the algorithm: 0 none, 1 MSZIP,
2 Quantum, 3 LZX; the high bits carry algorithm parameters (for example LZX
window bits). The raw word is kept and unknown codes are accepted.

`attribs` bits: 0x01 read-only, 0x02 hidden, 0x04 system, 0x08 volume,
0x10 directory, 0x20 archive, 0x40 device, 0x80 UTF-8 name (honored for
version 1.3+ cabinets). The packed date/time decode to
`year = 1980 + d / 512`, `month = (d / 32) % 16`, `day = d % 32`,
`hour = t / 2048`, `minute = (t / 32) % 64`, `second = (t % 32) * 2`.

## Errors

`cab_parse`: `cab: bad signature`, `cab: truncated header`,
`cab: reserved field set`, `cab: truncated cabinet`, `cab: bad cabinet size`,
`cab: truncated string`, `cab: folder directory overflow`,
`cab: file directory overflow`, `cab: coffFiles out of range`,
`cab: truncated file directory`, `cab: truncated name`, `cab: bad name`,
`cab: bad folder index`, `cab: folder data out of range`,
`cab: file span out of range`.

`cab_build`: `cab: entry count mismatch`, `cab: too many files`,
`cab: size overflow`, `cab: bad name`, `cab: name too long`.

See SPEC.md for the exact condition behind every message.

## Usage

```xi
use xiom.cab;
use xiom.io;
use xiom.convert;

var names = Vec[Str].new();
names.push("hello.txt");
var sizes = Vec[Int].new();
sizes.push(5);

let built = cab_build(&names, &sizes);
match built {
  Ok(bytes) => {
    io.println("cabinet bytes: " + convert.int_to_string(bytes.len()));  // 70
    match cab_parse(&bytes) {
      Ok(a) => {
        io.println("files:   " + convert.int_to_string(cab_file_count(&a)));
        io.println("name:    " + cab_file_name(&a, 0));                        // hello.txt
        io.println("size:    " + convert.int_to_string(cab_file_size(&a, 0))); // 5
        io.println("version: " + convert.int_to_string(cab_version_major(&a)) + "." + convert.int_to_string(cab_version_minor(&a))); // 1.3
      },
      Err(e) => { io.println("parse error: " + e); },
    }
  },
  Err(e) => { io.println("build error: " + e); },
}
```

`cab_build` emits a **dataless** directory: no CFDATA blocks, no reserve
areas, no prev/next links. The output is structurally valid and parses, but
is not extractable. Use the accessors after `cab_parse` to read a real
cabinet's index.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.cab
```

Expected: the section-4 namespace check passes, 17 `[PASS]` lines, and a
final `port: PASS (passed=17 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No CFDATA parsing or decompression.** MSZIP, Quantum and LZX payloads
  are never read; `cCFData` extents are only lower-bounded by their
  `8 + cbCFData` byte headers. Unknown compression codes pass through the
  index unchanged.
- **No extraction and no filesystem I/O.** Only the header and directory are
  interpreted.
- **No multi-cabinet traversal.** Prev/next names are validated and skipped,
  not stored; `setID`/`iCabinet` are exposed for the caller.
- **`cab_build` is directory-only.** One folder, `typeCompress` none,
  `cCFData` 0, no reserve, no prev/next; `coffCabStart` points just past the
  directory. The result is not extractable.
- **Name policy.** Parsed names must be non-empty, NUL-terminated inside
  `cbCabinet` and printable: ASCII 0x20..0x7E always, bytes 0x80..0xFF only
  for version 1.3+ entries with the 0x80 attribute bit. No UTF-8 sequence
  validation and no path sanitization; callers extracting names to disk must
  apply their own traversal checks.
- **Builder name cap.** `cab_build` rejects names above 255 bytes and any
  byte outside 0x20..0x7E (`cab: name too long` / `cab: bad name`).
- The whole buffer and every parsed name live in memory; plain value types,
  no thread safety.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
