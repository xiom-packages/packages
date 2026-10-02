// XIOM -- xiom.data conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.data modules against the rules pinned
// in SPEC.md: dataset container and iterators, batch assembly/collation,
// the batched loader, sequential/shuffled/weighted samplers, the
// deterministic MINSTD LCG Fisher-Yates shuffle and train/validation/test
// splitting.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every dump and
// error-message check below is routed through streq instead of `==`.

module data_tests
use xiom.io; use xiom.test;
use xiom.data; use xiom.data.batch; use xiom.data.order;
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

fn zeros(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
  return v;
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

fn v8(a: Int, b: Int, c: Int, d: Int, f: Int, g: Int, h: Int, i: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  return v;
}

fn v10(a: Int, b: Int, c: Int, d: Int, f: Int, g: Int, h: Int, i: Int, j: Int, k: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(f);
  v.push(g);
  v.push(h);
  v.push(i);
  v.push(j);
  v.push(k);
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

fn dataset_of(r: Result[Dataset, Str]) -> Dataset {
  match r {
    Ok(d) => { return d; },
    Err(_) => { return Dataset{ n: 0; width: 0; xs: e(); ys: e(); }; },
  }
  return Dataset{ n: 0; width: 0; xs: e(); ys: e(); };
}

fn batch_of(r: Result[Batch, Str]) -> Batch {
  match r {
    Ok(b) => { return b; },
    Err(_) => { return Batch{ n: 0; width: 0; xs: e(); ys: e(); indices: e(); }; },
  }
  return Batch{ n: 0; width: 0; xs: e(); ys: e(); indices: e(); };
}

fn loader_of(r: Result[Loader, Str]) -> Loader {
  match r {
    Ok(l) => { return l; },
    Err(_) => { return Loader{ n: 0; width: 0; order: e(); batch_size: 1; drop_last: 0; cursor: 0; }; },
  }
  return Loader{ n: 0; width: 0; order: e(); batch_size: 1; drop_last: 0; cursor: 0; };
}

fn sampler_of(r: Result[Sampler, Str]) -> Sampler {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return Sampler{ n: 0; order: e(); }; },
  }
  return Sampler{ n: 0; order: e(); };
}

