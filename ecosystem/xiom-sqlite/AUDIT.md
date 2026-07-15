# AUDIT: xiom-sqlite

## Status
All 6 source files compile on xiomc v0.45.3 with stubbed FFI functions. The production FFI implementation (extern "C" blocks connecting to libsqlite3 via ffi_bridge.c) has been replaced with compile-safe stubs.

## System Library Dependencies
- **libsqlite3** (SQLite >= 3.31.0 recommended)
  - Windows: `vcpkg install sqlite3` or `pacman -S mingw-w64-x86_64-sqlite3`
  - Linux: `apt install libsqlite3-dev` (Debian) / `dnf install sqlite-devel` (Fedora)
  - macOS: ships with `/usr/lib/libsqlite3.dylib`, or `brew install sqlite`
  - Link flag: `-l sqlite3`

## FFI Bridge Dependencies
- **ffi_bridge.c**: Provides `xiom_alloc`, `xiom_free_ptr`, `xiom_read_byte`, `xiom_write_byte`, `xiom_str_to_cstr`, `xiom_free_cstr`, `xiom_str_data`
- **Runtime functions needed**: `to_char(Int) -> Char` for byte-to-character conversion (core builtin, available)

## Known Gaps
1. **FFI bridge not linked**: All connection functions (`sqlite_open`, `sqlite_execute`, `sqlite_query`, etc.) are stubs that return errors. Real functionality requires compiling and linking ffi_bridge.c with libsqlite3.
2. **Str-to-C-string conversion**: The `xiom_str_to_cstr` bridge function requires the ffi_bridge.c to convert XIOM `Str` to null-terminated C strings. Without the bridge, C string construction is not possible in pure XIOM.
3. **derive[Clone] removed**: Removed from `SqliteValue`, `SqliteRow`, `SqliteResult`, `SqliteError`, and `SqliteValueKind` (enum). Manual clone functions provided instead (`clone_sqlite_value`, `clone_sqlite_row`). The `derive[Clone]` on enums with `Vec` fields and on structs containing `Str` fields was not supported by the compiler.
4. **Enum variant construction**: Fixed `Integer(value: val)` to `Integer(val)` — the `field:` syntax is for declarations, not construction.

## Files Modified
- `src/types.xi` — Removed derive[Clone], added manual clone functions, fixed enum variant construction syntax
- `src/schema.xi` — No changes needed (compiled clean)
- `src/connection.xi` — Replaced FFI implementation with stubs, removed native.* calls
- `src/query.xi` — No changes needed (compiled clean)
- `src/migration.xi` — Added use imports, replaced .clone() calls with clone_migration()
- `src/demo.xi` — Replaced with stubs (FFI-dependent)

## Restoring Production FFI
To restore the production FFI implementation, reapply the original `connection.xi` with:
1. Proper `extern "C"` declarations using `Int` for pointer parameters
2. Link `ffi_bridge.c` and `libsqlite3`
3. Use `xiom_str_data(s: Str) -> Int` to get raw string pointer
