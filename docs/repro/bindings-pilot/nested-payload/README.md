# nested-payload -- enum payload nested in an enum payload corrupts struct-with-Vec values (B-26, v0.64.4)

Found while building the `xiom.sqlite` 0.4.0 driver (`SqlDriver.query_one`).
The intended API returned `Result[Option[SqliteRow], SqliteError]` (a row
plus a "no row" marker).  Extracting the row from that nested payload
corrupted it: the `columns` vector length read as a pointer-like garbage
value (observed `140700400781437` / `140702023260877` in the package suite,
`9` in this minimal probe), and using the corrupted row crashed the binary
with an access violation (`0xC0000005`).

## Shape

```xiom
pub type Bag = { items: Vec[Int]; }

fn nested_ok() -> Result[Option[Bag], Str] {
  return Ok(Some(bag_new()));           // enum payload in enum payload
}

let r = nested_ok();
let opt = r.value;                      // Result payload  -> Option[Bag]
let bag: Bag = opt.value;               // Option payload  -> Bag (CORRUPT)
let n = bag.items.len();                // reads a pointer-like value, not 2
```

Controls on the same build:

```xiom
pub type BagOutcome = { has: Bool; bag: Bag; }
fn flat_ok() -> Result[BagOutcome, Str] { ... }   // struct payload -> GREEN
fn opt_ok() -> Option[Bag] { ... }                // single-level Option -> GREEN
```

## Run

Pure XIOM -- no C source, no DLL:

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi
```

## Result (2026-10-13, v0.64.4; identical across two consecutive runs)

```
=== nested-payload probe (v0.64.4) ===
nested Result[Option[Bag]]: items.len=9 (expected 2)
flat Result[BagOutcome]: items.len=2 (expected 2)
single-level Option[Bag]: items.len=2 (expected 2)
failures=1
exit code: 1
```

RED: extracted nested payload reads a bogus length (`9`, pointer-like values
in the package context) and crashes when the Vec is used.  GREEN: flat
struct payload and single-level `Option[Bag]` extraction are correct.

## Shape matrix (`matrix.xi`, 3 fresh builds, 2026-10-13, v0.64.4)

| Shape | Result |
|-------|--------|
| D `Result[BagFlat]` (flat struct) | GREEN 3/3 -- tag=2, items.len=2 |
| E `Option[Bag]` (single level) | GREEN 3/3 |
| B `Result[Option[Int]]` (nested scalar) | GREEN 3/3 -- value=41 |
| C `Option[Result[Bag]]` (inverted nesting) | GREEN 3/3 |
| F `Result[Option[Vec[Int]]]` (nested bare Vec) | GREEN 3/3 -- len=2 |
| A2 `Result[Option[BagV]]` (nested struct-with-Vec, no scalar) | GREEN 3/3 in `matrix.xi`; **RED 4/4 in `probe.xi`** (items.len=9) |
| A `Result[Option[Bag]]` (nested struct-with-Vec + leading Int tag) | **ACCESS VIOLATION 3/3** (0xC0000005) |

Reading:

- The corruption needs a nested enum payload whose value is a
  struct-with-Vec (`Result[Option[..]]`); nested scalar and nested bare
  `Vec` stay green, as do flat and single-level payloads.
- The exact behavior depends on the surrounding **module content**: the
  same no-scalar nested shape is RED in `probe.xi` (4/4 builds) and GREEN
  in `matrix.xi` (3/3 builds) -- a source/build-sensitive miscompilation
  (B-01 family signature).
- Adding a leading `Int` field to the nested struct makes it a reliable
  access violation at the extraction/use step (`matrix.xi` shape A, 3/3);
  the crash lands between the shape header and the first field read.

`matrix.xi` shape A is the reliable red artifact; `probe.xi` stays the
minimal RED for the source-sensitivity flip.

## Workaround shipped (xiom.sqlite 0.4.0)

`query_one` returns a flat `RowOutcome { has_row: Bool; row: SqliteRow; }`
instead of `Result[Option[SqliteRow]]`; consumers read `out.row` like any
plain struct field.  The repaired `Result[Option[..]]` shape can be restored
once the compiler fix lands (re-test from this bundle).
