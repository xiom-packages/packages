# xiom.cidr -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.cidr` (`src/cidr.xi`). Pure XIOM, no FFI.

## 1. Scope

IPv4 addresses and CIDR blocks as 32-bit `Int`s:

- parsing and formatting dotted quads (`cidr_ip_parse`, `cidr_ip_format`),
- parsing and formatting `address/len` blocks (`cidr_parse`, `cidr_format`),
- prefix masks and block range math (`cidr_mask`, `cidr_network`,
  `cidr_broadcast`, `cidr_host_count`, `cidr_first_host`, `cidr_last_host`),
- membership and intersection tests (`cidr_contains`, `cidr_overlap`).

Nothing else: no IPv6, no DNS, no sockets, no allocation beyond the `Str`
values the formatters return.

## 2. Model

- An address is the non-negative 32-bit `Int` with
  `value = a*2^24 + b*2^16 + c*2^8 + d` for the dotted quad `a.b.c.d`. Thus
  `0.0.0.0` is `0` and `255.255.255.255` is `4294967295` (2^32 - 1).
- A block is the pair `(network, prefix)`: `prefix` in 0..32 is the number of
  leading network bits, and `network` is the address with all host bits zero
  (`cidr_network(network, prefix) == network`).
- The block covers the inclusive range `[network, broadcast]`; its size is
  `2^(32-prefix)` addresses (`cidr_host_count`).
- Every function that takes an address uses only the low 32 bits (value mod
  2^32); `cidr_ip_format(-1)` is `"255.255.255.255"` and
  `cidr_network(4294967296, 32)` is `0`.
- `Int` is a 64-bit signed type on the pinned toolchain, so the exact value
  `2^32 = 4294967296` (the /0 block size) is representable and never wraps.

## 3. Parsing rules

### 3.1 `cidr_ip_parse(s: Str) -> Result[Int, Str]`

1. `s` is split on `.` and must have exactly four parts (an empty string has
   its own error; an empty slice in `cidr_parse` counts as zero parts).
2. Each part is 1..3 ASCII digits with value 0..255.
3. A multi-digit part must not start with `0`; the single-digit part `"0"` is
   allowed. So `01.2.3.4`, `1.02.3.4` and `1.2.3.04` are invalid while
   `0.0.0.0` and `1.2.3.0` are valid.
4. Empty parts, signs, spaces, trailing bytes and non-digit bytes are invalid.

### 3.2 `cidr_parse(s: Str) -> Result[(Int, Int), Str]`

1. `s` must contain a `/`; the part before it is parsed by the rule above.
2. The part after `/` is the prefix length: 1..2 canonical decimal digits
   (the parser rejects a leading zero on a multi-digit prefix, so `/024` is
   invalid, `/0` and `/24` are valid) and its value must be 0..32.
3. The returned network is `address & cidr_mask(prefix)`: **host bits are
   masked off**, so `"192.168.1.77/24"` parses to `(3232235776, 24)`.
4. `cidr_format` is the inverse on canonical pairs:
   `cidr_parse(cidr_format(net, prefix))` returns `(net, prefix)` for
   `net == cidr_network(net, prefix)` and `prefix` in 0..32.

## 4. API

```xi
pub fn cidr_ip_parse(s: Str) -> Result[Int, Str]
pub fn cidr_ip_format(ip: Int) -> Str
pub fn cidr_parse(s: Str) -> Result[(Int, Int), Str]
pub fn cidr_format(network: Int, prefix: Int) -> Str
pub fn cidr_mask(prefix: Int) -> Int
pub fn cidr_network(ip: Int, prefix: Int) -> Int
pub fn cidr_broadcast(network: Int, prefix: Int) -> Int
pub fn cidr_contains(network: Int, prefix: Int, ip: Int) -> Bool
pub fn cidr_overlap(a_net: Int, a_prefix: Int, b_net: Int, b_prefix: Int) -> Bool
pub fn cidr_host_count(prefix: Int) -> Int
pub fn cidr_first_host(network: Int, prefix: Int) -> Int
pub fn cidr_last_host(network: Int, prefix: Int) -> Int
```

