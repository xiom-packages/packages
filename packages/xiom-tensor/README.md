# xiom.tensor

> **Status:** `incubating` -- conformance-tested (29/29); not yet published on the XIOM registry.
> **Scope:** a deterministic n-dimensional integer tensor core over a flat
> `Vec[Int]` plus a shape: validated construction, row-major strides,
> coordinate and flat get/set, reshape, rank-2 transpose, axis-0 slicing with
> an offset map, broadcasting add, elementwise add/multiply, axis sum/max
> reductions and a canonical text dump.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (the library imports `xiom.convert`;
> tests additionally use `xiom.test`, `xiom.io`, `xiom.string` and
> `xiom.string.compare`).

## What it is

`xiom.tensor` is an integer-only n-dimensional array ("tensor") library with
**no floating point, no FFI, no views and no global state**. A tensor is a
`{ rank, dims, data }` record: `dims` holds exactly `rank` non-negative
dimension sizes and `data` is the row-major flat buffer of exactly
`product(dims)` elements. Rank 0 is allowed and means a one-element scalar
(the empty product is 1), so reductions of rank-1 tensors can return scalars.

Every operation is deterministic and pure:

- **Validated construction** (`tensor_new`, `tensor_from_flat`): rank 0..6,
  non-negative dims, a checked shape product, and an element-capacity guard
  (`tensor_max_elements()` = 1000000).
- **Geometry** (`tensor_rank`, `tensor_dim`, `tensor_numel`, `tensor_shape`,
  `tensor_stride`, `tensor_strides`): row-major strides
  `stride[rank-1] = 1`, `stride[k] = dims[k+1] * stride[k+1]`.
- **Indexing** (`tensor_offset`, `tensor_get`, `tensor_get_flat`,
  `tensor_set`, `tensor_set_flat`): coordinate -> flat offset
  `sum(k) i_k * stride[k]` with full rank/bounds checks; writes only through
  an explicit `&mut Tensor` and only inside the arithmetic envelope.
- **Transforms**: `tensor_reshape` (same element count only, flat order
  preserved) and `tensor_transpose2` (rank 2 only, `out[col,row] =
  t[row,col]`).
- **Slicing**: `tensor_slice_axis0` copies rows `start .. start+count`; the
  companion `tensor_slice_offsets_axis0` returns the flat source offsets of
  that copy (the offset map).
- **Arithmetic**: `tensor_broadcast_add` applies NumPy-style right-aligned
  broadcasting; `tensor_add` / `tensor_mul` require exactly equal shapes.
  Every arithmetic step is checked; overflow fails closed with `Err` instead
  of wrapping.
- **Reductions**: `tensor_sum_axis` and `tensor_max_axis` drop one axis;
  the empty sum is 0 and a maximum over an empty axis is an error (no empty
  identity).
- **Canonical dump**: `tensor_dump` renders
  `tensor rank=R dims=[...] data=[...]` on one line.

