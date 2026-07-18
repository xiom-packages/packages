// XIOM — Sprite Field Demo (Vec-based, v0.46-validated FFI)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.vulkan.demo_sprites

use xiom.io;
use xiom.math;
use xiom.vulkan;

pub type Sprite = {
  x: Float32;
  y: Float32;
  size: Float32;
  speed: Float32;
  phase: Float32;
  r: Float32;
  g: Float32;
  b: Float32;
}

fn draw_sprite(app: Int, sprite: Sprite, t: Float32) {
  let cx = sprite.x + (math.sin((t + sprite.phase) as Float64) as Float32) * 0.2;
  let cy = sprite.y + (math.cos((t + sprite.phase) as Float64) as Float32) * 0.2;
  let sz = sprite.size;
  draw_quad_2d(app, cx, cy, sz, sz, sprite.r, sprite.g, sprite.b);
}

fn main() -> Int {
  let app = create_app("XIOM Vulkan - Sprite Field", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      var sprites = Vec[Sprite].new();
      var si: Int = 0;
      while si < 50 {
        let row = (si / 10) as Float32;
        let col = (si % 10) as Float32;
        sprites.push(Sprite{
          x: (col - 5.0) * 0.18,
          y: (row - 2.5) * 0.3,
          size: 0.03 + (si as Float32) * 0.001,
          speed: 0.5 + (si as Float32) * 0.1,
          phase: (si as Float32) * 0.628,
          r: ((si % 3) as Float32) * 0.4 + 0.2,
          g: (((si + 1) % 3) as Float32) * 0.4 + 0.2,
          b: (((si + 2) % 3) as Float32) * 0.4 + 0.2,
        });
        si = si + 1;
      }

      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now() as Float32;
          set_clear_color(a, 0.01, 0.01, 0.03);
          var sj: Int = 0;
          while sj < 50 {
            draw_sprite(a, sprites[sj], t);
            sj = sj + 1;
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
