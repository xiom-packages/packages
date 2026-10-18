// B-29 witness (corrected 2026-10-18): big-int bitops >= 2^31 are EXACT;
// the original B-27/B-29 probe compared ops on 3132620800 (0xBAB80000)
// against expectations derived from 3134193664 (0xBAD00000) -- a probe
// defect, confirmed by compiler triage (m335) and this corrected run.
//
// Build+run:  xiom --run probe.xi      (exit 0 = all exact)
//
// Verified values (v0.64.7, and exact on v0.64.5 per m335):
//   3134193664 (0xBAD00000): >>20 = 2989, &0xFFF00000 = 3134193664, /2^20 = 2989
//   3132620800 (0xBAB80000): >>20 = 2987, &0xFFF00000 = 3132096512 (0xBAB00000),
//                            /2^20 = 2987
//   0xBAD00000 literal == 3134193664 decimal (parity exact)
// Status: B-29 CLOSED as not-a-compiler-defect; the ngx boundary-arithmetic
// workaround is a retirement candidate at the next xiom.dlss/nis touch.
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
  let intended = 3134193664;
  let hexv = 0xBAD00000;
  let shift20 = intended >> 20;
  let and_mask = intended & 4293918720;
  let div20 = intended / 1048576;

  let other = 3132620800;
  let o_shift20 = other >> 20;
  let o_and_mask = other & 4293918720;
  let o_div20 = other / 1048576;

  io.println("0xBAD00000: shift20=" + i2s(shift20) + " and_mask=" + i2s(and_mask) + " div20=" + i2s(div20));
  io.println("control 0xBAB80000: shift20=" + i2s(o_shift20) + " and_mask=" + i2s(o_and_mask) + " div20=" + i2s(o_div20));

  let ok = intended == hexv
    && shift20 == 2989 && and_mask == 3134193664 && div20 == 2989
    && o_shift20 == 2987 && o_and_mask == 3132096512 && o_div20 == 2987;
  if ok {
    io.println("B-29: exact (NOT-A-COMPILER-DEFECT)");
    return 0;
  }
  io.println("B-29: mismatch");
  return 1;
}
