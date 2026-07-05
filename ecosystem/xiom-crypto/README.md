# xiom-crypto

> Production-grade cryptography for XIOM — OpenSSL FFI bindings with pure-XIOM reference implementations.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-crypto provides hashing (SHA-256/512, MD5), symmetric encryption (AES-128/256), encoding (Base64, Hex), key derivation (PBKDF2, HKDF), and random number generation — all wrapped in compile-time safety contracts.

**Dual implementation**: Production path uses OpenSSL via `extern "C"` FFI. Pure-XIOM reference implementations exist for all algorithms (verification + bootstrapping).

## Installation

```bash
xiom install xiom-crypto
```

## Dependencies

### System Libraries
| OS | Command |
|----|---------|
| **Windows** | `vcpkg install openssl` |
| **Ubuntu/Debian** | `sudo apt install libssl-dev` |
| **Fedora** | `sudo dnf install openssl-devel` |
| **Arch** | `sudo pacman -S openssl` |
| **macOS** | `brew install openssl` |

Then link at compile time: `xiomc -l crypto -l ssl myprogram.xi`

## Quick Start

```xiom
use xiom.crypto;

fn main() -> Int {
  // Hash some data
  var data = [72, 101, 108, 108, 111];  // "Hello"
  var hash = sha256(&data);
  var hex = sha256_hex(&data);
  // hex = "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969"

  // Generate random bytes
  var rand = random_bytes(32).unwrap();

  // HMAC
  var key = [115, 101, 99, 114, 101, 116];  // "secret"
  var mac = hmac_sha256(&data, &key);

  return 0;
}
```

## API Reference

### Hashing (OpenSSL FFI)
| Function | Output Size | Description |
|----------|-------------|-------------|
| `sha256(data)` | 32 bytes | SHA-256 |
| `sha256_hex(data)` | 64 chars | SHA-256 hex |
| `sha512(data)` | 64 bytes | SHA-512 |
| `sha512_hex(data)` | 128 chars | SHA-512 hex |
| `md5(data)` | 16 bytes | MD5 (legacy) |
| `md5_hex(data)` | 32 chars | MD5 hex (legacy) |
| `hmac_sha256(data, key)` | 32 bytes | HMAC-SHA256 |

### Symmetric Encryption (Pure XIOM)
| Function | Key Size | Block Size | Description |
|----------|----------|------------|-------------|
| `aes128_encrypt(plain, key)` | 16 bytes | 16 bytes | AES-128 encrypt |
| `aes128_decrypt(cipher, key)` | 16 bytes | 16 bytes | AES-128 decrypt |
| `aes256_encrypt(plain, key)` | 32 bytes | 16 bytes | AES-256 encrypt |
| `aes256_decrypt(cipher, key)` | 32 bytes | 16 bytes | AES-256 decrypt |

### Encoding
| Function | Description |
|----------|-------------|
| `base64_encode(data)` | Standard Base64 |
| `base64_decode(input)` | Standard Base64 decode |
| `base64url_encode(data)` | URL-safe Base64 |
| `base64url_decode(input)` | URL-safe Base64 decode |
| `hex_encode(data)` | Hex (lowercase) |
| `hex_decode(input)` | Hex decode |

### Key Derivation
| Function | Description |
|----------|-------------|
| `pbkdf2_sha256(password, salt, iter, len)` | PBKDF2-HMAC-SHA256 |

### Random (Pure XIOM Xorshift)
| Function | Description |
|----------|-------------|
| `random_bytes(count)` | OpenSSL RAND_bytes (FFI) |
| `xorshift64(state)` | Fast PRNG (pure XIOM) |
| `random_range(state, min, max)` | Random in range |

### Signatures
| Function | Status |
|----------|--------|
| `ed25519_keygen()` | Stub (needs OS entropy + bigint) |
| `ed25519_sign(msg, keypair)` | Stub |
| `ed25519_verify(msg, sig, pubkey)` | Stub |

## Safety Contracts

Every FFI boundary is guarded:
- `sha256/sha512/md5`: requires data.len() > 0, ensures output length
- `aes128_encrypt`: requires plaintext.len() == 16, key.len() == 16
- `aes256_encrypt`: requires plaintext.len() == 16, key.len() == 32
- `random_bytes`: requires count > 0
- `pbkdf2_sha256`: requires iterations >= 1, keylen > 0

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| SHA-256/512 (OpenSSL FFI) | ✅ Production | FFI bridge integrated, requires ffi_bridge.c |
| SHA-256/512 (Pure XIOM) | Reference | FIPS 180-4 compliant, for verification |
| MD5 (OpenSSL FFI) | ✅ Production | FFI bridge integrated |
| MD5 (Pure XIOM) | Reference | RFC 1321 compliant |
| HMAC-SHA256 | Production | Pure XIOM on top of FFI SHA-256 |
| AES-128/256 (Pure XIOM) | Reference | Full S-Box, MixColumns, key expansion |
| AES-GCM / AES-CBC | Not yet | Block cipher modes |
| Base64/Hex | Production | Pure XIOM, no FFI needed |
| Random (OpenSSL) | ✅ Production | FFI bridge integrated |
| Random (Xorshift) | Complete | Pure XIOM PRNG |
| PBKDF2 | Production | Pure XIOM on top of SHA-256 |
| Ed25519 | Stubs only | Needs bigint math + secure RNG |
| TLS/SSL | Not yet | Needs full TLS implementation |

### What's Left for v1.0
1. **Block cipher modes** — CBC, CTR, GCM for AES
2. **Ed25519 implementation** — needs compiler bigint support or FFI
3. **TLS bindings** — via OpenSSL `libssl`

## Build & Run

```bash
# Compile with FFI bridge and OpenSSL
xiomc myprogram.xi ../runtime/ffi_bridge.c -l crypto -l ssl -o myprogram.exe
./myprogram.exe
```

> Requires ffi_bridge.c to be compiled alongside. The FFI bridge provides `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, and `xiom_free_cstr` across the FFI boundary.

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)

## License

MIT OR Apache-2.0
