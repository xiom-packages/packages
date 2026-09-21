// XIOM -- Raylib Bindings v0.1.0 (Phase 5 -- SPEC)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers around raylib v5.5 via extern "C" FFI.
// Links against system-installed raylib at link time.
// 26 functions + 8 newtypes + 40 constants + 28 safe wrappers.

module xiom.raylib

// -- extern "C" -- Raw raylib C Declarations (26 functions) ------------------

extern "C" {
  fn InitWindow(width: Int32, height: Int32, title: Str);
  fn CloseWindow();
  fn WindowShouldClose() -> Int32;
  fn BeginDrawing();
  fn EndDrawing();
  fn ClearBackground(color: Int32);
  fn DrawRectangle(x: Int32, y: Int32, w: Int32, h: Int32, color: Int32);
  fn DrawCircle(cx: Int32, cy: Int32, r: Float32, color: Int32);
  fn DrawText(text: Str, x: Int32, y: Int32, fontSize: Int32, color: Int32);
  fn DrawTexture(texture: Int, x: Int32, y: Int32, color: Int32);
  fn DrawModel(model: Int, posX: Float32, posY: Float32, posZ: Float32, scale: Float32, color: Int32);
  fn LoadTexture(path: Str) -> Int;
  fn UnloadTexture(texture: Int);
  fn LoadModel(path: Str) -> Int;
  fn UnloadModel(model: Int);
  fn LoadSound(path: Str) -> Int;
  fn PlaySound(sound: Int);
  fn SetCameraMode(camera: Int, mode: Int32);
  fn UpdateCamera(camera: Int, mode: Int32);
  fn GetMouseX() -> Float32;
  fn GetMouseY() -> Float32;
  fn IsKeyDown(key: Int32) -> Int32;
  fn IsMouseButtonDown(button: Int32) -> Int32;
  fn GetFrameTime() -> Float32;
  fn SetTargetFPS(fps: Int32);
  fn LoadFont(path: Str) -> Int;
  fn DrawTextEx(font: Int, text: Str, x: Float32, y: Float32, fontSize: Float32, spacing: Float32, color: Int32);
}

// -- Newtypes -- Opaque resource handles (8 types) ---------------------------

pub type RlWindow    = Int;
pub type RlTexture   = Int;
pub type RlShader    = Int;
pub type RlModel     = Int;
pub type RlSound     = Int;
pub type RlMusic     = Int;
pub type RlCamera    = Int;
pub type RlFont      = Int;

// -- Color Constants (RGBA packed as Int32, little-endian byte order) -------

pub const RAYWHITE:   Int = 0xFFFFFFFF;
pub const WHITE:      Int = 0xFFFFFFFF;
pub const BLACK:      Int = 0xFF000000;
pub const BLANK:      Int = 0x00000000;
pub const LIGHTGRAY:  Int = 0xFFC8C8C8;
pub const GRAY:       Int = 0xFF828282;
pub const DARKGRAY:   Int = 0xFF505050;
pub const RED:        Int = 0xFF3729E6;
pub const MAROON:     Int = 0xFF3721BE;
pub const GREEN:      Int = 0xFF30E400;
pub const LIME:       Int = 0xFF2F9E00;
pub const DARKGREEN:  Int = 0xFF2C7500;
pub const BLUE:       Int = 0xFFF17900;
pub const SKYBLUE:    Int = 0xFFFFBF66;
pub const DARKBLUE:   Int = 0xFFAC5200;
pub const YELLOW:     Int = 0xFF00F9FD;
pub const GOLD:       Int = 0xFF00CBFF;
pub const ORANGE:     Int = 0xFF00A1FF;
pub const PINK:       Int = 0xFFC26DFF;
pub const MAGENTA:    Int = 0xFFFF00FF;
pub const PURPLE:     Int = 0xFFFF7AC8;
pub const VIOLET:     Int = 0xFFBE3C87;
pub const DARKPURPLE: Int = 0xFF7E1F70;
pub const BEIGE:      Int = 0xFF83B0D3;
pub const BROWN:      Int = 0xFF4F6A7F;
pub const DARKBROWN:  Int = 0xFF2F3F4C;

// -- Keyboard Key Constants -------------------------------------------------

