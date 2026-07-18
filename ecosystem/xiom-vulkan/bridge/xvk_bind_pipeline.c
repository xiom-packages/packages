#include "xvk_bind_pipeline.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_shader_module(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkShaderModuleCreateInfo* ci =
        (const VkShaderModuleCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_shader_module: null device or create info");
        return 0;
    }
    VkShaderModule module = VK_NULL_HANDLE;
    VkResult res = vkCreateShaderModule(dev, ci, NULL, &module);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateShaderModule: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)module;
}

void xvk_destroy_shader_module(int64_t device, int64_t shader)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !shader) return;
    vkDestroyShaderModule(dev, (VkShaderModule)(uint64_t)shader, NULL);
}

int64_t xvk_create_pipeline_layout(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkPipelineLayoutCreateInfo* ci =
        (const VkPipelineLayoutCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_pipeline_layout: null device or create info");
        return 0;
    }
    VkPipelineLayout layout = VK_NULL_HANDLE;
    VkResult res = vkCreatePipelineLayout(dev, ci, NULL, &layout);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineLayout: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)layout;
}

void xvk_destroy_pipeline_layout(int64_t device, int64_t layout)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !layout) return;
    vkDestroyPipelineLayout(dev, (VkPipelineLayout)(uint64_t)layout, NULL);
}

int64_t xvk_create_graphics_pipelines(int64_t device, int64_t cache, int32_t count,
                                      int64_t create_infos_struct, int64_t out_pipelines)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkGraphicsPipelineCreateInfo* cis =
        (const VkGraphicsPipelineCreateInfo*)(intptr_t)create_infos_struct;
    VkPipeline* out = (VkPipeline*)(intptr_t)out_pipelines;
    if (!dev || !cis || !out || count <= 0) {
        xvk_set_error("xvk_create_graphics_pipelines: invalid arguments");
        return (int64_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkCreateGraphicsPipelines(dev, (VkPipelineCache)(uint64_t)cache,
                                             (uint32_t)count, cis, NULL, out);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateGraphicsPipelines: %d", (int)res);
    }
    return (int64_t)res;
}

int64_t xvk_create_compute_pipelines(int64_t device, int64_t cache, int32_t count,
                                     int64_t create_infos_struct, int64_t out_pipelines)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkComputePipelineCreateInfo* cis =
        (const VkComputePipelineCreateInfo*)(intptr_t)create_infos_struct;
    VkPipeline* out = (VkPipeline*)(intptr_t)out_pipelines;
    if (!dev || !cis || !out || count <= 0) {
        xvk_set_error("xvk_create_compute_pipelines: invalid arguments");
        return (int64_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkCreateComputePipelines(dev, (VkPipelineCache)(uint64_t)cache,
                                            (uint32_t)count, cis, NULL, out);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateComputePipelines: %d", (int)res);
    }
    return (int64_t)res;
}

void xvk_destroy_pipeline(int64_t device, int64_t pipeline)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !pipeline) return;
    vkDestroyPipeline(dev, (VkPipeline)(uint64_t)pipeline, NULL);
}

int64_t xvk_create_pipeline_cache(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkPipelineCacheCreateInfo* ci =
        (const VkPipelineCacheCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_pipeline_cache: null device or create info");
        return 0;
    }
    VkPipelineCache pcache = VK_NULL_HANDLE;
    VkResult res = vkCreatePipelineCache(dev, ci, NULL, &pcache);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineCache: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)pcache;
}

void xvk_destroy_pipeline_cache(int64_t device, int64_t cache)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !cache) return;
    vkDestroyPipelineCache(dev, (VkPipelineCache)(uint64_t)cache, NULL);
}
