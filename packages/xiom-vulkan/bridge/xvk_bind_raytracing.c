#include "xvk_bind_raytracing.h"
#include "xvk_util.h"

#include <stdint.h>
#include <string.h>
#include <vulkan/vulkan.h>

/* ---- handle / pointer casts ---------------------------------------------- */

#define XVK_RT_DEV(h)     ((VkDevice)(intptr_t)(h))
#define XVK_RT_CMD(h)     ((VkCommandBuffer)(intptr_t)(h))
#define XVK_RT_PTR(T, h)  ((T)(intptr_t)(h))
#define XVK_RT_NDH(T, h)  ((T)(uint64_t)(h))   /* non-dispatchable handle */
#define XVK_RT_H64(v)     ((int64_t)(uint64_t)(v))

/* ---- per-device extension proc cache ------------------------------------- */

typedef struct XvkRtProcs {
    VkDevice device;

    /* VK_KHR_acceleration_structure */
    PFN_vkCreateAccelerationStructureKHR                 CreateAccelerationStructureKHR;
    PFN_vkDestroyAccelerationStructureKHR                DestroyAccelerationStructureKHR;
    PFN_vkGetAccelerationStructureBuildSizesKHR          GetAccelerationStructureBuildSizesKHR;
    PFN_vkCmdBuildAccelerationStructuresKHR              CmdBuildAccelerationStructuresKHR;
    PFN_vkCmdBuildAccelerationStructuresIndirectKHR      CmdBuildAccelerationStructuresIndirectKHR;
    PFN_vkCmdCopyAccelerationStructureKHR                CmdCopyAccelerationStructureKHR;
    PFN_vkCmdCopyAccelerationStructureToMemoryKHR        CmdCopyAccelerationStructureToMemoryKHR;
    PFN_vkCmdCopyMemoryToAccelerationStructureKHR        CmdCopyMemoryToAccelerationStructureKHR;
    PFN_vkCopyAccelerationStructureKHR                   CopyAccelerationStructureKHR;
    PFN_vkCmdWriteAccelerationStructuresPropertiesKHR    CmdWriteAccelerationStructuresPropertiesKHR;
    PFN_vkGetAccelerationStructureDeviceAddressKHR       GetAccelerationStructureDeviceAddressKHR;
    PFN_vkGetDeviceAccelerationStructureCompatibilityKHR GetDeviceAccelerationStructureCompatibilityKHR;

    /* VK_KHR_ray_tracing_pipeline */
    PFN_vkCreateRayTracingPipelinesKHR                   CreateRayTracingPipelinesKHR;
    PFN_vkCmdTraceRaysKHR                                CmdTraceRaysKHR;
    PFN_vkCmdTraceRaysIndirectKHR                        CmdTraceRaysIndirectKHR;
    PFN_vkGetRayTracingShaderGroupHandlesKHR             GetRayTracingShaderGroupHandlesKHR;
    PFN_vkGetRayTracingCaptureReplayShaderGroupHandlesKHR GetRayTracingCaptureReplayShaderGroupHandlesKHR;
    PFN_vkGetRayTracingShaderGroupStackSizeKHR           GetRayTracingShaderGroupStackSizeKHR;
    PFN_vkCmdSetRayTracingPipelineStackSizeKHR           CmdSetRayTracingPipelineStackSizeKHR;

    /* VK_NV_ray_tracing */
    PFN_vkCreateRayTracingPipelinesNV                    CreateRayTracingPipelinesNV;
    PFN_vkCreateAccelerationStructureNV                  CreateAccelerationStructureNV;
    PFN_vkDestroyAccelerationStructureNV                 DestroyAccelerationStructureNV;
    PFN_vkGetAccelerationStructureMemoryRequirementsNV   GetAccelerationStructureMemoryRequirementsNV;
    PFN_vkBindAccelerationStructureMemoryNV              BindAccelerationStructureMemoryNV;
    PFN_vkCmdBuildAccelerationStructureNV                CmdBuildAccelerationStructureNV;
    PFN_vkCmdCopyAccelerationStructureNV                 CmdCopyAccelerationStructureNV;
    PFN_vkCmdTraceRaysNV                                 CmdTraceRaysNV;
    PFN_vkGetRayTracingShaderGroupHandlesNV              GetRayTracingShaderGroupHandlesNV;
    PFN_vkGetAccelerationStructureHandleNV               GetAccelerationStructureHandleNV;
    PFN_vkCmdWriteAccelerationStructuresPropertiesNV     CmdWriteAccelerationStructuresPropertiesNV;
    PFN_vkCompileDeferredNV                              CompileDeferredNV;

    /* VK_KHR_deferred_host_operations (Phase 7.6) */
    PFN_vkCreateDeferredOperationKHR                     CreateDeferredOperationKHR;
    PFN_vkDestroyDeferredOperationKHR                    DestroyDeferredOperationKHR;
    PFN_vkDeferredOperationJoinKHR                       DeferredOperationJoinKHR;
    PFN_vkGetDeferredOperationResultKHR                  GetDeferredOperationResultKHR;
    PFN_vkGetDeferredOperationMaxConcurrencyKHR          GetDeferredOperationMaxConcurrencyKHR;

#if defined(VK_EXT_opacity_micromap)
    /* VK_EXT_micromap */
    PFN_vkCreateMicromapEXT                              CreateMicromapEXT;
    PFN_vkDestroyMicromapEXT                             DestroyMicromapEXT;
    PFN_vkCmdBuildMicromapsEXT                           CmdBuildMicromapsEXT;
    PFN_vkBuildMicromapsEXT                              BuildMicromapsEXT;
    PFN_vkCopyMicromapEXT                                CopyMicromapEXT;
    PFN_vkCmdCopyMicromapEXT                             CmdCopyMicromapEXT;
    PFN_vkCmdCopyMicromapToMemoryEXT                     CmdCopyMicromapToMemoryEXT;
    PFN_vkCmdCopyMemoryToMicromapEXT                     CmdCopyMemoryToMicromapEXT;
    PFN_vkCmdWriteMicromapsPropertiesEXT                 CmdWriteMicromapsPropertiesEXT;
    PFN_vkGetDeviceMicromapCompatibilityEXT              GetDeviceMicromapCompatibilityEXT;
    PFN_vkGetMicromapBuildSizesEXT                       GetMicromapBuildSizesEXT;
#endif
} XvkRtProcs;

