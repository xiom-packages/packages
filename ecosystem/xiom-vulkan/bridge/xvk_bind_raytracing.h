#ifndef XVK_BIND_RAYTRACING_H_
#define XVK_BIND_RAYTRACING_H_

#include <stdint.h>

/*
 * xvk_bind_raytracing — flat C ABI over the Vulkan ray tracing extensions:
 *
 *   VK_KHR_acceleration_structure
 *   VK_KHR_ray_tracing_pipeline
 *   VK_NV_ray_tracing            (legacy)
 *   VK_EXT_micromap              (VK_EXT_opacity_micromap headers required)
 *
 * Conventions (raw binding layer — no bridge-side wrapper objects):
 *   - `device` / `cmd_buf` are raw VkDevice / VkCommandBuffer handles.
 *   - All other handle parameters (pipeline, query_pool, deferred_op, ...)
 *     are raw non-dispatchable Vulkan handles (64-bit), 0 = VK_NULL_HANDLE.
 *   - `*_struct` / `*_infos` / `out_*` parameters are raw pointers to fully
 *     populated Vulkan structs or arrays (caller sets sType/pNext), cast to
 *     int64_t. 0 = NULL.
 *   - Functions wrapping a VkResult-returning Vulkan entry point return the
 *     raw VkResult (0 = VK_SUCCESS, negative = error; the error message is
 *     available via xvk_last_error()). Positive success codes such as
 *     VK_OPERATION_DEFERRED_KHR are passed through unchanged.
 *   - Creation helpers return the created handle, 0 on failure.
 *
 * Extension function pointers are resolved through vkGetDeviceProcAddr and
 * cached per device. Device-level entry points (re)load the cache on demand.
 * Command-buffer entry points (`xvk_cmd_*`) use the cache of the most
 * recently referenced device — call xvk_raytracing_load_device_procs()
 * once after device creation (or any device-level function of this module)
 * before recording ray tracing commands.
 *
 * Special parameter layouts (flat-ABI packing):
 *   - xvk_cmd_build_acceleration_structures_khr:
 *       `build_range_infos` points to an array of `info_count` POINTERS,
 *       each pointing to VkAccelerationStructureBuildRangeInfoKHR[geometryCount]
 *       (exactly vkCmdBuildAccelerationStructuresKHR's ppBuildRangeInfos).
 *   - xvk_cmd_build_acceleration_structures_indirect_khr:
 *       `indirect_strides` points to one packed buffer holding
 *       VkDeviceAddress[info_count] (indirect device addresses) immediately
 *       followed by uint32_t[info_count] (indirect strides).
 *       `max_prim_counts` maps to ppMaxPrimitiveCounts: an array of
 *       `info_count` pointers to uint32_t[geometryCount].
 *   - xvk_cmd_build_acceleration_structure_nv:
 *       `acceleration_structure_info_struct` points to an
 *       XvkBuildAccelerationStructureNV bridge struct (see below), because
 *       vkCmdBuildAccelerationStructureNV takes more parameters than the
 *       flat signature carries. `flags` is reserved (pass 0).
 *   - xvk_cmd_trace_rays_nv:
 *       each `*_sbt` points to an XvkSbtRegionNV (see below); 0 means
 *       "no table" (VK_NULL_HANDLE buffer, offset/stride 0). The raygen
 *       region's stride is ignored (the NV API has none).
 *   - xvk_cmd_trace_rays_khr:
 *       each `*_sbt` points to a VkStridedDeviceAddressRegionKHR; 0 means
 *       an all-zero region.
 */

/* Extended parameters for xvk_cmd_build_acceleration_structure_nv. */
typedef struct XvkBuildAccelerationStructureNV {
    int64_t info;             /* const VkAccelerationStructureInfoNV*        */
    int64_t dst;              /* VkAccelerationStructureNV (required)        */
    int64_t src;              /* VkAccelerationStructureNV, 0 if not update  */
    int64_t instance_offset;  /* VkDeviceSize byte offset in instance_data   */
    int64_t scratch_offset;   /* VkDeviceSize byte offset in scratch buffer  */
} XvkBuildAccelerationStructureNV;

/* One shader-binding-table region for xvk_cmd_trace_rays_nv. */
typedef struct XvkSbtRegionNV {
    int64_t buffer;           /* VkBuffer                                    */
    int64_t offset;           /* VkDeviceSize                                */
    int64_t stride;           /* VkDeviceSize (ignored for the raygen table) */
} XvkSbtRegionNV;

/* Capability bits returned by xvk_raytracing_load_device_procs. */
#define XVK_RT_CAP_KHR_ACCELERATION_STRUCTURE 0x1
#define XVK_RT_CAP_KHR_RAY_TRACING_PIPELINE   0x2
#define XVK_RT_CAP_NV_RAY_TRACING             0x4
#define XVK_RT_CAP_EXT_MICROMAP               0x8

/* Loads (or reloads) the extension proc cache for `device` and makes it the
 * current device for xvk_cmd_* calls. Returns an XVK_RT_CAP_* bitmask of the
 * ray tracing extensions actually enabled on the device (0 = none). */
int32_t xvk_raytracing_load_device_procs(int64_t device);

/* ---- VK_KHR_acceleration_structure ------------------------------------- */

