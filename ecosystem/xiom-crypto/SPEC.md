xiom-crypto: XIOM Cryptography Library v0.1.0

== Overview ==

xiom-crypto is the XIOM Cryptography Library providing hashing, symmetric encryption,
encoding, random number generation, key derivation, and digital signature primitives.

Two tiers of implementation are provided:
  - FFI Tier (crypto.xi): Production-grade bindings to OpenSSL via extern "C",
    offering SHA-256, SHA-512, MD5, HMAC-SHA256, CSPRNG (RAND_bytes), Base64,
    and Hex encoding.
  - Pure-XIOM Tier (src/): Self-contained reference implementations for SHA,
    MD5, AES, Base64, Hex, Xorshift PRNG, PBKDF2, HKDF, and Ed25519 stubs.
    Serves as verification-grade code and educational reference for the XIOM
    ecosystem.

Layer: 3.4 (Ecosystem Libraries)
Package: xiom-crypto
Namespace: xiom.crypto.*

== Module Architecture ==

xiom.crypto            FFI-backed production bindings (OpenSSL via extern "C")
xiom.crypto.demo       Usage examples and smoke tests for the FFI tier
xiom.crypto.hash       Fast non-cryptographic hashes (DJB2, FNV-1a, MurmurHash3)
xiom.crypto.sha        SHA-256 and SHA-512 with HMAC (pure XIOM)
xiom.crypto.md5        MD5 hash (legacy compatibility, pure XIOM)
xiom.crypto.aes        AES-128/256 block cipher (ECB mode, pure XIOM)
xiom.crypto.b64        Base64 and Base64URL encoding/decoding (pure XIOM)
xiom.crypto.hex        Hexadecimal encoding/decoding (pure XIOM)
xiom.crypto.random     Xorshift PRNG family (pure XIOM)
xiom.crypto.pbkdf      PBKDF2-HMAC-SHA256 and HKDF-SHA256 (pure XIOM)
xiom.crypto.ed25519    Ed25519 signature types (stubs)

== OpenSSL Runtime Dependency ==

The root `xiom.crypto` module (crypto.xi) links against OpenSSL's libcrypto
at runtime for hardware-accelerated hashing and cryptographically secure
random number generation. The pure-XIOM src/ modules have no external
dependencies.

Required FFI symbols:
  SHA256, SHA512, MD5      — libcrypto (one-shot digest)
  RAND_bytes               — libcrypto (CSPRNG)

=== Linux (Debian/Ubuntu) ===

  sudo apt update
  sudo apt install libssl-dev

The XIOM runtime resolver loads libcrypto.so.3 (or libcrypto.so.1.1 on older
systems). Verify the library is on the linker path:

  ldconfig -p | grep libcrypto

=== Linux (Fedora/RHEL) ===

  sudo dnf install openssl-devel

=== Linux (Arch) ===

  sudo pacman -S openssl

=== macOS ===

OpenSSL is not shipped by default on macOS. Install via Homebrew:

  brew install openssl@3

Add the library to the linker search path (Homebrew keg-only default):

  export LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$LIBRARY_PATH"
  export LD_LIBRARY_PATH="/opt/homebrew/opt/openssl@3/lib:$LD_LIBRARY_PATH"

On Intel Macs, use /usr/local/homebrew/opt/openssl@3/lib instead.

Verify:

  ls /opt/homebrew/opt/openssl@3/lib/libcrypto.dylib

=== Windows ===

Option A — vcpkg (recommended)

  git clone https://github.com/Microsoft/vcpkg.git C:\vcpkg
  cd C:\vcpkg
  .\bootstrap-vcpkg.bat
  .\vcpkg install openssl:x64-windows

Set environment variables for the XIOM linker:

  set OPENSSL_DIR=C:\vcpkg\packages\openssl_x64-windows
  set PATH=%OPENSSL_DIR%\bin;%PATH%

Option B — Pre-built binaries (SlikSVN / Shining Light Productions)

  1. Download "Win64 OpenSSL v3.x" installer from https://slproweb.com/products/Win32OpenSSL.html
  2. Run the installer and choose "Copy OpenSSL DLLs to /bin directory"
  3. Verify: where libcrypto-3-x64.dll

Option C — MSYS2 / MinGW

  pacman -S mingw-w64-x86_64-openssl

Verify after any method:

  XIOM loads libcrypto-3-x64.dll (or libcrypto-1_1-x64.dll) from PATH.

=== XIOM FFI Link-Time Resolution ===

At build time, the XIOM compiler emits a dynamic symbol reference for
each function declared in `extern "C" { }` blocks. The runtime loader
resolves these symbols against the system libcrypto using:

  Linux:   dlopen("libcrypto.so.3", RTLD_NOW)
  macOS:   dlopen("libcrypto.3.dylib", RTLD_NOW)
  Windows: LoadLibraryA("libcrypto-3-x64.dll")

If the library cannot be found, the module will fail to load and return
a linker error at module initialization time.

