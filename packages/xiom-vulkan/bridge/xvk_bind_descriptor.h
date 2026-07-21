#ifndef XVK_BIND_DESCRIPTOR_H_
#define XVK_BIND_DESCRIPTOR_H_

#include <stdint.h>

/* Direct Vulkan descriptor bindings.
 * Handles are raw Vulkan handles as int64_t (0 = VK_NULL_HANDLE).
 * *_struct parameters are raw pointers (as int64_t) to fully-built Vulkan
 * structs produced by the xvk_structs marshalling layer. */

int64_t xvk_create_descriptor_set_layout(int64_t device, int64_t create_info_struct);
void xvk_destroy_descriptor_set_layout(int64_t device, int64_t layout);

int64_t xvk_create_descriptor_pool(int64_t device, int64_t create_info_struct);
void xvk_destroy_descriptor_pool(int64_t device, int64_t pool);

int32_t xvk_allocate_descriptor_sets(int64_t device, int64_t allocate_info_struct,
                                     int64_t out_sets);
int32_t xvk_free_descriptor_sets(int64_t device, int64_t pool, int32_t count,
                                 int64_t sets);
void xvk_update_descriptor_sets(int64_t device, int32_t write_count, int64_t writes_struct,
                                int32_t copy_count, int64_t copies_struct);

int64_t xvk_create_descriptor_update_template(int64_t device, int64_t create_info_struct);
void xvk_destroy_descriptor_update_template(int64_t device, int64_t update_template);

#endif
