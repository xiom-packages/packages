// XIOM -- xiom.tensor conformance tests (29 checks)
// Port task: prove the pure-XIOM xiom.tensor module against the rules pinned
// in SPEC.md: validated construction, row-major strides, coordinate and flat
// get/set, reshape, rank-2 transpose, axis-0 slicing with an offset map,
// broadcasting, elementwise add/multiply, axis reductions and the canonical
// dump.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every dump and
// error-message check below is routed through streq instead of `==`.

module tensor_tests
use xiom.io; use xiom.test; use xiom.tensor;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// Fixture builders
// ---------------------------------------------------------------------------

fn e() -> Vec[Int] {
  return Vec[Int].new();
}

fn v1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn v4(a: Int, b: Int, c: Int, d: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn v5(a: Int, b: Int, c: Int, d: Int, f: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(f);
  return v;
}

fn v6(a: Int, b: Int, c: Int, d: Int, f: Int, g: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(f);
  v.push(g);
  return v;
}

fn zeros(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
  return v;
}

// ---------------------------------------------------------------------------
// Result extractors with graceful fallbacks: a construction failure makes the
// value checks fail instead of aborting the whole suite.
// ---------------------------------------------------------------------------

fn int_of(r: Result[Int, Str]) -> Int {
  match r {
    Ok(x) => { return x; },
    Err(_) => { return -2; },
  }
  return -2;
}

fn ints_of(r: Result[Vec[Int], Str]) -> Vec[Int] {
  match r {
    Ok(v) => { return v; },
    Err(_) => { return e(); },
  }
  return e();
}

fn tensor_of(r: Result[Tensor, Str]) -> Tensor {
  match r {
    Ok(t) => { return t; },
    Err(_) => { return Tensor{ rank: 0; dims: e(); data: v1(-999); }; },
  }
  return Tensor{ rank: 0; dims: e(); data: v1(-999); };
}

// ---------------------------------------------------------------------------
// Predicates
// ---------------------------------------------------------------------------

fn ints_equal(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn tensor_err(r: Result[Tensor, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn ints_err(r: Result[Vec[Int], Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn int_err(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn eq_int(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(x) => { return x == want; },
    Err(_) => { return false; },
  }
  return false;
}

fn get_is(t: &Tensor, indices: &Vec[Int], want: Int) -> Bool {
  return eq_int(tensor_get(t, indices), want);
}

fn flat_is(t: &Tensor, off: Int, want: Int) -> Bool {
  return eq_int(tensor_get_flat(t, off), want);
}

fn shape_is(t: &Tensor, want: &Vec[Int]) -> Bool {
  let got = tensor_shape(t);
  return ints_equal(&got, want);
}

fn data_is(t: &Tensor, want: &Vec[Int]) -> Bool {
  let got = tensor_data(t);
  return ints_equal(&got, want);
}

fn dump_is(t: &Tensor, want: Str) -> Bool {
  return streq(tensor_dump(t), want);
}

fn zeros_at(t: &Tensor, n: Int) -> Bool {
  var i = 0;
  while i < n {
    if !flat_is(t, i, 0) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let t = tensor_of(tensor_new(2, &v2(2, 3)));
  var ok = tensor_rank(&t) == 2;
  if tensor_dim(&t, 0) != 2 { ok = false; }
  if tensor_dim(&t, 1) != 3 { ok = false; }
  if tensor_dim(&t, 2) != -1 { ok = false; }
  if tensor_dim(&t, -1) != -1 { ok = false; }
  if tensor_numel(&t) != 6 { ok = false; }
  if !shape_is(&t, &v2(2, 3)) { ok = false; }
  if tensor_stride(&t, 0) != 3 { ok = false; }
  if tensor_stride(&t, 1) != 1 { ok = false; }
  if tensor_stride(&t, 2) != -1 { ok = false; }
  let strides = tensor_strides(&t);
  if !ints_equal(&strides, &v2(3, 1)) { ok = false; }
  if t.data.len() != 6 { ok = false; }
  if !zeros_at(&t, 6) { ok = false; }
  return assert(ok, "construction: rank-2 shape, dims, numel and strides");
}

fn t2() -> TestResult {
  let t = tensor_of(tensor_new(1, &v1(5)));
  var ok = tensor_rank(&t) == 1;
  if tensor_numel(&t) != 5 { ok = false; }
  if !shape_is(&t, &v1(5)) { ok = false; }
  let strides = tensor_strides(&t);
  if !ints_equal(&strides, &v1(1)) { ok = false; }
  if tensor_stride(&t, 0) != 1 { ok = false; }
  return assert(ok, "rank-1 tensor: one dimension, stride 1");
}

fn t3() -> TestResult {
  let t = tensor_of(tensor_new(3, &v3(2, 3, 4)));
  var ok = tensor_numel(&t) == 24;
  let strides = tensor_strides(&t);
  if !ints_equal(&strides, &v3(12, 4, 1)) { ok = false; }
  if tensor_stride(&t, 2) != 1 { ok = false; }
  if tensor_stride(&t, 1) != 4 { ok = false; }
  if !shape_is(&t, &v3(2, 3, 4)) { ok = false; }
  return assert(ok, "rank-3 tensor: row-major strides [12,4,1]");
}

fn t4() -> TestResult {
  let t = tensor_of(tensor_new(0, &e()));
  var ok = tensor_rank(&t) == 0;
  if tensor_numel(&t) != 1 { ok = false; }
  if tensor_dim(&t, 0) != -1 { ok = false; }
  if !shape_is(&t, &e()) { ok = false; }
  let strides = tensor_strides(&t);
  if strides.len() != 0 { ok = false; }
  if !get_is(&t, &e(), 0) { ok = false; }
  if !flat_is(&t, 0, 0) { ok = false; }
  if !dump_is(&t, "tensor rank=0 dims=[] data=[0]") { ok = false; }
  return assert(ok, "rank-0 scalar: empty dims, numel 1, empty-index get");
}

fn t5() -> TestResult {
  var ok = tensor_err(tensor_new(7, &v1(1)), "tensor: rank must be between 0 and 6");
  if !tensor_err(tensor_new(-1, &e()), "tensor: rank must be between 0 and 6") { ok = false; }
  if !tensor_err(tensor_new(2, &v3(1, 2, 3)), "tensor: dims length must equal rank") { ok = false; }
  if !tensor_err(tensor_new(1, &v1(-1)), "tensor: dims must be non-negative") { ok = false; }
  if !tensor_err(tensor_new(2, &v2(9223372036854775807, 2)), "tensor: shape product overflows") { ok = false; }
  if !tensor_err(tensor_new(1, &v1(1000001)), "tensor: shape exceeds the element limit") { ok = false; }
  return assert(ok, "construction errors: rank, dims length, negative, overflow, limit");
}

fn t6() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var ok = tensor_numel(&t) == 6;
  if !data_is(&t, &v6(1, 2, 3, 4, 5, 6)) { ok = false; }
  if !get_is(&t, &v2(1, 2), 6) { ok = false; }
  if !get_is(&t, &v2(0, 0), 1) { ok = false; }
  if !dump_is(&t, "tensor rank=2 dims=[2,3] data=[1,2,3,4,5,6]") { ok = false; }
  return assert(ok, "from_flat: values land in row-major order");
}

fn t7() -> TestResult {
  var src = v3(10, 20, 30);
  let t = tensor_of(tensor_from_flat(1, &v1(3), &src));
  src[0] = 99;
  var ok = flat_is(&t, 0, 10);
  if !flat_is(&t, 1, 20) { ok = false; }
  var copy = tensor_data(&t);
  copy[0] = 77;
  if !flat_is(&t, 0, 10) { ok = false; }
  return assert(ok, "copy semantics: from_flat and tensor_data copy the buffer");
}

fn t8() -> TestResult {
  var ok = tensor_err(tensor_from_flat(2, &v2(2, 2), &v3(1, 2, 3)), "tensor: values length does not match shape");
  let huge = 0 - 9223372036854775807 - 1;
  if !tensor_err(tensor_from_flat(1, &v1(1), &v1(huge)), "tensor: value magnitude exceeds the limit") { ok = false; }
  return assert(ok, "from_flat errors: length mismatch and envelope violation");
}

fn t9() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var ok = eq_int(tensor_offset(&t, &v2(0, 0)), 0);
  if !eq_int(tensor_offset(&t, &v2(0, 2)), 2) { ok = false; }
  if !eq_int(tensor_offset(&t, &v2(1, 0)), 3) { ok = false; }
  if !eq_int(tensor_offset(&t, &v2(1, 2)), 5) { ok = false; }
  if !int_err(tensor_offset(&t, &v1(0)), "tensor: index rank does not match tensor rank") { ok = false; }
  if !int_err(tensor_offset(&t, &v2(0, -1)), "tensor: index out of bounds") { ok = false; }
  if !int_err(tensor_offset(&t, &v2(2, 0)), "tensor: index out of bounds") { ok = false; }
  if !int_err(tensor_offset(&t, &v2(0, 3)), "tensor: index out of bounds") { ok = false; }
  return assert(ok, "tensor_offset: row-major formula plus rank and bounds errors");
}

fn t10() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var ok = flat_is(&t, 0, 1);
  if !flat_is(&t, 5, 6) { ok = false; }
  if !int_err(tensor_get_flat(&t, -1), "tensor: offset out of bounds") { ok = false; }
  if !int_err(tensor_get_flat(&t, 6), "tensor: offset out of bounds") { ok = false; }
  if !get_is(&t, &v2(1, 1), 5) { ok = false; }
  return assert(ok, "tensor_get_flat: inclusive bounds and out-of-range errors");
}

fn t11() -> TestResult {
  var t = tensor_of(tensor_from_flat(2, &v2(2, 3), &zeros(6)));
  var ok = eq_int(tensor_set(&mut t, &v2(1, 1), 99), 4);
  if !get_is(&t, &v2(1, 1), 99) { ok = false; }
  if !eq_int(tensor_set_flat(&mut t, 0, -7), 0) { ok = false; }
  if !flat_is(&t, 0, -7) { ok = false; }
  if !int_err(tensor_set(&mut t, &v2(2, 0), 5), "tensor: index out of bounds") { ok = false; }
  if !flat_is(&t, 0, -7) { ok = false; }
  if !int_err(tensor_set_flat(&mut t, 6, 5), "tensor: offset out of bounds") { ok = false; }
  if tensor_numel(&t) != 6 { ok = false; }
  return assert(ok, "tensor_set/tensor_set_flat: writes, returns offset, fails closed");
}

fn t12() -> TestResult {
  var t = tensor_of(tensor_from_flat(1, &v1(1), &v1(0)));
  let too_small = 0 - 9223372036854775807 - 1;
  var ok = int_err(tensor_set(&mut t, &v1(0), too_small), "tensor: value magnitude exceeds the limit");
  if !flat_is(&t, 0, 0) { ok = false; }
  if !int_err(tensor_set_flat(&mut t, 0, too_small), "tensor: value magnitude exceeds the limit") { ok = false; }
  if !flat_is(&t, 0, 0) { ok = false; }
  return assert(ok, "set envelope: out-of-envelope values are rejected unwritten");
}

fn t13() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let r1 = tensor_of(tensor_reshape(&t, 2, &v2(3, 2)));
  var ok = shape_is(&r1, &v2(3, 2));
  if !data_is(&r1, &v6(1, 2, 3, 4, 5, 6)) { ok = false; }
  let r2 = tensor_of(tensor_reshape(&t, 1, &v1(6)));
  if tensor_rank(&r2) != 1 { ok = false; }
  if !shape_is(&r2, &v1(6)) { ok = false; }
  let one = tensor_of(tensor_from_flat(1, &v1(1), &v1(42)));
  let r3 = tensor_of(tensor_reshape(&one, 0, &e()));
  if tensor_rank(&r3) != 0 { ok = false; }
  if !flat_is(&r3, 0, 42) { ok = false; }
  return assert(ok, "reshape: same element count, flat order preserved, rank 0 allowed");
}

fn t14() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var ok = tensor_err(tensor_reshape(&t, 1, &v1(4)), "tensor: reshape changes the element count");
  if !tensor_err(tensor_reshape(&t, 7, &v1(1)), "tensor: rank must be between 0 and 6") { ok = false; }
  if !tensor_err(tensor_reshape(&t, 1, &v2(2, 3)), "tensor: dims length must equal rank") { ok = false; }
  return assert(ok, "reshape errors: count change, bad rank, dims length");
}

fn t15() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var r = tensor_of(tensor_reshape(&t, 2, &v2(3, 2)));
  let set = tensor_set(&mut r, &v2(0, 0), 100);
  var ok = eq_int(set, 0);
  if !data_is(&t, &v6(1, 2, 3, 4, 5, 6)) { ok = false; }
  if !flat_is(&r, 0, 100) { ok = false; }
  if !flat_is(&t, 0, 1) { ok = false; }
  return assert(ok, "copy semantics: reshape returns an independent tensor");
}

fn t16() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let tr = tensor_of(tensor_transpose2(&t));
  var ok = shape_is(&tr, &v2(3, 2));
  if !data_is(&tr, &v6(1, 4, 2, 5, 3, 6)) { ok = false; }
  if !get_is(&tr, &v2(2, 1), 6) { ok = false; }
  if !get_is(&tr, &v2(1, 0), 2) { ok = false; }
  if !dump_is(&tr, "tensor rank=2 dims=[3,2] data=[1,4,2,5,3,6]") { ok = false; }
  return assert(ok, "transpose rank 2: dims swap and out[col,row] = t[row,col]");
}

