// XIOM -- Raylib Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Tests all types, constants, color helpers, and safe wrapper contracts
// in xiom.raylib. FFI-dependent tests validate compile-time contracts;
// linking requires system-installed raylib.

module raylib_conformance

use TestResult;
use assert_eq;
use xiom.test.assert;
use xiom.test.run_all;
use xiom.io;
use xiom.raylib;

// =========================================================================
// Helpers
// =========================================================================

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

// =========================================================================
// 1. Type Construction Tests (8 tests)
// =========================================================================

fn test_type_rl_window() -> TestResult {
  let w: xiom.raylib.RlWindow = 0;
  return assert_eq(0 as Int, w as Int, "type: RlWindow = Int construction");
}

fn test_type_rl_texture() -> TestResult {
  let t: xiom.raylib.RlTexture = 42;
  return assert_eq(42 as Int, t as Int, "type: RlTexture = Int construction");
}

fn test_type_rl_shader() -> TestResult {
  let s: xiom.raylib.RlShader = 7;
  return assert_eq(7 as Int, s as Int, "type: RlShader = Int construction");
}

fn test_type_rl_model() -> TestResult {
  let m: xiom.raylib.RlModel = 1;
  return assert_eq(1 as Int, m as Int, "type: RlModel = Int construction");
}

fn test_type_rl_sound() -> TestResult {
  let s: xiom.raylib.RlSound = 3;
  return assert_eq(3 as Int, s as Int, "type: RlSound = Int construction");
}

fn test_type_rl_music() -> TestResult {
  let m: xiom.raylib.RlMusic = 5;
  return assert_eq(5 as Int, m as Int, "type: RlMusic = Int construction");
}

fn test_type_rl_camera() -> TestResult {
  let c: xiom.raylib.RlCamera = 0;
  return assert_eq(0 as Int, c as Int, "type: RlCamera = Int construction");
}

fn test_type_rl_font() -> TestResult {
  let f: xiom.raylib.RlFont = 99;
  return assert_eq(99 as Int, f as Int, "type: RlFont = Int construction");
}

// =========================================================================
// 2. Color Constant Tests (8 tests)
// =========================================================================

fn test_color_raywhite() -> TestResult {
  return assert_eq(0xFFFFFFFF, xiom.raylib.RAYWHITE, "color: RAYWHITE == 0xFFFFFFFF");
}

fn test_color_black() -> TestResult {
  return assert_eq(0xFF000000, xiom.raylib.BLACK, "color: BLACK == 0xFF000000");
}

fn test_color_blank_transparent() -> TestResult {
  return assert_eq(0x00000000, xiom.raylib.BLANK, "color: BLANK == 0x00000000 (fully transparent)");
}

fn test_color_red() -> TestResult {
  return assert_eq(0xFF3729E6, xiom.raylib.RED, "color: RED == 0xFF3729E6");
}

fn test_color_green() -> TestResult {
  return assert_eq(0xFF30E400, xiom.raylib.GREEN, "color: GREEN == 0xFF30E400");
}

fn test_color_blue() -> TestResult {
  return assert_eq(0xFFF17900, xiom.raylib.BLUE, "color: BLUE == 0xFFF17900");
}

fn test_color_magenta() -> TestResult {
  return assert_eq(0xFFFF00FF, xiom.raylib.MAGENTA, "color: MAGENTA == 0xFFFF00FF");
}

fn test_color_white_eq_raywhite() -> TestResult {
  return assert_eq(xiom.raylib.WHITE, xiom.raylib.RAYWHITE, "color: WHITE == RAYWHITE");
}

// =========================================================================
// 3. Key Constant Tests (5 tests)
// =========================================================================

fn test_key_space() -> TestResult {
  return assert_eq(32, xiom.raylib.KEY_SPACE, "key: KEY_SPACE == 32");
}

fn test_key_escape() -> TestResult {
  return assert_eq(256, xiom.raylib.KEY_ESCAPE, "key: KEY_ESCAPE == 256");
}

