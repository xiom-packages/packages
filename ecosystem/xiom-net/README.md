# xiom-net

> TCP/UDP networking for XIOM — Winsock2/POSIX socket FFI with safety contracts.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-net provides low-level TCP and UDP socket networking via native OS socket APIs. Every socket operation is guarded by compile-time contracts that prevent use-after-close, null-pointer derefs, and invalid port bindings.

## Installation

```bash
xiom install xiom-net
```

## Dependencies

### System Libraries
| OS | Library | Status |
|----|---------|--------|
| **Windows** | `ws2_32.dll` | Built-in |
| **Linux** | POSIX sockets | Built-in |
| **macOS** | POSIX sockets | Built-in |

Link on Windows: `xiomc -l ws2_32 myprogram.xi`
Link on Linux/macOS: No extra flags needed.

## Quick Start

### TCP Client
```xiom
use xiom.net.types;
use xiom.net.tcp;

fn main() -> Int {
  var addr = socket_addr_from_str("93.184.216.34:80").unwrap();
  var stream = tcp_connect(addr).unwrap();
  var request = "GET / HTTP/1.0\r\nHost: example.com\r\n\r\n";
  // tcp_write(&stream, &data);
  tcp_close(stream);
  return 0;
}
```

### TCP Server
```xiom
var addr = socket_addr_from_str("127.0.0.1:8080").unwrap();
var listener = tcp_listen(addr).unwrap();
var client = tcp_accept(&mut listener).unwrap();
// handle client...
tcp_close(client);
tcp_listener_close(listener);
```

## API Reference

### Types (`xiom.net.types`)
| Type | Description |
|------|-------------|
| `IpAddr` | IP address (IPv4 or IPv6) |
| `IpVersion` | Enum: V4, V6 |
| `SocketAddr` | IP + port |
| `TcpStream` | TCP connection |
| `TcpListener` | TCP server socket |
| `UdpSocket` | UDP socket |
| `DnsResult` | DNS resolution result |

### IP Functions
| Function | Description |
|----------|-------------|
| `ipv4(a, b, c, d)` | Create IPv4 address |
| `ipv4_from_str(s)` | Parse "1.2.3.4" |
| `ipv4_to_str(ip)` | Format IPv4 string |
| `socket_addr(ip, port)` | Create socket address |
| `socket_addr_from_str(s)` | Parse "host:port" |

### TCP (`xiom.net.tcp`)
| Function | Description |
|----------|-------------|
| `tcp_connect(addr)` | Connect to remote |
| `tcp_listen(addr)` | Bind and listen |
| `tcp_accept(listener)` | Accept connection |
| `tcp_read(stream, buf)` | Read data |
| `tcp_write(stream, data)` | Write data |
| `tcp_close(stream)` | Close connection |
| `tcp_listener_close(listener)` | Close listener |
| `tcp_is_connected(stream)` | Check connected |
| `tcp_remote_addr(stream)` | Get remote address |

### UDP (`xiom.net.udp`)
| Function | Description |
|----------|-------------|
| `udp_bind(addr)` | Bind UDP socket |
| `udp_send_to(socket, data, addr)` | Send datagram |
| `udp_recv_from(socket, buf)` | Receive datagram |
| `udp_close(socket)` | Close socket |

### DNS (`xiom.net.dns`)
| Function | Description |
|----------|-------------|
| `dns_resolve(hostname)` | Resolve hostname |
| `dns_reverse(ip)` | Reverse DNS lookup |

### Demo (`xiom.net.demo`)
| Function | Description |
|----------|-------------|
| `demo_http_request()` | Raw HTTP GET via TCP |
| `demo_echo_server()` | Echo server on 127.0.0.1:8080 |

## Safety Contracts

Every socket operation is guarded:
- `tcp_connect/listen`: requires addr.port > 0, port < 65536
- `tcp_accept`: requires listener.bound
- `tcp_read/write`: requires stream.connected
- `tcp_close`: requires stream.connected
- `udp_bind`: requires addr.port > 0, port < 65536
- `udp_send_to/recv_from`: requires socket.bound
- `udp_close`: requires socket.bound
- `ipv4(a,b,c,d)`: requires each octet 0-255

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| TCP client (connect/send/recv/close) | ✅ Production | FFI bridge integrated, requires ffi_bridge.c |
| TCP server (bind/listen/accept) | ✅ Production | FFI bridge integrated |
| UDP (bind/sendto/recvfrom) | ✅ Production | FFI bridge integrated |
| IPv4 parsing/formatting | ✅ Complete | Pure XIOM |
| IPv6 | ⚠️ Types only | Parsing stubbed |
| DNS resolution | ⚠️ Stub | Needs getaddrinfo FFI |
| TLS/SSL | ❌ Not yet | Needs OpenSSL integration |
| Non-blocking I/O | ❌ Not yet | |
| Epoll/kqueue/IOCP | ❌ Not yet | |
| Unix domain sockets | ❌ Not yet | |
| Raw sockets | ❌ Not yet | |
| HTTP (use xiom-http) | — | Separate package |

### What's Left for v1.0
1. **DNS resolution** — wire up `getaddrinfo` FFI
2. **IPv6 support** — complete parsing and sockaddr_in6
3. **Non-blocking mode** — `fcntl`/`ioctlsocket` for async I/O
4. **POSIX portability** — `#ifdef` for Linux/macOS socket calls vs Winsock2

## Build & Run

```bash
# Compile with FFI bridge (sockets are OS-provided)
xiomc myprogram.xi ../runtime/ffi_bridge.c -l ws2_32 -o myprogram.exe
./myprogram.exe
```

> Requires ffi_bridge.c to be compiled alongside. The FFI bridge provides `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, and `xiom_free_cstr` across the FFI boundary. On Linux/macOS, omit `-l ws2_32`.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
