// XIOM — SDL3 (Simple DirectMedia Layer 3) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for SDL 3.4.8.
// SDL3 is a cross-platform development library for graphics, input, and audio.
//
// Types: all SDL handles/pointers map to Int. Uint32 → Int32, Uint64 → Int,
// int → Int32, float → Float32, C bool → Int32 (0=false, non-zero=true).
// Naming follows the C API verbatim (SDL_Init, SDL_CreateWindow, etc.).

module xiom.sdl3

// =========================================================================
// SDL Init Flags (SDL_InitFlags)
// =========================================================================

pub const SDL_INIT_AUDIO: Int32    = 16 as Int32;
pub const SDL_INIT_VIDEO: Int32    = 32 as Int32;
pub const SDL_INIT_JOYSTICK: Int32 = 512 as Int32;
pub const SDL_INIT_HAPTIC: Int32   = 4096 as Int32;
pub const SDL_INIT_GAMEPAD: Int32  = 8192 as Int32;
pub const SDL_INIT_EVENTS: Int32   = 16384 as Int32;
pub const SDL_INIT_SENSOR: Int32   = 32768 as Int32;
pub const SDL_INIT_CAMERA: Int32   = 65536 as Int32;

// =========================================================================
// SDL Window Flags (SDL_WindowFlags — Uint64, kept as Int)
// =========================================================================

pub const SDL_WINDOW_FULLSCREEN: Int           = 1;
pub const SDL_WINDOW_OPENGL: Int               = 2;
pub const SDL_WINDOW_OCCLUDED: Int             = 4;
pub const SDL_WINDOW_HIDDEN: Int               = 8;
pub const SDL_WINDOW_BORDERLESS: Int           = 16;
pub const SDL_WINDOW_RESIZABLE: Int            = 32;
pub const SDL_WINDOW_MINIMIZED: Int            = 64;
pub const SDL_WINDOW_MAXIMIZED: Int            = 128;
pub const SDL_WINDOW_MOUSE_GRABBED: Int        = 256;
pub const SDL_WINDOW_INPUT_FOCUS: Int          = 512;
pub const SDL_WINDOW_MOUSE_FOCUS: Int          = 1024;
pub const SDL_WINDOW_EXTERNAL: Int             = 2048;
pub const SDL_WINDOW_MODAL: Int                = 4096;
pub const SDL_WINDOW_HIGH_PIXEL_DENSITY: Int   = 8192;
pub const SDL_WINDOW_MOUSE_CAPTURE: Int        = 16384;
pub const SDL_WINDOW_MOUSE_RELATIVE_MODE: Int  = 32768;
pub const SDL_WINDOW_ALWAYS_ON_TOP: Int        = 65536;
pub const SDL_WINDOW_UTILITY: Int              = 131072;
pub const SDL_WINDOW_TOOLTIP: Int              = 262144;
pub const SDL_WINDOW_POPUP_MENU: Int           = 524288;
pub const SDL_WINDOW_KEYBOARD_GRABBED: Int     = 1048576;
pub const SDL_WINDOW_FILL_DOCUMENT: Int        = 2097152;
pub const SDL_WINDOW_VULKAN: Int               = 268435456;
pub const SDL_WINDOW_METAL: Int                = 536870912;
pub const SDL_WINDOW_TRANSPARENT: Int          = 1073741824;
pub const SDL_WINDOW_NOT_FOCUSABLE: Int        = 2147483648;

pub const SDL_WINDOWPOS_UNDEFINED_MASK: Int = 536805376;
pub const SDL_WINDOWPOS_CENTERED_MASK: Int  = 805240832;

// SDL_WINDOWPOS_UNDEFINED_DISPLAY(X) = SDL_WINDOWPOS_UNDEFINED_MASK | (X)
// For primary display (X=0): SDL_WINDOWPOS_UNDEFINED = 536805376
pub const SDL_WINDOWPOS_UNDEFINED: Int = 536805376;
pub const SDL_WINDOWPOS_CENTERED: Int  = 805240832;

// =========================================================================
// SDL Event Types (SDL_EventType)
// =========================================================================

pub const SDL_EVENT_FIRST: Int32 = 0 as Int32;

pub const SDL_EVENT_QUIT: Int32                  = 256 as Int32;
pub const SDL_EVENT_TERMINATING: Int32            = 257 as Int32;
pub const SDL_EVENT_LOW_MEMORY: Int32             = 258 as Int32;
pub const SDL_EVENT_WILL_ENTER_BACKGROUND: Int32  = 259 as Int32;
pub const SDL_EVENT_DID_ENTER_BACKGROUND: Int32   = 260 as Int32;
pub const SDL_EVENT_WILL_ENTER_FOREGROUND: Int32  = 261 as Int32;
pub const SDL_EVENT_DID_ENTER_FOREGROUND: Int32   = 262 as Int32;
pub const SDL_EVENT_LOCALE_CHANGED: Int32         = 263 as Int32;
pub const SDL_EVENT_SYSTEM_THEME_CHANGED: Int32   = 264 as Int32;