#define XVK_RT_MAX_DEVICES 8

static XvkRtProcs g_xvk_rt_procs[XVK_RT_MAX_DEVICES];
static int        g_xvk_rt_proc_count = 0;
static int        g_xvk_rt_proc_last  = -1;

static const VkStridedDeviceAddressRegionKHR g_xvk_rt_empty_region = {0, 0, 0};
static const XvkSbtRegionNV                  g_xvk_rt_empty_sbt_nv = {0, 0, 0};

#define XVK_RT_LOAD(field) \
    p->field = (PFN_vk##field)vkGetDeviceProcAddr(dev, "vk" #field)

static XvkRtProcs* xvk_rt_load(VkDevice dev)
{
    int slot = -1;
    int i;
    XvkRtProcs* p;

    for (i = 0; i < g_xvk_rt_proc_count; i++) {
        if (g_xvk_rt_procs[i].device == dev) { slot = i; break; }
    }
    if (slot < 0) {
        if (g_xvk_rt_proc_count < XVK_RT_MAX_DEVICES) {
            slot = g_xvk_rt_proc_count++;
        } else {
            slot = (g_xvk_rt_proc_last + 1) % XVK_RT_MAX_DEVICES;
        }
    }

    p = &g_xvk_rt_procs[slot];
    memset(p, 0, sizeof(*p));
    p->device = dev;

    XVK_RT_LOAD(CreateAccelerationStructureKHR);
    XVK_RT_LOAD(DestroyAccelerationStructureKHR);
    XVK_RT_LOAD(GetAccelerationStructureBuildSizesKHR);
    XVK_RT_LOAD(CmdBuildAccelerationStructuresKHR);
    XVK_RT_LOAD(CmdBuildAccelerationStructuresIndirectKHR);
    XVK_RT_LOAD(CmdCopyAccelerationStructureKHR);
    XVK_RT_LOAD(CmdCopyAccelerationStructureToMemoryKHR);
    XVK_RT_LOAD(CmdCopyMemoryToAccelerationStructureKHR);
    XVK_RT_LOAD(CopyAccelerationStructureKHR);
    XVK_RT_LOAD(CmdWriteAccelerationStructuresPropertiesKHR);
    XVK_RT_LOAD(GetAccelerationStructureDeviceAddressKHR);
    XVK_RT_LOAD(GetDeviceAccelerationStructureCompatibilityKHR);

    XVK_RT_LOAD(CreateRayTracingPipelinesKHR);
    XVK_RT_LOAD(CmdTraceRaysKHR);
    XVK_RT_LOAD(CmdTraceRaysIndirectKHR);
    XVK_RT_LOAD(GetRayTracingShaderGroupHandlesKHR);
    XVK_RT_LOAD(GetRayTracingCaptureReplayShaderGroupHandlesKHR);
    XVK_RT_LOAD(GetRayTracingShaderGroupStackSizeKHR);
    XVK_RT_LOAD(CmdSetRayTracingPipelineStackSizeKHR);

    XVK_RT_LOAD(CreateRayTracingPipelinesNV);
    XVK_RT_LOAD(CreateAccelerationStructureNV);
    XVK_RT_LOAD(DestroyAccelerationStructureNV);
    XVK_RT_LOAD(GetAccelerationStructureMemoryRequirementsNV);
    XVK_RT_LOAD(BindAccelerationStructureMemoryNV);
    XVK_RT_LOAD(CmdBuildAccelerationStructureNV);
    XVK_RT_LOAD(CmdCopyAccelerationStructureNV);
    XVK_RT_LOAD(CmdTraceRaysNV);
    XVK_RT_LOAD(GetRayTracingShaderGroupHandlesNV);
    XVK_RT_LOAD(GetAccelerationStructureHandleNV);
    XVK_RT_LOAD(CmdWriteAccelerationStructuresPropertiesNV);
    XVK_RT_LOAD(CompileDeferredNV);

    /* VK_KHR_deferred_host_operations (Phase 7.6) */
    XVK_RT_LOAD(CreateDeferredOperationKHR);
    XVK_RT_LOAD(DestroyDeferredOperationKHR);
    XVK_RT_LOAD(DeferredOperationJoinKHR);
    XVK_RT_LOAD(GetDeferredOperationResultKHR);
    XVK_RT_LOAD(GetDeferredOperationMaxConcurrencyKHR);

#if defined(VK_EXT_opacity_micromap)
    XVK_RT_LOAD(CreateMicromapEXT);
    XVK_RT_LOAD(DestroyMicromapEXT);
    XVK_RT_LOAD(CmdBuildMicromapsEXT);
    XVK_RT_LOAD(BuildMicromapsEXT);
    XVK_RT_LOAD(CopyMicromapEXT);
    XVK_RT_LOAD(CmdCopyMicromapEXT);
    XVK_RT_LOAD(CmdCopyMicromapToMemoryEXT);
    XVK_RT_LOAD(CmdCopyMemoryToMicromapEXT);
    XVK_RT_LOAD(CmdWriteMicromapsPropertiesEXT);
    XVK_RT_LOAD(GetDeviceMicromapCompatibilityEXT);
    XVK_RT_LOAD(GetMicromapBuildSizesEXT);
#endif

    g_xvk_rt_proc_last = slot;
    return p;
}

static XvkRtProcs* xvk_rt_procs(int64_t device_h)
{
    VkDevice dev = XVK_RT_DEV(device_h);
    int i;

    if (!dev) {
        xvk_set_error("xvk raytracing: device handle is 0");
        return NULL;
    }
    for (i = 0; i < g_xvk_rt_proc_count; i++) {
        if (g_xvk_rt_procs[i].device == dev) {
            g_xvk_rt_proc_last = i;
            return &g_xvk_rt_procs[i];
        }
    }
    return xvk_rt_load(dev);
}

static XvkRtProcs* xvk_rt_procs_cmd(void)
{
    if (g_xvk_rt_proc_last < 0) {
        xvk_set_error("xvk raytracing: no device procs loaded; "
                      "call xvk_raytracing_load_device_procs first");
        return NULL;
    }
    return &g_xvk_rt_procs[g_xvk_rt_proc_last];
}

#define XVK_RT_REQUIRE(p, field, retval)                                       \
    do {                                                                       \
        if (!(p)) return retval;                                               \
        if (!(p)->field) {                                                     \
            xvk_set_error_fmt("vk%s unavailable (extension not enabled on "    \
                              "device?)", #field);                             \
            return retval;                                                     \
        }                                                                      \
    } while (0)

#define XVK_RT_REQUIRE_VOID(p, field)                                          \
    do {                                                                       \
        if (!(p)) return;                                                      \
        if (!(p)->field) {                                                     \
            xvk_set_error_fmt("vk%s unavailable (extension not enabled on "    \
                              "device?)", #field);                             \
            return;                                                            \
        }                                                                      \
    } while (0)

int32_t xvk_raytracing_load_device_procs(int64_t device)
{
    VkDevice dev = XVK_RT_DEV(device);
    XvkRtProcs* p;
    int32_t caps = 0;

    if (!dev) {
        xvk_set_error("xvk_raytracing_load_device_procs: device handle is 0");
        return 0;
    }
    p = xvk_rt_load(dev);
    if (p->CreateAccelerationStructureKHR) caps |= XVK_RT_CAP_KHR_ACCELERATION_STRUCTURE;
    if (p->CreateRayTracingPipelinesKHR)   caps |= XVK_RT_CAP_KHR_RAY_TRACING_PIPELINE;
    if (p->CreateAccelerationStructureNV)  caps |= XVK_RT_CAP_NV_RAY_TRACING;
#if defined(VK_EXT_opacity_micromap)
    if (p->CreateMicromapEXT)              caps |= XVK_RT_CAP_EXT_MICROMAP;
#endif
    return caps;
}

/* ==== VK_KHR_acceleration_structure ======================================= */

int64_t xvk_create_acceleration_structure_khr(int64_t device, int64_t create_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkAccelerationStructureKHR as = VK_NULL_HANDLE;
    VkResult res;

    XVK_RT_REQUIRE(p, CreateAccelerationStructureKHR, 0);
    if (!create_info_struct) {
        xvk_set_error("xvk_create_acceleration_structure_khr: create_info is NULL");
        return 0;
    }
    res = p->CreateAccelerationStructureKHR(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkAccelerationStructureCreateInfoKHR*, create_info_struct),
        NULL, &as);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateAccelerationStructureKHR failed: %d", (int)res);
        return 0;
    }
    return XVK_RT_H64(as);
}

void xvk_destroy_acceleration_structure_khr(int64_t device, int64_t as)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE_VOID(p, DestroyAccelerationStructureKHR);
    if (!as) return;
    p->DestroyAccelerationStructureKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkAccelerationStructureKHR, as), NULL);
}

