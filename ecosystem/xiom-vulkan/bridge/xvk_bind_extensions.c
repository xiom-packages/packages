#include "xvk_bind_extensions.h"

#define XVK_EXT_DISP(T, h)   ((T)(intptr_t)(h))
#define XVK_EXT_NDISP(T, h)  ((T)(uint64_t)(h))
#define XVK_EXT_CPTR(T, h)   ((const T*)(intptr_t)(h))
#define XVK_EXT_MPTR(T, h)   ((T*)(intptr_t)(h))
#define XVK_EXT_H64(x)       ((int64_t)(uint64_t)(x))
#define XVK_EXT_CB(h)        XVK_EXT_DISP(VkCommandBuffer, h)
#define XVK_EXT_DEVH(h)      XVK_EXT_DISP(VkDevice, h)
#define XVK_EXT_QUEUEH(h)    XVK_EXT_DISP(VkQueue, h)
#define XVK_EXT_INSTH(h)     XVK_EXT_DISP(VkInstance, h)
#define XVK_EXT_BOOL(b)      ((b) ? VK_TRUE : VK_FALSE)

static VkInstance g_xvk_ext_instance = VK_NULL_HANDLE;
static VkDevice   g_xvk_ext_device   = VK_NULL_HANDLE;
static uint32_t   g_xvk_ext_igen     = 1;
static uint32_t   g_xvk_ext_dgen     = 1;

static VkSampleCountFlagBits g_xvk_ext_samples = VK_SAMPLE_COUNT_1_BIT;

#define XVK_EXT_MAX_MESSENGERS 16
static VkDebugUtilsMessengerEXT g_xvk_ext_messengers[XVK_EXT_MAX_MESSENGERS];
static int g_xvk_ext_messenger_count = 0;

void xvk_ext_load_instance(int64_t instance)
{
    g_xvk_ext_instance = XVK_EXT_INSTH(instance);
    g_xvk_ext_igen++;
}

void xvk_ext_load_device(int64_t device)
{
    g_xvk_ext_device = XVK_EXT_DEVH(device);
    g_xvk_ext_dgen++;
}

static PFN_vkVoidFunction xvk_ext_iproc(VkInstance instance, const char* name)
{
    if (instance == VK_NULL_HANDLE) {
        instance = g_xvk_ext_instance;
    } else if (g_xvk_ext_instance == VK_NULL_HANDLE) {
        g_xvk_ext_instance = instance;
        g_xvk_ext_igen++;
    }
    if (instance == VK_NULL_HANDLE) {
        xvk_set_error_fmt("%s: no VkInstance registered (call xvk_ext_load_instance)", name);
        return NULL;
    }
    PFN_vkVoidFunction fn = vkGetInstanceProcAddr(instance, name);
    if (!fn) xvk_set_error_fmt("%s: entry point not available (extension not enabled?)", name);
    return fn;
}

static PFN_vkVoidFunction xvk_ext_dproc(VkDevice device, const char* name, const char* alt)
{
    if (device == VK_NULL_HANDLE) {
        device = g_xvk_ext_device;
    } else if (g_xvk_ext_device == VK_NULL_HANDLE) {
        g_xvk_ext_device = device;
        g_xvk_ext_dgen++;
    }
    PFN_vkVoidFunction fn = NULL;
    if (device != VK_NULL_HANDLE) {
        fn = vkGetDeviceProcAddr(device, name);
        if (!fn && alt) fn = vkGetDeviceProcAddr(device, alt);
    }
    if (!fn && g_xvk_ext_instance != VK_NULL_HANDLE) {
        fn = vkGetInstanceProcAddr(g_xvk_ext_instance, name);
        if (!fn && alt) fn = vkGetInstanceProcAddr(g_xvk_ext_instance, alt);
    }
    if (!fn) {
        if (device == VK_NULL_HANDLE && g_xvk_ext_instance == VK_NULL_HANDLE)
            xvk_set_error_fmt("%s: no VkDevice registered (call xvk_ext_load_device)", name);
        else
            xvk_set_error_fmt("%s: entry point not available (extension not enabled?)", name);
    }
    return fn;
}