pub const SDL_EVENT_DISPLAY_ORIENTATION: Int32        = 337 as Int32;
pub const SDL_EVENT_DISPLAY_ADDED: Int32              = 338 as Int32;
pub const SDL_EVENT_DISPLAY_REMOVED: Int32            = 339 as Int32;
pub const SDL_EVENT_DISPLAY_MOVED: Int32              = 340 as Int32;
pub const SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED: Int32 = 341 as Int32;
pub const SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED: Int32 = 342 as Int32;
pub const SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED: Int32 = 343 as Int32;
pub const SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED: Int32 = 344 as Int32;

pub const SDL_EVENT_WINDOW_SHOWN: Int32                = 514 as Int32;
pub const SDL_EVENT_WINDOW_HIDDEN: Int32               = 515 as Int32;
pub const SDL_EVENT_WINDOW_EXPOSED: Int32              = 516 as Int32;
pub const SDL_EVENT_WINDOW_MOVED: Int32                = 517 as Int32;
pub const SDL_EVENT_WINDOW_RESIZED: Int32              = 518 as Int32;
pub const SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: Int32   = 519 as Int32;
pub const SDL_EVENT_WINDOW_METAL_VIEW_RESIZED: Int32   = 520 as Int32;
pub const SDL_EVENT_WINDOW_MINIMIZED: Int32            = 521 as Int32;
pub const SDL_EVENT_WINDOW_MAXIMIZED: Int32            = 522 as Int32;
pub const SDL_EVENT_WINDOW_RESTORED: Int32             = 523 as Int32;
pub const SDL_EVENT_WINDOW_MOUSE_ENTER: Int32          = 524 as Int32;
pub const SDL_EVENT_WINDOW_MOUSE_LEAVE: Int32          = 525 as Int32;
pub const SDL_EVENT_WINDOW_FOCUS_GAINED: Int32         = 526 as Int32;
pub const SDL_EVENT_WINDOW_FOCUS_LOST: Int32           = 527 as Int32;
pub const SDL_EVENT_WINDOW_CLOSE_REQUESTED: Int32      = 528 as Int32;
pub const SDL_EVENT_WINDOW_HIT_TEST: Int32             = 529 as Int32;
pub const SDL_EVENT_WINDOW_ICCPROF_CHANGED: Int32      = 530 as Int32;
pub const SDL_EVENT_WINDOW_DISPLAY_CHANGED: Int32      = 531 as Int32;
pub const SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: Int32 = 532 as Int32;
pub const SDL_EVENT_WINDOW_SAFE_AREA_CHANGED: Int32    = 533 as Int32;
pub const SDL_EVENT_WINDOW_OCCLUDED: Int32             = 534 as Int32;
pub const SDL_EVENT_WINDOW_ENTER_FULLSCREEN: Int32     = 535 as Int32;
pub const SDL_EVENT_WINDOW_LEAVE_FULLSCREEN: Int32     = 536 as Int32;
pub const SDL_EVENT_WINDOW_DESTROYED: Int32            = 537 as Int32;
pub const SDL_EVENT_WINDOW_HDR_STATE_CHANGED: Int32    = 538 as Int32;

pub const SDL_EVENT_KEY_DOWN: Int32            = 768 as Int32;
pub const SDL_EVENT_KEY_UP: Int32              = 769 as Int32;
pub const SDL_EVENT_TEXT_EDITING: Int32        = 770 as Int32;
pub const SDL_EVENT_TEXT_INPUT: Int32          = 771 as Int32;
pub const SDL_EVENT_KEYMAP_CHANGED: Int32      = 772 as Int32;
pub const SDL_EVENT_KEYBOARD_ADDED: Int32      = 773 as Int32;
pub const SDL_EVENT_KEYBOARD_REMOVED: Int32    = 774 as Int32;
pub const SDL_EVENT_TEXT_EDITING_CANDIDATES: Int32 = 775 as Int32;

pub const SDL_EVENT_MOUSE_MOTION: Int32        = 1024 as Int32;
pub const SDL_EVENT_MOUSE_BUTTON_DOWN: Int32   = 1025 as Int32;
pub const SDL_EVENT_MOUSE_BUTTON_UP: Int32     = 1026 as Int32;
pub const SDL_EVENT_MOUSE_WHEEL: Int32         = 1027 as Int32;
pub const SDL_EVENT_MOUSE_ADDED: Int32         = 1028 as Int32;
pub const SDL_EVENT_MOUSE_REMOVED: Int32       = 1029 as Int32;

