# xiom.relativity -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.relativity` (`src/relativity.xi`). Pure XIOM, no FFI. Scalars
only: `Int` permille speeds, `Float64` physics quantities; no
`Vec[Float64]`, no structs, no methods.

## 1. Scope

Special-relativity helpers for a single collinear (1-D) speed, expressed as a
permille integer and everything derived from it:

- `rel_lorentz_permille` -- Lorentz factor `gamma`,
- `rel_time_dilation_s` -- `gamma * proper_s`,
- `rel_length_contraction_m` -- `proper_m / gamma`,
- `rel_velocity_add_permille` -- relativistic collinear velocity addition on
  the permille grid (integer),
- `rel_energy_j` -- rest energy `m * c^2`,
- `rel_kinetic_energy_j` -- `(gamma - 1) * m * c^2`,
- `rel_momentum_ns` -- `gamma * m * v` with `v = beta * c`,
- `rel_beta_from_bits` -- clamp any `Int` into the valid speed range.

Every entry point is a free function; the only imports are
`xiom.convert.int_to_float` and the scalar `xiom.math.sqrt` /
`xiom.math.abs_float` wrappers from `xiom.std`.

## 2. Non-goals

- No general relativity: no gravity, curvature, geodesics, gravitational
  redshift, or accelerated frames.
- No Lorentz transformations between frames, no 4-vectors, no transverse or
  non-collinear velocity addition, no matrices.
- No dynamics (forces, collisions, decays), no radiation/Doppler/aberration,
  no thermodynamics of relativistic gases.
- No `Result`/error channel: invalid beta uses the documented `0.0` sentinel
  (section 3.3), like the other scalar `xiom.*` helpers.
- No unit system or dimensional analysis; each function's unit is fixed in
  its name and documented in README.md.
- No structs, no `Vec[StructType]`, no `Vec[fn]` dispatch, no lambdas, no
  methods, no `Vec[Float64]` (XIOM v0.61.3 constraints).

## 3. Conventions

### 3.1 Units and constants

| Name | Value | Meaning |
|---|---|---|
| `_REL_C_M_PER_S` | `299792458.0` | speed of light c in m/s (exact SI value) |
| permille scale | `1000` | `beta = beta_permille / 1000.0` |
| energy unit | joule | `kg * (m/s)^2` |
| momentum unit | kg*m/s (N*s) | `kg * m/s` |

The representable speed range is `-0.999 c .. +0.999 c` (`+-999` permille);
`+-1000` permille is exactly `|beta| = 1` and is rejected, so no input can
produce a division by zero or a NaN.

### 3.2 Valid beta

`beta_permille` is **valid** iff `-999 <= beta_permille <= 999`, i.e. beta is
inside the open interval `(-1000, 1000)` in permille. Equivalently, an input
is invalid when `beta_permille <= -1000 || beta_permille >= 1000`, so both the
threshold itself and every super-luminal value (`5000`, `1000000`, ...) are
invalid.

### 3.3 Invalid-beta policy

For every beta-taking entry point other than velocity addition, invalid beta
returns the exact `Float64` `0.0` (a deterministic sentinel; never NaN, never
a panic):

| Function | Invalid-beta result |
|---|---|
| `rel_lorentz_permille` | `0.0` |
| `rel_time_dilation_s` | `0.0` |
| `rel_length_contraction_m` | `0.0` |
| `rel_kinetic_energy_j` | `0.0` |
| `rel_momentum_ns` | `0.0` |

`0.0` is distinguishable from every valid result except where the physics
itself is zero (`proper_s = 0`, `mass = 0`, `beta = 0`), which is inherent to
a sentinel-based API and documented in README.md.

`rel_velocity_add_permille` and `rel_beta_from_bits` cannot fail: the former
clamps both inputs with the latter and always returns an `Int` in
`[-1000, 1000]`.

## 4. Formulas

Let `b = beta_permille / 1000.0` (Float64, computed via
`xiom.convert.int_to_float(beta_permille) / 1000.0`).

### 4.1 Lorentz factor

```
gamma(b) = 1 / sqrt(1 - b*b)          // valid beta only, else 0.0
```

`gamma(0) = 1`, `gamma(+-600) = 1.25` (since `1 - 0.36 = 0.64`),
`gamma(+-800) = 5/3`, `gamma(+-999) = 1/sqrt(0.001999) = 22.366272042129371`.

### 4.2 Time dilation

```
rel_time_dilation_s(proper_s, beta) = proper_s * gamma(beta)   // invalid -> 0.0
```

### 4.3 Length contraction

```
rel_length_contraction_m(proper_m, beta) = proper_m / gamma(beta)  // invalid -> 0.0
```

The contraction factor `1/gamma = sqrt(1 - b*b)` lies in `(0, 1]`, so the
moving length never exceeds the proper length. `L(gamma)` and `1/L` are
inverse only up to IEEE-754 rounding (section 5).

### 4.4 Velocity addition (integer)

