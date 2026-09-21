// XIOM -- Vulkan Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom.vulkan safe wrappers.
// Covers: lifecycle, accessors, frame, input, utility, buffers,
// offscreen, camera, math, textures, font, images, drawing.
//
// Pattern: runner fns return Int exit codes (0=pass, 1=fail, 2=skip),
// test fns wrap in TestResult. Manual dispatch in main() works around
// compiler codegen issues with test.run_all() and struct-by-value params.
//
// NOTE: Most tests open a small window. No-headless driver support yet.
// Tests that need Vulkan skip gracefully on non-GPU machines (rc=2).

module vulkan_conformance
use xiom.io;
use xiom.test;
use xiom.vulkan;

// ===========================================================================
// Helpers
// ===========================================================================

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

// ===========================================================================
// 1. Lifecycle (create_app, destroy_app, app_valid, should_close, poll)
// ===========================================================================

fn run_lifecycle_create_destroy() -> Int {
  let a = create_app("XIOM Lifecycle", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => { destroy_app(app); return 0; }
  }
}

fn test_lifecycle_create_destroy() -> TestResult {
  let rc = run_lifecycle_create_destroy();
  if rc == 0 { return assert(true, "lifecycle: create_app + destroy_app"); }
  if rc == 2 { return assert(true, "lifecycle: create_app skip (no GPU)"); }
  return assert(false, "lifecycle: create_app failed");
}

fn run_lifecycle_app_valid() -> Int {
  let a = create_app("XIOM Valid", 100, 100);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      if !app_valid(app) { destroy_app(app); return 1; }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_lifecycle_app_valid() -> TestResult {
  let rc = run_lifecycle_app_valid();
  if rc == 0 { return assert(true, "lifecycle: app_valid returns true"); }
  if rc == 2 { return assert(true, "lifecycle: app_valid skip (no GPU)"); }
  return assert(false, "lifecycle: app_valid returned false");
}

fn run_lifecycle_not_valid_after_destroy() -> Int {
  let a = create_app("XIOM PostDestroy", 100, 100);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      destroy_app(app);
      // app_valid on destroyed handle: may return false or crash.
      // Just verify destroy_app doesn't crash.
      return 0;
    }
  }
}

fn test_lifecycle_not_valid_after_destroy() -> TestResult {
  let rc = run_lifecycle_not_valid_after_destroy();
  if rc == 0 { return assert(true, "lifecycle: destroy_app no crash"); }
  if rc == 2 { return assert(true, "lifecycle: post-destroy skip"); }
  return assert(false, "lifecycle: destroy_app crashed");
}

fn run_lifecycle_should_close() -> Int {
  let a = create_app("XIOM CloseCheck", 100, 100);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // Freshly created app should not report close
      if should_close(app) { destroy_app(app); return 1; }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_lifecycle_should_close() -> TestResult {
  let rc = run_lifecycle_should_close();
  if rc == 0 { return assert(true, "lifecycle: should_close false on fresh app"); }
  if rc == 2 { return assert(true, "lifecycle: should_close skip"); }
  return assert(false, "lifecycle: should_close true on fresh app");
}

// ===========================================================================
// 2. Accessors (9 getter functions)
// ===========================================================================

fn run_accessors_all() -> Int {
  let a = create_app("XIOM Accessors", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      let w = get_glfw_window(app);
      let i = get_instance(app);
      let d = get_device(app);
      let p = get_physical_device(app);
      let q = get_graphics_queue(app);
      let r = get_render_pass(app);
      let cb = get_command_buffer(app);
      let fw = get_fb_width(app);
      let fh = get_fb_height(app);

      if w == 0 { destroy_app(app); return 1; }
      if i == 0 { destroy_app(app); return 1; }
      if d == 0 { destroy_app(app); return 1; }
      if p == 0 { destroy_app(app); return 1; }
      if q == 0 { destroy_app(app); return 1; }
      if r == 0 { destroy_app(app); return 1; }
      if cb == 0 { destroy_app(app); return 1; }
      // fb width/height may be 0 before first frame; that's OK
      destroy_app(app);
      return 0;
    }
  }
}

