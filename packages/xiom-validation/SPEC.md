# xiom.validation -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.validation` (`src/validation.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free set of infallible `Bool` validators for common text
formats:

- `valid_is_email` -- pragmatic ASCII email address,
- `valid_is_ipv4` / `valid_is_ipv6` -- IP address literals,
- `valid_is_hex` -- non-empty hex string,
- `valid_is_uuid` -- canonical hyphenated UUID,
- `valid_is_slug` -- lowercase dash-separated slug,
- `valid_is_date_ymd` -- proleptic Gregorian calendar date,
- `valid_is_port` -- TCP/UDP port number range.

All functions return `Bool`, never `Result`: there is deliberately no error
channel and no allocation. Scanning is byte-wise over the input `Str`.

## 2. Non-goals

- Full RFC 5322 email: no quoted local parts, comments, folding whitespace,
  address literals (`user@[192.0.2.1]`), or IDN/Unicode domains.
- Full RFC 4291 IPv6: no zone IDs, no embedded dotted-quad tail
  (`::ffff:192.168.0.1`), no IPv4-mapped special-casing.
- Punycode, normalization, case folding or DNS resolution.
- Date *string* parsing: `valid_is_date_ymd` takes three `Int`s.
- FFI, file I/O, registry integration.

## 3. Per-validator rules

Byte values refer to `string.byte_at` widened with `(b as Int) & 0xFF`, so all
comparisons happen in Int space.

### 3.1 `valid_is_email(s: Str) -> Bool`

1. `s.len()` must be > 0 and contain **exactly one** `@` (0x40).
2. Any byte >= 128 rejects the whole string (ASCII only).
3. The `@` may be neither the first nor the last byte.
4. Local part = `s[0..at]`, 1..64 bytes inclusive, each byte in
   `[A-Za-z0-9._%+-]`; it must not start with `.`, must not end with `.`, and
   must not contain `..`.
5. Domain = `s[at+1..]` split on `.` into non-empty labels; each label byte is
   in `[A-Za-z0-9-]`; a label must not start or end with `-`.
6. The domain must contain at least one `.`.
7. The final label (TLD) must be at least 2 bytes and consist of ASCII
   letters only (`[A-Za-z]`).

Accepted: `a@b.co`, `first.last+tag@sub.domain.org`, `A.B@Example.COM`,
`user_name%x-1@example.com`. Rejected: `no-at-sign.com`, `two@@at.co`,
`a@b@c.co`, `.lead@x.co`, `trail.@x.co`, `two..dots@x.co`, `a@b`,
`a@b.c`, `a@b..co`, `a@-bad.co`, `a@bad-.co`, `a@b.c0`, `a b@x.co`,
`café@x.co`, `a@exämple.co`, `a@[127.0.0.1]`.

### 3.2 `valid_is_ipv4(s: Str) -> Bool`

1. `s` is split on `.`; there must be exactly 4 parts.
2. Every part is 1..3 ASCII digits, value 0..255.
3. A part with more than one digit must not start with `0`; the single-digit
   part `"0"` is allowed.
4. Empty parts, signs, spaces and non-digit bytes reject.

Accepted: `0.0.0.0`, `255.255.255.255`, `192.168.1.1`, `1.2.3.0`, `10.0.255.9`.
Rejected: `256.0.0.1`, `1.2.3`, `1.2.3.4.5`, `01.2.3.4`, `1.02.3.4`,
`1..2.3`, `1.2.3.`, `.1.2.3`, `a.b.c.d`, `""`.

### 3.3 `valid_is_ipv6(s: Str) -> Bool`

1. Colon runs longer than two (`:::`) reject.
2. At most one `::` run; a second `::` rejects.
3. With no `::`: exactly 8 groups, each 1..4 hex digits separated by single
   `:`; an empty group (leading/trailing/doubled single `:`) rejects.
4. With `::`: the explicit groups left and right of it each follow rule 3
   (empty side allowed) and their total must be <= 7, because `::` stands for
   at least one zero group. `::` alone is the all-zero address.

Accepted: `::`, `::1`, `fe80::1`, `2001:db8::`, `2001:db8:0:0:0:0:0:1`,
`1:2:3:4:5:6:7:8`, `1::`, `::8`, `1:2:3:4:5:6:7::`, `ABCD::EF01`.
Rejected: `:::` , `12345::`, `:`, `:::1`, `fe80::1:`, `:fe80::1`, `g::1`,
`1::2::3`, `1:2:3:4:5:6:7:8:9`, `1:2:3:4:5:6:7:8::`, `1::2:3:4:5:6:7:8`, `""`.

### 3.4 `valid_is_hex(s: Str) -> Bool`

Non-empty; every byte in `[0-9A-Fa-f]`. Accepts `0`, `A`, `00ff`, `deadBEEF`.
Rejects `""`, `0x12`, `12 34`, `xyz`, `12g4`, `dead-beef`.

### 3.5 `valid_is_uuid(s: Str) -> Bool`

