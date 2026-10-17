module c_probe_xiomprobe

use d_mod_xiomprobe;

fn main() -> Int {
  var hs = Vec[d_mod_xiomprobe.Handle].new();
  hs.push(1);
  let n = d_mod_xiomprobe.take(&hs);
  return n;
}
