// XIOM — GLFW Windowing Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.glfw

pub type Window = Int;

pub fn init() -> Result[Unit, Str];
pub fn terminate();
pub fn get_version() -> (Int, Int, Int);
pub fn get_error() -> Option[Str];

pub fn create_window(width: Int, height: Int, title: Str) -> Result[Window, Str];
pub fn destroy_window(window: Window);
pub fn should_close(window: Window) -> Bool;
pub fn set_should_close(window: Window, value: Bool);
pub fn set_title(window: Window, title: Str);
pub fn get_window_size(window: Window) -> (Int, Int);
pub fn set_window_size(window: Window, width: Int, height: Int);
pub fn get_framebuffer_size(window: Window) -> (Int, Int);

pub fn poll_events();
pub fn wait_events();
pub fn get_time() -> Float64;

pub fn get_key(window: Window, key: Int) -> Int; // 0=release, 1=press, 2=repeat
pub fn get_mouse_button(window: Window, button: Int) -> Int;
pub fn get_cursor_pos(window: Window) -> (Float64, Float64);

pub fn make_context_current(window: Window);
pub fn swap_buffers(window: Window);
pub fn set_swap_interval(interval: Int);

pub fn create_window_surface(instance: Int, window: Window) -> Result[Int, Str];
pub fn get_vulkan_extensions() -> Vec[Str];

// Key constants
pub const KEY_SPACE: Int = 32;
pub const KEY_ESCAPE: Int = 256;
pub const KEY_ENTER: Int = 257;
pub const KEY_TAB: Int = 258;
pub const KEY_BACKSPACE: Int = 259;
pub const KEY_LEFT: Int = 263;
pub const KEY_RIGHT: Int = 262;
pub const KEY_UP: Int = 265;
pub const KEY_DOWN: Int = 264;
pub const KEY_A: Int = 65;
pub const KEY_W: Int = 87;
pub const KEY_S: Int = 83;
pub const KEY_D: Int = 68;

pub const MOUSE_BUTTON_LEFT: Int = 0;
pub const MOUSE_BUTTON_RIGHT: Int = 1;
pub const MOUSE_BUTTON_MIDDLE: Int = 2;

pub const PRESS: Int = 1;
pub const RELEASE: Int = 0;
pub const REPEAT: Int = 2;
