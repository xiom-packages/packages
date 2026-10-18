// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Repro: XVC-C-15 -- literal stores into Vec[Float32] slots skip numeric
// narrowing (Float64 literal stores its raw low 32 bits; Int literal
// stores its raw bits as an f32 pattern). Found 2026-10-11 during the Q-a
// quantization slice (`probe_quantization`, constant-dimension check).
//
// Expected (correct) values are asserted; exit = failed expectations
// (0 when fixed). On the pinned revision the literal writes corrupt and
// the control shapes (variable / push) stay correct.

module xiom.vector.repro_f32_slot_literal

use xiom.io;
use xiom.convert;
use xiom.vectors;

fn f32str(x: Float32) -> Str {
  return convert.float_to_string(x as Float64);
}

fn main() -> Int {
  var fails: Int = 0;

  // A: Float64 literal into a Vec[Float32] slot (expect 7.0).
  var a = Vec[Float32].new();
  a.push(0.5); a.push(0.5); a.push(0.5);
  a[1] = 7.0;
  if a[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] A f64 literal -> Vec[Float32] slot: a[1]=" + f32str(a[1]));
  } else {
    io.println("  [ok] A f64 literal -> Vec[Float32] slot");
  }

  // B: Int literal into a Vec[Float32] slot (expect 7.0).
  var b = Vec[Float32].new();
  b.push(0.5); b.push(0.5); b.push(0.5);
  b[1] = 7;
  if b[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] B int literal -> Vec[Float32] slot: b[1]=" + f32str(b[1]));
  } else {
    io.println("  [ok] B int literal -> Vec[Float32] slot");
  }

  // C: Float32 VARIABLE into a Vec[Float32] slot (control: expect 7.0).
  var c = Vec[Float32].new();
  c.push(0.5); c.push(0.5); c.push(0.5);
  var cval: Float32 = 7.0;
  c[1] = cval;
  if c[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] C f32 variable -> Vec[Float32] slot: c[1]=" + f32str(c[1]));
  } else {
    io.println("  [ok] C f32 variable -> Vec[Float32] slot (control)");
  }

  // E: Float64 literal into a struct Vec[Float32] field (expect 7.0).
  var e = Vector.new(3);
  e.data[0] = 0.5 as Float32;
  e.data[1] = 0.5 as Float32;
  e.data[2] = 0.5 as Float32;
  e.data[1] = 7.0;
  if e.data[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] E f64 literal -> Vector.data slot: e.data[1]=" + f32str(e.data[1]));
  } else {
    io.println("  [ok] E f64 literal -> Vector.data slot");
  }

  // F: push(Float64 literal) (control: expect 7.0).
  var f = Vec[Float32].new();
  f.push(0.5);
  f.push(7.0);
  if f[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] F f64 literal -> push: f[1]=" + f32str(f[1]));
  } else {
    io.println("  [ok] F f64 literal -> push (control)");
  }

  // G: Float64 literal into a Vec[Float64] slot (control: expect 7.0).
  var g = Vec[Float64].new();
  g.push(0.5);
  g.push(0.5);
  g[1] = 7.0;
  if g[1] != 7.0 {
    fails = fails + 1;
    io.println("  [CORRUPT] G f64 literal -> Vec[Float64] slot: g[1]=" + convert.float_to_string(g[1]));
  } else {
    io.println("  [ok] G f64 literal -> Vec[Float64] slot (control)");
  }

  io.println("repro_f32_slot_literal: " + convert.int_to_string(fails) + " corrupted shapes");
  return fails;
}
