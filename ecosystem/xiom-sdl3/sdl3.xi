// XIOM — SDL3 (Simple DirectMedia Layer 3) Production Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for SDL 3.4.8 — full API surface.
// SDL3 is a cross-platform development library for graphics, input, and audio.
//
// Types: all SDL handles/pointers map to Int. Uint32 → Int32, Uint64 → Int,
// int → Int32, float → Float32, C bool → Int32 (0=false, non-zero=true),
// Uint8 → Int32 (0-255), Sint16 → Int32, char* → Int.
//
// Hex literals are supported by xiomc v0.46.0+.
// Naming follows the C API verbatim.

module xiom.sdl3

// =========================================================================
// SDL Init Flags (SDL_InitFlags — Uint32)
// =========================================================================

pub const SDL_INIT_AUDIO: Int32    = 0x00000010 as Int32;
pub const SDL_INIT_VIDEO: Int32    = 0x00000020 as Int32;
pub const SDL_INIT_JOYSTICK: Int32 = 0x00000200 as Int32;
pub const SDL_INIT_HAPTIC: Int32   = 0x00001000 as Int32;
pub const SDL_INIT_GAMEPAD: Int32  = 0x00002000 as Int32;
pub const SDL_INIT_EVENTS: Int32   = 0x00004000 as Int32;
pub const SDL_INIT_SENSOR: Int32   = 0x00008000 as Int32;
pub const SDL_INIT_CAMERA: Int32   = 0x00010000 as Int32;

// =========================================================================
// SDL Window Flags (SDL_WindowFlags — Uint64 → Int)
// =========================================================================

pub const SDL_WINDOW_FULLSCREEN: Int           = 0x0000000000000001;
pub const SDL_WINDOW_OPENGL: Int               = 0x0000000000000002;
pub const SDL_WINDOW_OCCLUDED: Int             = 0x0000000000000004;
pub const SDL_WINDOW_HIDDEN: Int               = 0x0000000000000008;
pub const SDL_WINDOW_BORDERLESS: Int           = 0x0000000000000010;
pub const SDL_WINDOW_RESIZABLE: Int            = 0x0000000000000020;
pub const SDL_WINDOW_MINIMIZED: Int            = 0x0000000000000040;
pub const SDL_WINDOW_MAXIMIZED: Int            = 0x0000000000000080;
pub const SDL_WINDOW_MOUSE_GRABBED: Int        = 0x0000000000000100;
pub const SDL_WINDOW_INPUT_FOCUS: Int          = 0x0000000000000200;
pub const SDL_WINDOW_MOUSE_FOCUS: Int          = 0x0000000000000400;
pub const SDL_WINDOW_EXTERNAL: Int             = 0x0000000000000800;
pub const SDL_WINDOW_MODAL: Int                = 0x0000000000001000;
pub const SDL_WINDOW_HIGH_PIXEL_DENSITY: Int   = 0x0000000000002000;
pub const SDL_WINDOW_MOUSE_CAPTURE: Int        = 0x0000000000004000;
pub const SDL_WINDOW_MOUSE_RELATIVE_MODE: Int  = 0x0000000000008000;
pub const SDL_WINDOW_ALWAYS_ON_TOP: Int        = 0x0000000000010000;
pub const SDL_WINDOW_UTILITY: Int              = 0x0000000000020000;
pub const SDL_WINDOW_TOOLTIP: Int              = 0x0000000000040000;
pub const SDL_WINDOW_POPUP_MENU: Int           = 0x0000000000080000;
pub const SDL_WINDOW_KEYBOARD_GRABBED: Int     = 0x0000000000100000;
pub const SDL_WINDOW_VULKAN: Int               = 0x0000000010000000;
pub const SDL_WINDOW_METAL: Int                = 0x0000000020000000;
pub const SDL_WINDOW_TRANSPARENT: Int          = 0x0000000040000000;
pub const SDL_WINDOW_NOT_FOCUSABLE: Int        = 0x0000000080000000;

pub const SDL_WINDOWPOS_UNDEFINED_MASK: Int32 = 0x1FFF0000 as Int32;
pub const SDL_WINDOWPOS_CENTERED_MASK: Int32  = 0x2FFF0000 as Int32;
pub const SDL_WINDOWPOS_UNDEFINED: Int32       = 0x1FFF0000 as Int32;
pub const SDL_WINDOWPOS_CENTERED: Int32        = 0x2FFF0000 as Int32;

// =========================================================================
// SDL Pixel Formats (SDL_PixelFormat)
// =========================================================================

pub const SDL_PIXELFORMAT_UNKNOWN: Int32       = 0x00000000 as Int32;
pub const SDL_PIXELFORMAT_INDEX1LSB: Int32     = 0x11100100 as Int32;
pub const SDL_PIXELFORMAT_INDEX1MSB: Int32     = 0x11200100 as Int32;
pub const SDL_PIXELFORMAT_INDEX4LSB: Int32     = 0x12100400 as Int32;
pub const SDL_PIXELFORMAT_INDEX4MSB: Int32     = 0x12200400 as Int32;
pub const SDL_PIXELFORMAT_INDEX8: Int32        = 0x13000801 as Int32;
pub const SDL_PIXELFORMAT_RGB332: Int32        = 0x14110801 as Int32;
pub const SDL_PIXELFORMAT_XRGB4444: Int32      = 0x15120c02 as Int32;
pub const SDL_PIXELFORMAT_XBGR4444: Int32      = 0x15520c02 as Int32;
pub const SDL_PIXELFORMAT_XRGB1555: Int32      = 0x15130f02 as Int32;
pub const SDL_PIXELFORMAT_XBGR1555: Int32      = 0x15530f02 as Int32;
pub const SDL_PIXELFORMAT_ARGB4444: Int32      = 0x15321002 as Int32;
pub const SDL_PIXELFORMAT_RGBA4444: Int32      = 0x15421002 as Int32;
pub const SDL_PIXELFORMAT_ABGR4444: Int32      = 0x15721002 as Int32;
pub const SDL_PIXELFORMAT_BGRA4444: Int32      = 0x15821002 as Int32;
pub const SDL_PIXELFORMAT_ARGB1555: Int32      = 0x15331002 as Int32;
pub const SDL_PIXELFORMAT_RGBA5551: Int32      = 0x15441002 as Int32;
pub const SDL_PIXELFORMAT_ABGR1555: Int32      = 0x15731002 as Int32;
pub const SDL_PIXELFORMAT_BGRA5551: Int32      = 0x15841002 as Int32;
pub const SDL_PIXELFORMAT_RGB565: Int32        = 0x15151002 as Int32;
pub const SDL_PIXELFORMAT_BGR565: Int32        = 0x15551002 as Int32;
pub const SDL_PIXELFORMAT_RGB24: Int32         = 0x17101803 as Int32;
pub const SDL_PIXELFORMAT_BGR24: Int32         = 0x17401803 as Int32;
pub const SDL_PIXELFORMAT_XRGB8888: Int32      = 0x16161804 as Int32;
pub const SDL_PIXELFORMAT_RGBX8888: Int32      = 0x16261804 as Int32;
pub const SDL_PIXELFORMAT_XBGR8888: Int32      = 0x16561804 as Int32;
pub const SDL_PIXELFORMAT_BGRX8888: Int32      = 0x16661804 as Int32;
pub const SDL_PIXELFORMAT_ARGB8888: Int32      = 0x16362004 as Int32;
pub const SDL_PIXELFORMAT_RGBA8888: Int32      = 0x16462004 as Int32;
pub const SDL_PIXELFORMAT_ABGR8888: Int32      = 0x16762004 as Int32;
pub const SDL_PIXELFORMAT_BGRA8888: Int32      = 0x16862004 as Int32;