int32_t xvk_get_acceleration_structure_build_sizes_khr(int64_t device, int32_t build_type,
    int64_t build_info_struct, int64_t max_prim_counts, int64_t out_size_info)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, GetAccelerationStructureBuildSizesKHR, 0);
    if (!build_info_struct || !out_size_info) {
        xvk_set_error("xvk_get_acceleration_structure_build_sizes_khr: "
                      "build_info or out_size_info is NULL");
        return 0;
    }
    p->GetAccelerationStructureBuildSizesKHR(XVK_RT_DEV(device),
        (VkAccelerationStructureBuildTypeKHR)build_type,
        XVK_RT_PTR(const VkAccelerationStructureBuildGeometryInfoKHR*, build_info_struct),
        XVK_RT_PTR(const uint32_t*, max_prim_counts),
        XVK_RT_PTR(VkAccelerationStructureBuildSizesInfoKHR*, out_size_info));
    return 1;
}

void xvk_cmd_build_acceleration_structures_khr(int64_t cmd_buf, int32_t info_count,
    int64_t infos_struct, int64_t build_range_infos)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdBuildAccelerationStructuresKHR);
    if (info_count <= 0 || !infos_struct || !build_range_infos) {
        xvk_set_error("xvk_cmd_build_acceleration_structures_khr: invalid arguments");
        return;
    }
    p->CmdBuildAccelerationStructuresKHR(XVK_RT_CMD(cmd_buf), (uint32_t)info_count,
        XVK_RT_PTR(const VkAccelerationStructureBuildGeometryInfoKHR*, infos_struct),
        XVK_RT_PTR(const VkAccelerationStructureBuildRangeInfoKHR* const*, build_range_infos));
}

void xvk_cmd_build_acceleration_structures_indirect_khr(int64_t cmd_buf, int32_t info_count,
    int64_t infos_struct, int64_t indirect_strides, int64_t max_prim_counts)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    const VkDeviceAddress* addrs;
    const uint32_t* strides;

    XVK_RT_REQUIRE_VOID(p, CmdBuildAccelerationStructuresIndirectKHR);
    if (info_count <= 0 || !infos_struct || !indirect_strides || !max_prim_counts) {
        xvk_set_error("xvk_cmd_build_acceleration_structures_indirect_khr: invalid arguments");
        return;
    }
    /* Packed layout: VkDeviceAddress[info_count] then uint32_t[info_count]. */
    addrs   = XVK_RT_PTR(const VkDeviceAddress*, indirect_strides);
    strides = (const uint32_t*)(const void*)(addrs + info_count);
    p->CmdBuildAccelerationStructuresIndirectKHR(XVK_RT_CMD(cmd_buf), (uint32_t)info_count,
        XVK_RT_PTR(const VkAccelerationStructureBuildGeometryInfoKHR*, infos_struct),
        addrs, strides,
        XVK_RT_PTR(const uint32_t* const*, max_prim_counts));
}

void xvk_cmd_copy_acceleration_structure_khr(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyAccelerationStructureKHR);
    if (!copy_info_struct) return;
    p->CmdCopyAccelerationStructureKHR(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyAccelerationStructureInfoKHR*, copy_info_struct));
}

