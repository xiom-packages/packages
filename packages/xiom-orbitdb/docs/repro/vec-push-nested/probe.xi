// C-ORBIT-05 repro bundle (v0.64.1, Windows + WSL):
// A nested loop over `Vec[Page]` (a struct with Vec fields) ABORTS with an
// access violation (exit 0xC0000005) when the outer loop also pushes an
// element into another `Vec[Page]`.
//
//   A (control): nested loop over Vec[Int] + push      -> green
//   B (control): single loop over Vec[Page] + push     -> green
//   C (control): nested loop over Vec[Page], no push   -> green
//   D (bug):     nested loop over Vec[Page] + push     -> CRASH before print
//
// Each variant writes a marker before running; the last marker names the
// crashing variant (stdout is lost on abort).
//
// Run: xiom --run docs/repro/vec-push-nested/probe.xi
module orbitdb_repro_vec_push_nested

use xiom.io;
use xiom.convert;
use xiom.db.storage.page;

fn mark(name: Str) {
  let _ = io.write_file("vec-push-nested.mark", name);
}

fn build(n: Int) -> Vec[Page] {
  var all = Vec[Page].new();
  var i = 0;
  while i < n {
    var d = Vec[Int].new();
    d.push(i & 0xFF);
    all.push(Page.new(i, d, page_compute_checksum(&d)));
    i = i + 1;
  }
  return all;
}

fn main() -> Int {
  let n = 418;

  // A (control, safe): nested loop over Vec[Int], push ints.
  mark("A");
  var ints = Vec[Int].new();
  var i = 0;
  while i < n {
    ints.push(i);
    i = i + 1;
  }
  var cout = Vec[Int].new();
  var k = 0;
  while k < ints.len() {
    var sup = false;
    var j = k + 1;
    while j < ints.len() && !sup {
      if ints[j] == ints[k] { sup = true; }
      j = j + 1;
    }
    if !sup { cout.push(ints[k]); }
    k = k + 1;
  }
  io.println("A ok out=" + convert.int_to_string(cout.len()));

  // B (control, safe): single loop push over Vec[Page].
  mark("B");
  let all = build(n);
  var out1 = Vec[Page].new();
  var m = 0;
  while m < all.len() {
    out1.push(all[m]);
    m = m + 1;
  }
  io.println("B ok out=" + convert.int_to_string(out1.len()));

  // C (control, safe): nested loop over Vec[Page], no push.
  mark("C");
  var hits = 0;
  var k2 = 0;
  while k2 < all.len() {
    var sup2 = false;
    var j2 = k2 + 1;
    while j2 < all.len() && !sup2 {
      if all[j2].id == all[k2].id { sup2 = true; }
      j2 = j2 + 1;
    }
    if !sup2 { hits = hits + 1; }
    k2 = k2 + 1;
  }
  io.println("C ok out=" + convert.int_to_string(hits));

  // D (bug): nested loop over Vec[Page] + push into another Vec[Page].
  mark("D-crashing");
  var out2 = Vec[Page].new();
  var k3 = 0;
  while k3 < all.len() {
    var sup3 = false;
    var j3 = k3 + 1;
    while j3 < all.len() && !sup3 {
      if all[j3].id == all[k3].id { sup3 = true; }
      j3 = j3 + 1;
    }
    if !sup3 { out2.push(all[k3]); }
    k3 = k3 + 1;
  }
  io.println("D ok out=" + convert.int_to_string(out2.len()));
  mark("done");
  return 0;
}
