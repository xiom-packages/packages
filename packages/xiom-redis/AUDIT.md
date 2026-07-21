# AUDIT: xiom-redis

## Status
All 3 source files compile on xiomc v0.45.3 with stubbed FFI functions.

## System Library Dependencies
- **hiredis** (Redis C client library)
  - Windows: `vcpkg install hiredis`
  - Linux: `apt install libhiredis-dev` (Debian) / `dnf install hiredis-devel` (Fedora)
  - macOS: `brew install hiredis`
  - Link flag: `-l hiredis`
- **Redis server**: >= 5.0 recommended (Redis Stack for all modules)

## Known Gaps
1. **hiredis FFI not linked**: All functions in `redis.xi` are stubs returning errors. Real functionality requires hiredis FFI bindings.
2. **Forward declarations removed**: Original `redis.xi` had function signatures without bodies. All functions now have stub bodies.
3. **client.xi simplified**: Made self-contained with inline stubs. Original wrapped `redis.xi` functions but cross-module imports fail in standalone compilation.
4. **`set` function renamed**: The local stub was named `rset` (and `rdel`) to avoid conflict with XIOM built-in `Set` type. Original names `set`/`del` were shadowed.
5. **test_redis.xi**: Simplified to self-contained test. Uses inline connect stub.

## Files Modified
- `redis.xi` — Added stub bodies to all forward-declared functions
- `src/client.xi` — Made self-contained, renamed shadowed `set`/`del` to `rset`/`rdel`
- `tests/test_redis.xi` — Made self-contained, replaced `let` with `var`, added inline stub

## Restoring Production FFI
To restore production functionality:
1. Implement hiredis C FFI bindings (`redisConnect`, `redisCommand`, `freeReplyObject`, etc.) via `extern "C"` blocks
2. Link against `hiredis` at compile time
3. Re-enable cross-module dependency between `redis.xi` and `client.xi`
