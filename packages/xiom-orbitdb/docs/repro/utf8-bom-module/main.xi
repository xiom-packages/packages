// Minimal repro: a UTF-8 BOM on a module whose declared module path does not
// match its file name makes the import unresolved (v0.64.8).
module repro.bom_main

use xiom.io;
use repro.bom_impl;

pub fn main() -> Int {
  io.println("v=" + bom_value().to_str());
  return 0;
}
