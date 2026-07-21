# AUDIT.md — xiom-grpc

## Compiler Compatibility
- **Compiler version:** xiom v0.11.0 (XIOM v0.45.3)
- **Status:** All `.xi` files compile successfully to LLVM IR when compiled together.

## Files
| File | Status | Notes |
|------|--------|-------|
| `grpc.xi` | ✓ Compiles | FFI declarations (no bodies); `pub const` works (GAP-3) |
| `src/types.xi` | ✓ Compiles | Fixed `.to_owned()` → `.clone()`; `pub const` declared successfully |
| `src/client.xi` | ✓ Compiles (multi-file only) | Requires `use xiom.grpc;` and compilation with `grpc.xi` |
| `src/server.xi` | ✓ Compiles (alone or multi-file) | Requires `use xiom.grpc.types.GrpcServer;` |
| `tests/test_grpc.xi` | Not tested separately | Requires `use xiom.test` (stdlib) |

## Fixes Applied
| File | Issue | Fix |
|------|-------|-----|
| `src/types.xi` | `.to_owned()` not available on `Str` | Changed to `.clone()` |
| `src/client.xi` | `init`, `shutdown`, etc. undefined | Added `use xiom.grpc;` |
| `src/client.xi` | `Vec[T]::with_capacity(n)` not available | Changed to `Vec[T]::new()` |
| `src/client.xi` | `Vec[UInt8]` len/push failures in cross-module context | Unified on `Vec[Int]` in `grpc.xi` |
| `src/client.xi` | `match Ok(bytes)` pattern failed `.len()` resolution | Used `raw.is_ok()` + `raw.unwrap()` with explicit type annotations |
| `src/client.xi` | `raw.unwrap_err()` not available on `Result` | Used string literal `Err("...")` for error paths |
| `src/server.xi` | `GrpcServer` type unknown | Added `use xiom.grpc.types.GrpcServer;` |
| `grpc.xi` | `Channel`/`Call` type aliases caused type mismatches | Changed FFI signatures to use `Int` directly |

## Compiler Gaps Found
| Gap | Description | Impact | Workaround |
|-----|-------------|--------|------------|
| `to_owned()` | `.to_owned()` method not available on `Str` | types.xi line 58 | Use `.clone()` instead |
| `with_capacity` | `Vec[T]::with_capacity(n)` not available | client.xi | Use `Vec[T]::new()` instead |
| `Vec[UInt8]` cross-module | `Vec[UInt8]` methods fail when type originates from a different module | client.xi | Unify on `Vec[Int]` across modules |
| `match` + FFI return | `match Ok(bytes)` pattern fails `.len()` resolution when Ok variant comes from FFI-declared function | client.xi | Use `is_ok()` + `unwrap()` with explicit type annotation |
| `unwrap_err` | `Result.unwrap_err()` not callable from user code | client.xi | Use `Err("...")` literal for error cases |

## System Dependencies
| Dependency | Required | Install |
|-----------|----------|---------|
| gRPC C Core | Yes (runtime FFI) | `apt install libgrpc-dev` (Linux), `brew install grpc` (macOS), vcpkg (Windows) |
| libprotobuf | Yes (gRPC dependency) | Included with gRPC |
| Link flags | `-l grpc -l gpr -l protobuf` | Pass via `--link` |

## Notes
- `grpc.xi` uses FFI declarations without function bodies. Linking requires gRPC C Core.
- All client/server functions compile successfully in multi-file mode (`xiom grpc.xi src/types.xi src/client.xi src/server.xi`).
- `pub const` declarations in `src/types.xi` compile without errors (GAP-3 confirmed closed).
