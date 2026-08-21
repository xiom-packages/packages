// XIOM -- SDL3 Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for SDL 3.4.8.
// All create/destroy pairs with Result[T, Str] + design-by-contract.
//
// COVERAGE: 6 resource types spanning the core SDL3 lifecycle:
//   SdlContext, SdlWindow, SdlRenderer, SdlTexture, SdlGamepad, SdlApp

module xiom.sdl3.safe

extern "C" {
  fn SDL_Init(flags: Int32) -> Int32;
  fn SDL_Quit();
  fn SDL_GetTicks() -> Int;
  fn SDL_Delay(ms: Int32);

  fn SDL_CreateWindow(title: Int, w: Int32, h: Int32, flags: Int) -> Int;
  fn SDL_DestroyWindow(window: Int);
  fn SDL_ShowWindow(window: Int) -> Int32;
  fn SDL_HideWindow(window: Int) -> Int32;
  fn SDL_RaiseWindow(window: Int) -> Int32;
  fn SDL_SetWindowTitle(window: Int, title: Int) -> Int32;
  fn SDL_GetWindowFlags(window: Int) -> Int;
  fn SDL_GetWindowID(window: Int) -> Int32;
  fn SDL_SetWindowFullscreen(window: Int, fullscreen: Int32) -> Int32;
  fn SDL_SetWindowSize(window: Int, w: Int32, h: Int32) -> Int32;

  fn SDL_CreateWindowAndRenderer(title: Int, width: Int32, height: Int32, window_flags: Int, window: Int, renderer: Int) -> Int32;
  fn SDL_CreateRenderer(window: Int, name: Int) -> Int;
  fn SDL_DestroyRenderer(renderer: Int);

  fn SDL_RenderClear(renderer: Int) -> Int32;
  fn SDL_RenderPresent(renderer: Int) -> Int32;
  fn SDL_SetRenderDrawColor(renderer: Int, r: Int32, g: Int32, b: Int32, a: Int32) -> Int32;
  fn SDL_SetRenderDrawColorFloat(renderer: Int, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn SDL_RenderFillRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_SetRenderDrawBlendMode(renderer: Int, blendMode: Int32) -> Int32;
  fn SDL_SetRenderVSync(renderer: Int, vsync: Int32) -> Int32;

  fn SDL_CreateTexture(renderer: Int, format: Int32, access: Int32, w: Int32, h: Int32) -> Int;
  fn SDL_DestroyTexture(texture: Int);
  fn SDL_SetTextureColorMod(texture: Int, r: Int32, g: Int32, b: Int32) -> Int32;
  fn SDL_SetTextureAlphaMod(texture: Int, alpha: Int32) -> Int32;
  fn SDL_SetTextureBlendMode(texture: Int, blendMode: Int32) -> Int32;
  fn SDL_RenderTexture(renderer: Int, texture: Int, srcrect: Int, dstrect: Int) -> Int32;

  fn SDL_PollEvent(event: Int) -> Int32;
  fn SDL_PumpEvents();
  fn SDL_GetError() -> Int;

  fn SDL_OpenGamepad(instance_id: Int32) -> Int;
  fn SDL_CloseGamepad(gamepad: Int);
  fn SDL_GetGamepadButton(gamepad: Int, button: Int32) -> Int32;
  fn SDL_GetGamepadAxis(gamepad: Int, axis: Int32) -> Int32;
  fn SDL_GetGamepadName(gamepad: Int) -> Int;
  fn SDL_GamepadConnected(gamepad: Int) -> Int32;

  fn SDL_SetClipboardText(text: Int) -> Int32;
  fn SDL_GetClipboardText() -> Int;
  fn SDL_HasClipboardText() -> Int32;
}

// =========================================================================
// SdlError
// =========================================================================

pub type SdlError = {
  message: Str;
} derive[Clone]

// =========================================================================
// SdlContext -- global SDL3 lifecycle manager
// =========================================================================

pub type SdlContext = {
  is_init: Bool;
} derive[Clone]

pub fn SdlContext.init(flags: Int32) -> Result[SdlContext, SdlError]
  requires: flags != 0
  ensures: result is Ok => result.unwrap().is_init == true
{
  let res: Int32 = unsafe { SDL_Init(flags) };
  if res == 0 {
    return Err(SdlError{ message: "SDL_Init failed" });
  }
  return Ok(SdlContext{ is_init: true });
}

pub fn SdlContext.quit()
  requires: is_init == true
{
  unsafe { SDL_Quit(); }
}

// =========================================================================
// SdlWindow -- an SDL_Window* resource
// =========================================================================

pub type SdlWindow = {
  handle: Int;
} derive[Clone]

pub fn SdlWindow.create(title: Int, w: Int32, h: Int32, flags: Int) -> Result[SdlWindow, SdlError]
  requires: title != 0
  requires: w > 0
  requires: h > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let win: Int = unsafe { SDL_CreateWindow(title, w, h, flags) };
  if win == 0 {
    return Err(SdlError{ message: "SDL_CreateWindow failed" });
  }
  return Ok(SdlWindow{ handle: win });
}

