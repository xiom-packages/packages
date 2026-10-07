# xiom.hostfile -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `xiom.hostfile` (`src/hostfile.xi`). Pure XIOM, no FFI.

## 1. Scope

A hosts-file codec for in-memory `Str` documents:

- parsing a file into a flat `HostsFile` document (`hostfile_parse`),
- address lexical validation and canonicalization
  (`hostfile_address_valid`, `hostfile_address_normalize`),
- hostname lexical validation (`hostfile_hostname_valid`),
- entry access (`hostfile_entry_count`, `hostfile_address`,
  `hostfile_hostname_count`, `hostfile_hostnames`, `hostfile_line`),
- lookups (`hostfile_lookup`, `hostfile_lookup_index`,
  `hostfile_entries_for_address`),
- canonical emission (`hostfile_emit`) and round-trips.

Nothing else: no DNS resolution, no NSS ordering, no `/etc/services`, no
file I/O and no allocation beyond the `Vec`/`Str` values the API returns.

## 2. Non-goals

- DNS resolution, NSS switch configuration, `nsswitch.conf`, search domains.
- `/etc/services` or any other colon/whitespace table format.
- Quoted tokens, escape sequences or preserved comments: the emitter is
  canonical, not lossless.
- Multiple addresses per line, aliases spread over lines, or any directive
  syntax.
- IPv6 zone IDs (`fe80::1%eth0`), IPv4-mapped special-casing beyond
  folding, RFC 5952 `::ffff:a.b.c.d` output form, and 128-bit arithmetic.
- CIDR/masks, routing, sorting or ordering semantics beyond document order.
- Unicode/IDN hostnames: ASCII letters, digits, hyphen and dot only.

## 3. Line grammar

```
document  = *( blank / comment / entry )
blank     = ws* EOL
comment   = ws* "#" *( byte except LF )
entry     = address ws+ hostname *( ws+ hostname ) [ ws* comment ] [ ws* ]
ws        = SP / TAB
EOL       = LF / CRLF / end of input
```

An `entry` is one physical line whose first token is an address followed by
at least one hostname; any further hostnames follow, separated by runs of
spaces/tabs. The three tokens are purely lexical: `#` is not a token
character and quoting does not exist, so the first `#` on a line always
starts a comment, even in the middle of a token (`h2#tight` contributes the
hostname `h2`).

Decisions (each is covered by the conformance suite):

1. **Lines.** The input is split at LF; one trailing CR before the LF (or
   before end of input) is removed. A file without a final newline still
   has one final line. Empty input is a zero-entry document.
2. **Blank lines.** A line with no tokens before the comment cut (blank,
   whitespace-only, comment-only) contributes no entry but still counts for
   line numbering.
3. **Line numbers.** `HostsFile.lines[i]` is the 1-based physical line of
   entry i, counted including blank and comment lines.
4. **Line cap.** A physical line longer than 4096 bytes, excluding the
   terminator, is rejected before any other check.
5. **Control bytes.** A byte 0x00..0x1F other than TAB, or DEL (0x7F), is
   rejected anywhere on the line -- comments included. The CR of a CRLF
   pair is legal because it is removed in step 1; a CR anywhere else is a
   control byte.
6. **Whitespace.** SP and TAB separate tokens; leading and trailing runs are
   ignored; runs collapse to one separator on emit.
7. **First token.** Must be a valid address (section 4); otherwise
   `Err("hostfile: bad address: <token>")`.
8. **No-hostname lines.** A valid address with no further token is
   `Err("hostfile: entry with no hostname: <token>")` (the token is the
   address as written).
9. **Hostnames.** Every later token must be a valid hostname (section 5);
   the first invalid one left to right is
   `Err("hostfile: bad hostname: <token>")`. Valid hostnames are stored
   lowercased.
10. **Error order.** Within a line the checks run cap, control byte, comment
    cut, address, hostname presence, then hostnames left to right; across
    the document the first failing line wins. Every message is stable ASCII.
11. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
    byte-wise. Bytes >= 0x80 are never valid in an address or hostname, but
    they are legal inside comments and pass through untouched.

