# xiom.geom3d -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.geom3d` (`src/geom3d.xi`). Pure XIOM integer math, no FFI.
Imports: `xiom.math` (integer `min_int` / `max_int` only).

## 1. Scope

A deterministic 3D geometry core on `Int` fixed-point scalars:

- `G3Vec3`: construct, add, sub, scale, dot, cross, length2, normalize;
- `G3Mat3`: identity, multiply, transpose, transform vector;
- `G3Mat4`: identity, multiply, transpose, rigid inverse, transform point and
  vector, build from quaternion + translation;
- `G3Quat`: construct, identity, conjugate, multiply, normalize, rotate vector,
  from axis + angle;
- intersections: ray-plane, ray-triangle (integer Moller-Trumbore), ray-AABB
  (slab method), each returning `G3Hit` = `{ hit, t, px, py, pz }`;
- `G3Aabb` overlap test;
- `G3Scene`: uniform-scale rigid scene transform helper.

## 2. Non-goals

- No floating point anywhere (`Float64` is never used, not even internally).
- No `Vec` values in the module: every function is scalar/struct arithmetic.
- No general matrix inverse, no projections, no perspective divide.
- No mesh storage, no polygon clipping, no spheres/cylinders.
- No user-defined methods, lambdas, or function tables; free functions only.
- No FFI, file I/O, randomness, or wall-clock time.

## 3. Fixed-point model

1. **Scale.** Every scalar is an `Int` measured in units of 1e-4:
   `G3_SCALE = 10000` means 1.0. Raw 25000 = 2.5, raw 1 = 0.0001.
2. **Raw products.** A product of two raw values is at scale 1e-8. Products
   are accumulated raw (saturating) and the sum is divided by `G3_SCALE` once,
   so each dot / cross component / matrix entry / quaternion component carries
   at most one rounding step.
3. **Rounding.** Every scaling division, and every mixed-unit ratio (ray
   parameters, quaternion components, normalized components), rounds half away
   from zero. XIOM `/` truncates toward zero, so `_g3_div_round` normalizes the
   denominator to positive, computes the truncated quotient and the remainder
   `r` with `|r| < d`, and adds one unit of magnitude when
   `|r| >= ceil(d/2)` (computed as `r >= d - d/2`, overflow-safe).
4. **Saturation.** `_g3_sat_mul`, `_g3_sat_add`, `_g3_sat_sub` clamp to
   `+/-9223372036854775807` instead of wrapping. `_g3_sat_mul` checks
   `|a| > MAX / |b|` before multiplying. The symmetric range excludes
   `-9223372036854775808`; every function is total (no panics, no errors).
5. **Supported range.** Dot/cross/length2 sums saturate when the raw products
   exceed 2^63-1, i.e. beyond raw inputs of roughly 3.0e9 per component or
   length2 inputs beyond raw ~1.7e9. Values above that remain deterministic
   but saturated; callers keeping raw coordinates below ~1.7e9 (real ~1.7e5)
   never saturate normal use.
6. **Zero cases.** `g3_vec3_normalize(0,0,0) = (0,0,0)`.
   `g3_quat_normalize(0,0,0,0) = (G3_SCALE,0,0,0)` (identity).
   `g3_ray_plane` with `n . dir == 0` misses. `_g3_div_round(n, 0) = 0`
   (unreachable through the public API; kept total).
7. **Units of `length2`.** `g3_vec3_length2` returns the raw sum
   `x*x + y*y + z*z` **without** the scale division, i.e. scale 1e-8 per square
   unit: raw 1e8 corresponds to a real squared length of 1.0. Real length is
   `isqrt(length2) / G3_SCALE`, computed internally with an overflow-safe
   Newton floor isqrt (`_g3_isqrt`), which terminates because each loop step
   strictly decreases the estimate.

## 4. Types

```xi
pub type G3Vec3 = { x: Int; y: Int; z: Int; }
pub type G3Mat3 = { m00..m22: Int; }                 // row-major, m<row><col>
pub type G3Mat4 = { m00..m33: Int; }                 // row-major affine
pub type G3Quat = { w: Int; x: Int; y: Int; z: Int; }
pub type G3Aabb = { min: G3Vec3; max: G3Vec3; }      // inclusive corners
pub type G3Ray = { origin: G3Vec3; dir: G3Vec3; }    // dir need not be unit
pub type G3Plane = { normal: G3Vec3; d: Int; }       // normal . p = d
pub type G3Triangle = { a: G3Vec3; b: G3Vec3; c: G3Vec3; }
pub type G3Hit = { hit: Bool; t: Int; px: Int; py: Int; pz: Int; }
pub type G3Scene = { position: G3Vec3; rotation: G3Quat; scale: Int; }
```

