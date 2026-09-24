# xiom.spectroscopy -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.spectroscopy` (`src/spectroscopy.xi`). Pure XIOM, no FFI.
Dependencies: `xiom.std` only; the module itself imports nothing (scalar
`Float64` arithmetic and the exported constants below); the tests use
`xiom.test`, `xiom.io`, `xiom.math` and `xiom.string.compare`.

## 1. Scope

Electromagnetic-spectrum conversions for a single scalar quantity at a time,
all in `Float64`:

- vacuum wavelength in nanometres (`nm`),
- frequency in terahertz (`THz`),
- wavenumber in reciprocal centimetres (`cm^-1`),
- photon energy in electronvolts (`eV`),
- a visible-range predicate (`380..750` nm inclusive),
- a spectral band-name helper (`UV`, `visible`, `near-IR`, `IR`, `far-IR`).

Every function is a free function; the module is deterministic,
allocation-free and total (invalid inputs map to `0.0`, `""` or `false`,
never to an error or a panic).

## 2. Non-goals

- Spectra as data: no arrays, `Vec[Float64]`, sample rates, baselines,
  smoothing, normalization or file formats. One scalar per call.
- Peak analysis: no peak detection, fitting, deconvolution, resolution
  estimates, emission-line identification or absorbance (Beer-Lambert).
- Media: no refractive index, dispersion models or material constants;
  wavelengths are vacuum wavelengths.
- Relativistic or Doppler effects, cosmology (redshift), units machinery
  (um, Angstrom, Hz, kJ/mol, ...) and any FFI, I/O or randomness.

## 3. Constants

Exact SI values (2019 SI), exported as `pub const`:

| Constant | Value | Unit | Meaning |
|---|---|---|---|
| `SPEC_C_M_PER_S` | `299792458.0` | m/s | speed of light in vacuum `c` |
| `SPEC_H_J_S` | `6.62607015e-34` | J*s | Planck constant `h` |
| `SPEC_EV_J` | `1.602176634e-19` | J | electronvolt `eV` |

Unit conversion factors used by the formulas, and their justification:

| Factor | Meaning |
|---|---|
| `1e-9` | nanometres to metres (`nm * 1e-9` is the wavelength in m) |
| `1e12` | terahertz to hertz (`thz * 1e12` is the frequency in Hz) |
| `1e7` | reciprocal centimetres per nanometre (`1 cm^-1 = 1e7 nm^-1`) |

## 4. Guard rule

Invalid inputs are total: they return the sentinel and are never errors or
panics. The rule is module-wide and is pinned by the conformance suite.

| Rule | Argument | Condition | Effect | Applies to |
|---|---|---|---|---|
| G1 | numeric input | `<= 0` | `0.0` | all eight conversion functions |
| G1 | `nm` in `spec_band_name` | `<= 0` | `""` | `spec_band_name` |
| G1 | `nm` in `spec_is_visible` | `<= 0` | `false` | `spec_is_visible` (also false by the bounds) |

Consequences worth stating explicitly:

- **No division by zero can occur.** Every divisor is guarded: `nm`, `thz`,
  `ev` and `cm_inv` are checked before use.
- **A real zero is not distinguishable from a rejected input** in the return
  value; callers who need the distinction must validate first.
- All positive inputs, however extreme, are accepted and computed with
  IEEE-754 double arithmetic; no clamping or saturation is applied.

## 5. Formulas

Let `c = SPEC_C_M_PER_S`, `h = SPEC_H_J_S`, `eV = SPEC_EV_J`, and `f` the
frequency, `lambda` the vacuum wavelength, `sigma` the wavenumber and `E` the
photon energy.

| Function | Formula | Sign/edge notes |
|---|---|---|
| `spec_nm_to_thz(nm)` | `c / (nm * 1e-9) / 1e12` | `f = c / lambda`; `nm <= 0 -> 0.0` |
| `spec_thz_to_nm(thz)` | `c / (thz * 1e12) / 1e-9` | `lambda = c / f`; inverse of the above |
| `spec_nm_to_ev(nm)` | `h * c / (nm * 1e-9) / eV` | `E = h*f = h*c/lambda` in eV; `nm <= 0 -> 0.0` |
| `spec_ev_to_nm(ev)` | `h * c / (ev * eV) / 1e-9` | `lambda = h*c/E`; inverse of the above |
| `spec_nm_to_cm_inv(nm)` | `1e7 / nm` | `sigma = 1/lambda`, lambda in nm |
| `spec_cm_inv_to_nm(cm_inv)` | `1e7 / cm_inv` | `lambda = 1/sigma`; inverse of the above |
| `spec_ev_to_thz(ev)` | `ev * eV / h / 1e12` | `f = E/h`; `ev <= 0 -> 0.0` |
| `spec_thz_to_ev(thz)` | `thz * 1e12 * h / eV` | `E = h*f` in eV; inverse of the above |
| `spec_is_visible(nm)` | `nm >= 380.0 && nm <= 750.0` | inclusive both ends; `false` for `nm <= 0` |
| `spec_band_name(nm)` | piecewise below | `""` for `nm <= 0` |

Rounding rule: operations are performed left to right exactly as written in
the table (the same order the implementation uses), in IEEE-754 double
precision. No intermediate rounding beyond double precision is specified.

