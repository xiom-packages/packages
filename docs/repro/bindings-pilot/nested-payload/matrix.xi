// nested-payload matrix -- localizes which nested-enum payload shapes are
// corrupted on v0.64.4.  Companion to probe.xi (the minimal RED repro).
//
// Observed 2026-10-13 on v0.64.4, this file rebuilt fresh 3x:
//   D, E, B, C, F, A2 -- GREEN (values exact)
//   A -- ACCESS VIOLATION (0xC0000005) 3/3, between the "A ..." header and
//   the first field read (at the second payload extraction / guard).
// probe.xi (same no-scalar nested shape as A2, different module content)
// is RED 4/4 builds (items.len=9): the miscompile is source/build-sensitive
// (B-01 family signature).  matrix.xi shape A is the reliable red artifact.
//
// Run order: controls first, then nested scalar/inverted/Vec, then the
// struct-with-Vec shapes LAST (they can AV on use -- a crash after a
// printed header still marks that shape RED).
//
// Shapes:
//   D  Result[BagFlat]             flat struct payload (control)
//   E  Option[Bag]                 single-level payload (control)
//   B  Result[Option[Int]]         nested, scalar payload
//   C  Option[Result[Bag]]         inverted nesting, struct-with-Vec
//   F  Result[Option[Vec[Int]]]    nested, bare Vec payload
//   A2 Result[Option[BagV]]        nested struct-with-Vec, NO leading scalar
//   A  Result[Option[Bag]]         nested struct-with-Vec + leading Int tag
//
// Pure XIOM; no C source.  Run:
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\matrix.xi

module nested_payload_matrix

use xiom.io;
use xiom.convert;

pub type BagV = {
  items: Vec[Int];
}

pub type Bag = {
  tag: Int;
  items: Vec[Int];
}

pub type BagFlat = {
  has: Bool;
  bag: Bag;
}

fn bagv_new() -> BagV {
  var b = BagV{ items: Vec[Int].new() };
  b.items.push(7);
  b.items.push(9);
  return b;
}

fn bag_new() -> Bag {
  var b = Bag{ tag: 2, items: Vec[Int].new() };
  b.items.push(7);
  b.items.push(9);
  return b;
}

fn d_flat_bag() -> Result[BagFlat, Str] {
  return Ok(BagFlat{ has: true, bag: bag_new() });
}

fn e_opt_bag() -> Option[Bag] {
  return Some(bag_new());
}

fn b_nested_int() -> Result[Option[Int], Str] {
  return Ok(Some(41));
}

fn c_opt_res_bag() -> Option[Result[Bag, Str]] {
  return Some(Ok(bag_new()));
}

fn f_nested_vec() -> Result[Option[Vec[Int]], Str] {
  var v = Vec[Int].new();
  v.push(7);
  v.push(9);
  return Ok(Some(v));
}

fn a2_nested_bagv() -> Result[Option[BagV], Str] {
  return Ok(Some(bagv_new()));
}

fn a_nested_bag() -> Result[Option[Bag], Str] {
  return Ok(Some(bag_new()));
}

fn main() -> Int {
  var bad: Int = 0;
  io.println("=== nested-payload matrix (v0.64.4) ===");

  io.println("D Result[BagFlat] (control):"); io.flush_stdout();
  let d = d_flat_bag();
  if !d.is_ok { io.println("  D err"); bad = bad + 1; }
  else {
    let dout: BagFlat = d.value;
    io.println("  D tag=" + convert.int_to_string(dout.bag.tag) + " items.len=" + convert.int_to_string(dout.bag.items.len()) + " (expect 2 / 2)"); io.flush_stdout();
    if dout.bag.tag != 2 { bad = bad + 1; }
    if dout.bag.items.len() != 2 { bad = bad + 1; }
  }

  io.println("E Option[Bag] (control):"); io.flush_stdout();
  let e = e_opt_bag();
  if !e.is_some { io.println("  E none"); bad = bad + 1; }
  else {
    let ebag: Bag = e.value;
    io.println("  E tag=" + convert.int_to_string(ebag.tag) + " items.len=" + convert.int_to_string(ebag.items.len()) + " (expect 2 / 2)"); io.flush_stdout();
    if ebag.tag != 2 { bad = bad + 1; }
    if ebag.items.len() != 2 { bad = bad + 1; }
  }

  io.println("B Result[Option[Int]]:"); io.flush_stdout();
  let b = b_nested_int();
  if !b.is_ok { io.println("  B err"); bad = bad + 1; }
  else {
    let bo = b.value;
    if !bo.is_some { io.println("  B none"); bad = bad + 1; }
    else {
      io.println("  B value=" + convert.int_to_string(bo.value) + " (expect 41)"); io.flush_stdout();
      if bo.value != 41 { bad = bad + 1; }
    }
  }

  io.println("C Option[Result[Bag]]:"); io.flush_stdout();
  let c = c_opt_res_bag();
  if !c.is_some { io.println("  C none"); bad = bad + 1; }
  else {
    let cr = c.value;
    if !cr.is_ok { io.println("  C err"); bad = bad + 1; }
    else {
      let cbag: Bag = cr.value;
      io.println("  C tag=" + convert.int_to_string(cbag.tag) + " items.len=" + convert.int_to_string(cbag.items.len()) + " (expect 2 / 2)"); io.flush_stdout();
      if cbag.tag != 2 { bad = bad + 1; }
      if cbag.items.len() != 2 { bad = bad + 1; }
    }
  }

  io.println("F Result[Option[Vec[Int]]]:"); io.flush_stdout();
  let f = f_nested_vec();
  if !f.is_ok { io.println("  F err"); bad = bad + 1; }
  else {
    let fo = f.value;
    if !fo.is_some { io.println("  F none"); bad = bad + 1; }
    else {
      let fv: Vec[Int] = fo.value;
      io.println("  F len=" + convert.int_to_string(fv.len()) + " (expect 2)"); io.flush_stdout();
      if fv.len() != 2 { bad = bad + 1; }
    }
  }

  io.println("A2 Result[Option[BagV]] (no leading scalar):"); io.flush_stdout();
  let a2 = a2_nested_bagv();
  if !a2.is_ok { io.println("  A2 err"); bad = bad + 1; }
  else {
    let a2o = a2.value;
    if !a2o.is_some { io.println("  A2 none"); bad = bad + 1; }
    else {
      let a2bag: BagV = a2o.value;
      io.println("  A2 items.len=" + convert.int_to_string(a2bag.items.len()) + " (expect 2)"); io.flush_stdout();
      if a2bag.items.len() != 2 { bad = bad + 1; }
    }
  }

  io.println("A Result[Option[Bag]] (leading Int tag; may AV):"); io.flush_stdout();
  let a = a_nested_bag();
  if !a.is_ok { io.println("  A err"); bad = bad + 1; }
  else {
    let ao = a.value;
    if !ao.is_some { io.println("  A none"); bad = bad + 1; }
    else {
      let bag: Bag = ao.value;
      io.println("  A tag read..."); io.flush_stdout();
      let tag_seen = bag.tag;
      io.println("  A tag=" + convert.int_to_string(tag_seen) + " (expect 2)"); io.flush_stdout();
      if tag_seen != 2 { bad = bad + 1; }
      let len_seen = bag.items.len();
      io.println("  A items.len=" + convert.int_to_string(len_seen) + " (expect 2)"); io.flush_stdout();
      if len_seen != 2 { bad = bad + 1; }
    }
  }

  io.println("failures=" + convert.int_to_string(bad));
  return bad;
}
