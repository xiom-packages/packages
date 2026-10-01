// XIOM -- xiom.tensor: deterministic n-dimensional integer tensor core
// Port task: promote the xiom.tensor placeholder to a real, tested, pure-XIOM
// package: an n-dimensional integer tensor over a flat Vec[Int] plus a shape
// (no floats, no FFI, no Vec[Float64], no threads).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   - A tensor is `{ rank, dims, data }`: `dims` has exactly `rank` entries,
//     each `>= 0`, and `data` is the row-major flat buffer of exactly
//     numel = product(dims) elements (the empty product is 1, so rank 0 is a
//     one-element scalar).
//   - rank is 0 .. 6; numel is at most tensor_max_elements() (1000000); a
//     shape whose product would overflow Int fails closed with Err.
//   - Row-major strides: stride[rank-1] = 1 and
//     stride[k] = dims[k+1] * stride[k+1]. The flat offset of an index
//     vector (i0, .., i{r-1}) is sum(k) i_k * stride[k].
//   - Every data value is kept inside the symmetric envelope
//     [-INT_MAX, INT_MAX]: constructors validate values, and add / multiply /
//     reduce-sum check every arithmetic step (no silent wraparound).
//   - Copy semantics everywhere: construction copies the input values,
//     tensor_data / tensor_shape return copies, reshape / slice / transpose /
//     elementwise ops return new tensors, and tensor_set mutates only through
//     an explicit `&mut Tensor`. There are no views and no aliasing.
//
// Layout notes that shaped this module (compiler v0.62.2):
//   * every Vec[Int] element read binds a typed local before use.
//   * no `&struct.field` is passed to a reference parameter: helpers receive
//     local copies (tensor_strides, reductions and the broadcast add all copy
//     the dims first).
//   * free functions only: no methods, no generics, no callbacks, no indexed
//     function-table dispatch.
//   * Ok/Err construction is confined to the leaf helpers at the bottom.
//   * no Vec[Str] is used anywhere (v0.62.2 mis-lowers Vec[Str].push), and no
//     Str value is compared in the library; the dump builds strings with
//     concatenation only.
//   * no `&mut Int` parameter: scalar state (there is none here) would be
//     threaded through returns; the only mutable parameter is `&mut Tensor`
//     with explicit `&mut` at every call site.
//   * multiply-before-divide steps are guarded; the division helper uses the
//     q/r form and is only applied to non-negative operands (indices).
//
// Out of scope for v0.1.0: rank-2 matrix multiplication, general axis
// permutation, strided views, float dtypes and serialization.

module xiom.tensor

use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Largest supported rank (number of dimensions).
const _TENSOR_MAX_RANK: Int = 6;
// Largest supported element count for any tensor (a documented capacity
// guard, well under the runtime Vec cap of 2^24 elements).
const _TENSOR_MAX_ELEMS: Int = 1000000;
// Symmetric arithmetic envelope; every stored value is validated against it.
const _TENSOR_INT_MAX: Int = 9223372036854775807;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// An n-dimensional integer tensor: a row-major flat `data` buffer of
/// `numel(dims)` elements plus the shape that indexes it.
///
/// Invariants (established by the constructors and preserved by every
/// operation): `dims.len() == rank`, `0 <= rank <= 6`, every dim `>= 0`,
/// `data.len() == product(dims)`, and every stored value lies in
/// `[-INT_MAX, INT_MAX]`. Fields are internal implementation detail; use the
/// tensor_* accessors.
pub type Tensor = {
  rank: Int;
  dims: Vec[Int];
  data: Vec[Int];
}

// ---------------------------------------------------------------------------
// Limits
// ---------------------------------------------------------------------------

/// Largest supported rank (6). Complexity: O(1).
pub fn tensor_max_rank() -> Int {
  return _TENSOR_MAX_RANK;
}

