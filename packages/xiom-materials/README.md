# xiom.materials

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** one dependency-free module modeling isotropic linear-elastic
> materials in deterministic fixed-point integer arithmetic.
> **Deps:** none (the library imports nothing; tests use `xiom.std` modules).

## What it is

`xiom.materials` turns Young's modulus `E` and Poisson's ratio `nu` into the
isotropic constants `G`, `K` and `lambda`, applies Hooke's law to 6-component
Voigt stress/strain vectors (and its inverse), computes the first invariant,
von Mises equivalent and principal max-shear stresses, checks a stress state
against a yield strength, and scales a property through a caller-supplied
temperature table. Every quantity is an `Int` at scale `1e-4` (`10000 == 1.0`).
No floats, no FFI, no allocation, no error paths.

## API

| Function | Returns | Description |
|---|---|---|
| `mat_scale()` | `Int` | Fixed-point scale, `10000`. |
| `mat_stress_unit_code()` | `Int` | Unit-system code, `1` (MPa, mm, N, 1e-4). |
| `mat_unit_consistent(scale)` | `Bool` | `scale == 10000`. |
| `mat_isqrt(n)` | `Int` | `floor(sqrt(n))`, `0` for `n <= 0`. |
| `mat_mul_overflows(a, b)` | `Bool` | Product-overflow guard. |
| `mat_shear_modulus(e_s, nu_s)` | `Int` | `G = E / (2 (1 + nu))`. |
| `mat_bulk_modulus(e_s, nu_s)` | `Int` | `K = E / (3 (1 - 2 nu))`. |
| `mat_lame_lambda(e_s, nu_s)` | `Int` | `lambda = E nu / ((1+nu)(1-2nu))`. |
| `mat_hooke_normal(lambda_s, g_s, trace_eps_s, eps_s)` | `Int` | Normal stress component. |
| `mat_hooke_shear(g_s, gamma_s)` | `Int` | Shear stress `G * gamma`. |
| `mat_hooke_inverse_normal(e_s, nu_s, sigma_s, other_sum_s)` | `Int` | Normal strain component. |
| `mat_hooke_inverse_shear(g_s, tau_s)` | `Int` | Tensor shear strain `tau / (2G)`. |
| `mat_invariant_i1(sxx, syy, szz)` | `Int` | First stress invariant. |
| `mat_von_mises_sq(...)` | `Int` | Twice the von Mises stress squared. |
| `mat_von_mises(sxx, syy, szz, syz, sxz, sxy)` | `Int` | Von Mises equivalent stress. |
| `mat_principal_max_shear(s1, s2, s3)` | `Int` | `(max - min) / 2`. |
| `mat_principal_von_mises(s1, s2, s3)` | `Int` | Von Mises from principal stresses. |
| `mat_yield_flag(yield_s, vm_s)` | `Int` | `1` when `vm > yield`, else `0`. |
| `mat_within_yield(yield_s, vm_s)` | `Bool` | `vm <= yield`. |
| `mat_safety_factor_x1e4(yield_s, vm_s)` | `Int` | `10000 * yield / vm`, `-1` if `vm <= 0`. |
| `mat_scale_at_temp(value_s, temps, factors, temp_s)` | `Int` | Linear-interpolated temperature scaling. |

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 26 `[PASS]` lines, then `xiom.materials: all tests passed`, exit 0.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