int64_t xvk_create_acceleration_structure_khr(int64_t device, int64_t create_info_struct);
void    xvk_destroy_acceleration_structure_khr(int64_t device, int64_t as);
int32_t xvk_get_acceleration_structure_build_sizes_khr(int64_t device, int32_t build_type, int64_t build_info_struct, int64_t max_prim_counts, int64_t out_size_info);
void    xvk_cmd_build_acceleration_structures_khr(int64_t cmd_buf, int32_t info_count, int64_t infos_struct, int64_t build_range_infos);
void    xvk_cmd_build_acceleration_structures_indirect_khr(int64_t cmd_buf, int32_t info_count, int64_t infos_struct, int64_t indirect_strides, int64_t max_prim_counts);
void    xvk_cmd_copy_acceleration_structure_khr(int64_t cmd_buf, int64_t copy_info_struct);
void    xvk_cmd_copy_acceleration_structure_to_memory_khr(int64_t cmd_buf, int64_t copy_info_struct);
void    xvk_cmd_copy_memory_to_acceleration_structure_khr(int64_t cmd_buf, int64_t copy_info_struct);
int64_t xvk_copy_acceleration_structure_khr(int64_t device, int64_t deferred_op, int64_t copy_info_struct);
void    xvk_cmd_write_acceleration_structures_properties_khr(int64_t cmd_buf, int32_t count, int64_t as_handles, int32_t query_type, int64_t query_pool, int32_t first_query);
int64_t xvk_get_acceleration_structure_device_address_khr(int64_t device, int64_t acceleration_structure_info_struct);
int32_t xvk_get_device_acceleration_structure_compatibility_khr(int64_t device, int64_t version_info_struct, int64_t out_compatibility);

/* ---- VK_KHR_ray_tracing_pipeline ---------------------------------------- */

int32_t xvk_create_ray_tracing_pipelines_khr(int64_t device, int64_t deferred_op, int64_t pipeline_cache, int32_t count, int64_t create_infos_struct, int64_t out_pipelines);
void    xvk_cmd_trace_rays_khr(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt, int64_t hit_sbt, int64_t callable_sbt, int32_t width, int32_t height, int32_t depth);
void    xvk_cmd_trace_rays_indirect_khr(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt, int64_t hit_sbt, int64_t callable_sbt, int64_t indirect_device_address);
int32_t xvk_get_ray_tracing_shader_group_handles_khr(int64_t device, int64_t pipeline, int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data);
int32_t xvk_get_ray_tracing_capture_replay_shader_group_handles_khr(int64_t device, int64_t pipeline, int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data);
int64_t xvk_get_ray_tracing_shader_group_stack_size_khr(int64_t device, int64_t pipeline, int32_t group, int32_t group_handle);
void    xvk_cmd_set_ray_tracing_pipeline_stack_size_khr(int64_t cmd_buf, int32_t stack_size);

/* ---- VK_NV_ray_tracing (legacy) ------------------------------------------ */

int32_t xvk_create_ray_tracing_pipelines_nv(int64_t device, int64_t pipeline_cache, int32_t count, int64_t create_infos_struct, int64_t out_pipelines);
int64_t xvk_create_acceleration_structure_nv(int64_t device, int64_t create_info_struct);
void    xvk_destroy_acceleration_structure_nv(int64_t device, int64_t as);
void    xvk_get_acceleration_structure_memory_requirements_nv(int64_t device, int64_t acceleration_structure_info_struct, int64_t out_reqs);
int32_t xvk_bind_acceleration_structure_memory_nv(int64_t device, int32_t count, int64_t bind_infos_struct);
void    xvk_cmd_build_acceleration_structure_nv(int64_t cmd_buf, int64_t acceleration_structure_info_struct, int64_t instance_data, int64_t scratch, int32_t update, int32_t flags);
void    xvk_cmd_copy_acceleration_structure_nv(int64_t cmd_buf, int64_t dst, int64_t src, int32_t mode);
void    xvk_cmd_trace_rays_nv(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt, int64_t hit_sbt, int64_t callable_sbt, int32_t width, int32_t height, int32_t depth);
int32_t xvk_get_ray_tracing_shader_group_handles_nv(int64_t device, int64_t pipeline, int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data);
/* If out_data != 0: fills it and returns the raw VkResult. If out_data == 0:
 * fetches the 8-byte handle internally and returns it directly (0 on failure). */
int64_t xvk_get_acceleration_structure_handle_nv(int64_t device, int64_t as, int64_t data_size, int64_t out_data);
void    xvk_cmd_write_acceleration_structures_properties_nv(int64_t cmd_buf, int32_t count, int64_t as_handles, int32_t query_type, int64_t query_pool, int32_t first_query);
int32_t xvk_compile_deferred_nv(int64_t device, int64_t pipeline, int32_t shader);

/* ---- VK_EXT_micromap ------------------------------------------------------ */

int64_t xvk_create_micromap_ext(int64_t device, int64_t create_info_struct);
void    xvk_destroy_micromap_ext(int64_t device, int64_t micromap);
void    xvk_cmd_build_micromaps_ext(int64_t cmd_buf, int32_t info_count, int64_t infos_struct);
int64_t xvk_build_micromaps_ext(int64_t device, int64_t deferred_op, int32_t info_count, int64_t infos_struct);
int64_t xvk_copy_micromap_ext(int64_t device, int64_t deferred_op, int64_t copy_info_struct);
void    xvk_cmd_copy_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct);
void    xvk_cmd_copy_micromap_to_memory_ext(int64_t cmd_buf, int64_t copy_info_struct);
void    xvk_cmd_copy_memory_to_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct);
void    xvk_cmd_write_micromaps_properties_ext(int64_t cmd_buf, int32_t count, int64_t micromaps, int32_t query_type, int64_t query_pool, int32_t first_query);
int32_t xvk_get_device_micromap_compatibility_ext(int64_t device, int64_t version_info_struct, int64_t out_compatibility);
/* Returns pSizeInfo->micromapSize on success (also written to out_size_info), 0 on failure. */
int64_t xvk_get_micromap_build_sizes_ext(int64_t device, int32_t build_type, int64_t build_info_struct, int64_t out_size_info);

#endif /* XVK_BIND_RAYTRACING_H_ */
