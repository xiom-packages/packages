#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_vulkan.h"
#include "imgui_bridge.h"
#include <vulkan/vulkan.h>
#include <string.h>
#include <stdio.h>

#define DBG(fmt, ...) printf( "[imgui-bridge] " fmt "\n", ##__VA_ARGS__)

static bool g_initialized = false;
static bool g_vk_initialized = false;

int32_t imgui_bridge_init(int64_t glfw_window)
{
    GLFWwindow* win = (GLFWwindow*)(intptr_t)glfw_window;
    if (!win) { DBG("NULL window"); return 0; }
    if (g_initialized) { DBG("already initialized"); return 1; }

    DBG("Creating context");
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    ImGui::StyleColorsDark();

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
    ini.CheckVkResultFn   = nullptr;
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
    ImGui_ImplVulkan_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();
}

void imgui_bridge_render(int64_t command_buffer)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)command_buffer;
    if (!cb) { DBG("NULL command buffer in render"); return; }
    ImGui::Render();
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), cb);
}

int32_t imgui_begin(const char* name) { return ImGui::Begin(name) ? 1 : 0; }
void    imgui_end(void)                { ImGui::End(); }
int32_t imgui_button(const char* label){ return ImGui::Button(label) ? 1 : 0; }
void    imgui_text(const char* text)   { ImGui::TextUnformatted(text); }
float   imgui_slider_float(const char* label, float val, float mn, float mx)
    { ImGui::SliderFloat(label, &val, mn, mx); return val; }
int32_t imgui_checkbox(const char* label, int32_t checked)
    { bool c = (checked != 0); ImGui::Checkbox(label, &c); return c ? 1 : 0; }
void    imgui_separator(void)          { ImGui::Separator(); }
void    imgui_same_line(void)          { ImGui::SameLine(); }
void    imgui_spacing(void)            { ImGui::Spacing(); }
int32_t imgui_tree_node(const char* label) { return ImGui::TreeNode(label) ? 1 : 0; }
void    imgui_tree_pop(void)           { ImGui::TreePop(); }
int32_t imgui_collapsing_header(const char* label)
    { return ImGui::CollapsingHeader(label) ? 1 : 0; }
void    imgui_plot_lines(const char* label, const float* v, int32_t n,
    float smin, float smax, float w, float h)
    { ImGui::PlotLines(label, v, n, 0, nullptr, smin, smax, ImVec2(w, h)); }
int32_t imgui_input_text(const char* label, char* buf, int32_t sz)
    { return ImGui::InputText(label, buf, (size_t)sz) ? 1 : 0; }
int32_t imgui_combo(const char* label, int32_t cur, const char* const* items, int32_t n)
    { int c = cur; ImGui::Combo(label, &c, items, n); return c; }
void    imgui_style_dark(void)    { ImGui::StyleColorsDark(); }
void    imgui_style_light(void)   { ImGui::StyleColorsLight(); }
void    imgui_style_classic(void) { ImGui::StyleColorsClassic(); }
