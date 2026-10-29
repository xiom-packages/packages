module diag_b4

use xiom.io;
use xiom.transport.sim;
use xiom.string.compare;

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = s.byte_at(i);
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn bytes_to_str(b: &Vec[UInt8]) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < b.len() {
    let x: UInt8 = b[i];
    out.push(x);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn main() -> Int {
  var l = sim_new(99, 10);
  var drop: Vec[Int] = Vec[Int].new();
  drop.push(3);
  var dup: Vec[Int] = Vec[Int].new();
  dup.push(2);
  sim_set_tables(&mut l, &drop, &dup, 2, 1000);
  sim_send_a(&mut l, &bytes_of("k0"));
  sim_send_a(&mut l, &bytes_of("k1"));
  sim_send_a(&mut l, &bytes_of("k2"));
  sim_send_a(&mut l, &bytes_of("k3"));
  let st0 = sim_stats(&l);
  io.println("st0 sent=" + st0.sent.to_str() + " dropped=" + st0.dropped.to_str() + " dup=" + st0.duplicated.to_str() + " displaced=" + st0.displaced.to_str() + " pending=" + st0.pending_a_to_b.to_str());
  sim_advance(&mut l, 10);
  let r1 = sim_recv_b(&mut l);
  io.println("r1 len=" + r1.len().to_str());
  var j = 0;
  while j < r1.len() {
    let p: Vec[UInt8] = r1[j];
    io.println("r1[" + j.to_str() + "]=" + bytes_to_str(&p));
    j = j + 1;
  }
  sim_advance(&mut l, 5000);
  let r2 = sim_recv_b(&mut l);
  io.println("r2 len=" + r2.len().to_str());
  var k0 = 0;
  var k2 = 0;
  var i = 0;
  while i < r2.len() {
    let p: Vec[UInt8] = r2[i];
    let s = bytes_to_str(&p);
    io.println("r2[" + i.to_str() + "]=" + s);
    if streq(s, "k0") { k0 = k0 + 1; }
    if streq(s, "k2") { k2 = k2 + 1; }
    i = i + 1;
  }
  let st1 = sim_stats(&l);
  io.println("st1 delivered=" + st1.delivered.to_str() + " pending=" + st1.pending_a_to_b.to_str() + " k0=" + k0.to_str() + " k2=" + k2.to_str());
  return 0;
}