#define XVK_EXT_I(fn, inst)                                   \
    static PFN_##fn s_pfn = NULL;                             \
    static uint32_t s_gen = 0;                                \
    if (s_gen != g_xvk_ext_igen) {                            \
        s_pfn = (PFN_##fn)xvk_ext_iproc((inst), #fn);         \
        s_gen = g_xvk_ext_igen;                               \
    }

#define XVK_EXT_DA(fn, alt, dev)                              \
    static PFN_##fn s_pfn = NULL;                             \
    static uint32_t s_gen = 0;                                \
    if (s_gen != g_xvk_ext_dgen) {                            \
        s_pfn = (PFN_##fn)xvk_ext_dproc((dev), #fn, (alt));   \
        s_gen = g_xvk_ext_dgen;                               \
    }

#define XVK_EXT_D(fn, dev) XVK_EXT_DA(fn, NULL, dev)

/* ------------------------------------------------------------------ */
/* VK_EXT_debug_utils                                                  */
/* ------------------------------------------------------------------ */

int32_t xvk_create_debug_utils_messenger_ext(int64_t instance, int64_t create_info_struct)
{
    XVK_EXT_I(vkCreateDebugUtilsMessengerEXT, XVK_EXT_INSTH(instance))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!instance || !create_info_struct) {
        xvk_set_error("vkCreateDebugUtilsMessengerEXT: null instance/create_info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    VkResult res = s_pfn(XVK_EXT_INSTH(instance),
                         XVK_EXT_CPTR(VkDebugUtilsMessengerCreateInfoEXT, create_info_struct),
                         NULL, &messenger);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDebugUtilsMessengerEXT failed: %d", (int)res);
        return (int32_t)res;
    }
    if (g_xvk_ext_messenger_count < XVK_EXT_MAX_MESSENGERS)
        g_xvk_ext_messengers[g_xvk_ext_messenger_count++] = messenger;
    return (int32_t)res;
}

void xvk_destroy_debug_utils_messenger_ext(int64_t instance, int64_t messenger)
{
    XVK_EXT_I(vkDestroyDebugUtilsMessengerEXT, XVK_EXT_INSTH(instance))
    if (!s_pfn || !instance) return;
    VkDebugUtilsMessengerEXT m = XVK_EXT_NDISP(VkDebugUtilsMessengerEXT, messenger);
    if (m == VK_NULL_HANDLE) {
        if (g_xvk_ext_messenger_count <= 0) return;
        m = g_xvk_ext_messengers[--g_xvk_ext_messenger_count];
    } else {
        for (int i = 0; i < g_xvk_ext_messenger_count; i++) {
            if (g_xvk_ext_messengers[i] == m) {
                g_xvk_ext_messengers[i] = g_xvk_ext_messengers[--g_xvk_ext_messenger_count];
                break;
            }
        }
    }
    s_pfn(XVK_EXT_INSTH(instance), m, NULL);
}

void xvk_set_debug_utils_object_name_ext(int64_t device, int64_t name_info_struct)
{
    XVK_EXT_I(vkSetDebugUtilsObjectNameEXT, VK_NULL_HANDLE)
    if (!s_pfn || !device || !name_info_struct) return;
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkDebugUtilsObjectNameInfoEXT, name_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkSetDebugUtilsObjectNameEXT failed: %d", (int)res);
}

void xvk_set_debug_utils_object_tag_ext(int64_t device, int64_t tag_info_struct)
{
    XVK_EXT_I(vkSetDebugUtilsObjectTagEXT, VK_NULL_HANDLE)
    if (!s_pfn || !device || !tag_info_struct) return;
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkDebugUtilsObjectTagInfoEXT, tag_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkSetDebugUtilsObjectTagEXT failed: %d", (int)res);
}

void xvk_queue_begin_debug_utils_label_ext(int64_t queue, int64_t label_info_struct)
{
    XVK_EXT_I(vkQueueBeginDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !queue || !label_info_struct) return;
    s_pfn(XVK_EXT_QUEUEH(queue), XVK_EXT_CPTR(VkDebugUtilsLabelEXT, label_info_struct));
}

void xvk_queue_end_debug_utils_label_ext(int64_t queue)
{
    XVK_EXT_I(vkQueueEndDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !queue) return;
    s_pfn(XVK_EXT_QUEUEH(queue));
}

void xvk_queue_insert_debug_utils_label_ext(int64_t queue, int64_t label_info_struct)
{
    XVK_EXT_I(vkQueueInsertDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !queue || !label_info_struct) return;
    s_pfn(XVK_EXT_QUEUEH(queue), XVK_EXT_CPTR(VkDebugUtilsLabelEXT, label_info_struct));
}

void xvk_cmd_begin_debug_utils_label_ext(int64_t cmd_buf, int64_t label_info_struct)
{
    XVK_EXT_I(vkCmdBeginDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !label_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkDebugUtilsLabelEXT, label_info_struct));
}

void xvk_cmd_end_debug_utils_label_ext(int64_t cmd_buf)
{
    XVK_EXT_I(vkCmdEndDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf));
}

void xvk_cmd_insert_debug_utils_label_ext(int64_t cmd_buf, int64_t label_info_struct)
{
    XVK_EXT_I(vkCmdInsertDebugUtilsLabelEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !label_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkDebugUtilsLabelEXT, label_info_struct));
}

/* ------------------------------------------------------------------ */
/* VK_EXT_mesh_shader                                                  */
/* ------------------------------------------------------------------ */

void xvk_cmd_draw_mesh_tasks_ext(int64_t cmd_buf, int32_t group_count_x, int32_t group_count_y, int32_t group_count_z)
{
    XVK_EXT_D(vkCmdDrawMeshTasksEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)group_count_x, (uint32_t)group_count_y, (uint32_t)group_count_z);
}

void xvk_cmd_draw_mesh_tasks_indirect_ext(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t draw_count, int32_t stride)
{
    XVK_EXT_D(vkCmdDrawMeshTasksIndirectEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !buffer) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_NDISP(VkBuffer, buffer), (VkDeviceSize)offset,
          (uint32_t)draw_count, (uint32_t)stride);
}

void xvk_cmd_draw_mesh_tasks_indirect_count_ext(int64_t cmd_buf, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride)
{
    XVK_EXT_D(vkCmdDrawMeshTasksIndirectCountEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !buffer || !count_buffer) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_NDISP(VkBuffer, buffer), (VkDeviceSize)offset,
          XVK_EXT_NDISP(VkBuffer, count_buffer), (VkDeviceSize)count_offset,
          (uint32_t)max_draw_count, (uint32_t)stride);
}

