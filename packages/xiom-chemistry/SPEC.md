# xiom.chemistry -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI. All masses are integers in
whole milligrams per mole (mg/mol).

## 1. Scope

The module parses molecular formula strings built from a fixed 27-element
table, element counts (implicit 1), and nested parentheses with optional
counts, and exposes:

1. `chem_symbols() -> Vec[Str]` -- the table's element symbols, sorted.
2. `chem_element_mass_mg(symbol) -> Option[Int]` -- one element's mg/mol.
3. `chem_molar_mass_mg_per_mol(formula) -> Result[Int, Str]` -- exact integer
   molar mass.
4. `chem_formula_elements(formula) -> Result[Vec[Str], Str]` -- distinct
   symbols in first-seen order.
5. `chem_mass_fraction_permille(formula, symbol) -> Result[Int, Str]` --
   truncated permille mass fraction.

Molar masses are integer by construction: each element mass is rounded once
(section 4), and formulas are computed with integer addition and
multiplication only.

## 2. Grammar

```
formula    := sequence
sequence   := item*
item       := group | atom
group      := "(" sequence ")" count?
atom       := symbol count?
symbol     := upper lower?
count      := digit+            (numeric value >= 1)
upper      := "A".."Z"
lower      := "a".."z"
digit      := "0".."9"
```

Notes:

- The full input must parse; nothing may remain (no trailing junk). Whitespace
  is not part of the grammar: a space, tab, newline or any other byte that is
  not part of a token is rejected.
- `symbol` is exactly one uppercase letter plus at most one lowercase letter;
  a second lowercase letter or a lowercase symbol start is an unexpected
  character. Symbols are case-sensitive (`Cl` is chlorine, `CL` is an error).
- `count` is one or more ASCII digits; an absent count means 1; a numeric
  value of 0 is rejected. Leading zeros are accepted and ignored
  (`H01` = one H atom, `C012` = 12 C atoms).
- Groups nest arbitrarily. An empty group (`()`) is rejected.
- Parentheses and counts may be adjacent in any order the grammar allows
  (`(OH)2`, `((OH)2)`, `(H2O)3CO2`).

## 3. Semantics

- **Molar mass**: `sum(mass(atom) * atom_count * enclosing_group_counts)` over
  every atom occurrence, computed as integers in input order. Groups are
  handled by pushing the running total when `(` opens and applying
  `saved + inner * count` when `)` closes (two linear scans, no AST).
- **Elements**: every symbol that occurs at least once, each exactly once,
  ordered by its first textual occurrence in the left-to-right scan.
  Deduplication compares through `str_compare`; a symbol appearing before and
  inside a group is still reported once, at its first position (`H(H)2` ->
  `["H"]`).
- **Mass fraction**: `atoms(symbol) * mass(symbol) * 1000 / total`, where
  `atoms` counts the element's atom occurrences (group counts included) and
  `total` is the formula's molar mass. The division is integer division on
  non-negative values, i.e. the result is truncated toward zero (the
  mathematical floor here). Results are in permille (parts per thousand) and
  need not sum to 1000.
- **Absent symbol**: if the requested symbol does not occur in the formula,
  `chem_mass_fraction_permille` returns an error (not 0).

## 4. Element table and rounding

Each entry's source value is its standard molar mass in g/mol; the stored
value is that number times 1000 with the standard half-up rounding to the
nearest whole milligram:

| Symbol | Source (g/mol) | Stored (mg/mol) |
|---|---|---|
| Ag | 107.868 | 107868 |
| Al | 26.982 | 26982 |
| Ar | 39.948 | 39948 |
| Au | 196.967 | 196967 |
| B | 10.81 | 10810 |
| Be | 9.012 | 9012 |
| C | 12.011 | 12011 |
| Ca | 40.078 | 40078 |
| Cl | 35.453 | 35453 |
| Cu | 63.546 | 63546 |
| F | 18.998 | 18998 |
| Fe | 55.845 | 55845 |
| H | 1.008 | 1008 |
| He | 4.0026 | 4003 |
| Hg | 200.592 | 200592 |
| K | 39.098 | 39098 |
| Li | 6.94 | 6940 |
| Mg | 24.305 | 24305 |
| N | 14.007 | 14007 |
| Na | 22.990 | 22990 |
| Ne | 20.180 | 20180 |
| O | 15.999 | 15999 |
| P | 30.974 | 30974 |
| Pb | 207.2 | 207200 |
| S | 32.06 | 32060 |
| Si | 28.085 | 28085 |
| Zn | 65.38 | 65380 |

Table order (and therefore `chem_symbols()` order) is byte-wise sorted:
Ag, Al, Ar, Au, B, Be, C, Ca, Cl, Cu, F, Fe, H, He, Hg, K, Li, Mg, N, Na,
Ne, O, P, Pb, S, Si, Zn.

Rounding rules:

1. One rounding per element, from the source g/mol to whole mg/mol, half-up.
2. No rounding afterwards: molar masses and mass-fraction numerators are exact
   integer arithmetic over the stored values.
3. A formula's molar mass is therefore `sum(stored_mass * count)` exactly;
   e.g. `H2O` = 2*1008 + 15999 = 18015 mg/mol.

## 5. Error catalog

Every failure is `Err` with a message prefixed `"chemistry: "`. Validation is
left to right; the first error encountered wins.