## 4. Address rules

An address is stored and emitted in canonical form; the parser accepts the
documented spellings below and normalizes them.

### 4.1 IPv4

Four dot-separated parts, each 1..3 ASCII digits with value 0..255. A
multi-digit part may not start with `0`, so `0` and `10` are valid parts
while `00` and `01` are not. The canonical form is the input text: decimal,
no leading zeros, exactly four parts.

### 4.2 IPv6 (documented subset)

- Groups are 1..4 hexadecimal digits; upper- and lowercase are both
  accepted, output is lowercase.
- Without `::`, exactly eight groups are required (`1:2:3:4:5:6:7:8`).
- At most one `::` is allowed, and it stands for one or more all-zero
  groups: the explicit group count must be at most 7. `::` alone is the
  all-zero address.
- No empty group is allowed: a leading single `:` (`:1:2:...`), a trailing
  single `:` (`...:8:`), `:::` and a second `::` are all invalid.
- An embedded dotted quad is accepted only as the final token (the final
  32 bits) and must itself satisfy the IPv4 rules; it counts as two groups.
  It is folded into two hex groups in canonical form, so an embedded IPv4
  tail never appears in emitted text. Examples:
  `::ffff:192.168.1.1` -> `::ffff:c0a8:101`,
  `1:2:3:4:5:6:1.2.3.4` -> `1:2:3:4:5:6:102:304`,
  `::1.2.3.4` -> `::102:304`.
- Zone IDs (`%` and anything after them) are not accepted.

### 4.3 Canonical IPv6 text

1. Groups are lowercase hex with no leading zeros (`0` for a zero group).
2. The longest run of two or more consecutive zero groups is replaced by
   `::`; on a tie the leftmost run is chosen.
3. A single zero group is written `0` (`::` is never used to shorten just
   one group, RFC 5952), so `1:2:3:4:5:6:0:8` is emitted unchanged.
4. The all-zero address is `::`.
5. `::` is placed at the start or end when the run touches an edge
   (`1::`, `::1`).

Canonicalization is idempotent: normalizing an already-canonical address
returns it unchanged, and parsing emitted text returns the same entries.

## 5. Hostname rules

A hostname is a dot-separated list of labels over ASCII letters (`A-Z`,
`a-z`), digits (`0-9`) and hyphen (`-`):

1. Every label is 1..63 bytes and the whole name is 1..253 bytes.
2. A label may not start or end with `-` (`-a`, `a-`, `a-.b` invalid).
3. Empty labels are invalid: no leading dot, no trailing dot, no `..`.
4. No other byte is allowed: `_`, `?`, spaces and bytes >= 0x80 are invalid
   (`under_score` is rejected; IDN must be punycoded by the caller).
5. All-numeric labels are accepted (`123` and `1.example` are valid names);
   the address position is decided by token order, not by content.
6. Names are stored lowercased. Lookups lowercase the query first, so
   matching is ASCII case-insensitive.

## 6. Data model

```xi
pub type HostsFile = {
  addresses: Vec[Str];    // entry i: canonical address text
  hosts: Vec[Str];        // flat hostname pool, document order, lowercased
  host_starts: Vec[Int];  // entry i: first index of its slice in hosts
  host_counts: Vec[Int];  // entry i: hostname count (>= 1)
  lines: Vec[Int];        // entry i: 1-based physical line
}
```

Invariants for a parsed document: `addresses`, `host_starts`,
`host_counts` and `lines` have the same length; entry i owns
`hosts[host_starts[i] .. host_starts[i] + host_counts[i]]`;
`host_counts[i] >= 1`; slices are contiguous, in order, and cover exactly
the first `sum(host_counts)` elements of `hosts` (addresses and hostnames
never interleave). `Vec[StructType]` is not usable in this compiler, so the
model is deliberately flat (four per-entry parallel vectors plus one shared
pool) instead of a vector of entry structs.