`G3Mat4` follows the affine convention: `m03/m13/m23` is the translation and a
rigid transform's last row is `0,0,0,G3_SCALE`.

## 5. Constants

| Constant | Value | Meaning |
|---|---|---|
| `G3_SCALE` | 10000 | raw units per 1.0 |
| `G3_PI` | 31416 | pi to 1e-4 (3.1416) |
| `G3_HALF_PI` | 15708 | pi/2 to 1e-4 |

## 6. API signatures

```xi
pub fn g3_vec3(x: Int, y: Int, z: Int) -> G3Vec3
pub fn g3_vec3_add(a: G3Vec3, b: G3Vec3) -> G3Vec3
pub fn g3_vec3_sub(a: G3Vec3, b: G3Vec3) -> G3Vec3
pub fn g3_vec3_scale(a: G3Vec3, k: Int) -> G3Vec3
pub fn g3_vec3_dot(a: G3Vec3, b: G3Vec3) -> Int
pub fn g3_vec3_cross(a: G3Vec3, b: G3Vec3) -> G3Vec3
pub fn g3_vec3_length2(a: G3Vec3) -> Int
pub fn g3_vec3_normalize(a: G3Vec3) -> G3Vec3

pub fn g3_mat3_identity() -> G3Mat3
pub fn g3_mat3_mul(a: G3Mat3, b: G3Mat3) -> G3Mat3
pub fn g3_mat3_transpose(m: G3Mat3) -> G3Mat3
pub fn g3_mat3_transform_vec(m: G3Mat3, v: G3Vec3) -> G3Vec3

pub fn g3_mat4_identity() -> G3Mat4
pub fn g3_mat4_mul(a: G3Mat4, b: G3Mat4) -> G3Mat4
pub fn g3_mat4_transpose(m: G3Mat4) -> G3Mat4
pub fn g3_mat4_rigid_inverse(m: G3Mat4) -> G3Mat4
pub fn g3_mat4_transform_point(m: G3Mat4, p: G3Vec3) -> G3Vec3
pub fn g3_mat4_transform_vec(m: G3Mat4, v: G3Vec3) -> G3Vec3
pub fn g3_mat4_from_quat_translation(q: G3Quat, t: G3Vec3) -> G3Mat4

pub fn g3_quat(w: Int, x: Int, y: Int, z: Int) -> G3Quat
pub fn g3_quat_identity() -> G3Quat
pub fn g3_quat_conjugate(q: G3Quat) -> G3Quat
pub fn g3_quat_mul(a: G3Quat, b: G3Quat) -> G3Quat
pub fn g3_quat_normalize(q: G3Quat) -> G3Quat
pub fn g3_quat_rotate_vec(q: G3Quat, v: G3Vec3) -> G3Vec3
pub fn g3_quat_from_axis_angle(axis: G3Vec3, angle: Int) -> G3Quat

pub fn g3_ray(origin: G3Vec3, dir: G3Vec3) -> G3Ray
pub fn g3_plane(normal: G3Vec3, d: Int) -> G3Plane
pub fn g3_triangle(a: G3Vec3, b: G3Vec3, c: G3Vec3) -> G3Triangle
pub fn g3_aabb(min: G3Vec3, max: G3Vec3) -> G3Aabb
pub fn g3_ray_plane(ray: G3Ray, plane: G3Plane) -> G3Hit
pub fn g3_ray_triangle(ray: G3Ray, tri: G3Triangle) -> G3Hit
pub fn g3_ray_aabb(ray: G3Ray, box: G3Aabb) -> G3Hit
pub fn g3_aabb_overlap(a: G3Aabb, b: G3Aabb) -> Bool

pub fn g3_scene(position: G3Vec3, rotation: G3Quat, scale: Int) -> G3Scene
pub fn g3_scene_identity() -> G3Scene
pub fn g3_scene_transform_point(s: G3Scene, p: G3Vec3) -> G3Vec3
pub fn g3_scene_transform_vector(s: G3Scene, v: G3Vec3) -> G3Vec3
```