Both inputs are first clamped: `u = clamp(u_permille)`, `v = clamp(v_permille)`
with `clamp(x) = max(-999, min(999, x))` -- see `rel_beta_from_bits`. Then,
with integer arithmetic that **truncates toward zero** at both divisions
(`/` on `Int` in XIOM v0.61.3):

```
rel_velocity_add_permille(u, v) = 1000 * (u + v) / (1000 + (u * v) / 1000)
```

Equivalently `1000 * (u+v) / (1000 + trunc(u*v/1000))`. This is the permille
form of `beta = (bu + bv) / (1 + bu*bv)`; the mathematically exact permille
value would be `1e6 * (u+v) / (1e6 + u*v)`.

Pinned values:

| u | v | result | note |
|---|---|---|---|
| 0 | 0 | 0 | exact |
| 500 | 500 | 800 | exact (0.5+0.5 -> 0.8) |
| 600 | 600 | 882 | exact value 882.3529... truncated |
| 300 | 700 | 826 | exact value 826.4462... truncated |
| -500 | 500 | 0 | exact |
| -500 | -500 | -800 | exact |
| -800 | 500 | -500 | exact |
| 999 | 999 | 1000 | **documented edge**: the inner `/1000` truncates 998.001 to 998, so the quotient becomes exactly 1000 although the exact rational value is 999.9995 permille |
| -999 | -999 | -1000 | mirror of the edge above |

The result never leaves `[-1000, 1000]` and the operation is commutative.

### 4.5 Energy, kinetic energy, momentum

```
rel_energy_j(mass_kg)                = mass_kg * c * c
rel_kinetic_energy_j(mass_kg, beta)  = (gamma(b) - 1) * mass_kg * c * c   // invalid -> 0.0
rel_momentum_ns(mass_kg, beta)       = gamma(b) * mass_kg * (b * c)       // invalid -> 0.0
```

with `c = _REL_C_M_PER_S`. `c^2` as a Float64 is the nearest double to the
exact integer `89875517873681764`, i.e. `8.987551787368176e16`.
`rel_kinetic_energy_j` is exactly `0.0` at `beta = 0` (because
`gamma(0) - 1 = 0`), and `rel_momentum_ns` is exactly `0.0` at `beta = 0`
(because `v = 0`). Kinetic energy and time dilation are even in beta;
momentum is odd in beta.

### 4.6 Beta clamp

```
rel_beta_from_bits(x) = x        for -999 <= x <= 999
                      = -999     for x < -999
                      = 999      for x > 999
```

Total function over `Int`; no other value can be returned.

## 5. Precision and rounding

- All floating-point work is IEEE-754 binary64 (`Float64`); `sqrt`/`fabs`
  come from libm via `xiom.math`, so every primitive is correctly rounded to
  nearest-even. The module adds no other floating-point rounding.
- `gamma` is computed exactly as `1.0 / sqrt(1.0 - b * b)` on the
  `int_to_float`-converted `b`. Values that are exactly representable are
  exact: `gamma(0) = 1.0`, `gamma(+-600) = 1.25`, `gamma(+-200)` (not pinned)
  etc. `gamma(+-800) = 1.666666666666667` (the double nearest to 5/3, which
  is `1.6666666666666666...` rounded), `gamma(+-999) = 22.366272042129371`.
- Derived quantities inherit one rounding per operation:
  `proper_s * gamma` (one multiply), `proper_m / gamma` (one divide),
  `mass * c * c` (two multiplies, left-to-right), `(gamma - 1) * mass * c * c`
  (three multiplies), `gamma * mass * (b * c)` (one multiply for `b * c`, then
  two more).
- `rel_length_contraction_m(L, b) * rel_lorentz_permille(b)` is `L` only
  within a few ulps; the tests assert it within `1e-6` absolute for `O(1)`
  magnitudes.
- Integer arithmetic in `rel_velocity_add_permille` truncates toward zero
  **twice** (inner `u * v / 1000`, then the final division); there is no
  round-to-nearest anywhere in the integer path. See section 4.4 for the
  pinned edge cases.
- `Int` overflow is not reachable: `|u * v| <= 998001`, `|1000 * (u + v)| <=
  1998000`, `1000 + (u * v) / 1000` is in `[1, 1998]`.

## 6. Test plan

