# xiom.passwd

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** `/etc/passwd` parsing into a flat document, field/uid/name
> access and lookups, a documented system-user count and canonical emission
> for the seven-field subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Overview

`xiom.passwd` is a pure-XIOM codec for the classic `/etc/passwd` format: lines
of seven colon-separated fields `name:passwd:uid:gid:gecos:home:shell`, with
column-1 `#` comments, blank lines and LF/CRLF endings. There are no escapes
and no quoting, so a colon is always a separator and fields are never
trimmed. The parser validates the login name (`[a-z_][a-z0-9_-]*`, 32-byte
cap), the uid/gid range (0..4294967295), printable gecos text and absolute
(or empty) home/shell paths, preserves duplicate names and uids in document
order, and the emitter writes the canonical LF text back.

The model is deliberately flat: eight parallel per-entry vectors, because
`Vec[StructType]` is not usable on the pinned compiler. Name and uid lookups
use documented first-match policies; see `SPEC.md` for the exact grammar,
field rules and error catalog.

## Install / use

```
xiom pkg install xiom.passwd@0.1.0
```

```xi
use xiom.passwd;
use xiom.io;

fn main() -> Int {
  let r = passwd_parse("root:x:0:0:root:/root:/bin/bash\n");
  match r {
    Ok(d) => {
      io.println(passwd_entry_count(&d));            // 1
      match passwd_home_for_name(&d, "root") {
        Some(h) => { io.println(h); },               // /root
        None => {},
      }
      match passwd_uid_for_name(&d, "root") {
        Some(uid) => { io.println(uid); },           // 0
        None => {},
      }
      io.println(passwd_system_user_count(&d));      // 1 (uid < 1000)
      io.println(passwd_emit(&d));
      // root:x:0:0:root:/root:/bin/bash
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Quick start

- `passwd_parse(text)` validates the whole file; the first error is returned
  as a stable `Err("passwd: ...")` message. Empty and comment-only files are
  valid zero-entry documents.
- `passwd_name(d, i)` / `passwd_password(d, i)` / `passwd_uid(d, i)` /
  `passwd_gid(d, i)` / `passwd_gecos(d, i)` / `passwd_home(d, i)` /
  `passwd_shell(d, i)` read one field of entry `i`; `passwd_line(d, i)` reads
  its 1-based source line.
- `passwd_name_index(d, name)` returns the first entry with that exact name
  (or `-1`); `passwd_home_for_name`, `passwd_shell_for_name` and
  `passwd_uid_for_name` read fields of that first match.
- `passwd_uid_count(d, uid)`, `passwd_names_for_uid(d, uid)` and
  `passwd_name_for_uid(d, uid)` answer uid queries across duplicate uids.
- `passwd_system_user_count(d)` counts entries with the documented
  `uid < 1000` predicate.
- `passwd_emit(d)` writes the canonical text: single colons between the seven
  fields, one line per entry, trailing LF, empty document -> `""`. Parsing
  the emitted text yields the same entries, and emitting again reproduces it
  byte for byte.

## API summary

| Function | Returns | Description |
|---|---|---|
| `passwd_parse(text)` | `Result[Passwd, Str]` | Parse a whole file; `Err("passwd: ...")` on the first malformed line. |
| `passwd_entry_count(d)` | `Int` | Number of entries. |
| `passwd_name(d, i)` | `Option[Str]` | Login name of entry `i`. |
| `passwd_password(d, i)` | `Option[Str]` | Passwd field verbatim (may be empty, `x`, `*`, ...). |
| `passwd_uid(d, i)` | `Option[Int]` | Uid of entry `i` (0..4294967295). |
| `passwd_gid(d, i)` | `Option[Int]` | Gid of entry `i` (0..4294967295). |
| `passwd_gecos(d, i)` | `Option[Str]` | Gecos text verbatim (may be empty). |
| `passwd_home(d, i)` | `Option[Str]` | Home directory (empty or absolute). |
| `passwd_shell(d, i)` | `Option[Str]` | Login shell (empty or absolute). |
| `passwd_line(d, i)` | `Int` | 1-based source line of entry `i` (0 out of range). |
| `passwd_name_index(d, name)` | `Int` | First entry with that exact name, or `-1`. |
| `passwd_home_for_name(d, name)` | `Option[Str]` | Home of the first name match. |
| `passwd_shell_for_name(d, name)` | `Option[Str]` | Shell of the first name match. |
| `passwd_uid_for_name(d, name)` | `Option[Int]` | Uid of the first name match. |
| `passwd_uid_count(d, uid)` | `Int` | Number of entries with that uid. |
| `passwd_names_for_uid(d, uid)` | `Vec[Str]` | Fresh list of names with that uid, document order. |
| `passwd_name_for_uid(d, uid)` | `Option[Str]` | First name with that uid. |
| `passwd_system_user_count(d)` | `Int` | Entries with uid < 1000 (documented predicate). |
| `passwd_emit(d)` | `Str` | Canonical passwd text (single colons, trailing LF). |

## Error model

Only `passwd_parse` fails. Every message is stable ASCII and starts with
`passwd: `:

| Message | Trigger |
|---|---|
| `passwd: control byte in line <n>` | byte 0x00..0x1F (TAB included) or DEL anywhere on line `<n>`, fields and comments alike |
| `passwd: wrong field count in line <n>` | non-blank, non-comment line without exactly seven colon-separated fields |
| `passwd: bad name: <field>` | empty, over 32 bytes, or outside `[a-z_][a-z0-9_-]*` |
| `passwd: bad uid: <field>` | uid is not 1..10 decimal digits or exceeds 4294967295 |
| `passwd: bad gid: <field>` | same, for the gid field |
| `passwd: bad home: <field>` | non-empty home that does not start with `/` |
| `passwd: bad shell: <field>` | non-empty shell that does not start with `/` |

Within a line the checks run control byte, field count, name, uid, gid, home,
shell; across the document the first failing line wins. Accessors never fail:
they return `None`, `0`, `-1` or an empty `Vec`. The passwd and gecos fields
have no message of their own -- a control byte in the gecos field is reported
as `passwd: control byte in line <n>`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.passwd
```

