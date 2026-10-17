// XIOM ORBITDB -- C-ORBIT-08 repro A: a tuple CONTAINING AN ENUM member
// (`(Color, Int)`) inside a Result miscompiles on v0.64.3.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Compiler warning (v0.64.3): "unknown type 'Tuple__Color__Int' -- defaulting
// to i64. This may produce incorrect code."
// Expected: n=5 custom=5. Observed: the Ok arm never runs (no output), or
// garbage values -- depending on call-site context.

module repro_enum_tuple

use xiom.io;
use xiom.convert;

pub type Color = enum { Red, Blue, Custom(n: Int) }

fn pick(c: Color) -> Result[(Color, Int), Int] {
  match c {
    Red => { return Ok((Color.Red, 1)); }
    Blue => { return Ok((Color.Blue, 2)); }
    Custom(n) => { return Ok((Color.Custom(n), n + 3)); }
  }
}

fn main() -> Int {
  let r = pick(Color.Custom(5));
  match r {
    Err(_) => { io.println("repro A: Err (wrong)"); }
    Ok(pair) => {
      let c = pair.0;
      let n = pair.1;
      io.println("repro A: n=" + convert.int_to_string(n));
      match c {
        Red => { io.println("repro A: red"); }
        Blue => { io.println("repro A: blue"); }
        Custom(m) => { io.println("repro A: custom=" + convert.int_to_string(m)); }
      }
    }
  }
  io.println("repro A: done");
  return 0;
}
