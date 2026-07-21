# xiom-libsodium Audit

## Compilation Status
- `libsodium.xi` — PASSES (standalone)
- `tests/test_libsodium.xi` — PASSES (with libsodium.xi)
- All files compile together: PASS

## Changes Made
1. **tests/test_libsodium.xi**: Fixed type mismatch — `secretbox_encrypt("test", key, nonce)` passed `Str` where `&Vec[UInt8]` was expected. Changed to `encoding.utf8_encode("test")` with `use xiom.encoding;`.

## System Dependencies

### Required: libsodium
- **Linux**: `apt install libsodium-dev` → `libsodium.so`
- **macOS**: `brew install libsodium` → `libsodium.dylib`
- **Windows**: Download pre-built from https://download.libsodium.org/libsodium/releases/ → `libsodium.dll`

### Required DLL at Runtime
| DLL | Purpose |
|-----|---------|
| `libsodium.dll` / `libsodium.so` / `libsodium.dylib` | All cryptographic primitives |

### Link Flags
```
-l sodium
```

### Compilation with Libraries
```powershell
xiomc --link sodium --link-path C:/path/to/libsodium/lib libsodium.xi program.xi
```

## FFI Bindings Mapped (libsodium.xiom-bind)

| XIOM Function | C Function | Category |
|--------------|------------|----------|
| `init` | `sodium_init` | Initialization |
| `random_bytes` | `randombytes_buf` | Random |
| `random_int_uniform` | `randombytes_uniform` | Random |
| `secretbox_encrypt` | `crypto_secretbox_easy` | Secret-key crypto |
| `secretbox_decrypt` | `crypto_secretbox_open_easy` | Secret-key crypto |
| `box_keypair` | `crypto_box_keypair` | Public-key crypto |
| `box_encrypt` | `crypto_box_easy` | Public-key crypto |
| `box_decrypt` | `crypto_box_open_easy` | Public-key crypto |
| `sign_keypair` | `crypto_sign_keypair` | Signatures |
| `sign_detached` | `crypto_sign_detached` | Signatures |
| `verify_detached` | `crypto_sign_verify_detached` | Signatures |
| `generic_hash` | `crypto_generichash` | Hashing |
| `generic_hash_keyed` | `crypto_generichash` (with key) | Hashing |
| `pwhash` | `crypto_pwhash` | Password hashing |

## Constants
All constants (`SECRETBOX_KEYBYTES`, `SECRETBOX_NONCEBYTES`, `BOX_PUBLICKEYBYTES`, `BOX_SECRETKEYBYTES`, `SIGN_PUBLICKEYBYTES`, `SIGN_SECRETKEYBYTES`) are hardcoded in `libsodium.xi`. They match libsodium 1.0.18+ values.

## Known Gaps
- All `libsodium.xi` functions are forward declarations (`;` body) — they require libsodium at link time and runtime.
- Tests gracefully skip if `init()` fails (no DLL present), but this means functional correctness is not verified at compile time.
- `pwhash_verify` is declared in `libsodium.xi` but has no corresponding `.xiom-bind` mapping — the C function `crypto_pwhash_str_verify` is missing from the bind file.
- `pwhash` salt parameter is missing from the XIOM API surface — the C function requires a salt but the XIOM binding doesn't expose it.
- No `sodium_memzero` or `sodium_mlock` wrappers for secure memory handling.
