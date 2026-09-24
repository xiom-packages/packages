# xiom.quantum -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.quantum` (`src/quantum.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only; the module itself imports `xiom.convert` (the
`Int -> Float64` conversion) and the exported constants below; the tests use
`xiom.test`, `xiom.io`, `xiom.math` and the module itself.

## 1. Scope

Introductory closed-form quantum formulas for one scalar quantity at a time:

- de Broglie wavelength of a massive particle (m),
- photon momentum from photon energy (kg*m/s),
- hydrogen level energies (eV) and transition energies (eV),
- Balmer and Lyman vacuum wavelengths (nm),
- two reference lengths: the electron Compton wavelength and the Bohr radius.

Everything is `Float64` arithmetic; the principal quantum number is an `Int`.
Every function is a free function; the module is deterministic, allocation-
free and total (invalid inputs map to `0.0`, never to an error or a panic).

## 2. Non-goals

- No linear algebra: no state vectors, qubits, operators, matrices, density
  matrices, complex amplitudes, tunneling probabilities or entanglement
  measures (the former placeholder's scope).
- No spectroscopy conversions: wavelength/frequency/wavenumber/photon-energy
  conversion belongs to `xiom.spectroscopy` and is deliberately not
  duplicated here.
- No selection rules, line intensities, lifetimes, fine structure, spin,
  Zeeman/Stark effects, multi-electron atoms or Z scaling (hydrogen-like
  Z = 1 only).
- No vectors, `Vec[Float64]` (unsupported in this build), structs, methods,
  lambdas, I/O, randomness, or any FFI of this package.

## 3. Constants

Exported as `pub const`:

| Constant | Value | Unit | Meaning |
|---|---|---|---|
| `QUANTUM_H_J_S` | `6.62607015e-34` | J*s | Planck constant `h` (exact by the 2019 SI definition) |
| `QUANTUM_C_M_PER_S` | `299792458.0` | m/s | speed of light in vacuum `c` (exact by the SI definition of the metre) |
| `QUANTUM_R_INF_PER_M` | `1.0973731568160e7` | 1/m | Rydberg constant `R_inf` for infinite nuclear mass (CODATA 2018) |
| `QUANTUM_E1_EV` | `13.605693122994` | eV | hydrogen ground-state energy magnitude `E1 = R_inf*h*c` (CODATA 2018) |
| `QUANTUM_M_E_KG` | `9.1093837015e-31` | kg | electron rest mass `m_e` (CODATA 2018) |

`QUANTUM_M_E_KG` is exported for callers of `quantum_de_broglie_m`; the
module itself does not use a mass constant (mass is always an argument).

Unit conversion factors used by the formulas:

| Factor | Meaning |
|---|---|
| `1e9` | reciprocal nanometres per metre (`1e9 / lambda_m` is the wavelength in nm) |

## 4. Guard rules

Invalid inputs are total: they return the sentinel `0.0` and are never errors
or panics. The rules are module-wide and pinned by the conformance suite.

| Rule | Argument | Condition | Effect | Applies to |
|---|---|---|---|---|
| G1 | scalar input | `<= 0` | `0.0` | `quantum_de_broglie_m` (`mass_kg <= 0` or `velocity_m_s <= 0`), `quantum_photon_momentum` (`energy_j <= 0`) |
| G2 | `n` | `n < 1` | `0.0` | `quantum_hydrogen_energy_ev` |
| G2 | `n_from`, `n_to` | `n_to < 1` or `n_from <= n_to` | `0.0` | `quantum_hydrogen_transition_ev` |
| G2 | `n` | `n <= 2` | `0.0` | `quantum_balmer_wavelength_nm` |
| G2 | `n` | `n <= 1` | `0.0` | `quantum_lyman_wavelength_nm` |

Consequences worth stating explicitly:

- **No division by zero can occur.** The two wavelength guards reject exactly
  the inputs that would zero the denominator (Balmer `n = 2`, Lyman `n = 1`);
  scalar guards reject the zero divisors in de Broglie and photon momentum.
- **A real zero is not distinguishable from a rejected input** in the return
  value; callers who need the distinction must validate first.
- **Transition direction is required.** `quantum_hydrogen_transition_ev`
  accepts only `n_from > n_to >= 1` and returns a positive photon energy;
  upward or equal transitions are rejected with `0.0` rather than returning a
  negative value.
- All valid inputs, however large, are accepted and computed with IEEE-754
  double arithmetic; no clamping or saturation is applied.

## 5. Formulas

Let `h = QUANTUM_H_J_S`, `c = QUANTUM_C_M_PER_S`,
`R = QUANTUM_R_INF_PER_M`, `E1 = QUANTUM_E1_EV`.

| Function | Formula | Notes |
|---|---|---|
| `quantum_de_broglie_m(mass_kg, velocity_m_s)` | `h / (mass_kg * velocity_m_s)` | `lambda = h/p`; G1 |
| `quantum_photon_momentum(energy_j)` | `energy_j / c` | `p = E/c`; G1 |
| `quantum_hydrogen_energy_ev(n)` | `-E1 / (nf * nf)` | `nf = float(n)`; Bohr model; result negative; G2 |
| `quantum_hydrogen_transition_ev(n_from, n_to)` | `E1 * (1/(nt*nt) - 1/(nf*nf))` | positive emitted photon; requires `n_from > n_to >= 1`; G2 |
| `quantum_balmer_wavelength_nm(n)` | `1e9 / (R * (0.25 - 1/(nf*nf)))` | `n_to = 2`; `0.25 = 1/2^2`; G2 |
| `quantum_lyman_wavelength_nm(n)` | `1e9 / (R * (1 - 1/(nf*nf)))` | `n_to = 1`; G2 |
| `quantum_compton_wavelength_m()` | `2.42631023867e-12` | CODATA 2018 value pinned as the literal |
| `quantum_rbohr_m()` | `5.29177210903e-11` | CODATA 2018 value pinned as the literal |

where `nf = xiom.convert.int_to_float(n)` and `nt =
xiom.convert.int_to_float(n_to)`.

Rounding rule: operations are performed left to right exactly as written in
the table (the same order the implementation uses), in IEEE-754 double
precision. The `Int -> Float64` conversion is exact for every `|n| <= 2^53`;
larger `n` are accepted and converted by the standard rounding rule. No
intermediate rounding beyond double precision is specified.

### 5.1 Pinned values

| Quantity | Value |
|---|---|
| de Broglie, electron (`m_e`) at `1e6` m/s | `7.2738951032537087e-10` m |
| momentum of a `1 eV` photon (`1.602176634e-19` J) | `5.3442859926783079e-28` kg*m/s |
| `E1` | `-13.605693122994` eV |
| `E2` | `-3.4014232807485` eV |
| `E3` | `-1.5117436803326667` eV |
| transition `2 -> 1` | `10.2042698422455` eV |
| transition `3 -> 2` | `1.8896796004158334` eV |
| transition `3 -> 1` | `12.093949442661332` eV |
| Balmer `n = 3` (H-alpha) | `656.1122764193188` nm |
| Balmer `n = 4` | `486.0090936439399` nm |
| Balmer `n = 5` | `433.9366907535178` nm |
| Lyman `n = 2` (Lyman-alpha) | `121.502273410985` nm |
| Lyman `n = 3` | `102.5175431905186` nm |
| Lyman `n = 4` | `97.201818728788` nm |
| Compton wavelength | `2.42631023867e-12` m |
| Bohr radius | `5.29177210903e-11` m |

## 6. Test plan

Suite: `tests/test_conformance.xi`, module `quantum_tests`, 18 checks run
explicitly from `main` (no `Vec[fn]` dispatch). Exit code is the number of
failed checks, so a green run exits 0.

Tolerance (relative, no absolute floor), documented in the test file:

```
q_close(a, b) := fabs(a - b) <= 1e-9 * fabs(b)
```

`b` is the pinned expected value and `fabs` is `xiom.math.abs_float`.
Expected `0.0` values must therefore be exactly `0.0`, which holds because
every guard returns the literal `0.0`; an assertion `q_close(x, 0.0)` proves
the guard fired, not merely that `x` is small.

| Check | Proves |
|---|---|
| `t01_de_broglie_electron` | electron at `1e6` m/s -> `7.2738951032537087e-10` m; doubling velocity halves the wavelength; 1 kg at 1 m/s -> `h` |
| `t02_de_broglie_guards` | G1: zero/negative mass or velocity -> exactly `0.0` |
| `t03_photon_momentum_1ev` | 1 eV -> `5.3442859926783079e-28`; doubling/halving energy doubles/halves momentum |
| `t04_photon_momentum_guards` | G1: zero/negative energy -> exactly `0.0` |
| `t05_hydrogen_levels` | `E1`, `E2`, `E3`, `E10` pinned to the `-E1/n^2` decimals |
| `t06_hydrogen_energy_guards` | G2: `n` = 0, -1, -100 -> exactly `0.0` |
| `t07_transition_2to1` | `2->1`, `3->1`, `3->2` pinned |
| `t08_transition_guards` | G2: `n_from == n_to`, upward `2->3`, `3->5`, `n_to < 1`, negatives -> exactly `0.0` |
| `t09_balmer_halpha` | Balmer `n = 3, 4, 5` pinned (H-alpha `656.1122764193188` nm) |
| `t10_balmer_guards` | G2: `n <= 2` (including the `n = 2` division-by-zero case) -> exactly `0.0` |
| `t11_lyman_alpha` | Lyman `n = 2, 3, 4` pinned (Lyman-alpha `121.502273410985` nm) |
| `t12_lyman_guards` | G2: `n <= 1` (including `n = 1`) -> exactly `0.0` |
| `t13_reference_lengths` | `quantum_compton_wavelength_m()` and `quantum_rbohr_m()` pinned |
| `t14_constants_pinned` | all five exported constants pinned to their documented literals |
| `t15_hydrogen_identity` | `E_n = E1/n^2` for `n = 1..5`; `transition = E(n_from) - E(n_to)` |
| `t16_rydberg_consistency` | `1/(lambda*1e-9) = R*(...)` for Balmer-alpha and Lyman-alpha; `h*c/(lambda*1e-9)/eV` equals the matching transition energy |
| `t17_formula_identity` | every formula reproduced from `h/c/R/E1` literals defined inside the test (independent of the module constants) |
| `t18_series_ordering` | wavelength strictly decreases with `n` in both series and Lyman lies below Balmer |

`t16` and `t17` use `h`, `c`, `R`, `E1` and `1.602176634e-19` as local
literals so the identities are checked against an independent statement of
the physics, not against the module's own constants.

## 7. Semantics notes

- **Signs.** Hydrogen level energies are negative; transition energies are
  positive (emitted photon) and defined only for `n_from > n_to`.
  `quantum_de_broglie_m` is positive for valid inputs;
  `quantum_photon_momentum` is positive for valid inputs.
- **Infinitely heavy nucleus.** `R_inf` and `E1` are the infinite-nuclear-mass
  values. The computed Lyman-alpha line is `121.5023` nm and H-alpha is
  `656.1123` nm; the experimental hydrogen lines (`121.567` nm, `656.28` nm
  H-alpha in air) use the reduced-mass Rydberg constant `R_H` and, for
  H-alpha, an air wavelength. The module pins `R_inf` deliberately; a
  reduced-mass variant is out of scope.
- **Approach to series limits.** As `n` grows, the Balmer wavelength
  approaches `1e9/(R/4) = 364.506820232955` nm and the Lyman wavelength
  approaches `1e9/R = 91.126705058239` nm. `Int` values are converted to `Float64` exactly for
  all practical `n`.
- **Naming.** `_m`, `_nm`, `_ev` are the output units on the function names;
  parameter names carry the input units (`mass_kg`, `velocity_m_s`,
  `energy_j`). `n` is an `Int` principal quantum number. No unit parsing or
  formatting is provided.
- **Independence.** The library module imports only `xiom.convert` (stdlib);
  the tests import `xiom.test`, `xiom.io`, `xiom.math` and `xiom.quantum`.

## 8. Verification

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.quantum
```

Green iff the tail is
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)` and the suite prints
`xiom.quantum: all tests passed`.