void xvk_cmd_copy_acceleration_structure_to_memory_khr(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyAccelerationStructureToMemoryKHR);
    if (!copy_info_struct) return;
    p->CmdCopyAccelerationStructureToMemoryKHR(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyAccelerationStructureToMemoryInfoKHR*, copy_info_struct));
}

void xvk_cmd_copy_memory_to_acceleration_structure_khr(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyMemoryToAccelerationStructureKHR);
    if (!copy_info_struct) return;
    p->CmdCopyMemoryToAccelerationStructureKHR(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyMemoryToAccelerationStructureInfoKHR*, copy_info_struct));
}

int64_t xvk_copy_acceleration_structure_khr(int64_t device, int64_t deferred_op, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, CopyAccelerationStructureKHR, (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (!copy_info_struct) {
        xvk_set_error("xvk_copy_acceleration_structure_khr: copy_info is NULL");
        return (int64_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->CopyAccelerationStructureKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op),
        XVK_RT_PTR(const VkCopyAccelerationStructureInfoKHR*, copy_info_struct));
    if (res < 0) xvk_set_error_fmt("vkCopyAccelerationStructureKHR failed: %d", (int)res);
    return (int64_t)res;
}

void xvk_cmd_write_acceleration_structures_properties_khr(int64_t cmd_buf, int32_t count,
    int64_t as_handles, int32_t query_type, int64_t query_pool, int32_t first_query)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdWriteAccelerationStructuresPropertiesKHR);
    if (count <= 0 || !as_handles) return;
    p->CmdWriteAccelerationStructuresPropertiesKHR(XVK_RT_CMD(cmd_buf), (uint32_t)count,
        XVK_RT_PTR(const VkAccelerationStructureKHR*, as_handles),
        (VkQueryType)query_type,
        XVK_RT_NDH(VkQueryPool, query_pool),
        (uint32_t)first_query);
}

int64_t xvk_get_acceleration_structure_device_address_khr(int64_t device,
    int64_t acceleration_structure_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkDeviceAddress addr;

    XVK_RT_REQUIRE(p, GetAccelerationStructureDeviceAddressKHR, 0);
    if (!acceleration_structure_info_struct) {
        xvk_set_error("xvk_get_acceleration_structure_device_address_khr: info is NULL");
        return 0;
    }
    addr = p->GetAccelerationStructureDeviceAddressKHR(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkAccelerationStructureDeviceAddressInfoKHR*,
                   acceleration_structure_info_struct));
    return (int64_t)addr;
}

int32_t xvk_get_device_acceleration_structure_compatibility_khr(int64_t device,
    int64_t version_info_struct, int64_t out_compatibility)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkAccelerationStructureCompatibilityKHR compat =
        VK_ACCELERATION_STRUCTURE_COMPATIBILITY_INCOMPATIBLE_KHR;

    XVK_RT_REQUIRE(p, GetDeviceAccelerationStructureCompatibilityKHR, 0);
    if (!version_info_struct) {
        xvk_set_error("xvk_get_device_acceleration_structure_compatibility_khr: "
                      "version_info is NULL");
        return 0;
    }
    p->GetDeviceAccelerationStructureCompatibilityKHR(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkAccelerationStructureVersionInfoKHR*, version_info_struct),
        &compat);
    if (out_compatibility) *XVK_RT_PTR(int32_t*, out_compatibility) = (int32_t)compat;
    return 1;
}

/* ==== VK_KHR_ray_tracing_pipeline ========================================= */

int32_t xvk_create_ray_tracing_pipelines_khr(int64_t device, int64_t deferred_op,
    int64_t pipeline_cache, int32_t count, int64_t create_infos_struct, int64_t out_pipelines)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, CreateRayTracingPipelinesKHR, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (count <= 0 || !create_infos_struct || !out_pipelines) {
        xvk_set_error("xvk_create_ray_tracing_pipelines_khr: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->CreateRayTracingPipelinesKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op),
        XVK_RT_NDH(VkPipelineCache, pipeline_cache),
        (uint32_t)count,
        XVK_RT_PTR(const VkRayTracingPipelineCreateInfoKHR*, create_infos_struct),
        NULL,
        XVK_RT_PTR(VkPipeline*, out_pipelines));
    if (res < 0) xvk_set_error_fmt("vkCreateRayTracingPipelinesKHR failed: %d", (int)res);
    return (int32_t)res;
}

void xvk_cmd_trace_rays_khr(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt,
    int64_t hit_sbt, int64_t callable_sbt, int32_t width, int32_t height, int32_t depth)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    const VkStridedDeviceAddressRegionKHR* rg;
    const VkStridedDeviceAddressRegionKHR* ms;
    const VkStridedDeviceAddressRegionKHR* ht;
    const VkStridedDeviceAddressRegionKHR* cb;

    XVK_RT_REQUIRE_VOID(p, CmdTraceRaysKHR);
    rg = raygen_sbt   ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, raygen_sbt)   : &g_xvk_rt_empty_region;
    ms = miss_sbt     ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, miss_sbt)     : &g_xvk_rt_empty_region;
    ht = hit_sbt      ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, hit_sbt)      : &g_xvk_rt_empty_region;
    cb = callable_sbt ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, callable_sbt) : &g_xvk_rt_empty_region;
    p->CmdTraceRaysKHR(XVK_RT_CMD(cmd_buf), rg, ms, ht, cb,
        (uint32_t)width, (uint32_t)height, (uint32_t)depth);
}

void xvk_cmd_trace_rays_indirect_khr(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt,
    int64_t hit_sbt, int64_t callable_sbt, int64_t indirect_device_address)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    const VkStridedDeviceAddressRegionKHR* rg;
    const VkStridedDeviceAddressRegionKHR* ms;
    const VkStridedDeviceAddressRegionKHR* ht;
    const VkStridedDeviceAddressRegionKHR* cb;

    XVK_RT_REQUIRE_VOID(p, CmdTraceRaysIndirectKHR);
    rg = raygen_sbt   ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, raygen_sbt)   : &g_xvk_rt_empty_region;
    ms = miss_sbt     ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, miss_sbt)     : &g_xvk_rt_empty_region;
    ht = hit_sbt      ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, hit_sbt)      : &g_xvk_rt_empty_region;
    cb = callable_sbt ? XVK_RT_PTR(const VkStridedDeviceAddressRegionKHR*, callable_sbt) : &g_xvk_rt_empty_region;
    p->CmdTraceRaysIndirectKHR(XVK_RT_CMD(cmd_buf), rg, ms, ht, cb,
        (VkDeviceAddress)(uint64_t)indirect_device_address);
}