=== Runtime Intrinsics Required ===

The following XIOM runtime intrinsics are required before the FFI tier is
fully operational (all marked PENDING in crypto.xi):

  @axiom_vec_to_ptr(v: &Vec[Int]) -> *UInt8
    Returns a pointer to the Vec backing store. No copy — the pointer is
    valid for the duration of the FFI call within the unsafe block.

  @axiom_alloc(size: UInt) -> *UInt8
    Allocates `size` zeroed bytes on the native heap. Caller frees manually.

  @axiom_read_u8(ptr: *UInt8, offset: UInt) -> Int
    Reads one unsigned byte at ptr+offset, zero-extended to XIOM Int.

  @axiom_free(ptr: *UInt8)
    Releases a native heap allocation returned by @axiom_alloc.

  @axiom_str_char_code(s: Str, pos: Int) -> Int
    Returns the Unicode code point at position `pos` in string `s`.
    Used for character-by-character String iteration in base64/hex decode.

These intrinsics must be implemented in the XIOM runtime (Layer 0) and
exposed to the compiler before crypto.xi can execute FFI code paths.

== Module Specifications ==

=== 0. xiom.crypto -- FFI Production Bindings ===

The root crypto.xi module provides production-quality cryptographic
primitives backed by the system OpenSSL library. All functions in this
module delegate to libcrypto via extern "C" FFI where applicable.
Encoding functions (Base64, Hex) are pure XIOM with no FFI dependency.

Functions:

  sha256(data: &Vec[Int]) -> Vec[Int]
    SHA-256 one-shot hash via libcrypto SHA256(). Returns 32 bytes.
    PENDING: @axiom_vec_to_ptr, @axiom_alloc, @axiom_read_u8, @axiom_free.

  sha256_hex(data: &Vec[Int]) -> Str
    Convenience: sha256() piped through hex_encode(). 64 hex chars.

  sha512(data: &Vec[Int]) -> Vec[Int]
    SHA-512 hash via libcrypto SHA512(). Returns 64 bytes.
    PENDING: Same intrinsics as sha256.

  sha512_hex(data: &Vec[Int]) -> Str
    Convenience: sha512() piped through hex_encode(). 128 hex chars.

  md5(data: &Vec[Int]) -> Vec[Int]
    MD5 hash via libcrypto MD5(). Returns 16 bytes.
    PENDING: Same intrinsics as sha256.

  md5_hex(data: &Vec[Int]) -> Str
    Convenience: md5() piped through hex_encode(). 32 hex chars.

  hmac_sha256(data: &Vec[Int], key: &Vec[Int]) -> Vec[Int]
    HMAC-SHA256 per RFC 2104. Uses sha256() (FFI-backed) internally.
    Key is padded/hashed to the SHA-256 block size (64 bytes).
    The HMAC algorithm itself is pure XIOM — no additional C function needed.

  random_bytes(count: Int) -> Result[Vec[Int], Str]
    Cryptographically secure random bytes via OpenSSL RAND_bytes().
    Returns count bytes, or Err if the entropy source is unavailable.
    PENDING: @axiom_alloc, @axiom_read_u8, @axiom_free.

  base64_encode(data: &Vec[Int]) -> Str
    RFC 4648 standard Base64 with + / and = padding. Pure XIOM.

  base64_decode(input: Str) -> Result[Vec[Int], Str]
    Decode standard Base64. Returns Err on invalid length or characters.
    Pure XIOM. PENDING: @axiom_str_char_code for string indexing.

  hex_encode(data: &Vec[Int]) -> Str
    Lowercase hex encoding. Pure XIOM.

  hex_decode(input: Str) -> Result[Vec[Int], Str]
    Decode hex string to bytes. Returns Err on odd length or invalid chars.
    Pure XIOM. PENDING: @axiom_str_char_code for string indexing.

=== 0.1. xiom.crypto.demo -- Usage Examples ===

  demo_hash() -> Result[Unit, Str]
    Computes SHA-256 of "Hello World" (ASCII bytes), produces hex string.
    Expected: a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e

  demo_random() -> Result[Unit, Str]
    Generates 16 cryptographically random bytes, encodes as hex.

  demo_hmac() -> Result[Unit, Str]
    Computes HMAC-SHA256 of "Hello World" with key "secret".

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
   The FFI tier's random_bytes() provides CSPRNG via OpenSSL RAND_bytes.
4. Ed25519 Stubs: Full Ed25519 requires Layer 2 (big integer math) completion.
5. No Constant-Time Guarantees: Pure-XIOM implementations are educational grade.
6. No Side-Channel Protection: Not hardened against timing or power analysis.
7. FFI Tier Pending: The root crypto.xi FFI bindings depend on Layer 0 runtime
   intrinsics (@axiom_vec_to_ptr, @axiom_alloc, @axiom_read_u8, @axiom_free).
   Until these are available, the FFI code paths are stubbed and return zeros.

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