// =========================================================================
// SDL Texture Access (SDL_TextureAccess)
// =========================================================================

pub const SDL_TEXTUREACCESS_STATIC: Int32    = 0 as Int32;
pub const SDL_TEXTUREACCESS_STREAMING: Int32 = 1 as Int32;
pub const SDL_TEXTUREACCESS_TARGET: Int32    = 2 as Int32;

// =========================================================================
// SDL Scale Mode / Flip Mode
// =========================================================================

pub const SDL_SCALEMODE_INVALID: Int32 = -1 as Int32;
pub const SDL_SCALEMODE_NEAREST: Int32 = 0 as Int32;
pub const SDL_SCALEMODE_LINEAR: Int32  = 1 as Int32;
pub const SDL_SCALEMODE_PIXELART: Int32 = 2 as Int32;

pub const SDL_FLIP_NONE: Int32 = 0 as Int32;
pub const SDL_FLIP_HORIZONTAL: Int32 = 1 as Int32;
pub const SDL_FLIP_VERTICAL: Int32 = 2 as Int32;

// =========================================================================
// SDL Blend Mode (SDL_BlendMode)
// =========================================================================

pub const SDL_BLENDMODE_NONE: Int32                = 0x00000000 as Int32;
pub const SDL_BLENDMODE_BLEND: Int32               = 0x00000001 as Int32;
pub const SDL_BLENDMODE_BLEND_PREMULTIPLIED: Int32 = 0x00000010 as Int32;
pub const SDL_BLENDMODE_ADD: Int32                 = 0x00000002 as Int32;
pub const SDL_BLENDMODE_ADD_PREMULTIPLIED: Int32   = 0x00000020 as Int32;
pub const SDL_BLENDMODE_MOD: Int32                 = 0x00000004 as Int32;
pub const SDL_BLENDMODE_MUL: Int32                 = 0x00000008 as Int32;
pub const SDL_BLENDMODE_INVALID: Int32             = 0x7FFFFFFF as Int32;

// =========================================================================
// SDL Event Types (SDL_EventType)
// =========================================================================

pub const SDL_EVENT_FIRST: Int32 = 0 as Int32;

pub const SDL_EVENT_QUIT: Int32                  = 0x100 as Int32;
pub const SDL_EVENT_TERMINATING: Int32            = 0x101 as Int32;
pub const SDL_EVENT_LOW_MEMORY: Int32             = 0x102 as Int32;
pub const SDL_EVENT_WILL_ENTER_BACKGROUND: Int32  = 0x103 as Int32;
pub const SDL_EVENT_DID_ENTER_BACKGROUND: Int32   = 0x104 as Int32;
pub const SDL_EVENT_WILL_ENTER_FOREGROUND: Int32  = 0x105 as Int32;
pub const SDL_EVENT_DID_ENTER_FOREGROUND: Int32   = 0x106 as Int32;
pub const SDL_EVENT_LOCALE_CHANGED: Int32         = 0x107 as Int32;
pub const SDL_EVENT_SYSTEM_THEME_CHANGED: Int32   = 0x108 as Int32;

pub const SDL_EVENT_DISPLAY_ORIENTATION: Int32        = 0x151 as Int32;
pub const SDL_EVENT_DISPLAY_ADDED: Int32              = 0x152 as Int32;
pub const SDL_EVENT_DISPLAY_REMOVED: Int32            = 0x153 as Int32;
pub const SDL_EVENT_DISPLAY_MOVED: Int32              = 0x154 as Int32;
pub const SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED: Int32 = 0x155 as Int32;
pub const SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED: Int32 = 0x156 as Int32;
pub const SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED: Int32 = 0x157 as Int32;
pub const SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED: Int32 = 0x158 as Int32;

pub const SDL_EVENT_WINDOW_SHOWN: Int32                = 0x202 as Int32;
pub const SDL_EVENT_WINDOW_HIDDEN: Int32               = 0x203 as Int32;
pub const SDL_EVENT_WINDOW_EXPOSED: Int32              = 0x204 as Int32;
pub const SDL_EVENT_WINDOW_MOVED: Int32                = 0x205 as Int32;
pub const SDL_EVENT_WINDOW_RESIZED: Int32              = 0x206 as Int32;
pub const SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: Int32   = 0x207 as Int32;
pub const SDL_EVENT_WINDOW_METAL_VIEW_RESIZED: Int32   = 0x208 as Int32;
pub const SDL_EVENT_WINDOW_MINIMIZED: Int32            = 0x209 as Int32;
pub const SDL_EVENT_WINDOW_MAXIMIZED: Int32            = 0x20A as Int32;
pub const SDL_EVENT_WINDOW_RESTORED: Int32             = 0x20B as Int32;
pub const SDL_EVENT_WINDOW_MOUSE_ENTER: Int32          = 0x20C as Int32;
pub const SDL_EVENT_WINDOW_MOUSE_LEAVE: Int32          = 0x20D as Int32;
pub const SDL_EVENT_WINDOW_FOCUS_GAINED: Int32         = 0x20E as Int32;
pub const SDL_EVENT_WINDOW_FOCUS_LOST: Int32           = 0x20F as Int32;
pub const SDL_EVENT_WINDOW_CLOSE_REQUESTED: Int32      = 0x210 as Int32;
pub const SDL_EVENT_WINDOW_HIT_TEST: Int32             = 0x211 as Int32;
pub const SDL_EVENT_WINDOW_ICCPROF_CHANGED: Int32      = 0x212 as Int32;
pub const SDL_EVENT_WINDOW_DISPLAY_CHANGED: Int32      = 0x213 as Int32;
pub const SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED: Int32 = 0x214 as Int32;
pub const SDL_EVENT_WINDOW_SAFE_AREA_CHANGED: Int32    = 0x215 as Int32;
pub const SDL_EVENT_WINDOW_OCCLUDED: Int32             = 0x216 as Int32;
pub const SDL_EVENT_WINDOW_ENTER_FULLSCREEN: Int32     = 0x217 as Int32;
pub const SDL_EVENT_WINDOW_LEAVE_FULLSCREEN: Int32     = 0x218 as Int32;
pub const SDL_EVENT_WINDOW_DESTROYED: Int32            = 0x219 as Int32;
pub const SDL_EVENT_WINDOW_HDR_STATE_CHANGED: Int32    = 0x21A as Int32;

