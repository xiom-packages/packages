// XVC-C-10 repro: `hnsw_decode` with a large-but-legal `m` (pad volume)
// segfaulted while the inline pad loop lived inside decode (revision-pinned;
// see README.md). After the fix (pad step behind `pad_adj_slots` + m/count
// bounds) this probe returns cleanly.
module probe_decode_pad_loop

use xiom.vector.index.hnsw;
use xiom.vectors;
use xiom.io;

fn main() -> Int {
  io.println("=== xv-decode-pad-loop: decode a 12-node graph with m=512 ===");
  var g = hnsw_new(4, 4.0);
  var i: Int = 0;
  while i < 12 {
    var v = Vector.new(3);
    v.set(0, (i % 5) as Float32);
    v.set(1, (i % 3) as Float32);
    v.set(2, ((i * 7) % 5) as Float32);
    hnsw_insert(&mut g, i + 1, v, DistanceMetric.Euclidean);
    i = i + 1;
  }
  var words = hnsw_encode(&g);
  words[1] = 512;      // inflate m (legal range; 512 = AnnParams cap)
  words[2] = 1024;     // inflate the level-0 cap too (max legal = 2 * m; the
                       // P-a codec carries it as the v3 second header word)
  words.push(7);       // trailing junk => decode must return None after the work
  io.println("decode start (pre-fix revisions segfault here)");
  var dec = hnsw_decode(&words);
  io.println("decode returned without crashing");
  match dec {
    Some(_) => { io.println("unexpected Some"); return 1; }
    None => { io.println("decode -> None (correct: trailing junk)"); }
  }
  return 0;
}
