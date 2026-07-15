// XIOM — Vulkan Enum Constants
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// All Vulkan enum/flag constants used by xiom.vulkan.extern and safe wrappers.
// Split from vulkan_extern.xi to stay under the compiler's per-module
// `pub const` declaration limit (~99).

module xiom.vulkan.constants

// =========================================================================
// VkResult codes
// =========================================================================
pub const VK_SUCCESS: Int32                          = 0
pub const VK_NOT_READY: Int32                        = 1
pub const VK_TIMEOUT: Int32                          = 2
pub const VK_EVENT_SET: Int32                        = 3
pub const VK_EVENT_RESET: Int32                      = 4
pub const VK_INCOMPLETE: Int32                       = 5
pub const VK_ERROR_OUT_OF_HOST_MEMORY: Int32         = -1
pub const VK_ERROR_OUT_OF_DEVICE_MEMORY: Int32       = -2
pub const VK_ERROR_INITIALIZATION_FAILED: Int32      = -3
pub const VK_ERROR_DEVICE_LOST: Int32                = -4
pub const VK_ERROR_MEMORY_MAP_FAILED: Int32          = -5
pub const VK_ERROR_LAYER_NOT_PRESENT: Int32          = -6
pub const VK_ERROR_EXTENSION_NOT_PRESENT: Int32      = -7
pub const VK_ERROR_FEATURE_NOT_PRESENT: Int32        = -8
pub const VK_ERROR_INCOMPATIBLE_DRIVER: Int32        = -9
pub const VK_ERROR_TOO_MANY_OBJECTS: Int32           = -10
pub const VK_ERROR_FORMAT_NOT_SUPPORTED: Int32       = -11
pub const VK_ERROR_FRAGMENTED_POOL: Int32            = -12
pub const VK_ERROR_UNKNOWN: Int32                    = -13
pub const VK_ERROR_OUT_OF_POOL_MEMORY: Int32         = -1000069000
pub const VK_ERROR_INVALID_EXTERNAL_HANDLE: Int32    = -1000072003
pub const VK_ERROR_FRAGMENTATION: Int32              = -1000161000
pub const VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS: Int32 = -1000257000
pub const VK_ERROR_SURFACE_LOST_KHR: Int32           = -1000000000
pub const VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: Int32   = -1000000001
pub const VK_SUBOPTIMAL_KHR: Int32                   = 1000001003
pub const VK_ERROR_OUT_OF_DATE_KHR: Int32            = -1000001004
pub const VK_ERROR_INCOMPATIBLE_DISPLAY_KHR: Int32   = -1000003001
pub const VK_ERROR_VALIDATION_FAILED_EXT: Int32      = -1000011001
pub const VK_ERROR_INVALID_SHADER_NV: Int32          = -1000012000

// =========================================================================
// VkStructureType (subset)
// =========================================================================
pub const VK_STRUCTURE_TYPE_APPLICATION_INFO: Int32                       = 0
pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: Int32                   = 1
pub const VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO: Int32               = 2
pub const VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO: Int32                     = 3
pub const VK_STRUCTURE_TYPE_SUBMIT_INFO: Int32                            = 4
pub const VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO: Int32                   = 5
pub const VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE: Int32                    = 6
pub const VK_STRUCTURE_TYPE_BIND_SPARSE_INFO: Int32                       = 7
pub const VK_STRUCTURE_TYPE_FENCE_CREATE_INFO: Int32                      = 8
pub const VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO: Int32                  = 9
pub const VK_STRUCTURE_TYPE_EVENT_CREATE_INFO: Int32                      = 10
pub const VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO: Int32                 = 11
pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO: Int32                     = 12
pub const VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO: Int32                = 13
pub const VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO: Int32                      = 14
pub const VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO: Int32                 = 15
pub const VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO: Int32              = 16
pub const VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO: Int32             = 17
pub const VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO: Int32      = 18
pub const VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO: Int32 = 19
pub const VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO: Int32 = 20
pub const VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO: Int32 = 21
pub const VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO: Int32    = 22
pub const VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO: Int32 = 23
pub const VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO: Int32 = 24
pub const VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO: Int32 = 25
pub const VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO: Int32 = 26
pub const VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO: Int32     = 27
pub const VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO: Int32          = 28
pub const VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO: Int32           = 29
pub const VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO: Int32            = 30

pub const VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO: Int32                    = 31
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO: Int32      = 32
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO: Int32            = 33
pub const VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO: Int32           = 34
pub const VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET: Int32                   = 35
pub const VK_STRUCTURE_TYPE_COPY_DESCRIPTOR_SET: Int32                    = 36
pub const VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO: Int32                = 37
pub const VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO: Int32                = 38
pub const VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO: Int32               = 39
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO: Int32           = 40
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO: Int32        = 41
pub const VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO: Int32              = 42
pub const VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO: Int32                 = 43
pub const VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER: Int32                  = 44
pub const VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER: Int32                   = 45
pub const VK_STRUCTURE_TYPE_MEMORY_BARRIER: Int32                         = 46

pub const VK_FORMAT_UNDEFINED: Int32                      = 0
pub const VK_FORMAT_R8G8B8A8_UNORM: Int32                 = 37
pub const VK_FORMAT_B8G8R8A8_UNORM: Int32                 = 44
pub const VK_FORMAT_R8G8B8A8_SRGB: Int32                  = 43
pub const VK_FORMAT_B8G8R8A8_SRGB: Int32                  = 50
pub const VK_FORMAT_R32G32B32A32_SFLOAT: Int32            = 109
pub const VK_FORMAT_R32G32B32_SFLOAT: Int32               = 106
pub const VK_FORMAT_R32G32_SFLOAT: Int32                  = 103
pub const VK_FORMAT_R32_SFLOAT: Int32                     = 100
pub const VK_FORMAT_D32_SFLOAT: Int32                     = 126
pub const VK_FORMAT_D24_UNORM_S8_UINT: Int32              = 129
pub const VK_FORMAT_D16_UNORM: Int32                      = 124