fn split_of(r: Result[Split, Str]) -> Split {
  match r {
    Ok(s) => { return s; },
    Err(_) => { return Split{ train: e(); val: e(); test: e(); }; },
  }
  return Split{ train: e(); val: e(); test: e(); };
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

fn dataset_err(r: Result[Dataset, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn batch_err(r: Result[Batch, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn loader_err(r: Result[Loader, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn sampler_err(r: Result[Sampler, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(msg) => { return streq(msg, want); },
  }
  return false;
}

fn split_err(r: Result[Split, Str], want: Str) -> Bool {
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

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

// n = 4, width = 2: rows [1,2] [3,4] [5,6] [7,8], labels [0,1,0,1].
fn base() -> Dataset {
  return dataset_of(dataset_from_flat(2, &v8(1, 2, 3, 4, 5, 6, 7, 8), &v4(0, 1, 0, 1)));
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let d = base();
  let vals = dataset_values(&d);
  let labs = dataset_labels(&d);
  let row = ints_of(dataset_row(&d, 2));
  var ok = dataset_num_samples(&d) == 4;
  if dataset_width(&d) != 2 { ok = false; }
  if dataset_num_values(&d) != 8 { ok = false; }
  if int_of(dataset_get(&d, 0, 0)) != 1 { ok = false; }
  if int_of(dataset_get(&d, 0, 1)) != 2 { ok = false; }
  if int_of(dataset_get(&d, 3, 1)) != 8 { ok = false; }
  if int_of(dataset_label(&d, 0)) != 0 { ok = false; }
  if int_of(dataset_label(&d, 3)) != 1 { ok = false; }
  if !ints_equal(&vals, &v8(1, 2, 3, 4, 5, 6, 7, 8)) { ok = false; }
  if !ints_equal(&labs, &v4(0, 1, 0, 1)) { ok = false; }
  if !ints_equal(&row, &v2(5, 6)) { ok = false; }
  return assert(ok, "dataset: shape, labels, values and row access");
}

fn t2() -> TestResult {
  var ok = dataset_err(dataset_from_flat(-1, &e(), &v1(0)), "data: width must be non-negative");
  if !dataset_err(dataset_from_flat(2, &v8(1, 2, 3, 4, 5, 6, 7, 8), &v3(0, 1, 0)), "data: flat length does not match sample count") { ok = false; }
  if !dataset_err(dataset_from_flat(9223372036854775807, &e(), &v2(1, 2)), "data: flat length overflows") { ok = false; }
  var many = zeros(1000001);
  if !dataset_err(dataset_from_flat(0, &e(), &many), "data: sample count exceeds the limit") { ok = false; }
  var wide = zeros(2000000);
  if !dataset_err(dataset_from_flat(1000000, &wide, &v2(1, 2)), "data: value count exceeds the limit") { ok = false; }
  return assert(ok, "dataset errors: width, length, overflow, sample and value caps");
}

fn t3() -> TestResult {
  let d = base();
  var ok = int_err(dataset_get(&d, -1, 0), "data: sample index out of bounds");
  if !int_err(dataset_get(&d, 4, 0), "data: sample index out of bounds") { ok = false; }
  if !int_err(dataset_get(&d, 0, -1), "data: feature index out of bounds") { ok = false; }
  if !int_err(dataset_get(&d, 0, 2), "data: feature index out of bounds") { ok = false; }
  if !int_err(dataset_label(&d, 4), "data: sample index out of bounds") { ok = false; }
  if !ints_err(dataset_row(&d, 4), "data: sample index out of bounds") { ok = false; }
  let labels_only = dataset_of(dataset_from_labels(&v3(5, 6, 7)));
  var ok2 = dataset_num_samples(&labels_only) == 3;
  if dataset_width(&labels_only) != 0 { ok2 = false; }
  if dataset_num_values(&labels_only) != 0 { ok2 = false; }
  if int_of(dataset_label(&labels_only, 1)) != 6 { ok2 = false; }
  if !int_err(dataset_get(&labels_only, 0, 0), "data: feature index out of bounds") { ok2 = false; }
  if !ints_equal(&ints_of(dataset_row(&labels_only, 0)), &e()) { ok2 = false; }
  if !ok2 { ok = false; }
  return assert(ok, "dataset access errors plus label-only construction");
}

fn t4() -> TestResult {
  let d = base();
  var it = dataset_iter(&d);
  var ok = dataset_iter_remaining(&it) == 4;
  let a: Int = dataset_iter_next(&mut it);
  if a != 0 { ok = false; }
  if dataset_iter_remaining(&it) != 3 { ok = false; }
  let b: Int = dataset_iter_next(&mut it);
  let c: Int = dataset_iter_next(&mut it);
  let f: Int = dataset_iter_next(&mut it);
  if b != 1 { ok = false; }
  if c != 2 { ok = false; }
  if f != 3 { ok = false; }
  if dataset_iter_next(&mut it) != -1 { ok = false; }
  dataset_iter_reset(&mut it);
  if dataset_iter_remaining(&it) != 4 { ok = false; }
  let again: Int = dataset_iter_next(&mut it);
  if again != 0 { ok = false; }
  let empty = dataset_of(dataset_from_flat(0, &e(), &e()));
  var it2 = dataset_iter(&empty);
  if dataset_iter_next(&mut it2) != -1 { ok = false; }
  if dataset_iter_remaining(&it2) != 0 { ok = false; }
  return assert(ok, "dataset iterator: forward order, reset and empty dataset");
}

fn t5() -> TestResult {
  var xs = v8(1, 2, 3, 4, 5, 6, 7, 8);
  var ys = v4(0, 1, 0, 1);
  let d = dataset_of(dataset_from_flat(2, &xs, &ys));
  xs[0] = 99;
  ys[0] = 99;
  var ok = int_of(dataset_get(&d, 0, 0)) == 1;
  if int_of(dataset_label(&d, 0)) != 0 { ok = false; }
  var vals = dataset_values(&d);
  vals[1] = 77;
  if int_of(dataset_get(&d, 0, 1)) != 2 { ok = false; }
  var labs = dataset_labels(&d);
  labs[0] = 77;
  if int_of(dataset_label(&d, 0)) != 0 { ok = false; }
  var row = ints_of(dataset_row(&d, 0));
  row[0] = 55;
  if int_of(dataset_get(&d, 0, 0)) != 1 { ok = false; }
  return assert(ok, "copy semantics: constructor, values, labels and rows are independent");
}

fn t6() -> TestResult {
  let d = base();
  let b = batch_of(batch_assemble(&d, &v2(3, 1)));
  var ok = batch_size(&b) == 2;
  if batch_width(&b) != 2 { ok = false; }
  if int_of(batch_index(&b, 0)) != 3 { ok = false; }
  if int_of(batch_index(&b, 1)) != 1 { ok = false; }
  if int_of(batch_label(&b, 0)) != 1 { ok = false; }
  if int_of(batch_label(&b, 1)) != 1 { ok = false; }
  if int_of(batch_get(&b, 0, 0)) != 7 { ok = false; }
  if int_of(batch_get(&b, 0, 1)) != 8 { ok = false; }
  if int_of(batch_get(&b, 1, 0)) != 3 { ok = false; }
  if int_of(batch_get(&b, 1, 1)) != 4 { ok = false; }
  if !ints_equal(&ints_of(batch_row(&b, 1)), &v2(3, 4)) { ok = false; }
  if !ints_equal(&batch_labels(&b), &v2(1, 1)) { ok = false; }
  if !ints_equal(&batch_indices(&b), &v2(3, 1)) { ok = false; }
  if !streq(batch_dump(&b), "batch n=2 width=2 indices=[3,1] labels=[1,1] data=[7,8,3,4]") { ok = false; }
  return assert(ok, "batch assembly: order, labels, indices and canonical dump");
}

fn t7() -> TestResult {
  let d = base();
  let b = batch_of(batch_assemble(&d, &v2(0, 0)));
  var ok = batch_size(&b) == 2;
  if !ints_equal(&batch_indices(&b), &v2(0, 0)) { ok = false; }
  if !ints_equal(&batch_labels(&b), &v2(0, 0)) { ok = false; }
  if int_of(batch_get(&b, 1, 0)) != 1 { ok = false; }
  if !batch_err(batch_assemble(&d, &v1(4)), "data: batch index out of bounds") { ok = false; }
  if !batch_err(batch_assemble(&d, &v1(-1)), "data: batch index out of bounds") { ok = false; }
  if !int_err(batch_get(&b, 2, 0), "data: sample index out of bounds") { ok = false; }
  if !int_err(batch_get(&b, 0, 2), "data: feature index out of bounds") { ok = false; }
  if !int_err(batch_label(&b, -1), "data: sample index out of bounds") { ok = false; }
  if !int_err(batch_index(&b, 2), "data: sample index out of bounds") { ok = false; }
  if !ints_err(batch_row(&b, 2), "data: sample index out of bounds") { ok = false; }
  return assert(ok, "batch: duplicate indices allowed, range errors fail closed");
}

fn t8() -> TestResult {
  let d = base();
  let b = batch_of(batch_slice(&d, 1, 2));
  var ok = ints_equal(&batch_indices(&b), &v2(1, 2));
  if !ints_equal(&batch_labels(&b), &v2(1, 0)) { ok = false; }
  if int_of(batch_get(&b, 0, 0)) != 3 { ok = false; }
  if int_of(batch_get(&b, 1, 1)) != 6 { ok = false; }
  let empty = batch_of(batch_slice(&d, 2, 0));
  if batch_size(&empty) != 0 { ok = false; }
  if !streq(batch_dump(&empty), "batch n=0 width=2 indices=[] labels=[] data=[]") { ok = false; }
  if !batch_err(batch_slice(&d, -1, 0), "data: batch slice out of bounds") { ok = false; }
  if !batch_err(batch_slice(&d, 0, -1), "data: batch slice out of bounds") { ok = false; }
  if !batch_err(batch_slice(&d, 3, 2), "data: batch slice out of bounds") { ok = false; }
  if !batch_err(batch_slice(&d, 5, 0), "data: batch slice out of bounds") { ok = false; }
  return assert(ok, "batch window: contents, empty window and bounds errors");
}

fn t9() -> TestResult {
  let d = base();
  var l = loader_of(loader_new(&d, 2, 0));
  var ok = loader_num_batches(&l) == 2;
  if loader_batch_size(&l) != 2 { ok = false; }
  if !loader_has_next(&l) { ok = false; }
  let b1 = batch_of(loader_next(&d, &mut l));
  if !ints_equal(&batch_indices(&b1), &v2(0, 1)) { ok = false; }
  if loader_position(&l) != 2 { ok = false; }
  let b2 = batch_of(loader_next(&d, &mut l));
  if !ints_equal(&batch_indices(&b2), &v2(2, 3)) { ok = false; }
  if int_of(batch_get(&b2, 1, 1)) != 8 { ok = false; }
  if loader_has_next(&l) { ok = false; }
  if !batch_err(loader_next(&d, &mut l), "data: loader is exhausted") { ok = false; }
  return assert(ok, "loader: identity order, batch count and exhaustion");
}

fn t10() -> TestResult {
  let d = base();
  var l1 = loader_of(loader_new(&d, 3, 1));
  var ok = loader_num_batches(&l1) == 1;
  let b1 = batch_of(loader_next(&d, &mut l1));
  if batch_size(&b1) != 3 { ok = false; }
  if !ints_equal(&batch_indices(&b1), &v3(0, 1, 2)) { ok = false; }
  if loader_has_next(&l1) { ok = false; }
  if !batch_err(loader_next(&d, &mut l1), "data: loader is exhausted") { ok = false; }
  var l2 = loader_of(loader_new(&d, 3, 0));
  if loader_num_batches(&l2) != 2 { ok = false; }
  let p1 = batch_of(loader_next(&d, &mut l2));
  if batch_size(&p1) != 3 { ok = false; }
  let p2 = batch_of(loader_next(&d, &mut l2));
  if batch_size(&p2) != 1 { ok = false; }
  if !ints_equal(&batch_indices(&p2), &v1(3)) { ok = false; }
  if int_of(batch_label(&p2, 0)) != 1 { ok = false; }
  return assert(ok, "loader: drop_last drops the partial tail, keep mode returns it");
}

fn t11() -> TestResult {
  let d = base();
  let empty = dataset_of(dataset_from_flat(0, &e(), &e()));
  var l0 = loader_of(loader_new(&empty, 1, 0));
  var ok = loader_num_batches(&l0) == 0;
  if loader_has_next(&l0) { ok = false; }
  if !batch_err(loader_next(&empty, &mut l0), "data: loader is exhausted") { ok = false; }
  var l1 = loader_of(loader_new(&d, 10, 0));
  if loader_num_batches(&l1) != 1 { ok = false; }
  let b = batch_of(loader_next(&d, &mut l1));
  if batch_size(&b) != 4 { ok = false; }
  if loader_has_next(&l1) { ok = false; }
  return assert(ok, "loader: empty dataset and batch size larger than n");
}

fn t12() -> TestResult {
  let d = base();
  var l = loader_of(loader_from_order(&d, &v4(3, 2, 1, 0), 2, 0));
  let b = batch_of(loader_next(&d, &mut l));
  var ok = ints_equal(&batch_indices(&b), &v2(3, 2));
  if !ints_equal(&batch_labels(&b), &v2(1, 0)) { ok = false; }
  if int_of(batch_get(&b, 0, 0)) != 7 { ok = false; }
  if int_of(batch_get(&b, 1, 1)) != 6 { ok = false; }
  if !loader_err(loader_from_order(&d, &v4(0, 1, 2, 3), 0, 0), "data: batch size must be positive") { ok = false; }
  if !loader_err(loader_from_order(&d, &v4(0, 1, 2, 3), 2, 2), "data: drop_last must be 0 or 1") { ok = false; }
  if !loader_err(loader_from_order(&d, &v3(0, 1, 2), 2, 0), "data: order length must equal sample count") { ok = false; }
  if !loader_err(loader_from_order(&d, &v4(0, 0, 1, 2), 2, 0), "data: order must be a permutation of 0..n-1") { ok = false; }
  if !loader_err(loader_from_order(&d, &v4(0, 1, 2, 4), 2, 0), "data: order must be a permutation of 0..n-1") { ok = false; }
  return assert(ok, "loader_from_order: custom order plus validation errors");
}

fn t13() -> TestResult {
  let d = base();
  var l = loader_of(loader_new(&d, 2, 0));
  let b1 = batch_of(loader_next(&d, &mut l));
  var ok = ints_equal(&batch_indices(&b1), &v2(0, 1));
  loader_reset(&mut l);
  if loader_position(&l) != 0 { ok = false; }
  let b2 = batch_of(loader_next(&d, &mut l));
  if !ints_equal(&batch_indices(&b2), &v2(0, 1)) { ok = false; }
  let other = dataset_of(dataset_from_flat(1, &v4(1, 2, 3, 4), &v4(0, 1, 0, 1)));
  if !batch_err(loader_next(&other, &mut l), "data: dataset does not match loader") { ok = false; }
  return assert(ok, "loader reset replays the pass; mismatched dataset is refused");
}

fn t14() -> TestResult {
  let s = sampler_of(sampler_sequential(4));
  let o = sampler_order(&s);
  var ok = sampler_len(&s) == 4;
  if sampler_get(&s, 0) != 0 { ok = false; }
  if sampler_get(&s, 3) != 3 { ok = false; }
  if sampler_get(&s, 4) != -1 { ok = false; }
  if sampler_get(&s, -1) != -1 { ok = false; }
  if !sampler_is_permutation(&s) { ok = false; }
  if !ints_equal(&o, &v4(0, 1, 2, 3)) { ok = false; }
  let s2 = sampler_of(sampler_from_order(4, &v4(2, 0, 3, 1)));
  let o2 = sampler_order(&s2);
  if !ints_equal(&o2, &v4(2, 0, 3, 1)) { ok = false; }
  if !sampler_is_permutation(&s2) { ok = false; }
  return assert(ok, "sampler: sequential order, explicit order and accessors");
}

fn t15() -> TestResult {
  var ok = sampler_err(sampler_sequential(-1), "data: sample count must be non-negative");
  if !sampler_err(sampler_sequential(1000001), "data: sample count exceeds the limit") { ok = false; }
  if !sampler_err(sampler_from_order(4, &v3(0, 1, 2)), "data: order length must equal sample count") { ok = false; }
  if !sampler_err(sampler_from_order(4, &v4(0, 0, 1, 2)), "data: order must be a permutation of 0..n-1") { ok = false; }
  if !sampler_err(sampler_from_order(4, &v4(0, 1, 2, 4)), "data: order must be a permutation of 0..n-1") { ok = false; }
  if !ints_err(shuffle_order(-1, 1), "data: sample count must be non-negative") { ok = false; }
  if !ints_err(shuffle_order(1000001, 1), "data: sample count exceeds the limit") { ok = false; }
  return assert(ok, "sampler and shuffle size errors fail closed");
}

fn t16() -> TestResult {
  let s = sampler_of(sampler_weighted(5, &v5(1, 3, 3, 0, 2)));
  let o = sampler_order(&s);
  var ok = ints_equal(&o, &v5(1, 2, 4, 0, 3));
  if !sampler_is_permutation(&s) { ok = false; }
  if !sampler_err(sampler_weighted(-1, &e()), "data: sample count must be non-negative") { ok = false; }
  if !sampler_err(sampler_weighted(10001, &e()), "data: weighted sampler sample count exceeds the limit") { ok = false; }
  if !sampler_err(sampler_weighted(3, &v2(1, 2)), "data: weight count must equal sample count") { ok = false; }
  if !sampler_err(sampler_weighted(3, &v3(1, -1, 2)), "data: weight must be non-negative") { ok = false; }
  return assert(ok, "weighted sampler: descending stable order and errors");
}

fn t17() -> TestResult {
  let s1 = sampler_of(sampler_shuffled(8, 12345));
  let s2 = sampler_of(sampler_shuffled(8, 12345));
  let s3 = sampler_of(sampler_shuffled(8, 12346));
  let o1 = sampler_order(&s1);
  let o2 = sampler_order(&s2);
  let o3 = sampler_order(&s3);
  let shuffled = ints_of(shuffle_order(8, 12345));
  var ok = ints_equal(&o1, &v8(6, 0, 4, 2, 3, 5, 1, 7));
  if !ints_equal(&o1, &o2) { ok = false; }
  if !ints_equal(&o1, &shuffled) { ok = false; }
  if !sampler_is_permutation(&s1) { ok = false; }
  if ints_equal(&o1, &v8(0, 1, 2, 3, 4, 5, 6, 7)) { ok = false; }
  if ints_equal(&o1, &o3) { ok = false; }
  if !ints_equal(&o3, &v8(5, 2, 7, 0, 3, 4, 1, 6)) { ok = false; }
  return assert(ok, "sampler_shuffled: same seed reproduces, different seed diverges");
}

fn t18() -> TestResult {
  let o8 = ints_of(shuffle_order(8, 12345));
  let o5 = ints_of(shuffle_order(5, 42));
  let o1 = ints_of(shuffle_order(1, 7));
  let o0 = ints_of(shuffle_order(0, 7));
  let o10 = ints_of(shuffle_order(10, 12345));
  var ok = ints_equal(&o8, &v8(6, 0, 4, 2, 3, 5, 1, 7));
  if !ints_equal(&o5, &v5(0, 1, 4, 3, 2)) { ok = false; }
  if !ints_equal(&o1, &v1(0)) { ok = false; }
  if !ints_equal(&o0, &e()) { ok = false; }
  if !ints_equal(&o10, &v10(8, 7, 1, 2, 3, 6, 0, 9, 4, 5)) { ok = false; }
  return assert(ok, "shuffle_order: pinned MINSTD Fisher-Yates vectors");
}

fn t19() -> TestResult {
  var ok = shuffle_seed_default() == 12345;
  if shuffle_lcg_modulus() != 2147483647 { ok = false; }
  if shuffle_lcg_multiplier() != 48271 { ok = false; }
  if shuffle_seed_normalize(0) != 2147483646 { ok = false; }
  if shuffle_seed_normalize(-1) != 2147483645 { ok = false; }
  if shuffle_seed_normalize(2147483647) != 1 { ok = false; }
  if shuffle_seed_normalize(1) != 1 { ok = false; }
  if shuffle_next(1) != 48271 { ok = false; }
  if shuffle_next(48271) != 182605794 { ok = false; }
  if shuffle_below(48271, 4) != 3 { ok = false; }
  if shuffle_below(48271, 0) != 0 { ok = false; }
  return assert(ok, "MINSTD LCG: normalization, steps and bounded value");
}

fn t20() -> TestResult {
  let s = split_of(split_indices(10, 6000, 2000));
  let train = split_train_indices(&s);
  let val = split_val_indices(&s);
  let test = split_test_indices(&s);
  var ok = split_bps() == 10000;
  if split_train_len(&s) != 6 { ok = false; }
  if split_val_len(&s) != 2 { ok = false; }
  if split_test_len(&s) != 2 { ok = false; }
  if split_train_at(&s, 0) != 0 { ok = false; }
  if split_train_at(&s, 5) != 5 { ok = false; }
  if split_train_at(&s, 6) != -1 { ok = false; }
  if split_val_at(&s, 0) != 6 { ok = false; }
  if split_val_at(&s, 1) != 7 { ok = false; }
  if split_val_at(&s, 2) != -1 { ok = false; }
  if split_test_at(&s, 0) != 8 { ok = false; }
  if split_test_at(&s, 1) != 9 { ok = false; }
  if split_test_at(&s, 2) != -1 { ok = false; }
  if !ints_equal(&train, &v6(0, 1, 2, 3, 4, 5)) { ok = false; }
  if !ints_equal(&val, &v2(6, 7)) { ok = false; }
  if !ints_equal(&test, &v2(8, 9)) { ok = false; }
  if !streq(split_dump(&s), "split train=[0,1,2,3,4,5] val=[6,7] test=[8,9]") { ok = false; }
  return assert(ok, "split_indices: contiguous basis-point partition and dump");
}

fn t21() -> TestResult {
  let s1 = split_of(split_indices(10, 10000, 0));
  var ok = split_train_len(&s1) == 10;
  if split_val_len(&s1) != 0 { ok = false; }
  if split_test_len(&s1) != 0 { ok = false; }
  let s2 = split_of(split_indices(10, 0, 0));
  if split_train_len(&s2) != 0 { ok = false; }
  if split_test_len(&s2) != 10 { ok = false; }
  if split_test_at(&s2, 0) != 0 { ok = false; }
  let s3 = split_of(split_indices(10, 0, 10000));
  if split_val_len(&s3) != 10 { ok = false; }
  if split_test_len(&s3) != 0 { ok = false; }
  let s4 = split_of(split_indices(3, 5000, 3000));
  if split_train_len(&s4) != 1 { ok = false; }
  if split_val_len(&s4) != 0 { ok = false; }
  if split_test_len(&s4) != 2 { ok = false; }
  if split_test_at(&s4, 0) != 1 { ok = false; }
  let s5 = split_of(split_indices(0, 5000, 5000));
  if split_train_len(&s5) != 0 { ok = false; }
  if split_val_len(&s5) != 0 { ok = false; }
  if split_test_len(&s5) != 0 { ok = false; }
  return assert(ok, "split edges: pure splits, truncation and empty input");
}

fn t22() -> TestResult {
  var ok = split_err(split_indices(-1, 5000, 5000), "data: split sample count must be non-negative");
  if !split_err(split_indices(1000001, 5000, 5000), "data: split sample count exceeds the limit") { ok = false; }
  if !split_err(split_indices(10, -1, 0), "data: split ratios must be non-negative") { ok = false; }
  if !split_err(split_indices(10, 0, -1), "data: split ratios must be non-negative") { ok = false; }
  if !split_err(split_indices(10, 6000, 5000), "data: split ratios must sum to at most 10000") { ok = false; }
  if !split_err(split_indices(10, 10001, 0), "data: split ratios must sum to at most 10000") { ok = false; }
  return assert(ok, "split errors: range, capacity and ratio validation");
}

fn t23() -> TestResult {
  let o = ints_of(shuffle_order(10, 12345));
  let s = split_of(split_shuffled(10, 6000, 2000, 12345));
  let train = split_train_indices(&s);
  let val = split_val_indices(&s);
  let test = split_test_indices(&s);
  var ok = split_train_len(&s) == 6;
  if split_val_len(&s) != 2 { ok = false; }
  if split_test_len(&s) != 2 { ok = false; }
  var expected_train = Vec[Int].new();
  var i = 0;
  while i < 6 {
    let v: Int = o[i];
    expected_train.push(v);
    i = i + 1;
  }
  var expected_val = Vec[Int].new();
  var j = 6;
  while j < 8 {
    let v: Int = o[j];
    expected_val.push(v);
    j = j + 1;
  }
  var expected_test = Vec[Int].new();
  var k = 8;
  while k < 10 {
    let v: Int = o[k];
    expected_test.push(v);
    k = k + 1;
  }
  if !ints_equal(&train, &expected_train) { ok = false; }
  if !ints_equal(&val, &expected_val) { ok = false; }
  if !ints_equal(&test, &expected_test) { ok = false; }
  let s2 = split_of(split_shuffled(10, 6000, 2000, 12345));
  if !streq(split_dump(&s), split_dump(&s2)) { ok = false; }
  var seen = zeros(10);
  var a = 0;
  while a < train.len() {
    let v: Int = train[a];
    seen[v] = 1;
    a = a + 1;
  }
  var b = 0;
  while b < val.len() {
    let v: Int = val[b];
    seen[v] = 1;
    b = b + 1;
  }
  var c = 0;
  while c < test.len() {
    let v: Int = test[c];
    seen[v] = 1;
    c = c + 1;
  }
  var sum = 0;
  var m = 0;
  while m < 10 {
    let v: Int = seen[m];
    sum = sum + v;
    m = m + 1;
  }
  if sum != 10 { ok = false; }
  return assert(ok, "split_shuffled: partition of the deterministic shuffle");
}

fn t24() -> TestResult {
  let d = base();
  let o = ints_of(shuffle_order(4, 7));
  var l = loader_of(loader_from_order(&d, &o, 2, 0));
  var ok = ints_equal(&o, &v4(3, 2, 0, 1));
  let b1 = batch_of(loader_next(&d, &mut l));
  let b2 = batch_of(loader_next(&d, &mut l));
  if batch_size(&b1) != 2 { ok = false; }
  if batch_size(&b2) != 2 { ok = false; }
  if !ints_equal(&batch_indices(&b1), &v2(3, 2)) { ok = false; }
  if !ints_equal(&batch_indices(&b2), &v2(0, 1)) { ok = false; }
  var seen = zeros(4);
  var r = 0;
  while r < batch_size(&b1) {
    let src: Int = int_of(batch_index(&b1, r));
    if src < 0 || src >= 4 {
      ok = false;
    } else {
      let cur: Int = seen[src];
      seen[src] = cur + 1;
    }
    var j = 0;
    while j < batch_width(&b1) {
      if int_of(batch_get(&b1, r, j)) != int_of(dataset_get(&d, src, j)) { ok = false; }
      j = j + 1;
    }
    r = r + 1;
  }
  var r2 = 0;
  while r2 < batch_size(&b2) {
    let src: Int = int_of(batch_index(&b2, r2));
    if src < 0 || src >= 4 {
      ok = false;
    } else {
      let cur: Int = seen[src];
      seen[src] = cur + 1;
    }
    var j = 0;
    while j < batch_width(&b2) {
      if int_of(batch_get(&b2, r2, j)) != int_of(dataset_get(&d, src, j)) { ok = false; }
      j = j + 1;
    }
    r2 = r2 + 1;
  }
  var sum = 0;
  var c = 0;
  while c < 4 {
    let v: Int = seen[c];
    if v != 1 { ok = false; }
    sum = sum + v;
    c = c + 1;
  }
  if sum != 4 { ok = false; }
  if loader_has_next(&l) { ok = false; }
  return assert(ok, "integration: loader over a shuffled order covers every sample once");
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.data conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.data: all tests passed");
  } else {
    io.println("xiom.data: tests failed");
  }
  return failed;
}