Accessors and the emitter defensively clamp against a mismatched document:
`hostfile_entry_count` reports the smallest of the four parallel vectors and
`hostfile_hostname_count` clamps its slice to `hosts.len()`, so a corrupted
document degrades to empty results instead of reading out of range.

## 7. API signatures

```xi
pub fn hostfile_parse(text: Str) -> Result[HostsFile, Str]
pub fn hostfile_address_valid(s: Str) -> Bool
pub fn hostfile_address_normalize(s: Str) -> Option[Str]
pub fn hostfile_hostname_valid(s: Str) -> Bool
pub fn hostfile_entry_count(h: &HostsFile) -> Int
pub fn hostfile_address(h: &HostsFile, i: Int) -> Option[Str]
pub fn hostfile_line(h: &HostsFile, i: Int) -> Int
pub fn hostfile_hostname_count(h: &HostsFile, i: Int) -> Int
pub fn hostfile_hostnames(h: &HostsFile, i: Int) -> Vec[Str]
pub fn hostfile_lookup_index(h: &HostsFile, hostname: Str) -> Int
pub fn hostfile_lookup(h: &HostsFile, hostname: Str) -> Option[Str]
pub fn hostfile_entries_for_address(h: &HostsFile, address: Str) -> Vec[Int]
pub fn hostfile_emit(h: &HostsFile) -> Str
```

Complexity: parsing is O(text length); `hostfile_emit` is O(output length);
`hostfile_lookup*` is O(entries x hostnames x name length);
`hostfile_entries_for_address` is O(entries); the remaining accessors are
O(1) except `hostfile_hostnames`, which is O(hostnames).

Contract details:

- `hostfile_parse` returns `Ok` for any document in sections 3-5, including
  empty and comment-only files; all failures are `Err` per section 8.
- `hostfile_address`/`hostfile_lookup` are `None` out of range / on no
  match; `hostfile_line` and `hostfile_hostname_count` return 0 out of
  range; `hostfile_hostnames` returns a fresh empty `Vec` out of range;
  `hostfile_lookup_index` returns -1 on no match.
- `hostfile_hostnames` and the `Vec`-returning lookups return fresh
  vectors: mutating them never changes the document.
- `hostfile_lookup*` takes the first matching entry in document order
  (first-match semantics, documented and pinned by tests).
- `hostfile_entries_for_address` canonicalizes its query with the same
  normalizer as the parser, so any accepted spelling matches
  (`0:0:0:0:0:0:0:1` matches `::1`); an invalid query matches nothing.
- `hostfile_emit` writes one line per entry as
  `<address> <hostname>[ <hostname>...]\n` with single spaces and a
  trailing newline; an empty document emits `""`. `emit(parse(x))` is
  idempotent: parsing it again yields the same entries, and emitting that
  result reproduces the text byte for byte.

## 8. Error catalog

All parse failures are `Err(msg)` with an exact ASCII message:

| Message | Trigger |
|---|---|
| `hostfile: line too long: <n>` | physical line longer than 4096 bytes (excluding terminator); `<n>` is the 1-based line number |
| `hostfile: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, anywhere on line `<n>` (comments included) |
| `hostfile: bad address: <token>` | first token of an entry line is not a valid IPv4/IPv6 address |
| `hostfile: entry with no hostname: <token>` | valid address token with no hostname token after it |
| `hostfile: bad hostname: <token>` | a later token is not a valid hostname (first such token left to right) |

Check order within a line: cap, control byte, comment cut, address,
hostname presence, hostnames. Across lines: the first failing line is
reported. `<token>` is the offending token exactly as written (before
lowercasing or canonicalization).

Examples pinned by the tests:

```
hostfile_parse("256.0.0.1 host")   -> Err("hostfile: bad address: 256.0.0.1")
hostfile_parse("10.0.0.1")          -> Err("hostfile: entry with no hostname: 10.0.0.1")
hostfile_parse("10.0.0.1 -bad")     -> Err("hostfile: bad hostname: -bad")
hostfile_parse("#" + a4096)         -> Err("hostfile: line too long: 1")
```

## 9. Test plan

`tests/test_conformance.xi` (module `hostfile_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | single entry | address, one hostname, line number |
| t2 | multiple hostnames | document order, one entry, lowercasing |
| t3 | multiple entries | blank/comment lines skipped, line numbers, CRLF |
| t4 | comments | first `#` cuts, tight `#`, full-line comments, tabs |
| t5 | IPv6 canonicalization | full form to `::1`, uppercase hex lowered, `::` kept |
| t6 | IPv6 compression | leftmost longest run, lone zero kept, full form, `::` |
| t7 | IPv4 tail | folding to hex groups for mapped/compatible forms |
| t8 | bad addresses | 17 exact `bad address` errors over IPv4 and IPv6 |
| t9 | bad hostnames | 9 exact `bad hostname` errors |
| t10 | no hostname | address-only lines (with/without trailing comment/ws) |
| t11 | control bytes | NUL-range byte, DEL, mid-line CR rejected; TAB and CRLF ok; line 2 numbering |
| t12 | line cap | 4096 bytes ok, 4097 rejected, line number reported |
| t13 | lookup | first match in document order, case-insensitive, -1/None |
| t14 | entries for address | duplicates in order, canonical IPv6 query, invalid query |
| t15 | emit | single spaces, trailing newline, empty/comment-only docs |
| t16 | round-trip | parse -> emit -> parse keeps addresses/hostnames; pinned text |
| t17 | emit fixed point | emit(parse(emit(parse(x)))) identical; pinned text |
| t18 | whitespace | leading/trailing runs, tabs, collapsed separators |
| t19 | IPv4 boundaries | `0.0.0.0`, `255.255.255.255`, `1.2.3.0` |
| t20 | IPv6 boundaries | `::`, `1::`, `::1`, full 8 groups, all-`f` address |
| t21 | line endings | missing final newline, CRLF, lone trailing CR |
| t22 | validators | direct accept/reject sets for both public predicates |
| t23 | hostname limits | label 63 vs 64, name 253 vs 254, parse integration |
| t24 | accessor guards | out-of-range results and copy semantics of `hostfile_hostnames` |

The suite uses no `Vec[fn]` dispatch and no `==` on `Str` values read from
`Vec[Str]` elements: element reads bind a typed local first and every
string comparison uses `xiom.string.compare.str_compare` (BUG 17).

## 10. Compiler / stdlib notes

- v0.61.3: free functions only; no methods, lambdas, `match` arms with
  `mut` bindings, or `Vec[StructType]` are used. `HostsFile` is a plain
  struct of five homogeneous vectors.
- Every byte read goes through `_hf_byte_at`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no `UInt8` is ever compared
  against an integer literal (including literals >= 128).
- `Ok`/`Err` for the struct-payload `Result[HostsFile, Str]` are constructed
  only in the leaf helpers `_hf_ok`/`_hf_err`.
- All pushes on the parallel vectors happen in `_hf_push_entry`, so the
  five vectors cannot drift; accessors and the emitter clamp defensively.
- Only `xiom.string`, `xiom.string.compare` and `xiom.convert` are imported
  from `xiom.std` (`str_slice`, `str_lower`, `str_compare`,
  `int_to_string`). No FFI, no new dependencies.

## Contracts (batch #33 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/hostfile.xi` in the batch
#33 hardening pass (compiler v0.64.0; `package.xi` is bumped by the
coordinator at integration). 33 clauses over all 13 public entry points; all
are `ensures:` (no `requires:`), so the accepted-input domain is unchanged.
Two consecutive `& .\scripts\port.ps1 -Package xiom.hostfile -TimeoutSec 60`
runs ended `port: PASS (passed=24 failed=0 program_exit=0 exit=0)` with the
clauses active (5.51 s and 5.30 s); the 24-check conformance suite exercises
every entry point -- including the out-of-range accessor guards (t24), the
lookup and emit paths (t13-t17) and the hostname-length boundaries (t23) --
and no clause trapped, so none was dropped.

