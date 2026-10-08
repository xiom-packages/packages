// XIOM -- xiom.glfw loader demo
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Run from the package directory:  xiom --run examples/demo_glfw.xi
// Prints SKIP when glfw3.dll is not on the loader search path.

module glfw_demo

use xiom.io;
use xiom.convert;
use xiom.glfw;

fn main() -> Int {
  io.println("=== xiom.glfw demo (dynamic loader) ===");
  let l = glfw_load();
  if !l.is_ok {
    io.println("GLFW unavailable (kind " + to_string(l.error.kind) + "): " + l.error.message);
    io.println("SKIP: install GLFW 3.4 or add its directory to PATH.");
    return 0;
  }
  let lib: GlfwLibrary = l.value;
  let v = glfw_get_version(&lib);
  io.println("GLFW version: " + to_string(v / 10000) + "." + to_string((v % 10000) / 100) + "." + to_string(v % 100));
  io.println("build: " + glfw_get_version_string(&lib));

  if !glfw_init(&lib) {
    io.println("glfwInit failed (headless?): " + glfw_last_error(&lib));
    let cl0 = glfw_close(&lib);
    return 0;
  }
  let t0 = glfw_get_time(&lib);
  io.println("timer: " + to_string(t0 as Int) + "s since init");
  glfw_terminate(&lib);
  let cl = glfw_close(&lib);
  if cl.is_ok { io.println("closed cleanly"); }
  return 0;
}
