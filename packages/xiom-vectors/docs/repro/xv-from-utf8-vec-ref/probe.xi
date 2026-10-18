// Minimal candidate: pass `&Vec[UInt8]` to Str::from_utf8 (stdlib passes the
// Vec BY VALUE). Observe: clang invalid getelementptr, or a silent wrong
// string.
module probe_from_utf8_ref

use xiom.string.slice;

fn main() -> Int {
  var kb = Vec[UInt8].new();
  kb.push(65u8);
  var s = Str::from_utf8(&kb);
  if s == "A" { return 0; }
  return 1;
}