`tests/test_conformance.xi` (module `relativity_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Float64 equality is checked with the absolute
helper `approx(a, b) = fabs(a - b) < 1e-6`; because that tolerance is
absolute, `c^2`-scale quantities are divided by a `c^2` reference computed
inside the test (or compared through ratios) before `approx` is applied, so
no assertion is weakened.

| # | Check | Semantics pinned |
|---|---|---|
| t01 | `lorentz(0)`, `lorentz(+-1)` | gamma(0) = 1; ultra-slow speeds stay within 1e-6 of 1 |
| t02 | `lorentz(600)` | 1.25 = 5/4 exactly (within tolerance) |
| t03 | `lorentz(800)` | 5/3 = 1.6666667 pinned approx |
| t04 | `lorentz(999)` | 22.3662720421294 pinned approx, inside (22, 23) |
| t05 | `lorentz(-999/-600/-800)` | gamma is even in beta |
| t06 | invalid beta `1000/-1000/5000/-5000/1000000` | sentinel 0.0; +-999 still valid and > 1 |
| t07 | dilation 1 s @ 0.6c; 2.5 s @ 0; 10 s @ 0.8c; 0 s @ 0.6c | 1.25 s; identity; 50/3 s; zero |
| t08 | contraction 1 m @ 0.6c; 2.5 m @ 0; L*gamma inverse | 0.8 m; identity; product = L0 |
| t09 | dilation and contraction invalid beta | 0.0 in all channels |
| t10 | `500+500=800`, `600+600=882`, `0+600=600` | canonical addition anchors |
| t11 | `0+0=0`, `500+0`, `0+-500`, `999+0`, `0+-999` | zero is an identity |
| t12 | `-500+-500`, `-500+500`, `500+-500`, `-800+500` | negatives mirror; cancellation to 0 |
| t13 | `300+700=826`, commutativity, `999+999=1000` | truncation toward zero; documented edge |
| t14 | `rel_beta_from_bits` on 0/+-500/+-999/+-1000/+-12345 | clamp boundaries |
| t15 | `5000+0=999`, `-5000+0=-999`, `5000+5000=1000`, `5000+-5000=0`, `1000+0=999` | clamping inside velocity addition |
| t16 | `E(1 kg)` vs `c^2` and `8.987551787368176e16`; `E(2)/E(1)=2`; `E(0)=0` | charged rest-energy pin, linearity |
| t17 | `K(1 kg, 0)`, `K(0 kg, 0.6c)`, invalid beta | exactly 0.0 in all cases |
| t18 | `K(1 kg, 0.6c)/c^2 = 0.25`, absolute vs `0.25*c^2`, `K(-600)=K(600)` | kinetic anchor; evenness |
| t19 | `p(1 kg, 0)`, `p(0 kg, 0.6c)`, invalid beta | exactly 0.0 in all cases |
| t20 | `p(1 kg, 0.6c) = 224844343.5` (within 1e-6), `p(-600) = -p(600)`, `p(2 kg)/p(1 kg) = 2` | momentum anchor; oddness; linearity |

## 7. Compiler / stdlib notes

v0.61.3 idioms used, following `xiom.geo` / `xiom.signal`:

- Free functions only (no methods, no lambdas); no `Vec[fn]` dispatch -- the
  suite calls `t01()` ... `t20()` and prints `r.passed` / `r.name`.
- No `Vec` and no structs at all; every value is a scalar `Int` or `Float64`,
  so no typed-Vec-read or `Vec[StructType]` workaround is needed.
- `module xiom.relativity` (no semicolon); `use ...;` lines end with `;`.
- `Int -> Float64` goes through `xiom.convert.int_to_float` (no implicit
  coercion in this compiler).
- All accesses of `r.passed` / `r.name` are direct field reads on a
  `TestResult` local, as in the other suites.
- Copyright and SPDX headers are present in `package.xi`, `src/relativity.xi`
  and `tests/test_conformance.xi`.

## 8. Known limitations

- 1-D collinear kinematics only; no vector or frame transformations.
- Permille granularity: speeds are quantized to 0.001 c and `|beta| >= 1` is
  not representable; `999 + 999` hits the documented 1000 edge instead of the
  exact 999.9995 permille.
- The `0.0` invalid-beta sentinel is indistinguishable from the physically
  zero results (`beta = 0`, zero mass, zero proper time).
- `rel_energy_j` does not validate mass (negative mass is accepted and
  returns negative energy, linearity is preserved).
- No dynamics, no Doppler/aberration, no general relativity.
- Floating-point results carry the usual few-ulp IEEE-754 error; the module
  does not provide compensated or higher-precision summation.

## 9. Provenance of expected values

Every pinned value follows from the closed-form formulas above and was
recomputed in IEEE-754 double precision before being pinned:

- `gamma(999) = 1/sqrt(1 - 0.999^2) = 22.366272042129371` (double);
- `gamma(800) = 5/3 -> 1.666666666666667` (double, within 1e-6 of the pinned
  decimal 1.6666667);
- `c^2 = 8.987551787368176e16` J for 1 kg (nearest double to 89875517873681764);
- `p(1 kg, 0.6c) = 1.25 * 0.6 * c = 224844343.49999997` (double; the pinned
  decimal 224844343.5 differs by ~3e-8, inside the 1e-6 tolerance);
- integer velocity-addition rows were computed with the section 4.4 formula
  by hand.

The exactness claims (`gamma(0) = 1`, `gamma(600) = 1.25`, `L(1 m, 0.6c) =
0.8 m`, `E(0) = 0`, `K(..., 0) = 0`, `p(..., 0) = 0`) were verified with the
double-precision arithmetic of the formula; no assertion was relaxed to make
the suite pass.