pub const KEY_SPACE:        Int = 32;
pub const KEY_APOSTROPHE:   Int = 39;
pub const KEY_COMMA:        Int = 44;
pub const KEY_MINUS:        Int = 45;
pub const KEY_PERIOD:       Int = 46;
pub const KEY_SLASH:        Int = 47;
pub const KEY_0:            Int = 48;
pub const KEY_1:            Int = 49;
pub const KEY_2:            Int = 50;
pub const KEY_3:            Int = 51;
pub const KEY_4:            Int = 52;
pub const KEY_5:            Int = 53;
pub const KEY_6:            Int = 54;
pub const KEY_7:            Int = 55;
pub const KEY_8:            Int = 56;
pub const KEY_9:            Int = 57;
pub const KEY_SEMICOLON:    Int = 59;
pub const KEY_EQUAL:        Int = 61;
pub const KEY_A:            Int = 65;
pub const KEY_B:            Int = 66;
pub const KEY_C:            Int = 67;
pub const KEY_D:            Int = 68;
pub const KEY_E:            Int = 69;
pub const KEY_F:            Int = 70;
pub const KEY_G:            Int = 71;
pub const KEY_H:            Int = 72;
pub const KEY_I:            Int = 73;
pub const KEY_J:            Int = 74;
pub const KEY_K:            Int = 75;
pub const KEY_L:            Int = 76;
pub const KEY_M:            Int = 77;
pub const KEY_N:            Int = 78;
pub const KEY_O:            Int = 79;
pub const KEY_P:            Int = 80;
pub const KEY_Q:            Int = 81;
pub const KEY_R:            Int = 82;
pub const KEY_S:            Int = 83;
pub const KEY_T:            Int = 84;
pub const KEY_U:            Int = 85;
pub const KEY_V:            Int = 86;
pub const KEY_W:            Int = 87;
pub const KEY_X:            Int = 88;
pub const KEY_Y:            Int = 89;
pub const KEY_Z:            Int = 90;
pub const KEY_LEFT_BRACKET:  Int = 91;
pub const KEY_BACKSLASH:     Int = 92;
pub const KEY_RIGHT_BRACKET: Int = 93;
pub const KEY_GRAVE:         Int = 96;

pub const KEY_ESCAPE:    Int = 256;
pub const KEY_ENTER:     Int = 257;
pub const KEY_TAB:       Int = 258;
pub const KEY_BACKSPACE: Int = 259;
pub const KEY_INSERT:    Int = 260;
pub const KEY_DELETE:    Int = 261;
pub const KEY_RIGHT:     Int = 262;
pub const KEY_LEFT:      Int = 263;
pub const KEY_DOWN:      Int = 264;
pub const KEY_UP:        Int = 265;
pub const KEY_PAGE_UP:   Int = 266;
pub const KEY_PAGE_DOWN: Int = 267;
pub const KEY_HOME:      Int = 268;
pub const KEY_END:       Int = 269;
pub const KEY_CAPS_LOCK:   Int = 280;
pub const KEY_SCROLL_LOCK: Int = 281;
pub const KEY_NUM_LOCK:    Int = 282;
pub const KEY_PRINT_SCREEN: Int = 283;
pub const KEY_PAUSE:       Int = 284;
pub const KEY_F1:  Int = 290;
pub const KEY_F2:  Int = 291;
pub const KEY_F3:  Int = 292;
pub const KEY_F4:  Int = 293;
pub const KEY_F5:  Int = 294;
pub const KEY_F6:  Int = 295;
pub const KEY_F7:  Int = 296;
pub const KEY_F8:  Int = 297;
pub const KEY_F9:  Int = 298;
pub const KEY_F10: Int = 299;
pub const KEY_F11: Int = 300;
pub const KEY_F12: Int = 301;
pub const KEY_KP_0: Int = 320;
pub const KEY_KP_1: Int = 321;
pub const KEY_KP_2: Int = 322;
pub const KEY_KP_3: Int = 323;
pub const KEY_KP_4: Int = 324;
pub const KEY_KP_5: Int = 325;
pub const KEY_KP_6: Int = 326;
pub const KEY_KP_7: Int = 327;
pub const KEY_KP_8: Int = 328;
pub const KEY_KP_9: Int = 329;
pub const KEY_KP_DECIMAL:  Int = 330;
pub const KEY_KP_DIVIDE:   Int = 331;
pub const KEY_KP_MULTIPLY: Int = 332;
pub const KEY_KP_SUBTRACT: Int = 333;
pub const KEY_KP_ADD:      Int = 334;
pub const KEY_KP_ENTER:    Int = 335;
pub const KEY_KP_EQUAL:    Int = 336;
pub const KEY_LEFT_SHIFT:    Int = 340;
pub const KEY_LEFT_CONTROL:  Int = 341;
pub const KEY_LEFT_ALT:      Int = 342;
pub const KEY_LEFT_SUPER:    Int = 343;
pub const KEY_RIGHT_SHIFT:   Int = 344;
pub const KEY_RIGHT_CONTROL: Int = 345;
pub const KEY_RIGHT_ALT:     Int = 346;
pub const KEY_RIGHT_SUPER:   Int = 347;
pub const KEY_MENU:          Int = 348;

