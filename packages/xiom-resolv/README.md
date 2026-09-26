# xiom.resolv

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** resolv.conf parsing, lexical address/mask validation, directive
> access and canonical emission for the documented subset.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.str_lower`, `xiom.string.str_trim`, `xiom.string.byte_at`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Overview

`xiom.resolv` is a pure-XIOM codec for the classic `resolv.conf` format:
`nameserver`, `domain`, `search`, `options` and `sortlist` directives, with
`#`/`;` comments, blank lines, LF/CRLF endings and backslash continuation
lines. It parses a whole document into a flat `ResolvConf`, lexically
validates and normalizes every address and sortlist mask, and emits the
canonical text back.

The model is deliberately flat (independent document-order pools plus a
parallel sortlist address/mask pair): `Vec[StructType]` is not usable on the
pinned compiler, and the accessors are written to stay safe even if a
document's vectors ever disagree. The library attaches **no semantics** to
the directives: it never resolves names, never applies search lists and
never interprets `options`. See `SPEC.md` for the exact grammar,
normalization rules and error catalog.

## Install / use

```
xiom pkg install xiom.resolv@0.1.0
```

```xi
use xiom.resolv;
use xiom.io;

fn main() -> Int {
  let r = resolv_parse("nameserver 2001:DB8::53 # v6\nsearch a.example b.example\noptions ndots:5 rotate\nsortlist 10.0.0.0/8\n");
  match r {
    Ok(h) => {
      io.println(resolv_nameserver_count(&h));   // 1
      match resolv_nameserver(&h, 0) {
        Some(addr) => { io.println(addr); },     // 2001:db8::53
        None => {},
      }
      io.println(resolv_option_index(&h, "ndots")); // 0
      io.println(resolv_emit(&h));
      // nameserver 2001:db8::53
      // search a.example b.example
      // options ndots:5 rotate
      // sortlist 10.0.0.0/8
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Quick start

- `resolv_parse(text)` validates the whole file; the first error is returned
  as a stable `Err("resolv: ...")` message.
- `resolv_nameserver(h, i)` / `resolv_search_domain(h, i)` /
  `resolv_option(h, i)` / `resolv_sortlist_addr(h, i)` read one item;
  indexes are zero-based and guarded (out of range yields `None`).
- `resolv_domain(h)` is `None` when no `domain` directive was present;
  `domain` and `search` are last-directive-wins.
- `resolv_option_index(h, name)` finds the first option by name
  (case-sensitive); `resolv_option_name(h, i)` and
  `resolv_option_value(h, i)` split `name:value` tokens.
- `resolv_sortlist_mask(h, i)` returns the mask, or `-1` when the entry was
  written without `/n`.
- `resolv_unknown_count(h)` / `resolv_unknown_line(h, i)` expose preserved
  `lookup`, `family` and unrecognized directive lines.
- `resolv_nameserver_over_limit(h)` is informational only: more than three
  nameservers is accepted and reported, never rejected.
- `resolv_emit(h)` writes the canonical text: documented directive order,
  single spaces, LF, empty document -> `""`.

## API summary

| Function | Returns | Description |
|---|---|---|
| `resolv_parse(text)` | `Result[ResolvConf, Str]` | Parse a whole file; `Err("resolv: ...")` on the first malformed line. |
| `resolv_address_valid(s)` | `Bool` | True for a valid IPv4/IPv6 address in the documented subset. |
| `resolv_address_normalize(s)` | `Option[Str]` | Address text lowercased, or `None`. |
| `resolv_nameserver_count(h)` | `Int` | Number of nameserver directives. |
| `resolv_nameserver(h, i)` | `Option[Str]` | Address of nameserver `i`. |
| `resolv_nameservers(h)` | `Vec[Str]` | Fresh list of all nameservers, in order. |
| `resolv_nameserver_over_limit(h)` | `Bool` | Informational: true when more than 3 nameservers. |
| `resolv_domain(h)` | `Option[Str]` | Domain of the last `domain` directive. |
| `resolv_search_count(h)` | `Int` | Domains in the last `search` list. |
| `resolv_search_domain(h, i)` | `Option[Str]` | Search domain `i`, verbatim. |
| `resolv_option_count(h)` | `Int` | Number of option tokens. |
| `resolv_option(h, i)` | `Option[Str]` | Option token `i`, verbatim. |
| `resolv_option_name(h, i)` | `Str` | Name part (before `:`), `""` out of range. |
| `resolv_option_value(h, i)` | `Option[Str]` | Value part, `None` when the token has no `:`. |
| `resolv_option_index(h, name)` | `Int` | First option with that name, or `-1`. |
| `resolv_sortlist_count(h)` | `Int` | Number of sortlist entries. |
| `resolv_sortlist_addr(h, i)` | `Option[Str]` | Address of sortlist entry `i`. |
| `resolv_sortlist_mask(h, i)` | `Int` | Mask of entry `i`, `-1` when no `/n` was written. |
| `resolv_unknown_count(h)` | `Int` | Preserved unknown/legacy directive lines. |
| `resolv_unknown_line(h, i)` | `Option[Str]` | Preserved raw line `i`. |
| `resolv_emit(h)` | `Str` | Canonical resolv.conf text (LF). |

## Error model

Only `resolv_parse` fails. Every message is stable ASCII and starts with
`resolv: `:

| Message | Trigger |
|---|---|
| `resolv: line too long: <n>` | physical line > 4096 bytes (excluding terminator) |
| `resolv: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, comments included |
| `resolv: backslash at end of input` | final physical line ends with `\` |
| `resolv: empty directive value: <keyword>` | modelled keyword with no argument |
| `resolv: unexpected argument: <token>` | second argument after `nameserver`/`domain` |
| `resolv: bad address: <token>` | invalid address in `nameserver` or `sortlist` |
| `resolv: bad mask: <token>` | malformed or out-of-range `/mask` in `sortlist` |
| `resolv: bad option: <token>` | option token with empty name/value or 2+ colons |

`lookup`, `family` and unknown keywords are never errors: they pass through
to the `unknown` pool. Accessors never fail; they return `None`, `-1`, `""`
or an empty `Vec`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.resolv
```

Expected tail: 25 `[PASS]` lines, `xiom.resolv: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- No DNS resolution, search-list semantics, `options` interpretation or
  sortlist ordering effects; the library is a codec only.
- The emitter is canonical, not lossless: comments, blank lines, original
  whitespace, CRLF, continuation backslashes and directive grouping are not
  preserved.
- IPv6 addresses are stored lowercased but **not** compressed or otherwise
  canonicalized; `0:0:0:0:0:0:0:1` and `::1` are distinct strings.
- Sortlist masks are validated (0..32 for IPv4, 0..128 for IPv6) and
  stored; there is no CIDR containment, masking or 128-bit arithmetic.
- `domain` and `search` are last-directive-wins; names are byte runs with no
  hostname validation, and no precedence rule between the two is applied.
- Errors carry a physical/logical line number only for the cap, control-byte
  and backslash-at-EOF cases.
- `lookup` and `family` are recognized keyword names but have no structured
  accessors in this version; they are preserved as raw lines alongside
  unrecognized directives.

See `SPEC.md` for the full semantics, grammar, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