pub const SDL_EVENT_KEY_DOWN: Int32            = 0x300 as Int32;
pub const SDL_EVENT_KEY_UP: Int32              = 0x301 as Int32;
pub const SDL_EVENT_TEXT_EDITING: Int32        = 0x302 as Int32;
pub const SDL_EVENT_TEXT_INPUT: Int32          = 0x303 as Int32;
pub const SDL_EVENT_KEYMAP_CHANGED: Int32      = 0x304 as Int32;
pub const SDL_EVENT_KEYBOARD_ADDED: Int32      = 0x305 as Int32;
pub const SDL_EVENT_KEYBOARD_REMOVED: Int32    = 0x306 as Int32;
pub const SDL_EVENT_TEXT_EDITING_CANDIDATES: Int32 = 0x307 as Int32;

pub const SDL_EVENT_MOUSE_MOTION: Int32        = 0x400 as Int32;
pub const SDL_EVENT_MOUSE_BUTTON_DOWN: Int32   = 0x401 as Int32;
pub const SDL_EVENT_MOUSE_BUTTON_UP: Int32     = 0x402 as Int32;
pub const SDL_EVENT_MOUSE_WHEEL: Int32         = 0x403 as Int32;
pub const SDL_EVENT_MOUSE_ADDED: Int32         = 0x404 as Int32;
pub const SDL_EVENT_MOUSE_REMOVED: Int32       = 0x405 as Int32;

pub const SDL_EVENT_JOYSTICK_AXIS_MOTION: Int32  = 0x600 as Int32;
pub const SDL_EVENT_JOYSTICK_BALL_MOTION: Int32  = 0x601 as Int32;
pub const SDL_EVENT_JOYSTICK_HAT_MOTION: Int32   = 0x602 as Int32;
pub const SDL_EVENT_JOYSTICK_BUTTON_DOWN: Int32  = 0x603 as Int32;
pub const SDL_EVENT_JOYSTICK_BUTTON_UP: Int32    = 0x604 as Int32;
pub const SDL_EVENT_JOYSTICK_ADDED: Int32        = 0x605 as Int32;
pub const SDL_EVENT_JOYSTICK_REMOVED: Int32      = 0x606 as Int32;
pub const SDL_EVENT_JOYSTICK_BATTERY_UPDATED: Int32 = 0x607 as Int32;

pub const SDL_EVENT_GAMEPAD_AXIS_MOTION: Int32   = 0x650 as Int32;
pub const SDL_EVENT_GAMEPAD_BUTTON_DOWN: Int32   = 0x651 as Int32;
pub const SDL_EVENT_GAMEPAD_BUTTON_UP: Int32     = 0x652 as Int32;
pub const SDL_EVENT_GAMEPAD_ADDED: Int32         = 0x653 as Int32;
pub const SDL_EVENT_GAMEPAD_REMOVED: Int32       = 0x654 as Int32;
pub const SDL_EVENT_GAMEPAD_REMAPPED: Int32      = 0x655 as Int32;

pub const SDL_EVENT_FINGER_DOWN: Int32   = 0x700 as Int32;
pub const SDL_EVENT_FINGER_UP: Int32     = 0x701 as Int32;
pub const SDL_EVENT_FINGER_MOTION: Int32 = 0x702 as Int32;

pub const SDL_EVENT_CLIPBOARD_UPDATE: Int32 = 0x900 as Int32;

pub const SDL_EVENT_DROP_FILE: Int32     = 0x1000 as Int32;
pub const SDL_EVENT_DROP_TEXT: Int32     = 0x1001 as Int32;

pub const SDL_EVENT_AUDIO_DEVICE_ADDED: Int32          = 0x1100 as Int32;
pub const SDL_EVENT_AUDIO_DEVICE_REMOVED: Int32        = 0x1101 as Int32;

pub const SDL_EVENT_SENSOR_UPDATE: Int32 = 0x1200 as Int32;

pub const SDL_EVENT_PEN_PROXIMITY_IN: Int32  = 0x1300 as Int32;
pub const SDL_EVENT_PEN_PROXIMITY_OUT: Int32 = 0x1301 as Int32;
pub const SDL_EVENT_PEN_DOWN: Int32          = 0x1302 as Int32;
pub const SDL_EVENT_PEN_UP: Int32            = 0x1303 as Int32;
pub const SDL_EVENT_PEN_BUTTON_DOWN: Int32   = 0x1304 as Int32;
pub const SDL_EVENT_PEN_BUTTON_UP: Int32     = 0x1305 as Int32;
pub const SDL_EVENT_PEN_MOTION: Int32        = 0x1306 as Int32;
pub const SDL_EVENT_PEN_AXIS: Int32          = 0x1307 as Int32;

pub const SDL_EVENT_CAMERA_DEVICE_ADDED: Int32    = 0x1400 as Int32;
pub const SDL_EVENT_CAMERA_DEVICE_REMOVED: Int32  = 0x1401 as Int32;

pub const SDL_EVENT_RENDER_TARGETS_RESET: Int32 = 0x2000 as Int32;
pub const SDL_EVENT_RENDER_DEVICE_RESET: Int32  = 0x2001 as Int32;
pub const SDL_EVENT_RENDER_DEVICE_LOST: Int32   = 0x2002 as Int32;

pub const SDL_EVENT_POLL_SENTINEL: Int32 = 0x7F00 as Int32;
pub const SDL_EVENT_USER: Int32          = 0x8000 as Int32;
pub const SDL_EVENT_LAST: Int32          = 0xFFFF as Int32;

pub const SDL_EVENT_SIZE: Int32 = 128 as Int32;

// =========================================================================
// SDL Scancodes (SDL_Scancode)
// =========================================================================

