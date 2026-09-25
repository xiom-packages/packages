# xiom.socks

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI) SOCKS5 wire codec for the RFC 1928 greeting,
> method selection, CONNECT request/reply and the RFC 1929
> username/password sub-negotiation. Bytes in, structs out -- no sockets.
> **Deps:** `xiom.std` only. The library module imports `xiom.string` (for
> `socks5_domain_bytes`); the tests use `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.socks` encodes and decodes the SOCKS5 messages a CONNECT client and
server exchange, and nothing else. It never opens a socket, resolves a name
or dials an address: every function takes or returns `Vec[UInt8]` and plain
value structs, so the caller owns the transport, the framing and the
timeouts.

A successful CONNECT negotiation is five messages:

```
client                                                server
  |-- greeting        VER NMETHODS METHODS ----------->|
  |<-- selection      VER METHOD ----------------------|
  |    (METHOD 0xFF = no acceptable methods)          |
  |-- auth (RFC 1929) VER=1 ULEN UNAME PLEN PASSWD -->|   only when METHOD = 0x02
  |<-- auth status    VER=1 STATUS ------------------|
  |-- request         VER CMD RSV ATYP ADDR PORT ---->|
  |<-- reply           VER REP RSV ATYP BND.ADDR BND.PORT |
```

All three address forms are supported everywhere an address appears:
ATYP `0x01` (IPv4, 4 bytes), `0x03` (domain, length-prefixed on the wire)
and `0x04` (IPv6, 16 bytes). Parsers validate the version, the reserved
byte, the command/reply code, the address type and length, and every
truncation shape, with stable `Err(Str)` messages (see `SPEC.md`).

## API

| Function | Returns | Description |
|---|---|---|
| `socks5_greeting_build(out, methods)` | `Result[Unit, Str]` | Append `VER NMETHODS METHODS`. |
| `socks5_greeting_parse(data)` | `Result[Socks5Greeting, Str]` | Parse a greeting; `methods` are `Int` 0..255. |
| `socks5_choice_build(out, method)` | `Result[Unit, Str]` | Append `VER METHOD` (0xFF allowed). |
| `socks5_choice_parse(data)` | `Result[Socks5Choice, Str]` | Parse a method selection. |
| `socks5_request_build(out, cmd, atyp, addr, port)` | `Result[Unit, Str]` | Append a CONNECT/BIND/UDP request. |
| `socks5_request_parse(data)` | `Result[Socks5Request, Str]` | Parse a request. |
| `socks5_reply_build(out, rep, atyp, addr, port)` | `Result[Unit, Str]` | Append a reply (REP 0x00..0x08). |
| `socks5_reply_parse(data)` | `Result[Socks5Reply, Str]` | Parse a reply. |
| `socks5_auth_build(out, uname, passwd)` | `Result[Unit, Str]` | Append an RFC 1929 credential request. |
| `socks5_auth_parse(data)` | `Result[Socks5UserPass, Str]` | Parse a credential request. |
| `socks5_auth_reply_build(out, status)` | `Result[Unit, Str]` | Append the RFC 1929 status reply. |
| `socks5_auth_reply_parse(data)` | `Result[Socks5AuthReply, Str]` | Parse the status reply. |
| `socks5_domain_bytes(name)` | `Vec[UInt8]` | Raw bytes of `name` for use as an ATYP `0x03` address. |

Parsed message types (fields are plain values):

| Type | Fields |
|---|---|
| `Socks5Greeting` | `methods: Vec[Int]` |
| `Socks5Choice` | `method: Int` |
| `Socks5Request` | `cmd: Int`, `atyp: Int`, `addr: Vec[UInt8]`, `port: Int` |
| `Socks5Reply` | `rep: Int`, `atyp: Int`, `addr: Vec[UInt8]`, `port: Int` |
| `Socks5UserPass` | `uname: Vec[UInt8]`, `passwd: Vec[UInt8]` |
| `Socks5AuthReply` | `status: Int` |

`addr` is always the raw address bytes: 4 for IPv4, 16 for IPv6, and the
domain name bytes **without** the on-the-wire length prefix.

Protocol constants are exposed: `SOCKS5_VERSION`, `AUTH_VERSION`,
`CMD_CONNECT`/`CMD_BIND`/`CMD_UDP_ASSOCIATE`, `ATYP_IPV4`/`ATYP_DOMAIN`/
`ATYP_IPV6`, `METHOD_NO_AUTH`/`METHOD_GSSAPI`/`METHOD_USERPASS`/
`METHOD_NO_ACCEPTABLE` and `REP_SUCCEEDED`..`REP_ADDRESS_TYPE_NOT_SUPPORTED`
(the nine reply codes 0x00..0x08).