/// Largest supported element count (1000000). Complexity: O(1).
pub fn tensor_max_elements() -> Int {
  return _TENSOR_MAX_ELEMS;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Construct a zero-filled tensor of a validated shape.
///
/// Params: rank - number of dimensions (0 .. 6; rank 0 is a one-element
///         scalar with an empty dims list);
///         dims - exactly `rank` non-negative dimension sizes, read only.
/// Returns: Ok(Tensor) whose data buffer is `product(dims)` zeros.
/// Error case: Err("tensor: ...") for a rank outside 0 .. 6, a dims length
/// that does not equal rank, a negative dimension, a shape product that
/// overflows Int, or a product past tensor_max_elements().
/// Complexity: O(numel).
pub fn tensor_new(rank: Int, dims: &Vec[Int]) -> Result[Tensor, Str] {
  let chk = _tensor_validate_shape(rank, dims);
  var numel: Int = 0;
  match chk {
    Ok(v) => { numel = v; },
    Err(e) => { return _err_tensor(e); },
  }
  var data = Vec[Int].new();
  var i = 0;
  while i < numel {
    data.push(0);
    i = i + 1;
  }
  let shape = _tensor_copy_ints(dims);
  return _ok_tensor(Tensor{ rank: rank; dims: shape; data: data; });
}

/// Construct a tensor from an existing flat buffer (copied).
///
/// Params: rank - number of dimensions (0 .. 6);
///         dims - exactly `rank` non-negative dimension sizes, read only;
///         values - exactly `product(dims)` row-major values in
///         [-INT_MAX, INT_MAX], read only.
/// Returns: Ok(Tensor) holding a copy of `values`; later changes to the
/// caller's vector are not visible through the tensor.
/// Error case: Err("tensor: ...") for any shape error (as tensor_new), a
/// values length that does not match the shape, or a value outside the
/// symmetric envelope.
/// Complexity: O(numel).
pub fn tensor_from_flat(rank: Int, dims: &Vec[Int], values: &Vec[Int]) -> Result[Tensor, Str] {
  let chk = _tensor_validate_shape(rank, dims);
  var numel: Int = 0;
  match chk {
    Ok(v) => { numel = v; },
    Err(e) => { return _err_tensor(e); },
  }
  if values.len() != numel {
    return _err_tensor("tensor: values length does not match shape");
  }
  var data = Vec[Int].new();
  var i = 0;
  while i < values.len() {
    let v: Int = values[i];
    if !_tensor_value_ok(v) {
      return _err_tensor("tensor: value magnitude exceeds the limit");
    }
    data.push(v);
    i = i + 1;
  }
  let shape = _tensor_copy_ints(dims);
  return _ok_tensor(Tensor{ rank: rank; dims: shape; data: data; });
}

// ---------------------------------------------------------------------------
// Shape accessors
// ---------------------------------------------------------------------------

/// Number of dimensions (0 .. 6). Complexity: O(1).
pub fn tensor_rank(t: &Tensor) -> Int {
  return t.rank;
}

/// Size of one axis, or -1 when `axis` is negative or >= tensor_rank(t).
/// Complexity: O(1).
pub fn tensor_dim(t: &Tensor, axis: Int) -> Int {
  if axis < 0 || axis >= t.rank {
    return -1;
  }
  let d: Int = t.dims[axis];
  return d;
}

/// Number of elements, `product(dims)` (the empty product is 1).
/// Complexity: O(rank).
pub fn tensor_numel(t: &Tensor) -> Int {
  var numel: Int = 1;
  var i = 0;
  while i < t.rank {
    let d: Int = t.dims[i];
    numel = numel * d;
    i = i + 1;
  }
  return numel;
}

/// Copy of the shape as a fresh `Vec[Int]` of length tensor_rank(t).
/// Complexity: O(rank).
pub fn tensor_shape(t: &Tensor) -> Vec[Int] {
  return _tensor_copy_dims(t);
}

/// Copy of the flat data buffer (row-major, length tensor_numel(t)).
/// Complexity: O(numel).
pub fn tensor_data(t: &Tensor) -> Vec[Int] {
  return _tensor_copy_data(t);
}

/// Row-major stride of one axis, or -1 when `axis` is out of range.
///
/// Stride formula: stride[rank-1] = 1 and
/// stride[k] = dims[k+1] * stride[k+1].
/// Complexity: O(rank).
pub fn tensor_stride(t: &Tensor, axis: Int) -> Int {
  if axis < 0 || axis >= t.rank {
    return -1;
  }
  return _tensor_stride_at(t, axis);
}

/// Copy of every row-major stride, in axis order (length tensor_rank(t)).
/// Complexity: O(rank).
pub fn tensor_strides(t: &Tensor) -> Vec[Int] {
  let dims = _tensor_copy_dims(t);
  return _tensor_strides_of(&dims);
}

// ---------------------------------------------------------------------------
// Flat and coordinate indexing
// ---------------------------------------------------------------------------

/// Flat offset of a coordinate, with rank and bounds checks.
///
/// Params: t - the tensor; indices - exactly tensor_rank(t) zero-based
///         coordinates, each within its axis.
/// Returns: Ok(offset) = sum(k) indices[k] * stride[k], always in
/// [0, tensor_numel(t)).
/// Error case: Err("tensor: index rank does not match tensor rank") when
/// indices.len() != tensor_rank(t);
/// Err("tensor: index out of bounds") when any coordinate is negative or
/// >= its axis size. A rank-0 tensor is addressed by an empty index vector.
/// Complexity: O(rank).
pub fn tensor_offset(t: &Tensor, indices: &Vec[Int]) -> Result[Int, Str] {
  return _tensor_offset_checked(t, indices);
}

/// Value at a coordinate.
///
/// Returns: Ok(data[offset]) for a valid coordinate (see tensor_offset).
/// Error case: the tensor_offset errors.
/// Complexity: O(rank).
pub fn tensor_get(t: &Tensor, indices: &Vec[Int]) -> Result[Int, Str] {
  let ochk = _tensor_offset_checked(t, indices);
  var off: Int = 0;
  match ochk {
    Ok(v) => { off = v; },
    Err(e) => { return _err_int(e); },
  }
  let x: Int = t.data[off];
  return _ok_int(x);
}

/// Value at a flat offset.
///
/// Returns: Ok(data[offset]) when 0 <= offset < data.len().
/// Error case: Err("tensor: offset out of bounds") otherwise.
/// Complexity: O(1).
pub fn tensor_get_flat(t: &Tensor, offset: Int) -> Result[Int, Str] {
  if offset < 0 || offset >= t.data.len() {
    return _err_int("tensor: offset out of bounds");
  }
  let x: Int = t.data[offset];
  return _ok_int(x);
}

/// Write a value at a coordinate, mutating the tensor in place.
///
/// Params: t - the tensor, taken by `&mut` (pass `&mut local` at the call
///         site); indices - the coordinate (as tensor_offset); value - the
///         new value, which must lie in [-INT_MAX, INT_MAX].
/// Returns: Ok(offset), the flat offset that was written.
/// Error case: the tensor_offset errors, or
/// Err("tensor: value magnitude exceeds the limit") for a value outside the
/// envelope. An Err writes nothing.
/// Complexity: O(rank).
pub fn tensor_set(t: &mut Tensor, indices: &Vec[Int], value: Int) -> Result[Int, Str] {
  let ochk = _tensor_offset_checked(t, indices);
  var off: Int = 0;
  match ochk {
    Ok(v) => { off = v; },
    Err(e) => { return _err_int(e); },
  }
  if !_tensor_value_ok(value) {
    return _err_int("tensor: value magnitude exceeds the limit");
  }
  t.data[off] = value;
  return _ok_int(off);
}

/// Write a value at a flat offset, mutating the tensor in place.
///
/// Returns: Ok(offset) when 0 <= offset < data.len().
/// Error case: Err("tensor: offset out of bounds") for an out-of-range
/// offset, or Err("tensor: value magnitude exceeds the limit") for a value
/// outside the envelope. An Err writes nothing.
/// Complexity: O(1).
pub fn tensor_set_flat(t: &mut Tensor, offset: Int, value: Int) -> Result[Int, Str] {
  if offset < 0 || offset >= t.data.len() {
    return _err_int("tensor: offset out of bounds");
  }
  if !_tensor_value_ok(value) {
    return _err_int("tensor: value magnitude exceeds the limit");
  }
  t.data[offset] = value;
  return _ok_int(offset);
}

// ---------------------------------------------------------------------------
// Reshape
// ---------------------------------------------------------------------------

/// Reshape to a new validated shape with the same element count (copy).
///
/// Params: t - the source tensor; rank - the new rank (0 .. 6);
///         dims - exactly `rank` non-negative sizes with
///         product(dims) == tensor_numel(t).
/// Returns: Ok(new tensor) holding a copy of the flat data in the same
/// row-major order. The source tensor is unchanged.
/// Error case: any shape error (as tensor_new) or
/// Err("tensor: reshape changes the element count").
/// Complexity: O(numel + rank).
pub fn tensor_reshape(t: &Tensor, rank: Int, dims: &Vec[Int]) -> Result[Tensor, Str] {
  let chk = _tensor_validate_shape(rank, dims);
  var numel: Int = 0;
  match chk {
    Ok(v) => { numel = v; },
    Err(e) => { return _err_tensor(e); },
  }
  if numel != t.data.len() {
    return _err_tensor("tensor: reshape changes the element count");
  }
  let data = _tensor_copy_data(t);
  let shape = _tensor_copy_ints(dims);
  return _ok_tensor(Tensor{ rank: rank; dims: shape; data: data; });
}

// ---------------------------------------------------------------------------
// Transpose (rank 2)
// ---------------------------------------------------------------------------

/// Transpose a rank-2 tensor (copy).
///
/// Params: t - a rank-2 tensor with dims (rows, cols).
/// Returns: Ok(tensor) with dims (cols, rows) where
/// out[col, row] == t[row, col]; every other rank is rejected.
/// Error case: Err("tensor: transpose requires rank 2").
/// Complexity: O(numel).
pub fn tensor_transpose2(t: &Tensor) -> Result[Tensor, Str] {
  if t.rank != 2 {
    return _err_tensor("tensor: transpose requires rank 2");
  }
  let rows: Int = t.dims[0];
  let cols: Int = t.dims[1];
  var dims = Vec[Int].new();
  dims.push(cols);
  dims.push(rows);
  var data = Vec[Int].new();
  var c = 0;
  while c < cols {
    var r = 0;
    while r < rows {
      let v: Int = t.data[r * cols + c];
      data.push(v);
      r = r + 1;
    }
    c = c + 1;
  }
  return _ok_tensor(Tensor{ rank: 2; dims: dims; data: data; });
}

// ---------------------------------------------------------------------------
// Slice along axis 0
// ---------------------------------------------------------------------------

/// Copy of rows `start .. start + count` along axis 0.
///
/// Params: t - a tensor with rank >= 1; start - first axis-0 index
///         (0 <= start <= dims[0]); count - number of rows to keep
///         (0 <= count <= dims[0] - start).
/// Returns: Ok(new tensor) with the same rank, dims[0] == count and the
/// remaining dims unchanged, holding a row-major copy of the selected rows.
/// A count of 0 yields an empty tensor with dims[0] == 0.
/// Error case: Err("tensor: slice requires rank >= 1") for a rank-0 tensor;
/// Err("tensor: slice range out of bounds") for a negative start/count or a
/// range past dims[0].
/// Complexity: O(count * product(dims[1..]))).
pub fn tensor_slice_axis0(t: &Tensor, start: Int, count: Int) -> Result[Tensor, Str] {
  let chk = _tensor_slice_check(t, start, count);
  var row_len: Int = 0;
  match chk {
    Ok(v) => { row_len = v; },
    Err(e) => { return _err_tensor(e); },
  }
  var dims = Vec[Int].new();
  dims.push(count);
  var k = 1;
  while k < t.rank {
    let d: Int = t.dims[k];
    dims.push(d);
    k = k + 1;
  }
  var data = Vec[Int].new();
  let base = start * row_len;
  let total = count * row_len;
  var i = 0;
  while i < total {
    let v: Int = t.data[base + i];
    data.push(v);
    i = i + 1;
  }
  return _ok_tensor(Tensor{ rank: t.rank; dims: dims; data: data; });
}

/// Source offsets of a slice along axis 0, in slice row-major order.
///
/// Params: t, start, count - exactly as tensor_slice_axis0.
/// Returns: Ok(offsets) of length count * product(dims[1..]), where entry j
/// is the flat offset in `t` of the j-th element of the slice. This is the
/// offset map of the copy: tensor_data(tensor_slice_axis0(t, s, c)) equals
/// the values of t at these offsets, in order.
/// Error case: the tensor_slice_axis0 errors.
/// Complexity: O(count * product(dims[1..]))).
pub fn tensor_slice_offsets_axis0(t: &Tensor, start: Int, count: Int) -> Result[Vec[Int], Str] {
  let chk = _tensor_slice_check(t, start, count);
  var row_len: Int = 0;
  match chk {
    Ok(v) => { row_len = v; },
    Err(e) => { return _err_ints(e); },
  }
  var offsets = Vec[Int].new();
  let base = start * row_len;
  let total = count * row_len;
  var i = 0;
  while i < total {
    offsets.push(base + i);
    i = i + 1;
  }
  return _ok_ints(offsets);
}

// ---------------------------------------------------------------------------
// Broadcasting and elementwise arithmetic
// ---------------------------------------------------------------------------

/// Broadcast-compatible elementwise add: `a + b` with NumPy-style
/// right-aligned broadcasting.
///
/// Broadcasting rules: ranks are right-aligned; for each axis the sizes must
/// be equal or one of them must be 1, and the output size is the non-1 size
/// (0 broadcasts with 1 to 0). A rank-0 operand is a scalar that broadcasts
/// to any shape.
/// Returns: Ok(tensor) of the broadcast shape, where every output element is
/// the checked sum of the corresponding (broadcast) input elements.
/// Error case: Err("tensor: shapes are not broadcast-compatible");
/// Err("tensor: shape exceeds the element limit") or
/// Err("tensor: shape product overflows") when the broadcast result is too
/// large; Err("tensor: addition overflows") on a checked overflow.
/// Complexity: O(numel(result) * max(rank)).
pub fn tensor_broadcast_add(a: &Tensor, b: &Tensor) -> Result[Tensor, Str] {
  let dchk = _tensor_broadcast_dims(a, b);
  var dims = Vec[Int].new();
  match dchk {
    Ok(v) => { dims = v; },
    Err(e) => { return _err_tensor(e); },
  }
  let nchk = _tensor_validate_shape(dims.len(), &dims);
  var numel: Int = 0;
  match nchk {
    Ok(v) => { numel = v; },
    Err(e) => { return _err_tensor(e); },
  }
  let a_dims = _tensor_copy_dims(a);
  let b_dims = _tensor_copy_dims(b);
  let out_strides = _tensor_strides_of(&dims);
  let a_strides = _tensor_strides_of(&a_dims);
  let b_strides = _tensor_strides_of(&b_dims);
  var data = Vec[Int].new();
  var off = 0;
  while off < numel {
    var aoff: Int = 0;
    var boff: Int = 0;
    var k = 0;
    while k < dims.len() {
      let os: Int = out_strides[k];
      var idx: Int = 0;
      if os > 0 {
        let d: Int = dims[k];
        idx = (off / os) % d;
      }
      let ai = a.rank - dims.len() + k;
      if ai >= 0 {
        let ad: Int = a_dims[ai];
        if ad > 1 {
          let ast: Int = a_strides[ai];
          aoff = aoff + idx * ast;
        }
      }
      let bi = b.rank - dims.len() + k;
      if bi >= 0 {
        let bd: Int = b_dims[bi];
        if bd > 1 {
          let bst: Int = b_strides[bi];
          boff = boff + idx * bst;
        }
      }
      k = k + 1;
    }
    let av: Int = a.data[aoff];
    let bv: Int = b.data[boff];
    if !_tensor_add_ok(av, bv) {
      return _err_tensor("tensor: addition overflows");
    }
    data.push(av + bv);
    off = off + 1;
  }
  return _ok_tensor(Tensor{ rank: dims.len(); dims: dims; data: data; });
}

/// Elementwise add: shapes must be exactly equal (no broadcasting).
///
/// Returns: Ok(tensor) with the same shape and data[i] = a.data[i] +
/// b.data[i], every step checked.
/// Error case: Err("tensor: shapes are not equal");
/// Err("tensor: addition overflows").
/// Complexity: O(numel).
pub fn tensor_add(a: &Tensor, b: &Tensor) -> Result[Tensor, Str] {
  if !_tensor_same_shape(a, b) {
    return _err_tensor("tensor: shapes are not equal");
  }
  var data = Vec[Int].new();
  var i = 0;
  while i < a.data.len() {
    let av: Int = a.data[i];
    let bv: Int = b.data[i];
    if !_tensor_add_ok(av, bv) {
      return _err_tensor("tensor: addition overflows");
    }
    data.push(av + bv);
    i = i + 1;
  }
  let shape = _tensor_copy_dims(a);
  return _ok_tensor(Tensor{ rank: a.rank; dims: shape; data: data; });
}

/// Elementwise multiply: shapes must be exactly equal (no broadcasting).
///
/// Returns: Ok(tensor) with the same shape and data[i] = a.data[i] *
/// b.data[i], every step checked.
/// Error case: Err("tensor: shapes are not equal");
/// Err("tensor: multiplication overflows").
/// Complexity: O(numel).
pub fn tensor_mul(a: &Tensor, b: &Tensor) -> Result[Tensor, Str] {
  if !_tensor_same_shape(a, b) {
    return _err_tensor("tensor: shapes are not equal");
  }
  var data = Vec[Int].new();
  var i = 0;
  while i < a.data.len() {
    let av: Int = a.data[i];
    let bv: Int = b.data[i];
    if !_tensor_mul_ok(av, bv) {
      return _err_tensor("tensor: multiplication overflows");
    }
    data.push(av * bv);
    i = i + 1;
  }
  let shape = _tensor_copy_dims(a);
  return _ok_tensor(Tensor{ rank: a.rank; dims: shape; data: data; });
}

// ---------------------------------------------------------------------------
// Reductions
// ---------------------------------------------------------------------------

/// Sum over one axis: the axis disappears from the shape.
///
/// Params: t - the tensor; axis - 0 <= axis < tensor_rank(t).
/// Returns: Ok(tensor) with rank tensor_rank(t) - 1, dims without `axis`,
/// and each output element the checked sum of the corresponding axis slice.
/// Reducing a zero-length axis yields 0 (the empty sum), so a rank-0 result
/// is possible when the input rank is 1.
/// Error case: Err("tensor: axis out of range");
/// Err("tensor: addition overflows").
/// Complexity: O(numel(t)).
pub fn tensor_sum_axis(t: &Tensor, axis: Int) -> Result[Tensor, Str] {
  if axis < 0 || axis >= t.rank {
    return _err_tensor("tensor: axis out of range");
  }
  let dims = _tensor_dims_without(t, axis);
  let out_strides = _tensor_strides_of(&dims);
  let src_dims = _tensor_copy_dims(t);
  let src_strides = _tensor_strides_of(&src_dims);
  var numel: Int = 1;
  var i = 0;
  while i < dims.len() {
    let d: Int = dims[i];
    numel = numel * d;
    i = i + 1;
  }
  let reduce_len: Int = src_dims[axis];
  let reduce_stride: Int = _tensor_stride_at(t, axis);
  var data = Vec[Int].new();
  var off = 0;
  while off < numel {
    let base = _tensor_reduce_base(&dims, &out_strides, &src_strides, axis, off);
    var acc: Int = 0;
    var v = 0;
    while v < reduce_len {
      let x: Int = t.data[base + v * reduce_stride];
      if !_tensor_add_ok(acc, x) {
        return _err_tensor("tensor: addition overflows");
      }
      acc = acc + x;
      v = v + 1;
    }
    data.push(acc);
    off = off + 1;
  }
  return _ok_tensor(Tensor{ rank: dims.len(); dims: dims; data: data; });
}

/// Maximum over one axis: the axis disappears from the shape.
///
/// Params: t - the tensor; axis - 0 <= axis < tensor_rank(t).
/// Returns: Ok(tensor) with rank tensor_rank(t) - 1, dims without `axis`,
/// and each output element the maximum of the corresponding axis slice.
/// Error case: Err("tensor: axis out of range");
/// Err("tensor: max of an empty reduction") when an output element would
/// reduce a zero-length axis (a maximum has no empty identity).
/// Complexity: O(numel(t)).
pub fn tensor_max_axis(t: &Tensor, axis: Int) -> Result[Tensor, Str] {
  if axis < 0 || axis >= t.rank {
    return _err_tensor("tensor: axis out of range");
  }
  let dims = _tensor_dims_without(t, axis);
  let out_strides = _tensor_strides_of(&dims);
  let src_dims = _tensor_copy_dims(t);
  let src_strides = _tensor_strides_of(&src_dims);
  var numel: Int = 1;
  var i = 0;
  while i < dims.len() {
    let d: Int = dims[i];
    numel = numel * d;
    i = i + 1;
  }
  let reduce_len: Int = src_dims[axis];
  if reduce_len == 0 && numel > 0 {
    return _err_tensor("tensor: max of an empty reduction");
  }
  let reduce_stride: Int = _tensor_stride_at(t, axis);
  var data = Vec[Int].new();
  var off = 0;
  while off < numel {
    let base = _tensor_reduce_base(&dims, &out_strides, &src_strides, axis, off);
    var acc: Int = t.data[base];
    var v = 1;
    while v < reduce_len {
      let x: Int = t.data[base + v * reduce_stride];
      if x > acc {
        acc = x;
      }
      v = v + 1;
    }
    data.push(acc);
    off = off + 1;
  }
  return _ok_tensor(Tensor{ rank: dims.len(); dims: dims; data: data; });
}

// ---------------------------------------------------------------------------
// Canonical dump
// ---------------------------------------------------------------------------

/// Canonical single-line text rendering of a tensor.
///
/// Format: `tensor rank=R dims=[d0,d1,...] data=[v0,v1,...]` with no
/// spaces inside the brackets, no trailing newline, and the data in
/// row-major order. A scalar renders as `dims=[]`, an empty tensor as
/// `data=[]`.
/// Returns: the text above; a pure function of the tensor fields.
/// Complexity: O(rank + numel) plus string assembly.
pub fn tensor_dump(t: &Tensor) -> Str {
  var out = "tensor rank=" + convert.int_to_string(t.rank) + " dims=[";
  var i = 0;
  while i < t.dims.len() {
    if i > 0 {
      out = out + ",";
    }
    let d: Int = t.dims[i];
    out = out + convert.int_to_string(d);
    i = i + 1;
  }
  out = out + "] data=[";
  var j = 0;
  while j < t.data.len() {
    if j > 0 {
      out = out + ",";
    }
    let v: Int = t.data[j];
    out = out + convert.int_to_string(v);
    j = j + 1;
  }
  out = out + "]";
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers: shape validation and geometry
// ---------------------------------------------------------------------------

// Validate a shape and return its element count. Order: rank range, dims
// length, non-negative dims, per-step product overflow, element limit.
fn _tensor_validate_shape(rank: Int, dims: &Vec[Int]) -> Result[Int, Str] {
  if rank < 0 || rank > _TENSOR_MAX_RANK {
    return _err_int("tensor: rank must be between 0 and 6");
  }
  if dims.len() != rank {
    return _err_int("tensor: dims length must equal rank");
  }
  var numel: Int = 1;
  var i = 0;
  while i < rank {
    let d: Int = dims[i];
    if d < 0 {
      return _err_int("tensor: dims must be non-negative");
    }
    if d > 0 {
      if numel > _TENSOR_INT_MAX / d {
        return _err_int("tensor: shape product overflows");
      }
      numel = numel * d;
    } else {
      numel = 0;
    }
    i = i + 1;
  }
  if numel > _TENSOR_MAX_ELEMS {
    return _err_int("tensor: shape exceeds the element limit");
  }
  return _ok_int(numel);
}

// Row-major strides of a validated dims vector (empty for rank 0).
fn _tensor_strides_of(dims: &Vec[Int]) -> Vec[Int] {
  var rev = Vec[Int].new();
  var s: Int = 1;
  var i = dims.len() - 1;
  while i >= 0 {
    rev.push(s);
    let d: Int = dims[i];
    s = s * d;
    i = i - 1;
  }
  var out = Vec[Int].new();
  var j = rev.len() - 1;
  while j >= 0 {
    let v: Int = rev[j];
    out.push(v);
    j = j - 1;
  }
  return out;
}

// Product of dims[axis+1..] without overflow (validated shapes).
fn _tensor_stride_at(t: &Tensor, axis: Int) -> Int {
  var s: Int = 1;
  var k = axis + 1;
  while k < t.rank {
    let d: Int = t.dims[k];
    s = s * d;
    k = k + 1;
  }
  return s;
}

// Checked coordinate -> offset. Order: rank length, then per-axis bounds.
fn _tensor_offset_checked(t: &Tensor, indices: &Vec[Int]) -> Result[Int, Str] {
  if indices.len() != t.rank {
    return _err_int("tensor: index rank does not match tensor rank");
  }
  let src_dims = _tensor_copy_dims(t);
  let src_strides = _tensor_strides_of(&src_dims);
  var off: Int = 0;
  var i = 0;
  while i < t.rank {
    let idx: Int = indices[i];
    let d: Int = src_dims[i];
    if idx < 0 || idx >= d {
      return _err_int("tensor: index out of bounds");
    }
    let st: Int = src_strides[i];
    off = off + idx * st;
    i = i + 1;
  }
  return _ok_int(off);
}

// Right-aligned broadcast of two validated shapes into a new dims vector.
fn _tensor_broadcast_dims(a: &Tensor, b: &Tensor) -> Result[Vec[Int], Str] {
  let a_dims = _tensor_copy_dims(a);
  let b_dims = _tensor_copy_dims(b);
  var rank = a.rank;
  if b.rank > rank {
    rank = b.rank;
  }
  var dims = Vec[Int].new();
  var k = 0;
  while k < rank {
    let ai = a.rank - rank + k;
    var da: Int = 1;
    if ai >= 0 {
      let da0: Int = a_dims[ai];
      da = da0;
    }
    let bi = b.rank - rank + k;
    var db: Int = 1;
    if bi >= 0 {
      let db0: Int = b_dims[bi];
      db = db0;
    }
    var d: Int = 0;
    if da == db {
      d = da;
    } else {
      if da == 1 {
        d = db;
      } else {
        if db == 1 {
          d = da;
        } else {
          return _err_ints("tensor: shapes are not broadcast-compatible");
        }
      }
    }
    dims.push(d);
    k = k + 1;
  }
  return _ok_ints(dims);
}

// Exact shape equality (rank first, then dims).
fn _tensor_same_shape(a: &Tensor, b: &Tensor) -> Bool {
  if a.rank != b.rank {
    return false;
  }
  var i = 0;
  while i < a.rank {
    let ad: Int = a.dims[i];
    let bd: Int = b.dims[i];
    if ad != bd {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Dims with one axis removed (validated axis).
fn _tensor_dims_without(t: &Tensor, axis: Int) -> Vec[Int] {
  var dims = Vec[Int].new();
  var i = 0;
  while i < t.rank {
    if i != axis {
      let d: Int = t.dims[i];
      dims.push(d);
    }
    i = i + 1;
  }
  return dims;
}

// Source base offset of one reduction output cell: decompose the output
// offset through the output strides, then map each output axis to its source
// axis (axes after the reduced one shift down by one).
fn _tensor_reduce_base(dims: &Vec[Int], out_strides: &Vec[Int], src_strides: &Vec[Int], axis: Int, off: Int) -> Int {
  var src: Int = 0;
  var k = 0;
  while k < dims.len() {
    let os: Int = out_strides[k];
    var idx: Int = 0;
    if os > 0 {
      let d: Int = dims[k];
      idx = (off / os) % d;
    }
    var t_axis = k;
    if k >= axis {
      t_axis = k + 1;
    }
    let st: Int = src_strides[t_axis];
    src = src + idx * st;
    k = k + 1;
  }
  return src;
}

// Shared slice validation: returns Ok(row length in elements) or the error.
fn _tensor_slice_check(t: &Tensor, start: Int, count: Int) -> Result[Int, Str] {
  if t.rank < 1 {
    return _err_int("tensor: slice requires rank >= 1");
  }
  if start < 0 || count < 0 {
    return _err_int("tensor: slice range out of bounds");
  }
  let d0: Int = t.dims[0];
  if start > d0 || count > d0 - start {
    return _err_int("tensor: slice range out of bounds");
  }
  var row_len: Int = 0;
  if d0 > 0 {
    row_len = t.data.len() / d0;
  }
  return _ok_int(row_len);
}

// ---------------------------------------------------------------------------
// Private helpers: arithmetic envelope and copies
// ---------------------------------------------------------------------------

// Symmetric-envelope membership test for stored values.
fn _tensor_value_ok(v: Int) -> Bool {
  if v > _TENSOR_INT_MAX {
    return false;
  }
  if v < 0 - _TENSOR_INT_MAX {
    return false;
  }
  return true;
}

// Checked add inside the symmetric envelope.
fn _tensor_add_ok(a: Int, b: Int) -> Bool {
  if b > 0 {
    if a > _TENSOR_INT_MAX - b {
      return false;
    }
    return true;
  }
  if b < 0 {
    if a < (0 - _TENSOR_INT_MAX) - b {
      return false;
    }
    return true;
  }
  return true;
}

// Checked multiply inside the symmetric envelope. INT_MIN never occurs
// because every stored value and every operand is validated first.
fn _tensor_mul_ok(a: Int, b: Int) -> Bool {
  if a == 0 || b == 0 {
    return true;
  }
  var aa = a;
  if aa < 0 {
    aa = 0 - aa;
  }
  var bb = b;
  if bb < 0 {
    bb = 0 - bb;
  }
  if aa <= 0 || bb <= 0 {
    return false;
  }
  if aa > _TENSOR_INT_MAX / bb {
    return false;
  }
  return true;
}

// Copy of a dims vector from a scalar or vector source.
fn _tensor_copy_ints(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    let v: Int = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Copy of a tensor's dims (never pass `&t.dims` to a helper: v0.62.2
// mis-lowers a borrow of a struct field).
fn _tensor_copy_dims(t: &Tensor) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < t.dims.len() {
    let d: Int = t.dims[i];
    out.push(d);
    i = i + 1;
  }
  return out;
}

// Copy of a tensor's flat data buffer.
fn _tensor_copy_data(t: &Tensor) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < t.data.len() {
    let v: Int = t.data[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Leaf Result constructors
// ---------------------------------------------------------------------------

fn _ok_tensor(t: Tensor) -> Result[Tensor, Str] {
  return Ok(t);
}

fn _err_tensor(msg: Str) -> Result[Tensor, Str] {
  return Err(msg);
}

fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

fn _err_ints(msg: Str) -> Result[Vec[Int], Str] {
  return Err(msg);
}

fn _ok_int(x: Int) -> Result[Int, Str] {
  return Ok(x);
}

fn _err_int(msg: Str) -> Result[Int, Str] {
  return Err(msg);
}
