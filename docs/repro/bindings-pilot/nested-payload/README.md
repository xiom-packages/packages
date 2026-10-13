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

## Workaround shipped (xiom.sqlite 0.4.0)

`query_one` returns a flat `RowOutcome { has_row: Bool; row: SqliteRow; }`
instead of `Result[Option[SqliteRow]]`; consumers read `out.row` like any
plain struct field.  The repaired `Result[Option[..]]` shape can be restored
once the compiler fix lands (re-test from this bundle).
