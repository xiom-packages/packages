// XIOM — SDL3 Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for SDL 3.4.8.
// All create/destroy pairs with Result[T, Str] + design-by-contract.
//
// COVERAGE: 4 resource types spanning the core SDL3 lifecycle:
//   SdlContext, SdlWindow, SdlRenderer, SdlEvent

module xiom.sdl3.safe

extern "C" {
  fn SDL_Init(flags: Int32) -> Int32;
  fn SDL_InitSubSystem(flags: Int32) -> Int32;
  fn SDL_QuitSubSystem(flags: Int32);
  fn SDL_WasInit(flags: Int32) -> Int32;
  fn SDL_Quit();

  fn SDL_CreateWindow(title: Int, w: Int32, h: Int32, flags: Int) -> Int;
  fn SDL_DestroyWindow(window: Int);
  fn SDL_GetWindowSize(window: Int, w: Int, h: Int) -> Int32;
  fn SDL_ShowWindow(window: Int) -> Int32;
  fn SDL_HideWindow(window: Int) -> Int32;
  fn SDL_SetWindowTitle(window: Int, title: Int) -> Int32;
  fn SDL_GetWindowFlags(window: Int) -> Int;
  fn SDL_GetWindowID(window: Int) -> Int32;
  fn SDL_RaiseWindow(window: Int) -> Int32;

  fn SDL_CreateWindowAndRenderer(title: Int, width: Int32, height: Int32, window_flags: Int, window: Int, renderer: Int) -> Int32;
  fn SDL_CreateRenderer(window: Int, name: Int) -> Int;
  fn SDL_DestroyRenderer(renderer: Int);

  fn SDL_RenderClear(renderer: Int) -> Int32;
  fn SDL_RenderPresent(renderer: Int) -> Int32;
  fn SDL_SetRenderDrawColor(renderer: Int, r: Int32, g: Int32, b: Int32, a: Int32) -> Int32;
  fn SDL_SetRenderDrawColorFloat(renderer: Int, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn SDL_RenderFillRect(renderer: Int, rect: Int) -> Int32;
  fn SDL_RenderRect(renderer: Int, rect: Int) -> Int32;

  fn SDL_PollEvent(event: Int) -> Int32;
  fn SDL_WaitEvent(event: Int) -> Int32;
  fn SDL_PumpEvents();

  fn SDL_Delay(ms: Int32);
  fn SDL_GetTicks() -> Int;
  fn SDL_GetError() -> Int;
  fn SDL_ClearError() -> Int32;
}

// =========================================================================
// SdlContext — global SDL3 lifecycle manager
// =========================================================================

pub type SdlContext = {
  is_init: Bool;
} derive[Clone]

pub fn SdlContext.init(flags: Int32) -> Result[SdlContext, Str]
  requires: flags != 0
  ensures: result is Ok => result.unwrap().is_init == true
{
  let res: Int32 = unsafe { SDL_Init(flags) };
  if res != 0 {
    return Err("SDL_Init failed");
  }
  return Ok(SdlContext{ is_init: true });
}

pub fn SdlContext.quit()
  requires: is_init == true
{
  unsafe { SDL_Quit(); }
}

// =========================================================================
// SdlWindow — an SDL_Window* resource
// =========================================================================

pub type SdlWindow = {
  handle: Int;
} derive[Clone]

pub fn SdlWindow.create(title: Int, w: Int32, h: Int32, flags: Int) -> Result[SdlWindow, Str]
  requires: title != 0
  requires: w > 0
  requires: h > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let win: Int = unsafe { SDL_CreateWindow(title, w, h, flags) };
  if win == 0 {
    return Err("SDL_CreateWindow failed");
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

pub fn SdlWindow.get_size() -> Result[Int, Str]
  requires: handle != 0
{
  let w: Int = 0;
  let h: Int = 0;
  let ok: Int32 = unsafe { SDL_GetWindowSize(handle, w, h) };
  if ok == 0 {
    return Err("SDL_GetWindowSize failed");
  }
  return Ok(w);
}

// =========================================================================
// SdlRenderer — an SDL_Renderer* resource
// =========================================================================

pub type SdlRenderer = {
  handle: Int;
} derive[Clone]

pub fn SdlRenderer.create(window_handle: Int) -> Result[SdlRenderer, Str]
  requires: window_handle != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let ren: Int = unsafe { SDL_CreateRenderer(window_handle, 0) };
  if ren == 0 {
    return Err("SDL_CreateRenderer failed");
  }
  return Ok(SdlRenderer{ handle: ren });
}

pub fn SdlRenderer.create_for_window(window: SdlWindow) -> Result[SdlRenderer, Str]
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

// =========================================================================
// SdlApp — high-level application runner
// =========================================================================

pub type SdlApp = {
  ctx: SdlContext;
  renderer: SdlRenderer;
  window: SdlWindow;
} derive[Clone]

pub fn SdlApp.create(title: Int, width: Int32, height: Int32) -> Result[SdlApp, Str]
  requires: title != 0
  requires: width > 0
  requires: height > 0
{
  let flags: Int32 = 32 as Int32;
  let c = SdlContext.init(flags)?;

  let win_flags: Int = 32;
  let win: Int = 0;
  let ren: Int = 0;
  let ok: Int32 = unsafe { SDL_CreateWindowAndRenderer(title, width, height, win_flags, win, ren) };
  if ok == 0 {
    return Err("SDL_CreateWindowAndRenderer failed");
  }

  return Ok(SdlApp{
    ctx: c,
    window: SdlWindow{ handle: win },
    renderer: SdlRenderer{ handle: ren },
  });
}

pub fn SdlApp.run(duration_ms: Int32)
  requires: window.handle != 0
  requires: renderer.handle != 0
{
  let start: Int = unsafe { SDL_GetTicks() };
  let running: Bool = true;
  while running {
    let event_buf: [Int32; 32] = [ 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, 0 as Int32, ];
    let event_ptr: Int = 0;
    while unsafe { SDL_PollEvent(event_ptr) } != 0 {
      let event_type: Int32 = event_buf[0];
      if event_type == (256 as Int32) {
        running = false;
      }
    }

    unsafe { SDL_SetRenderDrawColor(renderer.handle, 0 as Int32, 0 as Int32, 0 as Int32, 255 as Int32); }
    unsafe { SDL_RenderClear(renderer.handle); }
    unsafe { SDL_SetRenderDrawColor(renderer.handle, 255 as Int32, 0 as Int32, 0 as Int32, 255 as Int32); }
    let rect_data: [Int32; 4] = [ 50 as Int32, 50 as Int32, 200 as Int32, 200 as Int32 ];
    let rect_ptr: Int = 0;
    unsafe { SDL_RenderFillRect(renderer.handle, rect_ptr); }
    unsafe { SDL_RenderPresent(renderer.handle); }

    let now: Int = unsafe { SDL_GetTicks() };
    if (now - start) > (duration_ms as Int) {
      running = false;
    }
  }
}
