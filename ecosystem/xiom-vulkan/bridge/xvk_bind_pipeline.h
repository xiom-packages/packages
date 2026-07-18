#ifndef XVK_BIND_PIPELINE_H_
#define XVK_BIND_PIPELINE_H_

#include <stdint.h>

/* Direct Vulkan pipeline bindings.
 * Handles are raw Vulkan handles as int64_t (0 = VK_NULL_HANDLE).
 * *_struct parameters are raw pointers (as int64_t) to fully-built Vulkan
 * structs produced by the xvk_structs marshalling layer. */

int64_t xvk_create_shader_module(int64_t device, int64_t create_info_struct);
void xvk_destroy_shader_module(int64_t device, int64_t shader);

int64_t xvk_create_pipeline_layout(int64_t device, int64_t create_info_struct);
void xvk_destroy_pipeline_layout(int64_t device, int64_t layout);

int64_t xvk_create_graphics_pipelines(int64_t device, int64_t cache, int32_t count,
                                      int64_t create_infos_struct, int64_t out_pipelines);
int64_t xvk_create_compute_pipelines(int64_t device, int64_t cache, int32_t count,
                                     int64_t create_infos_struct, int64_t out_pipelines);
void xvk_destroy_pipeline(int64_t device, int64_t pipeline);

int64_t xvk_create_pipeline_cache(int64_t device, int64_t create_info_struct);
void xvk_destroy_pipeline_cache(int64_t device, int64_t cache);

#endif