pub const SDL_SCANCODE_UNKNOWN: Int32 = 0 as Int32;
pub const SDL_SCANCODE_A: Int32 = 4 as Int32;  pub const SDL_SCANCODE_B: Int32 = 5 as Int32;
pub const SDL_SCANCODE_C: Int32 = 6 as Int32;  pub const SDL_SCANCODE_D: Int32 = 7 as Int32;
pub const SDL_SCANCODE_E: Int32 = 8 as Int32;  pub const SDL_SCANCODE_F: Int32 = 9 as Int32;
pub const SDL_SCANCODE_G: Int32 = 10 as Int32; pub const SDL_SCANCODE_H: Int32 = 11 as Int32;
pub const SDL_SCANCODE_I: Int32 = 12 as Int32; pub const SDL_SCANCODE_J: Int32 = 13 as Int32;
pub const SDL_SCANCODE_K: Int32 = 14 as Int32; pub const SDL_SCANCODE_L: Int32 = 15 as Int32;
pub const SDL_SCANCODE_M: Int32 = 16 as Int32; pub const SDL_SCANCODE_N: Int32 = 17 as Int32;
pub const SDL_SCANCODE_O: Int32 = 18 as Int32; pub const SDL_SCANCODE_P: Int32 = 19 as Int32;
pub const SDL_SCANCODE_Q: Int32 = 20 as Int32; pub const SDL_SCANCODE_R: Int32 = 21 as Int32;
pub const SDL_SCANCODE_S: Int32 = 22 as Int32; pub const SDL_SCANCODE_T: Int32 = 23 as Int32;
pub const SDL_SCANCODE_U: Int32 = 24 as Int32; pub const SDL_SCANCODE_V: Int32 = 25 as Int32;
pub const SDL_SCANCODE_W: Int32 = 26 as Int32; pub const SDL_SCANCODE_X: Int32 = 27 as Int32;
pub const SDL_SCANCODE_Y: Int32 = 28 as Int32; pub const SDL_SCANCODE_Z: Int32 = 29 as Int32;
pub const SDL_SCANCODE_1: Int32 = 30 as Int32; pub const SDL_SCANCODE_2: Int32 = 31 as Int32;
pub const SDL_SCANCODE_3: Int32 = 32 as Int32; pub const SDL_SCANCODE_4: Int32 = 33 as Int32;
pub const SDL_SCANCODE_5: Int32 = 34 as Int32; pub const SDL_SCANCODE_6: Int32 = 35 as Int32;
pub const SDL_SCANCODE_7: Int32 = 36 as Int32; pub const SDL_SCANCODE_8: Int32 = 37 as Int32;
pub const SDL_SCANCODE_9: Int32 = 38 as Int32; pub const SDL_SCANCODE_0: Int32 = 39 as Int32;
pub const SDL_SCANCODE_RETURN: Int32 = 40 as Int32;    pub const SDL_SCANCODE_ESCAPE: Int32 = 41 as Int32;
pub const SDL_SCANCODE_BACKSPACE: Int32 = 42 as Int32; pub const SDL_SCANCODE_TAB: Int32 = 43 as Int32;
pub const SDL_SCANCODE_SPACE: Int32 = 44 as Int32;     pub const SDL_SCANCODE_MINUS: Int32 = 45 as Int32;
pub const SDL_SCANCODE_EQUALS: Int32 = 46 as Int32;
pub const SDL_SCANCODE_CAPSLOCK: Int32 = 57 as Int32;
pub const SDL_SCANCODE_F1: Int32 = 58 as Int32;  pub const SDL_SCANCODE_F2: Int32 = 59 as Int32;
pub const SDL_SCANCODE_F3: Int32 = 60 as Int32;  pub const SDL_SCANCODE_F4: Int32 = 61 as Int32;
pub const SDL_SCANCODE_F5: Int32 = 62 as Int32;  pub const SDL_SCANCODE_F6: Int32 = 63 as Int32;
pub const SDL_SCANCODE_F7: Int32 = 64 as Int32;  pub const SDL_SCANCODE_F8: Int32 = 65 as Int32;
pub const SDL_SCANCODE_F9: Int32 = 66 as Int32;  pub const SDL_SCANCODE_F10: Int32 = 67 as Int32;
pub const SDL_SCANCODE_F11: Int32 = 68 as Int32; pub const SDL_SCANCODE_F12: Int32 = 69 as Int32;
pub const SDL_SCANCODE_INSERT: Int32 = 73 as Int32;    pub const SDL_SCANCODE_HOME: Int32 = 74 as Int32;
pub const SDL_SCANCODE_PAGEUP: Int32 = 75 as Int32;    pub const SDL_SCANCODE_DELETE: Int32 = 76 as Int32;
pub const SDL_SCANCODE_END: Int32 = 77 as Int32;       pub const SDL_SCANCODE_PAGEDOWN: Int32 = 78 as Int32;
pub const SDL_SCANCODE_RIGHT: Int32 = 79 as Int32;     pub const SDL_SCANCODE_LEFT: Int32 = 80 as Int32;
pub const SDL_SCANCODE_DOWN: Int32 = 81 as Int32;      pub const SDL_SCANCODE_UP: Int32 = 82 as Int32;
pub const SDL_SCANCODE_LCTRL: Int32 = 224 as Int32;    pub const SDL_SCANCODE_LSHIFT: Int32 = 225 as Int32;
pub const SDL_SCANCODE_LALT: Int32 = 226 as Int32;     pub const SDL_SCANCODE_LGUI: Int32 = 227 as Int32;
pub const SDL_SCANCODE_RCTRL: Int32 = 228 as Int32;    pub const SDL_SCANCODE_RSHIFT: Int32 = 229 as Int32;
pub const SDL_SCANCODE_RALT: Int32 = 230 as Int32;     pub const SDL_SCANCODE_RGUI: Int32 = 231 as Int32;

// =========================================================================
// SDL Log Priority / Category
// =========================================================================

pub const SDL_LOG_PRIORITY_TRACE: Int32    = 1 as Int32;
pub const SDL_LOG_PRIORITY_VERBOSE: Int32  = 2 as Int32;
pub const SDL_LOG_PRIORITY_DEBUG: Int32    = 3 as Int32;
pub const SDL_LOG_PRIORITY_INFO: Int32     = 4 as Int32;
pub const SDL_LOG_PRIORITY_WARN: Int32     = 5 as Int32;
pub const SDL_LOG_PRIORITY_ERROR: Int32    = 6 as Int32;
pub const SDL_LOG_PRIORITY_CRITICAL: Int32 = 7 as Int32;

pub const SDL_LOG_CATEGORY_APPLICATION: Int32 = 0 as Int32;
pub const SDL_LOG_CATEGORY_ERROR: Int32       = 1 as Int32;
pub const SDL_LOG_CATEGORY_SYSTEM: Int32      = 3 as Int32;
pub const SDL_LOG_CATEGORY_AUDIO: Int32       = 4 as Int32;
pub const SDL_LOG_CATEGORY_VIDEO: Int32       = 5 as Int32;
pub const SDL_LOG_CATEGORY_RENDER: Int32      = 6 as Int32;
pub const SDL_LOG_CATEGORY_INPUT: Int32       = 7 as Int32;

// =========================================================================
// SDL Power State
// =========================================================================

pub const SDL_POWERSTATE_ERROR: Int32       = -1 as Int32;
pub const SDL_POWERSTATE_UNKNOWN: Int32     = 0 as Int32;
pub const SDL_POWERSTATE_ON_BATTERY: Int32  = 1 as Int32;
pub const SDL_POWERSTATE_NO_BATTERY: Int32  = 2 as Int32;
pub const SDL_POWERSTATE_CHARGING: Int32    = 3 as Int32;
pub const SDL_POWERSTATE_CHARGED: Int32     = 4 as Int32;

// =========================================================================
// SDL Mouse Button Constants
// =========================================================================