pub const SDL_EVENT_JOYSTICK_AXIS_MOTION: Int32  = 1536 as Int32;
pub const SDL_EVENT_JOYSTICK_BALL_MOTION: Int32  = 1537 as Int32;
pub const SDL_EVENT_JOYSTICK_HAT_MOTION: Int32   = 1538 as Int32;
pub const SDL_EVENT_JOYSTICK_BUTTON_DOWN: Int32  = 1539 as Int32;
pub const SDL_EVENT_JOYSTICK_BUTTON_UP: Int32    = 1540 as Int32;
pub const SDL_EVENT_JOYSTICK_ADDED: Int32        = 1541 as Int32;
pub const SDL_EVENT_JOYSTICK_REMOVED: Int32      = 1542 as Int32;
pub const SDL_EVENT_JOYSTICK_BATTERY_UPDATED: Int32 = 1543 as Int32;
pub const SDL_EVENT_JOYSTICK_UPDATE_COMPLETE: Int32 = 1544 as Int32;

pub const SDL_EVENT_GAMEPAD_AXIS_MOTION: Int32   = 1616 as Int32;
pub const SDL_EVENT_GAMEPAD_BUTTON_DOWN: Int32   = 1617 as Int32;
pub const SDL_EVENT_GAMEPAD_BUTTON_UP: Int32     = 1618 as Int32;
pub const SDL_EVENT_GAMEPAD_ADDED: Int32         = 1619 as Int32;
pub const SDL_EVENT_GAMEPAD_REMOVED: Int32       = 1620 as Int32;
pub const SDL_EVENT_GAMEPAD_REMAPPED: Int32      = 1621 as Int32;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN: Int32 = 1622 as Int32;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION: Int32 = 1623 as Int32;
pub const SDL_EVENT_GAMEPAD_TOUCHPAD_UP: Int32   = 1624 as Int32;
pub const SDL_EVENT_GAMEPAD_SENSOR_UPDATE: Int32 = 1625 as Int32;
pub const SDL_EVENT_GAMEPAD_UPDATE_COMPLETE: Int32 = 1626 as Int32;

pub const SDL_EVENT_FINGER_DOWN: Int32   = 1792 as Int32;
pub const SDL_EVENT_FINGER_UP: Int32     = 1793 as Int32;
pub const SDL_EVENT_FINGER_MOTION: Int32 = 1794 as Int32;
pub const SDL_EVENT_FINGER_CANCELED: Int32 = 1795 as Int32;

pub const SDL_EVENT_CLIPBOARD_UPDATE: Int32 = 2304 as Int32;

pub const SDL_EVENT_DROP_FILE: Int32     = 4096 as Int32;
pub const SDL_EVENT_DROP_TEXT: Int32     = 4097 as Int32;
pub const SDL_EVENT_DROP_BEGIN: Int32    = 4098 as Int32;
pub const SDL_EVENT_DROP_COMPLETE: Int32 = 4099 as Int32;
pub const SDL_EVENT_DROP_POSITION: Int32 = 4100 as Int32;

pub const SDL_EVENT_AUDIO_DEVICE_ADDED: Int32          = 4352 as Int32;
pub const SDL_EVENT_AUDIO_DEVICE_REMOVED: Int32        = 4353 as Int32;
pub const SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED: Int32 = 4354 as Int32;

pub const SDL_EVENT_SENSOR_UPDATE: Int32 = 4608 as Int32;

pub const SDL_EVENT_PEN_PROXIMITY_IN: Int32  = 4864 as Int32;
pub const SDL_EVENT_PEN_PROXIMITY_OUT: Int32 = 4865 as Int32;
pub const SDL_EVENT_PEN_DOWN: Int32          = 4866 as Int32;
pub const SDL_EVENT_PEN_UP: Int32            = 4867 as Int32;
pub const SDL_EVENT_PEN_BUTTON_DOWN: Int32   = 4868 as Int32;
pub const SDL_EVENT_PEN_BUTTON_UP: Int32     = 4869 as Int32;
pub const SDL_EVENT_PEN_MOTION: Int32        = 4870 as Int32;
pub const SDL_EVENT_PEN_AXIS: Int32           = 4871 as Int32;

pub const SDL_EVENT_CAMERA_DEVICE_ADDED: Int32    = 5120 as Int32;
pub const SDL_EVENT_CAMERA_DEVICE_REMOVED: Int32  = 5121 as Int32;
pub const SDL_EVENT_CAMERA_DEVICE_APPROVED: Int32 = 5122 as Int32;
pub const SDL_EVENT_CAMERA_DEVICE_DENIED: Int32   = 5123 as Int32;

