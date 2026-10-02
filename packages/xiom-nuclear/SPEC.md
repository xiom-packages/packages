# xiom.nuclear -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.nuclear` (`src/nuclear.xi`). Pure XIOM, no FFI, one import
(`xiom.convert` for `int_to_string` in nuclear notation).
Dependencies: `xiom.std` only (tests use `xiom.test`, `xiom.io`,
`xiom.string`, `xiom.string.compare`).

## 1. Scope

Deterministic integer/fixed-point nuclear physics helpers:

- `decay`: whole half-lives elapsed, stepwise remaining fraction in permille,
  remaining atoms/activity, decay constant, mean lifetime, atom counts from a
  sample mass and back, activity from an atom count;
- `fission`: Q-value from mass-excess sums, per-event and total energy release
  in keV, keV -> attojoule conversion, overflow pre-check;
- `fusion`: the same Q-value helper, classical Coulomb barrier, classical
  feasibility, Q/input gain;
- `isotopes`: element symbols, "El-A" notation, a 17-entry built-in isotope
  table (half-life, dominant decay mode), fissile flags, neutron number;
- `cross_sections`: channel codes, a 10-target millibarn table, macroscopic
  cross-section from density, mean free path;
- `radiation`: absorbed dose and dose rate in microgray, half-value-layer
  attenuation in permille;
- `units`: scale/metadata accessors.

Every value is an `Int`, `Bool`, or `Str`; there is no allocation in the
library API, no floating point, and no error payloads.

## 2. Non-goals

- `Float64` APIs and continuous exponentials (decay is stepwise).
- Evaluated nuclear data (ENDF): the dataset is illustrative and fixed.
- Decay chains, equilibrium, branching ratios, or delayed radiation.
- Fission fragment distributions, delayed neutrons/energy, reactor kinetics.
- Quantum tunnelling, Gamow factors, or plasma/astrophysical rates.
- Geometry-aware shielding, build-up factors, or sievert quality factors.
- Any FFI, file I/O, registry integration, or unit-registry parsing.

## 3. Units and conventions

| Quantity | Unit | Stored as |
|---|---|---|
| Fraction | permille | `1000 = 1.0` |
| Energy, mass excess | keV | `Int` (`202500` = 202.5 MeV) |
| Time | second | `Int` |
| Sample mass | nanogram | `Int` (`1000000` = 1 mg) |
| Molar mass | g/mol | `Int` (`235`) |
| Cross-section | millibarn | `Int` (`585000` = 585 b) |
| Macro cross-section | 1e-6 /cm | from density in 1e21 /cm3 |
| Absorbed dose | microgray (uGy) | `Int` |

Constants: `ln(2)` = `693147` x 1e-6; Avogadro's number stored divided by
1e15 as `602214076`; one Julian year = `31557600` s; `1 keV` =
`160.2176634` aJ; Coulomb constant `1440` keV*fm; neutron mass excess `8071`
keV; prompt U-235 fission energy `202500` keV.

## 4. Rounding rules

All divisions are XIOM `Int` divisions and **truncate toward zero** (never
floor, never round-half). Documented consequences:

- `nuc_decay_factor_permille` and `nuc_hvl_attenuation_permille` apply one
  halving per whole half-life / HVL; the fraction reaches `0` at 10 or more.
- `nuc_atoms_from_mass` truncates the `mass * 602214076 / M` quotient; the
  inverse `nuc_mass_from_atoms` truncates twice, so a round trip can lose up
  to 1 ng (`2562613089361000000` atoms of U-235 -> `999999` ng, not 1e6).
- `nuc_activity_bq` takes `N / half_life` first, so activities below ~1 Bq
  quantize to `0` and the relative error is bounded by `half_life / N`.
- `nuc_kev_to_aj` truncates `kev * 1602176634 / 1e7` to whole attojoules.
- `nuc_dose_microgy` truncates at each of its three division stages.
- `nuc_coulomb_barrier_kev`, `nuc_q_value_kev`, `nuc_fusion_gain_x1e4`,
  `nuc_mean_free_path_nm` truncate their single division.

## 5. Behavior by subsystem

### 5.1 Decay