fn t17() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let once = tensor_of(tensor_transpose2(&t));
  let back = tensor_of(tensor_transpose2(&once));
  var ok = shape_is(&back, &v2(2, 3));
  if !data_is(&back, &v6(1, 2, 3, 4, 5, 6)) { ok = false; }
  let row = tensor_of(tensor_new(1, &v1(3)));
  if !tensor_err(tensor_transpose2(&row), "tensor: transpose requires rank 2") { ok = false; }
  let scalar = tensor_of(tensor_new(0, &e()));
  if !tensor_err(tensor_transpose2(&scalar), "tensor: transpose requires rank 2") { ok = false; }
  let empty = tensor_of(tensor_new(2, &v2(0, 3)));
  let et = tensor_of(tensor_transpose2(&empty));
  if !shape_is(&et, &v2(3, 0)) { ok = false; }
  if et.data.len() != 0 { ok = false; }
  return assert(ok, "transpose involution, rank guard and empty matrix");
}

fn t18() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(3, 2), &v6(1, 2, 3, 4, 5, 6)));
  let s = tensor_of(tensor_slice_axis0(&t, 1, 2));
  var ok = shape_is(&s, &v2(2, 2));
  if !data_is(&s, &v4(3, 4, 5, 6)) { ok = false; }
  let first = tensor_of(tensor_slice_axis0(&t, 0, 1));
  if !data_is(&first, &v2(1, 2)) { ok = false; }
  let none = tensor_of(tensor_slice_axis0(&t, 0, 0));
  if !shape_is(&none, &v2(0, 2)) { ok = false; }
  if none.data.len() != 0 { ok = false; }
  let tail = tensor_of(tensor_slice_axis0(&t, 3, 0));
  if !shape_is(&tail, &v2(0, 2)) { ok = false; }
  return assert(ok, "slice axis 0: row window copy, count 0 and empty tail");
}

