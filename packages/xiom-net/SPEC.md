# xiom-net Specification

## Package

- **Name:** `xiom-net`
- **Version:** `0.2.0`
- **Module:** `xiom.net` (submodules: `.types`, `.tcp`, `.udp`, `.dns`, `.demo`)
- **Dependencies:** None (Layer 3 -- type definitions + FFI-backed socket operations)
- **FFI Backends:** Winsock2 (Windows), POSIX sockets (Linux/macOS/BSD)

## Architecture

```
Layer 3 (This Package): Type definitions + FFI-backed socket operations
    v depends on
Layer 2 (Implemented): OS FFI bindings via extern "C" (Winsock2 / POSIX sockets)
    v depends on
Layer 1 (Platform): C runtime + libc (Linux/macOS) or ws2_32.lib (Windows)
```

All networking functions that require OS interaction are now implemented with real
`extern "C"` FFI calls in `unsafe` blocks. The type system and pure-data
constructors/parsers remain fully implemented in `xiom.net.types`.

---

## Platform & Build Requirements

### Windows (Winsock2)

The TCP and UDP modules use Winsock2 functions declared via `extern "C"`:
- `socket`, `connect`, `bind`, `listen`, `accept`, `send`, `recv`, `sendto`, `recvfrom`
- `closesocket`, `shutdown`, `WSAGetLastError`, `WSAStartup`, `WSACleanup`

**Linker requirement:** Link against `ws2_32.lib` (Ws2_32.dll).

**WSAStartup lifecycle:** The first call to any socket function triggers `WSAStartup(2.2, ...)`.
A static `wsa_initialized` flag prevents duplicate initialization. Call `wsa_cleanup()`
before process exit to release Winsock resources.

```c
/* XIOM runtime must link: */
/* Windows: -lWs2_32   (linker flag) */
#pragma comment(lib, "Ws2_32.lib")
```

### POSIX (Linux / macOS / BSD)

The same `extern "C"` function signatures map to POSIX socket calls:
- `socket`, `connect`, `bind`, `listen`, `accept`, `send`, `recv`, `sendto`, `recvfrom`
- `close` (mapped from `closesocket`), `shutdown`

**Linker requirement:** Link against `libc` (default on POSIX). No additional libraries needed.

On POSIX, the following FFI name mappings apply at link time:
| XIOM extern symbol | Windows (ws2_32) | POSIX (libc) |
|---|---|---|
| `closesocket` | `closesocket` | `close` |
| `WSAGetLastError` | `WSAGetLastError` | `errno` (int) |
| `WSAStartup` | `WSAStartup` | no-op (return 0) |
| `WSACleanup` | `WSACleanup` | no-op |
| `INVALID_SOCKET` | `~0` (`-1`) | `-1` |
| `SOCKET_ERROR` | `-1` | `-1` |

The XIOM runtime shim on POSIX should provide thin wrappers:
```c
/* posix_shim.c -- stub out Winsock-only functions on POSIX */
int WSAGetLastError(void) { return errno; }
int WSAStartup(int version, void *data) { return 0; }
int WSACleanup(void) { return 0; }
int closesocket(int fd) { return close(fd); }
```

---

## Module: `xiom.net.types`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `IpAddr` | `octets: Vec[Int]`, `version: Int` | IP address. `version=4` -> 4 octets (IPv4). `version=6` -> 16 octets (IPv6). |
| `SocketAddr` | `ip: IpAddr`, `port: Int` | IP + port endpoint. Port range: 0-65535. |
| `IpVersion` | enum: `V4`, `V6` | Discriminated IP version tag. |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `AF_INET` | `2` | IPv4 address family |
| `SOCK_STREAM` | `1` | TCP socket type |
| `SOCK_DGRAM` | `2` | UDP socket type |
| `INADDR_ANY` | `0` | Wildcard bind address |
| `INVALID_SOCKET` | `-1` | Failed socket() sentinel |
| `SOCKET_ERROR` | `-1` | Failed operation sentinel |
| `SOMAXCONN` | `128` | Default listen backlog |

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
| `build_sockaddr_in` | `(addr: &SocketAddr) -> Vec[Int]` | **Implemented** -- builds 16-byte `sockaddr_in` binary |
| `build_sockaddr_in_any` | `(port: Int) -> Vec[Int]` | **Implemented** -- builds `sockaddr_in` for `0.0.0.0:<port>` |
| `parse_sockaddr_in` | `(raw: &Vec[Int]) -> Result[SocketAddr, Str]` | **Implemented** -- parses 16-byte `sockaddr_in` back to XIOM types |
| `ws_error_to_str` | `(code: Int) -> Str` | **Implemented** -- maps Winsock error codes to human-readable strings |

