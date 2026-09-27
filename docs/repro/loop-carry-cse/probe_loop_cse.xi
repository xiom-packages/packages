// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Loop-carried CSE battery, reduced from the original `xiom.amqp` stack
// decoder. The pre-fix edit (recovered from the porting session) contains:
//
//     let sub_len = _read_u32(data, pos);
//     if sub_len > cur_end - pos - 4 { return _err_int("amqp: bad table"); }
//     _tree_push(t, 7, key, 0, 0, Vec[UInt8].new());
//     ends.push(pos + 4 + sub_len);
//     kinds.push(7);
//     sp = sp + 1;
//     pos = pos + 4;
//
// v0.61.3 reused the previous push's value for `pos + 4 + sub_len` on the
// second container (any two containers in one parent failed); binding the
// expression to a local first was the reported workaround, and the committed
// workaround is a recursive per-container function.
//
// This probe tries flat and per-container reductions of that shape; each
// value is compared against the hand-computed truth. `bad` counts failures.
// Exit 0 = all correct (possible: the reduction may not trigger the shared
// expression path even when the original did -- see README).
module probe_loop_cse

use xiom.convert;
use xiom.io;

fn _next_len(src: &Vec[Int], i: Int) -> Int {
  return src[i];
}

// Read a little-endian u32 at p (callers ensure p + 3 in range).
fn _read_u32(data: &Vec[UInt8], p: Int) -> Int {
  let b0: Int = data[p];
  let b1: Int = data[p + 1];
  let b2: Int = data[p + 2];
  let b3: Int = data[p + 3];
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn main() -> Int {
  var bad = 0;

  let lens = Vec[Int].new();
  lens.push(2);
  lens.push(3);

  // V1: flat loop, expression reused for the push and the advance
  let ends1 = Vec[Int].new();
  var pos1 = 0;
  var i = 0;
  while i < 2 {
    let sub_len = _next_len(&lens, i);
    ends1.push(pos1 + 4 + sub_len);
    pos1 = pos1 + 4 + sub_len;
    i = i + 1;
  }
  io.println("v1 ends=" + int_to_string(ends1[0]) + "," + int_to_string(ends1[1]) + " pos=" + int_to_string(pos1));
  if (ends1[0] != 6) { bad = bad + 1; }
  if (ends1[1] != 13) { bad = bad + 1; }
  if (pos1 != 13) { bad = bad + 1; }

  // V2: per-container reduction. Buffer:
  //   [0..3] root length = 15                       root end = 19
  //   [4] tag 7, [5..8] len 2, [9..10] payload AA AA      child1 end = 11
  //   [11] tag 7, [12..15] len 3, [16..18] payload BB*3   child2 end = 19
  let data = Vec[UInt8].new();
  data.push(15); data.push(0); data.push(0); data.push(0);
  data.push(7); data.push(2); data.push(0); data.push(0); data.push(0); data.push(170); data.push(170);
  data.push(7); data.push(3); data.push(0); data.push(0); data.push(0); data.push(187); data.push(187); data.push(187);

  let child_ends = Vec[Int].new();
  var pos = 4;
  var round = 0;
  while round < 2 {
    let tag: Int = data[pos];
    if tag != 7 {
      io.println("v2 tag=" + int_to_string(tag));
      bad = bad + 1;
      round = 2;
    } else {
      let sub_len = _read_u32(&data, pos + 1);
      child_ends.push((pos + 1) + 4 + sub_len); // the exact expression
      pos = (pos + 1) + 4 + sub_len;            // skip the child payload
      round = round + 1;
    }
  }
  io.println("v2 child_ends=" + int_to_string(child_ends[0]) + "," + int_to_string(child_ends[1]) + " pos=" + int_to_string(pos));
  if (child_ends[0] != 11) { bad = bad + 1; }
  if (child_ends[1] != 19) { bad = bad + 1; }
  if (pos != 19) { bad = bad + 1; }

  // V3: nested loops -- outer containers, inner entries, parent end reused
  let outer = Vec[Int].new();
  var op = 0;
  var oi = 0;
  while oi < 2 {
    let olen = _next_len(&lens, oi);
    let oend = op + 4 + olen;
    var ip = op + 4;
    var acc = 0;
    while ip < oend {
      acc = acc + ip;
      ip = ip + 1;
    }
    outer.push(oend);
    op = op + 4 + olen;
    oi = oi + 1;
  }
  io.println("v3 outer=" + int_to_string(outer[0]) + "," + int_to_string(outer[1]) + " op=" + int_to_string(op));
  if (outer[0] != 6) { bad = bad + 1; }
  if (outer[1] != 13) { bad = bad + 1; }
  if (op != 13) { bad = bad + 1; }

  io.println("bad=" + int_to_string(bad));
  return bad;
}