Complexity is O(1) per call except `g3_vec3_normalize`,
`g3_quat_normalize`, `g3_quat_from_axis_angle` and
`g3_mat4_from_quat_translation`, which also run the Newton isqrt (O(log n)).

## 7. Arithmetic formulas as implemented

### 7.1 Vec3

- `add/sub`: component-wise with saturating `Int` add/sub.
- `scale(a,k)`: component `round_half_away(a_i * k / G3_SCALE)`.
- `dot(a,b) = round_half_away((ax*bx + ay*by + az*bz) / G3_SCALE)` where the
  inner sum is saturating raw accumulation.
- `cross(a,b)`:
  - `x = round((ay*bz - az*by)/S)`, `y = round((az*bx - ax*bz)/S)`,
    `z = round((ax*by - ay*bx)/S)`, `S = G3_SCALE`.
  - The difference is saturating; the negative term is negated before summing.
- `length2(a) = sat(ax*ax) + sat(ay*ay) + sat(az*az)` (no division).
- `normalize(a)`: `L = isqrt(length2(a))`; if `L == 0` return zero; else each
  component is `round_half_away(a_i * G3_SCALE / L)`. With the 3-4-5 fixture
  this is exact: `(0.6, 0.8, 0)`.

### 7.2 Mat3

- `identity`: `diag(G3_SCALE)`.
- `mul(a,b)`: `c_ij = round((ai0*b0j + ai1*b1j + ai2*b2j)/S)`.
- `transpose`: `c_ij = a_ji`.
- `transform_vec(m,v)`: `round((mi0*vx + mi1*vy + mi2*vz)/S)` per row.

### 7.3 Mat4

- `mul(a,b)`: `c_ij = round((sum_k a_ik*b_kj)/S)`, k = 0..3.
- `transpose`: full 4x4 swap.
- `transform_point(m,p)`: rows compute
  `round((mi0*px + mi1*py + mi2*pz + mi3*G3_SCALE)/S)`; the `mi3` term adds
  the translation exactly.
- `transform_vec(m,v)`: same without the `mi3` term.
- `rigid_inverse(m)`: upper-left `R^T` (`m_ij -> m_ji` for i,j in 0..2),
  translation `-R^T t` with `(R^T t)_i = round((mi0*m03 + mi1*m13 + mi2*m23)/S)`
  (column i of the original R), last row `0,0,0,G3_SCALE`. The input is assumed
  rigid; it is not verified. For a rigid matrix `M * rigid_inverse(M)` is the
  identity up to the documented rounding.
- `from_quat_translation(q,t)`: `q` is normalized first, then the standard
  rotation matrix is formed with `xx,xy,... = raw products`:
  - `m00 = S - round(2*(yy+zz)/S)`, `m01 = round(2*(xy-wz)/S)`,
    `m02 = round(2*(xz+wy)/S)`,
  - `m10 = round(2*(xy+wz)/S)`, `m11 = S - round(2*(xx+zz)/S)`,
    `m12 = round(2*(yz-wx)/S)`,
  - `m20 = round(2*(xz-wy)/S)`, `m21 = round(2*(yz+wx)/S)`,
    `m22 = S - round(2*(xx+yy)/S)`,
  - translation `t`, last row `0,0,0,S`.

### 7.4 Quaternions

- `conjugate(q) = (w, -x, -y, -z)`.
- `mul(a,b)` (Hamilton product, b applied first):
  - `w = round((aw*bw - ax*bx - ay*by - az*bz)/S)`
  - `x = round((aw*bx + ax*bw + ay*bz - az*by)/S)`
  - `y = round((aw*by - ax*bz + ay*bw + az*bx)/S)`
  - `z = round((aw*bz + ax*by - ay*bx + az*bw)/S)`
- `normalize(q)`: `L = isqrt(w^2+x^2+y^2+z^2)`; if `L == 0` return identity;
  else component `round(q_i * S / L)`.
- `rotate_vec(q,v)` uses the expanded form
  `v' = (w^2 - |u|^2) v + 2 u (u . v) + 2 w (u x v)` with `u = (x,y,z)`,
  each scaled term with one rounding and a saturating sum. A non-unit `q`
  scales the result by `|q|^2`; normalize first for a pure rotation.
