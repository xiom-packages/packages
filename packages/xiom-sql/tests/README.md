# tests/README.md -- xiom.sql conformance test suite

## Error Discovered and Fixed

### P001 at sql.xi:20 -- Duplicate visibility modifier

**Original line (20):**
```
pub pub fn close(db: &Database) -> Int {
```

**Error:** `xiom --diagnostics=json` reported:
```
error[P001]: 20:5: expected declaration, found 'pub'
```

The `close` function had two `pub` keywords (`pub pub`), which is an invalid visibility modifier. XIOM's parser expects exactly one access modifier before `fn`. The second `pub` was interpreted as the start of a new declaration inside a function scope where declarations are not valid.

**Fix applied:** Changed `pub pub fn close(...)` to `pub fn close(...)`.

### Additional improvements

- Added `requires` contracts to all three public functions:
  - `open(path)` -- `requires: path.len() > 0`
  - `execute(db, sql)` -- `requires: sql.len() > 0`
  - `close(db)` -- `requires: db.handle >= 0`
- File now compiles cleanly on `xiom v0.49.7`.

## Test Suite

`test_conformance.xi` covers:
- `open` returns Database with correct handle/path
- `execute` returns 0 for various SQL inputs (MVP stub)
- `close` returns 0, including after execute
- Database handle is non-negative
- `#[derive(Clone)]` preserves handle and path

Run with:
```
xiom --run tests/test_conformance.xi
```
