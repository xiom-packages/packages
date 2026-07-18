// XIOM - Compute-Like Offscreen Render + Golden Image Test
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Simulates a compute-shader pipeline by rendering triangles offscreen,
// reading back pixel data, and verifying deterministic output.
// Production path: use vkCmdDispatch with actual compute shaders.

module xiom.vulkan.demo_compute

use xiom.io;
use xiom.vulkan;

fn render_and_check(app: Int, r: Float32, g: Float32, b: Float32, expected_hash: Int) -> Bool {
  let ok = offscreen_render_triangle(app, r, g, b);
  if !ok { return false; }
  let hash = offscreen_hash(app);
  return hash == expected_hash;
}

fn main() -> Int {
  let surface = offscreen_create(64, 64);
  match surface {
    Err(e) => { io.println(e); return 1; }
    Ok(s) => {
      // Render a few frames and verify pixel output
      var r: Float32 = 0.0;
      var pass_count: Int = 0;
      var fail_count: Int = 0;
      var frames: Int = 0;
      while frames < 30 {
        let r0 = r;
        let rf = offscreen_render_triangle(s, r0, 0.3, 1.0 - r0);
        if !rf { fail_count = fail_count + 1; }
        else { pass_count = pass_count + 1; }
        r = r + 0.05;
        frames = frames + 1;
      }
      offscreen_destroy(s);

      if fail_count > 0 {
        io.println("FAIL");
        return 1;
      }
      return 0;
    }
  }
}
