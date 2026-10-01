# xiom.geom3d

> **Status:** `incubating` -- conformance-tested (27/27); not yet published on the XIOM registry.
> **Scope:** one pure-XIOM module with deterministic fixed-point (scale 1e-4) 3D
> geometry: vec3, mat3/mat4, quaternions, ray intersections, and a scene helper.
> **Deps:** `xiom.std` only (the library imports `xiom.math` for integer
> min/max; tests use `xiom.test` and `xiom.io`). No FFI, no `Float64`, no `Vec`.

## What it is

`xiom.geom3d` implements a small, exactly-reproducible 3D math core on `Int`
fixed-point values: one raw unit is 1e-4 (raw 25000 = 2.5). Every scaling
division rounds half away from zero; every product and sum saturates at
`+/-2^63-1` instead of wrapping. The full rules and the intersection formulas
are pinned in `SPEC.md` and enforced by 27 conformance checks.

## API

| Function | Returns | Description |
|---|---|---|
| `g3_vec3(x,y,z)` | `G3Vec3` | Construct from raw components. |
| `g3_vec3_add/sub(a,b)` | `G3Vec3` | Component-wise (saturating). |
| `g3_vec3_scale(a,k)` | `G3Vec3` | a * k, k raw scalar (10000 = 1.0). |
| `g3_vec3_dot(a,b)` | `Int` | Raw dot product (sum of raw products, scaled once). |
| `g3_vec3_cross(a,b)` | `G3Vec3` | Right-handed cross product. |
| `g3_vec3_length2(a)` | `Int` | Raw sum of squares (1e-8 units). |
| `g3_vec3_normalize(a)` | `G3Vec3` | Unit vector; zero vector returns zero. |
| `g3_mat3_identity/transpose/mul` | `G3Mat3` | Row-major 3x3 operations. |
| `g3_mat3_transform_vec(m,v)` | `G3Vec3` | Linear transform. |
| `g3_mat4_identity/transpose/mul` | `G3Mat4` | Row-major affine 4x4. |
| `g3_mat4_rigid_inverse(m)` | `G3Mat4` | R^T / -R^T t for a rigid transform. |
| `g3_mat4_transform_point/vec(m,p)` | `G3Vec3` | Affine point / direction transform. |
| `g3_mat4_from_quat_translation(q,t)` | `G3Mat4` | Rigid matrix from quaternion + translation. |
| `g3_quat(w,x,y,z)` | `G3Quat` | Construct a quaternion. |
| `g3_quat_identity/conjugate` | `G3Quat` | Neutral and inverse rotation. |
| `g3_quat_mul(a,b)` | `G3Quat` | Hamilton product (b then a). |
| `g3_quat_normalize(q)` | `G3Quat` | Unit quaternion; zero returns identity. |
| `g3_quat_rotate_vec(q,v)` | `G3Vec3` | Rotate a vector. |
| `g3_quat_from_axis_angle(axis,angle)` | `G3Quat` | Angle in raw radians; axis normalized. |
| `g3_ray/origin/dir`, `g3_plane`, `g3_triangle`, `g3_aabb` | types | Constructors. |
| `g3_ray_plane(ray,plane)` | `G3Hit` | First t >= 0 hit, point included. |
| `g3_ray_triangle(ray,tri)` | `G3Hit` | Integer Moller-Trumbore, no divisions for barycentrics. |
| `g3_ray_aabb(ray,box)` | `G3Hit` | Slab method, t = 0 when the origin is inside. |
| `g3_aabb_overlap(a,b)` | `Bool` | Closed-box overlap (touching counts). |
| `g3_scene(position,rotation,scale)` | `G3Scene` | Uniform-scale rigid transform. |
| `g3_scene_transform_point/vector(s,v)` | `G3Vec3` | Apply a scene transform. |

```xi
use xiom.geom3d;
let wall = g3_plane(g3_vec3(0, 0, 10000), 5000);          // z = 0.5
let ray = g3_ray(g3_vec3(0, 0, 0), g3_vec3(0, 0, 20000)); // 2 units/s along z
let hit = g3_ray_plane(ray, wall);
// hit.hit = true, hit.t = 2500 (0.25 s), hit.pz = 5000 (z = 0.5)
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 27 `[PASS]` lines, then `xiom.geom3d: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.geom3d@0.1.0     # consumer
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