Parsers are O(s.len()); every other function is O(1) and allocation-free
(the formatters allocate the `Str` they return).

## 5. Masking rules and special prefixes

| prefix | mask | block | first host | last host |
|---|---|---|---|---|
| `/0` | `0` | whole space | `0.0.0.1` | `255.255.255.254` |
| `/8` | `255.0.0.0` | `x.0.0.0`..`x.255.255.255` | `network + 1` | `broadcast - 1` |
| `/24` | `255.255.255.0` | 256 addresses | `network + 1` | `network + 254` |
| `/30` | `255.255.255.252` | 4 addresses | `network + 1` | `network + 2` |
| `/31` | `255.255.255.254` | 2 addresses | `network` | `network` |
| `/32` | `255.255.255.255` | 1 address | `network` | `network` |

Rules:

1. `cidr_mask(prefix)` returns `0` for every prefix outside 0..32.
2. Because a mask of `0` is exactly the `/0` mask, every other
   prefix-taking function treats an out-of-range prefix as `/0`:
   `cidr_network` returns `0`, `cidr_broadcast` returns `4294967295`,
   `cidr_contains` returns `true` for every address, `cidr_overlap` returns
   `true` for every pair, `cidr_host_count` returns `4294967296`,
   `cidr_first_host` returns `1` and `cidr_last_host` returns `4294967294`.
3. `cidr_contains` is inclusive at both ends: the network address and the
   broadcast address are inside the block (`/24` contains `.0` and `.255`;
   a `/31` contains both of its addresses; a `/32` contains only itself).
4. `cidr_overlap` compares the inclusive ranges: it is true for partial
   overlap, equality and containment in either direction, and false for
   disjoint or merely adjacent blocks (`192.168.1.0/24` vs `192.168.2.0/24`).
5. `cidr_first_host`/`cidr_last_host` implement the classic usable-host
   convention: for prefixes 0..30 the network and broadcast addresses are
   excluded (`last_host = broadcast - 1 = network + 2^(32-prefix) - 2`).
   For `/31` and `/32` there is no separate host range under this library's
   convention, so **both return the network address itself** (RFC 3021
   point-to-point use of a `/31` is left to the caller).

## 6. Error catalog

Only the two parsers can fail; all messages are stable ASCII strings.

`cidr_ip_parse`:

| Condition | Message |
|---|---|
| `s == ""` | `cidr: empty address` |
| Part count is not four (`1.2.3`, `1.2.3.4.5`, empty slice) | `cidr: expected four octets` |
| Empty part (`.1.2.3`, `1.2.3.`, `1..2.3`), non-digit byte (`a.b.c.d`, `+`, `-`, space), more than three digits (`1234.2.3.4`), value above 255 (`256.0.0.1`), leading zero (`01.2.3.4`) | `cidr: invalid octet` |

`cidr_parse`:

| Condition | Message |
|---|---|
| `s == ""` | `cidr: empty input` |
| No `/` anywhere | `cidr: missing prefix length` |
| Address invalid | the `cidr_ip_parse` message, verbatim |
| Empty prefix (`/`), non-digit byte (`/2 4`, `/24x`, `/-1`), second `/` (`/24/8`), leading zero (`/024`) | `cidr: invalid prefix length` |
| Numeric prefix above 32 (`/33`) | `cidr: prefix length out of range` |

Examples (tests pin these exactly):
`cidr_ip_parse("256.0.0.1") -> Err("cidr: invalid octet")`,
`cidr_ip_parse("1.2.3") -> Err("cidr: expected four octets")`,
`cidr_parse("192.168.1.77/24") -> Ok((3232235776, 24))`,
`cidr_parse("1.2.3.4/33") -> Err("cidr: prefix length out of range")`.

## 7. Test plan