/* ------------------------------------------------------------------ */
/* VK_EXT_extended_dynamic_state / 2 / 3 + VK_EXT_color_write_enable   */
/* ------------------------------------------------------------------ */

void xvk_cmd_set_cull_mode_ext(int64_t cmd_buf, int32_t cull_mode)
{
    XVK_EXT_DA(vkCmdSetCullModeEXT, "vkCmdSetCullMode", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkCullModeFlags)cull_mode);
}

void xvk_cmd_set_front_face_ext(int64_t cmd_buf, int32_t front_face)
{
    XVK_EXT_DA(vkCmdSetFrontFaceEXT, "vkCmdSetFrontFace", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkFrontFace)front_face);
}

void xvk_cmd_set_primitive_topology_ext(int64_t cmd_buf, int32_t topology)
{
    XVK_EXT_DA(vkCmdSetPrimitiveTopologyEXT, "vkCmdSetPrimitiveTopology", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkPrimitiveTopology)topology);
}

void xvk_cmd_set_viewport_with_count_ext(int64_t cmd_buf, int32_t count, int64_t viewports_struct)
{
    XVK_EXT_DA(vkCmdSetViewportWithCountEXT, "vkCmdSetViewportWithCount", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !viewports_struct || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)count, XVK_EXT_CPTR(VkViewport, viewports_struct));
}

void xvk_cmd_set_scissor_with_count_ext(int64_t cmd_buf, int32_t count, int64_t scissors_struct)
{
    XVK_EXT_DA(vkCmdSetScissorWithCountEXT, "vkCmdSetScissorWithCount", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !scissors_struct || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)count, XVK_EXT_CPTR(VkRect2D, scissors_struct));
}

void xvk_cmd_set_depth_test_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetDepthTestEnableEXT, "vkCmdSetDepthTestEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_depth_write_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetDepthWriteEnableEXT, "vkCmdSetDepthWriteEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_depth_compare_op_ext(int64_t cmd_buf, int32_t compare_op)
{
    XVK_EXT_DA(vkCmdSetDepthCompareOpEXT, "vkCmdSetDepthCompareOp", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkCompareOp)compare_op);
}

void xvk_cmd_set_stencil_test_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetStencilTestEnableEXT, "vkCmdSetStencilTestEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_stencil_op_ext(int64_t cmd_buf, int32_t face_mask, int32_t fail_op, int32_t pass_op, int32_t depth_fail_op, int32_t compare_op)
{
    XVK_EXT_DA(vkCmdSetStencilOpEXT, "vkCmdSetStencilOp", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkStencilFaceFlags)face_mask, (VkStencilOp)fail_op,
          (VkStencilOp)pass_op, (VkStencilOp)depth_fail_op, (VkCompareOp)compare_op);
}

void xvk_cmd_set_rasterizer_discard_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetRasterizerDiscardEnableEXT, "vkCmdSetRasterizerDiscardEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_depth_bias_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetDepthBiasEnableEXT, "vkCmdSetDepthBiasEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_primitive_restart_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_DA(vkCmdSetPrimitiveRestartEnableEXT, "vkCmdSetPrimitiveRestartEnable", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_color_write_enable_ext(int64_t cmd_buf, int32_t count, int64_t enables)
{
    XVK_EXT_D(vkCmdSetColorWriteEnableEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !enables || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)count, XVK_EXT_CPTR(VkBool32, enables));
}

void xvk_cmd_set_logic_op_ext(int64_t cmd_buf, int32_t logic_op)
{
    XVK_EXT_D(vkCmdSetLogicOpEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkLogicOp)logic_op);
}

void xvk_cmd_set_polygon_mode_ext(int64_t cmd_buf, int32_t polygon_mode)
{
    XVK_EXT_D(vkCmdSetPolygonModeEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkPolygonMode)polygon_mode);
}

void xvk_cmd_set_rasterization_samples_ext(int64_t cmd_buf, int32_t samples)
{
    XVK_EXT_D(vkCmdSetRasterizationSamplesEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    g_xvk_ext_samples = (VkSampleCountFlagBits)samples;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkSampleCountFlagBits)samples);
}

void xvk_cmd_set_sample_mask_ext(int64_t cmd_buf, int32_t sample_mask)
{
    XVK_EXT_D(vkCmdSetSampleMaskEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    VkSampleMask masks[2];
    masks[0] = (VkSampleMask)sample_mask;
    masks[1] = (VkSampleMask)sample_mask;
    s_pfn(XVK_EXT_CB(cmd_buf), g_xvk_ext_samples, masks);
}

void xvk_cmd_set_alpha_to_coverage_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_D(vkCmdSetAlphaToCoverageEnableEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_color_blend_enable_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t enables)
{
    XVK_EXT_D(vkCmdSetColorBlendEnableEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !enables || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first, (uint32_t)count, XVK_EXT_CPTR(VkBool32, enables));
}

void xvk_cmd_set_color_blend_equation_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t equations_struct)
{
    XVK_EXT_D(vkCmdSetColorBlendEquationEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !equations_struct || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first, (uint32_t)count,
          XVK_EXT_CPTR(VkColorBlendEquationEXT, equations_struct));
}

void xvk_cmd_set_color_write_mask_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t masks)
{
    XVK_EXT_D(vkCmdSetColorWriteMaskEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !masks || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first, (uint32_t)count,
          XVK_EXT_CPTR(VkColorComponentFlags, masks));
}