// -- Mouse Button Constants -------------------------------------------------

pub const MOUSE_BUTTON_LEFT:   Int = 0;
pub const MOUSE_BUTTON_RIGHT:  Int = 1;
pub const MOUSE_BUTTON_MIDDLE: Int = 2;
pub const MOUSE_BUTTON_SIDE:   Int = 3;
pub const MOUSE_BUTTON_EXTRA:  Int = 4;
pub const MOUSE_BUTTON_FORWARD: Int = 5;
pub const MOUSE_BUTTON_BACK:   Int = 6;

// -- Camera Mode Constants --------------------------------------------------

pub const CAMERA_FREE:          Int = 0;
pub const CAMERA_FIRST_PERSON:  Int = 1;
pub const CAMERA_THIRD_PERSON:  Int = 2;
pub const CAMERA_ORBITAL:       Int = 3;

// -- FPS Constants ----------------------------------------------------------

pub const FPS_MIN:  Int = 1;
pub const FPS_MAX:  Int = 1000;
pub const FPS_60:   Int = 60;
pub const FPS_120:  Int = 120;
pub const FPS_144:  Int = 144;

// -- Color Helpers ----------------------------------------------------------

pub fn color_rgba(r: Int, g: Int, b: Int, a: Int) -> Int
  requires: r >= 0
  requires: r <= 255
  requires: g >= 0
  requires: g <= 255
  requires: b >= 0
  requires: b <= 255
  requires: a >= 0
  requires: a <= 255
  ensures:  result >= 0
{
  return (a * 16777216) + (b * 65536) + (g * 256) + r;
}

pub fn color_alpha(c: Int) -> Int
  ensures: result >= 0
  ensures: result <= 255
{
  return c / 16777216;
}

pub fn color_red(c: Int) -> Int
  ensures: result >= 0
  ensures: result <= 255
{
  return c % 256;
}

pub fn color_green(c: Int) -> Int
  ensures: result >= 0
  ensures: result <= 255
{
  return (c / 256) % 256;
}

pub fn color_blue(c: Int) -> Int
  ensures: result >= 0
  ensures: result <= 255
{
  return (c / 65536) % 256;
}

// -- Safe Wrappers -- Window Lifecycle ----------------------------------------

pub fn init_window(width: Int, height: Int, title: Str)
  requires: width > 0
  requires: height > 0
  requires: title.len() > 0
{
  unsafe { InitWindow(width as Int32, height as Int32, title); };
}

pub fn close_window()
{
  unsafe { CloseWindow(); };
}

pub fn should_close() -> Bool
{
  return unsafe { WindowShouldClose() != 0 };
}

// -- Safe Wrappers -- Drawing ------------------------------------------------

pub fn begin_drawing()
{
  unsafe { BeginDrawing(); };
}

pub fn end_drawing()
{
  unsafe { EndDrawing(); };
}

pub fn clear_background(color: Int)
  requires: color >= 0
{
  unsafe { ClearBackground(color as Int32); };
}

pub fn draw_rectangle(x: Int, y: Int, w: Int, h: Int, color: Int)
  requires: w >= 0
  requires: h >= 0
  requires: color >= 0
{
  unsafe { DrawRectangle(x as Int32, y as Int32, w as Int32, h as Int32, color as Int32); };
}