- `from_axis_angle(axis, angle)`:
  1. normalize `axis`; a zero axis returns identity;
  2. `half = round_half_away(angle / 2)` in raw radians;
  3. `c = cos(half)`, `s = sin(half)` (section 8);
  4. `q = (c, s*ux, s*uy, s*uz)` with one rounding per component;
  5. return `normalize(q)`.

### 7.5 Ray-plane

With `den = n . dir` and `num = d - n . o` (both raw dots as in 7.1):

1. miss when `den == 0` (parallel);
2. `t = round_half_away(num * G3_SCALE / den)`; miss when `t < 0`;
3. point `= o + dir * t` (component-wise `round(dir_i * t / S)` then
   saturating add).

### 7.6 Ray-triangle (integer Moller-Trumbore)

With `e1 = b-a`, `e2 = c-a`, `h = dir x e2`, `a = e1 . h`, `s = o-a`,
`q = s x e1` (all raw as in 7.1):

1. miss when `a == 0` (degenerate / parallel);
2. `u_num = s . h`, `v_num = dir . q` (raw, no division);
3. barycentric tests cross-multiplied, exact for the rounded dots:
   - `a > 0`: hit iff `u_num >= 0`, `v_num >= 0`, `u_num + v_num <= a`;
   - `a < 0`: hit iff `u_num <= 0`, `v_num <= 0`, `u_num + v_num >= a`;
4. `t = round_half_away((e2 . q) * G3_SCALE / a)`; miss when `t < 0`;
5. point `= o + dir * t`.

`u_num + v_num` and the comparisons are saturating adds.

### 7.7 Ray-AABB (slab method)

Per axis (`o, d, mn, mx`):

- `d == 0`: outside `[mn, mx]` means miss; inside means the axis does not
  constrain the interval (lo = MIN, hi = MAX);
- otherwise `t1 = round_half_away((mn-o) * S / d)`,
  `t2 = round_half_away((mx-o) * S / d)`, `lo = min(t1,t2)`, `hi = max(t1,t2)`.

Then `tmin = max(lo_x, lo_y, lo_z)`, `tmax = min(hi_x, hi_y, hi_z)`.
Miss when `tmax < tmin` or `tmax < 0` (interval entirely behind the origin).
Otherwise the hit distance is `max(tmin, 0)` (the origin itself when it is
inside the box) and the point is `o + dir * t`. Box bounds are inclusive.

### 7.8 AABB overlap

`a` and `b` overlap iff they overlap on all three axes with
`a.min_i <= b.max_i` and `b.min_i <= a.max_i`. Touching faces count as
overlap.

### 7.9 Scene transform

`G3Scene = { position, rotation, scale }` is a uniform-scale rigid transform:

- `transform_point(s,p) = rotate(rotation, scale(p)) + position`, where
  `scale(p)` is per-component `round(p_i * s.scale / S)`;
- `transform_vector(s,v) = rotate(rotation, scale(v))` (translation ignored);
- `identity` scene: position zero, identity quaternion, scale `G3_SCALE`.

A non-unit rotation quaternion scales both results by `|q|^2`.

## 8. Trigonometry (from_axis_angle only)

`sin` uses the degree-11 Taylor polynomial on `|x| <= pi/2`
(`x - x^3/3! + x^5/5! - x^7/7! + x^9/9! - x^11/11!`), each term built with
one rounding per fixed-point multiply and divided by its integer factorial with
round-half-away. Angles are first reduced to `[-pi, pi]` by subtracting the
nearest multiple of `2*pi` (the multiple count is scaled by `G3_SCALE`, then
`k*2*pi` uses the raw product). `sin` extends to all angles with the
`sin(pi - x)` reflection; `cos(theta) = sin(theta + pi/2)` after wrapping.

`G3_PI = 31416` (pi rounded to 1e-4), so angle results are accurate to about
1e-4; the important exact outputs are pinned by the suite:
`from_axis_angle(Z, 0) = (10000,0,0,0)`,
`from_axis_angle(Z, +/-pi) = (0,0,0,+/-10000)`,
`from_axis_angle(Z, pi/2) = (7072,0,0,7072)` after normalization.

## 9. Total behavior and errors