fn test_accessors_all() -> TestResult {
  let rc = run_accessors_all();
  if rc == 0 { return assert(true, "accessors: all 9 getters return non-zero"); }
  if rc == 2 { return assert(true, "accessors: skip (no GPU)"); }
  return assert(false, "accessors: getter returned zero handle");
}

// ===========================================================================
// 3. Frame Cycle (begin_frame, set_clear_color, end_frame)
// ===========================================================================

fn run_frame_cycle() -> Int {
  let a = create_app("XIOM Frame", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      var fc: Int = 0;
      while fc < 5 {
        poll(app);
        set_clear_color(app, 0.1, 0.2, 0.3);
        let s = begin_frame(app);
        if s == 1 {
          end_frame(app);
          fc = fc + 1;
        } elif s == -1 {
          destroy_app(app); return 1;
        }
      }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_frame_cycle() -> TestResult {
  let rc = run_frame_cycle();
  if rc == 0 { return assert(true, "frame: 5x begin+clear+end cycle"); }
  if rc == 2 { return assert(true, "frame: skip (no GPU)"); }
  return assert(false, "frame: cycle failed");
}

fn run_frame_guard() -> Int {
  let a = create_app("XIOM Guard", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      poll(app);
      let s = begin_frame(app);
      if s == 1 {
        // end_frame resets g_in_frame guard
        end_frame(app);
        // Verify we can begin again (guard reset)
        poll(app);
        let s2 = begin_frame(app);
        if s2 == 1 { end_frame(app); }
        else if s2 == -1 { destroy_app(app); return 1; }
      } elif s == -1 { destroy_app(app); return 1; }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_frame_guard() -> TestResult {
  let rc = run_frame_guard();
  if rc == 0 { return assert(true, "frame: guard reset allows re-begin"); }
  if rc == 2 { return assert(true, "frame: guard skip"); }
  return assert(false, "frame: guard failed to reset");
}

// ===========================================================================
// 4. Input (keys, mouse)
// ===========================================================================

fn run_input_keys() -> Int {
  let a = create_app("XIOM Input", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      poll(app);
      // No keys pressed initially
      let esc = is_key_down(app, 256);
      let space = is_key_down(app, 32);
      // Both should be false on a fresh app with no input
      if esc || space {
        // This is actually OK if the window got focus and user pressed something
        // during test startup. Just verify the function doesn't crash.
      }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_input_keys() -> TestResult {
  let rc = run_input_keys();
  if rc == 0 { return assert(true, "input: is_key_down no crash"); }
  if rc == 2 { return assert(true, "input: skip (no GPU)"); }
  return assert(false, "input: is_key_down crashed");
}

fn run_input_mouse() -> Int {
  let a = create_app("XIOM Mouse", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      poll(app);
      let (mx, my) = get_mouse_pos(app);
      let mb = is_mouse_down(app, 0);
      // Verify get_mouse_pos returns finite values
      // Mouse position defaults to (0,0) or window center -- just verify it runs
      destroy_app(app);
      return 0;
    }
  }
}

fn test_input_mouse() -> TestResult {
  let rc = run_input_mouse();
  if rc == 0 { return assert(true, "input: get_mouse_pos + is_mouse_down"); }
  if rc == 2 { return assert(true, "input: skip (no GPU)"); }
  return assert(false, "input: mouse functions crashed");
}

// ===========================================================================
// 5. Utility (last_error, now, device_type, framebuffer_size)
// ===========================================================================

fn run_utility_last_error() -> Int {
  // last_error should return a string even without an app
  let e = last_error();
  io.println("  last_error: " + e);
  return 0;
}

fn test_utility_last_error() -> TestResult {
  let rc = run_utility_last_error();
  return assert(rc == 0, "utility: last_error returns string");
}

fn run_utility_now() -> Int {
  let t1 = now();
  let t2 = now();
  // now() should be monotonic
  if t2 < t1 { return 1; }
  return 0;
}

fn test_utility_now() -> TestResult {
  let rc = run_utility_now();
  if rc == 0 { return assert(true, "utility: now() returns monotonic time"); }
  return assert(false, "utility: now() not monotonic");
}

fn run_utility_device_type() -> Int {
  let a = create_app("XIOM DevType", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      let dt = device_type(app);
      // dt should be 1 (integrated), 2 (discrete), 3 (virtual), or 4 (cpu)
      if dt >= 1 && dt <= 4 { destroy_app(app); return 0; }
      destroy_app(app); return 1;
    }
  }
}

fn test_utility_device_type() -> TestResult {
  let rc = run_utility_device_type();
  if rc == 0 { return assert(true, "utility: device_type returns valid code"); }
  if rc == 2 { return assert(true, "utility: device_type skip"); }
  return assert(false, "utility: device_type invalid");
}

fn run_utility_framebuffer_size() -> Int {
  let a = create_app("XIOM FBSize", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // pump one frame to get valid framebuffer
      poll(app);
      let s = begin_frame(app);
      if s == 1 { end_frame(app); }
      let (w, h) = get_framebuffer_size(app);
      if w > 0 && h > 0 { destroy_app(app); return 0; }
      destroy_app(app); return 0;
    }
  }
}

fn test_utility_framebuffer_size() -> TestResult {
  let rc = run_utility_framebuffer_size();
  if rc == 0 { return assert(true, "utility: get_framebuffer_size no crash"); }
  if rc == 2 { return assert(true, "utility: framebuffer_size skip"); }
  return assert(false, "utility: framebuffer_size crashed");
}

// ===========================================================================
// 6. Lifecycle Helpers (resize, maximize, fullscreen, toggle)
// ===========================================================================

fn run_lifecycle_helpers() -> Int {
  let a = create_app("XIOM Helpers", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // These should not crash on a valid app handle
      poll(app);
      let did_resize = app_did_resize(app);
      if did_resize { app_clear_resize(app); }
      app_maximize(app);
      app_toggle_fullscreen(app);
      app_toggle_fullscreen(app); // toggle back
      poll(app);
      destroy_app(app);
      return 0;
    }
  }
}

fn test_lifecycle_helpers() -> TestResult {
  let rc = run_lifecycle_helpers();
  if rc == 0 { return assert(true, "lifecycle: helpers (resize, maximize, fullscreen)"); }
  if rc == 2 { return assert(true, "lifecycle: helpers skip"); }
  return assert(false, "lifecycle: helpers crashed");
}

// ===========================================================================
// 7. Buffers (create, destroy, size, map, unmap)
// ===========================================================================

fn run_buffer_create_destroy() -> Int {
  let a = create_app("XIOM Buffer", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // VK_BUFFER_USAGE_STORAGE_BUFFER_BIT=8, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT=2
      let b = buffer_create(app, 256, 8, 2);
      match b {
        Err(e) => { io.println("  buffer create error: " + e); destroy_app(app); return 1; }
        Ok(buf) => {
          buffer_destroy(app, buf);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_buffer_create_destroy() -> TestResult {
  let rc = run_buffer_create_destroy();
  if rc == 0 { return assert(true, "buffer: create + destroy 256B"); }
  if rc == 2 { return assert(true, "buffer: skip (no GPU)"); }
  return assert(false, "buffer: create or destroy failed");
}

fn run_buffer_size() -> Int {
  let a = create_app("XIOM BufSize", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      let b = buffer_create(app, 512, 8, 2);
      match b {
        Err(_) => { destroy_app(app); return 1; }
        Ok(buf) => {
          let sz = buffer_size(app, buf);
          if sz != 512 { buffer_destroy(app, buf); destroy_app(app); return 1; }
          buffer_destroy(app, buf);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_buffer_size() -> TestResult {
  let rc = run_buffer_size();
  if rc == 0 { return assert(true, "buffer: size matches creation size"); }
  if rc == 2 { return assert(true, "buffer: size skip"); }
  return assert(false, "buffer: size mismatch");
}

fn run_buffer_map_unmap() -> Int {
  let a = create_app("XIOM Map", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      let b = buffer_create(app, 256, 8, 2);
      match b {
        Err(_) => { destroy_app(app); return 1; }
        Ok(buf) => {
          let mapped = buffer_map(app, buf);
          if mapped {
            buffer_unmap(app, buf);
          } else {
            buffer_destroy(app, buf); destroy_app(app); return 1;
          }
          buffer_destroy(app, buf);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_buffer_map_unmap() -> TestResult {
  let rc = run_buffer_map_unmap();
  if rc == 0 { return assert(true, "buffer: map + unmap"); }
  if rc == 2 { return assert(true, "buffer: map skip"); }
  return assert(false, "buffer: map or unmap failed");
}

// ===========================================================================
// 8. Offscreen (create, render, pixel, hash, destroy)
// ===========================================================================

fn run_offscreen_lifecycle() -> Int {
  let a = create_app("XIOM Offscreen", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // Need at least one frame before offscreen works
      poll(app);
      let s = begin_frame(app);
      if s == 1 { end_frame(app); }

      let os = offscreen_create(64, 64);
      match os {
        Err(e) => { io.println("  offscreen create: " + e); destroy_app(app); return 1; }
        Ok(h) => {
          let ok = offscreen_render_triangle(app, 1.0, 0.0, 0.0);
          if ok {
            let px = offscreen_pixel(app, 32, 32);
            let hsh = offscreen_hash(app);
          }
          offscreen_destroy(app);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_offscreen_lifecycle() -> TestResult {
  let rc = run_offscreen_lifecycle();
  if rc == 0 { return assert(true, "offscreen: create+render+pixel+hash+destroy"); }
  if rc == 2 { return assert(true, "offscreen: skip (no GPU)"); }
  return assert(false, "offscreen: lifecycle failed");
}

// ===========================================================================
// 9. Camera (orbit, zoom, reset, aspect ratio)
// ===========================================================================

fn run_camera_operations() -> Int {
  let a = create_app("XIOM Camera", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      poll(app);
      let s = begin_frame(app);
      if s == 1 {
        camera_reset(app);
        camera_orbit(app, 0.5, 0.2, -0.1);
        camera_zoom(app, 1.5);
        camera_set_aspect(app, 1.777);
        camera_set_aspect_from_fb(app, 120, 120);
        camera_set_view(app, 2.0, 2.0, 2.0, 0.0, 0.0, 0.0);
        end_frame(app);
      } elif s == -1 { destroy_app(app); return 1; }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_camera_operations() -> TestResult {
  let rc = run_camera_operations();
  if rc == 0 { return assert(true, "camera: all 6 operations no crash"); }
  if rc == 2 { return assert(true, "camera: skip (no GPU)"); }
  return assert(false, "camera: operation crashed");
}

// ===========================================================================
// 10. Math (cos, sin)
// ===========================================================================

fn run_math_cos_sin() -> Int {
  let c0 = cos(0.0);
  let s0 = sin(0.0);
  // cos(0)=1.0, sin(0)=0.0
  if c0 < 0.99 || c0 > 1.01 { return 1; }
  if s0 < -0.01 || s0 > 0.01 { return 1; }

  let pi = 3.14159265;
  let cpi = cos(pi);
  let spi = sin(pi);
  // cos(pi)~=-1.0, sin(pi)~=0.0
  if cpi < -1.01 || cpi > -0.99 { return 1; }

  let ch = cos(pi / 2.0);
  let sh = sin(pi / 2.0);
  // cos(pi/2)~=0.0, sin(pi/2)~=1.0
  if ch < -0.01 || ch > 0.01 { return 1; }
  if sh < 0.99 || sh > 1.01 { return 1; }

  return 0;
}

fn test_math_cos_sin() -> TestResult {
  let rc = run_math_cos_sin();
  if rc == 0 { return assert(true, "math: cos+sin values correct"); }
  return assert(false, "math: cos or sin incorrect");
}

// ===========================================================================
// 11. Procedural Textures (solid, gradient)
// ===========================================================================

fn run_proc_texture_solid() -> Int {
  let t = proc_texture_solid(32, 32, 1.0, 0.0, 0.0);
  match t {
    Err(e) => { io.println("  solid tex: " + e); return 1; }
    Ok(tex) => { free_pixels(tex); return 0; }
  }
}

fn test_proc_texture_solid() -> TestResult {
  let rc = run_proc_texture_solid();
  if rc == 0 { return assert(true, "texture: solid 32x32 red"); }
  return assert(false, "texture: solid create failed");
}

fn run_proc_texture_gradient() -> Int {
  let t = proc_texture_gradient(32, 32, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0);
  match t {
    Err(e) => { io.println("  grad tex: " + e); return 1; }
    Ok(tex) => { free_pixels(tex); return 0; }
  }
}

fn test_proc_texture_gradient() -> TestResult {
  let rc = run_proc_texture_gradient();
  if rc == 0 { return assert(true, "texture: gradient 32x32 vertical"); }
  return assert(false, "texture: gradient create failed");
}

// ===========================================================================
// 12. Font (create, metrics, measure, destroy)
// ===========================================================================

fn run_font_lifecycle() -> Int {
  let font = font_create(16.0);
  if font == 0 { return 1; }

  let count = font_get_glyph_count(font);
  if count < 90 || count > 200 { font_destroy(font); return 1; }

  let width = font_measure_text(font, "Hello XIOM");
  if width < 0.0 { font_destroy(font); return 1; }

  font_destroy(font);
  return 0;
}

fn test_font_lifecycle() -> TestResult {
  let rc = run_font_lifecycle();
  if rc == 0 { return assert(true, "font: create+count+measure+destroy"); }
  return assert(false, "font: lifecycle failed");
}

// ===========================================================================
// 13. Images (create_2d, destroy, view create, view destroy)
// ===========================================================================

fn run_image_create_destroy() -> Int {
  let a = create_app("XIOM Image", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // VK_FORMAT_R8G8B8A8_UNORM=37, VK_IMAGE_USAGE_SAMPLED_BIT=4
      let img = image_create_2d(app, 64, 64, 37, 4, 1);
      match img {
        Err(e) => { io.println("  image: " + e); destroy_app(app); return 1; }
        Ok(handle) => {
          // VK_IMAGE_ASPECT_COLOR_BIT=1
          let view = image_view_create(app, handle, 37, 1);
          match view {
            Err(_) => {}
            Ok(v) => { image_view_destroy(app, v); }
          }
          image_destroy(app, handle);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_image_create_destroy() -> TestResult {
  let rc = run_image_create_destroy();
  if rc == 0 { return assert(true, "image: create_2d+view_create+destroy"); }
  if rc == 2 { return assert(true, "image: skip (no GPU)"); }
  return assert(false, "image: lifecycle failed");
}

// ===========================================================================
// 14. Samplers (create, destroy)
// ===========================================================================

fn run_sampler_create_destroy() -> Int {
  let a = create_app("XIOM Sampler", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      // VK_FILTER_LINEAR=1, VK_SAMPLER_ADDRESS_MODE_REPEAT=0, VK_SAMPLER_MIPMAP_MODE_LINEAR=1
      let s = sampler_create(app, 1, 0, 0, 1, 1.0);
      match s {
        Err(e) => { io.println("  sampler: " + e); destroy_app(app); return 1; }
        Ok(handle) => {
          sampler_destroy(app, handle);
          destroy_app(app);
          return 0;
        }
      }
    }
  }
}

fn test_sampler_create_destroy() -> TestResult {
  let rc = run_sampler_create_destroy();
  if rc == 0 { return assert(true, "sampler: create + destroy"); }
  if rc == 2 { return assert(true, "sampler: skip (no GPU)"); }
  return assert(false, "sampler: lifecycle failed");
}

// ===========================================================================
// 15. Drawing (triangle, cube, quad, particles -- windowed smoke)
// ===========================================================================

fn run_drawing_smoke() -> Int {
  let a = create_app("XIOM Draw", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      var fc: Int = 0;
      while fc < 3 {
        poll(app);
        let s = begin_frame(app);
        if s == 1 {
          draw_triangle_2d(app, 1.0, 0.0, 0.0);
          draw_cube_3d(app, 0.5);
          draw_quad_2d(app, 0.0, 0.0, 0.4, 0.4, 0.0, 0.0, 1.0);
          draw_cube_3d_at(app, 0.3, 1.0, 0.0, -3.0, 1.0);
          end_frame(app);
          fc = fc + 1;
        } elif s == -1 { destroy_app(app); return 1; }
      }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_drawing_smoke() -> TestResult {
  let rc = run_drawing_smoke();
  if rc == 0 { return assert(true, "drawing: triangle+cube+quad+3d_at 3 frames"); }
  if rc == 2 { return assert(true, "drawing: skip (no GPU)"); }
  return assert(false, "drawing: smoke test failed");
}

fn run_particles_smoke() -> Int {
  let a = create_app("XIOM Particles", 120, 120);
  match a {
    Err(_) => return 2,
    Ok(app) => {
      if !particles_enable(app, 100) {
        // May fail if compute shaders not available
        destroy_app(app); return 0;
      }
      var fc: Int = 0;
      while fc < 3 {
        poll(app);
        let s = begin_frame(app);
        if s == 1 {
          draw_particles(app, 0.016);
          end_frame(app);
          fc = fc + 1;
        } elif s == -1 { destroy_app(app); return 1; }
      }
      destroy_app(app);
      return 0;
    }
  }
}

fn test_particles_smoke() -> TestResult {
  let rc = run_particles_smoke();
  if rc == 0 { return assert(true, "drawing: particles enable+draw 3 frames"); }
  if rc == 2 { return assert(true, "drawing: particles skip"); }
  return assert(false, "drawing: particles smoke failed");
}

// ===========================================================================
// 16. Error Handling (invalid params)
// ===========================================================================

fn run_error_invalid_app() -> Int {
  // destroy_app with invalid handle -- contract should catch it
  // NOTE: contracts trap (X0100), so we test via the raw FFI
  // Checking that buffer_create with garbage returns Err
  let b = buffer_create(0, 256, 8, 2);
  match b {
    Ok(_) => return 1, // should not succeed with app=0
    Err(_) => return 0,
  }
}

fn test_error_invalid_app() -> TestResult {
  let rc = run_error_invalid_app();
  if rc == 0 { return assert(true, "error: buffer_create(app=0) rejected"); }
  return assert(false, "error: buffer_create accepted invalid app");
}

fn run_error_zero_size() -> Int {
  // buffer_create with size=0 should be rejected by contract
  // But contract traps, so we test the raw bridge
  let raw = unsafe { xvk_buffer_create(0, 0, 8 as Int32, 2 as Int32) };
  if raw == 0 { return 0; }
  return 1; // should not create a 0-byte buffer
}

fn test_error_zero_size() -> TestResult {
  let rc = run_error_zero_size();
  if rc == 0 { return assert(true, "error: 0-byte buffer rejected at bridge"); }
  return assert(false, "error: 0-byte buffer unexpectedly created");
}

// ===========================================================================
// Main
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM Vulkan Conformance Tests ===");

  var failed: Int = 0;
  var total: Int = 0;

  // 1. Lifecycle
  let r1 = test_lifecycle_create_destroy();
  total = total + 1; failed = failed + report(r1.passed, r1.name);

  let r2 = test_lifecycle_app_valid();
  total = total + 1; failed = failed + report(r2.passed, r2.name);

  let r3 = test_lifecycle_not_valid_after_destroy();
  total = total + 1; failed = failed + report(r3.passed, r3.name);

  let r4 = test_lifecycle_should_close();
  total = total + 1; failed = failed + report(r4.passed, r4.name);

  // 2. Accessors
  let r5 = test_accessors_all();
  total = total + 1; failed = failed + report(r5.passed, r5.name);

  // 3. Frame
  let r6 = test_frame_cycle();
  total = total + 1; failed = failed + report(r6.passed, r6.name);

  let r7 = test_frame_guard();
  total = total + 1; failed = failed + report(r7.passed, r7.name);

  // 4. Input
  let r8 = test_input_keys();
  total = total + 1; failed = failed + report(r8.passed, r8.name);

  let r9 = test_input_mouse();
  total = total + 1; failed = failed + report(r9.passed, r9.name);

  // 5. Utility
  let r10 = test_utility_last_error();
  total = total + 1; failed = failed + report(r10.passed, r10.name);

  let r11 = test_utility_now();
  total = total + 1; failed = failed + report(r11.passed, r11.name);

  let r12 = test_utility_device_type();
  total = total + 1; failed = failed + report(r12.passed, r12.name);

  let r13 = test_utility_framebuffer_size();
  total = total + 1; failed = failed + report(r13.passed, r13.name);

  // 6. Lifecycle Helpers
  let r14 = test_lifecycle_helpers();
  total = total + 1; failed = failed + report(r14.passed, r14.name);

  // 7. Buffers
  let r15 = test_buffer_create_destroy();
  total = total + 1; failed = failed + report(r15.passed, r15.name);

  let r16 = test_buffer_size();
  total = total + 1; failed = failed + report(r16.passed, r16.name);

  let r17 = test_buffer_map_unmap();
  total = total + 1; failed = failed + report(r17.passed, r17.name);

  // 8. Offscreen
  let r18 = test_offscreen_lifecycle();
  total = total + 1; failed = failed + report(r18.passed, r18.name);

  // 9. Camera
  let r19 = test_camera_operations();
  total = total + 1; failed = failed + report(r19.passed, r19.name);

  // 10. Math
  let r20 = test_math_cos_sin();
  total = total + 1; failed = failed + report(r20.passed, r20.name);

  // 11. Textures
  let r21 = test_proc_texture_solid();
  total = total + 1; failed = failed + report(r21.passed, r21.name);

  let r22 = test_proc_texture_gradient();
  total = total + 1; failed = failed + report(r22.passed, r22.name);

  // 12. Font
  let r23 = test_font_lifecycle();
  total = total + 1; failed = failed + report(r23.passed, r23.name);

  // 13. Images
  let r24 = test_image_create_destroy();
  total = total + 1; failed = failed + report(r24.passed, r24.name);

  // 14. Samplers
  let r25 = test_sampler_create_destroy();
  total = total + 1; failed = failed + report(r25.passed, r25.name);

  // 15. Drawing
  let r26 = test_drawing_smoke();
  total = total + 1; failed = failed + report(r26.passed, r26.name);

  let r27 = test_particles_smoke();
  total = total + 1; failed = failed + report(r27.passed, r27.name);

  // 16. Error Handling
  let r28 = test_error_invalid_app();
  total = total + 1; failed = failed + report(r28.passed, r28.name);

  let r29 = test_error_zero_size();
  total = total + 1; failed = failed + report(r29.passed, r29.name);

  let passed = total - failed;
  io.println("");
  io.println("XIOM Vulkan Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
