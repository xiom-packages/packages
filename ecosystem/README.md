# AXIOM Ecosystem

Standard libraries for the AXIOM programming language.

## Libraries

| Package | Directory | Description |
|---------|-----------|-------------|
| axiom-http | `axiom-http/` | HTTP client via libcurl FFI |
| axiom-crypto | `axiom-crypto/` | Cryptographic hashing via OpenSSL FFI |
| axiom-sql | `axiom-sql/` | SQL database via SQLite FFI |

## Available FFI Bindings

| Library | Spec File | C Library |
|---------|-----------|-----------|
| libcurl | `axiom-http/libcurl.axiom-bind` | libcurl |
| OpenSSL | `axiom-crypto/openssl.axiom-bind` | libcrypto + libssl |
| SQLite | `axiom-sql/sqlite.axiom-bind` | libsqlite3 |

## Generate Bindings

```powershell
axiom ffigen ecosystem/axiom-http/libcurl.axiom-bind > ecosystem/axiom-http/curl_extern.ax
axiom ffigen ecosystem/axiom-crypto/openssl.axiom-bind > ecosystem/axiom-crypto/crypto_extern.ax
axiom ffigen ecosystem/axiom-sql/sqlite.axiom-bind > ecosystem/axiom-sql/sql_extern.ax
```

## Build

All ecosystem libraries compile with:
```powershell
axiomc -o output.exe ecosystem/axiom-http/http.ax
```
