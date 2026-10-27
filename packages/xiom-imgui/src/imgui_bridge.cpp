// xiom.imgui -- C bridge over the vendored Dear ImGui core (headless probe).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Integer-only ABI (same pattern as xiom.box2d): the bridge owns the C++
// API and the ImVec2/ImDrawData internals; values cross as ints and
// out-params in XIOM-owned slots.
//
// The probe uses upstream's own null platform+render backends
// (vendor/imgui_impl_null.cpp) -- the supported "blind context, no input,
// no output" flow from examples/example_null -- so the frame is realistic
// (RendererHasTextures active) and runs on any CI machine.

#include "../vendor/imgui.h"
#include "../vendor/imgui_impl_null.h"
#include "../vendor/imgui_impl_sdl3.h"
#include "../vendor/imgui_impl_vulkan.h"
#include "../vendor/SDL3/SDL.h"
#include <stdint.h>

extern "C" {

// No ini/log side effects: probes must leave the worktree clean, and ImGui
// otherwise writes/updates imgui.ini in the CWD on DestroyContext.
static void configure_io() {
  ImGuiIO& io = ImGui::GetIO();
  io.IniFilename = 0;
  io.LogFilename = 0;
}

// IMGUI_VERSION_NUM (1.92.9b -> 19291; encoded XYYZZ per imgui.h).
int imguiprobe_version(void) {
  return IMGUI_VERSION_NUM;
}

// IMGUI_VERSION as a C string ("1.92.9b").
const char* imguiprobe_version_str(void) {
  return IMGUI_VERSION;
}

// Headless frame: context -> null backends -> two NewFrame/Begin/Text/End/
// Render cycles; reports the SECOND frame's draw-data stats.  (ImGui hides
// a newly created window for its very first frame, so the steady-state
// frame is the informative one.)  Returns 0 on success.
int imguiprobe_frame(int* out_vertices, int* out_indices, int* out_cmd_lists) {
  if (out_vertices == 0 || out_indices == 0 || out_cmd_lists == 0) return 1;

  ImGui::CreateContext();
  configure_io();
  ImGui_ImplNullPlatform_Init();
  ImGui_ImplNullRender_Init();

  for (int f = 0; f < 2; f++) {
    ImGui_ImplNullPlatform_NewFrame();
    ImGui_ImplNullRender_NewFrame();
    ImGui::NewFrame();
    ImGui::Begin("xiom-probe");
    ImGui::Text("hello from xiom.imgui");
    ImGui::End();
    ImGui::Render();
  }

  ImDrawData* dd = ImGui::GetDrawData();
  if (dd == 0) {
    ImGui_ImplNullRender_Shutdown();
    ImGui_ImplNullPlatform_Shutdown();
    ImGui::DestroyContext();
    return 2;
  }
  *out_vertices = dd->TotalVtxCount;
  *out_indices = dd->TotalIdxCount;
  *out_cmd_lists = dd->CmdListsCount;

  ImGui_ImplNullRender_Shutdown();
  ImGui_ImplNullPlatform_Shutdown();
  ImGui::DestroyContext();
  return 0;
}

// Empty-frame lifecycle sanity: no windows -> zero draw lists (two frames
// for parity with the windowed probe).
int imguiprobe_empty_frame(int* out_cmd_lists) {
  if (out_cmd_lists == 0) return 1;

  ImGui::CreateContext();
  configure_io();
  ImGui_ImplNullPlatform_Init();
  ImGui_ImplNullRender_Init();

  for (int f = 0; f < 2; f++) {
    ImGui_ImplNullPlatform_NewFrame();
    ImGui_ImplNullRender_NewFrame();
    ImGui::NewFrame();
    ImGui::Render();
  }

  ImDrawData* dd = ImGui::GetDrawData();
  *out_cmd_lists = dd ? dd->CmdListsCount : -1;

  ImGui_ImplNullRender_Shutdown();
  ImGui_ImplNullPlatform_Shutdown();
  ImGui::DestroyContext();
  return 0;
}

// ---------------------------------------------------------------------------
// 0.3.0: long-lived context handles (registry, assimp pattern).
//
// Create/destroy ImGui contexts through integer handles and drive frames
// across separate XIOM calls, so window/context state persists (the
// ROADMAP's "context handle API for long-lived frames").  The null backends
// keep only per-context io flags, so multiple live contexts work as long as
// every call makes its context current.
// ---------------------------------------------------------------------------

static const int kMaxImguiContexts = 4;
static ImGuiContext* g_contexts[kMaxImguiContexts] = {0, 0, 0, 0};
static int g_context_frames[kMaxImguiContexts] = {0, 0, 0, 0};

// 1-based handle -> slot; -1 when the handle is invalid or destroyed.
static int context_slot(int handle) {
  int slot = handle - 1;
  if (slot < 0 || slot >= kMaxImguiContexts) return -1;
  if (g_contexts[slot] == 0) return -1;
  return slot;
}

// Create a headless context sized width x height; returns a 1-based handle
// or 0 when no slot is free / the size is invalid.
int imguiprobe_context_create(int width, int height) {
  if (width <= 0 || height <= 0) return 0;
  int slot = -1;
  for (int i = 0; i < kMaxImguiContexts; i++) {
    if (g_contexts[i] == 0) {
      slot = i;
      break;
    }
  }
  if (slot < 0) return 0;

  // CreateContext only makes the new context current when none is, so bind
  // and store the RETURNED context explicitly (an existing context otherwise
  // stays current and every slot would alias it).
  ImGuiContext* ctx = ImGui::CreateContext();
  ImGui::SetCurrentContext(ctx);
  configure_io();
  ImGui::GetIO().DisplaySize = ImVec2((float)width, (float)height);
  ImGui_ImplNullPlatform_Init();
  ImGui_ImplNullRender_Init();

  g_contexts[slot] = ctx;
  g_context_frames[slot] = 0;
  return slot + 1;
}

// One frame on a live handle: a "xiom-context" window with text.  Returns 0
// and the draw-data stats, or a nonzero error code.
int imguiprobe_context_frame(int handle, int* out_vertices, int* out_indices, int* out_cmd_lists) {
  int slot = context_slot(handle);
  if (slot < 0 || out_vertices == 0 || out_indices == 0 || out_cmd_lists == 0) return 1;

  ImGui::SetCurrentContext(g_contexts[slot]);
  ImGui_ImplNullPlatform_NewFrame();
  ImGui_ImplNullRender_NewFrame();
  ImGui::NewFrame();
  ImGui::Begin("xiom-context");
  ImGui::Text("long-lived frame");
  ImGui::End();
  ImGui::Render();

  ImDrawData* dd = ImGui::GetDrawData();
  if (dd == 0) return 2;
  *out_vertices = dd->TotalVtxCount;
  *out_indices = dd->TotalIdxCount;
  *out_cmd_lists = dd->CmdListsCount;
  g_context_frames[slot]++;
  return 0;
}

// Destroy a live handle.  Returns 1 on success, 0 for invalid handles
// (including a second destroy of the same handle).
int imguiprobe_context_destroy(int handle) {
  int slot = context_slot(handle);
  if (slot < 0) return 0;

  ImGui::SetCurrentContext(g_contexts[slot]);
  ImGui_ImplNullRender_Shutdown();
  ImGui_ImplNullPlatform_Shutdown();
  ImGui::DestroyContext(g_contexts[slot]);
  g_contexts[slot] = 0;
  g_context_frames[slot] = 0;
  return 1;
}

// Live context count (registry bookkeeping for the suite).
int imguiprobe_context_count(void) {
  int n = 0;
  for (int i = 0; i < kMaxImguiContexts; i++) {
    if (g_contexts[i] != 0) n++;
  }
  return n;
}

// Frames driven on a handle so far; -1 for invalid handles.
int imguiprobe_context_frames(int handle) {
  int slot = context_slot(handle);
  if (slot < 0) return -1;
  return g_context_frames[slot];
}

// ---------------------------------------------------------------------------
// 0.4.0: SDL3 platform + Vulkan renderer backends (engine-owned handles).
//
// The engine owns the SDL3 window, the Vulkan instance/device/queue and the
// render pass; the bridge only consumes those handles, matching the wishlist
// interop contract.  Handles cross as 64-bit values; the engine keeps
// ownership of every object (including the descriptor pool).
// ---------------------------------------------------------------------------

static const int kMaxBackendContexts = 2;

struct ImguiBackendCtx {
  ImGuiContext* ctx;
  bool sdl3;
  bool vulkan;
  int frames;
};

static ImguiBackendCtx g_backends[kMaxBackendContexts] = {};
static char g_backend_error[192] = {0};

static void backend_set_error(const char* msg) {
  int i = 0;
  while (msg && msg[i] && i < (int)sizeof(g_backend_error) - 1) {
    g_backend_error[i] = msg[i];
    i++;
  }
  g_backend_error[i] = 0;
}

static int backend_slot(int handle) {
  int slot = handle - 1;
  if (slot < 0 || slot >= kMaxBackendContexts) return -1;
  if (g_backends[slot].ctx == 0) return -1;
  return slot;
}

const char* imguibridge_backend_error(void) {
  return g_backend_error;
}

int imguibridge_backend_create(void) {
  int slot = -1;
  for (int i = 0; i < kMaxBackendContexts; i++) {
    if (g_backends[i].ctx == 0) { slot = i; break; }
  }
  if (slot < 0) return 0;
  ImGuiContext* ctx = ImGui::CreateContext();
  ImGui::SetCurrentContext(ctx);
  configure_io();
  g_backends[slot].ctx = ctx;
  g_backends[slot].sdl3 = false;
  g_backends[slot].vulkan = false;
  g_backends[slot].frames = 0;
  return slot + 1;
}

int imguibridge_backend_count(void) {
  int n = 0;
  for (int i = 0; i < kMaxBackendContexts; i++) {
    if (g_backends[i].ctx != 0) n++;
  }
  return n;
}

int imguibridge_backend_frames(int handle) {
  int slot = backend_slot(handle);
  return slot < 0 ? -1 : g_backends[slot].frames;
}

// mode: 0 = SDL_ImplSDL3_InitForOther, 1 = InitForVulkan (engine renderer).
int imguibridge_backend_sdl3_init(int handle, unsigned long long window, int mode) {
  int slot = backend_slot(handle);
  if (slot < 0 || window == 0) {
    backend_set_error("bad backend handle or SDL window");
    return 2;
  }
  if (g_backends[slot].sdl3) {
    backend_set_error("SDL3 platform backend already initialised");
    return 3;
  }
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  SDL_Window* w = (SDL_Window*)(uintptr_t)window;
  bool ok = (mode == 1) ? ImGui_ImplSDL3_InitForVulkan(w)
                        : ImGui_ImplSDL3_InitForOther(w);
  if (!ok) {
    backend_set_error("ImGui_ImplSDL3_Init failed");
    return 4;
  }
  g_backends[slot].sdl3 = true;
  return 0;
}

// event_ptr must point at a live SDL_Event (e.g. the one filled by
// SDL_PollEvent); the engine keeps ownership.
int imguibridge_backend_sdl3_process_event(int handle, unsigned long long event_ptr) {
  int slot = backend_slot(handle);
  if (slot < 0 || event_ptr == 0 || !g_backends[slot].sdl3) {
    backend_set_error("bad backend handle/event or SDL3 backend not initialised");
    return 2;
  }
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  ImGui_ImplSDL3_ProcessEvent((const SDL_Event*)(uintptr_t)event_ptr);
  return 0;
}

// Engine-owned Vulkan handles.  render_pass must be a real render pass
// (the engine-pass path from the wishlist); dynamic rendering is a
// follow-up.  The descriptor pool must satisfy the backend minimums
// (IMGUI_IMPL_VULKAN_MINIMUM_SAMPLED_IMAGE_POOL_SIZE +
// IMGUI_IMPL_VULKAN_MINIMUM_SAMPLER_POOL_SIZE).
int imguibridge_backend_vulkan_init(
    int handle,
    unsigned long long instance,
    unsigned long long physical_device,
    unsigned long long device,
    unsigned long long queue,
    int queue_family,
    unsigned long long descriptor_pool,
    unsigned long long render_pass,
    unsigned int api_version,
    int min_image_count,
    int image_count,
    int msaa,
    int subpass) {
  int slot = backend_slot(handle);
  if (slot < 0) {
    backend_set_error("bad backend handle");
    return 2;
  }
  if (g_backends[slot].vulkan) {
    backend_set_error("Vulkan renderer backend already initialised");
    return 3;
  }
  if (instance == 0 || physical_device == 0 || device == 0 || queue == 0 ||
      descriptor_pool == 0 || render_pass == 0) {
    backend_set_error("missing engine Vulkan handle (instance/physical/device/queue/pool/render_pass)");
    return 2;
  }
  if (queue_family < 0 || min_image_count < 2 ||
      image_count < min_image_count || msaa <= 0) {
    backend_set_error("bad queue family / image count / MSAA");
    return 2;
  }

  ImGui::SetCurrentContext(g_backends[slot].ctx);
  ImGui_ImplVulkan_InitInfo info = {};
  info.ApiVersion = api_version ? api_version : VK_API_VERSION_1_1;
  info.Instance = (VkInstance)(uintptr_t)instance;
  info.PhysicalDevice = (VkPhysicalDevice)(uintptr_t)physical_device;
  info.Device = (VkDevice)(uintptr_t)device;
  info.QueueFamily = (uint32_t)queue_family;
  info.Queue = (VkQueue)(uintptr_t)queue;
  info.DescriptorPool = (VkDescriptorPool)(uintptr_t)descriptor_pool;
  info.MinImageCount = (uint32_t)min_image_count;
  info.ImageCount = (uint32_t)image_count;
  info.PipelineInfoMain.RenderPass = (VkRenderPass)(uintptr_t)render_pass;
  info.PipelineInfoMain.Subpass = (uint32_t)subpass;
  info.PipelineInfoMain.MSAASamples = (VkSampleCountFlagBits)msaa;
  info.UseDynamicRendering = false;

  if (!ImGui_ImplVulkan_Init(&info)) {
    backend_set_error("ImGui_ImplVulkan_Init failed");
    return 4;
  }
  g_backends[slot].vulkan = true;
  return 0;
}

// One deterministic frame (platform + renderer NewFrame when initialised).
// The engine's own UI calls land here in the next tier; the selftest uses
// this window+text so the draw data is non-trivial.
int imguibridge_backend_frame(int handle, int* out_vertices, int* out_indices, int* out_cmd_lists) {
  int slot = backend_slot(handle);
  if (slot < 0 || out_vertices == 0 || out_indices == 0 || out_cmd_lists == 0) {
    backend_set_error("bad backend handle or out-params");
    return 2;
  }
  if (!g_backends[slot].sdl3) {
    backend_set_error("SDL3 platform backend not initialised");
    return 3;
  }
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  ImGui_ImplSDL3_NewFrame();
  if (g_backends[slot].vulkan) ImGui_ImplVulkan_NewFrame();
  ImGui::NewFrame();
  ImGui::Begin("xiom-backend");
  ImGui::Text("engine-owned backend frame");
  ImGui::End();
  ImGui::Render();

  ImDrawData* dd = ImGui::GetDrawData();
  if (dd == 0) {
    backend_set_error("no draw data");
    return 4;
  }
  *out_vertices = dd->TotalVtxCount;
  *out_indices = dd->TotalIdxCount;
  *out_cmd_lists = dd->CmdListsCount;
  g_backends[slot].frames++;
  return 0;
}

// Render the last frame's draw data into the engine's command buffer.
int imguibridge_backend_vulkan_render(int handle, unsigned long long draw_data, unsigned long long command_buffer) {
  int slot = backend_slot(handle);
  if (slot < 0 || !g_backends[slot].vulkan || draw_data == 0 || command_buffer == 0) {
    backend_set_error("bad handle/draw data/command buffer or Vulkan backend not initialised");
    return 2;
  }
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  ImGui_ImplVulkan_RenderDrawData((ImDrawData*)(uintptr_t)draw_data,
                                  (VkCommandBuffer)(uintptr_t)command_buffer);
  return 0;
}

// Latest draw data pointer (the engine records it into its command buffer).
unsigned long long imguibridge_backend_draw_data(int handle) {
  int slot = backend_slot(handle);
  if (slot < 0) return 0;
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  return (unsigned long long)(uintptr_t)ImGui::GetDrawData();
}

int imguibridge_backend_shutdown(int handle) {
  int slot = backend_slot(handle);
  if (slot < 0) return 0;
  ImGui::SetCurrentContext(g_backends[slot].ctx);
  if (g_backends[slot].vulkan) {
    ImGui_ImplVulkan_Shutdown();
    g_backends[slot].vulkan = false;
  }
  if (g_backends[slot].sdl3) {
    ImGui_ImplSDL3_Shutdown();
    g_backends[slot].sdl3 = false;
  }
  ImGui::DestroyContext(g_backends[slot].ctx);
  g_backends[slot].ctx = 0;
  g_backends[slot].frames = 0;
  return 1;
}

// 1 when an SDL3 video driver is available, 0 otherwise.  Does not leave
// the video subsystem initialised when this call initialised it.
int imguibridge_backend_sdl3_available(void) {
  bool own_video = (SDL_WasInit(SDL_INIT_VIDEO) == 0);
  if (own_video && !SDL_InitSubSystem(SDL_INIT_VIDEO)) return 0;
  bool ok = (SDL_GetCurrentVideoDriver() != 0);
  if (own_video) SDL_QuitSubSystem(SDL_INIT_VIDEO);
  return ok ? 1 : 0;
}

// Test-only: hidden SDL3 window + the real SDL3 platform backend, two
// frames.  Returns 0 on success, 3 when the host has no video/display
// (callers treat that as a SKIP), other nonzero for real failures.
int imguibridge_backend_sdl3_selftest(int* out_vertices, int* out_indices, int* out_cmd_lists) {
  if (out_vertices == 0 || out_indices == 0 || out_cmd_lists == 0) return 1;
  bool own_video = (SDL_WasInit(SDL_INIT_VIDEO) == 0);
  if (own_video && !SDL_InitSubSystem(SDL_INIT_VIDEO)) {
    backend_set_error("SDL_InitSubSystem(VIDEO) failed");
    return 2;
  }
  SDL_Window* window = SDL_CreateWindow("xiom-imgui-selftest", 320, 200, SDL_WINDOW_HIDDEN);
  if (window == 0) {
    if (own_video) SDL_QuitSubSystem(SDL_INIT_VIDEO);
    backend_set_error("SDL_CreateWindow failed (no display?)");
    return 3;
  }
  ImGuiContext* ctx = ImGui::CreateContext();
  ImGui::SetCurrentContext(ctx);
  configure_io();
  if (!ImGui_ImplSDL3_InitForOther(window)) {
    ImGui::DestroyContext(ctx);
    SDL_DestroyWindow(window);
    if (own_video) SDL_QuitSubSystem(SDL_INIT_VIDEO);
    backend_set_error("ImGui_ImplSDL3_InitForOther failed");
    return 4;
  }
  // Platform-only would leave the dynamic-texture atlas unbuilt; pair the
  // real SDL3 platform backend with the vendored null renderer for the
  // selftest (the engine pairs it with the Vulkan backend instead).
  ImGui_ImplNullRender_Init();
  for (int f = 0; f < 2; f++) {
    ImGui_ImplSDL3_NewFrame();
    ImGui_ImplNullRender_NewFrame();
    ImGui::NewFrame();
    ImGui::Begin("xiom-backend-selftest");
    ImGui::Text("sdl3 platform backend frame");
    ImGui::End();
    ImGui::Render();
  }
  int rc = 0;
  ImDrawData* dd = ImGui::GetDrawData();
  if (dd == 0) {
    rc = 5;
  } else {
    *out_vertices = dd->TotalVtxCount;
    *out_indices = dd->TotalIdxCount;
    *out_cmd_lists = dd->CmdListsCount;
  }
  ImGui_ImplNullRender_Shutdown();
  ImGui_ImplSDL3_Shutdown();
  ImGui::DestroyContext(ctx);
  SDL_DestroyWindow(window);
  if (own_video) SDL_QuitSubSystem(SDL_INIT_VIDEO);
  return rc;
}

} // extern "C"
