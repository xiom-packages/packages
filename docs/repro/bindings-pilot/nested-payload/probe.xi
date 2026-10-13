// nested-payload probe -- enum payload nested in an enum payload corrupts a
// struct-with-Vec value on v0.64.4.
//
// Shape: a function returns `Result[Option[Bag], Str]` where `Bag` is a
// struct containing a `Vec[Int]`.  Extracting the value (`r.value` then
// `opt.value`) yields a `Bag` whose `items` length reads as a pointer-like
// garbage value (observed 140702023260877 / 140700400781437 across builds)
// instead of 2; using the corrupted value (indexing / cloning the Vec)
// crashes with 0xC0000005.
//
// Controls on the same build:
//   * flat  `Result[BagOutcome]` (struct payload, Bool + Bag)  -> GREEN
//   * single-level `Option[Bag]` return                        -> GREEN
//
// Expected output on v0.64.4: nested line reads a huge bogus length
// (RED), both controls read 2 (GREEN); exit code 1.
//
// Pure XIOM -- no C source, no DLL.
// Run:
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi

module nested_payload_probe

use xiom.io;
use xiom.convert;

pub type Bag = {
  items: Vec[Int];
}

pub type BagOutcome = {
  has: Bool;
  bag: Bag;
}

fn bag_new() -> Bag {
  var b = Bag{ items: Vec[Int].new() };
  b.items.push(7);
  b.items.push(9);
  return b;
}

// Nested shape (RED): enum payload inside enum payload.
fn nested_ok() -> Result[Option[Bag], Str] {
  return Ok(Some(bag_new()));
}

// Flat control (GREEN): plain struct payload.
fn flat_ok() -> Result[BagOutcome, Str] {
  return Ok(BagOutcome{ has: true, bag: bag_new() });
}

// Single-level control (GREEN): Option payload, not nested.
fn opt_ok() -> Option[Bag] {
  return Some(bag_new());
}

fn main() -> Int {
  var bad: Int = 0;
  io.println("=== nested-payload probe (v0.64.4) ===");
  io.flush_stdout();

  let r = nested_ok();
  if !r.is_ok {
    io.println("nested Result[Option[Bag]]: Err (unexpected)");
    bad = bad + 1;
  } else {
    let opt = r.value;
    if !opt.is_some {
      io.println("nested Result[Option[Bag]]: None (unexpected)");
      bad = bad + 1;
    } else {
      let bag: Bag = opt.value;
      let n = bag.items.len();
      io.println("nested Result[Option[Bag]]: items.len=" + convert.int_to_string(n) + " (expected 2)");
      if n != 2 { bad = bad + 1; }
    }
  }
  io.flush_stdout();

  let f = flat_ok();
  if !f.is_ok {
    io.println("flat Result[BagOutcome]: Err (unexpected)");
    bad = bad + 1;
  } else {
    let out: BagOutcome = f.value;
    let nf = out.bag.items.len();
    io.println("flat Result[BagOutcome]: items.len=" + convert.int_to_string(nf) + " (expected 2)");
    if nf != 2 { bad = bad + 1; }
  }
  io.flush_stdout();

  let o = opt_ok();
  if !o.is_some {
    io.println("single-level Option[Bag]: None (unexpected)");
    bad = bad + 1;
  } else {
    let bag2: Bag = o.value;
    let no = bag2.items.len();
    io.println("single-level Option[Bag]: items.len=" + convert.int_to_string(no) + " (expected 2)");
    if no != 2 { bad = bad + 1; }
  }
  io.flush_stdout();

  io.println("failures=" + convert.int_to_string(bad));
  return bad;
}