void xvk_cmd_set_vertex_input_ext(int64_t cmd_buf, int32_t binding_count, int64_t binding_descs_struct, int32_t attr_count, int64_t attr_descs_struct)
{
    XVK_EXT_D(vkCmdSetVertexInputEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf),
          (uint32_t)binding_count, XVK_EXT_CPTR(VkVertexInputBindingDescription2EXT, binding_descs_struct),
          (uint32_t)attr_count, XVK_EXT_CPTR(VkVertexInputAttributeDescription2EXT, attr_descs_struct));
}

/* ------------------------------------------------------------------ */
/* VK_EXT_conditional_rendering                                        */
/* ------------------------------------------------------------------ */

void xvk_cmd_begin_conditional_rendering_ext(int64_t cmd_buf, int64_t conditional_rendering_begin_struct)
{
    XVK_EXT_D(vkCmdBeginConditionalRenderingEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !conditional_rendering_begin_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf),
          XVK_EXT_CPTR(VkConditionalRenderingBeginInfoEXT, conditional_rendering_begin_struct));
}

void xvk_cmd_end_conditional_rendering_ext(int64_t cmd_buf)
{
    XVK_EXT_D(vkCmdEndConditionalRenderingEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf));
}

/* ------------------------------------------------------------------ */
/* VK_EXT_transform_feedback                                           */
/* ------------------------------------------------------------------ */

void xvk_cmd_bind_transform_feedback_buffers_ext(int64_t cmd_buf, int32_t first_binding, int32_t count, int64_t buffers, int64_t offsets, int64_t sizes)
{
    XVK_EXT_D(vkCmdBindTransformFeedbackBuffersEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !buffers || !offsets || count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first_binding, (uint32_t)count,
          XVK_EXT_CPTR(VkBuffer, buffers), XVK_EXT_CPTR(VkDeviceSize, offsets),
          XVK_EXT_CPTR(VkDeviceSize, sizes));
}

void xvk_cmd_begin_transform_feedback_ext(int64_t cmd_buf, int32_t first_counter_buffer, int32_t counter_buffer_count, int64_t counter_buffers, int64_t counter_buffer_offsets)
{
    XVK_EXT_D(vkCmdBeginTransformFeedbackEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first_counter_buffer, (uint32_t)counter_buffer_count,
          XVK_EXT_CPTR(VkBuffer, counter_buffers), XVK_EXT_CPTR(VkDeviceSize, counter_buffer_offsets));
}

void xvk_cmd_end_transform_feedback_ext(int64_t cmd_buf, int32_t first_counter_buffer, int32_t counter_buffer_count, int64_t counter_buffers, int64_t counter_buffer_offsets)
{
    XVK_EXT_D(vkCmdEndTransformFeedbackEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)first_counter_buffer, (uint32_t)counter_buffer_count,
          XVK_EXT_CPTR(VkBuffer, counter_buffers), XVK_EXT_CPTR(VkDeviceSize, counter_buffer_offsets));
}

/* ------------------------------------------------------------------ */
/* VK_KHR_push_descriptor                                              */
/* ------------------------------------------------------------------ */

void xvk_cmd_push_descriptor_set_khr(int64_t cmd_buf, int32_t bind_point, int64_t layout, int32_t set, int32_t descriptor_write_count, int64_t descriptor_writes_struct)
{
    XVK_EXT_DA(vkCmdPushDescriptorSetKHR, "vkCmdPushDescriptorSet", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !layout || !descriptor_writes_struct || descriptor_write_count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkPipelineBindPoint)bind_point,
          XVK_EXT_NDISP(VkPipelineLayout, layout), (uint32_t)set,
          (uint32_t)descriptor_write_count,
          XVK_EXT_CPTR(VkWriteDescriptorSet, descriptor_writes_struct));
}

void xvk_cmd_push_descriptor_set_with_template_khr(int64_t cmd_buf, int64_t descriptor_update_template, int64_t layout, int32_t set, int64_t data)
{
    XVK_EXT_DA(vkCmdPushDescriptorSetWithTemplateKHR, "vkCmdPushDescriptorSetWithTemplate", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !descriptor_update_template || !layout) return;
    s_pfn(XVK_EXT_CB(cmd_buf),
          XVK_EXT_NDISP(VkDescriptorUpdateTemplate, descriptor_update_template),
          XVK_EXT_NDISP(VkPipelineLayout, layout), (uint32_t)set,
          (const void*)(intptr_t)data);
}

/* ------------------------------------------------------------------ */
/* VK_KHR_fragment_shading_rate                                        */
/* ------------------------------------------------------------------ */

void xvk_cmd_set_fragment_shading_rate_khr(int64_t cmd_buf, int64_t fragment_size_struct, int32_t combiner_ops[2])
{
    XVK_EXT_D(vkCmdSetFragmentShadingRateKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !fragment_size_struct) return;
    VkFragmentShadingRateCombinerOpKHR ops[2];
    ops[0] = combiner_ops ? (VkFragmentShadingRateCombinerOpKHR)combiner_ops[0]
                          : VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR;
    ops[1] = combiner_ops ? (VkFragmentShadingRateCombinerOpKHR)combiner_ops[1]
                          : VK_FRAGMENT_SHADING_RATE_COMBINER_OP_KEEP_KHR;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkExtent2D, fragment_size_struct), ops);
}

/* ------------------------------------------------------------------ */
/* VK_EXT_sample_locations (+ EDS3 enable)                             */
/* ------------------------------------------------------------------ */