pub const SDL_EVENT_RENDER_TARGETS_RESET: Int32 = 8192 as Int32;
pub const SDL_EVENT_RENDER_DEVICE_RESET: Int32  = 8193 as Int32;
pub const SDL_EVENT_RENDER_DEVICE_LOST: Int32   = 8194 as Int32;

pub const SDL_EVENT_POLL_SENTINEL: Int32 = 32512 as Int32;
pub const SDL_EVENT_USER: Int32          = 32768 as Int32;
pub const SDL_EVENT_LAST: Int32          = 65535 as Int32;

// =========================================================================
// SDL Scancodes (SDL_Scancode)
// =========================================================================

pub const SDL_SCANCODE_UNKNOWN: Int32 = 0 as Int32;
pub const SDL_SCANCODE_A: Int32 = 4 as Int32;
pub const SDL_SCANCODE_B: Int32 = 5 as Int32;
pub const SDL_SCANCODE_C: Int32 = 6 as Int32;
pub const SDL_SCANCODE_D: Int32 = 7 as Int32;
pub const SDL_SCANCODE_E: Int32 = 8 as Int32;
pub const SDL_SCANCODE_F: Int32 = 9 as Int32;
pub const SDL_SCANCODE_G: Int32 = 10 as Int32;
pub const SDL_SCANCODE_H: Int32 = 11 as Int32;
pub const SDL_SCANCODE_I: Int32 = 12 as Int32;
pub const SDL_SCANCODE_J: Int32 = 13 as Int32;
pub const SDL_SCANCODE_K: Int32 = 14 as Int32;
pub const SDL_SCANCODE_L: Int32 = 15 as Int32;
pub const SDL_SCANCODE_M: Int32 = 16 as Int32;
pub const SDL_SCANCODE_N: Int32 = 17 as Int32;
pub const SDL_SCANCODE_O: Int32 = 18 as Int32;
pub const SDL_SCANCODE_P: Int32 = 19 as Int32;
pub const SDL_SCANCODE_Q: Int32 = 20 as Int32;
pub const SDL_SCANCODE_R: Int32 = 21 as Int32;
pub const SDL_SCANCODE_S: Int32 = 22 as Int32;
pub const SDL_SCANCODE_T: Int32 = 23 as Int32;
pub const SDL_SCANCODE_U: Int32 = 24 as Int32;
pub const SDL_SCANCODE_V: Int32 = 25 as Int32;
pub const SDL_SCANCODE_W: Int32 = 26 as Int32;
pub const SDL_SCANCODE_X: Int32 = 27 as Int32;
pub const SDL_SCANCODE_Y: Int32 = 28 as Int32;
pub const SDL_SCANCODE_Z: Int32 = 29 as Int32;

pub const SDL_SCANCODE_1: Int32 = 30 as Int32;
pub const SDL_SCANCODE_2: Int32 = 31 as Int32;
pub const SDL_SCANCODE_3: Int32 = 32 as Int32;
pub const SDL_SCANCODE_4: Int32 = 33 as Int32;
pub const SDL_SCANCODE_5: Int32 = 34 as Int32;
pub const SDL_SCANCODE_6: Int32 = 35 as Int32;
pub const SDL_SCANCODE_7: Int32 = 36 as Int32;
pub const SDL_SCANCODE_8: Int32 = 37 as Int32;
pub const SDL_SCANCODE_9: Int32 = 38 as Int32;
pub const SDL_SCANCODE_0: Int32 = 39 as Int32;

pub const SDL_SCANCODE_RETURN: Int32    = 40 as Int32;
pub const SDL_SCANCODE_ESCAPE: Int32    = 41 as Int32;
pub const SDL_SCANCODE_BACKSPACE: Int32 = 42 as Int32;
pub const SDL_SCANCODE_TAB: Int32       = 43 as Int32;
pub const SDL_SCANCODE_SPACE: Int32     = 44 as Int32;
pub const SDL_SCANCODE_MINUS: Int32     = 45 as Int32;
pub const SDL_SCANCODE_EQUALS: Int32    = 46 as Int32;
pub const SDL_SCANCODE_LEFTBRACKET: Int32  = 47 as Int32;
pub const SDL_SCANCODE_RIGHTBRACKET: Int32 = 48 as Int32;
pub const SDL_SCANCODE_BACKSLASH: Int32    = 49 as Int32;
pub const SDL_SCANCODE_SEMICOLON: Int32    = 51 as Int32;
pub const SDL_SCANCODE_APOSTROPHE: Int32   = 52 as Int32;
pub const SDL_SCANCODE_GRAVE: Int32        = 53 as Int32;
pub const SDL_SCANCODE_COMMA: Int32        = 54 as Int32;
pub const SDL_SCANCODE_PERIOD: Int32       = 55 as Int32;
pub const SDL_SCANCODE_SLASH: Int32        = 56 as Int32;
pub const SDL_SCANCODE_CAPSLOCK: Int32     = 57 as Int32;

