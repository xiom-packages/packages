# xiom-crypto Roadmap

## v0.1.0 — Foundation (Current)

- [x] SHA-256 (pure XIOM + OpenSSL FFI)
- [x] SHA-512 (pure XIOM + OpenSSL FFI)
- [x] MD5 (pure XIOM + OpenSSL FFI)
- [x] HMAC-SHA256 (pure XIOM)
- [x] AES-128 ECB (pure XIOM)
- [x] AES-256 ECB (pure XIOM)
- [x] Base64 / Base64URL (pure XIOM)
- [x] Hex encoding/decoding (pure XIOM)
- [x] PBKDF2-HMAC-SHA256 (pure XIOM)
- [x] HKDF-SHA256 (pure XIOM)
- [x] Xorshift PRNG (pure XIOM)
- [x] CSPRNG via OpenSSL RAND_bytes (FFI)
- [x] Non-crypto hashes: DJB2, FNV-1a, MurmurHash3
- [x] Safety contracts on all public functions
- [x] Conformance test suite (known-answer vectors)

## v0.2.0 — Block Cipher Modes

- [ ] AES-CBC mode (encrypt + decrypt)
- [ ] AES-CTR mode (stream cipher)
- [ ] PKCS#7 padding
- [ ] AES-CBC test vectors (NIST CAVP)
- [ ] Block cipher benchmarks

## v0.3.0 — Authenticated Encryption

- [ ] AES-GCM mode (encrypt + decrypt)
- [ ] ChaCha20 stream cipher
- [ ] ChaCha20-Poly1305 AEAD
- [ ] GHASH/GF(2^128) multiplication
- [ ] AEAD test vectors

## v1.0.0 — Production Release

- [ ] Ed25519 key generation (needs OS entropy + bigint)
- [ ] Ed25519 signing (needs Curve25519 operations)
- [ ] Ed25519 verification
- [ ] SHA-3 family (Keccak)
- [ ] Constant-time implementation audit
- [ ] Side-channel resistance hardening
- [ ] Full NIST CAVP test vector coverage
- [ ] FIPS 140-3 self-tests
- [ ] Performance benchmarks vs OpenSSL native

## Future

- [ ] TLS 1.3 bindings via OpenSSL libssl
- [ ] X.509 certificate parsing
- [ ] RSA key generation/signing (FFI)
- [ ] ECDSA P-256 / P-384 (FFI)
- [ ] BLAKE2 / BLAKE3 hashing
- [ ] Argon2id key derivation
- [ ] WebAssembly target (pure XIOM path only)
- [ ] Hardware acceleration detection
- [ ] Formal verification of contracts via Z3
