// XVC-C-11 control: io.read_file content on an 11-byte file. The content loss
// was observed in probe_wal_file's compilation unit; this minimal unit
// passes, which is the context-sensitivity evidence. See README.md.
module probe_str_content

use xiom.io;
use xiom.string.slice;

fn main() -> Int {
  io.println("=== Str content repro (XVC-C-11) ===");
  var b = slice.str_bytes("hello world");
  var w = io.write_file_bytes("out/repro_str.txt", &b);
  match w {
    Ok(_) => {}
    Err(_) => { io.println("write failed"); return 2; }
  }
  var r = io.read_file("out/repro_str.txt");
  match r {
    Ok(s) => {
      var sb = slice.str_bytes(s);
      if sb.len() == 11 {
        io.println("str content ok len=11");
        return 0;
      }
      io.println("str content WRONG: expected 11 bytes, got a different length");
      return 1;
    }
    Err(_) => { io.println("read_file err"); return 1; }
  }
}
