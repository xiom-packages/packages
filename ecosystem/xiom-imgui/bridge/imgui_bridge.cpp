#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_vulkan.h"
#include "imgui_bridge.h"
#include <string.h>

static bool g_initialized = false;

int32_t imgui_bridge_init(int64_t glfw_window)
{
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();

    GLFWwindow* win = (GLFWwindow*)(intptr_t)glfw_window;
    if (!ImGui_ImplGlfw_InitForVulkan(win, true)) return 0;
    g_initialized = true;
    return 1;
}

int32_t imgui_bridge_init_vulkan(int64_t instance, int64_t device,
    int64_t physical_device, int64_t graphics_queue,
    int32_t queue_family, int64_t render_pass,
    int32_t subpass_count, float fb_width, float fb_height)
{
    if (!g_initialized) return 0;

    VkInstance inst = (VkInstance)(intptr_t)instance;
    VkDevice dev    = (VkDevice)(intptr_t)device;
    VkPhysicalDevice phys = (VkPhysicalDevice)(intptr_t)physical_device;
    VkQueue queue    = (VkQueue)(intptr_t)graphics_queue;
    VkRenderPass rp  = (VkRenderPass)(intptr_t)render_pass;

    ImGui_ImplVulkan_InitInfo init_info = {};
    init_info.Instance        = inst;
    init_info.PhysicalDevice  = phys;
    init_info.Device          = dev;
    init_info.QueueFamily     = (uint32_t)queue_family;
    init_info.Queue           = queue;
    init_info.PipelineCache   = VK_NULL_HANDLE;
    init_info.DescriptorPool  = VK_NULL_HANDLE;
    init_info.MinImageCount   = 2;
    init_info.ImageCount      = 2;
    init_info.Allocator       = nullptr;
    init_info.CheckVkResultFn = nullptr;
    init_info.PipelineInfoMain.RenderPass  = rp;
    init_info.PipelineInfoMain.Subpass     = (uint32_t)subpass_count;
    init_info.PipelineInfoMain.MSAASamples = VK_SAMPLE_COUNT_1_BIT;

    ImGui_ImplVulkan_Init(&init_info);
    return 1;
}

void imgui_bridge_shutdown()
{
    if (g_initialized) {
        ImGui_ImplVulkan_Shutdown();
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
    ImGui::Render();
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)command_buffer;
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), cb);
}

int32_t imgui_begin(const char* name) { return ImGui::Begin(name) ? 1 : 0; }
void    imgui_end(void)                { ImGui::End(); }
int32_t imgui_button(const char* label){ return ImGui::Button(label) ? 1 : 0; }
void    imgui_text(const char* text)   { ImGui::TextUnformatted(text); }
float   imgui_slider_float(const char* label, float value, float min_val, float max_val)
    { ImGui::SliderFloat(label, &value, min_val, max_val); return value; }
int32_t imgui_checkbox(const char* label, int32_t checked)
    { bool c = checked != 0; ImGui::Checkbox(label, &c); return c ? 1 : 0; }
void    imgui_separator(void)          { ImGui::Separator(); }
void    imgui_same_line(void)          { ImGui::SameLine(); }
void    imgui_spacing(void)            { ImGui::Spacing(); }
int32_t imgui_tree_node(const char* label) { return ImGui::TreeNode(label) ? 1 : 0; }
void    imgui_tree_pop(void)           { ImGui::TreePop(); }
int32_t imgui_collapsing_header(const char* label)
    { return ImGui::CollapsingHeader(label) ? 1 : 0; }

void imgui_plot_lines(const char* label, const float* values, int32_t count,
    float scale_min, float scale_max, float width, float height)
{
    ImGui::PlotLines(label, values, count, 0, nullptr, scale_min, scale_max,
                     ImVec2(width, height));
}

int32_t imgui_input_text(const char* label, char* buf, int32_t buf_size)
    { return ImGui::InputText(label, buf, (size_t)buf_size) ? 1 : 0; }

int32_t imgui_combo(const char* label, int32_t current_item,
    const char* const* items, int32_t item_count)
{
    int ci = current_item;
    ImGui::Combo(label, &ci, items, item_count);
    return ci;
}

void imgui_style_dark(void)    { ImGui::StyleColorsDark(); }
void imgui_style_light(void)   { ImGui::StyleColorsLight(); }
void imgui_style_classic(void) { ImGui::StyleColorsClassic(); }