void xvk_cmd_set_sample_locations_enable_ext(int64_t cmd_buf, int32_t enable)
{
    XVK_EXT_D(vkCmdSetSampleLocationsEnableEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_BOOL(enable));
}

void xvk_cmd_set_sample_locations_ext(int64_t cmd_buf, int64_t sample_locations_info_struct)
{
    XVK_EXT_D(vkCmdSetSampleLocationsEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !sample_locations_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkSampleLocationsInfoEXT, sample_locations_info_struct));
}

/* ------------------------------------------------------------------ */
/* VK_EXT_line_rasterization                                           */
/* ------------------------------------------------------------------ */

void xvk_cmd_set_line_stipple_ext(int64_t cmd_buf, int32_t line_stipple_factor, int16_t line_stipple_pattern)
{
    XVK_EXT_DA(vkCmdSetLineStippleEXT, "vkCmdSetLineStipple", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)line_stipple_factor, (uint16_t)line_stipple_pattern);
}

/* ------------------------------------------------------------------ */
/* VK_KHR_copy_commands2                                               */
/* ------------------------------------------------------------------ */

void xvk_cmd_copy_buffer2_khr(int64_t cmd_buf, int64_t copy_buffer_info_struct)
{
    XVK_EXT_DA(vkCmdCopyBuffer2KHR, "vkCmdCopyBuffer2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !copy_buffer_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkCopyBufferInfo2, copy_buffer_info_struct));
}

void xvk_cmd_copy_image2_khr(int64_t cmd_buf, int64_t copy_image_info_struct)
{
    XVK_EXT_DA(vkCmdCopyImage2KHR, "vkCmdCopyImage2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !copy_image_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkCopyImageInfo2, copy_image_info_struct));
}

void xvk_cmd_blit_image2_khr(int64_t cmd_buf, int64_t blit_image_info_struct)
{
    XVK_EXT_DA(vkCmdBlitImage2KHR, "vkCmdBlitImage2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !blit_image_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkBlitImageInfo2, blit_image_info_struct));
}

void xvk_cmd_copy_buffer_to_image2_khr(int64_t cmd_buf, int64_t copy_buffer_to_image_info_struct)
{
    XVK_EXT_DA(vkCmdCopyBufferToImage2KHR, "vkCmdCopyBufferToImage2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !copy_buffer_to_image_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkCopyBufferToImageInfo2, copy_buffer_to_image_info_struct));
}

void xvk_cmd_copy_image_to_buffer2_khr(int64_t cmd_buf, int64_t copy_image_to_buffer_info_struct)
{
    XVK_EXT_DA(vkCmdCopyImageToBuffer2KHR, "vkCmdCopyImageToBuffer2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !copy_image_to_buffer_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkCopyImageToBufferInfo2, copy_image_to_buffer_info_struct));
}

void xvk_cmd_resolve_image2_khr(int64_t cmd_buf, int64_t resolve_image_info_struct)
{
    XVK_EXT_DA(vkCmdResolveImage2KHR, "vkCmdResolveImage2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !resolve_image_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkResolveImageInfo2, resolve_image_info_struct));
}

/* ------------------------------------------------------------------ */
/* VK_EXT_host_image_copy                                              */
/* ------------------------------------------------------------------ */

int32_t xvk_copy_memory_to_image_ext(int64_t device, int64_t copy_memory_to_image_info_struct)
{
    XVK_EXT_DA(vkCopyMemoryToImageEXT, "vkCopyMemoryToImage", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !copy_memory_to_image_info_struct) {
        xvk_set_error("vkCopyMemoryToImageEXT: null device/info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkCopyMemoryToImageInfoEXT, copy_memory_to_image_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkCopyMemoryToImageEXT failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_copy_image_to_memory_ext(int64_t device, int64_t copy_image_to_memory_info_struct)
{
    XVK_EXT_DA(vkCopyImageToMemoryEXT, "vkCopyImageToMemory", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !copy_image_to_memory_info_struct) {
        xvk_set_error("vkCopyImageToMemoryEXT: null device/info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkCopyImageToMemoryInfoEXT, copy_image_to_memory_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkCopyImageToMemoryEXT failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_copy_image_to_image_ext(int64_t device, int64_t copy_image_to_image_info_struct)
{
    XVK_EXT_DA(vkCopyImageToImageEXT, "vkCopyImageToImage", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !copy_image_to_image_info_struct) {
        xvk_set_error("vkCopyImageToImageEXT: null device/info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkCopyImageToImageInfoEXT, copy_image_to_image_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkCopyImageToImageEXT failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_transition_image_layout_ext(int64_t device, int32_t transition_count, int64_t transitions_struct)
{
    XVK_EXT_DA(vkTransitionImageLayoutEXT, "vkTransitionImageLayout", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !transitions_struct || transition_count <= 0) {
        xvk_set_error("vkTransitionImageLayoutEXT: null device/transitions");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device), (uint32_t)transition_count,
                         XVK_EXT_CPTR(VkHostImageLayoutTransitionInfoEXT, transitions_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkTransitionImageLayoutEXT failed: %d", (int)res);
    return (int32_t)res;
}

/* ------------------------------------------------------------------ */
/* VK_KHR_timeline_semaphore                                           */
/* ------------------------------------------------------------------ */

int32_t xvk_get_semaphore_counter_value_khr(int64_t device, int64_t semaphore, int64_t out_value)
{
    XVK_EXT_DA(vkGetSemaphoreCounterValueKHR, "vkGetSemaphoreCounterValue", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !semaphore || !out_value) {
        xvk_set_error("vkGetSemaphoreCounterValueKHR: null device/semaphore/out_value");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkSemaphore, semaphore),
                         XVK_EXT_MPTR(uint64_t, out_value));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkGetSemaphoreCounterValueKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_wait_semaphores_khr(int64_t device, int64_t wait_info_struct, int64_t timeout)
{
    XVK_EXT_DA(vkWaitSemaphoresKHR, "vkWaitSemaphores", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !wait_info_struct) {
        xvk_set_error("vkWaitSemaphoresKHR: null device/wait_info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkSemaphoreWaitInfo, wait_info_struct), (uint64_t)timeout);
    if (res != VK_SUCCESS && res != VK_TIMEOUT)
        xvk_set_error_fmt("vkWaitSemaphoresKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_signal_semaphore_khr(int64_t device, int64_t signal_info_struct)
{
    XVK_EXT_DA(vkSignalSemaphoreKHR, "vkSignalSemaphore", XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !signal_info_struct) {
        xvk_set_error("vkSignalSemaphoreKHR: null device/signal_info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkSemaphoreSignalInfo, signal_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkSignalSemaphoreKHR failed: %d", (int)res);
    return (int32_t)res;
}

/* ------------------------------------------------------------------ */
/* VK_KHR_dynamic_rendering                                            */
/* ------------------------------------------------------------------ */

void xvk_cmd_begin_rendering_khr(int64_t cmd_buf, int64_t rendering_info_struct)
{
    XVK_EXT_DA(vkCmdBeginRenderingKHR, "vkCmdBeginRendering", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !rendering_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkRenderingInfo, rendering_info_struct));
}

void xvk_cmd_end_rendering_khr(int64_t cmd_buf)
{
    XVK_EXT_DA(vkCmdEndRenderingKHR, "vkCmdEndRendering", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf) return;
    s_pfn(XVK_EXT_CB(cmd_buf));
}

/* ------------------------------------------------------------------ */
/* VK_KHR_synchronization2                                             */
/* ------------------------------------------------------------------ */

void xvk_cmd_pipeline_barrier2_khr(int64_t cmd_buf, int64_t dependency_info_struct)
{
    XVK_EXT_DA(vkCmdPipelineBarrier2KHR, "vkCmdPipelineBarrier2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !dependency_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkDependencyInfo, dependency_info_struct));
}

void xvk_cmd_write_timestamp2_khr(int64_t cmd_buf, int32_t stage, int64_t query_pool, int32_t query)
{
    XVK_EXT_DA(vkCmdWriteTimestamp2KHR, "vkCmdWriteTimestamp2", VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !query_pool) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (VkPipelineStageFlags2)(uint32_t)stage,
          XVK_EXT_NDISP(VkQueryPool, query_pool), (uint32_t)query);
}

int32_t xvk_queue_submit2_khr(int64_t queue, int32_t submit_count, int64_t submits_struct, int64_t fence)
{
    XVK_EXT_DA(vkQueueSubmit2KHR, "vkQueueSubmit2", VK_NULL_HANDLE)
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!queue || (submit_count > 0 && !submits_struct)) {
        xvk_set_error("vkQueueSubmit2KHR: null queue/submits");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_QUEUEH(queue), (uint32_t)submit_count,
                         XVK_EXT_CPTR(VkSubmitInfo2, submits_struct),
                         XVK_EXT_NDISP(VkFence, fence));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkQueueSubmit2KHR failed: %d", (int)res);
    return (int32_t)res;
}

/* ------------------------------------------------------------------ */
/* VK_EXT_shader_object                                                */
/* ------------------------------------------------------------------ */

int32_t xvk_create_shaders_ext(int64_t device, int32_t count, int64_t create_infos_struct, int64_t out_shaders)
{
    XVK_EXT_D(vkCreateShadersEXT, XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !create_infos_struct || !out_shaders || count <= 0) {
        xvk_set_error("vkCreateShadersEXT: null device/create_infos/out_shaders");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device), (uint32_t)count,
                         XVK_EXT_CPTR(VkShaderCreateInfoEXT, create_infos_struct), NULL,
                         XVK_EXT_MPTR(VkShaderEXT, out_shaders));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkCreateShadersEXT failed: %d", (int)res);
    return (int32_t)res;
}

void xvk_destroy_shader_ext(int64_t device, int64_t shader, int64_t allocator)
{
    XVK_EXT_D(vkDestroyShaderEXT, XVK_EXT_DEVH(device))
    if (!s_pfn || !device || !shader) return;
    s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkShaderEXT, shader),
          XVK_EXT_CPTR(VkAllocationCallbacks, allocator));
}

void xvk_cmd_bind_shaders_ext(int64_t cmd_buf, int32_t stage_count, int64_t stages, int64_t shaders)
{
    XVK_EXT_D(vkCmdBindShadersEXT, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !stages || stage_count <= 0) return;
    s_pfn(XVK_EXT_CB(cmd_buf), (uint32_t)stage_count,
          XVK_EXT_CPTR(VkShaderStageFlagBits, stages), XVK_EXT_CPTR(VkShaderEXT, shaders));
}

/* ------------------------------------------------------------------ */
/* VK_KHR_video_queue / decode / encode                                */
/* ------------------------------------------------------------------ */

int64_t xvk_create_video_session_khr(int64_t device, int64_t create_info_struct)
{
    XVK_EXT_D(vkCreateVideoSessionKHR, XVK_EXT_DEVH(device))
    if (!s_pfn || !device || !create_info_struct) return 0;
    VkVideoSessionKHR session = VK_NULL_HANDLE;
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkVideoSessionCreateInfoKHR, create_info_struct),
                         NULL, &session);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateVideoSessionKHR failed: %d", (int)res);
        return 0;
    }
    return XVK_EXT_H64(session);
}

void xvk_destroy_video_session_khr(int64_t device, int64_t session)
{
    XVK_EXT_D(vkDestroyVideoSessionKHR, XVK_EXT_DEVH(device))
    if (!s_pfn || !device || !session) return;
    s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkVideoSessionKHR, session), NULL);
}

int32_t xvk_get_video_session_memory_requirements_khr(int64_t device, int64_t session, int64_t out_count, int64_t out_reqs)
{
    XVK_EXT_D(vkGetVideoSessionMemoryRequirementsKHR, XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !session || !out_count) {
        xvk_set_error("vkGetVideoSessionMemoryRequirementsKHR: null device/session/out_count");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkVideoSessionKHR, session),
                         XVK_EXT_MPTR(uint32_t, out_count),
                         XVK_EXT_MPTR(VkVideoSessionMemoryRequirementsKHR, out_reqs));
    if (res != VK_SUCCESS && res != VK_INCOMPLETE)
        xvk_set_error_fmt("vkGetVideoSessionMemoryRequirementsKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_bind_video_session_memory_khr(int64_t device, int64_t session, int32_t count, int64_t bind_infos_struct)
{
    XVK_EXT_D(vkBindVideoSessionMemoryKHR, XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !session || !bind_infos_struct || count <= 0) {
        xvk_set_error("vkBindVideoSessionMemoryKHR: null device/session/bind_infos");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkVideoSessionKHR, session),
                         (uint32_t)count,
                         XVK_EXT_CPTR(VkBindVideoSessionMemoryInfoKHR, bind_infos_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkBindVideoSessionMemoryKHR failed: %d", (int)res);
    return (int32_t)res;
}

int64_t xvk_create_video_session_parameters_khr(int64_t device, int64_t create_info_struct)
{
    XVK_EXT_D(vkCreateVideoSessionParametersKHR, XVK_EXT_DEVH(device))
    if (!s_pfn || !device || !create_info_struct) return 0;
    VkVideoSessionParametersKHR params = VK_NULL_HANDLE;
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_CPTR(VkVideoSessionParametersCreateInfoKHR, create_info_struct),
                         NULL, &params);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateVideoSessionParametersKHR failed: %d", (int)res);
        return 0;
    }
    return XVK_EXT_H64(params);
}

int32_t xvk_update_video_session_parameters_khr(int64_t device, int64_t session_params, int64_t update_info_struct)
{
    XVK_EXT_D(vkUpdateVideoSessionParametersKHR, XVK_EXT_DEVH(device))
    if (!s_pfn) return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    if (!device || !session_params || !update_info_struct) {
        xvk_set_error("vkUpdateVideoSessionParametersKHR: null device/params/update_info");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = s_pfn(XVK_EXT_DEVH(device),
                         XVK_EXT_NDISP(VkVideoSessionParametersKHR, session_params),
                         XVK_EXT_CPTR(VkVideoSessionParametersUpdateInfoKHR, update_info_struct));
    if (res != VK_SUCCESS)
        xvk_set_error_fmt("vkUpdateVideoSessionParametersKHR failed: %d", (int)res);
    return (int32_t)res;
}

void xvk_destroy_video_session_parameters_khr(int64_t device, int64_t session_params)
{
    XVK_EXT_D(vkDestroyVideoSessionParametersKHR, XVK_EXT_DEVH(device))
    if (!s_pfn || !device || !session_params) return;
    s_pfn(XVK_EXT_DEVH(device), XVK_EXT_NDISP(VkVideoSessionParametersKHR, session_params), NULL);
}

void xvk_cmd_begin_video_coding_khr(int64_t cmd_buf, int64_t begin_info_struct)
{
    XVK_EXT_D(vkCmdBeginVideoCodingKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !begin_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkVideoBeginCodingInfoKHR, begin_info_struct));
}

void xvk_cmd_end_video_coding_khr(int64_t cmd_buf, int64_t end_info_struct)
{
    XVK_EXT_D(vkCmdEndVideoCodingKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !end_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkVideoEndCodingInfoKHR, end_info_struct));
}

void xvk_cmd_control_video_coding_khr(int64_t cmd_buf, int64_t control_info_struct)
{
    XVK_EXT_D(vkCmdControlVideoCodingKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !control_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkVideoCodingControlInfoKHR, control_info_struct));
}

void xvk_cmd_decode_video_khr(int64_t cmd_buf, int64_t decode_info_struct)
{
    XVK_EXT_D(vkCmdDecodeVideoKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !decode_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkVideoDecodeInfoKHR, decode_info_struct));
}

void xvk_cmd_encode_video_khr(int64_t cmd_buf, int64_t encode_info_struct)
{
    XVK_EXT_D(vkCmdEncodeVideoKHR, VK_NULL_HANDLE)
    if (!s_pfn || !cmd_buf || !encode_info_struct) return;
    s_pfn(XVK_EXT_CB(cmd_buf), XVK_EXT_CPTR(VkVideoEncodeInfoKHR, encode_info_struct));
}

/* ======================================================================== */
/* Phase 8.1: Validation message capture ring buffer                       */
/* ======================================================================== */

#define XVK_VAL_MAX_MSGS 64
#define XVK_VAL_MSG_LEN  256

static char  g_xvk_val_msgs[XVK_VAL_MAX_MSGS][XVK_VAL_MSG_LEN];
static int   g_xvk_val_count = 0;
static int   g_xvk_val_head  = 0;

static VKAPI_ATTR VkBool32 VKAPI_CALL xvk_debug_callback(
    VkDebugUtilsMessageSeverityFlagBitsEXT      messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT             messageTypes,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void*                                       pUserData)
{
    (void)pUserData;
    (void)messageTypes;

    if (g_xvk_val_count >= XVK_VAL_MAX_MSGS)
        return VK_FALSE;  /* buffer full, drop message */

    const char* severity_str = "INFO";
    if (messageSeverity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT)
        severity_str = "WARN";
    if (messageSeverity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT)
        severity_str = "ERROR";
    if (messageSeverity & VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT)
        severity_str = "VERBOSE";

    int idx = g_xvk_val_head;
    snprintf(g_xvk_val_msgs[idx], XVK_VAL_MSG_LEN,
             "[%s] %s",
             severity_str,
             pCallbackData ? pCallbackData->pMessage : "(null)");

    /* Append object names if present */
    if (pCallbackData && pCallbackData->objectCount > 0) {
        int len = (int)strlen(g_xvk_val_msgs[idx]);
        int remaining = XVK_VAL_MSG_LEN - len - 1;
        if (remaining > 3) {
            snprintf(g_xvk_val_msgs[idx] + len, (size_t)remaining,
                     " | objects: %u", pCallbackData->objectCount);
        }
    }

    g_xvk_val_head = (g_xvk_val_head + 1) % XVK_VAL_MAX_MSGS;
    if (g_xvk_val_count < XVK_VAL_MAX_MSGS)
        g_xvk_val_count++;

    return VK_FALSE;  /* VK_FALSE = continue, don't abort */
}

int64_t xvk_create_debug_messenger_default(int64_t instance,
                                            int32_t severity_mask,
                                            int32_t type_mask)
{
    VkInstance inst = (VkInstance)(intptr_t)instance;
    if (!inst) { xvk_set_error("xvk_create_debug_messenger_default: null instance"); return 0; }

    /* Clear any previous validation messages */
    g_xvk_val_count = 0;
    g_xvk_val_head  = 0;

    VkDebugUtilsMessengerCreateInfoEXT ci = {0};
    ci.sType           = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    ci.messageSeverity = (VkDebugUtilsMessageSeverityFlagsEXT)severity_mask;
    ci.messageType     = (VkDebugUtilsMessageTypeFlagsEXT)type_mask;
    ci.pfnUserCallback = xvk_debug_callback;
    ci.pUserData       = NULL;

    VkDebugUtilsMessengerEXT messenger = VK_NULL_HANDLE;
    PFN_vkCreateDebugUtilsMessengerEXT pfn =
        (PFN_vkCreateDebugUtilsMessengerEXT)vkGetInstanceProcAddr(
            inst, "vkCreateDebugUtilsMessengerEXT");
    if (!pfn) {
        xvk_set_error("vkCreateDebugUtilsMessengerEXT not available");
        return 0;
    }
    VkResult res = pfn(inst, &ci, NULL, &messenger);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDebugUtilsMessengerEXT failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)messenger;
}

int32_t xvk_get_validation_messages(int64_t out_count, int64_t out_buffer)
{
    int32_t* count_ptr = (int32_t*)(intptr_t)out_count;
    const char** buf = (const char**)(intptr_t)out_buffer;
    if (!count_ptr || !buf || g_xvk_val_count == 0) {
        if (count_ptr) *count_ptr = 0;
        return 0;
    }

    int cnt = g_xvk_val_count;
    *count_ptr = (int32_t)cnt;

    /* Messages are stored in order: oldest at (head - count + MAX) % MAX,
     * newest at (head - 1 + MAX) % MAX. Write pointers in chronological order. */
    int start = (g_xvk_val_head - cnt + XVK_VAL_MAX_MSGS) % XVK_VAL_MAX_MSGS;
    for (int i = 0; i < cnt; i++) {
        int idx = (start + i) % XVK_VAL_MAX_MSGS;
        buf[i] = g_xvk_val_msgs[idx];
    }
    return (int32_t)cnt;
}

void xvk_clear_validation_messages(void)
{
    g_xvk_val_count = 0;
    g_xvk_val_head  = 0;
}

#undef XVK_EXT_I
#undef XVK_EXT_DA
#undef XVK_EXT_D
#undef XVK_EXT_DISP
#undef XVK_EXT_NDISP
#undef XVK_EXT_CPTR
#undef XVK_EXT_MPTR
#undef XVK_EXT_H64
#undef XVK_EXT_CB
#undef XVK_EXT_DEVH
#undef XVK_EXT_QUEUEH
#undef XVK_EXT_INSTH
#undef XVK_EXT_BOOL
#undef XVK_EXT_MAX_MESSENGERS
