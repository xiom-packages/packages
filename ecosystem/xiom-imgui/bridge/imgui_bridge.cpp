#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_vulkan.h"
#include "imgui_bridge.h"
#include <GLFW/glfw3.h>
#include <vulkan/vulkan.h>
#include <string.h>
#include <stdio.h>

#define DBG(fmt, ...) printf( "[imgui-bridge] " fmt "\n", ##__VA_ARGS__)

static bool g_initialized = false;
static bool g_vk_initialized = false;

/* Stored Vulkan handles for reinit_vulkan to use */
static VkInstance       g_Instance       = VK_NULL_HANDLE;
static VkDevice         g_Device         = VK_NULL_HANDLE;
static VkPhysicalDevice g_PhysicalDevice = VK_NULL_HANDLE;
static VkQueue          g_Queue          = VK_NULL_HANDLE;
static uint32_t         g_QueueFamily    = 0;
static VkRenderPass     g_RenderPass     = VK_NULL_HANDLE;
static int32_t          g_SubpassIndex   = 0;

static void check_vk_result(VkResult err)
{
    if (err != VK_SUCCESS) {
        fprintf(stderr, "[imgui-bridge] VULKAN ERROR: %d\n", (int)err);
    }
}

int32_t imgui_bridge_init(int64_t glfw_window)
{
    GLFWwindow* win = (GLFWwindow*)(intptr_t)glfw_window;
    if (!win) { DBG("NULL window"); return 0; }
    if (g_initialized) { DBG("already initialized"); return 1; }

    DBG("Creating context");
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    /* DPI font scaling from GLFW window content scale (HiDPI displays).
     * Framebuffer pixels / window coordinates ratio. Default 1.0. */
    {
        float xs = 1.0f, ys = 1.0f;
        glfwGetWindowContentScale(win, &xs, &ys);
        io.FontGlobalScale = (xs > 0.0f) ? xs : 1.0f;
    }

    ImGui::StyleColorsDark();

    /* Runtime version check: bridge must match bundled ImGui .obj version.
     * Mismatch causes ABI breakage with no compile-time diagnostic. */
    if (strcmp(ImGui::GetVersion(), "1.92.9") != 0) {
        DBG("ImGui version mismatch: expected 1.92.9, got %s", ImGui::GetVersion());
    }

    DBG("Init GLFW for Vulkan");
    if (!ImGui_ImplGlfw_InitForVulkan(win, true)) {
        DBG("GLFW init FAILED"); return 0;
    }
    g_initialized = true;
    DBG("GLFW init OK");
    return 1;
}

