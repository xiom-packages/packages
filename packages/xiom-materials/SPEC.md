# xiom.materials -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.materials` (`src/materials.xi`). Pure XIOM, no FFI, no imports.
Dependencies: `xiom.std` only (tests use `xiom.test` and `xiom.io`).

## 1. Scope

Deterministic fixed-point linear elasticity:

- isotropic elastic constants from `E` and `nu` (`G`, `K`, `lambda`),
- 6-component Voigt stress/strain vectors,
- Hooke's law strain -> stress and its inverse stress -> strain,
- invariants: first invariant `I1`, von Mises equivalent, principal max shear,
- safety factor and yield flags against a yield strength,
- temperature scaling with a caller-supplied `(temperature, factor)` table,
- unit-consistency metadata.

Every value is an `Int`; the module is deterministic, allocation-free, and
free of error paths except where documented (safety factor at zero stress).

## 2. Non-goals

- Floats and any `Float64` API.
- Anisotropy, orthotropy, composites, plasticity, creep, fatigue, damage.
- Full 6x6 stiffness-matrix assembly or eigenvalue extraction (principal
  stresses are caller-supplied to the principal-stress helpers).
- Material databases, parsing, pretty-printing, unit registries.
- Any FFI, file I/O, or registry integration.

## 3. Units and conventions

Fixed-point scale is `1e-4`: `10000` represents `1.0`.

| Quantity | Unit | Scaled example |
|---|---|---|
| Stress / stiffness | MPa | 200000.0000 MPa = `2000000000` |
| Strain / engineering shear | dimensionless | 0.0010 = `10` |
| Poisson ratio | dimensionless | 0.2500 = `2500` |
| Temperature | kelvin | 293.1500 K = `2931500` |
| Table scale factor | dimensionless | 1.0000 = `10000` |

Voigt component order is `[xx, yy, zz, yz, xz, xy]`. The last three entries of
a strain vector are engineering shear strains `gamma = 2 * eps`; the matching
stress components are the shear stresses. `mat_hooke_inverse_shear` returns the
tensor shear strain, i.e. half the engineering shear of the forward direction.

## 4. Rounding rules

All divisions are XIOM `Int` divisions and **truncate toward zero** (never
floor, never round-half). Every function evaluates its products first and then
performs exactly one truncating division, followed by exact additive terms.
Documented consequences:

- `mat_bulk_modulus(2000000000, 2500)` = `1333333333` (133333.3333 MPa).
- `mat_lame_lambda(2000000000, 3000)` = `1153846153` (115384.6153 MPa).
- `mat_von_mises` and `mat_principal_von_mises` apply `mat_isqrt` (floor) to an
  integer `D2 / 2`, so the equivalent stress is floored by up to one unit.

## 5. Formulas

### 5.1 Elastic constants

| Function | Formula |
|---|---|
| `mat_shear_modulus(e, nu)` | `e * 10000 / (2 * (10000 + nu))` |
| `mat_bulk_modulus(e, nu)` | `e * 10000 / (3 * (10000 - 2 * nu))` |
| `mat_lame_lambda(e, nu)` | `e * nu * 10000 / ((10000 + nu) * (10000 - 2 * nu))` |

### 5.2 Hooke's law (Voigt)

With `t = eps_xx + eps_yy + eps_zz` (the scaled trace):

| Function | Formula |
|---|---|
| `mat_hooke_normal(lam, g, t, eps_i)` | `(lam * t + 2 * g * eps_i) / 10000` |
| `mat_hooke_shear(g, gamma)` | `g * gamma / 10000` |
| `mat_hooke_inverse_normal(e, nu, sigma_i, other)` | `(10000 * sigma_i - nu * other) / e` |
| `mat_hooke_inverse_shear(g, tau)` | `10000 * tau / (2 * g)` |

`other` is the sum of the two normal stresses other than `sigma_i`.

### 5.3 Invariants

| Function | Formula |
|---|---|
| `mat_invariant_i1(sxx, syy, szz)` | `sxx + syy + szz` |
| `mat_von_mises_sq(...)` | `(sxx-syy)^2 + (syy-szz)^2 + (szz-sxx)^2 + 6*(syz^2 + sxz^2 + sxy^2)` |
| `mat_von_mises(...)` | `mat_isqrt(mat_von_mises_sq(...) / 2)` |
| `mat_principal_max_shear(s1,s2,s3)` | `(max - min) / 2` |
| `mat_principal_von_mises(s1,s2,s3)` | `mat_isqrt(((s1-s2)^2 + (s2-s3)^2 + (s3-s1)^2) / 2)` |

### 5.4 Yield checks

| Function | Formula |
|---|---|
| `mat_yield_flag(yield, vm)` | `1` if `vm > yield` else `0` |
| `mat_within_yield(yield, vm)` | `vm <= yield` |
| `mat_safety_factor_x1e4(yield, vm)` | `10000 * yield / vm`; `-1` if `vm <= 0` |

