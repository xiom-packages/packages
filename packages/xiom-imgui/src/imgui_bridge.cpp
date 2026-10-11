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

} // extern "C"