`xiom-verify src/hostfile.xi --check` (Z3 bundled with v0.64.0) reported
**0 proven / 0 violated / 31 unknown / 3 errors**; the 3 errors are the known
SMT emitter bug on the private leaf helpers (`unknown constant
_hf_find_colon` / `_hf_ipv6_canonical`, "not a proof failure of the code
under test"), and every clause is skipped because the emitter cannot encode
`Str`/`Vec` lengths, `Option`/`Result` tags or cross-call expressions. All 33
are enforced by the v0.64.0 runtime evaluator when the suite runs.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `hostfile_hostname_valid` | `s.len() == 0 => !result`; `s.len() > 253 => !result`; `result => s.len() >= 1 && s.len() <= 253` | runtime-checked (`Bool` guard pair + `Str` length band, 253 inlined) |
| `hostfile_address_normalize` | `s.len() == 0 => result is None`; `result is Some => s.len() >= 2` | runtime-checked (`Option` tag + `Str` length; 2 is the `::` minimum) |
| `hostfile_address_valid` | `s.len() == 0 => !result`; `result => s.len() >= 2` | runtime-checked (`Bool` guard pair + `Str` length) |
| `hostfile_parse` | `text.len() == 0 => result is Ok`; `result is Err => text.len() > 0` | runtime-checked (`Result` tag + `Str` length; no payload read) |
| `hostfile_entry_count` | `result >= 0`; `result <= h.addresses.len()`; `h.addresses.len() == 0 => result == 0` | runtime-checked (min-of-lens vs struct-field `Vec` length) |
| `hostfile_address` | `i < 0 => result is None`; `i >= hostfile_entry_count(h) => result is None`; `result is Some => i >= 0 && i < h.addresses.len()` | runtime-checked (`Option` tag + count cross-call) |
| `hostfile_line` | `i < 0 => result == 0`; `i >= hostfile_entry_count(h) => result == 0`; `result != 0 => i >= 0 && i < h.lines.len()` | runtime-checked (scalar sentinel + count cross-call) |
| `hostfile_hostname_count` | `i < 0 => result == 0`; `i >= hostfile_entry_count(h) => result == 0`; `result >= 0` | runtime-checked (scalar sentinel + count cross-call) |
| `hostfile_hostnames` | `result.len() == hostfile_hostname_count(h, i)`; `i < 0 => result.len() == 0`; `i >= hostfile_entry_count(h) => result.len() == 0` | runtime-checked (built `Vec` length + count cross-call) |
| `hostfile_lookup_index` | `hostfile_entry_count(h) == 0 => result == -1`; `result != -1 => result >= 0 && result < hostfile_entry_count(h)`; `result >= -1` | runtime-checked (scalar sentinel + count cross-call) |
| `hostfile_lookup` | `hostfile_lookup_index(h, hostname) < 0 => result is None`; `result is Some => hostfile_lookup_index(h, hostname) >= 0` | runtime-checked (`Option` tag + index cross-call) |
| `hostfile_entries_for_address` | `result.len() <= hostfile_entry_count(h)`; `hostfile_entry_count(h) == 0 => result.len() == 0` | runtime-checked (built `Vec` length + count cross-call) |
| `hostfile_emit` | `hostfile_entry_count(h) == 0 => result.len() == 0`; `result.len() >= hostfile_entry_count(h)` | runtime-checked (built `Str` length + count cross-call) |

All 33 clauses hold for hand-built `HostsFile` documents as well: the sentinel
and `Some` guards observe `Option` tags and `.len()` values only,
`hostfile_entry_count` is the smallest of the four parallel entry vectors (so
the count cross-call clauses see the clamped indices), and `hostfile_emit`
writes at least one LF per reported entry even when the stored address is
empty and the entry's hostname slice clamps to zero, so
`result.len() >= hostfile_entry_count(h)` is retained. Only the three public
non-re-entrant cross-calls (`hostfile_entry_count`,
`hostfile_hostname_count`, `hostfile_lookup_index`) appear in clauses; no
clause reads a parse `Ok` payload, and no `@pre` frame is claimed (no public
`&mut` parameter exists).
