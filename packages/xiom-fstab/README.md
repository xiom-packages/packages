# xiom.fstab

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** `/etc/fstab` parsing into a flat document, field/option access,
> duplicate-mountpoint lookup and canonical emission for the documented
> six-field subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Overview

`xiom.fstab` is a pure-XIOM codec for the classic `/etc/fstab` format: lines of
`device mountpoint fstype options dump pass` with `#` comments and flexible
whitespace. It parses a whole document into a flat `Fstab`, decodes the four
documented octal escapes (`\040` space, `\011` tab, `\012` newline, `\134`
backslash) in the device, mountpoint and fstype fields, validates dump/pass as
`0`/`1`/`2`, and emits the canonical text back with single tabs.

The model is deliberately flat: nine parallel per-entry vectors plus a shared
option-name pool, because `Vec[StructType]` is not usable on the pinned
compiler. Duplicate mountpoints are preserved in document order; the
mountpoint accessors use a documented first-match policy. `rw`/`ro` are stored
but never enforced. See `SPEC.md` for the exact grammar, escape table and error
catalog.

## Install / use

```
xiom pkg install xiom.fstab@0.1.0
```

```xi
use xiom.fstab;
use xiom.io;

fn main() -> Int {
  let r = fstab_parse("/dev/disk\\040one  /mnt/data  ext4  rw,noatime  0  2\n");
  match r {
    Ok(d) => {
      io.println(fstab_entry_count(&d));            // 1
      match fstab_mountpoint(&d, 0) {
        Some(m) => { io.println(m); },              // /mnt/data
        None => {},
      }
      if fstab_has_option(&d, 0, "noatime") { io.println("noatime set"); }
      io.println(fstab_emit(&d));
      // /dev/disk\040one<TAB>/mnt/data<TAB>ext4<TAB>rw,noatime<TAB>0<TAB>2
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Quick start

- `fstab_parse(text)` validates the whole file; the first error is returned as
  a stable `Err("fstab: ...")` message. Empty and comment-only files are valid
  zero-entry documents.
- `fstab_device(d, i)` / `fstab_mountpoint(d, i)` / `fstab_fstype(d, i)` read
  one decoded field; `fstab_line(d, i)` reads its 1-based source line.
- `fstab_option_count(d, i)` / `fstab_option(d, i, j)` / `fstab_options(d, i)`
  read the option list in written order; `fstab_options_string(d, i)` returns
  the raw field; `fstab_has_option(d, i, name)` is a byte-exact presence check.
- `fstab_dump(d, i)` / `fstab_pass(d, i)` return `Some(0)`, `Some(1)` or
  `Some(2)`.
- `fstab_mountpoint_index(d, mnt)` returns the first entry with that decoded
  mountpoint (or `-1`); `fstab_entries_for_mountpoint(d, mnt)` returns every
  index in document order.
- `fstab_emit(d)` writes the canonical text: single tabs between the six
  fields, one line per entry, trailing LF, empty document -> `""`. Parsing the
  emitted text yields the same entries, and emitting again reproduces it byte
  for byte.

## API summary

| Function | Returns | Description |
|---|---|---|
| `fstab_parse(text)` | `Result[Fstab, Str]` | Parse a whole file; `Err("fstab: ...")` on the first malformed line. |
| `fstab_entry_count(d)` | `Int` | Number of entries. |
| `fstab_device(d, i)` | `Option[Str]` | Decoded device of entry `i`. |
| `fstab_mountpoint(d, i)` | `Option[Str]` | Decoded mountpoint of entry `i`. |
| `fstab_fstype(d, i)` | `Option[Str]` | Decoded fstype of entry `i`. |
| `fstab_options_string(d, i)` | `Option[Str]` | Raw options field of entry `i`, exactly as written. |
| `fstab_option_count(d, i)` | `Int` | Number of options of entry `i` (0 out of range). |
| `fstab_option(d, i, j)` | `Option[Str]` | Option `j` of entry `i`, in written order. |
| `fstab_options(d, i)` | `Vec[Str]` | Fresh, ordered option list of entry `i`. |
| `fstab_has_option(d, i, name)` | `Bool` | Byte-exact, case-sensitive presence check. |
| `fstab_dump(d, i)` | `Option[Int]` | Dump value (0, 1 or 2) of entry `i`. |
| `fstab_pass(d, i)` | `Option[Int]` | Pass value (0, 1 or 2) of entry `i`. |
| `fstab_line(d, i)` | `Int` | 1-based source line of entry `i` (0 out of range). |
| `fstab_mountpoint_index(d, mnt)` | `Int` | First entry with that decoded mountpoint, or `-1`. |
| `fstab_entries_for_mountpoint(d, mnt)` | `Vec[Int]` | All entry indexes with that decoded mountpoint, in order. |
| `fstab_emit(d)` | `Str` | Canonical fstab text (single tabs, trailing LF). |

## Error model

Only `fstab_parse` fails. Every message is stable ASCII and starts with
`fstab: `:

| Message | Trigger |
|---|---|
| `fstab: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, comments included |
| `fstab: too few fields in line <n>` | entry line with 1..5 tokens before the comment cut |
| `fstab: too many fields in line <n>` | entry line with 7 or more tokens |
| `fstab: bad escape in device: <token>` | backslash that is not one of the four documented escapes |
| `fstab: bad escape in mountpoint: <token>` | same, in the mountpoint field |
| `fstab: bad escape in fstype: <token>` | same, in the fstype field |
| `fstab: empty device: <token>` | decoded device is empty or only spaces/tabs/newlines |
| `fstab: empty mountpoint: <token>` | decoded mountpoint is empty or only spaces/tabs/newlines |
| `fstab: empty fstype: <token>` | decoded fstype is empty or only spaces/tabs/newlines |
| `fstab: empty option: <token>` | leading, trailing or doubled comma in the options list |
| `fstab: bad dump: <token>` | dump is not exactly `0`, `1` or `2` |
| `fstab: bad pass: <token>` | pass is not exactly `0`, `1` or `2` |

Within a line the checks run control byte, field count, device, mountpoint,
fstype, options, dump, pass; across the document the first failing line wins.
Accessors never fail: they return `None`, `0`, `-1` or an empty `Vec`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.fstab
```

Expected tail: 20 `[PASS]` lines, `xiom.fstab: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- No mount execution, no UUID/LABEL/PARTUUID resolution, no `/proc/mounts`, no
  `mount(8)` command lines, no systemd generator semantics, no file I/O.
- The emitter is canonical, not lossless: comments, blank lines, original
  whitespace, line endings and any other layout are not preserved (source line
  numbers are stored on the document but never emitted).
- Only the four documented escapes exist; a bare `\` or any other octal
  sequence is an error, and `#` always starts a comment, so neither can appear
  inside a field.
- Escapes are decoded in device, mountpoint and fstype only; the options, dump
  and pass fields are stored and emitted verbatim.
- Options are opaque text: no `defaults` expansion, no flag validation, no
  `rw`/`ro` enforcement or exclusivity, duplicates preserved.
- Duplicate mountpoints are preserved; the mountpoint accessors document
  first-match and all-match policies rather than merging entries.
- Byte-exact and case-sensitive throughout; bytes >= 0x80 pass through
  opaquely with no Unicode normalization.
- Device, mountpoint and fstype must not decode to empty or whitespace-only
  text (a bare `\040` is rejected as empty).
- No line-length cap; parsing is O(input length) and holds the document in
  memory.
- Errors carry a 1-based line number but no column information.

See `SPEC.md` for the full semantics, grammar, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
