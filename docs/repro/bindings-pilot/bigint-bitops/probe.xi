// B-27 minimal shape -- bitwise ops and integer division on integer values
// >= 2^31 compute wrong results (observed while building xiom.dlss 0.1.0:
// NVSDK_NGX_Result failure codes are 0xBAD00000 | N, and the upstream
// SUCCEED/FAILED macros are bitwise).
//
// Build+run (workdir = this directory, toolchain + XIOM_STDLIB resolved as
// in the bundle README):
//   xiom --run probe.xi
//
// Expected (v0.64.5+ fix): shift20=2989 and_mask=3132620800 div20=2989.
// Observed on v0.64.4 (2026-10-13, 1/1 build): shift20=2987,
// and_mask=3132096512 (0xBAC00000), div20=2987 -- the 0xBAD00000 literal
// loses its 0x0D00000 nibble through these ops.  Controls on the same build:
// 2147483648 >> 20 = 2048, 3000000000 >> 20 = 2861, 3132620800 - 3132620800
// = 0 (comparisons, subtraction and printing are faithful).
//
// Exit 0 = all values correct (bug absent), 1 = bug present.
module bigint_bitops_probe

use xiom.io;

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  if n < 0 { return "-" + i2s(0 - n); }
  var val = n;
  var buf = "";
  while val > 0 {
    let d = val % 10;
    val = val / 10;
    if d == 0 { buf = "0" + buf; }
    elif d == 1 { buf = "1" + buf; }
    elif d == 2 { buf = "2" + buf; }
    elif d == 3 { buf = "3" + buf; }
    elif d == 4 { buf = "4" + buf; }
    elif d == 5 { buf = "5" + buf; }
    elif d == 6 { buf = "6" + buf; }
    elif d == 7 { buf = "7" + buf; }
    elif d == 8 { buf = "8" + buf; }
    elif d == 9 { buf = "9" + buf; }
  }
  return buf;
}

fn main() -> Int {
  let shift20 = 3132620800 >> 20;
  let and_mask = 3132620800 & 4293918720;
  let div20 = 3132620800 / 1048576;
  io.println("shift20=" + i2s(shift20)
    + " and_mask=" + i2s(and_mask)
    + " div20=" + i2s(div20));
  if shift20 == 2989 && and_mask == 3132620800 && div20 == 2989 {
    io.println("B-27: fixed (all three ops correct)");
    return 0;
  }
  io.println("B-27: REPRO (expected shift20=2989 and_mask=3132620800 div20=2989)");
  return 1;
}
