# xiom-net Specification

## Package

- **Name:** `xiom-net`
- **Version:** `0.1.0`
- **Module:** `xiom.net` (submodules: `.types`, `.tcp`, `.udp`, `.dns`)
- **Dependencies:** None (Layer 3.1 — pure type definitions with stubs)

## Architecture

```
Layer 3 (This Package): Type definitions + stub APIs
    ↓ depends on
Layer 2 (Not yet implemented): OS FFI bindings (BSD sockets, platform resolver)
```

All networking functions that require OS interaction return `Err(Str)` with an
explanatory message. The type system and pure-data constructors/parsers are
fully implemented. Layer 2 will replace stub bodies with actual FFI calls.

---

## Module: `xiom.net.types`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `IpAddr` | `octets: Vec[Int]`, `version: Int` | IP address. `version=4` → 4 octets (IPv4). `version=6` → 16 octets (IPv6). |
| `SocketAddr` | `ip: IpAddr`, `port: Int` | IP + port endpoint. Port range: 0–65535. |
| `IpVersion` | enum: `V4`, `V6` | Discriminated IP version tag. |

### Functions

| Function | Signature | Status |
|----------|-----------|--------|
| `ipv4` | `(a, b, c, d: Int) -> IpAddr` | **Implemented** |
| `ipv6_from_parts` | `(a..h: Int) -> IpAddr` | **Implemented** |
| `ipv4_from_str` | `(s: Str) -> Result[IpAddr, Str]` | **Implemented** |
| `ipv4_to_str` | `(ip: &IpAddr) -> Str` | **Implemented** |
| `socket_addr` | `(ip: IpAddr, port: Int) -> SocketAddr` | **Implemented** |
| `socket_addr_from_str` | `(s: Str) -> Result[SocketAddr, Str]` | **Implemented** |
| `IpAddr.is_v4` | `() -> Bool` | **Implemented** |
| `IpAddr.is_v6` | `() -> Bool` | **Implemented** |

#### IPv4 String Format

Accepts and produces standard dotted-quad notation (`"192.168.1.1"`). Each octet
must be in range 0–255. Leading zeros are accepted numerically (e.g. `"001"` → 1).

#### IPv6 Encoding

Stored as 16 octets in network byte order. The constructor `ipv6_from_parts`
accepts 8 × 16-bit hextets, each split into high/low bytes.

---

## Module: `xiom.net.tcp`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `TcpStream` | `fd: Int`, `connected: Bool`, `remote: SocketAddr` | Connected TCP socket. `fd=-1` when uninitialized. |
| `TcpListener` | `fd: Int`, `bound: Bool`, `addr: SocketAddr` | Listening TCP socket. `fd=-1` when uninitialized. |

### TCP Socket Lifecycle (Layer 2 will implement this)

```
Server:                       Client:
  tcp_listen(addr)              tcp_connect(addr)
    → TcpListener (bound)         → TcpStream (connected)
    → tcp_accept()
      → TcpStream (new)           tcp_read / tcp_write
      → tcp_read / tcp_write      tcp_close()
    → tcp_listener_close()
```

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `tcp_connect` | `(addr: SocketAddr) -> Result[TcpStream, Str]` | **Stub** — needs OS `socket()` + `connect()` |
| `tcp_listen` | `(addr: SocketAddr) -> Result[TcpListener, Str]` | **Stub** — needs OS `socket()` + `bind()` + `listen()` |
| `tcp_accept` | `(listener: &mut TcpListener) -> Result[TcpStream, Str]` | **Stub** — needs OS `accept()` |
| `tcp_read` | `(stream: &mut TcpStream, buf: &mut Vec[Int]) -> Result[Int, Str]` | **Stub** — needs OS `recv()` or `read()` |
| `tcp_write` | `(stream: &mut TcpStream, data: &Vec[Int]) -> Result[Int, Str]` | **Stub** — needs OS `send()` or `write()` |
| `tcp_close` | `(stream: TcpStream)` | **Stub** — consumes stream, will call OS `close()` |
| `tcp_listener_close` | `(listener: TcpListener)` | **Stub** — consumes listener, will call OS `close()` |
| `tcp_is_connected` | `(stream: &TcpStream) -> Bool` | **Implemented** — field access |
| `tcp_remote_addr` | `(stream: &TcpStream) -> SocketAddr` | **Implemented** — field access |

### Read/Write Semantics

- `tcp_read` returns the number of bytes read (0 = connection closed by peer).
- `tcp_write` returns the number of bytes written.
- Both use `Vec[Int]` as byte buffers (`Int` values in range 0–255).

