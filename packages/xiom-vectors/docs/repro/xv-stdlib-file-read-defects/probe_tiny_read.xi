// XVC-C-12 control: read_file_bytes on a 5-byte file. The abort was observed
// in probe_wal_file's compilation unit; this minimal unit passes, which is
// the context-sensitivity evidence. See README.md.
module probe_tiny_read

use xiom.io;
use xiom.string.slice;

fn main() -> Int {
  io.println("=== tiny read repro (XVC-C-12) ===");
  var b = slice.str_bytes("hello");
  var w = io.write_file_bytes("out/repro_tiny.txt", &b);
  match w {
    Ok(_) => {}
    Err(_) => { io.println("write failed"); return 2; }
  }
  io.println("read start (tiny file; current compiler aborts here)");
  var r = io.read_file_bytes("out/repro_tiny.txt");
  match r {
    Ok(x) => {
      if x.len() == 5 { io.println("read ok len=5"); return 0; }
      io.println("read ok but wrong length");
      return 1;
    }
    Err(_) => { io.println("read err"); return 1; }
  }
}