**Copy semantics throughout.** Construction copies the caller's values,
`tensor_shape`/`tensor_data`/`tensor_strides` return fresh vectors, and
reshape / transpose / slice / arithmetic always return new tensors. There
are no views and no aliasing, so mutating an input or a returned copy can
never change another tensor. See `SPEC.md` for the exact rules and the error
catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `tensor_max_rank()` / `tensor_max_elements()` | `Int` | Documented limits (6 / 1000000). |
| `tensor_new(rank, dims)` | `Result[Tensor, Str]` | Zero-filled tensor of a validated shape. |
| `tensor_from_flat(rank, dims, values)` | `Result[Tensor, Str]` | Tensor holding a copy of `values`; length must match the shape, values must lie in `[-INT_MAX, INT_MAX]`. |
| `tensor_rank(t)` / `tensor_numel(t)` | `Int` | Rank and `product(dims)`. |
| `tensor_dim(t, axis)` | `Int` | Axis size, `-1` out of range. |
| `tensor_shape(t)` | `Vec[Int]` | Copy of `dims`. |
| `tensor_data(t)` | `Vec[Int]` | Copy of the flat buffer. |
| `tensor_stride(t, axis)` | `Int` | Row-major stride, `-1` out of range. |
| `tensor_strides(t)` | `Vec[Int]` | Copy of all strides. |
| `tensor_offset(t, indices)` | `Result[Int, Str]` | Coordinate -> flat offset. |
| `tensor_get(t, indices)` | `Result[Int, Str]` | Value at a coordinate. |
| `tensor_get_flat(t, offset)` | `Result[Int, Str]` | Value at a flat offset. |
| `tensor_set(&mut t, indices, value)` | `Result[Int, Str]` | Write at a coordinate; returns the offset written. |
| `tensor_set_flat(&mut t, offset, value)` | `Result[Int, Str]` | Write at a flat offset. |
| `tensor_reshape(t, rank, dims)` | `Result[Tensor, Str]` | Reshape with the same element count (copy). |
| `tensor_transpose2(t)` | `Result[Tensor, Str]` | Rank-2 transpose (copy). |
| `tensor_slice_axis0(t, start, count)` | `Result[Tensor, Str]` | Row window copy along axis 0. |
| `tensor_slice_offsets_axis0(t, start, count)` | `Result[Vec[Int], Str]` | Flat source offsets of that window. |
| `tensor_broadcast_add(a, b)` | `Result[Tensor, Str]` | Broadcast-compatible elementwise add. |
| `tensor_add(a, b)` / `tensor_mul(a, b)` | `Result[Tensor, Str]` | Elementwise add / multiply; shapes exactly equal. |
| `tensor_sum_axis(t, axis)` / `tensor_max_axis(t, axis)` | `Result[Tensor, Str]` | Reduce one axis; the axis disappears. |
| `tensor_dump(t)` | `Str` | Canonical single-line rendering. |

The complete error catalog is in `SPEC.md`.

## Usage

```xi
use xiom.tensor;
use xiom.io;

fn main() -> Int {
  var dims = Vec[Int].new();
  dims.push(2);
  dims.push(3);
  var values = Vec[Int].new();
  values.push(1); values.push(2); values.push(3);
  values.push(4); values.push(5); values.push(6);

  let built = tensor_from_flat(2, &dims, &values);
  if !built.is_ok { return 1; }
  let t = built.value;              // [[1,2,3],[4,5,6]]

  var rdims = Vec[Int].new();
  rdims.push(3);
  var rvalues = Vec[Int].new();
  rvalues.push(10); rvalues.push(20); rvalues.push(30);
  let rowr = tensor_from_flat(1, &rdims, &rvalues);
  if !rowr.is_ok { return 1; }
  let row = rowr.value;

  let sumr = tensor_broadcast_add(&t, &row);
  if !sumr.is_ok { return 1; }
  let sum = sumr.value;
  io.println(tensor_dump(&sum));
  // tensor rank=2 dims=[2,3] data=[11,22,33,14,25,36]

  let colr = tensor_sum_axis(&t, 0);
  if !colr.is_ok { return 1; }
  io.println(tensor_dump(&colr.value));
  // tensor rank=1 dims=[3] data=[5,7,9]

  let trr = tensor_transpose2(&sum);
  if !trr.is_ok { return 1; }
  io.println(tensor_dump(&trr.value));
  // tensor rank=2 dims=[3,2] data=[11,14,22,25,33,36]
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.tensor -TimeoutSec 60
```

Expected tail: 29 `[PASS]` lines, `xiom.tensor: all tests passed`, then
`port: PASS (passed=29 failed=0 program_exit=0 exit=0)`. Verified twice on
the pinned compiler 0.62.2 (installed) with the repo stdlib.

## Limitations

- **Integers only.** There is no `Float64` dtype (and no `Vec[Float64]` on
  this toolchain); callers scale to fixed point themselves.
- **Envelope.** Every stored value must lie in `[-INT_MAX, INT_MAX]`; add,
  multiply and reduce-sum are checked and return `Err` on overflow rather
  than wrapping. The capacity guard is 1000000 elements per tensor.
- **No views or aliasing by design.** All transforms copy; a stride-only
  view (`tensor_slice_axis0` returns a copy) trades memory for a simple,
  documented ownership story.
- **Rank 2 transpose only.** General axis permutation is out of scope for
  v0.1.0, as are matrix multiplication, broadcasting for `tensor_mul`,
  concatenation and serialization.
- **Slice axis 0 only.** Slicing deeper axes requires reshape/slice
  composition by the caller.
- **Reduction output rank.** Reducing a rank-1 tensor yields a rank-0
  scalar tensor; reduce twice to reach a plain `Int`.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
