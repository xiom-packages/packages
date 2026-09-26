# xiom.resolv -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.resolv` (`src/resolv.xi`). Pure XIOM, no FFI.

## 1. Scope

A resolv.conf codec for in-memory `Str` documents:

- parsing a file into a flat `ResolvConf` document (`resolv_parse`),
- address lexical validation and normalization (`resolv_address_valid`,
  `resolv_address_normalize`),
- nameserver access (`resolv_nameserver_count`, `resolv_nameserver`,
  `resolv_nameservers`, `resolv_nameserver_over_limit`),
- domain/search access (`resolv_domain`, `resolv_search_count`,
  `resolv_search_domain`),
- option access (`resolv_option_count`, `resolv_option`,
  `resolv_option_name`, `resolv_option_value`, `resolv_option_index`),
- sortlist access (`resolv_sortlist_count`, `resolv_sortlist_addr`,
  `resolv_sortlist_mask`),
- unknown/legacy directive access (`resolv_unknown_count`,
  `resolv_unknown_line`),
- canonical emission (`resolv_emit`) and round-trips.

Nothing else: no DNS resolution, no search-list semantics, no NSS
configuration, no file I/O and no allocation beyond the `Vec`/`Str` values
the API returns.

## 2. Non-goals

- Resolving names, applying search domains, `ndots` behavior, `options`
  semantics, nameserver selection or failover, sortlist ordering effects.
- `/etc/nsswitch.conf`, `/etc/hosts`, `/etc/services`, `include` handling.
- Quoted tokens, escape sequences or preserved comments: the emitter is
  canonical, not lossless.
- Attaching meaning to any directive: `domain`, `search`, `options` and
  `sortlist` are stored and returned, never interpreted.
- IPv6 compression/equivalence: addresses are stored lowercased, not
  canonicalized to RFC 5952 form, so `0:0:0:0:0:0:0:1` and `::1` stay
  distinct strings.
- Zone IDs (`fe80::1%eth0`), 128-bit arithmetic, CIDR containment/merging
  (sortlist masks are validated and stored only).
- Unicode/IDN names: names are byte runs; only control bytes, whitespace and
  the comment starters are special.

## 3. Line grammar

```
document   = *( blank / line )
blank      = ws* [ comment ] EOL
line       = content [ continuation ] ( [ ws+ comment ] / comment ) EOL
continuation = "\" EOL        ; joins the next physical line directly
comment    = ( "#" / ";" ) *( byte except LF )
EOL        = LF / CRLF / end of input
ws         = SP / TAB
```

The input is split into physical lines at LF; one trailing CR before the LF
(or before end of input) is removed. A physical line is scanned as follows,
in order:

1. **Cap.** A physical line longer than 4096 bytes, excluding the
   terminator, is `Err("resolv: line too long: <n>")` before any other
   check.
2. **Control bytes.** A byte 0x00..0x1F other than TAB, or DEL (0x7F), is
   `Err("resolv: control byte in line <n>")`, comments included. The CR of a
   CRLF pair is legal because it is removed in step 0; a CR anywhere else is
   a control byte.
3. **Comment cut.** The first `#` or `;` byte starts a comment that runs to
   end of line. There is no quoting, so the cut happens even in the middle
   of a token (`nameserver 192.0.2.3#tight` contributes the address
   `192.0.2.3`).