---

## Module: `xiom.net.udp`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `UdpSocket` | `fd: Int`, `bound: Bool` | UDP socket. `fd=-1` when uninitialized. |

### UDP Socket Lifecycle (Layer 2 will implement this)

```
  udp_bind(addr)
    → UdpSocket (bound)
    → loop { udp_recv_from() / udp_send_to() }
    → udp_close()
```

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `udp_bind` | `(addr: SocketAddr) -> Result[UdpSocket, Str]` | **Stub** — needs OS `socket()` + `bind()` |
| `udp_send_to` | `(socket: &UdpSocket, data: &Vec[Int], addr: SocketAddr) -> Result[Int, Str]` | **Stub** — needs OS `sendto()` |
| `udp_recv_from` | `(socket: &UdpSocket, buf: &mut Vec[Int]) -> Result[(Int, SocketAddr), Str]` | **Stub** — needs OS `recvfrom()` |
| `udp_close` | `(socket: UdpSocket)` | **Stub** — consumes socket, will call OS `close()` |

### recv_from Return

Returns a tuple `(bytes_read, source_addr)` where:
- `bytes_read: Int` — number of bytes written into `buf`
- `source_addr: SocketAddr` — the sender's address

---

## Module: `xiom.net.dns`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `DnsResult` | `hostname: Str`, `addresses: Vec[IpAddr]` | DNS lookup result. |

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `dns_resolve` | `(hostname: Str) -> Result[DnsResult, Str]` | **Stub** — needs OS `getaddrinfo()` |
| `dns_reverse` | `(ip: IpAddr) -> Result[Str, Str]` | **Stub** — needs OS `getnameinfo()` |

### DNS Behavior (Layer 2 will implement)

- `dns_resolve("example.com")` → `Ok(DnsResult{ hostname: "example.com", addresses: [...] })`
- `dns_reverse(ip)` → `Ok("host.example.com")`
- Both may return multiple addresses (A + AAAA records).
- Errors: `NXDOMAIN` → `Err("hostname not found")`, network failure → `Err("DNS query failed")`.

---

## Layer 2 FFI Requirements

The following platform API calls are needed for full implementation:

| XIOM Function | POSIX | Windows (WinSock2) |
|---------------|-------|---------------------|
| `tcp_connect` | `socket(AF_INET, SOCK_STREAM)` + `connect()` | `socket(AF_INET, SOCK_STREAM)` + `connect()` |
| `tcp_listen` | `socket()` + `bind()` + `listen()` | `socket()` + `bind()` + `listen()` |
| `tcp_accept` | `accept()` | `accept()` |
| `tcp_read` | `recv()` or `read()` | `recv()` |
| `tcp_write` | `send()` or `write()` | `send()` |
| `tcp_close` | `close()` or `shutdown()` | `closesocket()` |
| `udp_bind` | `socket(AF_INET, SOCK_DGRAM)` + `bind()` | `socket(AF_INET, SOCK_DGRAM)` + `bind()` |
| `udp_send_to` | `sendto()` | `sendto()` |
| `udp_recv_from` | `recvfrom()` | `recvfrom()` |
| `udp_close` | `close()` | `closesocket()` |
| `dns_resolve` | `getaddrinfo()` | `getaddrinfo()` |
| `dns_reverse` | `getnameinfo()` | `getnameinfo()` |

### Socket Address Translation

Layer 2 must convert between `xiom.net.SocketAddr` and platform `sockaddr_in` /
`sockaddr_in6` structures. The `IpAddr.octets` vector maps directly to
`sin_addr.s_addr` (IPv4, 4 bytes) or `sin6_addr.s6_addr` (IPv6, 16 bytes).
Port is stored in host byte order and converted to network byte order (`htons`).

---

## Error Conventions

All FFI-dependent functions return `Result<T, Str>` where:
- `Ok(value)` on success
- `Err("...")` with a descriptive message on failure

Layer 2 will wrap OS errno values into string descriptions (e.g.,
`"connection refused"`, `"address in use"`, `"network unreachable"`).

## Usage Examples

```
var addr = ipv4(127, 0, 0, 1);
var sock = socket_addr(addr, 8080);
var endpoint = socket_addr_from_str("192.168.1.1:443");
match endpoint {
  Ok(sa) => { ... },
  Err(msg) => { ... },
}

var ip = ipv4_from_str("10.0.0.1");
match ip {
  Ok(addr) => {
    if addr.is_v4() {
      var s = ipv4_to_str(&addr);
    }
  },
  Err(msg) => { ... },
}
```