pub fn SdlWindow.destroy()
  requires: handle != 0
{
  unsafe { SDL_DestroyWindow(handle); }
}

pub fn SdlWindow.show() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_ShowWindow(handle) };
  return res != 0;
}

pub fn SdlWindow.hide() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_HideWindow(handle) };
  return res != 0;
}

pub fn SdlWindow.raise() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_RaiseWindow(handle) };
  return res != 0;
}

pub fn SdlWindow.set_title(title: Int) -> Bool
  requires: handle != 0
  requires: title != 0
{
  let res: Int32 = unsafe { SDL_SetWindowTitle(handle, title) };
  return res != 0;
}

pub fn SdlWindow.set_size(w: Int32, h: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetWindowSize(handle, w, h) };
  return res != 0;
}

pub fn SdlWindow.set_fullscreen(fullscreen: Bool) -> Bool
  requires: handle != 0
{
  let flag: Int32 = 0 as Int32;
  if fullscreen { flag = 1 as Int32; }
  let res: Int32 = unsafe { SDL_SetWindowFullscreen(handle, flag) };
  return res != 0;
}

pub fn SdlWindow.get_flags() -> Int
  requires: handle != 0
{
  return unsafe { SDL_GetWindowFlags(handle) };
}

pub fn SdlWindow.get_id() -> Int32
  requires: handle != 0
{
  return unsafe { SDL_GetWindowID(handle) };
}

// =========================================================================
// SdlRenderer -- an SDL_Renderer* resource
// =========================================================================

pub type SdlRenderer = {
  handle: Int;
} derive[Clone]

pub fn SdlRenderer.create(window_handle: Int) -> Result[SdlRenderer, SdlError]
  requires: window_handle != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let ren: Int = unsafe { SDL_CreateRenderer(window_handle, 0) };
  if ren == 0 {
    return Err(SdlError{ message: "SDL_CreateRenderer failed" });
  }
  return Ok(SdlRenderer{ handle: ren });
}

pub fn SdlRenderer.create_for_window(window: SdlWindow) -> Result[SdlRenderer, SdlError]
  requires: window.handle != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  return SdlRenderer.create(window.handle);
}

pub fn SdlRenderer.destroy()
  requires: handle != 0
{
  unsafe { SDL_DestroyRenderer(handle); }
}

pub fn SdlRenderer.clear() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_RenderClear(handle) };
  return res != 0;
}

pub fn SdlRenderer.present()
  requires: handle != 0
{
  unsafe { SDL_RenderPresent(handle); }
}

pub fn SdlRenderer.set_draw_color(r: Int32, g: Int32, b: Int32, a: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetRenderDrawColor(handle, r, g, b, a) };
  return res != 0;
}

pub fn SdlRenderer.set_draw_color_float(r: Float32, g: Float32, b: Float32, a: Float32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetRenderDrawColorFloat(handle, r, g, b, a) };
  return res != 0;
}

pub fn SdlRenderer.fill_rect(rect_ptr: Int) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_RenderFillRect(handle, rect_ptr) };
  return res != 0;
}

pub fn SdlRenderer.draw_rect(rect_ptr: Int) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_RenderRect(handle, rect_ptr) };
  return res != 0;
}

pub fn SdlRenderer.set_blend_mode(mode: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetRenderDrawBlendMode(handle, mode) };
  return res != 0;
}

pub fn SdlRenderer.set_vsync(vsync: Bool) -> Bool
  requires: handle != 0
{
  let flag: Int32 = 0 as Int32;
  if vsync { flag = 1 as Int32; }
  let res: Int32 = unsafe { SDL_SetRenderVSync(handle, flag) };
  return res != 0;
}