| Condition | Message |
|---|---|
| Empty formula (`""`) | `chemistry: empty formula` |
| Any byte that cannot start a token (including digits, lowercase, whitespace, punctuation) | `chemistry: unexpected character: <byte>` |
| Uppercase (+optional lowercase) symbol not in the table | `chemistry: unknown symbol: <symbol>` |
| `)` with no open group | `chemistry: unmatched ')'` |
| End of input with open groups | `chemistry: unclosed '('` |
| Group with no atoms (`()`) | `chemistry: empty group` |
| Digit run whose value is 0 (`H0`, `(H)0`) | `chemistry: invalid count` |
| `chem_mass_fraction_permille` with a symbol not present in the formula | `chemistry: symbol not present: <symbol>` |
| Defensive: zero total mass (unreachable for valid non-empty formulas) | `chemistry: zero molar mass` |

`chem_element_mass_mg` never errors; it returns `None` for unknown or
mis-cased symbols. `chem_symbols` never fails.

## 6. Test plan (tests/test_conformance.xi, 25 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | element masses H, C, O | `chem_element_mass_mg`: H=1008, C=12011, O=15999 |
| t2 | element masses Na, Cl, Fe | Na=22990, Cl=35453, Fe=55845 |
| t3 | unknown/mis-cased symbol | `None` for `"Xx"`, `""`, `"cl"`, `"CL"` |
| t4 | symbols sorted/unique | `chem_symbols().len() == 27`; strictly ascending under `str_compare` |
| t5 | symbols present+positive | H, C, O, Na, Cl, Fe appear; every table symbol has `Some(m)`, `m > 0` |
| t6 | H2O | 18015 = 2*1008 + 15999 |
| t7 | CO2 | 44009 = 12011 + 2*15999 |
| t8 | NaCl | 58443 = 22990 + 35453 |
| t9 | Ca(OH)2 | 74092 = 40078 + 2*(15999+1008) |
| t10 | C12H22O11 | 342297 = 12*12011 + 22*1008 + 11*15999 |
| t11 | multi-digit counts | Fe3O4=231531 (3*55845+4*15999), C60=720660 (60*12011) |
| t12 | nested parentheses | ((OH)2)=34014, (H2O)2=36030 |
| t13 | implicit count 1 | H2O1=18015, NaOH=39997, Fe=55845, NaCl1=58443 |
| t14 | lowercase second letter | Cl2=70906, C2=24022, Cl=35453 (vs C=12011) |
| t15 | unknown symbols | Err for `Xx2`, `Co2`, `H2Zz`, `NaCq` |
| t16 | unbalanced parens | Err for `Ca(OH2`, `(H2O`, `H2O)`, `)` |
| t17 | empty formula | Err for `""` |
| t18 | trailing junk / bad start | Err for `H2O!`, `2H2O`, `h2o`, `"H2O "`, `H2O#` |
| t19 | elements order/dedup | C12H22O11 -> [C,H,O]; H2O -> [H,O]; NaCl -> [Na,Cl] |
| t20 | elements groups/dedup | (NH4)2SO4 -> [N,H,S,O]; H(H)2 -> [H]; Ca(OH)2 -> [Ca,O,H] |
| t21 | elements errors | Err for `""`, `Xx`, `H2O)` |
| t22 | water permille | H=111 (2016000/18015), O=888 (15999000/18015) |
| t23 | more permille | NaCl Na=393, Cl=606; (OH)2 H=59, O=940 |
| t24 | sucrose permille | C12H22O11: C=421, H=64, O=514 |
| t25 | permille errors | Err for (H2O, Na), (NaCl, Xx), (`H2O!`, H), (H2O, `H2O`) |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## 7. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`,
  no `Vec[Float64]` (all masses are integers).
- `Ok`/`Err` are constructed only in the leaf helpers `_ok_int`, `_err_int`,
  `_ok_vec`, `_err_vec`; constructing results inline in other functions
  miscompiles in this compiler (the workaround proven by xiom-patch and
  xiom-scheduler).
- `Vec[Str]`/`Vec[Int]` element reads are bound to typed locals
  (`let e: Str = v[i];`, `let m: Int = masses[i];`) before use, and string
  equality always goes through `xiom.string.compare.str_compare` (BUG 17
  family: a direct element read can carry a bogus length, and `==` lowers to a
  pointer comparison).
- Byte classification uses `xiom.string.byte_at` compared against ASCII
  constants below 128 only.
- Matches cover `Some`/`None` and `Ok`/`Err` exhaustively (non-exhaustive
  match is a hard error); no `mut` patterns.
- The module takes no `&mut` reference to a Vec that is later returned as a
  `Result` payload; the symbols scan builds its own local `Vec[Str]`.
- Dependencies: `xiom.string` and `xiom.string.compare` (both in `xiom.std`);
  no `xiom.io` dependency in the library module.

## 8. Known limitations

- Integer mg/mol masses (max +/-0.5 mg/mol per element); no isotopes, no
  atomic-mass precision modes.
- 27 elements; real elements outside the table (e.g. Co, Ni) are unknown
  symbols. Adding elements requires extending both parallel table vectors and
  keeping them byte-wise sorted.
- No charges (`SO4^2-`), hydrate dots (`*`/`·`), state markers `(s)/(l)/(g)`,
  brackets `[]`, or coefficients (`2H2O`) -- those inputs are errors.
- No whitespace tolerance anywhere in a formula.
- Counts are plain integers; no ranges, fractions or scientific notation.
- Mass fractions are truncated integers, not exact rationals; they may not sum
  to 1000.
- No reaction balancing, stoichiometric matrices or yield calculations.