### 5.5 Temperature scaling

`mat_scale_at_temp(value, temps, factors, temp)`:

1. empty table -> `value`; one entry -> `value * factors[0] / 10000`,
2. `temp <= temps[0]` -> first factor; `temp > temps[n-1]` -> last factor,
3. otherwise find the bracketing pair `(t0, f0), (t1, f1)` and return
   `value * (f0 + (f1 - f0) * (temp - t0) / (t1 - t0)) / 10000`.

`temps` must be ascending; `temps` and `factors` are parallel with equal length.

## 6. Range and overflow

Inputs are 64-bit signed `Int`. The widest intermediates are the products in
`mat_von_mises_sq` (squares of scaled stress components) and the numerator of
`mat_scale_at_temp` (`value * factor`). The documented envelope is:

- stress components up to `1e7` scaled (1000 MPa): squares up to `1e14`,
  `mat_von_mises_sq` up to about `1.6e15` — far inside range;
- `value` up to `2e9` and factor up to `1e4`: product `2e13` — inside range.

`mat_mul_overflows(a, b)` is provided so callers can pre-check products outside
this envelope. Behaviour outside the envelope is undefined by this spec and not
tested.

## 7. API signatures

All functions are `pub`, free functions, `O(1)` (except `mat_scale_at_temp`,
which is `O(n)` in the table length), and import nothing.

## 8. Test plan

`tests/test_conformance.xi` (module `materials_tests`) runs 26 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Primary fixture: `E = 2e9`, `nu = 2500`, which
makes `G = 8e8` and `lambda = 8e8` exact while `K = 1333333333` truncates.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | shear modulus | nu=0.25 exact 8e8; nu=0.3 and (E=70 GPa, nu=0.33) truncated |
| t2 | bulk modulus | nu=0.25 `1333333333`; nu=0.3 `1666666666`; second material |
| t3 | Lame lambda | nu=0.25 exact; nu=0.3 `1153846153` |
| t4 | second material | G and K for E=70 GPa, nu=0.33; G doubling relation |
| t5 | Hooke normal | sigma_xx=224, sigma_yy=160, sigma_zz=96 MPa |
| t6 | Hooke consistency | sum 4.8e6, equal differences 640000 |
| t7 | Hooke shear | tau=960000 at gamma=0.0012; zero; antisymmetric |
| t8 | inverse normal | eps_xx=8, eps_yy=4, eps_zz=0 |
| t9 | inverse shear | tensor eps=6 from gamma=0.0012; signs; zero |
| t10 | round trip | stress -> strain -> stress exact on the fixture |
| t11 | I1 | `3+4+5=12`; signed; zero; stress triple |
| t12 | von Mises | uniaxial = axial; hydrostatic = 0 |
| t13 | von Mises shear | each shear alone -> `1732050` |
| t14 | von Mises mixed | `D2=1.875e12`, vm=`968245` |
| t15 | integer sqrt | 0,1,15,16,17,144,1e12 |
| t16 | max shear | `(300,100,-100) -> 2e6`; hydrostatic 0; negative triple |
| t17 | principal vm | `(300,100,-100) -> 3464101`; hydrostatic 0 |
| t18 | safety factor | 1.25 -> 12500; 1.0 -> 10000; 0.5 -> 5000; sentinel -1 |
| t19 | within yield | inclusive boundary; zero stress within |
| t20 | yield flag | 0 at/below, 1 above yield |
| t21 | unit metadata | scale 10000; code 1; consistency guard |
| t22 | temperature table | endpoints exact, midpoint 0.975 interpolation |
| t23 | temperature clamps | below-first and above-last clamp |
| t24 | empty table | returns value unchanged |
| t25 | overflow guard | small/zero false, wide true, signed true |
| t26 | algebraic relations | G and lambda satisfy their defining equations |

No assertion uses tolerance; all expected values are exact integers. The test
file builds two `Vec[Int]` tables for the scaling checks and calls every test
explicitly from `main`.

## 9. Known limitations

- Truncation toward zero is the only rounding; `mat_von_mises` floors.
- Principal stresses must be supplied by the caller; no eigen-solver.
- No material database, parsing or formatting; callers keep track of units.
- Yield is a simple scalar comparison against an equivalent stress (no
  anisotropy, no hardening).
- No overflow checking beyond `mat_mul_overflows`; see section 6.

## 10. Compiler / stdlib notes

Built against XIOM v0.62.2. No workarounds beyond the repo's standard
discipline: free functions only (no methods), no lambdas, no `Vec[Struct]`, no
`Result`/`Option`, no `match` inside the module, `module` without a trailing
semicolon, `use` lines with one, and the copyright + SPDX header on every `.xi`
file. The library module itself imports nothing; tests use `xiom.io` and
`xiom.test`. Loop progress is guaranteed by a strictly increasing index in
`mat_scale_at_temp` and by Newton's strictly decreasing estimate in
`mat_isqrt`.