`tests/test_conformance.xi` (module `cidr_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | ip_parse pinned | seven dotted quads to exact 32-bit values, including 2^31 and 2^32-1 |
| t2 | ip_format pinned | seven exact values to dotted text, including 0.0.0.0 and 255.255.255.255 |
| t3 | round-trip | `parse(format(v)) == v` for 0, byte and word boundaries and the top of the range |
| t4 | bad octets | value > 255, four digits, junk, signs, trailing space -> exact `invalid octet` |
| t5 | part count / empty parts | empty input, 3/5/6 parts, leading/trailing/doubled dot |
| t6 | leading zeros | `01`/`02`/`04`/`00`/`001` rejected, bare `0` octets accepted |
| t7 | cidr host masking | `/8`, `/12`, `/16`, `/24`, `/30`, `/32`, `/0` all mask host bits |
| t8 | prefix canonicality | `/0`, `/31`, `/32` accepted; `/33`, `/999`, `/024`, `/`, `/-1`, `/24x`, `/24/8`, `/2 4` exact errors |
| t9 | delegated errors | empty input, missing slash, address errors inside `cidr_parse` |
| t10 | cidr_format | masked network text, `/0`, `/32`, and parse(format(...)) round-trip |
| t11 | mask table | /0 /1 /8 /12 /16 /24 /30 /31 /32 exact masks; -1, 33, 64 -> 0 |
| t12 | network | `/8`, `/16`, `/24`, `/32`, `/0`; 2^32-1 input; out-of-range -> 0 |
| t13 | broadcast | `/8`, `/16`, `/24`, `/30`, `/32`, `/0`; out-of-range -> 4294967295 |
| t14 | contains boundaries | network/broadcast inclusive, just-outside excluded, `/31`, `/32`, `/0` |
| t15 | overlap | containment both orders, equality, `/32` in `/8`, disjoint, adjacent, `/0` |
| t16 | overlap symmetry | same result swapped; `/12` contains its `/16` but not the next `/12` |
| t17 | host_count | /0 = 4294967296, /8, /24 = 256, /30 = 4, /31 = 2, /32 = 1; out-of-range = /0 |
| t18 | first/last host | /0, /8, /24, /30 usable ranges; unmasked network input masked first |
| t19 | /31 and /32 specials | both functions return the network address |
| t20 | per-block consistency | `network == net & mask`, `broadcast == network + count - 1`, containment of both ends, exclusion just outside |
| t21 | /0 and 32-bit masking | `/0` spans the space; 2^32 and -1 masked; format(-1) = 255.255.255.255 |
| t22 | huge values exact | /0 range size, 2^32-1 arithmetic, 256 * 2^24 = 2^32 |

The suite performs no `Str` equality and uses no `Vec[Str]`, so BUG 17
(`==` on `Str` values read from `Vec[Str]` elements lowers to a pointer
comparison) cannot apply; all string comparisons go through
`xiom.string.compare.str_compare`.

## 8. Limitations

- **IPv4 only. No IPv6** parsing, formatting, masking or 128-bit support.
- No CIDR range notation (`a.b.c.d-e.f.g.h`), no hostnames, no whitespace,
  no signs, no non-canonical forms.
- `cidr_parse` does not preserve the host address; it returns the masked
  network by design.
- No routing table, longest-prefix match, address allocation or arithmetic
  beyond the documented functions.
- No allocation in the range math; the formatters build their returned `Str`.

## 9. Compiler / stdlib notes

- v0.61.3: free functions only; no methods, lambdas, `Vec` values, `match`
  arms, struct returns or function-pointer tables are used anywhere in the
  module.
- Every byte read goes through `_cidr_byte_at`
  (`(string.byte_at(s, i) as Int) & 0xFF`), so no `UInt8` value is ever
  compared against an integer literal (including literals >= 128).
- All `Ok`/`Err` values are constructed in the tiny leaf helpers
  `_ip_ok`/`_ip_err`/`_cidr_ok`/`_cidr_err`.
- Only `xiom.string` and `xiom.convert` are imported from `xiom.std`.