int32_t xvk_get_ray_tracing_shader_group_handles_khr(int64_t device, int64_t pipeline,
    int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, GetRayTracingShaderGroupHandlesKHR, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (group_count <= 0 || data_size <= 0 || !out_data) {
        xvk_set_error("xvk_get_ray_tracing_shader_group_handles_khr: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->GetRayTracingShaderGroupHandlesKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipeline, pipeline),
        (uint32_t)first_group, (uint32_t)group_count,
        (size_t)data_size, XVK_RT_PTR(void*, out_data));
    if (res < 0) xvk_set_error_fmt("vkGetRayTracingShaderGroupHandlesKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_get_ray_tracing_capture_replay_shader_group_handles_khr(int64_t device,
    int64_t pipeline, int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, GetRayTracingCaptureReplayShaderGroupHandlesKHR,
                   (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (group_count <= 0 || data_size <= 0 || !out_data) {
        xvk_set_error("xvk_get_ray_tracing_capture_replay_shader_group_handles_khr: "
                      "invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->GetRayTracingCaptureReplayShaderGroupHandlesKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipeline, pipeline),
        (uint32_t)first_group, (uint32_t)group_count,
        (size_t)data_size, XVK_RT_PTR(void*, out_data));
    if (res < 0) {
        xvk_set_error_fmt("vkGetRayTracingCaptureReplayShaderGroupHandlesKHR failed: %d",
                          (int)res);
    }
    return (int32_t)res;
}

int64_t xvk_get_ray_tracing_shader_group_stack_size_khr(int64_t device, int64_t pipeline,
    int32_t group, int32_t group_handle)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, GetRayTracingShaderGroupStackSizeKHR, 0);
    return (int64_t)p->GetRayTracingShaderGroupStackSizeKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipeline, pipeline),
        (uint32_t)group,
        (VkShaderGroupShaderKHR)group_handle);
}

void xvk_cmd_set_ray_tracing_pipeline_stack_size_khr(int64_t cmd_buf, int32_t stack_size)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdSetRayTracingPipelineStackSizeKHR);
    p->CmdSetRayTracingPipelineStackSizeKHR(XVK_RT_CMD(cmd_buf), (uint32_t)stack_size);
}

/* ==== VK_NV_ray_tracing (legacy) ========================================== */

int32_t xvk_create_ray_tracing_pipelines_nv(int64_t device, int64_t pipeline_cache,
    int32_t count, int64_t create_infos_struct, int64_t out_pipelines)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, CreateRayTracingPipelinesNV, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (count <= 0 || !create_infos_struct || !out_pipelines) {
        xvk_set_error("xvk_create_ray_tracing_pipelines_nv: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->CreateRayTracingPipelinesNV(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipelineCache, pipeline_cache),
        (uint32_t)count,
        XVK_RT_PTR(const VkRayTracingPipelineCreateInfoNV*, create_infos_struct),
        NULL,
        XVK_RT_PTR(VkPipeline*, out_pipelines));
    if (res < 0) xvk_set_error_fmt("vkCreateRayTracingPipelinesNV failed: %d", (int)res);
    return (int32_t)res;
}

int64_t xvk_create_acceleration_structure_nv(int64_t device, int64_t create_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkAccelerationStructureNV as = VK_NULL_HANDLE;
    VkResult res;

    XVK_RT_REQUIRE(p, CreateAccelerationStructureNV, 0);
    if (!create_info_struct) {
        xvk_set_error("xvk_create_acceleration_structure_nv: create_info is NULL");
        return 0;
    }
    res = p->CreateAccelerationStructureNV(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkAccelerationStructureCreateInfoNV*, create_info_struct),
        NULL, &as);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateAccelerationStructureNV failed: %d", (int)res);
        return 0;
    }
    return XVK_RT_H64(as);
}

void xvk_destroy_acceleration_structure_nv(int64_t device, int64_t as)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE_VOID(p, DestroyAccelerationStructureNV);
    if (!as) return;
    p->DestroyAccelerationStructureNV(XVK_RT_DEV(device),
        XVK_RT_NDH(VkAccelerationStructureNV, as), NULL);
}

void xvk_get_acceleration_structure_memory_requirements_nv(int64_t device,
    int64_t acceleration_structure_info_struct, int64_t out_reqs)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE_VOID(p, GetAccelerationStructureMemoryRequirementsNV);
    if (!acceleration_structure_info_struct || !out_reqs) {
        xvk_set_error("xvk_get_acceleration_structure_memory_requirements_nv: "
                      "info or out_reqs is NULL");
        return;
    }
    p->GetAccelerationStructureMemoryRequirementsNV(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkAccelerationStructureMemoryRequirementsInfoNV*,
                   acceleration_structure_info_struct),
        XVK_RT_PTR(VkMemoryRequirements2KHR*, out_reqs));
}

