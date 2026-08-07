# xiom-password

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Password hashing, validation, and policy enforcement.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `hash` | Password hashing (argon2/bcrypt-style) |
| `verify` | Constant-time password verification |
| `policy` | Complexity and strength rules |
| `gen` | Secure random password generation |
