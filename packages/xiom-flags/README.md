# xiom-flags

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Command-line flag and argument parsing for XIOM CLI programs.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `flags/parser` | Parses command-line arguments into typed values |
| `flags/subcommand` | Nested subcommand dispatch and help generation |
| `flags/env` | Falls back to environment variables for missing flags |
