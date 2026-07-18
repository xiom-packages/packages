#ifndef XVK_PIPELINE_H_
#define XVK_PIPELINE_H_

#include "xvk_types.h"
#include "xvk_util.h"

VkShaderModule create_shader_module(VkDevice dev,
                                     const unsigned int* code,
                                     unsigned int code_size_bytes);
VkPipelineLayout create_pipeline_layout(VkDevice dev,
                                         VkPushConstantRange* pcrs,
                                         uint32_t pcr_count);
VkPipeline create_graphics_pipeline(VkDevice dev,
    VkPipelineLayout layout, VkRenderPass rp,
    VkShaderModule vert, VkShaderModule frag,
    uint32_t width, uint32_t height,
    int enable_depth);
int create_sync_objects(VkDevice dev, int count,
    VkSemaphore* image_avail, VkSemaphore* render_fin, VkFence* fences);
VkCommandPool create_cmd_pool(VkDevice dev, uint32_t family);
int allocate_cmd_buffers(VkDevice dev, VkCommandPool pool,
                          VkCommandBuffer* bufs, int count);

int64_t xvk_shader_create(int64_t app_h, const unsigned int* code, int32_t code_size);
int64_t xvk_shader_create_named(int64_t app_h, const char* name);
void xvk_shader_destroy(int64_t app_h, int64_t shader_h);

int64_t xvk_pipeline_layout_create(int64_t app_h, int32_t push_size, int32_t push_stages,
                                    int32_t desc_layout_count, const int64_t* desc_layouts);
void xvk_pipeline_layout_destroy(int64_t app_h, int64_t layout_h);

int64_t xvk_pipeline_create_graphics(int64_t app_h,
    int32_t topology, int32_t cull_mode, int32_t depth_test, int32_t depth_write,
    int32_t blend_enable,
    int64_t vertex_shader_h, int64_t fragment_shader_h,
    int64_t layout_h, int64_t render_pass_h,
    const int32_t* bindings, int32_t binding_count,
    const int32_t* attributes, int32_t attr_count);
int64_t xvk_pipeline_create_compute(int64_t app_h, int64_t shader_h, int64_t layout_h);
void xvk_pipeline_destroy(int64_t app_h, int64_t pipeline_h);

void xvk_compute_dispatch(int64_t app_h, int64_t pipeline_h, int64_t layout_h,
                           int32_t x, int32_t y, int32_t z);

#endif
