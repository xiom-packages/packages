# xiom.socks -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.socks`, version `0.1.0`).
Module: `src/socks.xi` (`module xiom.socks`).
Depends on `xiom.std`; the library module imports `xiom.string` (for
`socks5_domain_bytes`). The tests add `xiom.test`, `xiom.io`,
`xiom.string`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## Scope

A pure-XIOM (no FFI) message codec for the SOCKS5 negotiation a CONNECT
client and server exchange (RFC 1928), plus the RFC 1929 username/password
sub-negotiation:

- client greeting (`VER`, `NMETHODS`, `METHODS`) -- build and parse;
- server method selection (`VER`, `METHOD`, including `0xFF` "no acceptable
  methods") -- build and parse;
- request (`VER`, `CMD`, `RSV`, `ATYP`, address, port) -- build and parse,
  address types IPv4 / domain / IPv6, port big-endian;
- reply (`VER`, `REP` 0x00..0x08, `RSV`, `ATYP`, `BND.ADDR`, `BND.PORT`) --
  build and parse;
- RFC 1929 credential request (`VER=1`, `ULEN`, `UNAME`, `PLEN`, `PASSWD`)
  and status reply (`VER=1`, `STATUS`) -- build and parse;
- deterministic `Err(Str)` validation for bad version bytes, nonzero `RSV`,
  unknown command/reply/address type, empty or oversized domains, bad IPv4
  and IPv6 lengths, out-of-range method/port/status, oversized method lists
  and oversized credentials, and every truncated shape.

## Non-goals

- **No sockets / I/O.** Nothing opens, reads, writes or closes a
  connection; the caller owns the transport.
- **No SOCKS4** (or SOCKS4a) messages.
- **No BIND or UDP ASSOCIATE flows.** CMD `0x02` and `0x03` are carried
  structurally by the shared request layout, but no association state
  machine, relay, UDP datagram header or payload handling exists.
- **No GSSAPI** (`METHOD 0x01` is a constant only).
- **No framing.** Parsers decode the first message in a buffer and ignore
  trailing bytes; stream framing is the caller's job.
- **No DNS / address text handling.** Addresses stay raw bytes; there is no
  string formatting, parsing or name resolution.
- **No credential validation.** The RFC 1929 fields are opaque bytes; no
  character-set checks or comparison logic.
- **No streaming/incremental parsing** and no message writer for a whole
  negotiation sequence.

## Byte-level layout

### Greeting (client -> server)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | VER | `0x05` |
| 1 | 1 | NMETHODS | number of method bytes, 0..255 |
| 2 | NMETHODS | METHODS | one method identifier per byte, each 0..255 |

`NMETHODS = 0` is accepted on parse and allowed on build: the message is
structurally valid but offers the server nothing (a server answers
`0xFF`). Bytes after the METHODS list are ignored.

### Method selection (server -> client)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | VER | `0x05` |
| 1 | 1 | METHOD | `0x00` no auth, `0x01` GSSAPI, `0x02` username/password, `0xFF` no acceptable methods; any byte parses |

### Request (client -> server) and reply (server -> client)

Both messages share one layout; the second byte is CMD for a request and
REP for a reply, and the address is the destination (request) or the bound
address (reply).

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | VER | `0x05` |
| 1 | 1 | CMD / REP | CMD `0x01..0x03`; REP `0x00..0x08` |
| 2 | 1 | RSV | `0x00` |
| 3 | 1 | ATYP | `0x01` IPv4, `0x03` domain, `0x04` IPv6 |
| 4 | variable | ADDR | see the addressing rules below |
| 4 + address bytes | 2 | PORT / BND.PORT | unsigned big-endian, 0..65535 |

Commands (RFC 1928): `0x01` CONNECT, `0x02` BIND, `0x03` UDP ASSOCIATE.
Reply codes: `0x00` succeeded, `0x01` general server failure, `0x02` not
allowed by ruleset, `0x03` network unreachable, `0x04` host unreachable,
`0x05` connection refused, `0x06` TTL expired, `0x07` command not
supported, `0x08` address type not supported; `0x09..0xFF` are rejected.

### Address rules

| ATYP | ADDR on the wire | `addr` field in the structs | Valid lengths |
|---|---|---|---|
| `0x01` IPv4 | 4 bytes, verbatim | 4 bytes | exactly 4 |
| `0x03` domain | 1 length byte (1..255), then that many name bytes | the name bytes only, **no** length prefix | 1..255 |
| `0x04` IPv6 | 16 bytes, verbatim | 16 bytes | exactly 16 |

IPv4 and IPv6 bytes are opaque (no textual or numeric form is produced or
consumed).

### RFC 1929 credential request (client -> server)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | VER | `0x01` |
| 1 | 1 | ULEN | 1..255; an empty username is rejected |
| 2 | ULEN | UNAME | raw bytes |
| 2 + ULEN | 1 | PLEN | 0..255; an empty password is accepted |
| 3 + ULEN | PLEN | PASSWD | raw bytes |

### RFC 1929 status reply (server -> client)

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 | VER | `0x01` |
| 1 | 1 | STATUS | `0x00` success, nonzero failure; any byte parses |

## API signatures

All functions are free functions in module `xiom.socks` (no self methods):

```xi
pub type Socks5Greeting   = { methods: Vec[Int]; }
pub type Socks5Choice     = { method: Int; }
pub type Socks5Request    = { cmd: Int; atyp: Int; addr: Vec[UInt8]; port: Int; }
pub type Socks5Reply      = { rep: Int; atyp: Int; addr: Vec[UInt8]; port: Int; }
pub type Socks5UserPass   = { uname: Vec[UInt8]; passwd: Vec[UInt8]; }
pub type Socks5AuthReply  = { status: Int; }

pub fn socks5_greeting_build(out: &mut Vec[UInt8], methods: &Vec[Int]) -> Result[Unit, Str]
pub fn socks5_greeting_parse(data: &Vec[UInt8]) -> Result[Socks5Greeting, Str]
pub fn socks5_choice_build(out: &mut Vec[UInt8], method: Int) -> Result[Unit, Str]
pub fn socks5_choice_parse(data: &Vec[UInt8]) -> Result[Socks5Choice, Str]
pub fn socks5_request_build(out: &mut Vec[UInt8], cmd: Int, atyp: Int, addr: &Vec[UInt8], port: Int) -> Result[Unit, Str]
pub fn socks5_request_parse(data: &Vec[UInt8]) -> Result[Socks5Request, Str]
pub fn socks5_reply_build(out: &mut Vec[UInt8], rep: Int, atyp: Int, addr: &Vec[UInt8], port: Int) -> Result[Unit, Str]
pub fn socks5_reply_parse(data: &Vec[UInt8]) -> Result[Socks5Reply, Str]
pub fn socks5_auth_build(out: &mut Vec[UInt8], uname: &Vec[UInt8], passwd: &Vec[UInt8]) -> Result[Unit, Str]
pub fn socks5_auth_parse(data: &Vec[UInt8]) -> Result[Socks5UserPass, Str]
pub fn socks5_auth_reply_build(out: &mut Vec[UInt8], status: Int) -> Result[Unit, Str]
pub fn socks5_auth_reply_parse(data: &Vec[UInt8]) -> Result[Socks5AuthReply, Str]
pub fn socks5_domain_bytes(name: Str) -> Vec[UInt8]
```

Constants: `SOCKS5_VERSION` (5), `AUTH_VERSION` (1), `CMD_CONNECT` /
`CMD_BIND` / `CMD_UDP_ASSOCIATE` (1/2/3), `ATYP_IPV4` / `ATYP_DOMAIN` /
`ATYP_IPV6` (1/3/4), `METHOD_NO_AUTH` / `METHOD_GSSAPI` /
`METHOD_USERPASS` / `METHOD_NO_ACCEPTABLE` (0/1/2/255), and the nine reply
codes `REP_SUCCEEDED` .. `REP_ADDRESS_TYPE_NOT_SUPPORTED` (0..8).

## Semantics

`socks5_greeting_build(out, methods)`
: Validates the list size (at most 255) and every method (0..255) before
  writing. Writes `VER`, `NMETHODS`, then the methods in order. The empty
  list is allowed and writes `05 00`.

`socks5_greeting_parse(data)`
: Requires at least 2 bytes, `VER = 5`, and enough bytes for `NMETHODS`
  methods. Returns the methods as `Int` values 0..255. Trailing bytes are
  ignored.

`socks5_choice_build(out, method)`
: Requires 0 <= `method` <= 255 and writes `VER`, `METHOD`.

`socks5_choice_parse(data)`
: Requires at least 2 bytes and `VER = 5`; returns any METHOD byte,
  including `0xFF`. Trailing bytes are ignored.

`socks5_request_build(out, cmd, atyp, addr, port)`
: Validation order is CMD (1..3), then ATYP + address length, then PORT
  (0..65535). For ATYP `0x03` the one-byte length prefix is written before
  the name bytes; `addr` holds the name alone. Nothing is written before
  every check passes.

`socks5_request_parse(data)`
: Check order is: 4-byte fixed header; `VER = 5`; CMD 1..3; `RSV = 0`;
  ATYP in {1,3,4}; address fits (with the domain length byte 1..255); two
  port bytes. Returns CMD, ATYP, the raw address and the big-endian port.
  Trailing bytes are ignored.

`socks5_reply_build(out, rep, atyp, addr, port)`
: Same as `socks5_request_build` with REP (0..8) instead of CMD.

`socks5_reply_parse(data)`
: Same as `socks5_request_parse` with REP (0..8) instead of CMD.

`socks5_auth_build(out, uname, passwd)`
: Requires `uname.len()` in 1..255 and `passwd.len()` in 0..255 before
  writing `VER=1`, `ULEN`, `UNAME`, `PLEN`, `PASSWD`.

`socks5_auth_parse(data)`
: Requires 2 bytes, `VER = 1`, `ULEN` >= 1, the username bytes, the PLEN
  byte and the password bytes (an empty password is valid). Trailing bytes
  are ignored.

`socks5_auth_reply_build(out, status)`
: Requires 0 <= `status` <= 255 and writes `VER=1`, `STATUS`.

`socks5_auth_reply_parse(data)`
: Requires 2 bytes and `VER = 1`; returns the STATUS byte unchanged.

`socks5_domain_bytes(name)`
: Copies the bytes of `name` verbatim into a fresh vector for use as an
  ATYP `0x03` address. No validation or length-prefixing happens here; the
  builders validate 1..255 bytes.

All builders are atomic: every condition is checked before the first byte
is appended, so `out` is byte-for-byte unchanged when a builder fails.

## Error string catalog

All errors are `Err(Str)` with these exact messages:

| Function(s) | Condition | Error text |
|---|---|---|
| `greeting_build` | `methods.len() > 255` | `socks: too many methods` |
| `greeting_build`, `choice_build` | method < 0 or > 255 | `socks: method out of range` |
| `greeting_parse` | fewer than 2 bytes | `socks: truncated greeting` |
| `greeting_parse` | `VER != 5` | `socks: bad version` |
| `greeting_parse` | fewer than NMETHODS bytes remain | `socks: truncated methods` |
| `choice_parse` | fewer than 2 bytes | `socks: truncated choice` |
| `choice_parse` | `VER != 5` | `socks: bad version` |
| `request_build`, `reply_build` | CMD not 0x01..0x03 | `socks: unknown command` |
| `request_build`, `reply_build` | REP not 0x00..0x08 | `socks: unknown reply code` |
| `*_build`, `*_parse` (request/reply) | ATYP not 1/3/4 | `socks: unknown address type` |
| `*_build` (request/reply) | ATYP 1 and `addr.len() != 4` | `socks: bad IPv4 length` |
| `*_build` (request/reply) | ATYP 4 and `addr.len() != 16` | `socks: bad IPv6 length` |
| `*_build`, `*_parse` (request/reply) | ATYP 3 and address length 0 | `socks: empty domain` |
| `*_build` (request/reply) | ATYP 3 and `addr.len() > 255` | `socks: domain too long` |
| `*_build` (request/reply) | port < 0 or > 65535 | `socks: port out of range` |
| `request_parse` | fewer than 4 bytes | `socks: truncated request` |
| `request_parse` | `VER != 5` | `socks: bad version` |
| `request_parse` | `RSV != 0` | `socks: bad reserved byte` |
| `request_parse` | address does not fit | `socks: truncated address` |
| `request_parse` | fewer than 2 port bytes remain | `socks: truncated port` |
| `reply_parse` | fewer than 4 bytes | `socks: truncated reply` |
| `reply_parse` | `VER != 5` | `socks: bad version` |
| `reply_parse` | REP not 0x00..0x08 | `socks: unknown reply code` |
| `reply_parse` | `RSV != 0` | `socks: bad reserved byte` |
| `reply_parse` | address does not fit | `socks: truncated address` |
| `reply_parse` | fewer than 2 port bytes remain | `socks: truncated port` |
| `auth_build` | `uname.len() == 0` | `socks: empty username` |
| `auth_build` | `uname.len() > 255` | `socks: username too long` |
| `auth_build` | `passwd.len() > 255` | `socks: password too long` |
| `auth_parse` | fewer than 2 bytes | `socks: truncated auth request` |
| `auth_parse` | `VER != 1` | `socks: bad auth version` |
| `auth_parse` | `ULEN == 0` | `socks: empty username` |
| `auth_parse` | username does not fit | `socks: truncated username` |
| `auth_parse` | PLEN byte or password bytes missing | `socks: truncated password` |
| `auth_reply_build` | status < 0 or > 255 | `socks: status out of range` |
| `auth_reply_parse` | fewer than 2 bytes | `socks: truncated auth reply` |
| `auth_reply_parse` | `VER != 1` | `socks: bad auth version` |

Check order is fixed and first-failure-wins; the request/reply builders
check CMD/REP first, then ATYP + address, then PORT, and within the address
the ATYP is checked before its length. Parsers check in wire order
(fixed header, version, command/reply, reserved byte, address type,
address bytes, port), except that for a domain the length byte is read and
validated before the name bytes.

## Complexity

| Operation | Complexity |
|---|---|
| `socks5_greeting_build` | O(methods.len()) |
| `socks5_greeting_parse` | O(NMETHODS) |
| `socks5_choice_build` / `socks5_choice_parse` | O(1) |
| `socks5_request_build` / `socks5_reply_build` | O(addr.len()) |
| `socks5_request_parse` / `socks5_reply_parse` | O(addr bytes) |
| `socks5_auth_build` / `socks5_auth_parse` | O(credential bytes) |
| `socks5_auth_reply_build` / `socks5_auth_reply_parse` | O(1) |
| `socks5_domain_bytes` | O(name.len()) |

No function allocates more than the message it returns; parsers copy only
the address/credential bytes into fresh `Vec[UInt8]` values (no borrowing
of `data`).

## Test plan

`tests/test_conformance.xi` (`module socks_tests`, 18 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. `greeting build writes VER, NMETHODS and METHODS` -- exact bytes
   (`05 03 00 01 02`, `05 01 FF`, `05 00`).
2. `greeting parse reads methods and ignores trailing bytes` -- pinned
   values 0/1/2, method `0xFF`, empty list, a trailing byte.
3. `255 methods round-trip; 256 methods and 256/-1 are Err` -- maximum
   NMETHODS, `too many methods`, `method out of range`, untouched output.
4. `greeting errors: truncation and bad version are Err` -- `05`, empty
   buffer, `04`, short METHODS, exact 2-method list accepted.
5. `method selection: 0x00/0x02/0xFF parse; bad version and range are Err`
   -- including trailing bytes accepted and `256/-1` build errors.
6. `CONNECT request build writes exact IPv4 bytes (ports 0 and 65535)` --
   exact `05 01 00 01 C0 A8 00 01 00 50`, port 0, CMD 3 + port 65535.
7. `CONNECT request parse pins cmd/atyp/addr/port`.
8. `domain request round-trips at 11 and 255 bytes` -- length prefix,
   maximum domain, exact size 18/262.
9. `IPv6 request round-trips 16 high-bit address bytes` -- `fe80::1`,
   port 65535.
10. `request parse errors: version, cmd, RSV, atyp, truncation, empty
    domain` -- every request error message, plus trailing bytes ignored.
11. `request build errors are atomic and reported in check order` -- bad
    lengths, oversized domain, port range, precedence checks.
12. `reply build/parse pins REP, ATYP, BND.ADDR and BND.PORT` -- exact
    `05 00 00 01 0A 00 00 01 04 38`.
13. `all REP codes 0x00..0x08 round-trip; 0x09/0xFF and -1 are Err`.
14. `reply errors are Err; a domain reply round-trips` -- version, RSV,
    atyp, truncations, empty domain, domain reply bytes.
15. `auth request round-trips, including empty password and 255-byte
    fields` -- exact `01 04 "user" 04 "pass"`, empty password, 513-byte
    maximum message.
16. `auth request errors: version, empty/truncated fields, oversized
    credentials`.
17. `auth status reply: 0/1/255 round-trip; bad version and status are
    Err`.
18. `round-trip matrix: IPv4, IPv6 and domain survive request and reply` --
    all three address types in both directions plus high-bit byte checks.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.socks
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Message codec only: no sockets, DNS, timers, retries, BIND/UDP
  association flows, SOCKS4 or GSSAPI.
- CMD `0x02`/`0x03` are parsed and built structurally; the package defines
  no semantics for them.
- Parsers decode the first message in the buffer and ignore trailing
  bytes; stream framing is the caller's responsibility.
- `NMETHODS = 0` is accepted (documented degenerate greeting); an empty
  RFC 1929 username is rejected while an empty password is accepted (both
  are strictness choices, not RFC requirements).
- Address and credential bytes are opaque: no UTF-8 validation, textual
  address formatting or parsing, and no credential checking.
- Reply codes `0x09..0xFF` and CMD values outside `0x01..0x03` are
  rejected; any METHOD byte and any AUTH status byte are accepted.
- All types are plain values; there is no shared state and no locking.

## Compiler / stdlib notes for v0.61.3

- Free functions only; no self methods, no `Vec[StructType]` and no
  table-driven dispatch (test functions are called directly).
- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_greeting`/`_err_greeting`, `_ok_choice`/`_err_choice`,
  `_ok_request`/`_err_request`, `_ok_reply`/`_err_reply`,
  `_ok_userpass`/`_err_userpass`, `_ok_auth_reply`/`_err_auth_reply` and
  `_ok_unit`/`_err_unit` (constructing Results inside other functions
  miscompiles in this compiler).
- Every `Vec[UInt8]` byte read is widened with `(data[pos] as Int) & 0xFF`
  before entering Int arithmetic; no byte is compared to an
  `Int >= 128` without widening.
- Vec elements are bound to typed locals (`let m: Int = methods[i]`,
  `let a: Vec[UInt8] = q.addr`) before use; `&struct.field` is never passed
  as a `&Vec[UInt8]` argument (that lowers to an empty vector).
- Str values in the tests are compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a Str read from a
  `Vec` lowers to a pointer comparison).
- The package declares no `extern "C"` blocks (no FFI); `xiom.string` is
  only used for `byte_at` in `socks5_domain_bytes`.
