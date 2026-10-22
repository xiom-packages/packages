// probe_match_result_enum_defect.xi -- minimized compiler-defect probe.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Compiler: v0.64.9 (pinned toolchain).
//
// DEFECT: matching a nested enum variant directly inside a Result pattern
//         (Err(Enum.Variant(..))) miscompiles the match. Every Err arm is
//         guarded by the Result's Err tag (0) instead of descending into the
//         inner enum's discriminant, so the FIRST Err arm always wins. The
//         bound payload is then read from the wrong slot (observed 0).
//
// This probe is expected to FAIL on the affected compiler: `make(2)` returns
// Err(E.B(9)) yet the first Err(E.A(v)) arm is taken. The fix used by
// xiom.http 0.1.10 is a two-level match:
//     match result { Err(e) => match e { E.A(v) => .., E.B(v) => .. } }
// which the compiler lowers correctly.
//
// Run from E:\xiom-packages\packages (expected exit code 1 on v0.64.9):
//   & .\scripts\xiom.ps1 -Stdlib E:\xiom-lang\stdlib --run `
//       packages\xiom-http\docs\probe_match_result_enum_defect.xi
module http_match_result_enum_defect

use xiom.io;
use xiom.convert;

enum E {
  A(x: Int),
  B(y: Int),
}

fn make(tag: Int) -> Result[Int, E] {
  if tag == 1 {
    return Err(E.A(7));
  };
  return Err(E.B(9));
}

pub fn main() -> Int {
  var failures: Int = 0;
  match make(2) {
    Ok(_) => {
      io.println("[FAIL] unexpected Ok");
      failures = failures + 1;
    },
    Err(E.A(v)) => {
      io.println("[BUG] make(2) returned E.B(9) but matched E.A(v=" + convert.to_string(v) + ")");
      failures = failures + 1;
    },
    Err(E.B(v)) => {
      if v == 9 {
        io.println("[OK] make(2) matched E.B(9)");
      } else {
        io.println("[BUG] E.B payload corrupted: " + convert.to_string(v));
        failures = failures + 1;
      };
    },
  };

  // Control: two-level matching on the same values is correct.
  match make(2) {
    Ok(_) => {},
    Err(e) => {
      match e {
        E.A(v) => {
          io.println("[FAIL] control: nested match took E.A(" + convert.to_string(v) + ")");
          failures = failures + 1;
        },
        E.B(v) => {
          if v == 9 {
            io.println("[OK] control: two-level match took E.B(9)");
          } else {
            io.println("[FAIL] control: E.B payload " + convert.to_string(v));
            failures = failures + 1;
          };
        },
      };
    },
  };
  return failures;
}