fn test_key_a() -> TestResult {
  return assert_eq(65, xiom.raylib.KEY_A, "key: KEY_A == 65 (ASCII 'A')");
}

fn test_key_right() -> TestResult {
  return assert_eq(262, xiom.raylib.KEY_RIGHT, "key: KEY_RIGHT == 262");
}

fn test_key_special_ordering() -> TestResult {
  let ok = xiom.raylib.KEY_UP > xiom.raylib.KEY_DOWN
        && xiom.raylib.KEY_DOWN > xiom.raylib.KEY_LEFT
        && xiom.raylib.KEY_LEFT > xiom.raylib.KEY_RIGHT;
  return assert(ok, "key: KEY_UP > KEY_DOWN > KEY_LEFT > KEY_RIGHT ordering");
}

// =========================================================================
// 4. Mouse Button Tests (3 tests)
// =========================================================================

fn test_mouse_left() -> TestResult {
  return assert_eq(0, xiom.raylib.MOUSE_BUTTON_LEFT, "mouse: MOUSE_BUTTON_LEFT == 0");
}

fn test_mouse_right() -> TestResult {
  return assert_eq(1, xiom.raylib.MOUSE_BUTTON_RIGHT, "mouse: MOUSE_BUTTON_RIGHT == 1");
}

fn test_mouse_ordering() -> TestResult {
  let ok = xiom.raylib.MOUSE_BUTTON_LEFT < xiom.raylib.MOUSE_BUTTON_RIGHT
        && xiom.raylib.MOUSE_BUTTON_RIGHT < xiom.raylib.MOUSE_BUTTON_MIDDLE;
  return assert(ok, "mouse: LEFT < RIGHT < MIDDLE ordering");
}

// =========================================================================
// 5. Camera Mode Tests (2 tests)
// =========================================================================

fn test_camera_free() -> TestResult {
  return assert_eq(0, xiom.raylib.CAMERA_FREE, "camera: CAMERA_FREE == 0");
}

fn test_camera_orbital() -> TestResult {
  return assert_eq(3, xiom.raylib.CAMERA_ORBITAL, "camera: CAMERA_ORBITAL == 3");
}

// =========================================================================
// 6. FPS Constant Tests (2 tests)
// =========================================================================

fn test_fps_min_positive() -> TestResult {
  let ok = xiom.raylib.FPS_MIN > 0;
  return assert(ok, "fps: FPS_MIN > 0");
}

fn test_fps_ordering() -> TestResult {
  let ok = xiom.raylib.FPS_60 < xiom.raylib.FPS_120 && xiom.raylib.FPS_120 < xiom.raylib.FPS_144;
  return assert(ok, "fps: FPS_60 < FPS_120 < FPS_144 ordering");
}

// =========================================================================
// 7. Color Helper Function Tests (7 tests)
// =========================================================================

fn test_helper_color_rgba_black() -> TestResult {
  let c: Int = xiom.raylib.color_rgba(0, 0, 0, 255);
  return assert_eq(xiom.raylib.BLACK, c, "helper: color_rgba(0,0,0,255) == BLACK");
}

fn test_helper_color_rgba_white() -> TestResult {
  let c: Int = xiom.raylib.color_rgba(255, 255, 255, 255);
  return assert_eq(xiom.raylib.RAYWHITE, c, "helper: color_rgba(255,255,255,255) == RAYWHITE");
}

fn test_helper_color_rgba_blank() -> TestResult {
  let c: Int = xiom.raylib.color_rgba(0, 0, 0, 0);
  return assert_eq(xiom.raylib.BLANK, c, "helper: color_rgba(0,0,0,0) == BLANK");
}

fn test_helper_color_alpha_raywhite() -> TestResult {
  let a: Int = xiom.raylib.color_alpha(xiom.raylib.RAYWHITE);
  return assert_eq(255, a, "helper: color_alpha(RAYWHITE) == 255");
}

