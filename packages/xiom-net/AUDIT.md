# xiom-net -- System Dependencies & Build Notes

## System Requirements

### Windows
- **Winsock2** (`ws2_32.dll`) -- Built into Windows, no separate installation needed.
- **Linker flag:** `xiom -l ws2_32 ...`

### Linux
- POSIX sockets -- Built into libc, no extra installation needed.
- A POSIX shim is required to map Winsock2 symbols to POSIX equivalents:
  - `WSAGetLastError` -> `errno`
  - `WSAStartup` -> no-op (return 0)
  - `WSACleanup` -> no-op
  - `closesocket` -> `close`

### macOS
- POSIX sockets -- Built into libc, same as Linux.

## Build Command Example

```bash
# Windows
xiom src/types.xi src/tcp.xi src/udp.xi src/dns.xi src/demo.xi -l ws2_32 -o net_demo.exe

# Linux/macOS
xiom src/types.xi src/tcp.xi src/udp.xi src/dns.xi src/demo.xi posix_shim.c -o net_demo
```

## Runtime Dependencies
- None beyond the platform's native socket library.

## Compilation Status
- All 5 source files (`types.xi`, `tcp.xi`, `udp.xi`, `dns.xi`, `demo.xi`) type-check successfully with xiom v0.45.3.
- `dns.xi` functions are stubs returning `Err(...)` -- DNS resolution requires OS `getaddrinfo` FFI to be wired.
- IPv6 parsing is stubbed; only IPv4 is fully implemented.