Every function is total; there are no `Result` / `Option` returns and no
panics. Degenerate inputs take the documented fallbacks of section 3.6.
Neither the plane orientation nor the ray direction is required to be unit
length: all formulas use raw divisions, so any non-zero direction works.

## 10. Test plan

`tests/test_conformance.xi` (module `geom3d_tests`) runs 27 named checks with
`assert(cond, "name")`, one function per check plus fresh-value fixture
constructors; `main` returns the failure count (0 = green).

| # | Check | Pins |
|---|---|---|
| t1 | vec3 add/sub | component-wise signed values |
| t2 | vec3 scale | 2.5*2 = 5; rounding at 0.5 ulp both signs |
| t3 | overflow guards | saturating mul/add/sub at 2^63-1 and scale rounding |
| t4 | dot | 3-4-5 squared; orthogonal axes; sub-ulp sum -> 0 |
| t5 | cross | X x Y = Z; pinned mixed product; anti-commutativity |
| t6 | length2 / normalize | raw 1e-8 units; 3-4-5 -> 0.6/0.8; zero vector; unit input |
| t7 | normalize sign | odd rounding keeps direction |
| t8 | mat3 transpose/identity | exact entries |
| t9 | mat3 multiply | Rz * Rz^T = identity |
| t10 | mat3 transform_vec | 90-degree axis mapping |
| t11 | mat4 identity/transpose | point, vector, translation moved to last row |
| t12 | from_quat_translation | diag(-1,-1,1) + (1,2,3) |
| t13 | mat4 transform point/vector | translation applied / ignored |
| t14 | rigid inverse | pinned inverse; M * M^-1 = identity; point round trip |
| t15 | quat identity/conjugate | exact fields |
| t16 | quat multiply | identity neutral; q90^2 = 180-Z; q180^2 = -identity |
| t17 | quat normalize | 3-0-0-4 -> 0.6/0.8; zero -> identity; q*conj(q) = identity |
| t18 | quat rotate | 180-Z axis mapping; identity |
| t19 | rotation composition | X then Z = 180 about Y, axes pinned |
| t20 | 90-degree literal | (0,39999,0) and (-39999,0,0); dot = 0; length2 pinned |
| t21 | from_axis_angle | 0, +/-pi exact; non-unit axis; pi/2 = 7072/7072; zero axis |
| t22 | ray-plane | hits t = 0.5/0.25, negative denominator, misses, rounded t |
| t23 | ray-triangle | interior/vertex/edge/below hits at t = 1; all misses |
| t24 | ray-AABB | entry 0.5, inside t = 0, negative direction, touch, misses |
| t25 | AABB overlap | touching, 1-ulp gap, containment, separation |
| t26 | scene identity/TRS | scale then translate; vector ignores translation |
| t27 | scene rotation | 180-Z flip with scale and translation |

## 11. Known limitations

- **1e-4 resolution.** Fixed-point rounding is visible: a 90-degree
  quaternion literal rotates (4,0,0) to (0,3.9999,0), not exactly (0,4,0).
  Exact identities are available where the fixtures pin them (0, 180, 360
  degrees about an axis) because sin/cos are exact there.
- **Rigid inverse unchecked.** `g3_mat4_rigid_inverse` assumes an orthonormal
  rotation and last row `0,0,0,1`; it does not verify and will silently return
  a wrong matrix otherwise.
- **Saturation.** Extreme raw values (beyond ~1.7e9 for length2) saturate
  rather than wrap, which is total but inaccurate by design.
- **No general inverse / projection / mesh operations** (section 2).
- **Trig accuracy** ~1e-4 (pi at 1e-4, degree-11 polynomial); insufficient for
  long chains of angle-derived rotations.
- **From-axis-angle only.** There is no way to recover angle/axis from a
  quaternion, and no slerp/lerp.

## 12. Compiler notes (v0.62.2)

- No `Vec` is used, so no `Vec[Str].push` / element-lowering workarounds were
  needed and no parallel-vector mirroring is required.
- Structs are moved on every by-value call, so internal helpers take `Int`
  scalars (or the public functions read scalar fields) instead of passing the
  same struct value twice; the test suite uses fresh-value constructor helpers
  for fixtures.
- `_g3_wrap_two_pi` subtracts `k * 2*pi` with the **raw** product (the turn
  count `k` is not a fixed-point value); using the scaled multiply here left a
  6-ulp error in `from_axis_angle(pi)` during development.