int32_t imgui_bridge_init_vulkan(int64_t instance, int64_t device,
    int64_t physical_device, int64_t graphics_queue,
    int32_t queue_family, int64_t render_pass,
    int32_t subpass_count, float fb_width, float fb_height)
{
    if (!g_initialized) { DBG("Not initialized"); return 0; }

    VkInstance       inst = (VkInstance)(intptr_t)instance;
    VkDevice         dev  = (VkDevice)(intptr_t)device;
    VkPhysicalDevice phys = (VkPhysicalDevice)(intptr_t)physical_device;
    VkQueue          q    = (VkQueue)(intptr_t)graphics_queue;
    VkRenderPass     rp   = (VkRenderPass)(intptr_t)render_pass;

    DBG("inst=%p dev=%p phys=%p queue=%p rp=%p fb=%.0fx%.0f",
        (void*)inst, (void*)dev, (void*)phys, (void*)q, (void*)rp,
        (double)fb_width, (double)fb_height);

    if (!inst || !dev || !phys || !q || !rp) {
        DBG("NULL VK handle"); return 0;
    }

    /* Store handles for reinit_vulkan to use */
    g_Instance       = inst;
    g_Device         = dev;
    g_PhysicalDevice = phys;
    g_Queue          = q;
    g_QueueFamily    = (uint32_t)queue_family;
    g_RenderPass     = rp;
    g_SubpassIndex   = subpass_count;

    /* Required when IMGUI_IMPL_VULKAN_NO_PROTOTYPES is defined */
    DBG("Loading Vulkan functions");
    ImGui_ImplVulkan_LoadFunctions(VK_API_VERSION_1_0,
        [](const char* name, void* ud) -> PFN_vkVoidFunction {
            return vkGetInstanceProcAddr((VkInstance)ud, name);
        }, (void*)inst);

    ImGui_ImplVulkan_InitInfo ini = {};
    ini.Instance          = inst;
    ini.PhysicalDevice    = phys;
    ini.Device            = dev;
    ini.QueueFamily       = (uint32_t)queue_family;
    ini.Queue             = q;
    ini.PipelineCache     = VK_NULL_HANDLE;
    ini.DescriptorPool    = VK_NULL_HANDLE;
    ini.DescriptorPoolSize = 32;
    ini.MinImageCount     = 2;
    ini.ImageCount        = 2;
    ini.Allocator         = nullptr;
    ini.CheckVkResultFn   = check_vk_result;
    ini.PipelineInfoMain.RenderPass  = rp;
    ini.PipelineInfoMain.Subpass     = (uint32_t)subpass_count;
    ini.PipelineInfoMain.MSAASamples = VK_SAMPLE_COUNT_1_BIT;

    DBG("Calling ImGui_ImplVulkan_Init");
    if (!ImGui_ImplVulkan_Init(&ini)) {
        DBG("Vulkan init FAILED"); return 0;
    }
    g_vk_initialized = true;
    DBG("Vulkan init OK");
    return 1;
}

void imgui_bridge_shutdown()
{
    if (g_vk_initialized) {
        ImGui_ImplVulkan_Shutdown();
        g_vk_initialized = false;
    }
    if (g_initialized) {
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        g_initialized = false;
    }
}

void imgui_bridge_new_frame()
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(1280.0f, 800.0f);  /* default, overridden by sized variant */
    io.DisplayFramebufferScale = ImVec2(1.0f, 1.0f);
    ImGui_ImplGlfw_NewFrame();       /* platform first: mouse, keys, time */
    ImGui_ImplVulkan_NewFrame();     /* renderer: reset descriptor pool */
    ImGui::NewFrame();               /* ImGui internal: begin frame */
}

void imgui_bridge_new_frame_sized(int32_t fb_w, int32_t fb_h)
{
    /* CRITICAL FIX: set DisplaySize BEFORE NewFrame() so ImGui reads
     * current dimensions for mouse hit-testing, clipping, and layout.
     * Order: platform (GLFW) → renderer (Vulkan) → ImGui::NewFrame() */
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2((float)fb_w, (float)fb_h);
    io.DisplayFramebufferScale = ImVec2(1.0f, 1.0f);
    ImGui_ImplGlfw_NewFrame();       /* updates mouse, keyboard, time from GLFW */
    ImGui_ImplVulkan_NewFrame();     /* resets descriptor pool */
    ImGui::NewFrame();               /* begins ImGui frame with correct DisplaySize */
}

void imgui_bridge_render(int64_t command_buffer)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)command_buffer;
    if (!cb) { printf("[imgui-bridge] NULL command buffer in render\n"); return; }
    ImGui::Render();
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), cb);
}

void imgui_bridge_set_display_size(float fb_w, float fb_h)
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(fb_w, fb_h);
    io.DisplayFramebufferScale = ImVec2(1.0f, 1.0f);
}

void imgui_bridge_set_display_size_i32(int32_t fb_w, int32_t fb_h)
{
    imgui_bridge_set_display_size((float)fb_w, (float)fb_h);
}

