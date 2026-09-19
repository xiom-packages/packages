# xiom.libsodium -- SPEC

**Phase**: 2 | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi

## What it wraps
libsodium -- modern cryptography library (NaCl fork).
Encryption, decryption, hashing, signatures, key exchange.

## Dependencies: System-installed. `apt install libsodium-dev`.

## Bundling strategy: System-installed only.

## API (minimal)
```xiom
pub fn crypto_box_keypair() -> (PubKey, SecretKey)
pub fn crypto_box_seal(msg, pubkey) -> Vec[UInt8]
pub fn crypto_box_seal_open(cipher, pubkey, seckey) -> Result[Vec[UInt8], Str]
pub fn crypto_sign(msg, seckey) -> Vec[UInt8]
pub fn crypto_sign_verify(signed, pubkey) -> Result[Vec[UInt8], Str]
```

## Effort: Day
