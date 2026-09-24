# xiom.quantum

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** introductory quantum formulas on scalars: de Broglie wavelength,
> photon momentum, hydrogen energy levels and transitions, Balmer and Lyman
> vacuum wavelengths, plus two reference lengths (Compton wavelength, Bohr
> radius).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports `xiom.convert` for the `Int -> Float64` conversion and uses
> no FFI of its own). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.math`.

## What it is

`xiom.quantum` is a small, dependency-light module of eight free functions
built entirely from scalar `Float64` arithmetic and `Int` quantum numbers.
Every quantity is a plain double whose unit is spelled out in the function
name (`_m`, `_nm`, `_ev`, and `_kg`/`_m_s` in the parameter names), and every
formula is the textbook expression with explicitly documented edge cases. It
replaces the former placeholder (which promised qubit vectors, operators,
density matrices, tunneling, entanglement and FFI) with a precise, measured,
pure-XIOM core: introductory closed-form formulas only, no linear algebra, no
complex numbers, no C.

The exported constants are:

| Constant | Value | Unit | Meaning |
|---|---|---|---|
| `QUANTUM_H_J_S` | `6.62607015e-34` | J*s | Planck constant `h` (exact 2019 SI) |
| `QUANTUM_C_M_PER_S` | `299792458` | m/s | speed of light in vacuum `c` (exact SI) |
| `QUANTUM_R_INF_PER_M` | `1.0973731568160e7` | 1/m | Rydberg constant `R_inf` (CODATA 2018) |
| `QUANTUM_E1_EV` | `13.605693122994` | eV | hydrogen ground-state energy magnitude `E1` (CODATA 2018) |
| `QUANTUM_M_E_KG` | `9.1093837015e-31` | kg | electron rest mass `m_e` (CODATA 2018) |

See `SPEC.md` for the exact formulas, the guard rules and the test plan.

## Guard rules

Invalid inputs are total, not errors: they return `0.0` and never panic.

- **G1 non-positive scalar:** `quantum_de_broglie_m` returns `0.0` when
  `mass_kg <= 0` or `velocity_m_s <= 0`, and `quantum_photon_momentum`
  returns `0.0` when `energy_j <= 0`. No division by zero can occur.
- **G2 invalid quantum number:** `quantum_hydrogen_energy_ev` returns `0.0`
  for `n < 1`; `quantum_hydrogen_transition_ev` returns `0.0` unless
  `n_from > n_to >= 1`; `quantum_balmer_wavelength_nm` returns `0.0` for
  `n <= 2`; `quantum_lyman_wavelength_nm` returns `0.0` for `n <= 1`. The
  forbidden `n` values are exactly those that would divide by zero (Balmer
  `n = 2`, Lyman `n = 1`) or have no physical line (`n < 1`, upward
  transition).

A real zero is indistinguishable from a rejected input in the return value;
validate first when the distinction matters.

## API

| Function | Returns | Input unit | Output unit | Description |
|---|---|---|---|---|
| `quantum_de_broglie_m(mass_kg, velocity_m_s)` | `Float64` | kg, m/s | m | `h / (m*v)`; non-positive input -> `0.0` (G1). |
| `quantum_photon_momentum(energy_j)` | `Float64` | J | kg*m/s | `E / c`; `energy_j <= 0 -> 0.0` (G1). |
| `quantum_hydrogen_energy_ev(n)` | `Float64` | -- (Int) | eV | `-E1 / n^2` (negative); `n < 1 -> 0.0` (G2). |
| `quantum_hydrogen_transition_ev(n_from, n_to)` | `Float64` | -- (Int) | eV | `E1*(1/n_to^2 - 1/n_from^2)` (positive); `0.0` unless `n_from > n_to >= 1` (G2). |
| `quantum_balmer_wavelength_nm(n)` | `Float64` | -- (Int) | nm | `1e9 / (R_inf*(0.25 - 1/n^2))`; `n <= 2 -> 0.0` (G2). `n = 3` is H-alpha. |
| `quantum_lyman_wavelength_nm(n)` | `Float64` | -- (Int) | nm | `1e9 / (R_inf*(1 - 1/n^2))`; `n <= 1 -> 0.0` (G2). `n = 2` is Lyman-alpha. |
| `quantum_compton_wavelength_m()` | `Float64` | -- | m | `2.42631023867e-12` (CODATA 2018). |
| `quantum_rbohr_m()` | `Float64` | -- | m | `5.29177210903e-11` (CODATA 2018). |

Pinned examples (conformance-tested): an electron at `1e6` m/s has
`lambda = 7.2738951032537087e-10` m; a `1 eV` photon has
`p = 5.3442859926783079e-28` kg*m/s; `E1 = -13.605693122994` eV,
`E2 = -3.4014232807485` eV; the `2 -> 1` transition is `10.2042698422455` eV;
H-alpha (`n = 3`) is `656.1122764193188` nm; Lyman-alpha (`n = 2`) is
`121.502273410985` nm.

## Usage

```xi
use xiom.quantum;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  io.println("electron at 1e6 m/s: " +
    convert.float_to_string(quantum_de_broglie_m(QUANTUM_M_E_KG, 1e6)) + " m");
  io.println("2 -> 1 hydrogen transition: " +
    convert.float_to_string(quantum_hydrogen_transition_ev(2, 1)) + " eV");
  io.println("H-alpha: " +
    convert.float_to_string(quantum_balmer_wavelength_nm(3)) + " nm");
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.quantum
```

Expected tail: 18 `[PASS]` lines, `xiom.quantum: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Non-relativistic.** The de Broglie relation `lambda = h/(m*v)` and the
  Bohr energies use non-relativistic mechanics; there is no Lorentz factor,
  no fine structure, no spin, and no reduced-mass correction (`R_inf` and
  `E1` assume an infinitely heavy nucleus).
- **Scalar only.** Every value is a single `Float64` (or `Int` quantum
  number); there are no vectors, matrices, complex amplitudes, density
  matrices, or state vectors. One quantity at a time.
- **Hydrogen-like only.** Levels, transitions, and the Balmer/Lyman series
  are for the hydrogen atom (Z = 1); there is no Z scaling, no multi-electron
  atoms, no selection rules, line intensities, or lifetimes.
- **No spectroscopy conversions.** Wavelength/frequency/wavenumber/photon
  energy conversions belong to `xiom.spectroscopy` and are deliberately not
  duplicated here; this module pins `R_inf` in per metre and returns
  wavelengths in nanometres only.
- **Guard-based edge handling.** Invalid inputs return `0.0` with no
  `Result` and no panic; a real zero is indistinguishable from a rejected
  input. See `SPEC.md` section 4.
- **No overflow/NaN contract.** IEEE-754 double behaviour applies for extreme
  magnitudes; inputs are expected to be finite physical values. Very large
  `n` values are accepted and approach the series limits.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