/* ── Windows ── */
int32_t imgui_begin(const char* name, int32_t flags) { return ImGui::Begin(name, nullptr, (ImGuiWindowFlags)flags) ? 1 : 0; }
void    imgui_end(void)                { ImGui::End(); }
int32_t imgui_begin_child(const char* id, float w, float h, int32_t border)
    { return ImGui::BeginChild(id, ImVec2(w, h), border != 0) ? 1 : 0; }
void    imgui_end_child(void)          { ImGui::EndChild(); }
void imgui_set_next_window_size_i32(int32_t w, int32_t h)
    { ImGui::SetNextWindowSize(ImVec2((float)w, (float)h)); }
void imgui_set_next_window_pos_i32(int32_t x, int32_t y)
    { ImGui::SetNextWindowPos(ImVec2((float)x, (float)y)); }

/* ── Widgets ── */
int32_t imgui_button(const char* label){ return ImGui::Button(label) ? 1 : 0; }
int32_t imgui_small_button(const char* label) { return ImGui::SmallButton(label) ? 1 : 0; }
void    imgui_text(const char* text)   { ImGui::TextUnformatted(text); }
void    imgui_text_colored(float r, float g, float b, float a, const char* text)
    { ImGui::TextColored(ImVec4(r,g,b,a), "%s", text); }
void    imgui_bullet_text(const char* text) { ImGui::BulletText("%s", text); }
float   imgui_slider_float(const char* l, float v, float mn, float mx)
    { ImGui::SliderFloat(l, &v, mn, mx); return v; }
int32_t imgui_slider_int(const char* l, int32_t v, int32_t mn, int32_t mx)
    { ImGui::SliderInt(l, &v, mn, mx); return v; }
int32_t imgui_checkbox(const char* l, int32_t c)
    { bool b = (c!=0); ImGui::Checkbox(l, &b); return b?1:0; }
float   imgui_drag_float(const char* l, float v, float spd, float mn, float mx)
    { ImGui::DragFloat(l, &v, spd, mn, mx); return v; }
int32_t imgui_drag_int(const char* l, int32_t v, float spd, int32_t mn, int32_t mx)
    { ImGui::DragInt(l, &v, spd, mn, mx); return v; }
float   imgui_input_float(const char* l, float v)
    { ImGui::InputFloat(l, &v); return v; }
int32_t imgui_input_int(const char* l, int32_t v)
    { ImGui::InputInt(l, &v); return v; }
int32_t imgui_input_text(const char* l, char* buf, int32_t sz)
    { return ImGui::InputText(l, buf, (size_t)sz) ? 1 : 0; }
int32_t imgui_color_edit3(const char* l, float r, float g, float b)
    { float c[3]={r,g,b}; if(ImGui::ColorEdit3(l, c)) { /* values stored in c, but bridge can't return 3 floats */ }; return 1; }
int32_t imgui_color_edit4(const char* l, float r, float g, float b, float a)
    { float c[4]={r,g,b,a}; if(ImGui::ColorEdit4(l, c)) { /* same limitation */ }; return 1; }

/* color_edit3_rgb: reads back modified values into caller's float variables */
void imgui_color_edit3_rgb(const char* label, float* r, float* g, float* b)
{
    float col[3];
    col[0] = r ? *r : 0.0f;
    col[1] = g ? *g : 0.0f;
    col[2] = b ? *b : 0.0f;
    if (ImGui::ColorEdit3(label, col)) {
        if (r) *r = col[0];
        if (g) *g = col[1];
        if (b) *b = col[2];
    }
}

/* color_edit4_rgba: reads back modified values into caller's float variables */
void imgui_color_edit4_rgba(const char* label, float* r, float* g, float* b, float* a)
{
    float col[4];
    col[0] = r ? *r : 0.0f;
    col[1] = g ? *g : 0.0f;
    col[2] = b ? *b : 0.0f;
    col[3] = a ? *a : 0.0f;
    if (ImGui::ColorEdit4(label, col)) {
        if (r) *r = col[0];
        if (g) *g = col[1];
        if (b) *b = col[2];
        if (a) *a = col[3];
    }
}
int32_t imgui_combo(const char* l, int32_t cur, const char* const* it, int32_t n)
    { ImGui::Combo(l, &cur, it, n); return cur; }
