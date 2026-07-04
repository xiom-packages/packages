# XIOM Ecosystem

Standard libraries for the XIOM programming language.

## Libraries

| Package | Directory | Description |
|---------|-----------|-------------|
| xiom-http | `xiom-http/` | HTTP client via libcurl FFI |
| xiom-crypto | `xiom-crypto/` | Cryptographic hashing via OpenSSL FFI |
| xiom-sql | `xiom-sql/` | SQL database via SQLite FFI |
| xiom-vulkan | `xiom-vulkan/` | GPU graphics/compute via Vulkan FFI |
| xiom-glfw | `xiom-glfw/` | Windowing and input via GLFW FFI |
| xiom-libsodium | `xiom-libsodium/` | Secure cryptography via libsodium FFI |
| xiom-bullet | `xiom-bullet/` | Physics via Bullet Physics FFI |
| xiom-blas | `xiom-blas/` | Linear algebra via BLAS/LAPACK FFI |
| xiom-protobuf | `xiom-protobuf/` | Protocol Buffers via libprotobuf FFI |
| xiom-grpc | `xiom-grpc/` | gRPC client via gRPC C Core FFI |

## Available FFI Bindings

| Library | Spec File | C Library |
|---------|-----------|-----------|
| libcurl | `xiom-http/libcurl.xiom-bind` | libcurl |
| OpenSSL | `xiom-crypto/openssl.xiom-bind` | libcrypto + libssl |
| SQLite | `xiom-sql/sqlite.xiom-bind` | libsqlite3 |
| Vulkan | `xiom-vulkan/vulkan.xiom-bind` | vulkan-1 |
| GLFW | `xiom-glfw/glfw.xiom-bind` | glfw3 |
| libsodium | `xiom-libsodium/libsodium.xiom-bind` | libsodium |
| Bullet Physics | `xiom-bullet/bullet.xiom-bind` | BulletCollision + BulletDynamics |
| BLAS/LAPACK | `xiom-blas/blas.xiom-bind` | libopenblas |
| Protocol Buffers | `xiom-protobuf/protobuf.xiom-bind` | libprotobuf |
| gRPC C Core | `xiom-grpc/grpc.xiom-bind` | libgrpc |

## Generate Bindings

```powershell
xiom ffigen ecosystem/xiom-http/libcurl.xiom-bind > ecosystem/xiom-http/curl_extern.xi
xiom ffigen ecosystem/xiom-crypto/openssl.xiom-bind > ecosystem/xiom-crypto/crypto_extern.xi
xiom ffigen ecosystem/xiom-sql/sqlite.xiom-bind > ecosystem/xiom-sql/sql_extern.xi
xiom ffigen ecosystem/xiom-vulkan/vulkan.xiom-bind > ecosystem/xiom-vulkan/vulkan_extern.xi
xiom ffigen ecosystem/xiom-glfw/glfw.xiom-bind > ecosystem/xiom-glfw/glfw_extern.xi
xiom ffigen ecosystem/xiom-libsodium/libsodium.xiom-bind > ecosystem/xiom-libsodium/libsodium_extern.xi
xiom ffigen ecosystem/xiom-bullet/bullet.xiom-bind > ecosystem/xiom-bullet/bullet_extern.xi
xiom ffigen ecosystem/xiom-blas/blas.xiom-bind > ecosystem/xiom-blas/blas_extern.xi
xiom ffigen ecosystem/xiom-protobuf/protobuf.xiom-bind > ecosystem/xiom-protobuf/protobuf_extern.xi
xiom ffigen ecosystem/xiom-grpc/grpc.xiom-bind > ecosystem/xiom-grpc/grpc_extern.xi
```

## Build

All ecosystem libraries compile with:
```powershell
xiomc -o output.exe ecosystem/xiom-http/http.xi
```
