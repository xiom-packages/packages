# xiom-http

> Production-grade HTTP client and message library for XIOM — libcurl FFI with pure-XIOM message parser.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-http provides a complete HTTP/1.1 client backed by libcurl, plus a pure-XIOM HTTP message parser, URL encoder, cookie handler, MIME type resolver, and status code library — all guarded by safety contracts.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design vision — the lean native core (server/client/routing/middleware/plugins/contracts), how it compares to Express/Fastify/Koa/NestJS/Tower, and an honest "Current State vs Target" breakdown of what is implemented today versus planned.

## Ecosystem

xiom-http is the mandatory, dependency-lean core of a web layer that is split into opt-in, independently versioned packages built on top of it:

- **xiom-http** — core: HTTP client, message types, parsing, and (planned) native server, routing, middleware, plugins, and contracts.
- **xiom-rest** — REST resource routing, content negotiation, pagination, and HATEOAS helpers; builds on xiom-http.
- **xiom-graphql** — GraphQL schema, resolvers, and execution engine; builds on xiom-http.
- **xiom-websocket** — WebSocket upgrade, framing, and pub/sub channels; builds on xiom-http.
- **xiom-micro** — service discovery, RPC clients, circuit breakers, and retries; builds on xiom-http.
- **xiom-realtime** — pub/sub, presence, and broadcast rooms; builds on xiom-http (via xiom-websocket).

## Installation

```bash
xiom install xiom-http
```

## Dependencies

### System Libraries (for FFI client)
| OS | Command |
|----|---------|
| **Windows** | `vcpkg install curl` |
| **Ubuntu/Debian** | `sudo apt install libcurl4-openssl-dev` |
| **Fedora** | `sudo dnf install libcurl-devel` |
| **macOS** | `brew install curl` |

Link: `xiom -l curl myprogram.xi`

The message parser, URL handler, and cookie parser are **pure XIOM** and need no dependencies.

## Quick Start

### HTTP Client (FFI)
```xiom
use xiom.http;

fn main() -> Int {
  var response = http_get("https://api.example.com/data").unwrap();
  // response.status, response.body, response.headers
  return 0;
}
```

### HTTP Message Parser (Pure XIOM)
```xiom
use xiom.http.parser;

fn main() -> Int {
  var raw = "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n";
  var request = http_parse_request(raw).unwrap();
  return 0;
}
```

## API Reference

### Client (`xiom.http`) — libcurl FFI
| Function | Description |
|----------|-------------|
| `http_get(url)` | HTTP GET |
| `http_post(url, body, content_type)` | HTTP POST |
| `http_put(url, body)` | HTTP PUT |
| `http_delete(url)` | HTTP DELETE |
| `http_download(url, path)` | Download to file |

### Message Types (`xiom.http.types`)
| Type | Description |
|------|-------------|
| `HttpMethod` | Enum: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS |
| `HttpVersion` | Enum: HTTP09, HTTP10, HTTP11, HTTP20 |
| `HttpHeaders` | Header collection with add/get/has/remove |
| `HttpRequest` | Full request (method, path, headers, body) |
| `HttpResponse` | Full response (status, reason, headers, body) |

### Parser (`xiom.http.parser`)
| Function | Description |
|----------|-------------|
| `http_parse_request(input)` | Parse raw HTTP request |
| `http_parse_response(input)` | Parse raw HTTP response |
| `http_parse_headers(input)` | Parse headers block |

### URL (`xiom.http.url`)
| Function | Description |
|----------|-------------|
| `url_parse(input)` | Parse URL string |
| `url_to_str(url)` | Serialize URL |
| `url_encode(s)` | Percent-encode |
| `url_decode(s)` | Percent-decode |
| `path_join(base, relative)` | Join URL paths |

### Status Codes (`xiom.http.status`)
| Function | Description |
|----------|-------------|
| `http_status_text(code)` | Reason phrase for status code |
| `http_is_success(code)` | 2xx check |
| `http_is_redirect(code)` | 3xx check |
| `http_is_client_error(code)` | 4xx check |
| `http_is_server_error(code)` | 5xx check |

### Cookies (`xiom.http.cookie`)
| Function | Description |
|----------|-------------|
| `cookie_new(name, value)` | Create cookie |
| `cookie_parse(set_cookie)` | Parse Set-Cookie header |
| `cookie_parse_all(header)` | Parse Cookie header |
| `cookie_to_str(cookie)` | Serialize cookie |

### MIME Types (`xiom.http.mime`)
| Function | Description |
|----------|-------------|
| `mime_from_ext(ext)` | Extension → MIME type (21 types) |
| `mime_to_str(mime)` | MIME type → string |

### Server (`xiom.http.server`) — ⚠️ Stubs
| Function | Status |
|----------|--------|
| `server_new(addr, port)` | ⚠️ Type only |
| `server_listen(server)` | ⚠️ Stub |
| `server_handle(server, method, path)` | ⚠️ Stub |

## Safety Contracts

Every public function is guarded:
- `http_get/post/put/delete/download`: requires url.len() > 0
- `HttpHeaders.add/get/has/remove`: requires name.len() > 0
- `HttpResponse.new`: requires status >= 100, status < 600
- `server_new`: requires port > 0, port < 65536, addr.len() > 0
- All parsers: requires input.len() > 0

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| HTTP GET/POST/PUT/DELETE (libcurl) | ✅ Production | FFI bridge integrated, requires ffi_bridge.c |
| HTTP message parser | ✅ Complete | Pure XIOM, RFC 7230 compliant |
| URL parser/encoder | ✅ Complete | RFC 3986 compliant |
| Cookie parser | ✅ Complete | RFC 6265 compliant |
| Status codes (32 codes) | ✅ Complete | All standard codes |
| MIME types (21 types) | ✅ Complete | Common extensions |
| File download | ✅ Production | Via libcurl |
| HTTP/2 support | ❌ Not yet | Needs libcurl HTTP/2 |
| HTTP server | ❌ Stubs only | Needs TCP socket FFI + threading |
| HTTPS/TLS | ⚠️ Libcurl handles it | Config via `CURLOPT_SSL_*` |
| Multipart forms | ❌ Not yet | |
| WebSocket | ❌ Not yet | |
| Streaming responses | ❌ Not yet | |
| Connection pooling | ❌ Not yet | |

### What's Left for v1.0
1. **HTTP server** — wire up via xiom-net TCP sockets
2. **Streaming/chunked responses** — incremental body reading
3. **Multipart form uploads** — file upload support

## Build & Run

```bash
# Compile with FFI bridge and libcurl
xiom myprogram.xi ../runtime/ffi_bridge.c -l curl -o myprogram.exe
./myprogram.exe
```

> Requires ffi_bridge.c to be compiled alongside. The FFI bridge provides `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, and `xiom_free_cstr` across the FFI boundary.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
