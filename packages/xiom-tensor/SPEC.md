# xiom.tensor -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.tensor` (`src/tensor.xi`). Pure XIOM, no FFI.
Toolchain: pinned compiler v0.62.2 + stdlib-perf1 (`E:\xiom-lang\stdlib`).

## 1. Scope

An integer-only n-dimensional tensor core for in-memory computation:

- validated construction from a shape (`tensor_new`) and from a flat buffer
  (`tensor_from_flat`),
- shape and stride inspection (`tensor_rank`, `tensor_dim`, `tensor_numel`,
  `tensor_shape`, `tensor_stride`, `tensor_strides`),
- coordinate and flat indexing (`tensor_offset`, `tensor_get`,
  `tensor_get_flat`, `tensor_set`, `tensor_set_flat`),
- reshape and rank-2 transpose (`tensor_reshape`, `tensor_transpose2`),
- slicing along axis 0 with an offset map (`tensor_slice_axis0`,
  `tensor_slice_offsets_axis0`),
- broadcast add and elementwise add/multiply (`tensor_broadcast_add`,
  `tensor_add`, `tensor_mul`),
- axis reductions (`tensor_sum_axis`, `tensor_max_axis`),
- a canonical text dump (`tensor_dump`).

A tensor is a `Tensor` record (`pub type Tensor = { rank: Int; dims:
Vec[Int]; data: Vec[Int]; }`). There are no views, no aliasing and no
floating point.

## 2. Non-goals

- No floats, no `Float64`, no mixed dtypes (integer data only).
- No views, strides-only aliasing, broadcasting on write, or in-place
  arithmetic other than `tensor_set` / `tensor_set_flat`.
- No general axis permutation (transpose is rank 2 only).
- No matrix multiplication, concatenation, padding, gather/scatter or
  serialization.
- No FFI, file I/O, threads or registry integration.

## 3. Data model

1. **Record.** `rank: Int`, `dims: Vec[Int]`, `data: Vec[Int]`.
   Invariants: `dims.len() == rank`, `0 <= rank <= tensor_max_rank()` (6),
   every `dims[i] >= 0`, `data.len() == product(dims)`, every stored value
   in `[-INT_MAX, INT_MAX]` (`INT_MAX = 9223372036854775807`).
2. **Rank 0.** The empty dims vector is valid: `product([]) = 1`, so a rank-0
   tensor is a one-element scalar addressed by an empty index vector. Rank-1
   reductions therefore produce scalars.
3. **Row-major layout.** Element `(i0, .., i{r-1})` of a shape
   `[d0, .., d{r-1}]` lives at
   `offset = sum(k = 0 .. r-1) i_k * stride[k]` with
   `stride[r-1] = 1` and `stride[k] = d[k+1] * stride[k+1]` (the strides
   vector is empty for rank 0). Examples: `[2,3] -> [3,1]`,
   `[2,3,4] -> [12,4,1]`.
4. **Capacity.** `product(dims) <= tensor_max_elements()` (1000000). The
   shape product is computed with a per-step overflow guard
   (`numel > INT_MAX / d -> Err`), so oversized shapes never reach the data
   buffer.
5. **Arithmetic envelope.** Every value stored in `data` lies in
   `[-INT_MAX, INT_MAX]`. Constructors validate; `tensor_set` validates;
   add, multiply and reduce-sum check each step and return `Err` instead of
   wrapping.

## 4. Construction and validation order

`tensor_new(rank, dims)` validates, in order:

1. `rank < 0 || rank > 6` ->
   `tensor: rank must be between 0 and 6`;
2. `dims.len() != rank` -> `tensor: dims length must equal rank`;
3. any `dims[i] < 0` -> `tensor: dims must be non-negative` (checked in
   axis order, left to right);
4. per-axis product overflow -> `tensor: shape product overflows`;
5. `product > tensor_max_elements()` -> `tensor: shape exceeds the element
   limit`.

On success it returns a zero-filled tensor. `tensor_from_flat` runs the same
shape validation, then

6. `values.len() != product` ->
   `tensor: values length does not match shape`;
7. any value outside the envelope ->
   `tensor: value magnitude exceeds the limit` (checked left to right).

On success it copies `values` into a fresh buffer.

## 5. Indexing

1. **Coordinate -> offset** (`tensor_offset`): `indices.len()` must equal
   `rank` (`tensor: index rank does not match tensor rank`); each
   `indices[k]` must satisfy `0 <= indices[k] < dims[k]`
   (`tensor: index out of bounds`, checked in axis order); the result is the
   row-major offset formula of section 3.4. A rank-0 tensor takes an empty
   index vector and returns offset 0.