pub const SDL_SCANCODE_F1: Int32  = 58 as Int32;
pub const SDL_SCANCODE_F2: Int32  = 59 as Int32;
pub const SDL_SCANCODE_F3: Int32  = 60 as Int32;
pub const SDL_SCANCODE_F4: Int32  = 61 as Int32;
pub const SDL_SCANCODE_F5: Int32  = 62 as Int32;
pub const SDL_SCANCODE_F6: Int32  = 63 as Int32;
pub const SDL_SCANCODE_F7: Int32  = 64 as Int32;
pub const SDL_SCANCODE_F8: Int32  = 65 as Int32;
pub const SDL_SCANCODE_F9: Int32  = 66 as Int32;
pub const SDL_SCANCODE_F10: Int32 = 67 as Int32;
pub const SDL_SCANCODE_F11: Int32 = 68 as Int32;
pub const SDL_SCANCODE_F12: Int32 = 69 as Int32;

pub const SDL_SCANCODE_PRINTSCREEN: Int32 = 70 as Int32;
pub const SDL_SCANCODE_SCROLLLOCK: Int32  = 71 as Int32;
pub const SDL_SCANCODE_PAUSE: Int32       = 72 as Int32;
pub const SDL_SCANCODE_INSERT: Int32      = 73 as Int32;
pub const SDL_SCANCODE_HOME: Int32        = 74 as Int32;
pub const SDL_SCANCODE_PAGEUP: Int32      = 75 as Int32;
pub const SDL_SCANCODE_DELETE: Int32      = 76 as Int32;
pub const SDL_SCANCODE_END: Int32         = 77 as Int32;
pub const SDL_SCANCODE_PAGEDOWN: Int32    = 78 as Int32;
pub const SDL_SCANCODE_RIGHT: Int32       = 79 as Int32;
pub const SDL_SCANCODE_LEFT: Int32        = 80 as Int32;
pub const SDL_SCANCODE_DOWN: Int32        = 81 as Int32;
pub const SDL_SCANCODE_UP: Int32          = 82 as Int32;

pub const SDL_SCANCODE_LCTRL: Int32  = 224 as Int32;
pub const SDL_SCANCODE_LSHIFT: Int32 = 225 as Int32;
pub const SDL_SCANCODE_LALT: Int32   = 226 as Int32;
pub const SDL_SCANCODE_LGUI: Int32   = 227 as Int32;
pub const SDL_SCANCODE_RCTRL: Int32  = 228 as Int32;
pub const SDL_SCANCODE_RSHIFT: Int32 = 229 as Int32;
pub const SDL_SCANCODE_RALT: Int32   = 230 as Int32;
pub const SDL_SCANCODE_RGUI: Int32   = 231 as Int32;

// =========================================================================
// SDL Texture Access (SDL_TextureAccess)
// =========================================================================

pub const SDL_TEXTUREACCESS_STATIC: Int32    = 0 as Int32;
pub const SDL_TEXTUREACCESS_STREAMING: Int32 = 1 as Int32;
pub const SDL_TEXTUREACCESS_TARGET: Int32    = 2 as Int32;

// =========================================================================
// SDL Renderer Logical Presentation
// =========================================================================

pub const SDL_LOGICAL_PRESENTATION_DISABLED: Int32      = 0 as Int32;
pub const SDL_LOGICAL_PRESENTATION_STRETCH: Int32       = 1 as Int32;
pub const SDL_LOGICAL_PRESENTATION_LETTERBOX: Int32     = 2 as Int32;
pub const SDL_LOGICAL_PRESENTATION_OVERSCAN: Int32      = 3 as Int32;
pub const SDL_LOGICAL_PRESENTATION_INTEGER_SCALE: Int32 = 4 as Int32;

// =========================================================================
// SDL Event struct layout helpers
// SDL_Event is 128 bytes (union with padding[128]).
// The first field in every event is Uint32 type (offset 0, size 4).
// =========================================================================

pub const SDL_EVENT_SIZE: Int32 = 128 as Int32;

// =========================================================================
// FFI: extern C declarations for SDL3 v3.4.8
// =========================================================================