pub const SDL_BUTTON_LEFT: Int32   = 1 as Int32;
pub const SDL_BUTTON_MIDDLE: Int32 = 2 as Int32;
pub const SDL_BUTTON_RIGHT: Int32  = 3 as Int32;
pub const SDL_BUTTON_X1: Int32     = 4 as Int32;
pub const SDL_BUTTON_X2: Int32     = 5 as Int32;

pub const SDL_BUTTON_LMASK: Int32  = 0x0001 as Int32;
pub const SDL_BUTTON_MMASK: Int32  = 0x0002 as Int32;
pub const SDL_BUTTON_RMASK: Int32  = 0x0004 as Int32;
pub const SDL_BUTTON_X1MASK: Int32 = 0x0008 as Int32;
pub const SDL_BUTTON_X2MASK: Int32 = 0x0010 as Int32;

// =========================================================================
// SDL System Cursor
// =========================================================================

pub const SDL_SYSTEM_CURSOR_DEFAULT: Int32      = 0 as Int32;
pub const SDL_SYSTEM_CURSOR_TEXT: Int32         = 1 as Int32;
pub const SDL_SYSTEM_CURSOR_WAIT: Int32         = 2 as Int32;
pub const SDL_SYSTEM_CURSOR_CROSSHAIR: Int32    = 3 as Int32;
pub const SDL_SYSTEM_CURSOR_PROGRESS: Int32     = 4 as Int32;
pub const SDL_SYSTEM_CURSOR_NWSE_RESIZE: Int32  = 5 as Int32;
pub const SDL_SYSTEM_CURSOR_NESW_RESIZE: Int32  = 6 as Int32;
pub const SDL_SYSTEM_CURSOR_EW_RESIZE: Int32    = 7 as Int32;
pub const SDL_SYSTEM_CURSOR_NS_RESIZE: Int32    = 8 as Int32;
pub const SDL_SYSTEM_CURSOR_MOVE: Int32         = 9 as Int32;
pub const SDL_SYSTEM_CURSOR_NOT_ALLOWED: Int32  = 10 as Int32;
pub const SDL_SYSTEM_CURSOR_POINTER: Int32      = 11 as Int32;

// =========================================================================
// SDL Message Box Flags
// =========================================================================

pub const SDL_MESSAGEBOX_ERROR: Int32       = 0x00000010 as Int32;
pub const SDL_MESSAGEBOX_WARNING: Int32     = 0x00000020 as Int32;
pub const SDL_MESSAGEBOX_INFORMATION: Int32 = 0x00000040 as Int32;

// =========================================================================
// SDL Audio Format Constants
// =========================================================================

pub const SDL_AUDIO_U8: Int32    = 0x0008 as Int32;
pub const SDL_AUDIO_S8: Int32    = 0x8008 as Int32;
pub const SDL_AUDIO_S16LE: Int32 = 0x8010 as Int32;
pub const SDL_AUDIO_S32LE: Int32 = 0x8020 as Int32;
pub const SDL_AUDIO_F32LE: Int32 = 0x8120 as Int32;
pub const SDL_AUDIO_S16: Int32   = 0x8010 as Int32;
pub const SDL_AUDIO_S32: Int32   = 0x8020 as Int32;
pub const SDL_AUDIO_F32: Int32   = 0x8120 as Int32;

pub const SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK: Int32  = 0xFFFFFFFF as Int32;
pub const SDL_AUDIO_DEVICE_DEFAULT_RECORDING: Int32 = 0xFFFFFFFE as Int32;

// =========================================================================
// SDL Gamepad Constants
// =========================================================================

pub const SDL_GAMEPAD_BUTTON_INVALID: Int32 = -1 as Int32;
pub const SDL_GAMEPAD_BUTTON_SOUTH: Int32 = 0 as Int32;
pub const SDL_GAMEPAD_BUTTON_EAST: Int32 = 1 as Int32;
pub const SDL_GAMEPAD_BUTTON_WEST: Int32 = 2 as Int32;
pub const SDL_GAMEPAD_BUTTON_NORTH: Int32 = 3 as Int32;
pub const SDL_GAMEPAD_BUTTON_BACK: Int32 = 4 as Int32;
pub const SDL_GAMEPAD_BUTTON_GUIDE: Int32 = 5 as Int32;
pub const SDL_GAMEPAD_BUTTON_START: Int32 = 6 as Int32;
pub const SDL_GAMEPAD_BUTTON_LEFT_STICK: Int32 = 7 as Int32;
pub const SDL_GAMEPAD_BUTTON_RIGHT_STICK: Int32 = 8 as Int32;
pub const SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: Int32 = 9 as Int32;
pub const SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: Int32 = 10 as Int32;
pub const SDL_GAMEPAD_BUTTON_DPAD_UP: Int32 = 11 as Int32;
pub const SDL_GAMEPAD_BUTTON_DPAD_DOWN: Int32 = 12 as Int32;
pub const SDL_GAMEPAD_BUTTON_DPAD_LEFT: Int32 = 13 as Int32;
pub const SDL_GAMEPAD_BUTTON_DPAD_RIGHT: Int32 = 14 as Int32;

pub const SDL_GAMEPAD_AXIS_INVALID: Int32 = -1 as Int32;
pub const SDL_GAMEPAD_AXIS_LEFTX: Int32 = 0 as Int32;
pub const SDL_GAMEPAD_AXIS_LEFTY: Int32 = 1 as Int32;
pub const SDL_GAMEPAD_AXIS_RIGHTX: Int32 = 2 as Int32;
pub const SDL_GAMEPAD_AXIS_RIGHTY: Int32 = 3 as Int32;
pub const SDL_GAMEPAD_AXIS_LEFT_TRIGGER: Int32 = 4 as Int32;
pub const SDL_GAMEPAD_AXIS_RIGHT_TRIGGER: Int32 = 5 as Int32;

pub const SDL_GAMEPAD_TYPE_UNKNOWN: Int32 = 0 as Int32;
pub const SDL_GAMEPAD_TYPE_XBOX360: Int32 = 2 as Int32;
pub const SDL_GAMEPAD_TYPE_XBOXONE: Int32 = 3 as Int32;
pub const SDL_GAMEPAD_TYPE_PS4: Int32 = 5 as Int32;
pub const SDL_GAMEPAD_TYPE_PS5: Int32 = 6 as Int32;

// =========================================================================
// SDL Touch Device Type
// =========================================================================

pub const SDL_TOUCH_DEVICE_INVALID: Int32 = -1 as Int32;
pub const SDL_TOUCH_DEVICE_DIRECT: Int32 = 0 as Int32;
pub const SDL_TOUCH_DEVICE_INDIRECT_ABSOLUTE: Int32 = 1 as Int32;
pub const SDL_TOUCH_DEVICE_INDIRECT_RELATIVE: Int32 = 2 as Int32;

// =========================================================================
// FFI: full extern C declarations for SDL3 v3.4.8
// =========================================================================

