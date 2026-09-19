# xiom.pgp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** OpenPGP encryption, signing, and keyring operations.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `keys` | PGP key generation, import, and export |
| `encrypt` | Symmetric and public-key message encryption |
| `sign` | Message signing and signature verification |
| `armor` | ASCII-armored packet encoding/decoding |