extern "C" {
  // --- SDL_init.h ---
  fn SDL_Init(flags: Int32) -> Int32;
  fn SDL_InitSubSystem(flags: Int32) -> Int32;
  fn SDL_QuitSubSystem(flags: Int32);
  fn SDL_WasInit(flags: Int32) -> Int32;
  fn SDL_Quit();

  // --- SDL_video.h ---
  fn SDL_CreateWindow(title: Int, w: Int32, h: Int32, flags: Int) -> Int;
  fn SDL_CreatePopupWindow(parent: Int, offset_x: Int32, offset_y: Int32, w: Int32, h: Int32, flags: Int) -> Int;
  fn SDL_DestroyWindow(window: Int);
  fn SDL_GetWindowSize(window: Int, w: Int, h: Int) -> Int32;
  fn SDL_GetWindowSizeInPixels(window: Int, w: Int, h: Int) -> Int32;
  fn SDL_SetWindowSize(window: Int, w: Int32, h: Int32) -> Int32;
  fn SDL_SetWindowTitle(window: Int, title: Int) -> Int32;
  fn SDL_GetWindowTitle(window: Int) -> Int;
  fn SDL_GetWindowFlags(window: Int) -> Int;
  fn SDL_GetWindowID(window: Int) -> Int32;
  fn SDL_GetWindowFromID(id: Int32) -> Int;
  fn SDL_ShowWindow(window: Int) -> Int32;
  fn SDL_HideWindow(window: Int) -> Int32;
  fn SDL_RaiseWindow(window: Int) -> Int32;
  fn SDL_MaximizeWindow(window: Int) -> Int32;
  fn SDL_MinimizeWindow(window: Int) -> Int32;
  fn SDL_RestoreWindow(window: Int) -> Int32;
  fn SDL_SetWindowFullscreen(window: Int, fullscreen: Int32) -> Int32;
  fn SDL_SetWindowPosition(window: Int, x: Int32, y: Int32) -> Int32;
  fn SDL_GetWindowPosition(window: Int, x: Int, y: Int) -> Int32;
  fn SDL_GetNumVideoDrivers() -> Int32;
  fn SDL_GetVideoDriver(index: Int32) -> Int;
  fn SDL_GetCurrentVideoDriver() -> Int;
  fn SDL_GetSystemTheme() -> Int32;
  fn SDL_GetDisplays(count: Int) -> Int;
  fn SDL_GetPrimaryDisplay() -> Int32;
  fn SDL_GetDisplayName(displayID: Int32) -> Int;
  fn SDL_GetDisplayBounds(displayID: Int32, rect: Int) -> Int32;
  fn SDL_GetDisplayUsableBounds(displayID: Int32, rect: Int) -> Int32;

  // --- SDL_render.h ---
  fn SDL_CreateWindowAndRenderer(title: Int, width: Int32, height: Int32, window_flags: Int, window: Int, renderer: Int) -> Int32;
  fn SDL_CreateRenderer(window: Int, name: Int) -> Int;
  fn SDL_DestroyRenderer(renderer: Int);
  fn SDL_GetRenderWindow(renderer: Int) -> Int;
  fn SDL_GetRendererName(renderer: Int) -> Int;
  fn SDL_GetNumRenderDrivers() -> Int32;
  fn SDL_GetRenderDriver(index: Int32) -> Int;
  fn SDL_RenderClear(renderer: Int) -> Int32;
  fn SDL_RenderPresent(renderer: Int) -> Int32;
  fn SDL_SetRenderDrawColor(renderer: Int, r: Int32, g: Int32, b: Int32, a: Int32) -> Int32;
  fn SDL_SetRenderDrawColorFloat(renderer: Int, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn SDL_RenderFillRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderPoint(renderer: Int, x: Float32, y: Float32) -> Int32;
  fn SDL_RenderLine(renderer: Int, x1: Float32, y1: Float32, x2: Float32, y2: Float32) -> Int32;
  fn SDL_SetRenderLogicalPresentation(renderer: Int, w: Int32, h: Int32, mode: Int32) -> Int32;
  fn SDL_GetRenderLogicalPresentation(renderer: Int, w: Int, h: Int, mode: Int) -> Int32;
  fn SDL_SetRenderVSync(renderer: Int, vsync: Int32) -> Int32;
  fn SDL_GetRenderOutputSize(renderer: Int, w: Int, h: Int) -> Int32;
  fn SDL_SetRenderScale(renderer: Int, scaleX: Float32, scaleY: Float32) -> Int32;
  fn SDL_GetRenderScale(renderer: Int, scaleX: Int, scaleY: Int) -> Int32;
  fn SDL_SetRenderClipRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_GetRenderClipRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_CreateTexture(renderer: Int, format: Int32, access: Int32, w: Int32, h: Int32) -> Int;
  fn SDL_DestroyTexture(texture: Int);
  fn SDL_GetTextureSize(texture: Int, w: Int, h: Int) -> Int32;
  fn SDL_SetTextureColorMod(texture: Int, r: Int32, g: Int32, b: Int32) -> Int32;
  fn SDL_SetTextureAlphaMod(texture: Int, alpha: Int32) -> Int32;
  fn SDL_RenderTexture(renderer: Int, texture: Int, srcrect: Int, dstrect: Int) -> Int32;

  // --- SDL_events.h ---
  fn SDL_PollEvent(event: Int) -> Int32;
  fn SDL_WaitEvent(event: Int) -> Int32;
  fn SDL_WaitEventTimeout(event: Int, timeoutMS: Int32) -> Int32;
  fn SDL_PumpEvents();
  fn SDL_PushEvent(event: Int) -> Int32;
  fn SDL_PeepEvents(events: Int, numevents: Int32, action: Int32, minType: Int32, maxType: Int32) -> Int32;
  fn SDL_HasEvent(type_: Int32) -> Int32;
  fn SDL_HasEvents(minType: Int32, maxType: Int32) -> Int32;
  fn SDL_FlushEvent(type_: Int32);
  fn SDL_FlushEvents(minType: Int32, maxType: Int32);

  // --- SDL_timer.h ---
  fn SDL_Delay(ms: Int32);
  fn SDL_DelayNS(ns: Int);
  fn SDL_GetTicks() -> Int;
  fn SDL_GetTicksNS() -> Int;
  fn SDL_GetPerformanceCounter() -> Int;
  fn SDL_GetPerformanceFrequency() -> Int;

  // --- SDL_error.h ---
  fn SDL_GetError() -> Int;
  fn SDL_ClearError() -> Int32;
}

// =========================================================================
// Safe wrapper functions — for direct procedural use
// =========================================================================

pub fn init(flags: Int32) -> Bool {
  let res: Int32 = unsafe { SDL_Init(flags) };
  return res == 0;
}

pub fn init_subsystem(flags: Int32) -> Bool {
  let res: Int32 = unsafe { SDL_InitSubSystem(flags) };
  return res == 0;
}

pub fn quit_subsystem(flags: Int32) {
  unsafe { SDL_QuitSubSystem(flags); }
}

pub fn was_init(flags: Int32) -> Int32 {
  return unsafe { SDL_WasInit(flags) };
}

pub fn quit() {
  unsafe { SDL_Quit(); }
}

pub fn create_window(title: Int, w: Int32, h: Int32, flags: Int) -> Result[Int, Str]
  requires: title != 0
{
  let win: Int = unsafe { SDL_CreateWindow(title, w, h, flags) };
  if win == 0 {
    return Err("SDL_CreateWindow failed");
  }
  return Ok(win);
}

pub fn destroy_window(window: Int)
  requires: window != 0
{
  unsafe { SDL_DestroyWindow(window); }
}

pub fn get_window_size(window: Int) -> Result[Int, Str]
  requires: window != 0
{
  let w: Int = 0;
  let h: Int = 0;
  let ok: Int32 = unsafe { SDL_GetWindowSize(window, w, h) };
  if ok == 0 {
    return Err("SDL_GetWindowSize failed");
  }
  return Ok(w);
}

pub fn show_window(window: Int) -> Bool
  requires: window != 0
{
  let res: Int32 = unsafe { SDL_ShowWindow(window) };
  return res != 0;
}

pub fn create_renderer(window: Int) -> Result[Int, Str]
  requires: window != 0
{
  let ren: Int = unsafe { SDL_CreateRenderer(window, 0) };
  if ren == 0 {
    return Err("SDL_CreateRenderer failed");
  }
  return Ok(ren);
}

pub fn create_window_and_renderer(title: Int, width: Int32, height: Int32, window_flags: Int) -> Result[Int, Str]
  requires: title != 0
  requires: width > 0
  requires: height > 0
{
  let win: Int = 0;
  let ren: Int = 0;
  let ok: Int32 = unsafe { SDL_CreateWindowAndRenderer(title, width, height, window_flags, win, ren) };
  if ok == 0 {
    return Err("SDL_CreateWindowAndRenderer failed");
  }
  return Ok(win);
}

pub fn destroy_renderer(renderer: Int)
  requires: renderer != 0
{
  unsafe { SDL_DestroyRenderer(renderer); }
}

pub fn render_clear(renderer: Int) -> Bool
  requires: renderer != 0
{
  let res: Int32 = unsafe { SDL_RenderClear(renderer) };
  return res != 0;
}

pub fn render_present(renderer: Int) -> Bool
  requires: renderer != 0
{
  let res: Int32 = unsafe { SDL_RenderPresent(renderer) };
  return res != 0;
}

pub fn set_render_draw_color(renderer: Int, r: Int32, g: Int32, b: Int32, a: Int32) -> Bool
  requires: renderer != 0
{
  let res: Int32 = unsafe { SDL_SetRenderDrawColor(renderer, r, g, b, a) };
  return res != 0;
}

pub fn render_fill_rect(renderer: Int, rect: Int) -> Bool
  requires: renderer != 0
{
  let res: Int32 = unsafe { SDL_RenderFillRect(renderer, rect) };
  return res != 0;
}

pub fn poll_event(event: Int) -> Bool
  requires: event != 0
{
  let res: Int32 = unsafe { SDL_PollEvent(event) };
  return res != 0;
}

pub fn wait_event(event: Int) -> Bool
  requires: event != 0
{
  let res: Int32 = unsafe { SDL_WaitEvent(event) };
  return res != 0;
}

pub fn pump_events() {
  unsafe { SDL_PumpEvents(); }
}

pub fn delay(ms: Int32) {
  unsafe { SDL_Delay(ms); }
}

pub fn get_ticks() -> Int {
  return unsafe { SDL_GetTicks() };
}

pub fn get_error() -> Int {
  return unsafe { SDL_GetError() };
}

pub fn clear_error() -> Bool {
  let res: Int32 = unsafe { SDL_ClearError() };
  return res != 0;
}

pub fn get_num_video_drivers() -> Int32 {
  return unsafe { SDL_GetNumVideoDrivers() };
}

pub fn get_video_driver(index: Int32) -> Int {
  return unsafe { SDL_GetVideoDriver(index) };
}

pub fn get_current_video_driver() -> Int {
  return unsafe { SDL_GetCurrentVideoDriver() };
}

pub fn get_num_render_drivers() -> Int32 {
  return unsafe { SDL_GetNumRenderDrivers() };
}

pub fn get_render_driver(index: Int32) -> Int {
  return unsafe { SDL_GetRenderDriver(index) };
}

// =========================================================================
// Event type → human-readable string
// =========================================================================

pub fn event_type_to_string(type_: Int32) -> Str {
  if type_ == SDL_EVENT_QUIT                  { return "SDL_EVENT_QUIT"; }
  if type_ == SDL_EVENT_KEY_DOWN              { return "SDL_EVENT_KEY_DOWN"; }
  if type_ == SDL_EVENT_KEY_UP                { return "SDL_EVENT_KEY_UP"; }
  if type_ == SDL_EVENT_MOUSE_MOTION          { return "SDL_EVENT_MOUSE_MOTION"; }
  if type_ == SDL_EVENT_MOUSE_BUTTON_DOWN     { return "SDL_EVENT_MOUSE_BUTTON_DOWN"; }
  if type_ == SDL_EVENT_MOUSE_BUTTON_UP       { return "SDL_EVENT_MOUSE_BUTTON_UP"; }
  if type_ == SDL_EVENT_MOUSE_WHEEL           { return "SDL_EVENT_MOUSE_WHEEL"; }
  if type_ == SDL_EVENT_WINDOW_CLOSE_REQUESTED { return "SDL_EVENT_WINDOW_CLOSE_REQUESTED"; }
  if type_ == SDL_EVENT_WINDOW_RESIZED        { return "SDL_EVENT_WINDOW_RESIZED"; }
  if type_ == SDL_EVENT_WINDOW_MOVED          { return "SDL_EVENT_WINDOW_MOVED"; }
  if type_ == SDL_EVENT_WINDOW_FOCUS_GAINED   { return "SDL_EVENT_WINDOW_FOCUS_GAINED"; }
  if type_ == SDL_EVENT_WINDOW_FOCUS_LOST     { return "SDL_EVENT_WINDOW_FOCUS_LOST"; }
  if type_ == SDL_EVENT_WINDOW_MINIMIZED      { return "SDL_EVENT_WINDOW_MINIMIZED"; }
  if type_ == SDL_EVENT_WINDOW_MAXIMIZED      { return "SDL_EVENT_WINDOW_MAXIMIZED"; }
  if type_ == SDL_EVENT_WINDOW_RESTORED       { return "SDL_EVENT_WINDOW_RESTORED"; }
  if type_ == SDL_EVENT_WINDOW_SHOWN          { return "SDL_EVENT_WINDOW_SHOWN"; }
  if type_ == SDL_EVENT_WINDOW_HIDDEN         { return "SDL_EVENT_WINDOW_HIDDEN"; }
  if type_ == SDL_EVENT_WINDOW_DESTROYED      { return "SDL_EVENT_WINDOW_DESTROYED"; }
  if type_ == SDL_EVENT_RENDER_TARGETS_RESET  { return "SDL_EVENT_RENDER_TARGETS_RESET"; }
  if type_ == SDL_EVENT_RENDER_DEVICE_RESET   { return "SDL_EVENT_RENDER_DEVICE_RESET"; }
  if type_ == SDL_EVENT_RENDER_DEVICE_LOST    { return "SDL_EVENT_RENDER_DEVICE_LOST"; }
  return "SDL_EVENT_UNKNOWN";
}