2. **Get** (`tensor_get`, `tensor_get_flat`): read at a validated coordinate
   or at `0 <= offset < data.len()`; an out-of-range flat offset is
   `tensor: offset out of bounds`.
3. **Set** (`tensor_set`, `tensor_set_flat`): validate exactly as get,
   additionally require the value to be inside the envelope
   (`tensor: value magnitude exceeds the limit`), then write in place and
   return `Ok(offset)`. An `Err` writes nothing. Callers must pass
   `&mut t` explicitly (v0.62.2 silently writes to a copy without it).

## 6. Reshape, transpose, slice

1. **Reshape** (`tensor_reshape`): validates the new shape (section 4 rules
   1-5) and requires `product(new dims) == tensor_numel(t)`
   (`tensor: reshape changes the element count`). The flat data is copied
   unchanged, so reshape preserves row-major element order; the source is
   not modified. `[2,3] -> [3,2]` keeps `[1,2,3,4,5,6]`; a rank-0 result
   needs a single-element source.
2. **Transpose** (`tensor_transpose2`): rank must be exactly 2
   (`tensor: transpose requires rank 2`); result dims are `(d1, d0)` and
   `out[j, i] == t[i, j]`. Transposing twice reproduces the input. A `[0,3]`
   matrix transposes to `[3,0]` with an empty buffer.
3. **Slice axis 0** (`tensor_slice_axis0`): rank must be `>= 1`
   (`tensor: slice requires rank >= 1`); `start >= 0`, `count >= 0` and
   `start + count <= dims[0]` (`tensor: slice range out of bounds`). The
   result has the same rank, `dims[0] == count`, the other dims unchanged,
   and a copied prefix of the rows: slice element `j` (row-major) is source
   element `start * row_len + j` where `row_len = product(dims[1..])`.
   `count == 0` yields an empty tensor with `dims[0] == 0`.
4. **Offset map** (`tensor_slice_offsets_axis0`): the same validation and
   the same formula, returned as the `Vec[Int]` of source offsets. By
   construction `tensor_data(tensor_slice_axis0(t, s, c))` equals the values
   of `t` at these offsets, in order.

## 7. Broadcasting and elementwise arithmetic

1. **Broadcast rules** (`tensor_broadcast_add`): ranks are right-aligned;
   for each axis the operand sizes `da`, `db` must satisfy `da == db`,
   `da == 1` or `db == 1`; the output size is `db` when `da == 1`, else
   `da`. The pair `(0, 1)` broadcasts to `0`. A rank-0 operand is a scalar
   and broadcasts to any shape. Any other pairing fails with
   `tensor: shapes are not broadcast-compatible`.
2. **Result guard.** The broadcast shape is re-validated (section 4 rules
   1-5): a result larger than `tensor_max_elements()` fails with
   `tensor: shape exceeds the element limit` and an overflowing product with
   `tensor: shape product overflows`, before any allocation.
3. **Index mapping.** For each output offset the multi-index is recovered
   from the output strides (`idx = (off / stride) % dim`), and each input's
   source offset accumulates `idx * input_stride` only for axes where the
   input dim is `> 1`; size-1 axes always read index 0 (the offset map).
4. **Checked add.** Each pair is added through the envelope check;
   overflow fails closed with `tensor: addition overflows`.
5. **Elementwise add/multiply** (`tensor_add`, `tensor_mul`): the shapes
   must be exactly equal (`tensor: shapes are not equal`; rank included),
   and every pair is checked (`tensor: addition overflows`,
   `tensor: multiplication overflows`). `0` factors short-circuit the
   multiply check, so `INT_MAX * 0 = 0` is valid.

## 8. Reductions

1. **Axis** must satisfy `0 <= axis < rank` (`tensor: axis out of range`).
2. **Output shape** is `dims` with `axis` removed (rank - 1). Reducing a
   rank-1 tensor yields a rank-0 scalar tensor.
3. **Sum** (`tensor_sum_axis`) visits each slice in axis order and adds each
   element through the envelope check (`tensor: addition overflows`). A
   zero-length axis yields the empty sum `0`.
4. **Max** (`tensor_max_axis`) visits each slice and keeps the largest
   value. A maximum has no empty identity: when an output cell would reduce
   a zero-length axis, the call fails with
   `tensor: max of an empty reduction` (this includes reducing the only
   axis of a `[0]` tensor).

## 9. Canonical dump

`tensor_dump(t)` returns one line, no trailing newline:

```
tensor rank=R dims=[d0,d1,...] data=[v0,v1,...]
```