extern "C" {
  // === SDL_init.h ===
  fn SDL_Init(flags: Int32) -> Int32;
  fn SDL_InitSubSystem(flags: Int32) -> Int32;
  fn SDL_QuitSubSystem(flags: Int32);
  fn SDL_WasInit(flags: Int32) -> Int32;
  fn SDL_Quit();
  fn SDL_IsMainThread() -> Int32;
  fn SDL_SetAppMetadata(appname: Int, appversion: Int, appidentifier: Int) -> Int32;

  // === SDL_version.h ===
  fn SDL_GetVersion() -> Int32;
  fn SDL_GetRevision() -> Int;

  // === SDL_error.h ===
  fn SDL_GetError() -> Int;
  fn SDL_ClearError() -> Int32;

  // === SDL_video.h ===
  fn SDL_GetNumVideoDrivers() -> Int32;
  fn SDL_GetVideoDriver(index: Int32) -> Int;
  fn SDL_GetCurrentVideoDriver() -> Int;
  fn SDL_GetSystemTheme() -> Int32;
  fn SDL_GetDisplays(count: Int) -> Int;
  fn SDL_GetPrimaryDisplay() -> Int32;
  fn SDL_GetDisplayName(displayID: Int32) -> Int;
  fn SDL_GetDisplayBounds(displayID: Int32, rect: Int) -> Int32;
  fn SDL_GetDisplayUsableBounds(displayID: Int32, rect: Int) -> Int32;
  fn SDL_GetDisplayProperties(displayID: Int32) -> Int;

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
  fn SDL_SetWindowResizable(window: Int, resizable: Int32) -> Int32;
  fn SDL_SetWindowAlwaysOnTop(window: Int, on_top: Int32) -> Int32;
  fn SDL_SetWindowBordered(window: Int, bordered: Int32) -> Int32;
  fn SDL_GetWindowOpacity(window: Int) -> Float32;
  fn SDL_SetWindowOpacity(window: Int, opacity: Float32) -> Int32;
  fn SDL_GetWindowDisplayScale(window: Int) -> Float32;

  // === SDL_render.h ===
  fn SDL_GetNumRenderDrivers() -> Int32;
  fn SDL_GetRenderDriver(index: Int32) -> Int;
  fn SDL_CreateWindowAndRenderer(title: Int, width: Int32, height: Int32, window_flags: Int, window: Int, renderer: Int) -> Int32;
  fn SDL_CreateRenderer(window: Int, name: Int) -> Int;
  fn SDL_DestroyRenderer(renderer: Int);
  fn SDL_GetRenderWindow(renderer: Int) -> Int;
  fn SDL_GetRendererName(renderer: Int) -> Int;
  fn SDL_GetRenderer(renderer: Int) -> Int;
  fn SDL_RenderClear(renderer: Int) -> Int32;
  fn SDL_RenderPresent(renderer: Int) -> Int32;
  fn SDL_SetRenderDrawColor(renderer: Int, r: Int32, g: Int32, b: Int32, a: Int32) -> Int32;
  fn SDL_SetRenderDrawColorFloat(renderer: Int, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn SDL_GetRenderDrawColor(renderer: Int, r: Int, g: Int, b: Int, a: Int) -> Int32;
  fn SDL_SetRenderDrawBlendMode(renderer: Int, blendMode: Int32) -> Int32;
  fn SDL_GetRenderDrawBlendMode(renderer: Int, blendMode: Int) -> Int32;
  fn SDL_RenderFillRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderPoint(renderer: Int, x: Float32, y: Float32) -> Int32;
  fn SDL_RenderLine(renderer: Int, x1: Float32, y1: Float32, x2: Float32, y2: Float32) -> Int32;
  fn SDL_RenderFillRects(renderer: Int, rects: Int, count: Int32) -> Int32;
  fn SDL_RenderRects(renderer: Int, rects: Int, count: Int32) -> Int32;
  fn SDL_RenderPoints(renderer: Int, points: Int, count: Int32) -> Int32;
  fn SDL_RenderLines(renderer: Int, points: Int, count: Int32) -> Int32;
  fn SDL_SetRenderLogicalPresentation(renderer: Int, w: Int32, h: Int32, mode: Int32) -> Int32;
  fn SDL_GetRenderLogicalPresentation(renderer: Int, w: Int, h: Int, mode: Int) -> Int32;
  fn SDL_SetRenderViewport(renderer: Int, rect: Int) -> Int32;
  fn SDL_GetRenderViewport(renderer: Int, rect: Int) -> Int32;
  fn SDL_SetRenderVSync(renderer: Int, vsync: Int32) -> Int32;
  fn SDL_GetRenderOutputSize(renderer: Int, w: Int, h: Int) -> Int32;
  fn SDL_GetCurrentRenderOutputSize(renderer: Int, w: Int, h: Int) -> Int32;
  fn SDL_SetRenderScale(renderer: Int, scaleX: Float32, scaleY: Float32) -> Int32;
  fn SDL_GetRenderScale(renderer: Int, scaleX: Int, scaleY: Int) -> Int32;
  fn SDL_SetRenderClipRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_GetRenderClipRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderGeometry(renderer: Int, texture: Int, vertices: Int, num_vertices: Int32, indices: Int, num_indices: Int32) -> Int32;
  fn SDL_RenderDebugText(renderer: Int, x: Float32, y: Float32, str: Int) -> Int32;

  fn SDL_CreateTexture(renderer: Int, format: Int32, access: Int32, w: Int32, h: Int32) -> Int;
  fn SDL_CreateTextureFromSurface(renderer: Int, surface: Int) -> Int;
  fn SDL_DestroyTexture(texture: Int);
  fn SDL_GetTextureSize(texture: Int, w: Int, h: Int) -> Int32;
  fn SDL_SetTextureColorMod(texture: Int, r: Int32, g: Int32, b: Int32) -> Int32;
  fn SDL_GetTextureColorMod(texture: Int, r: Int, g: Int, b: Int) -> Int32;
  fn SDL_SetTextureAlphaMod(texture: Int, alpha: Int32) -> Int32;
  fn SDL_GetTextureAlphaMod(texture: Int, alpha: Int) -> Int32;
  fn SDL_SetTextureBlendMode(texture: Int, blendMode: Int32) -> Int32;
  fn SDL_GetTextureBlendMode(texture: Int, blendMode: Int) -> Int32;
  fn SDL_SetTextureScaleMode(texture: Int, scaleMode: Int32) -> Int32;
  fn SDL_GetTextureScaleMode(texture: Int, scaleMode: Int) -> Int32;
  fn SDL_UpdateTexture(texture: Int, rect: Int, pixels: Int, pitch: Int32) -> Int32;
  fn SDL_LockTexture(texture: Int, rect: Int, pixels: Int, pitch: Int) -> Int32;
  fn SDL_UnlockTexture(texture: Int);
  fn SDL_RenderTexture(renderer: Int, texture: Int, srcrect: Int, dstrect: Int) -> Int32;

  // === SDL_events.h ===
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

  // === SDL_timer.h ===
  fn SDL_Delay(ms: Int32);
  fn SDL_DelayNS(ns: Int);
  fn SDL_GetTicks() -> Int;
  fn SDL_GetTicksNS() -> Int;
  fn SDL_GetPerformanceCounter() -> Int;
  fn SDL_GetPerformanceFrequency() -> Int;

  // === SDL_keyboard.h ===
  fn SDL_HasKeyboard() -> Int32;
  fn SDL_GetKeyboards(count: Int) -> Int;
  fn SDL_GetKeyboardNameForID(instance_id: Int32) -> Int;
  fn SDL_GetKeyboardFocus() -> Int;
  fn SDL_GetKeyboardState(numkeys: Int) -> Int;
  fn SDL_ResetKeyboard();
  fn SDL_GetModState() -> Int32;
  fn SDL_SetModState(modstate: Int32);
  fn SDL_GetKeyFromScancode(scancode: Int32, modstate: Int32, key_event: Int32) -> Int32;
  fn SDL_GetScancodeFromKey(key: Int32, modstate: Int) -> Int32;
  fn SDL_GetScancodeName(scancode: Int32) -> Int;
  fn SDL_GetScancodeFromName(name: Int) -> Int32;
  fn SDL_GetKeyName(key: Int32) -> Int;
  fn SDL_GetKeyFromName(name: Int) -> Int32;
  fn SDL_StartTextInput(window: Int) -> Int32;
  fn SDL_TextInputActive(window: Int) -> Int32;
  fn SDL_StopTextInput(window: Int) -> Int32;
  fn SDL_HasScreenKeyboardSupport() -> Int32;
  fn SDL_ScreenKeyboardShown(window: Int) -> Int32;

  // === SDL_mouse.h ===
  fn SDL_HasMouse() -> Int32;
  fn SDL_GetMice(count: Int) -> Int;
  fn SDL_GetMouseNameForID(instance_id: Int32) -> Int;
  fn SDL_GetMouseFocus() -> Int;
  fn SDL_GetMouseState(x: Int, y: Int) -> Int32;
  fn SDL_GetGlobalMouseState(x: Int, y: Int) -> Int32;
  fn SDL_GetRelativeMouseState(x: Int, y: Int) -> Int32;
  fn SDL_WarpMouseInWindow(window: Int, x: Float32, y: Float32);
  fn SDL_WarpMouseGlobal(x: Float32, y: Float32) -> Int32;
  fn SDL_CaptureMouse(enabled: Int32) -> Int32;
  fn SDL_CreateSystemCursor(id: Int32) -> Int;
  fn SDL_SetCursor(cursor: Int) -> Int32;
  fn SDL_GetCursor() -> Int;
  fn SDL_GetDefaultCursor() -> Int;
  fn SDL_DestroyCursor(cursor: Int);
  fn SDL_ShowCursor() -> Int32;
  fn SDL_HideCursor() -> Int32;
  fn SDL_CursorVisible() -> Int32;

  // === SDL_gamepad.h ===
  fn SDL_HasGamepad() -> Int32;
  fn SDL_GetGamepads(count: Int) -> Int;
  fn SDL_IsGamepad(instance_id: Int32) -> Int32;
  fn SDL_GetGamepadNameForID(instance_id: Int32) -> Int;
  fn SDL_OpenGamepad(instance_id: Int32) -> Int;
  fn SDL_GetGamepadFromID(instance_id: Int32) -> Int;
  fn SDL_GetGamepadFromPlayerIndex(player_index: Int32) -> Int;
  fn SDL_GetGamepadID(gamepad: Int) -> Int32;
  fn SDL_GetGamepadName(gamepad: Int) -> Int;
  fn SDL_GetGamepadType(gamepad: Int) -> Int32;
  fn SDL_SetGamepadPlayerIndex(gamepad: Int, player_index: Int32) -> Int32;
  fn SDL_GetGamepadPlayerIndex(gamepad: Int) -> Int32;
  fn SDL_GamepadConnected(gamepad: Int) -> Int32;
  fn SDL_GetGamepadAxis(gamepad: Int, axis: Int32) -> Int32;
  fn SDL_GetGamepadButton(gamepad: Int, button: Int32) -> Int32;
  fn SDL_RumbleGamepad(gamepad: Int, low: Int32, high: Int32, duration: Int32) -> Int32;
  fn SDL_SetGamepadLED(gamepad: Int, r: Int32, g: Int32, b: Int32) -> Int32;
  fn SDL_CloseGamepad(gamepad: Int);

  // === SDL_joystick.h ===
  fn SDL_GetJoysticks(count: Int) -> Int;
  fn SDL_GetJoystickNameForID(instance_id: Int32) -> Int;
  fn SDL_OpenJoystick(instance_id: Int32) -> Int;
  fn SDL_GetJoystickFromID(instance_id: Int32) -> Int;
  fn SDL_GetJoystickID(joystick: Int) -> Int32;
  fn SDL_JoystickConnected(joystick: Int) -> Int32;
  fn SDL_GetJoystickAxis(joystick: Int, axis: Int32) -> Int32;
  fn SDL_GetJoystickButton(joystick: Int, button: Int32) -> Int32;
  fn SDL_CloseJoystick(joystick: Int);

  // === SDL_touch.h ===
  fn SDL_GetTouchDevices(count: Int) -> Int;
  fn SDL_GetTouchDeviceName(touchID: Int) -> Int;
  fn SDL_GetTouchDeviceType(touchID: Int) -> Int32;
  fn SDL_GetTouchFingers(touchID: Int, count: Int) -> Int;

  // === SDL_surface.h ===
  fn SDL_CreateSurface(width: Int32, height: Int32, format: Int32) -> Int;
  fn SDL_DestroySurface(surface: Int);
  fn SDL_LoadBMP(file: Int) -> Int;
  fn SDL_SaveBMP(surface: Int, file: Int) -> Int32;

  // === SDL_pixels.h ===
  fn SDL_GetPixelFormatName(format: Int32) -> Int;

  // === SDL_blendmode.h ===
  fn SDL_ComposeCustomBlendMode(srcColorFactor: Int32, dstColorFactor: Int32, colorOperation: Int32, srcAlphaFactor: Int32, dstAlphaFactor: Int32, alphaOperation: Int32) -> Int32;

  // === SDL_clipboard.h ===
  fn SDL_SetClipboardText(text: Int) -> Int32;
  fn SDL_GetClipboardText() -> Int;
  fn SDL_HasClipboardText() -> Int32;

  // === SDL_log.h ===
  fn SDL_SetLogPriorities(priority: Int32);
  fn SDL_SetLogPriority(category: Int32, priority: Int32);
  fn SDL_GetLogPriority(category: Int32) -> Int32;
  fn SDL_ResetLogPriorities();
  fn SDL_Log(fmt: Int, ...);
  fn SDL_LogMessage(category: Int32, priority: Int32, fmt: Int, ...);

  // === SDL_power.h ===
  fn SDL_GetPowerInfo(seconds: Int, percent: Int) -> Int32;

  // === SDL_messagebox.h ===
  fn SDL_ShowSimpleMessageBox(flags: Int32, title: Int, message: Int, window: Int) -> Int32;

  // === SDL_audio.h ===
  fn SDL_GetNumAudioDrivers() -> Int32;
  fn SDL_GetAudioDriver(index: Int32) -> Int;
  fn SDL_GetCurrentAudioDriver() -> Int;
  fn SDL_GetAudioPlaybackDevices(count: Int) -> Int;
  fn SDL_GetAudioRecordingDevices(count: Int) -> Int;
  fn SDL_GetAudioDeviceName(devid: Int32) -> Int;
  fn SDL_OpenAudioDevice(devid: Int32, spec: Int) -> Int32;
  fn SDL_PauseAudioDevice(devid: Int32) -> Int32;
  fn SDL_ResumeAudioDevice(devid: Int32) -> Int32;
  fn SDL_AudioDevicePaused(devid: Int32) -> Int32;
  fn SDL_CloseAudioDevice(devid: Int32);
  fn SDL_LoadWAV(path: Int, spec: Int, audio_buf: Int, audio_len: Int) -> Int32;
  fn SDL_MixAudio(dst: Int, src: Int, format: Int32, len: Int32, volume: Float32) -> Int32;
  fn SDL_GetAudioFormatName(format: Int32) -> Int;

  // === SDL_hints.h ===
  fn SDL_SetHint(name: Int, value: Int) -> Int32;
  fn SDL_GetHint(name: Int) -> Int;
  fn SDL_SetHintWithPriority(name: Int, value: Int, priority: Int32) -> Int32;
  fn SDL_ResetHint(name: Int) -> Int32;
  fn SDL_ResetHints();

  // === SDL_cpuinfo.h ===
  fn SDL_GetNumLogicalCPUCores() -> Int32;
  fn SDL_GetSystemRAM() -> Int;
  fn SDL_GetSIMDAlignment() -> Int32;
  fn SDL_HasSSE() -> Int32;
  fn SDL_HasSSE2() -> Int32;
  fn SDL_HasSSE3() -> Int32;
  fn SDL_HasSSE41() -> Int32;
  fn SDL_HasSSE42() -> Int32;
  fn SDL_HasAVX() -> Int32;
  fn SDL_HasAVX2() -> Int32;
  fn SDL_HasNEON() -> Int32;
  fn SDL_GetPlatform() -> Int;

  // === SDL_filesystem.h ===
  fn SDL_GetBasePath() -> Int;
  fn SDL_GetPrefPath(org: Int, app: Int) -> Int;

  // === SDL_dialog.h ===
  fn SDL_ShowOpenFileDialog(callback: Int, userdata: Int, window: Int, filters: Int, nfilters: Int32, default_location: Int, allow_many: Int32);
  fn SDL_ShowSaveFileDialog(callback: Int, userdata: Int, window: Int, filters: Int, nfilters: Int32, default_location: Int);
  fn SDL_ShowOpenFolderDialog(callback: Int, userdata: Int, window: Int, default_location: Int, allow_many: Int32);

  // === SDL_guid.h ===
  fn SDL_GUIDToString(guid: Int, pszGUID: Int, cbGUID: Int32);
}

// =========================================================================
// Safe wrapper functions — for direct procedural use
// =========================================================================

pub fn init(flags: Int32) -> Bool
  requires: flags != 0
{
  let res: Int32 = unsafe { SDL_Init(flags) };
  return res != 0;
}

pub fn init_subsystem(flags: Int32) -> Bool
  requires: flags != 0
{
  let res: Int32 = unsafe { SDL_InitSubSystem(flags) };
  return res != 0;
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

pub fn get_version() -> Int32 {
  return unsafe { SDL_GetVersion() };
}

pub fn get_revision() -> Int {
  return unsafe { SDL_GetRevision() };
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

pub fn delay(ms: Int32)
  requires: ms >= 0
{
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

pub fn get_video_driver(index: Int32) -> Int
  requires: index >= 0
{
  return unsafe { SDL_GetVideoDriver(index) };
}

pub fn get_current_video_driver() -> Int {
  return unsafe { SDL_GetCurrentVideoDriver() };
}

pub fn get_num_render_drivers() -> Int32 {
  return unsafe { SDL_GetNumRenderDrivers() };
}

pub fn get_render_driver(index: Int32) -> Int
  requires: index >= 0
{
  return unsafe { SDL_GetRenderDriver(index) };
}

pub fn has_keyboard() -> Bool {
  let res: Int32 = unsafe { SDL_HasKeyboard() };
  return res != 0;
}

pub fn has_mouse() -> Bool {
  let res: Int32 = unsafe { SDL_HasMouse() };
  return res != 0;
}

pub fn has_gamepad() -> Bool {
  let res: Int32 = unsafe { SDL_HasGamepad() };
  return res != 0;
}

pub fn get_platform() -> Int {
  return unsafe { SDL_GetPlatform() };
}

pub fn get_num_cpu_cores() -> Int32 {
  return unsafe { SDL_GetNumLogicalCPUCores() };
}

pub fn get_system_ram() -> Int {
  return unsafe { SDL_GetSystemRAM() };
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
  if type_ == SDL_EVENT_GAMEPAD_BUTTON_DOWN   { return "SDL_EVENT_GAMEPAD_BUTTON_DOWN"; }
  if type_ == SDL_EVENT_GAMEPAD_BUTTON_UP     { return "SDL_EVENT_GAMEPAD_BUTTON_UP"; }
  if type_ == SDL_EVENT_GAMEPAD_AXIS_MOTION   { return "SDL_EVENT_GAMEPAD_AXIS_MOTION"; }
  if type_ == SDL_EVENT_RENDER_TARGETS_RESET  { return "SDL_EVENT_RENDER_TARGETS_RESET"; }
  if type_ == SDL_EVENT_RENDER_DEVICE_RESET   { return "SDL_EVENT_RENDER_DEVICE_RESET"; }
  if type_ == SDL_EVENT_RENDER_DEVICE_LOST    { return "SDL_EVENT_RENDER_DEVICE_LOST"; }
  if type_ == SDL_EVENT_FINGER_DOWN           { return "SDL_EVENT_FINGER_DOWN"; }
  if type_ == SDL_EVENT_FINGER_UP             { return "SDL_EVENT_FINGER_UP"; }
  if type_ == SDL_EVENT_DROP_FILE             { return "SDL_EVENT_DROP_FILE"; }
  if type_ == SDL_EVENT_DROP_TEXT             { return "SDL_EVENT_DROP_TEXT"; }
  return "SDL_EVENT_UNKNOWN";
}