### 5.1 Band boundaries

| Band name | Condition | Note |
|---|---|---|
| `""` | `nm <= 0` | guard G1 |
| `"UV"` | `nm < 380` | excludes 380 |
| `"visible"` | `380 <= nm <= 750` | 750 nm belongs to `visible`, matching `spec_is_visible` |
| `"near-IR"` | `750 < nm < 2500` | starts strictly above 750 |
| `"IR"` | `2500 <= nm < 1e6` | 2500 nm is `IR` |
| `"far-IR"` | `nm >= 1e6` | 1e6 nm (1 mm) is `far-IR` |

The bands cover the positive axis with no gap and no overlap under this
convention, and it is consistent with `spec_is_visible` at 750 nm.

## 6. Test plan

Suite: `tests/test_conformance.xi`, module `spectroscopy_tests`, 16 checks
run explicitly from `main` (no `Vec[fn]` dispatch). Exit code is the number
of failed checks, so a green run exits 0.

Tolerance (task-mandated relative-with-floor), documented in the test file:

```
close(a, b) := fabs(a - b) <= 1e-6 * max(1, fabs(b))
```

`b` is the pinned expected value; `fabs` is `xiom.math.abs_float` and `max`
is `xiom.math.max_float`. Expected values are pinned decimals of the
formulas in section 5, recomputed in IEEE-754 double precision; the floor
keeps 1e-6 absolute for magnitudes <= 1 and 1e-6 relative above.

| Check | Proves |
|---|---|
| `t01` | `spec_nm_to_thz`: 500 nm -> 599.584916 THz pinned; 1000 -> 299.792458; 250 -> 1199.169832 |
| `t02` | `spec_nm_to_ev`: 500 nm -> 2.4796837 eV pinned; 1000 -> 1.23984185; 250 -> 4.9593679 |
| `t03` | round-trip nm -> THz -> nm for 250/500/1064/10000 nm |
| `t04` | round-trip nm -> eV -> nm for 200/500/1064 nm |
| `t05` | round-trip nm -> cm^-1 -> nm for 500/1064/10000 nm |
| `t06` | `spec_cm_inv_to_nm`: 1000 cm^-1 -> 10000 nm; 5000 -> 2000; 1 -> 1e7; inverse direct check |
| `t07` | `spec_ev_to_nm`: 1 eV -> 1239.841984 nm pinned; 2 eV -> 619.920992; 10 eV -> 123.9841984 |
| `t08` | visible boundaries: 379.9 false, 380 true, 500 true, 750 true, 750.1 false |
| `t09` | band names at every boundary: UV/visible/near-IR/IR/far-IR (10, 300, 379.9, 380, 500, 750, 750.1, 1000, 2499.9, 2500, 5000, 999999, 1e6, 1e7 nm) |
| `t10` | band-name guard: 0, -5, -0.001 nm -> `""` (via `str_compare`) |
| `t11` | guard G1 across all eight conversions (0 and negative inputs) plus `spec_is_visible` false |
| `t12` | round-trip eV -> THz -> eV for 0.5/1/2.5 eV, both directions |
| `t13` | `spec_ev_to_thz` pinned: 1 eV -> 241.7989242 THz; 2.5 -> 604.4973105; 0.5 -> 120.8994621; `spec_thz_to_ev` inverse |
| `t14` | cross-path consistency at 500 nm: THz -> eV equals direct eV; eV -> THz equals direct THz; both round-trips |
| `t15` | large pinned values at 0.1 nm: 2997924.58 THz, 12398.419843 eV, 1e8 cm^-1, band UV |
| `t16` | formulas reproduced from `c/h/eV` literals defined inside the test (independent of the module constants) |

`Str` equality in `t09`/`t10`/`t15` goes through `xiom.string.compare`'s
`str_compare` (`seq`/`band_is` helpers), never `==` on `Str` (BUG 17:
`Str` `==` can lower to a pointer comparison).

Boundary cases are pinned even where the formula would behave identically:
`nm = 0` and `nm < 0`, `380`, `750`, `750.1`, `2500`, `1e6`.

## 7. Semantics notes

- **Monotonicity.** On positive inputs, `spec_nm_to_thz`, `spec_nm_to_ev`
  and `spec_nm_to_cm_inv` are strictly decreasing in `nm`; their inverses
  are strictly decreasing in their argument. The round-trip tests exercise
  the inverse pairs on both sides of the visible range.
- **Exact anchored values.** 500 nm -> 599.584916 THz is exact decimal
  (299792458/500/1e3 THz); 1 cm^-1 -> 1e7 nm and 1000 cm^-1 -> 10000 nm are
  exact; the eV anchors (2.4796837 eV, 1239.841984 nm, 241.7989242 THz) are
  pinned decimals within the documented tolerance.
- **Naming.** `_cm_inv` is the wavenumber in cm^-1; `_thz` is frequency in
  THz; `_ev` is photon energy in electronvolts; `_nm` is vacuum wavelength in
  nanometres. No unit parsing or formatting is provided.
- **Independence.** The library module imports no stdlib module; the tests
  import `xiom.test`, `xiom.io`, `xiom.math` and `xiom.string.compare` only.

## 8. Verification

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.spectroscopy
```

Green iff the tail is
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)` and the suite prints
`xiom.spectroscopy: all tests passed`.
