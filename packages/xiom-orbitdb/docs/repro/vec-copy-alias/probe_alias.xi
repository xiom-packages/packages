// C-ORBIT-09 repro: element assignment through a copied Vec handle writes
// through to the SOURCE buffer, while push/pop copy-on-write.
//
// The ORBITDB M3 snapshot-pin COW hit this inside the node arena: copying a
// B-tree node to a fresh slot by plain assignment left the new slot sharing
// keys/values/children buffers with the pinned original, and the in-place
// `keys[i] = keys[i+1]` mutations of an update corrupted the pinned view
// (suite failures: snapshot reads returned the post-write values).
module orbitdb_repro_vec_alias

use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Flat Vec: no use-after-move involved.
  var src = Vec[Int].new();
  src.push(1);
  src.push(2);
  var copy = src;
  copy[0] = 99;
  io.println("flat elem-assign: src[0]=" + convert.int_to_string(src[0])
    + " copy[0]=" + convert.int_to_string(copy[0]));
  copy.push(3);
  io.println("flat push: src.len=" + convert.int_to_string(src.len())
    + " copy.len=" + convert.int_to_string(copy.len()));

  // Arena analogue (the engine shape): two LIVE handles into one arena.
  var arena = Vec[Vec[Int]].new();
  var a = Vec[Int].new();
  a.push(1);
  a.push(2);
  arena.push(a);
  var extracted = arena[0];
  arena.push(extracted);          // a "fresh slot" that must own its storage
  var work = arena[1];
  work[0] = 99;                   // engine: node.key_shifts on the copy
  io.println("arena elem-assign: src[0]=" + convert.int_to_string(arena[0][0])
    + " copy[0]=" + convert.int_to_string(arena[1][0]));
  work.pop();                     // structural ops DO copy-on-write
  io.println("arena pop: src.len=" + convert.int_to_string(arena[0].len())
    + " store-copy.len=" + convert.int_to_string(arena[1].len())
    + " local.len=" + convert.int_to_string(work.len()));
  return 0;
}