int32_t xvk_bind_acceleration_structure_memory_nv(int64_t device, int32_t count,
    int64_t bind_infos_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, BindAccelerationStructureMemoryNV, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (count <= 0 || !bind_infos_struct) {
        xvk_set_error("xvk_bind_acceleration_structure_memory_nv: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->BindAccelerationStructureMemoryNV(XVK_RT_DEV(device), (uint32_t)count,
        XVK_RT_PTR(const VkBindAccelerationStructureMemoryInfoNV*, bind_infos_struct));
    if (res < 0) xvk_set_error_fmt("vkBindAccelerationStructureMemoryNV failed: %d", (int)res);
    return (int32_t)res;
}

void xvk_cmd_build_acceleration_structure_nv(int64_t cmd_buf,
    int64_t acceleration_structure_info_struct, int64_t instance_data, int64_t scratch,
    int32_t update, int32_t flags)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    const XvkBuildAccelerationStructureNV* b;

    (void)flags; /* reserved */
    XVK_RT_REQUIRE_VOID(p, CmdBuildAccelerationStructureNV);
    if (!acceleration_structure_info_struct) {
        xvk_set_error("xvk_cmd_build_acceleration_structure_nv: build struct is NULL");
        return;
    }
    b = XVK_RT_PTR(const XvkBuildAccelerationStructureNV*, acceleration_structure_info_struct);
    if (!b->info || !b->dst) {
        xvk_set_error("xvk_cmd_build_acceleration_structure_nv: info/dst missing "
                      "in XvkBuildAccelerationStructureNV");
        return;
    }
    p->CmdBuildAccelerationStructureNV(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkAccelerationStructureInfoNV*, b->info),
        XVK_RT_NDH(VkBuffer, instance_data),
        (VkDeviceSize)(uint64_t)b->instance_offset,
        update ? VK_TRUE : VK_FALSE,
        XVK_RT_NDH(VkAccelerationStructureNV, b->dst),
        XVK_RT_NDH(VkAccelerationStructureNV, b->src),
        XVK_RT_NDH(VkBuffer, scratch),
        (VkDeviceSize)(uint64_t)b->scratch_offset);
}

void xvk_cmd_copy_acceleration_structure_nv(int64_t cmd_buf, int64_t dst, int64_t src, int32_t mode)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyAccelerationStructureNV);
    if (!dst || !src) return;
    p->CmdCopyAccelerationStructureNV(XVK_RT_CMD(cmd_buf),
        XVK_RT_NDH(VkAccelerationStructureNV, dst),
        XVK_RT_NDH(VkAccelerationStructureNV, src),
        (VkCopyAccelerationStructureModeKHR)mode);
}

void xvk_cmd_trace_rays_nv(int64_t cmd_buf, int64_t raygen_sbt, int64_t miss_sbt,
    int64_t hit_sbt, int64_t callable_sbt, int32_t width, int32_t height, int32_t depth)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    const XvkSbtRegionNV* rg;
    const XvkSbtRegionNV* ms;
    const XvkSbtRegionNV* ht;
    const XvkSbtRegionNV* cb;

    XVK_RT_REQUIRE_VOID(p, CmdTraceRaysNV);
    rg = raygen_sbt   ? XVK_RT_PTR(const XvkSbtRegionNV*, raygen_sbt)   : &g_xvk_rt_empty_sbt_nv;
    ms = miss_sbt     ? XVK_RT_PTR(const XvkSbtRegionNV*, miss_sbt)     : &g_xvk_rt_empty_sbt_nv;
    ht = hit_sbt      ? XVK_RT_PTR(const XvkSbtRegionNV*, hit_sbt)      : &g_xvk_rt_empty_sbt_nv;
    cb = callable_sbt ? XVK_RT_PTR(const XvkSbtRegionNV*, callable_sbt) : &g_xvk_rt_empty_sbt_nv;
    p->CmdTraceRaysNV(XVK_RT_CMD(cmd_buf),
        XVK_RT_NDH(VkBuffer, rg->buffer), (VkDeviceSize)(uint64_t)rg->offset,
        XVK_RT_NDH(VkBuffer, ms->buffer), (VkDeviceSize)(uint64_t)ms->offset,
        (VkDeviceSize)(uint64_t)ms->stride,
        XVK_RT_NDH(VkBuffer, ht->buffer), (VkDeviceSize)(uint64_t)ht->offset,
        (VkDeviceSize)(uint64_t)ht->stride,
        XVK_RT_NDH(VkBuffer, cb->buffer), (VkDeviceSize)(uint64_t)cb->offset,
        (VkDeviceSize)(uint64_t)cb->stride,
        (uint32_t)width, (uint32_t)height, (uint32_t)depth);
}

int32_t xvk_get_ray_tracing_shader_group_handles_nv(int64_t device, int64_t pipeline,
    int32_t first_group, int32_t group_count, int64_t data_size, int64_t out_data)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, GetRayTracingShaderGroupHandlesNV, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (group_count <= 0 || data_size <= 0 || !out_data) {
        xvk_set_error("xvk_get_ray_tracing_shader_group_handles_nv: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->GetRayTracingShaderGroupHandlesNV(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipeline, pipeline),
        (uint32_t)first_group, (uint32_t)group_count,
        (size_t)data_size, XVK_RT_PTR(void*, out_data));
    if (res < 0) xvk_set_error_fmt("vkGetRayTracingShaderGroupHandlesNV failed: %d", (int)res);
    return (int32_t)res;
}

int64_t xvk_get_acceleration_structure_handle_nv(int64_t device, int64_t as,
    int64_t data_size, int64_t out_data)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    if (out_data) {
        XVK_RT_REQUIRE(p, GetAccelerationStructureHandleNV,
                       (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT);
        res = p->GetAccelerationStructureHandleNV(XVK_RT_DEV(device),
            XVK_RT_NDH(VkAccelerationStructureNV, as),
            (size_t)data_size, XVK_RT_PTR(void*, out_data));
        if (res < 0) xvk_set_error_fmt("vkGetAccelerationStructureHandleNV failed: %d", (int)res);
        return (int64_t)res;
    } else {
        uint64_t handle = 0;
        XVK_RT_REQUIRE(p, GetAccelerationStructureHandleNV, 0);
        res = p->GetAccelerationStructureHandleNV(XVK_RT_DEV(device),
            XVK_RT_NDH(VkAccelerationStructureNV, as),
            sizeof(handle), &handle);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkGetAccelerationStructureHandleNV failed: %d", (int)res);
            return 0;
        }
        return (int64_t)handle;
    }
}

void xvk_cmd_write_acceleration_structures_properties_nv(int64_t cmd_buf, int32_t count,
    int64_t as_handles, int32_t query_type, int64_t query_pool, int32_t first_query)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdWriteAccelerationStructuresPropertiesNV);
    if (count <= 0 || !as_handles) return;
    p->CmdWriteAccelerationStructuresPropertiesNV(XVK_RT_CMD(cmd_buf), (uint32_t)count,
        XVK_RT_PTR(const VkAccelerationStructureNV*, as_handles),
        (VkQueryType)query_type,
        XVK_RT_NDH(VkQueryPool, query_pool),
        (uint32_t)first_query);
}