## Usage

Build a CONNECT request for `example.com:443` and parse it back:

```xi
use xiom.socks;
use xiom.io;

let host = socks5_domain_bytes("example.com");
var req = Vec[UInt8].new();
socks5_request_build(&mut req, CMD_CONNECT, ATYP_DOMAIN, &host, 443);
// req bytes: 05 01 00 03 0B "example.com" 01 BB

let r = socks5_request_parse(&req);
match r {
  Ok(q) => {
    io.println("cmd=" + xiom.convert.int_to_string(q.cmd));   // 1
    let addr: Vec[UInt8] = q.addr;                            // raw name bytes
    io.println("addr bytes=" + xiom.convert.int_to_string(addr.len())); // 11
  },
  Err(e) => { io.println("bad request: " + e); },
}
```

Server side: offer no-auth or username/password and answer a CONNECT:

```xi
use xiom.socks;

// Greeting offer (client).
var methods = Vec[Int].new();
methods.push(METHOD_NO_AUTH);
methods.push(METHOD_USERPASS);
var greeting = Vec[UInt8].new();
socks5_greeting_build(&mut greeting, &methods);              // 05 02 00 02

// Method selection (server): pick username/password.
var selection = Vec[UInt8].new();
socks5_choice_build(&mut selection, METHOD_USERPASS);         // 05 02

// RFC 1929 credentials (client) and the status reply (server).
let user = socks5_domain_bytes("ada");    // raw ASCII bytes; any bytes work
let pass = socks5_domain_bytes("secret");
var auth = Vec[UInt8].new();
socks5_auth_build(&mut auth, &user, &pass);                   // 01 03 "ada" 06 "secret"
var ok = Vec[UInt8].new();
socks5_auth_reply_build(&mut ok, 0);                          // 01 00

// Success reply with a 0.0.0.0:0 bound address (server).
var bnd = Vec[UInt8].new();
bnd.push(0 as UInt8);
bnd.push(0 as UInt8);
bnd.push(0 as UInt8);
bnd.push(0 as UInt8);
var reply = Vec[UInt8].new();
socks5_reply_build(&mut reply, REP_SUCCEEDED, ATYP_IPV4, &bnd, 0);
```

## Error model

Every fallible function returns `Result[..., Str]` with a stable,
lowercase, `socks: `-prefixed message. Examples:

```
socks: bad version            socks: truncated request
socks: bad reserved byte      socks: truncated address
socks: unknown command        socks: empty domain
socks: unknown reply code     socks: domain too long
socks: bad IPv4 length        socks: unknown address type
socks: bad IPv6 length        socks: port out of range
socks: truncated greeting     socks: bad auth version
socks: truncated methods      socks: empty username
socks: truncated choice       socks: truncated username
socks: method out of range    socks: password too long
socks: too many methods       socks: status out of range
```

The full condition -> message table is in `SPEC.md`. Builders validate the
whole message before writing a single byte, so `out` is byte-for-byte
unchanged on `Err` (atomic failure). Parsers read the first message in the
buffer and ignore any bytes after it.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.socks
```

Expected: the namespace check passes, 18 `[PASS]` lines, and a final
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Message codec only.** No sockets, DNS, timers, retries, BIND or UDP
  ASSOCIATE association state machines, and no SOCKS4 or GSSAPI.
- **Structural CMD only.** `socks5_request_parse` returns CMD
  `0x01..0x03` but BIND and UDP ASSOCIATE payloads/flows are out of scope;
  the package itself only gives CONNECT meaning.
- **First message only.** Parsers accept a buffer holding more than one
  message and ignore the trailing bytes; framing is the caller's job.
- **Out-of-band address length.** An ATYP `0x03` address carries its length
  byte only on the wire; the `addr` field is the name bytes alone, so
  `addr.len()` must be 1..255 (rejected as `socks: empty domain` /
  `socks: domain too long` otherwise).
- **Deliberate strictness deviations:** a greeting with `NMETHODS = 0` is
  accepted (structurally parseable, but it offers nothing); an RFC 1929
  request with an empty username is rejected while an empty password is
  accepted.
- **Raw bytes.** Credentials and domains are not validated as UTF-8, and
  no textual address formatting/parsing is provided.
- Not thread-safe; all types are plain values with no shared state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