fn t19() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(3, 2), &v6(1, 2, 3, 4, 5, 6)));
  let scalar = tensor_of(tensor_new(0, &e()));
  var ok = tensor_err(tensor_slice_axis0(&scalar, 0, 1), "tensor: slice requires rank >= 1");
  if !tensor_err(tensor_slice_axis0(&t, -1, 1), "tensor: slice range out of bounds") { ok = false; }
  if !tensor_err(tensor_slice_axis0(&t, 0, -1), "tensor: slice range out of bounds") { ok = false; }
  if !tensor_err(tensor_slice_axis0(&t, 4, 0), "tensor: slice range out of bounds") { ok = false; }
  if !tensor_err(tensor_slice_axis0(&t, 1, 3), "tensor: slice range out of bounds") { ok = false; }
  return assert(ok, "slice errors: rank 0, negative range, past dims[0]");
}

fn t20() -> TestResult {
  let t = tensor_of(tensor_from_flat(1, &v1(5), &v5(10, 20, 30, 40, 50)));
  let s = tensor_of(tensor_slice_axis0(&t, 1, 3));
  var ok = shape_is(&s, &v1(3));
  if !data_is(&s, &v3(20, 30, 40)) { ok = false; }
  let offs = ints_of(tensor_slice_offsets_axis0(&t, 1, 3));
  if !ints_equal(&offs, &v3(1, 2, 3)) { ok = false; }
  let all = tensor_of(tensor_slice_axis0(&t, 0, 5));
  if !data_is(&all, &v5(10, 20, 30, 40, 50)) { ok = false; }
  let full_offs = ints_of(tensor_slice_offsets_axis0(&t, 0, 5));
  if !ints_equal(&full_offs, &v5(0, 1, 2, 3, 4)) { ok = false; }
  if !ints_err(tensor_slice_offsets_axis0(&t, 2, 4), "tensor: slice range out of bounds") { ok = false; }
  return assert(ok, "slice rank 1 and offset map: offsets index the source exactly");
}