int32_t xvk_compile_deferred_nv(int64_t device, int64_t pipeline, int32_t shader)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, CompileDeferredNV, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    res = p->CompileDeferredNV(XVK_RT_DEV(device),
        XVK_RT_NDH(VkPipeline, pipeline), (uint32_t)shader);
    if (res < 0) xvk_set_error_fmt("vkCompileDeferredNV failed: %d", (int)res);
    return (int32_t)res;
}

/* ==== VK_EXT_micromap ====================================================== */

#if defined(VK_EXT_opacity_micromap)

int64_t xvk_create_micromap_ext(int64_t device, int64_t create_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkMicromapEXT micromap = VK_NULL_HANDLE;
    VkResult res;

    XVK_RT_REQUIRE(p, CreateMicromapEXT, 0);
    if (!create_info_struct) {
        xvk_set_error("xvk_create_micromap_ext: create_info is NULL");
        return 0;
    }
    res = p->CreateMicromapEXT(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkMicromapCreateInfoEXT*, create_info_struct),
        NULL, &micromap);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateMicromapEXT failed: %d", (int)res);
        return 0;
    }
    return XVK_RT_H64(micromap);
}

void xvk_destroy_micromap_ext(int64_t device, int64_t micromap)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE_VOID(p, DestroyMicromapEXT);
    if (!micromap) return;
    p->DestroyMicromapEXT(XVK_RT_DEV(device), XVK_RT_NDH(VkMicromapEXT, micromap), NULL);
}

void xvk_cmd_build_micromaps_ext(int64_t cmd_buf, int32_t info_count, int64_t infos_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdBuildMicromapsEXT);
    if (info_count <= 0 || !infos_struct) return;
    p->CmdBuildMicromapsEXT(XVK_RT_CMD(cmd_buf), (uint32_t)info_count,
        XVK_RT_PTR(const VkMicromapBuildInfoEXT*, infos_struct));
}

int64_t xvk_build_micromaps_ext(int64_t device, int64_t deferred_op, int32_t info_count,
    int64_t infos_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, BuildMicromapsEXT, (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (info_count <= 0 || !infos_struct) {
        xvk_set_error("xvk_build_micromaps_ext: invalid arguments");
        return (int64_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->BuildMicromapsEXT(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op),
        (uint32_t)info_count,
        XVK_RT_PTR(const VkMicromapBuildInfoEXT*, infos_struct));
    if (res < 0) xvk_set_error_fmt("vkBuildMicromapsEXT failed: %d", (int)res);
    return (int64_t)res;
}

int64_t xvk_copy_micromap_ext(int64_t device, int64_t deferred_op, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkResult res;

    XVK_RT_REQUIRE(p, CopyMicromapEXT, (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    if (!copy_info_struct) {
        xvk_set_error("xvk_copy_micromap_ext: copy_info is NULL");
        return (int64_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    res = p->CopyMicromapEXT(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op),
        XVK_RT_PTR(const VkCopyMicromapInfoEXT*, copy_info_struct));
    if (res < 0) xvk_set_error_fmt("vkCopyMicromapEXT failed: %d", (int)res);
    return (int64_t)res;
}

void xvk_cmd_copy_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyMicromapEXT);
    if (!copy_info_struct) return;
    p->CmdCopyMicromapEXT(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyMicromapInfoEXT*, copy_info_struct));
}

void xvk_cmd_copy_micromap_to_memory_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyMicromapToMemoryEXT);
    if (!copy_info_struct) return;
    p->CmdCopyMicromapToMemoryEXT(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyMicromapToMemoryInfoEXT*, copy_info_struct));
}

void xvk_cmd_copy_memory_to_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdCopyMemoryToMicromapEXT);
    if (!copy_info_struct) return;
    p->CmdCopyMemoryToMicromapEXT(XVK_RT_CMD(cmd_buf),
        XVK_RT_PTR(const VkCopyMemoryToMicromapInfoEXT*, copy_info_struct));
}

void xvk_cmd_write_micromaps_properties_ext(int64_t cmd_buf, int32_t count, int64_t micromaps,
    int32_t query_type, int64_t query_pool, int32_t first_query)
{
    XvkRtProcs* p = xvk_rt_procs_cmd();
    XVK_RT_REQUIRE_VOID(p, CmdWriteMicromapsPropertiesEXT);
    if (count <= 0 || !micromaps) return;
    p->CmdWriteMicromapsPropertiesEXT(XVK_RT_CMD(cmd_buf), (uint32_t)count,
        XVK_RT_PTR(const VkMicromapEXT*, micromaps),
        (VkQueryType)query_type,
        XVK_RT_NDH(VkQueryPool, query_pool),
        (uint32_t)first_query);
}

int32_t xvk_get_device_micromap_compatibility_ext(int64_t device, int64_t version_info_struct,
    int64_t out_compatibility)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkAccelerationStructureCompatibilityKHR compat =
        VK_ACCELERATION_STRUCTURE_COMPATIBILITY_INCOMPATIBLE_KHR;

    XVK_RT_REQUIRE(p, GetDeviceMicromapCompatibilityEXT, 0);
    if (!version_info_struct) {
        xvk_set_error("xvk_get_device_micromap_compatibility_ext: version_info is NULL");
        return 0;
    }
    p->GetDeviceMicromapCompatibilityEXT(XVK_RT_DEV(device),
        XVK_RT_PTR(const VkMicromapVersionInfoEXT*, version_info_struct),
        &compat);
    if (out_compatibility) *XVK_RT_PTR(int32_t*, out_compatibility) = (int32_t)compat;
    return 1;
}