| Function | Formula / rule |
|---|---|
| `nuc_halflives_elapsed(t12, t)` | `0` if `t12 <= 0` or `t <= 0`, else `t / t12` |
| `nuc_decay_factor_permille(t12, t)` | start `1000`; halve once per whole half-life until `n == 0` or `f == 0` |
| `nuc_remaining_atoms(n, t12, t)` | `0` if `n <= 0`, else `n * factor / 1000` |
| `nuc_remaining_activity_bq(a, t12, t)` | `0` if `a <= 0`, else `a * factor / 1000` |
| `nuc_decay_constant_per_s_x1e18(t12)` | `0` if `t12 <= 0`, else `693147 * 1e12 / t12` |
| `nuc_mean_lifetime_s(t12)` | `0` if `t12 <= 0`, else `t12 * 1e6 / 693147` |
| `nuc_atoms_from_mass(m, M)` | `0` if `m <= 0` or `M <= 0`, else `(m * 602214076 / M) * 1e6` |
| `nuc_mass_from_atoms(N, M)` | `0` if `N <= 0` or `M <= 0`, else `(N / 1e6) * M / 602214076` |
| `nuc_activity_bq(N, t12)` | `0` if `N <= 0` or `t12 <= 0`, else `(N / t12) * 693147 / 1e6` |

### 5.2 Fission and fusion

| Function | Formula / rule |
|---|---|
| `nuc_q_value_kev(r, p)` | `r - p` (signed; `Q > 0` is exothermic) |
| `nuc_reaction_feasible_kev(q)` | `q > 0` (strict; `Q = 0` is not feasible) |
| `nuc_fission_energy_total_kev(e, E)` | `0` for `e <= 0` or `E <= 0`; `-1` if `e * E` overflows; else `e * E` |
| `nuc_kev_to_aj(kev)` | `0` for `kev <= 0`, else `kev * 1602176634 / 1e7` |
| `nuc_coulomb_barrier_kev(z1, z2, r)` | `-1` if `r <= 0` or a `z < 0`; else `1440 * z1 * z2 / r` |
| `nuc_fusion_feasible(z1, z2, r, e)` | `false` for an undefined barrier; else `e >= barrier` |
| `nuc_fusion_gain_x1e4(q, e)` | `-1` if `e <= 0`, else `10000 * q / e` |

### 5.3 Radiation

`nuc_dose_microgy(A, E, f, t, m)` returns `-1` when `m <= 0`, `0` when any of
`A, E, f, t` is non-positive, otherwise:

```
decays    = A * t
effective = decays * f / 1000
e_mev     = effective * E
uGy       = e_mev * 1602176634 / 1e6 / 1e7 / m
```

`nuc_dose_rate_microgy_per_h(A, E, f, m)` is the same with `t = 3600`.
`nuc_hvl_attenuation_permille(H, x)` returns `1000` when `H <= 0` or `x <= 0`,
otherwise halves `1000` once per whole HVL until `layers == 0` or `f == 0`.

### 5.4 Cross sections

Channels: `1` capture, `2` fission, `3` scattering (accessors return those
codes). `nuc_xs_millibarns(z, a, channel)` returns the tabulated value, `-1`
for an unknown isotope or channel, and `0` for a tabulated zero channel
(e.g. U-238 thermal fission). `nuc_macro_xs_per_cm_x1e6(n, sigma)` = `n*sigma`
(0 for non-positive inputs). `nuc_mean_free_path_nm(S)` = `-1` for `S <= 0`,
else `1e13 / S`.

## 6. Data model (built-in tables)

Isotope table (17 entries), keyed by `(Z, A)`; half-life in seconds, mode in
`{"stable", "beta-", "alpha"}`:

| Nuclide | Z | A | Half-life (s) | Mode |
|---|---|---|---|---|
| H-1 | 1 | 1 | 0 (stable) | stable |
| H-2 | 1 | 2 | 0 (stable) | stable |
| H-3 | 1 | 3 | 388789632 | beta- |
| He-4 | 2 | 4 | 0 (stable) | stable |
| C-12 | 6 | 12 | 0 (stable) | stable |
| C-14 | 6 | 14 | 180825048000 | beta- |
| K-40 | 19 | 40 | 39383884800000000 | beta- |
| Co-60 | 27 | 60 | 166344192 | beta- |
| Sr-90 | 38 | 90 | 908543304 | beta- |
| I-131 | 53 | 131 | 693377 | beta- |
| Cs-137 | 55 | 137 | 949252608 | beta- |
| Ra-226 | 88 | 226 | 50492160000 | alpha |
| Th-232 | 90 | 232 | 443384280000000000 | alpha |
| U-235 | 92 | 235 | 22216550400000000 | alpha |
| U-238 | 92 | 238 | 140999356800000000 | alpha |
| Pu-239 | 94 | 239 | 760853736000 | alpha |
| Am-241 | 95 | 241 | 13639194720 | alpha |

Half-lives are the rounded literature values converted with 1 a = 31557600 s
(1.248e9 a, 1925.28 d, 8.0252 d, 30.08 a, 1600 a, etc.). Stable nuclides are
stored as `0`; unknown keys return `-1` from `nuc_isotope_half_life_s` and
`"unknown"` from `nuc_isotope_decay_mode`.

Element symbols: H, He, Li, Be, B, C, N, O, F, Ne, Na, Mg, Al, Si, P, S, Cl,
Ar, K, Ca, Fe, Co, Ni, Sr, Cd, I, Xe, Cs, Ra, Th, U, Pu, Am; anything else is
`"X"`. Fissile set: U-233, U-235, Pu-239, Pu-241.

Cross-section table (millibarns; thermal/representative values):

| Target | capture | fission | scatter |
|---|---|---|---|
| H-1 | 332 | - | 20000 |
| H-2 | - | - | 3300 |
| He-4 | - | - | 800 |
| B-10 | 3837000 | - | 2000 |
| C-12 | 3 | - | 3500 |
| Cd-113 | 20600000 | - | - |
| Xe-135 | 2650000000 | - | - |
| U-235 | 99000 | 585000 | 15000 |
| U-238 | 2680 | 0 | 9000 |
| Pu-239 | 271000 | 750000 | - |

## 7. Error cases and sentinels

- Unknown isotope/channel lookups return `-1` (`"unknown"` for the mode,
  `"X"` for the element symbol), distinct from tabulated zeros.
- `nuc_fission_energy_total_kev` returns `-1` on overflow; the caller can
  pre-check with `nuc_mul_overflows(a, b)`.
- `nuc_coulomb_barrier_kev` / `nuc_mean_free_path_nm` / `nuc_dose_microgy`
  return `-1` for undefined inputs (distance `<= 0`, `Sigma <= 0`,
  `mass_g <= 0`).
- Non-positive time/amount/energy inputs return `0` except where a factor or
  attenuation is the natural neutral value (`1000`).
- There are no panics, `Result`s, or `Option`s in the module API.

## 8. Range and overflow envelope

Inputs are 64-bit signed `Int`. Documented envelope (outside it, behavior is
undefined by this spec and untested):

- `nuc_atoms_from_mass`: `mass_ng * 602214076` must fit, i.e. `mass_ng` up to
  ~1.5e10 ng (15 g); 1 mg of U-235 gives 2.56e18 atoms, inside range.
- `nuc_mass_from_atoms`: `(N / 1e6) * M` must fit.
- `nuc_dose_microgy`: `e_mev * 1602176634` must fit, i.e. total emitted energy
  up to ~5.7e9 MeV per call.
- `nuc_fission_energy_total_kev`: overflow is detected and reported, not
  silently wrapped.
- `nuc_decay_constant_per_s_x1e18` and `nuc_coulomb_barrier_kev` multiply
  small constants by inputs and stay inside range for physical Z and t12.

## 9. API signatures

All functions are `pub`, free, and `O(1)`; the table lookups are bounded
if-chains. `module xiom.nuclear` carries no trailing semicolon, `use
xiom.convert;` one. The library imports nothing else.

## 10. Test plan

