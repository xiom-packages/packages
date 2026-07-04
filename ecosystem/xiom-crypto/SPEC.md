xiom-crypto: XIOM Cryptography Library v0.1.0

== Overview ==

xiom-crypto is a pure-XIOM cryptographic library providing hashing, symmetric encryption,
encoding, random number generation, key derivation, and digital signature primitives.
All implementations are self-contained (no FFI dependencies) and serve as reference
implementations for the XIOM ecosystem.

Layer: 3.4 (Ecosystem Libraries)
Package: xiom-crypto
Namespace: xiom.crypto.*

== Module Architecture ==

xiom.crypto.hash      Fast non-cryptographic hashes (DJB2, FNV-1a, MurmurHash3)
xiom.crypto.sha       SHA-256 and SHA-512 with HMAC
xiom.crypto.md5       MD5 hash (legacy compatibility)
xiom.crypto.aes       AES-128/256 block cipher (ECB mode)
xiom.crypto.b64       Base64 and Base64URL encoding/decoding
xiom.crypto.hex       Hexadecimal encoding/decoding
xiom.crypto.random    Xorshift PRNG family
xiom.crypto.pbkdf     PBKDF2-HMAC-SHA256 and HKDF-SHA256
xiom.crypto.ed25519   Ed25519 signature types (stubs)

== Module Specifications ==

=== 1. xiom.crypto.hash -- Fast Hashes ===

Non-cryptographic hash functions for hash tables, checksums, and data fingerprinting.

hash_djb2(data): DJB2 algorithm, Int output. hash = hash * 33 + byte.
hash_fnv1a(data): FNV-1a algorithm, Int output. XOR-then-multiply with 32-bit FNV prime.
hash_murmur3_32(data, seed): MurmurHash3 32-bit, Int output. 4-byte blocks, finalization avalanche.

=== 2. xiom.crypto.sha -- SHA-2 Family ===

Full FIPS 180-4 compliant SHA-256 and SHA-512 implementations.

SHA-256 Constants:
  8 initial hash values H[0..7] - first 32 bits of fractional parts of sqrt(first 8 primes)
  64 round constants K[0..63] - first 32 bits of fractional parts of cbrt(first 64 primes)

SHA-512 Constants:
  8 initial hash values H[0..7] - first 64 bits of fractional parts of sqrt(first 8 primes)
  80 round constants K[0..79] - first 64 bits of fractional parts of cbrt(first 80 primes)

Functions:
  sha256(data)           SHA-256 hash, 32 bytes output
  sha256_hex(data)       SHA-256 as hex string, 64 chars
  sha256_hmac(data, key) HMAC-SHA256 (RFC 2104), 32 bytes output
  sha512(data)           SHA-512 hash, 64 bytes output
  sha512_hex(data)       SHA-512 as hex string, 128 chars

SHA-256 Algorithm:
  1. Padding: Append 0x80, pad with zeros, append 64-bit big-endian bit length
  2. Parsing: Split into 512-bit (64-byte) blocks
  3. Per Block:
     - Prepare message schedule W[0..63] (16 words from block + 48 computed)
     - Initialize working variables a..h from current hash
     - 64 rounds: T1 = h + S1(e) + Ch(e,f,g) + K[i] + W[i]
                  T2 = S0(a) + Maj(a,b,c)
     - Add compressed values to hash state
  4. Output: Concatenate final H[0..7] as 32 big-endian bytes

HMAC: HMAC(K, m) = H((K' xor opad) || H((K' xor ipad) || m))
      K' is key padded/hashed to block size (64 bytes for SHA-256)

=== 3. xiom.crypto.md5 -- MD5 Hash ===

RFC 1321 compliant MD5 implementation for legacy compatibility.

  md5(data)     MD5 hash, 16 bytes output
  md5_hex(data) MD5 as hex string, 32 chars

Algorithm:
  1. Padding with little-endian bit length
  2. 4 rounds of 16 operations using F, G, H, I nonlinear functions
  3. 64 T-constants (abs(sin(i+1)) * 2^32)
  4. Per-round shift amounts S[0..63]
  5. Output as 4 little-endian 32-bit words

=== 4. xiom.crypto.aes -- AES Block Cipher ===

FIPS 197 compliant AES-128 and AES-256 single-block ECB encryption/decryption.

  aes128_encrypt(pt, key)  128-bit key, 10 rounds, 16-byte block
  aes128_decrypt(ct, key)  128-bit key, 10 rounds, 16-byte block
  aes256_encrypt(pt, key)  256-bit key, 14 rounds, 16-byte block
  aes256_decrypt(ct, key)  256-bit key, 14 rounds, 16-byte block