int32_t imgui_list_box(const char* l, int32_t cur, const char* const* it, int32_t n)
    { ImGui::ListBox(l, &cur, it, n); return cur; }

/* ── Extended Widgets ── */
void    imgui_progress_bar(float frac, float w, float h)
    { ImGui::ProgressBar(frac, w > 0 ? ImVec2(w,h) : ImVec2(-FLT_MIN, 0)); }
int32_t imgui_radio_button(const char* l, int32_t active)
    { return ImGui::RadioButton(l, active != 0) ? 1 : 0; }
int32_t imgui_selectable(const char* l, int32_t sel)
    { return ImGui::Selectable(l, sel != 0) ? 1 : 0; }
void    imgui_text_wrapped(const char* t) { ImGui::TextWrapped("%s", t); }
void    imgui_label_text(const char* label, const char* text) { ImGui::LabelText(label, "%s", text); }
int32_t imgui_begin_disabled(int32_t d) { ImGui::BeginDisabled(d != 0); return d; }
void    imgui_end_disabled(void) { ImGui::EndDisabled(); }

/* ── Layout ── */
void    imgui_separator(void) { ImGui::Separator(); }
void    imgui_same_line(float off, float sp) { ImGui::SameLine(off, sp); }
void    imgui_spacing(void)   { ImGui::Spacing(); }
void    imgui_dummy(float w, float h) { ImGui::Dummy(ImVec2(w,h)); }
void    imgui_new_line(void)  { ImGui::NewLine(); }

/* ── Trees ── */
int32_t imgui_tree_node(const char* l) { return ImGui::TreeNode(l) ? 1 : 0; }
int32_t imgui_tree_node_flags(const char* l, int32_t f)
    { return ImGui::TreeNodeEx(l, (ImGuiTreeNodeFlags)f) ? 1 : 0; }
void    imgui_tree_pop(void)  { ImGui::TreePop(); }
int32_t imgui_collapsing_header(const char* l) { return ImGui::CollapsingHeader(l) ? 1 : 0; }

/* ── Tabs ── */
int32_t imgui_begin_tab_bar(const char* id) { return ImGui::BeginTabBar(id) ? 1 : 0; }
void    imgui_end_tab_bar(void)  { ImGui::EndTabBar(); }
int32_t imgui_begin_tab_item(const char* l) { return ImGui::BeginTabItem(l) ? 1 : 0; }
void    imgui_end_tab_item(void) { ImGui::EndTabItem(); }

/* ── Plots ── */
void imgui_plot_lines(const char* l, const float* v, int32_t n, float smin, float smax, float w, float h)
    { ImGui::PlotLines(l, v, n, 0, nullptr, smin, smax, ImVec2(w,h)); }
void imgui_plot_histogram(const char* l, const float* v, int32_t n, float smin, float smax, float w, float h)
    { ImGui::PlotHistogram(l, v, n, 0, nullptr, smin, smax, ImVec2(w,h)); }

/* ── Popups ── */
void    imgui_open_popup(const char* id) { ImGui::OpenPopup(id); }
int32_t imgui_begin_popup(const char* id) { return ImGui::BeginPopup(id) ? 1 : 0; }
void    imgui_end_popup(void) { ImGui::EndPopup(); }
void    imgui_close_current_popup(void) { ImGui::CloseCurrentPopup(); }
int32_t imgui_begin_popup_context_item(const char* id)
    { return ImGui::BeginPopupContextItem(id) ? 1 : 0; }
int32_t imgui_begin_popup_modal(const char* n) { return ImGui::BeginPopupModal(n) ? 1 : 0; }
void    imgui_end_popup_modal(void) { ImGui::EndPopup(); }

