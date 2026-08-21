# xiom-net Roadmap

## Current State -- v0.2.0

| Module | Status | Notes |
|--------|--------|-------|
| `xiom.net.types` | Complete | IPv4/IPv6 types, constructors, parsers, formatters, sockaddr_in binary encode/decode, Winsock error mapping |
| `xiom.net.tcp` | Production | socket/connect/bind/listen/accept/send/recv/shutdown/closesocket via Winsock2 FFI |
| `xiom.net.udp` | Production | socket/bind/sendto/recvfrom/closesocket via Winsock2 FFI |
| `xiom.net.dns` | Stub | dns_resolve and dns_reverse return Err -- need getaddrinfo/getnameinfo FFI |
| `xiom.net.demo` | Complete | HTTP GET demo + echo server demo |

### Contracts Coverage

- **21 public functions** across 5 modules
- **19 functions** guarded by `requires:` contracts (90%)
- Missing: `IpAddr.is_v4`, `IpAddr.is_v6` (accessors on valid instances), `ws_error_to_str` (pure mapping), `wsa_cleanup`, `tcp_is_connected` (accessor), `demo_http_request`, `demo_echo_server` (no-param entry points)

### Test Coverage

- **58 conformance tests** in `tests/test_conformance.xi`
- Covers: constants, constructors, parsers (valid + error paths), formatters, binary encode/decode, error codes, DNS stubs, TCP/UDP type introspection, enum matching

---

## v0.3.0 -- DNS Resolution

- [ ] Wire `getaddrinfo` FFI in `dns_resolve`
- [ ] Wire `getnameinfo` FFI in `dns_reverse`
- [ ] Support A (IPv4) and AAAA (IPv6) record parsing
- [ ] Add DNS-specific error codes (NXDOMAIN, SERVFAIL, timeout)
- [ ] Tests: resolve localhost, resolve known host, NXDOMAIN error path

## v0.4.0 -- IPv6 Completeness

- [ ] `ipv6_from_str` parser (colon-hex format, :: compression)
- [ ] `ipv6_to_str` formatter (canonical form)
- [ ] `build_sockaddr_in6` binary encoder
- [ ] `parse_sockaddr_in6` binary decoder
- [ ] `socket_addr_from_str` IPv6 bracket support (`[::1]:8080`)
- [ ] TCP/UDP bind/connect with IPv6 addresses
- [ ] Tests: full IPv6 parsing/formatting/encoding roundtrip

## v0.5.0 -- Async I/O

- [ ] Non-blocking socket mode (`ioctlsocket`/`fcntl` with `O_NONBLOCK`)
- [ ] `select`-based multiplexing (cross-platform)
- [ ] Event-driven socket state machine
- [ ] Timeout support for connect/read/write operations

## v0.6.0 -- High-Performance I/O

- [ ] Windows: IOCP (I/O Completion Ports) backend
- [ ] Linux: epoll backend
- [ ] macOS/BSD: kqueue backend
- [ ] Unified async `Stream` and `Listener` abstractions

## v0.7.0 -- POSIX Portability

- [ ] `#ifdef`-style platform dispatch (Winsock2 vs POSIX)
- [ ] POSIX shim: `WSAGetLastError` -> `errno`, `closesocket` -> `close`
- [ ] CI: build + test on Windows, Linux, macOS
- [ ] Error code mapping table for POSIX errno values

## v1.0.0 -- Stable Release

- [ ] All above features complete
- [ ] 90%+ test coverage on all modules
- [ ] Full API documentation
- [ ] Performance benchmarks (throughput, latency)
- [ ] Security audit of all `unsafe` blocks
- [ ] Formal contract verification (xiom-verify) on public API

---

## Backlog / Future

| Feature | Priority | Notes |
|---------|----------|-------|
| Unix domain sockets | Low | `AF_UNIX` / `AF_LOCAL` |
| Raw sockets | Low | `SOCK_RAW`, requires admin |
| TLS/SSL | Medium | OpenSSL / SChannel FFI |
| HTTP/1.1 client | Medium | Separate `xiom-http` package |
| WebSocket | Low | Upgrade from HTTP |
| QUIC/HTTP3 | Future | Needs TLS 1.3 + UDP |
| Zero-copy send/recv | Low | `WSASend`/`WSARecv` with IOCP |
| Socket options | Medium | `setsockopt`/`getsockopt` (SO_REUSEADDR, SO_KEEPALIVE, etc.) |
| Multicast UDP | Low | `IP_ADD_MEMBERSHIP` |
| Broadcast UDP | Low | `SO_BROADCAST` |

---

## Dependency Graph

```
xiom-net (this package)
  |-- xiom-std (stdlib: string, ptr, io, collections)
  `-- OS sockets (Winsock2 / POSIX libc)
```
