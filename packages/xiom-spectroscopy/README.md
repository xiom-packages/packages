# xiom.spectroscopy

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** electromagnetic-spectrum conversions on scalar `Float64` values:
> vacuum wavelength (nm), frequency (THz), wavenumber (cm^-1) and photon
> energy (eV), plus a visible-range test and a spectral band-name helper.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (platform dependency only; the library
> module imports nothing and uses no FFI of its own). Tests additionally use
> `xiom.test`, `xiom.io`, `xiom.math` and `xiom.string.compare`.

## What it is

`xiom.spectroscopy` is a small, dependency-free module of ten free functions
built entirely from scalar `Float64` arithmetic. Every quantity is a plain
double whose unit is spelled out in the function name (`_nm`, `_thz`, `_ev`,
`_cm_inv`), and every conversion is the textbook formula with explicitly
documented edge cases. It replaces the former placeholder (which promised
spectra loading, absorbance, peak fitting and FFI) with a precise,
measured, pure-XIOM core: conversions only, no FFTs, no files, no C.

The exported constants are the exact 2019 SI values:

| Constant | Value | Unit | Meaning |
|---|---|---|---|
| `SPEC_C_M_PER_S` | `299792458` | m/s | speed of light in vacuum |
| `SPEC_H_J_S` | `6.62607015e-34` | J*s | Planck constant |
| `SPEC_EV_J` | `1.602176634e-19` | J | electronvolt |

See `SPEC.md` for the exact formulas, the guard rule and the test plan.

## Guard rule

Invalid inputs are total, not errors: they return `0.0` (`spec_band_name`
returns `""`) and never panic.

- **G1 non-positive input:** every conversion function returns `0.0` when its
  numeric argument is `<= 0`; `spec_band_name` returns `""` and
  `spec_is_visible` returns `false`. This means no division by zero can
  occur, and a real zero is indistinguishable from a rejected input in the
  return value -- validate first when the distinction matters.

## API

| Function | Returns | Input unit | Output unit | Description |
|---|---|---|---|---|
| `spec_nm_to_thz(nm)` | `Float64` | nm | THz | `c / (nm*1e-9) / 1e12`; `nm <= 0 -> 0.0` (G1). |
| `spec_thz_to_nm(thz)` | `Float64` | THz | nm | `c / (thz*1e12) / 1e-9`; `thz <= 0 -> 0.0` (G1). |
| `spec_nm_to_ev(nm)` | `Float64` | nm | eV | `h*c / (nm*1e-9) / eV`; `nm <= 0 -> 0.0` (G1). |
| `spec_ev_to_nm(ev)` | `Float64` | eV | nm | `h*c / (ev*eV) / 1e-9`; `ev <= 0 -> 0.0` (G1). |
| `spec_nm_to_cm_inv(nm)` | `Float64` | nm | cm^-1 | `1e7 / nm`; `nm <= 0 -> 0.0` (G1). |
| `spec_cm_inv_to_nm(cm_inv)` | `Float64` | cm^-1 | nm | `1e7 / cm_inv`; `cm_inv <= 0 -> 0.0` (G1). |
| `spec_ev_to_thz(ev)` | `Float64` | eV | THz | `ev * eV / h / 1e12`; `ev <= 0 -> 0.0` (G1). |
| `spec_thz_to_ev(thz)` | `Float64` | THz | eV | `thz * 1e12 * h / eV`; `thz <= 0 -> 0.0` (G1). |
| `spec_is_visible(nm)` | `Bool` | nm | -- | `380.0 <= nm <= 750.0` (inclusive); `false` otherwise. |
| `spec_band_name(nm)` | `Str` | nm | -- | `""` for `nm <= 0`; else `"UV"` (`< 380`), `"visible"` (`380..750`), `"near-IR"` (`> 750..< 2500`), `"IR"` (`2500..< 1e6`), `"far-IR"` (`>= 1e6`). |

Pinned examples (conformance-tested): 500 nm = 599.584916 THz = 2.4796837 eV;
1 eV = 1239.841984 nm = 241.7989242 THz; 1000 cm^-1 = 10000 nm.

## Usage

```xi
use xiom.spectroscopy;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  io.println("500 nm: " +
    convert.float_to_string(spec_nm_to_thz(500.0)) + " THz, " +
    convert.float_to_string(spec_nm_to_ev(500.0)) + " eV, " +
    convert.float_to_string(spec_nm_to_cm_inv(500.0)) + " cm^-1, band " +
    spec_band_name(500.0));
  io.println("1 eV photon: " +
    convert.float_to_string(spec_ev_to_nm(1.0)) + " nm");
  return 0;
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.spectroscopy
```

Expected tail: 16 `[PASS]` lines, `xiom.spectroscopy: all tests passed`, then
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Vacuum wavelength only.** Wavelengths are in vacuum, never in a medium;
  no refractive index, dispersion, or material data is applied. Convert to a
  medium wavelength by dividing by the refractive index before calling.
- **Scalar only.** Every value is a single `Float64`; there are no vectors,
  spectra, sample arrays, peaks, baselines, or file formats. One wavelength
  or one photon energy at a time.
- **Conversions only.** No spectrum loading, absorbance (Beer-Lambert),
  emission-line identification, resolution/deconvolution, or peak detection
  and fitting; the former placeholder's C-FFI scope is intentionally out of
  scope for this pure-XIOM release.
- **No units machinery.** Units live in the names; there is no dimensional
  analysis, parsing, or formatting, and no conversions for other units
  (um, Angstrom, Hz, kJ/mol, ...).
- **Guard-based edge handling.** Invalid inputs return `0.0` (or `""`/`false`)
  with no `Result` and no panic; a real zero is indistinguishable from a
  rejected input. See `SPEC.md` section 4.
- **No overflow/NaN contract.** IEEE-754 double behaviour applies for extreme
  magnitudes; inputs are expected to be finite physical values.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