int64_t xvk_get_micromap_build_sizes_ext(int64_t device, int32_t build_type,
    int64_t build_info_struct, int64_t out_size_info)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    VkMicromapBuildSizesInfoEXT* out;

    XVK_RT_REQUIRE(p, GetMicromapBuildSizesEXT, 0);
    if (!build_info_struct || !out_size_info) {
        xvk_set_error("xvk_get_micromap_build_sizes_ext: build_info or out_size_info is NULL");
        return 0;
    }
    out = XVK_RT_PTR(VkMicromapBuildSizesInfoEXT*, out_size_info);
    p->GetMicromapBuildSizesEXT(XVK_RT_DEV(device),
        (VkAccelerationStructureBuildTypeKHR)build_type,
        XVK_RT_PTR(const VkMicromapBuildInfoEXT*, build_info_struct),
        out);
    return (int64_t)out->micromapSize;
}

/* ======================================================================== */
/* VK_KHR_deferred_host_operations (Phase 7.6)                              */
/* ======================================================================== */

int64_t xvk_create_deferred_operation_khr(int64_t device)
{
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, CreateDeferredOperationKHR, 0);
    if (!p->CreateDeferredOperationKHR) return 0;

    VkDeferredOperationKHR deferred_op = VK_NULL_HANDLE;
    VkResult res = p->CreateDeferredOperationKHR(
        XVK_RT_DEV(device), NULL, &deferred_op);
    if (res != VK_SUCCESS) {
        if (res == VK_ERROR_OUT_OF_HOST_MEMORY)
            xvk_set_error("vkCreateDeferredOperationKHR: out of host memory");
        else
            xvk_set_error_fmt("vkCreateDeferredOperationKHR failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)deferred_op;
}

void xvk_destroy_deferred_operation_khr(int64_t device, int64_t deferred_op)
{
    if (!deferred_op) return;
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE_VOID(p, DestroyDeferredOperationKHR);
    if (p->DestroyDeferredOperationKHR)
        p->DestroyDeferredOperationKHR(XVK_RT_DEV(device),
            XVK_RT_NDH(VkDeferredOperationKHR, deferred_op), NULL);
}

int32_t xvk_deferred_operation_join_khr(int64_t device, int64_t deferred_op)
{
    if (!deferred_op) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, DeferredOperationJoinKHR, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    VkResult res = p->DeferredOperationJoinKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op));
    /* VK_THREAD_DONE_KHR (0) and VK_THREAD_IDLE_KHR (1000268000) are success codes */
    if (res < 0) xvk_set_error_fmt("vkDeferredOperationJoinKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_get_deferred_operation_result_khr(int64_t device, int64_t deferred_op)
{
    if (!deferred_op) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, GetDeferredOperationResultKHR, (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT);
    VkResult res = p->GetDeferredOperationResultKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op));
    if (res < 0 && res != VK_NOT_READY)
        xvk_set_error_fmt("vkGetDeferredOperationResultKHR failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_get_deferred_operation_max_concurrency_khr(int64_t device, int64_t deferred_op)
{
    if (!deferred_op) return 0;
    XvkRtProcs* p = xvk_rt_procs(device);
    XVK_RT_REQUIRE(p, GetDeferredOperationMaxConcurrencyKHR, 0);
    uint32_t max = p->GetDeferredOperationMaxConcurrencyKHR(XVK_RT_DEV(device),
        XVK_RT_NDH(VkDeferredOperationKHR, deferred_op));
    return (int32_t)max;
}

#else /* !VK_EXT_opacity_micromap -- headers too old, keep the ABI with stubs */

#define XVK_RT_NO_MICROMAP_HEADERS()                                           \
    xvk_set_error("VK_EXT_micromap unavailable: Vulkan headers lack "          \
                  "VK_EXT_opacity_micromap (need SDK >= 1.3.230)")

int64_t xvk_create_micromap_ext(int64_t device, int64_t create_info_struct)
{
    (void)device; (void)create_info_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
    return 0;
}

void xvk_destroy_micromap_ext(int64_t device, int64_t micromap)
{
    (void)device; (void)micromap;
    XVK_RT_NO_MICROMAP_HEADERS();
}

void xvk_cmd_build_micromaps_ext(int64_t cmd_buf, int32_t info_count, int64_t infos_struct)
{
    (void)cmd_buf; (void)info_count; (void)infos_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
}

int64_t xvk_build_micromaps_ext(int64_t device, int64_t deferred_op, int32_t info_count,
    int64_t infos_struct)
{
    (void)device; (void)deferred_op; (void)info_count; (void)infos_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
    return (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT;
}

int64_t xvk_copy_micromap_ext(int64_t device, int64_t deferred_op, int64_t copy_info_struct)
{
    (void)device; (void)deferred_op; (void)copy_info_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
    return (int64_t)VK_ERROR_EXTENSION_NOT_PRESENT;
}

void xvk_cmd_copy_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    (void)cmd_buf; (void)copy_info_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
}

void xvk_cmd_copy_micromap_to_memory_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    (void)cmd_buf; (void)copy_info_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
}

void xvk_cmd_copy_memory_to_micromap_ext(int64_t cmd_buf, int64_t copy_info_struct)
{
    (void)cmd_buf; (void)copy_info_struct;
    XVK_RT_NO_MICROMAP_HEADERS();
}

void xvk_cmd_write_micromaps_properties_ext(int64_t cmd_buf, int32_t count, int64_t micromaps,
    int32_t query_type, int64_t query_pool, int32_t first_query)
{
    (void)cmd_buf; (void)count; (void)micromaps;
    (void)query_type; (void)query_pool; (void)first_query;
    XVK_RT_NO_MICROMAP_HEADERS();
}

int32_t xvk_get_device_micromap_compatibility_ext(int64_t device, int64_t version_info_struct,
    int64_t out_compatibility)
{
    (void)device; (void)version_info_struct; (void)out_compatibility;
    XVK_RT_NO_MICROMAP_HEADERS();
    return 0;
}

int64_t xvk_get_micromap_build_sizes_ext(int64_t device, int32_t build_type,
    int64_t build_info_struct, int64_t out_size_info)
{
    (void)device; (void)build_type; (void)build_info_struct; (void)out_size_info;
    XVK_RT_NO_MICROMAP_HEADERS();
    return 0;
}

#endif /* VK_EXT_opacity_micromap */
