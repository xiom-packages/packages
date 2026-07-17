// probe7 — isolate: annotated Vec literal (no .data), element reads, float scalars
module probe7

extern "C" {
  fn xvk_take_f32_scalar(a: Float32, b: Float32) -> Int;
  fn xvk_take_f64_scalar(a: Float64) -> Int;
}

fn main() -> Int {
  // 1. Float scalars to C
  let ok1 = unsafe { xvk_take_f32_scalar(1.5, 0.25) };
  if ok1 != 1 { return 1; }
  let ok2 = unsafe { xvk_take_f64_scalar(2.75) };
  if ok2 != 1 { return 2; }

  // 2. Annotated Vec[Float32] literal — element reads (no .data)
  let vb: Vec[Float32] = [1.5, 2.5, 3.5];
  let e0: Float32 = vb[0];
  let e1: Float32 = vb[1];
  let e2: Float32 = vb[2];
  if e0 != 1.5 { return 3; }
  if e1 != 2.5 { return 4; }
  if e2 != 3.5 { return 5; }
  if vb.len() != 3 { return 6; }

  // 3. push-built Vec[Float32] element reads
  var pv = Vec[Float32].new();
  pv.push(4.5);
  pv.push(5.5);
  let p0: Float32 = pv[0];
  let p1: Float32 = pv[1];
  if p0 != 4.5 { return 7; }
  if p1 != 5.5 { return 8; }

  // 4. Vec[Int32] literal element reads
  let iv: Vec[Int32] = [10, 20, 30];
  let i0: Int32 = iv[0];
  let i2: Int32 = iv[2];
  if i0 != 10 { return 9; }
  if i2 != 30 { return 10; }

  // 5. Vec[UInt16] literal element reads (index buffer case)
  let uv: Vec[UInt16] = [0, 1, 2];
  let u1: UInt16 = uv[1];
  if u1 != 1 { return 11; }

  return 0;
}
