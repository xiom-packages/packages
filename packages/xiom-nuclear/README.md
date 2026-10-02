# xiom.nuclear

> **Status:** `incubating` -- conformance-tested (27/27); not yet published on the XIOM registry.
> **Scope:** one dependency-light module of deterministic integer/fixed-point
> nuclear physics: decay, fission, fusion, isotope data, cross sections, and
> radiation dose/attenuation. No floating point, no FFI, no external files.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.convert.int_to_string` for
> nuclear notation). Tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`.

## Libs inventory

| Lib | Description | Module functions |
|-----|-------------|------------------|
| `decay` | Radioactive decay, half-life, activity, atom counts | `nuc_halflives_elapsed`, `nuc_decay_factor_permille`, `nuc_remaining_atoms`, `nuc_remaining_activity_bq`, `nuc_decay_constant_per_s_x1e18`, `nuc_mean_lifetime_s`, `nuc_atoms_from_mass`, `nuc_mass_from_atoms`, `nuc_activity_bq` |
| `fission` | Fission Q-values, energy release, yield arithmetic | `nuc_fission_energy_per_event_kev`, `nuc_fission_energy_total_kev`, `nuc_q_value_kev`, `nuc_reaction_feasible_kev`, `nuc_kev_to_aj` |
| `fusion` | Reaction feasibility: Q-value, Coulomb barrier, gain | `nuc_q_value_kev` (shared), `nuc_coulomb_barrier_kev`, `nuc_fusion_feasible`, `nuc_fusion_gain_x1e4` |
| `isotopes` | Built-in isotope table and nuclear notation | `nuc_element_symbol`, `nuc_isotope_symbol`, `nuc_isotope_half_life_s`, `nuc_isotope_decay_mode`, `nuc_is_fissile`, `nuc_neutron_number` |
| `cross_sections` | Interaction cross-section lookup and macroscopic use | `nuc_xs_channel_capture`, `nuc_xs_channel_fission`, `nuc_xs_channel_scatter`, `nuc_xs_millibarns`, `nuc_macro_xs_per_cm_x1e6`, `nuc_mean_free_path_nm` |
| `radiation` | Dose and exposure estimates, shielding attenuation | `nuc_dose_microgy`, `nuc_dose_rate_microgy_per_h`, `nuc_hvl_attenuation_permille` |
| `units` | Scale/metadata accessors | `nuc_permille`, `nuc_scale_x1e4`, `nuc_ln2_x1e6`, `nuc_avogadro_x1e15`, `nuc_seconds_per_year`, `nuc_neutron_excess_kev`, `nuc_mul_overflows` |

## Conventions

- Fractions are permille (`1000 = 1.0`); energies and mass excesses are keV;
  times are seconds; sample mass is nanograms; cross-sections are millibarns.
- Every division is `Int` division truncating toward zero; the half-life and
  HVL models quantize to whole half-lives/half-value layers. Rounding is
  documented per function in `SPEC.md`.
- Undefined lookups use documented sentinels: `-1` for "not in the dataset",
  `0` for a tabulated stable nuclide or a zero cross-section.

## Usage

```xi
use xiom.nuclear;

fn main() -> Int {
  let t12 = nuc_decay_factor_permille(10, 35);        // 125 (3 half-lives)
  let q = nuc_q_value_kev(28086, 10496);              // 17590 keV (D-T)
  let b = nuc_coulomb_barrier_kev(1, 1, 5);           // 288 keV
  let fissile = nuc_is_fissile(94, 239);              // true (Pu-239)
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.nuclear
```

Expected tail: 27 `[PASS]` lines, `xiom.nuclear: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- The isotope dataset and cross-section table are small illustrative fixtures
  (17 nuclides, 10 targets), not evaluated nuclear data files.
- The decay model is stepwise by whole half-lives; there is no continuous
  exponential (integer math only) and no decay chains or equilibrium.
- Fusion feasibility is the classical Coulomb barrier only: no quantum
  tunnelling, no cross-section energy dependence, no plasma physics.
- Fission energy is the conventional ~202.5 MeV prompt value per U-235 event;
  no fragment distribution, delayed energy, or neutronics.
- Dose is a homogeneous-absorber point estimate (no geometry, no build-up,
  no quality factors in sievert).
- `Int` samples can hold atom counts only up to ~9.2e18 (a few mg of heavy
  nuclide) and products must stay inside the documented envelope.

See `SPEC.md` for the full behavior, data model, API, and error cases. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