fn t21() -> TestResult {
  let a = tensor_of(tensor_from_flat(2, &v2(2, 2), &v4(1, 2, 3, 4)));
  let b = tensor_of(tensor_from_flat(2, &v2(2, 2), &v4(10, 20, 30, 40)));
  let sum = tensor_of(tensor_add(&a, &b));
  var ok = shape_is(&sum, &v2(2, 2));
  if !data_is(&sum, &v4(11, 22, 33, 44)) { ok = false; }
  let c = tensor_of(tensor_from_flat(1, &v1(4), &v4(1, 2, 3, 4)));
  if !tensor_err(tensor_add(&a, &c), "tensor: shapes are not equal") { ok = false; }
  let scalar = tensor_of(tensor_new(0, &e()));
  if !tensor_err(tensor_add(&a, &scalar), "tensor: shapes are not equal") { ok = false; }
  return assert(ok, "elementwise add: equal shapes only");
}

fn t22() -> TestResult {
  let a = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let b = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(2, 2, 2, 0, 3, 1)));
  let p = tensor_of(tensor_mul(&a, &b));
  var ok = shape_is(&p, &v2(2, 3));
  if !data_is(&p, &v6(2, 4, 6, 0, 15, 6)) { ok = false; }
  let c = tensor_of(tensor_from_flat(1, &v1(6), &v6(1, 1, 1, 1, 1, 1)));
  if !tensor_err(tensor_mul(&a, &c), "tensor: shapes are not equal") { ok = false; }
  return assert(ok, "elementwise multiply: equal shapes only, zeros propagate");
}