4. **Continuation.** If the comment-stripped text ends with a backslash
   (byte `\`), the backslash is removed, the text is joined *directly* (no
   separator is inserted) with the next physical line's comment-stripped
   text, and scanning continues on that next line. A backslash not in final
   position is an ordinary byte. A backslash on the final physical line of
   the input is `Err("resolv: backslash at end of input")`; a file may end
   with `"...\"` followed by LF and *nothing else*, which is also an error.
5. **Dispatch.** The joined logical line is split on runs of spaces/TAB into
   tokens. No tokens (blank, whitespace-only or comment-only line)
   contributes nothing. The first token is the keyword, matched
   case-sensitively against the lowercase spellings below; any other
   keyword is preserved (section 4.6).

Decisions (each is covered by the conformance suite):

1. **Line numbers.** A logical line reports the 1-based number of the first
   physical line it occupies; cap/control errors report the physical line.
2. **Whitespace.** SP and TAB separate tokens and are never part of a token;
   leading/trailing runs are ignored and runs collapse to one separator on
   emit.
3. **Comments.** Both `#` and `;` start comments, everywhere, including
   after a backslash that would otherwise continue the line. A comment on a
   joined line terminates it because the comment text is removed before the
   backslash test.
4. **Encoding.** `Str` is treated as a UTF-8 byte buffer and all scanning is
   byte-wise. Bytes >= 0x80 are legal in names, option values and unknown
   lines; they can never be part of a valid address.
5. **Error order.** Within a logical line the checks run keyword, argument
   count, then arguments left to right; for a sortlist entry mask syntax,
   address, then mask range. Across the document the first failing logical
   line wins. Every message is stable ASCII.
6. **Keyword case.** Keywords are lowercase; `NAMESERVER 1.1.1.1` is an
   unknown directive, not a syntax error.

## 4. Directives

### 4.1 `nameserver <addr>`

- Exactly one address argument. No argument is
  `Err("resolv: empty directive value: nameserver")`; a second token is
  `Err("resolv: unexpected argument: <token>")` (argument count is checked
  before the address).
- The address must satisfy section 5; the stored/emitted form is the
  input text lowercased.
- Every directive appends one nameserver in document order. There is no
  count limit: a document with more than three nameservers parses
  normally, and `resolv_nameserver_over_limit` reports `true` as a purely
  informational predicate (the classic `MAXNS` value, 3). Nothing is ever
  rejected or truncated because of the count.

### 4.2 `domain <name>`

- Exactly one name. No argument is
  `Err("resolv: empty directive value: domain")`; a second token is
  `Err("resolv: unexpected argument: <token>")`.
- The name is stored verbatim (case preserved; any non-whitespace bytes).
- **Last directive wins**: each `domain` directive replaces the stored
  value, and `resolv_domain` returns `Some` only when the last value is
  non-empty.

### 4.3 `search <name> [<name> ...]`

- At least one name; no argument is
  `Err("resolv: empty directive value: search")`.
- Names are stored verbatim in written order.
- **Last directive wins**: each `search` directive replaces the whole
  previously stored list (it never appends).
- No lookup semantics are attached (non-goal): the library does not decide
  whether `domain` or `search` would be used by a resolver.

### 4.4 `options <opt> [<opt> ...]`

- At least one option token; no argument is
  `Err("resolv: empty directive value: options")`.
- An option token is `name` or `name:value` where both parts are non-empty
  and there is at most one colon; any other non-whitespace byte is allowed
  in either part. A token that starts with `:`, ends with `:`, or contains a
  second colon is `Err("resolv: bad option: <token>")`.
- Every option token is preserved verbatim (case included) and appended in
  document order across `options` directives. `resolv_option_name` returns
  the part before the first colon, `resolv_option_value` returns
  `Some(value)` only for `name:value` tokens (a bare `rotate` has `None`),
  and `resolv_option_index` implements first-match-by-name lookup
  (byte-exact, case-sensitive) and returns `-1` when absent.

### 4.5 `sortlist <entry> [<entry> ...]`

- At least one entry; no argument is
  `Err("resolv: empty directive value: sortlist")`.
- An entry is `addr` or `addr/mask`. The mask is a canonical decimal
  (`0` allowed, no leading zero, no sign, no extra `/`) and is range-checked
  per address family: **0..32 for an IPv4 address, 0..128 for an IPv6
  address**. A bad mask is `Err("resolv: bad mask: <entry>")` where
  `<entry>` is the whole entry as written.
- Check order per entry: mask syntax, then address validity, then mask
  range. So `junk/abc` is a bad mask, `junk/24` is a bad address, and
  `1.2.3.4/33` is a bad mask.
- Entries are appended across `sortlist` directives in document order. The
  address is stored/emitted lowercased; the mask is stored as an `Int`, with
  `-1` meaning the entry was written without `/n`.
- `resolv_sortlist_mask` returns `-1` both for a maskless entry and for an
  out-of-range index; a real mask is never negative.

### 4.6 `lookup`, `family` and unknown keywords

`lookup` and `family` are recognized as legacy directives, and any other
keyword is unrecognized. Neither is an error: the logical line (comments
removed, continuations joined, leading/trailing whitespace trimmed, internal
whitespace preserved) is appended verbatim to the `unknown` pool, in
document order, and re-emitted verbatim. `resolv_unknown_count` counts them
and `resolv_unknown_line` returns one line. This version attaches no
semantics to `lookup` or `family`.

## 5. Address rules

Addresses are validated lexically; the parser accepts the documented
spellings below. Storage/emission is the input text lowercased (`str_lower`;
IPv4 digits and dots are unaffected). There is **no compression or other
canonicalization**, so `0:0:0:0:0:0:0:1` stays `0:0:0:0:0:0:0:1` and
`2001:DB8::1` becomes `2001:db8::1`.

### 5.1 IPv4

Four dot-separated parts, each 1..3 ASCII digits with value 0..255. A
multi-digit part may not start with `0`, so `0` and `10` are valid parts
while `00` and `01` are not. No other byte is allowed (in particular no
`/`, no whitespace).

### 5.2 IPv6 (documented subset)

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
  It is kept as written in the stored text (only lowercased). Examples:
  `::ffff:192.168.1.1`, `1:2:3:4:5:6:1.2.3.4`, `::1.2.3.4` are valid.
- Zone IDs (`%` and anything after them) are not accepted.

## 6. Data model

```xi
pub type ResolvConf = {
  nameservers: Vec[Str];    // all nameserver addresses, document order
  domain: Str;              // last domain directive, "" when absent
  search: Vec[Str];         // last search list, written order
  options: Vec[Str];        // all option tokens, document order
  sortlist_addrs: Vec[Str]; // sortlist entry i address
  sortlist_masks: Vec[Int]; // sortlist entry i mask, -1 = written without /n
  unknown: Vec[Str];        // preserved lookup/family/unknown lines
}
```

Invariants for a parsed document: `sortlist_addrs` and `sortlist_masks`
have the same length and are pushed only in `_rv_process`, so they cannot
drift; every other pool is independent and in document order. `Vec[StructType]`
is not usable in this compiler, so the model is deliberately flat (parallel
sortlist vectors instead of a vector of entry structs).

`resolv_sortlist_count` defensively reports the smaller of the two parallel
vectors, and every accessor guards its index, so a corrupted document
degrades to `None` / `0` / `""` / `-1` instead of reading out of range.

## 7. API signatures

```xi
pub fn resolv_parse(text: Str) -> Result[ResolvConf, Str]
pub fn resolv_address_valid(s: Str) -> Bool
pub fn resolv_address_normalize(s: Str) -> Option[Str]
pub fn resolv_nameserver_count(h: &ResolvConf) -> Int
pub fn resolv_nameserver(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_nameservers(h: &ResolvConf) -> Vec[Str]
pub fn resolv_nameserver_over_limit(h: &ResolvConf) -> Bool
pub fn resolv_domain(h: &ResolvConf) -> Option[Str]
pub fn resolv_search_count(h: &ResolvConf) -> Int
pub fn resolv_search_domain(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_option_count(h: &ResolvConf) -> Int
pub fn resolv_option(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_option_name(h: &ResolvConf, i: Int) -> Str
pub fn resolv_option_value(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_option_index(h: &ResolvConf, name: Str) -> Int
pub fn resolv_sortlist_count(h: &ResolvConf) -> Int
pub fn resolv_sortlist_addr(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_sortlist_mask(h: &ResolvConf, i: Int) -> Int
pub fn resolv_unknown_count(h: &ResolvConf) -> Int
pub fn resolv_unknown_line(h: &ResolvConf, i: Int) -> Option[Str]
pub fn resolv_emit(h: &ResolvConf) -> Str
```

Complexity: parsing is O(text length); `resolv_emit` is O(output length);
`resolv_option_index` is O(options x name length); `resolv_nameservers` is
O(nameservers); the remaining accessors are O(1) except the option
name/value helpers, which are O(token length).

Contract details:

- `resolv_parse` returns `Ok` for any document in sections 3-5, including an
  empty and a comment-only file; all failures are `Err` per section 9.
- `resolv_domain` is `None` when no `domain` directive was present;
  `resolv_option_name` is `""` out of range (unambiguous because a parsed
  option name is never empty); `resolv_sortlist_mask` is `-1` out of range
  or when the entry had no mask; the other accessors return `None` / `0` /
  empty vector out of range.
- `resolv_nameservers` returns a fresh vector: mutating it never changes the
  document.
- `resolv_option_index` takes the first option whose name part matches,
  byte-exact and case-sensitive (first-match semantics, documented and
  pinned by tests).
- `resolv_nameserver_over_limit` never affects parsing: it is a report, not
  a validation.

## 8. Canonical emission order

`resolv_emit` writes LF-terminated lines, single-space separators, in this
documented order, skipping any section that has no content:

1. one `nameserver <addr>` line per nameserver, in document order;
2. `domain <name>` when the domain is non-empty;
3. one `search <d1> <d2> ...` line with all search domains;
4. one `options <o1> <o2> ...` line with all option tokens;
5. one `sortlist <e1> <e2> ...` line with all entries, each `addr` or
   `addr/mask` (the `/mask` part is omitted when the mask is `-1`);
6. every preserved unknown/legacy line, in document order, verbatim.

Comments, blank lines, continuation backslashes, original whitespace, CRLF
and the original grouping of `options`/`sortlist` directives are not
preserved. An empty document emits `""`. For a document produced by
`resolv_parse`, `emit(parse(x))` is a fixed point: parsing the emitted text
yields the same content and emitting that result reproduces the text byte
for byte.

## 9. Error catalog

All parse failures are `Err(msg)` with an exact ASCII message:

| Message | Trigger |
|---|---|
| `resolv: line too long: <n>` | physical line longer than 4096 bytes (excluding terminator); `<n>` is the 1-based physical line |
| `resolv: control byte in line <n>` | byte 0x00..0x1F other than TAB, or DEL, anywhere on physical line `<n>` (comments included) |
| `resolv: backslash at end of input` | a comment-stripped final physical line ends with `\` (no next line to join) |
| `resolv: empty directive value: <keyword>` | a modelled keyword (`nameserver`, `domain`, `search`, `options`, `sortlist`) with no argument |
| `resolv: unexpected argument: <token>` | a second argument after `nameserver <addr>` or `domain <name>` (checked before address validation) |
| `resolv: bad address: <token>` | `nameserver` argument not a valid address; sortlist entry whose address (before `/`) is invalid (the token is the whole entry) |
| `resolv: bad mask: <token>` | sortlist entry with a malformed `/mask`, or a mask out of range for the family (the token is the whole entry) |
| `resolv: bad option: <token>` | `options` token that is empty, starts/ends with `:`, or has more than one colon |

Unknown-directive policy: `lookup`, `family` and any unrecognized keyword
never fail; their lines pass through to the `unknown` pool (section 4.6).

Examples pinned by the tests:

```
resolv_parse("nameserver 256.0.0.1\n")        -> Err("resolv: bad address: 256.0.0.1")
resolv_parse("sortlist 1.2.3.4/33\n")          -> Err("resolv: bad mask: 1.2.3.4/33")
resolv_parse("nameserver\n")                   -> Err("resolv: empty directive value: nameserver")
resolv_parse("options :5\n")                   -> Err("resolv: bad option: :5")
resolv_parse("nameserver 1.1.1.1\\")           -> Err("resolv: backslash at end of input")
resolv_parse("nameserver 1.1.1.1 8.8.8.8\n")   -> Err("resolv: unexpected argument: 8.8.8.8")
```

## 10. Test plan

`tests/test_conformance.xi` (module `resolv_tests`) runs 25 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full document | all five directives, counts, name/value split, masks |
| t2 | nameserver accumulation | document order, fresh list helper, copy semantics |
| t3 | over-limit predicate | 4/5 nameservers accepted; `true` only above 3; empty -> false |
| t4 | IPv6 normalization | lowercase, no compression, embedded v4 tail kept |
| t5 | domain/search last-wins | replacement, not accumulation, for both |
| t6 | search order | verbatim names, written order, case preserved |
| t7 | options split | tokens verbatim across multiple `options` lines |
| t8 | option lookup | first match by name, case-sensitive, `-1` absent |
| t9 | sortlist forms | v4/v6 with and without mask, parallel storage |
| t10 | sortlist masks | 0/32/128 boundaries; 8 exact bad-mask errors |
| t11 | bad addresses | 13 exact `bad address` errors; valid v4 tail |
| t12 | empty values | all five modelled keywords, comments/whitespace variants |
| t13 | unexpected argument | nameserver/domain second token, count before address |
| t14 | bad options | `:5`, `ndots:`, `a:b:c`, mixed lines; valid forms accepted |
| t15 | comments | `#` and `;`, full-line, trailing, mid-token |
| t16 | continuation | join, direct concatenation (no separator), backslash-before-comment, ordinary mid-token backslash, unknown-line join |
| t17 | backslash at EOF | no LF, LF, CRLF variants; followed-by-empty-line accepted |
| t18 | line endings | CRLF, blank lines, missing final newline, lone trailing CR |
| t19 | control bytes | NUL-range, DEL, mid-line CR, comment control; TAB/CRLF ok; line 2 |
| t20 | line cap | 4096 accepted (LF and CRLF), 4097 rejected, line numbers |
| t21 | unknown directives | `lookup`, `family`, unknown, uppercase keyword, trimmed raw line |
| t22 | emit | documented order, single spaces, LF, empty/comment-only docs, maskless entry |
| t23 | round-trip | pinned canonical text, `same_doc`, emit fixed point |
| t24 | accessor guards | out-of-range results, mask sentinel, empty-document guards |
| t25 | validators | accept/reject sets for IPv4/IPv6 and `resolv_address_normalize` |

The suite uses no `Vec[fn]` dispatch and no `==` on `Str` values read from
`Vec[Str]` elements: element reads bind a typed local first and every string
comparison uses `xiom.string.compare.str_compare` (BUG 17).

## 11. Compiler / stdlib notes

- v0.61.3: free functions only; no methods, lambdas, `match` arms with
  `mut` bindings, or `Vec[StructType]` are used. `ResolvConf` is a plain
  struct of homogeneous vectors plus one `Str`.
- Every byte read goes through `_rv_byte_at`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no `UInt8` is ever compared
  against an integer literal (including literals >= 128).
- `Ok`/`Err` for the struct-payload `Result[ResolvConf, Str]` are
  constructed only in the leaf helpers `_rv_ok`/`_rv_err`; `_rv_process`
  returns an error-message `Str` so the big dispatch function never builds a
  `Result` itself.
- The two sortlist vectors are pushed only in `_rv_process`, in one place,
  so they cannot drift; accessors and the emitter clamp defensively.
- Only `xiom.string`, `xiom.string.compare` and `xiom.convert` are imported
  from `xiom.std` (`str_slice`, `str_lower`, `str_trim`, `byte_at`,
  `str_compare`, `int_to_string`). No FFI, no new dependencies.
