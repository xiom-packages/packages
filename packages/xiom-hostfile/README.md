# xiom.hostfile

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** hosts-file parsing, address/hostname validation, lookups and
> canonical emission for the documented subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.str_lower`, `xiom.string.byte_at`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.hostfile` is a pure-XIOM codec for the classic `hosts` file format:
lines of `address hostname [hostname ...]` with `#` comments and flexible
whitespace. It parses a whole document into a flat `HostsFile`, validates and
canonicalizes every address (IPv4 dotted quads and a documented IPv6 subset)
and every hostname, and emits the canonical text back. Hostnames are stored
lowercased and compared case-insensitively; IPv6 addresses are stored
lowercase with the longest leftmost zero run compressed, and an embedded
IPv4 tail is folded into hex groups.

The model is deliberately flat (four parallel per-entry vectors plus a shared
hostname pool): `Vec[StructType]` is not usable on the pinned compiler, and
the accessors are written to stay safe even if a document's vectors ever
disagree. See `SPEC.md` for the exact grammar, canonicalization rules and
error catalog.

## Install / use

```
xiom pkg install xiom.hostfile@0.1.0
```

```xi
use xiom.hostfile;
use xiom.io;

fn main() -> Int {
  let r = hostfile_parse("127.0.0.1  localhost\n::1 ip6-localhost # v6\n");
  match r {
    Ok(h) => {
      io.println(hostfile_entry_count(&h));       // 2
      match hostfile_lookup(&h, "LOCALHOST") {
        Some(addr) => { io.println(addr); },      // 127.0.0.1
        None => {},
      }
      io.println(hostfile_emit(&h));
      // 127.0.0.1 localhost
      // ::1 ip6-localhost
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Quick start

- `hostfile_parse(text)` validates the whole file; the first error is
  returned as a stable `Err("hostfile: ...")` message.
- `hostfile_address(h, i)` / `hostfile_hostnames(h, i)` / `hostfile_line(h, i)`
  read one entry; indexes are zero-based and guarded (out of range yields
  `None` / an empty `Vec` / `0`).
- `hostfile_lookup(h, name)` returns the address of the first entry whose
  hostname list contains `name` (case-insensitive first match);
  `hostfile_lookup_index(h, name)` returns its index or `-1`.
- `hostfile_entries_for_address(h, addr)` returns every entry index for an
  address, with the query canonicalized exactly like parsed input.
- `hostfile_emit(h)` writes the canonical text: single spaces, one line per
  entry, trailing newline, empty document -> `""`.

## API summary

| Function | Returns | Description |
|---|---|---|
| `hostfile_parse(text)` | `Result[HostsFile, Str]` | Parse a whole file; `Err("hostfile: ...")` on the first malformed line. |
| `hostfile_address_valid(s)` | `Bool` | True for a valid IPv4/IPv6 address in the documented subset. |
| `hostfile_address_normalize(s)` | `Option[Str]` | Canonical address text, or `None`. |
| `hostfile_hostname_valid(s)` | `Bool` | True for a valid hostname (labels 1..63, name <= 253, `A-Z a-z 0-9 - .`). |
| `hostfile_entry_count(h)` | `Int` | Number of entries. |
| `hostfile_address(h, i)` | `Option[Str]` | Canonical address of entry `i`. |
| `hostfile_hostname_count(h, i)` | `Int` | Number of hostnames of entry `i`. |
| `hostfile_hostnames(h, i)` | `Vec[Str]` | Fresh, ordered hostname list of entry `i`. |
| `hostfile_line(h, i)` | `Int` | 1-based source line of entry `i` (0 out of range). |
| `hostfile_lookup_index(h, name)` | `Int` | Index of the first matching entry, or `-1`. |
| `hostfile_lookup(h, name)` | `Option[Str]` | Address of the first matching entry. |
| `hostfile_entries_for_address(h, addr)` | `Vec[Int]` | All entry indexes with that address, in order. |
| `hostfile_emit(h)` | `Str` | Canonical hosts-file text (trailing newline). |

## Error model

Only `hostfile_parse` fails. Every message is stable ASCII and starts with
`hostfile: `:

| Message | Trigger |
|---|---|
| `hostfile: line too long: <n>` | physical line > 4096 bytes (excluding terminator) |
| `hostfile: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, comments included |
| `hostfile: bad address: <token>` | first token is not a valid address |
| `hostfile: entry with no hostname: <token>` | valid address with no hostname |
| `hostfile: bad hostname: <token>` | later token is not a valid hostname |

Lookups never fail; they return `None`, `-1` or an empty `Vec`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.hostfile
```

Expected tail: 24 `[PASS]` lines, `xiom.hostfile: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- No DNS resolution, no NSS ordering, no `/etc/services`, no file I/O.
- The emitter is canonical, not lossless: comments, blank lines, original
  whitespace and CRLF are not preserved (line numbers are not re-emitted).
- One address per line; no directives, no aliases across lines.
- IPv6 is a documented subset: at most one `::`, eight groups after
  expansion, no zone IDs; an embedded dotted quad is accepted only as the
  final 32 bits and is emitted as two hex groups (no RFC 5952
  `::ffff:a.b.c.d` output form).
- Hostnames are ASCII only (`A-Z a-z 0-9 - .`); `_` and other symbols are
  rejected, and IDN must be punycoded by the caller.
- Address comparisons are textual after canonicalization; there is no
  arithmetic, masking or ordering API.
- Errors carry a 1-based line number but no column information.

See `SPEC.md` for the full semantics, grammar, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