fn test_helper_color_alpha_blank() -> TestResult {
  let a: Int = xiom.raylib.color_alpha(xiom.raylib.BLANK);
  return assert_eq(0, a, "helper: color_alpha(BLANK) == 0");
}

fn test_helper_color_red_extract() -> TestResult {
  let r: Int = xiom.raylib.color_red(xiom.raylib.RED);
  return assert_eq(230, r, "helper: color_red(RED) == 230");
}

fn test_helper_color_green_extract() -> TestResult {
  let g: Int = xiom.raylib.color_green(xiom.raylib.GREEN);
  return assert_eq(228, g, "helper: color_green(GREEN) == 228");
}

// =========================================================================
// 8. Cross-Constant Consistency Tests (2 tests)
// =========================================================================

fn test_constants_distinct_colors() -> TestResult {
  let ok = xiom.raylib.RED != xiom.raylib.GREEN
        && xiom.raylib.GREEN != xiom.raylib.BLUE
        && xiom.raylib.BLUE != xiom.raylib.BLACK
        && xiom.raylib.BLACK != xiom.raylib.RAYWHITE
        && xiom.raylib.ORANGE != xiom.raylib.YELLOW
        && xiom.raylib.PURPLE != xiom.raylib.MAGENTA
        && xiom.raylib.MAROON != xiom.raylib.RED
        && xiom.raylib.SKYBLUE != xiom.raylib.BLUE
        && xiom.raylib.BEIGE != xiom.raylib.BROWN;
  return assert(ok, "constants: all named colors are distinct");
}

fn test_constants_key_symmetry() -> TestResult {
  let ok = xiom.raylib.KEY_Z == xiom.raylib.KEY_A + 25
        && xiom.raylib.KEY_9 == xiom.raylib.KEY_0 + 9;
  return assert(ok, "constants: KEY_Z == KEY_A + 25 && KEY_9 == KEY_0 + 9");
}

// =========================================================================
// Main -- run all tests
// =========================================================================

fn main() -> Int {
  io.println("=== XIOM Raylib Conformance Tests ===");

  var tests: Vec[fn() -> TestResult] = Vec[fn() -> TestResult].new();

  tests.push(test_type_rl_window);
  tests.push(test_type_rl_texture);
  tests.push(test_type_rl_shader);
  tests.push(test_type_rl_model);
  tests.push(test_type_rl_sound);
  tests.push(test_type_rl_music);
  tests.push(test_type_rl_camera);
  tests.push(test_type_rl_font);

  tests.push(test_color_raywhite);
  tests.push(test_color_black);
  tests.push(test_color_blank_transparent);
  tests.push(test_color_red);
  tests.push(test_color_green);
  tests.push(test_color_blue);
  tests.push(test_color_magenta);
  tests.push(test_color_white_eq_raywhite);

  tests.push(test_key_space);
  tests.push(test_key_escape);
  tests.push(test_key_a);
  tests.push(test_key_right);
  tests.push(test_key_special_ordering);

  tests.push(test_mouse_left);
  tests.push(test_mouse_right);
  tests.push(test_mouse_ordering);

  tests.push(test_camera_free);
  tests.push(test_camera_orbital);

  tests.push(test_fps_min_positive);
  tests.push(test_fps_ordering);

  tests.push(test_helper_color_rgba_black);
  tests.push(test_helper_color_rgba_white);
  tests.push(test_helper_color_rgba_blank);
  tests.push(test_helper_color_alpha_raywhite);
  tests.push(test_helper_color_alpha_blank);
  tests.push(test_helper_color_red_extract);
  tests.push(test_helper_color_green_extract);

  tests.push(test_constants_distinct_colors);
  tests.push(test_constants_key_symmetry);

  let failed = run_all(tests);
  let exit_code = failed;

  io.println("");
  if exit_code == 0 {
    io.println("All 37 tests passed.");
  } else {
    io.println(int_to_str(exit_code) + " test(s) failed.");
  };

  return exit_code;
}