No spaces inside the brackets; dims and data in axis / row-major order.
Examples: `tensor rank=2 dims=[2,3] data=[1,2,3,4,5,6]`,
`tensor rank=0 dims=[] data=[0]`,
`tensor rank=1 dims=[0] data=[]`. The dump is a pure function of the tensor
fields and uses only `xiom.convert.int_to_string` and `Str` concatenation.

## 10. Copy semantics (no views, no aliasing)

1. `tensor_from_flat` copies `values`; later mutation of the caller's vector
   or of a `tensor_data` copy never changes the tensor.
2. `tensor_shape`, `tensor_data` and `tensor_strides` return fresh vectors;
   mutating them never changes the tensor.
3. `tensor_reshape`, `tensor_transpose2`, `tensor_slice_axis0`, the
   arithmetic operations and the reductions all return new tensors with
   freshly allocated buffers. No returned tensor shares a buffer with any
   input.
4. `tensor_set` / `tensor_set_flat` are the only mutating operations; they
   take the tensor by `&mut` and mutate exactly one element.
5. Consequently there are no borrow interactions to reason about at the
   call site: every function but the setters takes `&Tensor` and reads only.

## 11. Error catalog (as implemented)

| Message | Raised by |
|---|---|
| `tensor: rank must be between 0 and 6` | shape validation (construct, reshape, broadcast result) |
| `tensor: dims length must equal rank` | shape validation |
| `tensor: dims must be non-negative` | shape validation |
| `tensor: shape product overflows` | shape validation (per-step product guard) |
| `tensor: shape exceeds the element limit` | shape validation (product > 1000000) |
| `tensor: value magnitude exceeds the limit` | `tensor_from_flat`, `tensor_set`, `tensor_set_flat` |
| `tensor: values length does not match shape` | `tensor_from_flat` |
| `tensor: index rank does not match tensor rank` | `tensor_offset`, `tensor_get`, `tensor_set` |
| `tensor: index out of bounds` | coordinate lookups |
| `tensor: offset out of bounds` | `tensor_get_flat`, `tensor_set_flat` |
| `tensor: reshape changes the element count` | `tensor_reshape` |
| `tensor: transpose requires rank 2` | `tensor_transpose2` |
| `tensor: slice requires rank >= 1` | `tensor_slice_axis0`, `tensor_slice_offsets_axis0` |
| `tensor: slice range out of bounds` | both slice functions |
| `tensor: shapes are not equal` | `tensor_add`, `tensor_mul` |
| `tensor: shapes are not broadcast-compatible` | `tensor_broadcast_add` |
| `tensor: addition overflows` | broadcast add, add, reduce-sum |
| `tensor: multiplication overflows` | `tensor_mul` |
| `tensor: axis out of range` | `tensor_sum_axis`, `tensor_max_axis` |
| `tensor: max of an empty reduction` | `tensor_max_axis` |

Validation order is documented in sections 4-8; an `Err` never leaves a
partial write (`tensor_set*`) or a partially built tensor visible.

## 12. API signatures

```xi
pub fn tensor_max_rank() -> Int
pub fn tensor_max_elements() -> Int
pub fn tensor_new(rank: Int, dims: &Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_from_flat(rank: Int, dims: &Vec[Int], values: &Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_rank(t: &Tensor) -> Int
pub fn tensor_dim(t: &Tensor, axis: Int) -> Int
pub fn tensor_numel(t: &Tensor) -> Int
pub fn tensor_shape(t: &Tensor) -> Vec[Int]
pub fn tensor_data(t: &Tensor) -> Vec[Int]
pub fn tensor_stride(t: &Tensor, axis: Int) -> Int
pub fn tensor_strides(t: &Tensor) -> Vec[Int]
pub fn tensor_offset(t: &Tensor, indices: &Vec[Int]) -> Result[Int, Str]
pub fn tensor_get(t: &Tensor, indices: &Vec[Int]) -> Result[Int, Str]
pub fn tensor_get_flat(t: &Tensor, offset: Int) -> Result[Int, Str]
pub fn tensor_set(t: &mut Tensor, indices: &Vec[Int], value: Int) -> Result[Int, Str]
pub fn tensor_set_flat(t: &mut Tensor, offset: Int, value: Int) -> Result[Int, Str]
pub fn tensor_reshape(t: &Tensor, rank: Int, dims: &Vec[Int]) -> Result[Tensor, Str]
pub fn tensor_transpose2(t: &Tensor) -> Result[Tensor, Str]
pub fn tensor_slice_axis0(t: &Tensor, start: Int, count: Int) -> Result[Tensor, Str]
pub fn tensor_slice_offsets_axis0(t: &Tensor, start: Int, count: Int) -> Result[Vec[Int], Str]
pub fn tensor_broadcast_add(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_add(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_mul(a: &Tensor, b: &Tensor) -> Result[Tensor, Str]
pub fn tensor_sum_axis(t: &Tensor, axis: Int) -> Result[Tensor, Str]
pub fn tensor_max_axis(t: &Tensor, axis: Int) -> Result[Tensor, Str]
pub fn tensor_dump(t: &Tensor) -> Str
```

