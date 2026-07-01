# axiom:libsodium — Secure Cryptography

libsodium FFI bindings for AXIOM. Provides:
- Secret-key encryption (secretbox)
- Public-key encryption (box)
- Digital signatures
- Generic hashing (BLAKE2b)
- Password hashing (Argon2)
- Secure random number generation

## Example

```axiom
use axiom.libsodium;

fn main() -> Int {
  init()?;
  let key = random_bytes(SECRETBOX_KEYBYTES);
  let nonce = random_bytes(SECRETBOX_NONCEBYTES);
  let encrypted = secretbox_encrypt("hello", key, nonce)?;
  let decrypted = secretbox_decrypt(encrypted, key, nonce)?;
  return 0;
}
```