fn t23() -> TestResult {
  let maxv = 9223372036854775807;
  let a = tensor_of(tensor_from_flat(1, &v1(1), &v1(maxv)));
  let one = tensor_of(tensor_from_flat(1, &v1(1), &v1(1)));
  let two = tensor_of(tensor_from_flat(1, &v1(1), &v1(2)));
  var ok = tensor_err(tensor_add(&a, &one), "tensor: addition overflows");
  if !tensor_err(tensor_mul(&a, &two), "tensor: multiplication overflows") { ok = false; }
  let zero = tensor_of(tensor_from_flat(1, &v1(1), &v1(0)));
  let z = tensor_of(tensor_mul(&a, &zero));
  if !flat_is(&z, 0, 0) { ok = false; }
  return assert(ok, "checked arithmetic: add/multiply overflow fail closed");
}

fn t24() -> TestResult {
  let a = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let row = tensor_of(tensor_from_flat(1, &v1(3), &v3(10, 20, 30)));
  let ab = tensor_of(tensor_broadcast_add(&a, &row));
  var ok = shape_is(&ab, &v2(2, 3));
  if !data_is(&ab, &v6(11, 22, 33, 14, 25, 36)) { ok = false; }
  let col = tensor_of(tensor_from_flat(2, &v2(2, 1), &v2(100, 200)));
  let cb = tensor_of(tensor_broadcast_add(&a, &col));
  if !data_is(&cb, &v6(101, 102, 103, 204, 205, 206)) { ok = false; }
  let l = tensor_of(tensor_from_flat(2, &v2(2, 1), &v2(1, 2)));
  let r = tensor_of(tensor_from_flat(2, &v2(1, 3), &v3(10, 20, 30)));
  let grid = tensor_of(tensor_broadcast_add(&l, &r));
  if !shape_is(&grid, &v2(2, 3)) { ok = false; }
  if !data_is(&grid, &v6(11, 21, 31, 12, 22, 32)) { ok = false; }
  let sc = tensor_of(tensor_from_flat(0, &e(), &v1(7)));
  let sb = tensor_of(tensor_broadcast_add(&a, &sc));
  if !data_is(&sb, &v6(8, 9, 10, 11, 12, 13)) { ok = false; }
  return assert(ok, "broadcast add: row, column, outer grid and scalar");
}