#### sockaddr_in Binary Layout (16 bytes)

```
Offset  Size  Field         Endianness
0       2     sin_family     little-endian (AF_INET = 0x0002)
2       2     sin_port       big-endian (network byte order, htons)
4       4     sin_addr       big-endian (network byte order, 4 octets)
8       8     sin_zero       zero-padded
```

#### IPv4 String Format

Accepts and produces standard dotted-quad notation (`"192.168.1.1"`). Each octet
must be in range 0-255. Leading zeros are accepted numerically (e.g. `"001"` -> 1).

#### IPv6 Encoding

Stored as 16 octets in network byte order. The constructor `ipv6_from_parts`
accepts 8 x 16-bit hextets, each split into high/low bytes.

---

## Module: `xiom.net.tcp`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `TcpStream` | `fd: Int`, `connected: Bool`, `remote: SocketAddr` | Connected TCP socket. `fd=-1` when uninitialized. |
| `TcpListener` | `fd: Int`, `bound: Bool`, `addr: SocketAddr` | Listening TCP socket. `fd=-1` when uninitialized. |

### Socket Lifecycle

```
Server:                       Client:
  tcp_listen(addr)              tcp_connect(addr)           [FFI: socket + connect]
    -> TcpListener (bound)         -> TcpStream (connected)
    -> tcp_accept()              tcp_read / tcp_write        [FFI: recv / send]
      -> TcpStream (new)         tcp_close()                 [FFI: shutdown + closesocket]
      -> tcp_read / tcp_write
    -> tcp_listener_close()
```

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `tcp_connect` | `(addr: SocketAddr) -> Result[TcpStream, Str]` | **Implemented** -- `socket(AF_INET,SOCK_STREAM)` + `connect()` |
| `tcp_listen` | `(addr: SocketAddr) -> Result[TcpListener, Str]` | **Implemented** -- `socket()` + `bind()` + `listen()` |
| `tcp_accept` | `(listener: &mut TcpListener) -> Result[TcpStream, Str]` | **Implemented** -- `accept()` |
| `tcp_read` | `(stream: &mut TcpStream, buf: &mut Vec[Int]) -> Result[Int, Str]` | **Implemented** -- `recv()` |
| `tcp_write` | `(stream: &mut TcpStream, data: &Vec[Int]) -> Result[Int, Str]` | **Implemented** -- `send()` |
| `tcp_close` | `(stream: TcpStream)` | **Implemented** -- `shutdown(fd, SD_BOTH)` + `closesocket(fd)` |
| `tcp_listener_close` | `(listener: TcpListener)` | **Implemented** -- `closesocket(fd)` |
| `tcp_is_connected` | `(stream: &TcpStream) -> Bool` | **Implemented** -- field access |
| `tcp_remote_addr` | `(stream: &TcpStream) -> SocketAddr` | **Implemented** -- field access |
| `wsa_cleanup` | `() -> ()` | **Implemented** -- calls `WSACleanup()`, releases Winsock resources |

### FFI Dependencies (`extern "C"`)

```
socket, connect, bind, listen, accept, send, recv,
closesocket, shutdown, WSAGetLastError, WSAStartup, WSACleanup
```

### Read/Write Semantics

- `tcp_read` returns the number of bytes read (0 = connection closed by peer). Sets `stream.connected = false` on EOF.
- `tcp_write` returns the number of bytes written.
- Both use `Vec[Int]` as byte buffers (`Int` values in range 0-255).
- On error, returns `Err(Str)` with the Winsock error description (e.g., `"connection refused"`, `"connection reset"`).

---

## Module: `xiom.net.udp`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `UdpSocket` | `fd: Int`, `bound: Bool` | UDP socket. `fd=-1` when uninitialized. |

### Socket Lifecycle

```
  udp_bind(addr)
    -> UdpSocket (bound)           [FFI: socket(AF_INET,SOCK_DGRAM) + bind]
    -> loop { udp_recv_from() / udp_send_to() }
    -> udp_close()                 [FFI: closesocket]
```

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `udp_bind` | `(addr: SocketAddr) -> Result[UdpSocket, Str]` | **Implemented** -- `socket(AF_INET,SOCK_DGRAM)` + `bind()` |
| `udp_send_to` | `(socket: &UdpSocket, data: &Vec[Int], addr: SocketAddr) -> Result[Int, Str]` | **Implemented** -- `sendto()` |
| `udp_recv_from` | `(socket: &UdpSocket, buf: &mut Vec[Int]) -> Result[(Int, SocketAddr), Str]` | **Implemented** -- `recvfrom()` |
| `udp_close` | `(socket: UdpSocket)` | **Implemented** -- `closesocket()` |

### FFI Dependencies (`extern "C"`)

