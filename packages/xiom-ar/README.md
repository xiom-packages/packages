# xiom.ar

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Unix ar archive codec: parse and build the common
> `ar(5)` member container.
> **Deps:** `xiom.std` only (`xiom.string`; tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex`). No FFI.

## What it is

`xiom.ar` reads and writes Unix ar archives, the container used by
`ar`, `llvm-ar` and the `.a` static-library format:

- `ar_parse` validates the 8-byte global magic (`!<arch>\n`), walks the
  60-byte member headers (`name[16]`, `mtime[12]`, `uid[6]`, `gid[6]`,
  `mode[8]`, `size[10]`, terminator `0x60 0x0A`), decodes plain
  trailing-space-padded names and BSD `#1/<len>` extended names, and returns
  a flat `ArArchive` index: names, header offsets, data offsets, payload
  sizes, mtimes, uids, gids and modes. Payload bytes stay in the source
  buffer and are located by the recorded offsets.
- `ar_append` serializes one member (header, optional BSD name bytes, data,
  one `0x0A` pad byte when the member size is odd) into a caller-owned
  buffer with all validation done before the first byte is written.
- `ar_build` builds a whole archive from parallel name/data vectors plus a
  flat metadata buffer, starting with the global magic.
- `ar_entry_data` copies one entry's payload bytes out of the parse buffer.

Everything is structural and in-memory: no filesystem I/O, no compression,
no extraction. Values are parsed and re-emitted as stored. See SPEC.md for
the byte layout tables, validation order, error catalog and test plan.

## API

All functions are free functions in module `xiom.ar`.

| Function | Returns | Description |
|---|---|---|
| `ar_global()` | `Vec[UInt8]` | The eight global magic bytes, `!<arch>\n`. |
| `ar_parse(data)` | `Result[ArArchive, Str]` | Parse and validate an archive; index every member. |
| `ar_count(a)` | `Int` | Number of parsed members. |
| `ar_entry_name(a, i)` | `Str` | Decoded member name; `""` out of range. Compare with `str_compare`. |
| `ar_entry_header_offset(a, i)` | `Int` | Absolute offset of the 60-byte header; `-1` out of range. |
| `ar_entry_size(a, i)` | `Int` | Payload size in bytes (BSD name bytes excluded); `-1` out of range. |
| `ar_entry_data_offset(a, i)` | `Int` | Absolute offset of the first payload byte; `-1` out of range. |
| `ar_entry_mtime(a, i)` | `Int` | Modification time as stored; `-1` out of range. |
| `ar_entry_uid(a, i)` | `Int` | User id as stored; `-1` out of range. |
| `ar_entry_gid(a, i)` | `Int` | Group id as stored; `-1` out of range. |
| `ar_entry_mode(a, i)` | `Int` | File mode decoded from the octal field; `-1` out of range. |
| `ar_entry_data(data, a, i)` | `Result[Vec[UInt8], Str]` | Copy of entry `i`'s payload bytes out of `data`. |
| `ar_append(out, name, meta, data)` | `Result[Unit, Str]` | Append one member (no global magic); `out` untouched on `Err`. |
| `ar_build(names, datas, metas)` | `Result[Vec[UInt8], Str]` | Build a whole archive from parallel vectors. |

`ArArchive = { names: Vec[Str]; header_offsets: Vec[Int]; data_offsets:
Vec[Int]; sizes: Vec[Int]; mtimes: Vec[Int]; uids: Vec[Int]; gids: Vec[Int];
modes: Vec[Int]; }` -- one element per member, in stream order (flat
parallel storage, no per-entry structs).

`meta` for `ar_append` and `metas` for `ar_build` are flat vectors with
stride `AR_META_LEN` (4), in field order: mtime, uid, gid, mode
(`AR_META_MTIME` .. `AR_META_MODE`). `datas[i]` is the payload of
`names[i]`; its length becomes the member size.

## Member layout and naming

All numeric fields are ASCII digits, left aligned and space padded to their
width. `mtime`, `uid`, `gid` and `size` are **decimal**; `mode` is
**octal** (the `ar(5)` convention, e.g. `100644` for a regular file mode
`0644`). Each member header is exactly 60 bytes and ends with the two
terminator bytes `0x60 0x0A` (`'\x60' '\n'`).

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | name (plain, or `#1/<len>` BSD extended) |
| 16 | 12 | mtime (decimal) |
| 28 | 6 | uid (decimal) |
| 34 | 6 | gid (decimal) |
| 40 | 8 | mode (octal) |
| 48 | 10 | size (decimal, includes the BSD name bytes) |
| 58 | 2 | terminator `0x60 0x0A` |

Plain names are written space padded. A name is written in the plain form
only when it is 1..16 bytes, contains no space and starts/ends with a
character other than `/`; every other name uses BSD `#1/<len>`, where
`<len>` is the decimal byte length of the name including nothing else, and
the name bytes occupy the start of the member data. On parse, a plain name
loses its trailing spaces and one trailing `/` (the GNU/SysV
regular-member marker); a name whose plain field starts with `/` is the GNU
special-member namespace and is rejected.

Payloads start at `header + 60` (just past the BSD name bytes when used)
and occupy `size` bytes (minus the BSD name bytes). When the member size is
odd, exactly one `0x0A` byte follows the data, keeping the stream even.
There is no end-of-archive marker; the archive ends after the last
member's padding.

## Errors

`ar_parse`: `ar: bad global magic`, `ar: truncated header`,
`ar: bad terminator`, `ar: bad name`, `ar: unsupported special member`,
`ar: name too long`, `ar: bad decimal field`, `ar: bad octal field`,
`ar: truncated data`, `ar: size/data mismatch`, `ar: missing padding`,
`ar: bad padding`.

`ar_append` / `ar_build`: `ar: metadata length mismatch`,
`ar: entry count mismatch`, `ar: bad name`, `ar: name too long`,
`ar: field overflow`.

`ar_entry_data`: `ar: entry out of range`, `ar: truncated data`.

See SPEC.md for the exact condition behind every message.

## Usage

```xi
use xiom.ar;
use xiom.io;
use xiom.convert;

// Build a one-member archive: mtime 1700000000, uid/gid 1000,
// mode 0100644 (octal 100644).
var names = Vec[Str].new();
names.push("hello.txt");
var datas = Vec[Vec[UInt8]].new();
var body = Vec[UInt8].new();
body.push(104 as UInt8);   // 'h'
body.push(105 as UInt8);   // 'i'
datas.push(body);
var metas = Vec[Int].new();  // mtime, uid, gid, mode
metas.push(1700000000);
metas.push(1000);
metas.push(1000);
metas.push(33188);

let built = ar_build(&names, &datas, &metas);
match built {
  Ok(bytes) => {
    match ar_parse(&bytes) {
      Ok(a) => {
        io.println("members: " + convert.int_to_string(ar_count(&a)));            // 1
        io.println("name:    " + ar_entry_name(&a, 0));                           // hello.txt
        io.println("size:    " + convert.int_to_string(ar_entry_size(&a, 0)));    // 2
        io.println("mode:    " + convert.int_to_string(ar_entry_mode(&a, 0)));    // 33188
      },
      Err(e) => { io.println("parse error: " + e); },
    }
  },
  Err(e) => { io.println("build error: " + e); },
}
```

For streaming builds, start with `ar_global()` and call `ar_append` once per
member; the concatenation is a valid archive.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ar
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No GNU special members.** The symbol table `/`, the long-name table
  `//` and `/SYM64/` are rejected with `ar: unsupported special member`.
  Archives produced by GNU `ar`/`llvm-ar` with a symbol table therefore do
  not parse; strip the symbol table first or extract the member stream.
- **No long-name table, no thin archives, no BSD ranlib tables.** Only the
  plain name field and BSD `#1/<len>` names are understood.
- **Names are capped at 255 bytes** (`AR_MAX_NAME`); longer names are
  `ar: name too long` on both parse and build. Names round-trip as `Str`
  bytes (NUL-terminated semantics of the plain field); the bytes are not
  validated as UTF-8 and no path sanitization is applied.
- **`ar_build`/`ar_append` write no trailing `/`** on plain names. GNU and
  BSD ar accept both forms; the parser strips one trailing `/` on input.
- **`mode` is octal on the wire.** The builder rejects modes above
  `0o77777777` (16777215) and negative values with `ar: field overflow`;
  the other fields are similarly width-limited (mtime 12, uid/gid 6, size
  10 decimal digits).
- **No end-of-archive marker.** Parsing consumes members until the buffer
  is exhausted; trailing bytes that do not start a valid 60-byte header are
  `ar: truncated header`.
- **Padding is strict.** An odd-sized member must be followed by a `0x0A`
  byte; a missing pad is `ar: missing padding`, any other byte is
  `ar: bad padding`.
- The whole archive and every copied payload live in memory. Not
  thread-safe; all values are plain value types.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
