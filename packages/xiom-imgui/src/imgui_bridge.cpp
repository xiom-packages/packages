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

} // extern "C"