Exactly 36 bytes; hyphens at zero-based positions 8, 13, 18 and 23; every
other byte a hex digit (`[0-9A-Fa-f]`). Case-insensitive. Accepts
`550e8400-e29b-41d4-a716-446655440000` and its uppercase form. Rejects wrong
lengths, misplaced/missing hyphens and non-hex bytes.

### 3.6 `valid_is_slug(s: Str) -> Bool`

Non-empty; every byte in `[a-z0-9]` or `-`; `-` may not be the first or last
byte and may not follow another `-`. Accepts `hello`, `hello-world`,
`a1-b2-c3`, `x`. Rejects `""`, `-hello`, `hello-`, `hello--world`, `-`,
`Hello`, `hello_world`, `hello world`, `héllo`.

### 3.7 `valid_is_date_ymd(y: Int, m: Int, d: Int) -> Bool`

Year >= 1; month 1..12; day 1..days_in_month(y, m), where February has 29 days
iff the year is leap under the proleptic Gregorian rule (divisible by 4,
except centuries, except every 400 years). Truth table pinned by the tests:
2000-02-29 and 2024-02-29 are valid; 1900-02-29 and 2100-02-29 are not;
2024-04-31, 2024-02-30, 2024-13-01, 2024-01-00 and year 0 are not.

### 3.8 `valid_is_port(n: Int) -> Bool`

`1 <= n <= 65535`. `0`, negatives and `65536` are invalid.

## 4. API signatures

```xi
pub fn valid_is_email(s: Str) -> Bool
pub fn valid_is_ipv4(s: Str) -> Bool
pub fn valid_is_ipv6(s: Str) -> Bool
pub fn valid_is_hex(s: Str) -> Bool
pub fn valid_is_uuid(s: Str) -> Bool
pub fn valid_is_slug(s: Str) -> Bool
pub fn valid_is_date_ymd(y: Int, m: Int, d: Int) -> Bool
pub fn valid_is_port(n: Int) -> Bool
```

Complexity: every string validator is O(s.len()); the date and port checks are
O(1). All validators are allocation-free.

## 5. Test plan

`tests/test_conformance.xi` (module `validation_tests`) runs 24 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | email valid basics | one `@`, charset, TLD, case |
| t2 | email structure | no/extra `@`, empty sides |
| t3 | email local dots | leading/trailing/doubled dot, charset |
| t4 | email domain labels | dot required, dash rules |
| t5 | email ASCII/TLD | non-ASCII rejected, letter TLD >= 2 |
| t6 | email local length | 64 accepted, 65 rejected |
| t7 | ipv4 valid | 0.0.0.0, 255.255.255.255, private ranges |
| t8 | ipv4 invalid | 256, part count, leading zero, junk, empty |
| t9 | ipv4 zero parts | `0` allowed, `00`/`01`/`04` rejected |
| t10 | ipv6 valid | `::1`, `fe80::1`, full 8 groups, `::` |
| t11 | ipv6 invalid | `:::`, `12345::`, `:`, `:::1`, 9 groups, `"1::2::3"` |
| t12 | ipv6 edges | uppercase hex, `::` bounds, stray colons |
| t13 | hex valid | mixed case, single digit |
| t14 | hex invalid | empty, `0x` prefix, space, non-hex, dash |
| t15 | uuid valid | canonical, uppercase, all-zero |
| t16 | uuid invalid | short/long, missing hyphen, `zzzz`, empty |
| t17 | slug valid | single words and dash chains |
| t18 | slug invalid | empty, edge/double dash, case, space, non-ASCII |
| t19 | dates leap | 2000/2024/2004/2400 yes; 1900/2100 no |
| t20 | dates bounds | 31/30/29/28-day months, month and day bounds, year >= 1 |
| t21 | dates February | Feb 28/29/30 behaviour |
| t22 | ports | 1, 80, 443, 65535 yes; 0, 65536, -1 no |
| t23 | email TLD | `cd` yes; `c`, `co2`, `b_c`, `[127.0.0.1]` no |
| t24 | ipv6 `::` | compression counts explicit groups <= 7 |

The suite performs no `Str` equality, so BUG 17 (`==` on `Str` values read from
`Vec[Str]` elements lowers to a pointer comparison) cannot apply.

## 6. Known limitations

- Pragmatic ASCII validators, not full RFC 5322 / RFC 4291 (section 2).
- Entirely byte-oriented: multi-byte UTF-8 input never validates.
- No length limits beyond the email local part and the IPv6/UUID shapes.
- The date validator accepts any lexical form the caller converted to `Int`s;
  it does not parse `"YYYY-MM-DD"` strings.

## 7. Compiler / stdlib notes

- v0.61.3: no FFI, no `Vec` values, no lambdas, no `match`, and no
  struct-returning functions, so none of the known codegen traps apply.
- Every byte read goes through `_byte_at_i` (`(string.byte_at(s, i) as Int) &
  0xFF`), so no `UInt8` value is ever compared against an integer literal
  (including literals >= 128).
- Helpers and constants live in Int space; only `xiom.string.byte_at` is used
  from the stdlib, and `xiom.string.compare` is not imported because no `Str`
  equality occurs here.