Complexity: construction `O(numel)`; indexing `O(rank)` (flat `O(1)`);
reshape / transpose / slice / elementwise ops `O(numel)`;
`tensor_broadcast_add` `O(numel(result) * rank)`; reductions `O(numel)`;
`tensor_dump` `O(rank + numel)` plus string assembly.

## 13. Test plan

`tests/test_conformance.xi` (module `tensor_tests`) runs 29 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | rank-2 construction | dims, numel, strides `[3,1]`, `-1` sentinel (sections 3-4) |
| t2 | rank-1 | one dim, stride `[1]` |
| t3 | rank-3 | strides `[12,4,1]` |
| t4 | rank-0 scalar | empty dims, numel 1, empty-index get, dump |
| t5 | construction errors | rank range, dims length, negative dim, overflow, limit |
| t6 | from_flat | row-major placement, exact dump |
| t7 | copy semantics | source and `tensor_data` copies are independent |
| t8 | from_flat errors | length mismatch and envelope violation |
| t9 | offset | coordinate formula plus all error shapes |
| t10 | get_flat | inclusive bounds and errors |
| t11 | set paths | coordinate/flat writes, returned offset, fail-closed errors |
| t12 | set envelope | out-of-envelope writes rejected unwritten |
| t13 | reshape | same count, flat order, rank-0 result |
| t14 | reshape errors | count change, bad rank, dims length |
| t15 | reshape copy | result is independent of the source |
| t16 | transpose | dims swap, `out[col,row] = t[row,col]`, dump |
| t17 | transpose edges | involution, rank guard, empty matrix |
| t18 | slice axis 0 | window copy, `count 0`, empty tail |
| t19 | slice errors | rank 0, negative range, past `dims[0]` |
| t20 | slice rank 1 + offsets | offset map indexes the source exactly |
| t21 | elementwise add | equal shapes only |
| t22 | elementwise multiply | equal shapes, zero propagation |
| t23 | checked arithmetic | add/multiply overflow fail closed |
| t24 | broadcast add | row, column, outer grid, scalar |
| t25 | broadcast errors | incompatible axis, oversized result |
| t26 | broadcast overflow | checked overflow inside the expanded loop |
| t27 | sum axis | axis dropped, empty sum 0, axis errors |
| t28 | max axis | values, empty-reduction error, axis errors |
| t29 | dump + copies | canonical text; shape/data/strides copies independent |

Every `Str` comparison in the suite goes through `xiom.string.compare`'s
`str_compare` (BUG 17: `==` on `Str` values from `Vec[Str]` elements lowers
to a pointer comparison); the library itself never compares strings.

## 14. Compiler / stdlib notes

- **v0.62.2 traps handled.** Every `Vec[Int]` element read binds an
  explicitly typed local; every `&mut` call site passes `&mut` explicitly;
  no `&mut Int` parameters exist (setters mutate a struct, whose
  write-through was probed green); no `Vec[Str]` and no `Vec[Str].push`
  anywhere; no `Vec[StructType]`, lambdas, `self`, fn-tables or
  builtin-named functions; multiply-before-divide steps are guarded and the
  only divisions are on non-negative indices (q/r not needed, but product
  guards use division).
- **`&struct.field` workaround.** No borrow of a struct field is passed to a
  reference parameter; helpers (`tensor_strides`, reductions, broadcast)
  receive local copies of the dims vector.
- **Mixed brackets.** The writer tooling can silently produce `Vec<` /
  `Result<`; both files are grepped clean after the final edit.
- **No new compiler findings.** No stdlib functions were needed beyond
  `xiom.convert.int_to_string` for the dump.

## 15. Known limitations

- Integer-only; callers must scale floats to fixed point.
- The arithmetic envelope is `[-INT_MAX, INT_MAX]`; `INT_MIN` is not a valid
  stored value.
- 1000000-element capacity guard per tensor.
- Copy semantics trade memory for the absence of views/aliasing.
- Transpose is rank 2; slicing is axis 0; `tensor_mul` does not broadcast.
