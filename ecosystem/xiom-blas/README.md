# xiom:blas — Linear Algebra

BLAS/LAPACK FFI bindings. High-performance linear algebra for ML and scientific computing.

```xiom
use xiom.blas;

fn main() -> Result[Unit, Str] {
  let a = matrix_new(2, 2);
  let b = matrix_new(2, 2);
  let c = matmul(&a, &b)?;
  return Ok(());
}
```