pub fn draw_circle(cx: Int, cy: Int, r: Float32, color: Int)
  requires: r >= 0.0
  requires: color >= 0
{
  unsafe { DrawCircle(cx as Int32, cy as Int32, r, color as Int32); };
}

pub fn draw_text(text: Str, x: Int, y: Int, fontSize: Int, color: Int)
  requires: text.len() > 0
  requires: fontSize > 0
  requires: color >= 0
{
  unsafe { DrawText(text, x as Int32, y as Int32, fontSize as Int32, color as Int32); };
}

// -- Safe Wrappers -- Textures & Models --------------------------------------

pub fn load_texture(path: Str) -> RlTexture
  requires: path.len() > 0
  ensures:  result >= 0
{
  return unsafe { LoadTexture(path) };
}

pub fn unload_texture(texture: RlTexture)
  requires: texture != 0
{
  unsafe { UnloadTexture(texture); };
}

pub fn draw_texture(texture: RlTexture, x: Int, y: Int, color: Int)
  requires: texture != 0
  requires: color >= 0
{
  unsafe { DrawTexture(texture, x as Int32, y as Int32, color as Int32); };
}

pub fn load_model(path: Str) -> RlModel
  requires: path.len() > 0
  ensures:  result >= 0
{
  return unsafe { LoadModel(path) };
}

pub fn unload_model(model: RlModel)
  requires: model != 0
{
  unsafe { UnloadModel(model); };
}

pub fn draw_model(model: RlModel, posX: Float32, posY: Float32, posZ: Float32, scale: Float32, color: Int)
  requires: model != 0
  requires: scale > 0.0
  requires: color >= 0
{
  unsafe { DrawModel(model, posX, posY, posZ, scale, color as Int32); };
}

// -- Safe Wrappers -- Audio --------------------------------------------------

pub fn load_sound(path: Str) -> RlSound
  requires: path.len() > 0
  ensures:  result >= 0
{
  return unsafe { LoadSound(path) };
}

pub fn play_sound(sound: RlSound)
  requires: sound != 0
{
  unsafe { PlaySound(sound); };
}

// -- Safe Wrappers -- Camera -------------------------------------------------

pub fn set_camera_mode(camera: RlCamera, mode: Int)
  requires: camera != 0
  requires: mode >= 0
{
  unsafe { SetCameraMode(camera, mode as Int32); };
}

pub fn update_camera(camera: RlCamera, mode: Int)
  requires: camera != 0
  requires: mode >= 0
{
  unsafe { UpdateCamera(camera, mode as Int32); };
}

// -- Safe Wrappers -- Input --------------------------------------------------

pub fn get_mouse_position() -> (Float32, Float32)
{
  let x: Float32 = unsafe { GetMouseX() };
  let y: Float32 = unsafe { GetMouseY() };
  return (x, y);
}

pub fn is_key_down(key: Int) -> Bool
  requires: key >= 0
{
  return unsafe { IsKeyDown(key as Int32) != 0 };
}

pub fn is_mouse_button_down(button: Int) -> Bool
  requires: button >= 0
{
  return unsafe { IsMouseButtonDown(button as Int32) != 0 };
}

// -- Safe Wrappers -- Timing -------------------------------------------------

pub fn get_frame_time() -> Float32
  ensures: result >= 0.0
{
  return unsafe { GetFrameTime() };
}

pub fn set_target_fps(fps: Int)
  requires: fps >= 0
{
  unsafe { SetTargetFPS(fps as Int32); };
}

// -- Safe Wrappers -- Text Advanced ------------------------------------------

pub fn load_font(path: Str) -> RlFont
  requires: path.len() > 0
  ensures:  result >= 0
{
  return unsafe { LoadFont(path) };
}

pub fn draw_text_ex(font: RlFont, text: Str, x: Float32, y: Float32, fontSize: Float32, spacing: Float32, color: Int)
  requires: font != 0
  requires: text.len() > 0
  requires: fontSize > 0.0
  requires: spacing >= 0.0
  requires: color >= 0
{
  unsafe { DrawTextEx(font, text, x, y, fontSize, spacing, color as Int32); };
}