```
socket, bind, sendto, recvfrom, closesocket,
WSAGetLastError, WSAStartup, WSACleanup
```

### recv_from Return

Returns a tuple `(bytes_read, source_addr)` where:
- `bytes_read: Int` -- number of bytes written into `buf`
- `source_addr: SocketAddr` -- the sender's address (parsed from `sockaddr_in`)

---

## Module: `xiom.net.dns`

### Types

| Type | Fields | Description |
|------|--------|-------------|
| `DnsResult` | `hostname: Str`, `addresses: Vec[IpAddr]` | DNS lookup result. |

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `dns_resolve` | `(hostname: Str) -> Result[DnsResult, Str]` | **Stub** -- needs OS `getaddrinfo()` |
| `dns_reverse` | `(ip: IpAddr) -> Result[Str, Str]` | **Stub** -- needs OS `getnameinfo()` |

### DNS Behavior (Layer 2 will implement)

- `dns_resolve("example.com")` -> `Ok(DnsResult{ hostname: "example.com", addresses: [...] })`
- `dns_reverse(ip)` -> `Ok("host.example.com")`
- Both may return multiple addresses (A + AAAA records).
- Errors: `NXDOMAIN` -> `Err("hostname not found")`, network failure -> `Err("DNS query failed")`.

---

## Module: `xiom.net.demo`

### Function API

| Function | Signature | Status |
|----------|-----------|--------|
| `demo_http_request` | `() -> Result[Unit, Str]` | **Implemented** -- raw HTTP GET to example.com:80 via TCP |
| `demo_echo_server` | `() -> Result[Unit, Str]` | **Implemented** -- echo server on 127.0.0.1:8080 |

### demo_http_request Flow

```
resolve_host("example.com")          [DNS stub; falls back to hardcoded IP]
  -> tcp_connect(ip, 80)              [FFI: socket + connect]
  -> tcp_write("GET / HTTP/1.0\r\n...")  [FFI: send]
  -> loop { tcp_read(buf) }           [FFI: recv]
  -> tcp_close(stream)                [FFI: shutdown + closesocket]
```

### demo_echo_server Flow

```
tcp_listen(127.0.0.1:8080)           [FFI: socket + bind + listen]
  -> tcp_accept(listener)             [FFI: accept]
  -> tcp_read(client, buf)            [FFI: recv]
  -> tcp_write(client, buf)           [FFI: send] (echo back)
  -> tcp_close(client)                [FFI: shutdown + closesocket]
  -> tcp_listener_close(listener)     [FFI: closesocket]
```

---

## Error Conventions

All FFI-dependent functions return `Result<T, Str>` where:
- `Ok(value)` on success
- `Err("...")` with a descriptive message on failure

Socket errors are obtained via `WSAGetLastError()` (Windows) or `errno` (POSIX) and
mapped to human-readable strings via `ws_error_to_str()`. Error codes follow the
standard Winsock error numbering:

| Code | Meaning |
|------|---------|
| 10013 | Permission denied |
| 10048 | Address in use |
| 10049 | Address not available |
| 10051 | Network unreachable |
| 10054 | Connection reset by peer |
| 10060 | Connection timed out |
| 10061 | Connection refused |
| 10093 | WSAStartup not called |

---

## Usage Examples

### TCP Client (HTTP GET)
```
var ip = ipv4(93, 184, 216, 34);
var addr = socket_addr(ip, 80);
var stream = tcp_connect(addr);
match stream {
  Ok(s) => {
    var req = str_to_bytes("GET / HTTP/1.0\r\nHost: example.com\r\n\r\n");
    var _written = tcp_write(&mut s, &req);
    var buf = ...;
    var _read = tcp_read(&mut s, &mut buf);
    tcp_close(s);
  },
  Err(msg) => { ... },
}
```

### TCP Server (Echo)
```
var addr = socket_addr(ipv4(127, 0, 0, 1), 8080);
var listener = tcp_listen(addr);
match listener {
  Ok(l) => {
    var client = tcp_accept(&mut l);
    var buf = ...;
    var n = tcp_read(&mut client, &mut buf);
    var _written = tcp_write(&mut client, &buf);
    tcp_close(client);
    tcp_listener_close(l);
  },
  Err(msg) => { ... },
}
```

### UDP
```
var addr = socket_addr(ipv4(0, 0, 0, 0), 9999);
var socket = udp_bind(addr);
match socket {
  Ok(s) => {
    var buf = ...;
    var result = udp_recv_from(&s, &mut buf);
    match result {
      Ok((n, src)) => {
        var _sent = udp_send_to(&s, &buf, src);
      },
      Err(msg) => { ... },
    }
    udp_close(s);
  },
  Err(msg) => { ... },
}
```

### Type Construction & Parsing
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