Components:
  S-Box: 256-entry substitution table (GF(2^8) inverse + affine transform)
  Inverse S-Box: 256-entry reverse substitution
  Rcon: Round constants (1, 2, 4, 8, 16, 32, 64, 128, 27, 54)
  Key Expansion: Derives (Nr+1)*16 bytes of round keys
  SubBytes: Per-byte S-Box substitution
  ShiftRows: Cyclic row shifts (0, 1, 2, 3 positions)
  MixColumns: GF(2^8) matrix multiplication per column
  AddRoundKey: XOR state with round key

GF Operations: mul2(x) = (x << 1) xor (0x1B if x & 0x80 else 0).
  mul3 = mul2(x) xor x, mul9 = mul2(mul2(mul2(x))) xor x, etc.

=== 5. xiom.crypto.b64 -- Base64 Encoding ===

RFC 4648 compliant Base64 and Base64URL encoding/decoding.

  base64_encode(data)      Standard Base64 with + / and = padding
  base64_decode(input)     Decode standard Base64, returns Result
  base64url_encode(data)   URL-safe Base64 with - _ no padding
  base64url_decode(input)  Decode URL-safe Base64, returns Result

Alphabet: A-Z (0-25), a-z (26-51), 0-9 (52-61), +/ for standard, -_ for URL-safe.

=== 6. xiom.crypto.hex -- Hexadecimal Encoding ===

  hex_encode(data)        Lowercase hex string
  hex_encode_upper(data)  Uppercase hex string
  hex_decode(input)       Decode hex string to bytes, returns Result

=== 7. xiom.crypto.random -- Xorshift PRNG ===

Marsaglia's Xorshift pseudorandom number generators.

  xorshift32(state)              Period 2^32 - 1
  xorshift64(state)              Period 2^64 - 1
  xorshift128(state)             Period 2^128 - 1
  xorshift_star64(state)         Xorshift* variant, period 2^64 - 1
  random_range(state, min, max)  Returns (value, new_state)
  random_bytes(state, count)     Returns (bytes, new_state)

These are deterministic PRNGs. Seed with OS entropy for cryptographic use.

=== 8. xiom.crypto.pbkdf -- Key Derivation ===

  pbkdf2_sha256(password, salt, iterations, keylen)  RFC 2898 / PKCS #5
  hkdf_sha256(ikm, salt, info, length)               RFC 5869

PBKDF2: U_1 = PRF(Password, Salt || INT_32_BE(i))
        U_n = PRF(Password, U_{n-1})
        output = U_1 xor U_2 xor ... xor U_c

HKDF Extract: PRK = HMAC-SHA256(salt, IKM)
HKDF Expand:  OKM = T(1) || T(2) || ...
              T(n) = HMAC-SHA256(PRK, T(n-1) || info || n)

=== 9. xiom.crypto.ed25519 -- Ed25519 Signatures ===

  ed25519_keygen()                    STUB - Generate Ed25519 key pair
  ed25519_sign(msg, keypair)          STUB - Sign message
  ed25519_verify(msg, sig, pubkey)    STUB - Verify signature

Types:
  Ed25519KeyPair = { public_key: Vec[Int]; private_key: Vec[Int]; }
  Ed25519Signature = { r: Vec[Int]; s: Vec[Int]; }

Dependencies (not yet available):
  - OS entropy source for secure key generation
  - Big integer arithmetic (modular operations in GF(2^255-19))
  - SHA-512 (available in xiom.crypto.sha)
  - Elliptic curve point operations on Curve25519

== Limitations ==

1. ECB Mode Only: AES implements single-block ECB. CBC/CTR/GCM not yet available.
2. No Authenticated Encryption: AES-GCM and ChaCha20-Poly1305 not implemented.
3. Deterministic PRNG: Xorshift is not cryptographically secure without hardware seed.
4. Ed25519 Stubs: Full Ed25519 requires Layer 2 (big integer math) completion.
5. No Constant-Time Guarantees: Implementations are educational/verification grade.
6. No Side-Channel Protection: Not hardened against timing or power analysis.

== API Conventions ==

- Hash functions: accept &Vec[Int], return Vec[Int] or Str (hex)
- Encoding functions: accept &Vec[Int], return Str
- Decoding functions: accept Str, return Result[Vec[Int], Str]
- AES functions: return Result[Vec[Int], Str] with validation
- PRNG functions: pure, return (value, new_state) tuples
- KDF functions: accept &Vec[Int] for all parameters

== Test Vectors ==

Expected outputs for empty input:

  sha256_hex([]):
    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

  sha512_hex([]):
    cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce
    47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e

  md5_hex([]):
    d41d8cd98f00b204e9800998ecf8427e

  base64_encode([]): ""
  hex_encode([]): ""
  hash_djb2([]): 5381
  hash_fnv1a([]): -2128831035
