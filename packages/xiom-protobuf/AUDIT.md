# AUDIT.md — xiom-protobuf

## Compiler Compatibility
- **Compiler version:** xiom v0.11.0 (XIOM v0.45.3)
- **Status:** All `.xi` files compile successfully to LLVM IR.

## Files
| File | Status | Notes |
|------|--------|-------|
| `src/schema.xi` | ✓ Compiles | Fixed `.to_owned()` → `.clone()` |
| `protobuf.xi` | ✓ Compiles | `type ProtoValue = enum{}` syntax works (GAP-9) |
| `tests/test_protobuf.xi` | Not tested separately | Requires `use xiom.test` (stdlib) |

## Compiler Gaps Found
| Gap | Description | Impact | Workaround |
|-----|-------------|--------|------------|
| `to_owned()` | `.to_owned()` method not available on `Str` | schema.xi line 105 | Use `.clone()` instead |
| `with_capacity` | `Vec[T]::with_capacity(n)` not available | None in this package | Use `Vec[T]::new()` instead |

## System Dependencies
| Dependency | Required | Install |
|-----------|----------|---------|
| libprotobuf | Yes (runtime FFI) | `apt install libprotobuf-dev` (Linux), `brew install protobuf` (macOS), vcpkg (Windows) |
| Link flags | `-l protobuf` | Pass via `--link protobuf` |

## Notes
- `protobuf.xi` uses FFI declarations (no function bodies). Actual linking requires libprotobuf at link time.
- The `type ProtoValue = enum{}` variant syntax compiles correctly — GAP-9 is confirmed closed.
- Tests reference `xiom.test` stdlib module. Not verified independently.
