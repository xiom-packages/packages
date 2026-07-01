# AXIOM Ecosystem

Standard libraries for the AXIOM programming language.

## Libraries

| Package | Directory | Description |
|---------|-----------|-------------|
| axiom-http | `axiom-http/` | HTTP client via libcurl FFI |
| axiom-crypto | `axiom-crypto/` | Cryptographic hashing via OpenSSL FFI |
| axiom-sql | `axiom-sql/` | SQL database via SQLite FFI |
| axiom-vulkan | `axiom-vulkan/` | GPU graphics/compute via Vulkan FFI |
| axiom-glfw | `axiom-glfw/` | Windowing and input via GLFW FFI |
| axiom-libsodium | `axiom-libsodium/` | Secure cryptography via libsodium FFI |
| axiom-bullet | `axiom-bullet/` | Physics via Bullet Physics FFI |
| axiom-blas | `axiom-blas/` | Linear algebra via BLAS/LAPACK FFI |
| axiom-protobuf | `axiom-protobuf/` | Protocol Buffers via libprotobuf FFI |
| axiom-grpc | `axiom-grpc/` | gRPC client via gRPC C Core FFI |

## Available FFI Bindings

| Library | Spec File | C Library |
|---------|-----------|-----------|
| libcurl | `axiom-http/libcurl.axiom-bind` | libcurl |
| OpenSSL | `axiom-crypto/openssl.axiom-bind` | libcrypto + libssl |
| SQLite | `axiom-sql/sqlite.axiom-bind` | libsqlite3 |
| Vulkan | `axiom-vulkan/vulkan.axiom-bind` | vulkan-1 |
| GLFW | `axiom-glfw/glfw.axiom-bind` | glfw3 |
| libsodium | `axiom-libsodium/libsodium.axiom-bind` | libsodium |
| Bullet Physics | `axiom-bullet/bullet.axiom-bind` | BulletCollision + BulletDynamics |
| BLAS/LAPACK | `axiom-blas/blas.axiom-bind` | libopenblas |
| Protocol Buffers | `axiom-protobuf/protobuf.axiom-bind` | libprotobuf |
| gRPC C Core | `axiom-grpc/grpc.axiom-bind` | libgrpc |

## Generate Bindings

```powershell
axiom ffigen ecosystem/axiom-http/libcurl.axiom-bind > ecosystem/axiom-http/curl_extern.ax
axiom ffigen ecosystem/axiom-crypto/openssl.axiom-bind > ecosystem/axiom-crypto/crypto_extern.ax
axiom ffigen ecosystem/axiom-sql/sqlite.axiom-bind > ecosystem/axiom-sql/sql_extern.ax
axiom ffigen ecosystem/axiom-vulkan/vulkan.axiom-bind > ecosystem/axiom-vulkan/vulkan_extern.ax
axiom ffigen ecosystem/axiom-glfw/glfw.axiom-bind > ecosystem/axiom-glfw/glfw_extern.ax
axiom ffigen ecosystem/axiom-libsodium/libsodium.axiom-bind > ecosystem/axiom-libsodium/libsodium_extern.ax
axiom ffigen ecosystem/axiom-bullet/bullet.axiom-bind > ecosystem/axiom-bullet/bullet_extern.ax
axiom ffigen ecosystem/axiom-blas/blas.axiom-bind > ecosystem/axiom-blas/blas_extern.ax
axiom ffigen ecosystem/axiom-protobuf/protobuf.axiom-bind > ecosystem/axiom-protobuf/protobuf_extern.ax
axiom ffigen ecosystem/axiom-grpc/grpc.axiom-bind > ecosystem/axiom-grpc/grpc_extern.ax
```

## Build

All ecosystem libraries compile with:
```powershell
axiomc -o output.exe ecosystem/axiom-http/http.ax
```