fn t25() -> TestResult {
  let a = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let bad = tensor_of(tensor_from_flat(1, &v1(2), &v2(1, 2)));
  var ok = tensor_err(tensor_broadcast_add(&a, &bad), "tensor: shapes are not broadcast-compatible");
  let wide = tensor_of(tensor_new(2, &v2(200000, 1)));
  let tall = tensor_of(tensor_new(2, &v2(1, 6)));
  if !tensor_err(tensor_broadcast_add(&wide, &tall), "tensor: shape exceeds the element limit") { ok = false; }
  return assert(ok, "broadcast errors: incompatible axis and oversized result");
}

fn t26() -> TestResult {
  let maxv = 9223372036854775807;
  let a = tensor_of(tensor_from_flat(2, &v2(2, 1), &v2(maxv, 1)));
  let b = tensor_of(tensor_from_flat(2, &v2(1, 2), &v2(1, 1)));
  var ok = tensor_err(tensor_broadcast_add(&a, &b), "tensor: addition overflows");
  return assert(ok, "broadcast add: checked overflow inside the expanded loop");
}

fn t27() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 4, 5, 6)));
  let s0 = tensor_of(tensor_sum_axis(&t, 0));
  var ok = shape_is(&s0, &v1(3));
  if !data_is(&s0, &v3(5, 7, 9)) { ok = false; }
  let s1 = tensor_of(tensor_sum_axis(&t, 1));
  if !shape_is(&s1, &v1(2)) { ok = false; }
  if !data_is(&s1, &v2(6, 15)) { ok = false; }
  let v = tensor_of(tensor_from_flat(1, &v1(4), &v4(1, 2, 3, 4)));
  let sv = tensor_of(tensor_sum_axis(&v, 0));
  if tensor_rank(&sv) != 0 { ok = false; }
  if !flat_is(&sv, 0, 10) { ok = false; }
  let empty = tensor_of(tensor_new(2, &v2(0, 2)));
  let se = tensor_of(tensor_sum_axis(&empty, 0));
  if !shape_is(&se, &v1(2)) { ok = false; }
  if !data_is(&se, &v2(0, 0)) { ok = false; }
  if !tensor_err(tensor_sum_axis(&t, 2), "tensor: axis out of range") { ok = false; }
  if !tensor_err(tensor_sum_axis(&t, -1), "tensor: axis out of range") { ok = false; }
  return assert(ok, "sum along an axis: shape drops the axis, empty sum is 0");
}

fn t28() -> TestResult {
  let t = tensor_of(tensor_from_flat(2, &v2(2, 3), &v6(1, 2, 3, 6, 5, 4)));
  let m0 = tensor_of(tensor_max_axis(&t, 0));
  var ok = shape_is(&m0, &v1(3));
  if !data_is(&m0, &v3(6, 5, 4)) { ok = false; }
  let m1 = tensor_of(tensor_max_axis(&t, 1));
  if !data_is(&m1, &v2(3, 6)) { ok = false; }
  let empty = tensor_of(tensor_new(2, &v2(0, 2)));
  if !tensor_err(tensor_max_axis(&empty, 0), "tensor: max of an empty reduction") { ok = false; }
  if !tensor_err(tensor_max_axis(&t, 3), "tensor: axis out of range") { ok = false; }
  return assert(ok, "max along an axis: values plus empty-reduction error");
}

fn t29() -> TestResult {
  let t = tensor_of(tensor_from_flat(3, &v3(1, 2, 3), &v6(1, 2, 3, 4, 5, 6)));
  var ok = dump_is(&t, "tensor rank=3 dims=[1,2,3] data=[1,2,3,4,5,6]");
  let empty = tensor_of(tensor_new(1, &v1(0)));
  if !dump_is(&empty, "tensor rank=1 dims=[0] data=[]") { ok = false; }
  var s = tensor_shape(&t);
  s[0] = 9;
  if tensor_dim(&t, 0) != 1 { ok = false; }
  var d = tensor_data(&t);
  d[0] = 9;
  if !flat_is(&t, 0, 1) { ok = false; }
  var st = tensor_strides(&t);
  st[0] = 9;
  if tensor_stride(&t, 0) != 6 { ok = false; }
  return assert(ok, "canonical dump plus shape/data/strides copy independence");
}

fn main() -> Int {
  io.println("=== xiom.tensor conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.tensor: all tests passed");
  } else {
    io.println("xiom.tensor: tests failed");
  }
  return failed;
}