/* ── Menus ── */
int32_t imgui_begin_menu_bar(void) { return ImGui::BeginMenuBar() ? 1 : 0; }
void    imgui_end_menu_bar(void)   { ImGui::EndMenuBar(); }
int32_t imgui_begin_main_menu_bar(void) { return ImGui::BeginMainMenuBar() ? 1 : 0; }
void    imgui_end_main_menu_bar(void)   { ImGui::EndMainMenuBar(); }
int32_t imgui_begin_menu(const char* l) { return ImGui::BeginMenu(l) ? 1 : 0; }
void    imgui_end_menu(void) { ImGui::EndMenu(); }
int32_t imgui_menu_item(const char* l, const char* s, int32_t e)
    { return ImGui::MenuItem(l, s, false, e!=0) ? 1 : 0; }

/* ── Tooltips ── */
void    imgui_set_tooltip(const char* t)  { ImGui::SetTooltip("%s", t); }
void    imgui_begin_tooltip(void) { ImGui::BeginTooltip(); }
void    imgui_end_tooltip(void)   { ImGui::EndTooltip(); }

/* ── Focus/Scrolling ── */
void    imgui_set_scroll_here_y(void) { ImGui::SetScrollHereY(); }
int32_t imgui_is_item_hovered(void)   { return ImGui::IsItemHovered() ? 1 : 0; }
int32_t imgui_is_item_clicked(void)   { return ImGui::IsItemClicked() ? 1 : 0; }

/* ── Styling ── */
void imgui_style_dark(void)    { ImGui::StyleColorsDark(); }
void imgui_style_light(void)   { ImGui::StyleColorsLight(); }
void imgui_style_classic(void) { ImGui::StyleColorsClassic(); }
void imgui_bridge_reset_vulkan(int64_t instance, int64_t device,
    int64_t physical_device, int64_t graphics_queue,
    int32_t queue_family, int64_t render_pass,
    float fb_width, float fb_height)
{
    (void)instance; (void)device; (void)physical_device;
    (void)graphics_queue; (void)queue_family;
    /* Only reset the ImGui Vulkan backend, keep GLFW backend active */
    if (g_vk_initialized) {
        ImGui_ImplVulkan_Shutdown();
        g_vk_initialized = false;
    }
    /* Reinitialize with same handles */
    imgui_bridge_init_vulkan(instance, device, physical_device, graphics_queue,
                              queue_family, render_pass, 0, fb_width, fb_height);
}
void imgui_push_style_color(int32_t idx, float r, float g, float b, float a)
    { ImGui::PushStyleColor((ImGuiCol)idx, ImVec4(r,g,b,a)); }
void imgui_pop_style_color(int32_t count) { ImGui::PopStyleColor(count); }

void imgui_bridge_reinit_vulkan(int64_t render_pass, float fb_w, float fb_h)
{
    if (!g_vk_initialized) return;
    /* Shutdown and reinitialize Vulkan backend using stored handles */
    ImGui_ImplVulkan_Shutdown();
    g_vk_initialized = false;

    if (g_Instance && g_Device && g_PhysicalDevice && g_Queue) {
        imgui_bridge_init_vulkan(
            (int64_t)(uint64_t)g_Instance,
            (int64_t)(uint64_t)g_Device,
            (int64_t)(uint64_t)g_PhysicalDevice,
            (int64_t)(uint64_t)g_Queue,
            (int32_t)g_QueueFamily,
            render_pass ? render_pass : (int64_t)(uint64_t)g_RenderPass,
            g_SubpassIndex,
            fb_w, fb_h);
    } else {
        DBG("reinit_vulkan: no stored handles");
    }
}

/* ── Utility ── */
int32_t imgui_get_framerate(void)    { return (int32_t)ImGui::GetIO().Framerate; }
int32_t imgui_get_frame_count(void)  { return ImGui::GetFrameCount(); }