// =========================================================================
// SdlTexture -- an SDL_Texture* resource
// =========================================================================

pub type SdlTexture = {
  handle: Int;
} derive[Clone]

pub fn SdlTexture.create(renderer: Int, format: Int32, access: Int32, w: Int32, h: Int32) -> Result[SdlTexture, SdlError]
  requires: renderer != 0
  requires: w > 0
  requires: h > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let tex: Int = unsafe { SDL_CreateTexture(renderer, format, access, w, h) };
  if tex == 0 {
    return Err(SdlError{ message: "SDL_CreateTexture failed" });
  }
  return Ok(SdlTexture{ handle: tex });
}

pub fn SdlTexture.destroy()
  requires: handle != 0
{
  unsafe { SDL_DestroyTexture(handle); }
}

pub fn SdlTexture.set_color_mod(r: Int32, g: Int32, b: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetTextureColorMod(handle, r, g, b) };
  return res != 0;
}

pub fn SdlTexture.set_alpha_mod(alpha: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetTextureAlphaMod(handle, alpha) };
  return res != 0;
}

pub fn SdlTexture.set_blend_mode(mode: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_SetTextureBlendMode(handle, mode) };
  return res != 0;
}

// =========================================================================
// SdlGamepad -- an SDL_Gamepad* resource
// =========================================================================

pub type SdlGamepad = {
  handle: Int;
} derive[Clone]

pub fn SdlGamepad.open(instance_id: Int32) -> Result[SdlGamepad, SdlError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  let gp: Int = unsafe { SDL_OpenGamepad(instance_id) };
  if gp == 0 {
    return Err(SdlError{ message: "SDL_OpenGamepad failed" });
  }
  return Ok(SdlGamepad{ handle: gp });
}

pub fn SdlGamepad.close()
  requires: handle != 0
{
  unsafe { SDL_CloseGamepad(handle); }
}

pub fn SdlGamepad.get_button(button: Int32) -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_GetGamepadButton(handle, button) };
  return res != 0;
}

pub fn SdlGamepad.get_axis(axis: Int32) -> Int32
  requires: handle != 0
{
  return unsafe { SDL_GetGamepadAxis(handle, axis) };
}

pub fn SdlGamepad.is_connected() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { SDL_GamepadConnected(handle) };
  return res != 0;
}

pub fn SdlGamepad.get_name() -> Int
  requires: handle != 0
{
  return unsafe { SDL_GetGamepadName(handle) };
}

// =========================================================================
// SdlApp -- high-level application runner
// =========================================================================

pub type SdlApp = {
  window: SdlWindow;
  renderer: SdlRenderer;
  is_running: Bool;
} derive[Clone]

pub fn SdlApp.create(title: Int, width: Int32, height: Int32) -> Result[SdlApp, SdlError]
  requires: title != 0
  requires: width > 0
  requires: height > 0
{
  let ctx = SdlContext.init(0x00000020 as Int32);
  match ctx {
    Err(e) => { return Err(e); }
    Ok(c) => {
      let win_flags: Int = 0x0000000000000020;
      let win: Int = 0;
      let ren: Int = 0;
      let ok: Int32 = unsafe { SDL_CreateWindowAndRenderer(title, width, height, win_flags, win, ren) };
      if ok == 0 {
        return Err(SdlError{ message: "SDL_CreateWindowAndRenderer failed" });
      }
      return Ok(SdlApp{
        window: SdlWindow{ handle: win },
        renderer: SdlRenderer{ handle: ren },
        is_running: true,
      });
    }
  }
}

pub fn SdlApp.stop()
  requires: is_running == true
{
  is_running = false;
}

pub fn SdlApp.destroy()
  requires: window.handle != 0
  requires: renderer.handle != 0
{
  unsafe { SDL_DestroyRenderer(renderer.handle); }
  unsafe { SDL_DestroyWindow(window.handle); }
  unsafe { SDL_Quit(); }
}

pub fn SdlApp.clear_screen(r: Int32, g: Int32, b: Int32, a: Int32)
  requires: renderer.handle != 0
{
  unsafe { SDL_SetRenderDrawColor(renderer.handle, r, g, b, a); }
  unsafe { SDL_RenderClear(renderer.handle); }
}

pub fn SdlApp.present()
  requires: renderer.handle != 0
{
  unsafe { SDL_RenderPresent(renderer.handle); }
}