`tests/test_conformance.xi` (module `nuclear_tests`) runs 27 named checks
through `assert(cond, "name")`, one `fn` per check; `main` returns the failure
count (0 = green). The decay fixture is 1 mg of pure U-235 (10^6 ng,
M = 235 g/mol, t1/2 = 22216550400000000 s). All `Str` equality goes through
`xiom.string.compare.str_compare` (BUG-17 discipline).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | constants | permille 1000, scale 1e4, ln2 693147, N_A 602214076, year 31557600, n excess 8071, fission 202500 keV |
| t2 | half-lives | floor 35/10=3; boundaries 9/10; non-positive guards |
| t3 | decay factor | 125 after 3.5 t1/2; 1000 guard; 0 at 10 t1/2 |
| t4 | remaining | 1e6 -> 125000 atoms; activity 1000 -> 250 Bq; guards |
| t5 | constant/lifetime | 693147e12/1000; 1e9/693147 = 1442; zero guards |
| t6 | atoms from mass | 1 mg U-235 -> 2562613089361000000; guards |
| t7 | mass from atoms | inverse -> 999999 ng (documented truncation) |
| t8 | activity | 1 mg U-235 -> 79 Bq; 1e12 atoms/1000 s -> 693147000 Bq |
| t9 | fission Q | 48986 - (-124299) = 173285 keV; zero and negative |
| t10 | fission energy | 3 x 202500 = 607500 keV; overflow -> -1; per-event constant |
| t11 | keV -> aJ | 1 -> 160; 202500 -> 32444076; guards |
| t12 | D-T Q | 28086 - 10496 = 17590 keV |
| t13 | Coulomb barrier | 288 keV at 5 fm; 576 at Z=2; r=0 and Z<0 -> -1 |
| t14 | fusion feasibility | inclusive at 288; 287 false; r=0 false |
| t15 | fusion gain | 586333 x1e4; input<=0 -> -1; negative q -> -10000 |
| t16 | reaction feasible | Q>0 strict; 0 and -1 false |
| t17 | notation | "H", "U", "X", "U-235", "C-14", "X-300" |
| t18 | half-life table | stable 0; C-14/U-235/Pu-239 pinned; unknown -1 |
| t19 | decay modes | stable/beta-/alpha/unknown strings |
| t20 | fissile set | U-233/235, Pu-239 yes; U-238, Pu-240 no |
| t21 | neutron number | 235-92=143; invalid A<Z -> 0 |
| t22 | cross sections | channels; B-10 3.837e6 mb; U-235 fission 585000 mb; U-238 fission 0 |
| t23 | xs sentinels | unknown isotope/channel -> -1 |
| t24 | macro xs | 49 x 585000 = 28665000 (1e-6/cm); guards |
| t25 | mean free path | 1e13/28665000 = 348857 nm; guards |
| t26 | dose | 1 MBq x 1 MeV x 1 h over 1 kg -> 576 uGy; rate; guards |
| t27 | HVL | 2 layers -> 250; guards; 0 at 10 HVLs |

No assertion uses tolerance; every expected value is an exact integer. No
`Vec[fn]` dispatch: every test is called explicitly from `main`.

## 11. Known limitations

- Stepwise decay/attenuation: quantized to whole half-lives/HVLs, no
  continuous exponential.
- Illustrative dataset only (17 nuclides, 10 cross-section targets), rounded
  literature values; not for safety-critical or dosimetry use.
- Fission energy is the single conventional 202.5 MeV prompt value; no
  fragment yields or delayed contributions.
- Classical fusion barrier only.
- Dose is a homogeneous point estimate; no geometry, build-up, or sievert
  weighting.
- `Int`-sized samples: atom counts are representable only up to ~9.2e18.

## 12. Compiler / stdlib notes

Built against XIOM v0.62.2. No workarounds beyond the repo's standard
discipline: free functions only (no methods), no lambdas, no `Vec[Struct]`,
no `Result`/`Option` in the module, no `match`, `module` without a trailing
semicolon, `use` lines with one, and the copyright + SPDX header on every
`.xi` file. The library imports only `xiom.convert`; tests use `xiom.io`,
`xiom.test`, `xiom.string` and `xiom.string.compare`. Loop progress is
guaranteed by the strictly decreasing half-life/HVL counters, which also
bound each loop to at most 10 iterations.