Expected tail: 20 `[PASS]` lines, `xiom.passwd: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- No `/etc/shadow`, no `/etc/group`, no NSS/LDAP backing stores, no file I/O,
  no locking or atomic-replacement semantics.
- The passwd field is opaque: `x`, `*`, `!` and crypt hashes are never
  interpreted, hashed, verified or lock-detected.
- The emitter is canonical, not lossless: comments, blank lines, CRLF
  endings and source line numbers are not preserved; uid/gid leading zeros
  are normalized to canonical decimal. Everything else (spaces, gecos,
  non-ASCII bytes) is emitted byte for byte.
- A comment must start with `#` in column 1; `#` elsewhere is data. Only
  truly empty lines are blank -- a space-only line is a one-field entry and
  is rejected.
- Control bytes (0x00..0x1F, TAB included, and DEL) are rejected everywhere,
  including comments; CR is legal only as part of a CRLF pair.
- Login names are ASCII lowercase only (no dots, uppercase or `@`); the
  32-byte cap is stricter than the kernel's 255-byte `LOGIN_NAME_MAX`.
- Home and shell must be empty or absolute; no path normalization, existence
  or `/etc/shells` check is performed.
- Duplicate names and duplicate uids are preserved; name and uid lookups
  document first-match (`-1`/`None`) or all-match (`passwd_names_for_uid`)
  policies rather than merging entries.
- The system-user count uses the fixed documented `uid < 1000` boundary; it
  is advisory and not configurable.
- Byte-exact and case-sensitive throughout; bytes >= 0x80 pass through
  opaquely with no Unicode normalization.
- No line-length cap; parsing is O(input length) and holds the document in
  memory. Errors carry a 1-based line number but no column information.

See `SPEC.md` for the full semantics, grammar, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
