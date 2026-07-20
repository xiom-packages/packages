# xiom-eigen — SPEC

**Phase**: 2 (Scientific) | **Priority**: HIGH
**Status**: SPEC only | **Depends on**: xiom.ffi

## What it wraps
Eigen — C++ template library for linear algebra. Header-only.
Used in robotics (ROS), computer vision, physics simulation.

## Dependencies
| What | How | Size |
|------|-----|------|
| Eigen 3.4 | `apt install libeigen3-dev` or download headers | ~5MB headers |

## Bundling strategy
**Header-only download.** No DLL. Compile into bridge .obj.
`wget https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz`

## API (minimal)
```xiom
pub fn matrix_new(rows, cols) -> Result[Matrix, Str]
pub fn matrix_mul(a, b) -> Result[Matrix, Str]
pub fn matrix_transpose(m) -> Matrix
pub fn matrix_inverse(m) -> Result[Matrix, Str]
pub fn eigen_sym(m) -> Result[(Vec[Float64], Matrix), Str]
pub fn svd(m) -> Result[(Matrix, Vec[Float64], Matrix), Str]
```

## Effort: Weekend
