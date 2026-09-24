# xiom.chemistry

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Chemical formula parsing with molar masses and mass fractions
> (integer mg/mol).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.compare.str_compare`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.chemistry` parses molecular formula strings -- element symbols with an
optional lowercase second letter, optional decimal counts (implicit 1) and
nested parentheses with optional counts -- and computes:

- the molar mass of a formula as an exact integer sum in whole mg/mol
  (`H2O` -> 18015);
- the distinct elements of a formula in first-seen order (`Ca(OH)2` ->
  `["Ca", "O", "H"]`);
- the mass fraction of one element in permille, truncated (`H2O`: H -> 111,
  O -> 888).

The built-in element table holds 27 elements and no FFI is used. Every error
is reported as `Err("chemistry: ...")` with a stable message catalog (see
`SPEC.md`).

## API

| Function | Returns | Description |
|---|---|---|
| `chem_symbols()` | `Vec[Str]` | Every table symbol, sorted byte-wise (27 entries). |
| `chem_element_mass_mg(symbol)` | `Option[Int]` | Whole mg/mol for an exact, case-sensitive symbol (`H`=1008, `C`=12011, `O`=15999, `Na`=22990, `Cl`=35453, `Fe`=55845); `None` when unknown or mis-cased. |
| `chem_molar_mass_mg_per_mol(formula)` | `Result[Int, Str]` | Exact integer molar mass in mg/mol; `Err("chemistry: ...")` on malformed input. |
| `chem_formula_elements(formula)` | `Result[Vec[Str], Str]` | Distinct symbols in first-seen order (deduplicated across groups). |
| `chem_mass_fraction_permille(formula, symbol)` | `Result[Int, Str]` | `atoms(symbol) * mass(symbol) * 1000 / total`, truncated; `Err` when the symbol is absent or the formula is malformed. |

## Usage

```xi
use xiom.chemistry;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  let m = chem_molar_mass_mg_per_mol("Ca(OH)2");
  if m.is_ok {
    io.println(convert.int_to_string(m.value));        // 74092
  }
  let f = chem_mass_fraction_permille("H2O", "H");
  if f.is_ok {
    io.println(convert.int_to_string(f.value));        // 111
  }
  match chem_formula_elements("C12H22O11") {
    Ok(v) => {
      let n: Int = v.len();
      io.println(convert.int_to_string(n));            // 3
    },
    Err(_) => {},
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.chemistry
```

Expected tail: 25 `[PASS]` lines, `xiom.chemistry: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- Molar masses are whole mg/mol: each element's standard molar mass is rounded
  half-up once to the nearest whole mg/mol (table and rounding rules in
  `SPEC.md`). Totals are then exact integer sums; no further rounding.
- Mass fractions are truncated integer permille values and may not sum to
  exactly 1000.
- Only the 27 table elements exist; unknown symbols (including real elements
  outside the table, e.g. `Co`) are errors. Nothing is case-folded (`CL` is an
  error).
- No isotopes, charges, hydrate dots (`CuSO4·5H2O`), state markers,
  concentrations or reaction balancing -- formula arithmetic only.
- Whitespace is not part of the grammar and is rejected anywhere in a formula.
- A count must be at least 1 (`H0` is an error); leading zeros are accepted
  (`H01` counts as one H).
- Compiler note: `Vec[Str]` element reads are bound to typed locals before use
  and compared via `str_compare` (BUG 17 family in `SPEC.md`).

See `SPEC.md` for the grammar, the full element table, the error catalog and
the test plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
