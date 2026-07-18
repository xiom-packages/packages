// XIOM — Model Field Demo (Vec-based, v0.46-validated FFI)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.vulkan.demo_models

use xiom.io;
use xiom.math;
use xiom.vulkan;

pub type ModelInstance = {
  px: Float32;
  py: Float32;
  pz: Float32;
  rx: Float32;
  ry: Float32;
  rz: Float32;
  scale: Float32;
  r: Float32;
  g: Float32;
  b: Float32;
}

fn draw_model(app: Int, model: ModelInstance, t: Float32) {
  draw_cube_3d_at(app, t + model.ry, model.px, model.py, model.pz, model.scale);
}

fn main() -> Int {
  let app = create_app("XIOM Vulkan - Model Field", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      var models = Vec[ModelInstance].new();
      var mi: Int = 0;
      while mi < 20 {
        let angle = (mi as Float32) / 20.0 * 6.28318;
        let radius = 1.5 + ((mi % 3) as Float32) * 0.5;
        let inst = ModelInstance{
          px: (math.cos(angle as Float64) * radius as Float64) as Float32;
          py: ((mi - 10) as Float32) * 0.25;
          pz: (math.sin(angle as Float64) * radius as Float64) as Float32;
          rx: 0.0;
          ry: (mi as Float32) * 0.3;
          rz: 0.0;
          scale: 0.15 + (mi as Float32) * 0.01;
          r: ((mi % 5) as Float32) * 0.2;
          g: (((mi + 2) % 5) as Float32) * 0.2;
          b: (((mi + 4) % 5) as Float32) * 0.2;
        };
        models.push(inst);
        mi = mi + 1;
      }

      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now() as Float32;
          set_clear_color(a, 0.01, 0.01, 0.04);
          var mi2: Int = 0;
          while mi2 < 20 {
            draw_model(a, models[mi2], t);
            mi2 = mi2 + 1;
          }
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: begin_frame failed: " + last_error());
          break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
