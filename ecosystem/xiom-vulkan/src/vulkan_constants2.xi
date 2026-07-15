// XIOM — Vulkan Enum Constants (Part 2: Usage/Stage/Access flags)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.vulkan.constants2

pub const VK_IMAGE_LAYOUT_UNDEFINED: Int32                                      = 0
pub const VK_IMAGE_LAYOUT_GENERAL: Int32                                        = 1
pub const VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL: Int32                        = 2
pub const VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL: Int32               = 3
pub const VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL: Int32                = 4
pub const VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL: Int32                       = 5
pub const VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL: Int32                           = 6
pub const VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL: Int32                           = 7
pub const VK_IMAGE_LAYOUT_PREINITIALIZED: Int32                                 = 8
pub const VK_IMAGE_LAYOUT_PRESENT_SRC_KHR: Int32                                = 1000001002

pub const VK_IMAGE_USAGE_TRANSFER_SRC_BIT: Int32          = 1
pub const VK_IMAGE_USAGE_TRANSFER_DST_BIT: Int32          = 2
pub const VK_IMAGE_USAGE_SAMPLED_BIT: Int32               = 4
pub const VK_IMAGE_USAGE_STORAGE_BIT: Int32               = 8
pub const VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT: Int32      = 16
pub const VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT: Int32 = 32
pub const VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT: Int32  = 64
pub const VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT: Int32      = 128

pub const VK_BUFFER_USAGE_TRANSFER_SRC_BIT: Int32                          = 1
pub const VK_BUFFER_USAGE_TRANSFER_DST_BIT: Int32                          = 2
pub const VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT: Int32                  = 4
pub const VK_BUFFER_USAGE_STORAGE_TEXEL_BUFFER_BIT: Int32                  = 8
pub const VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT: Int32                        = 16
pub const VK_BUFFER_USAGE_STORAGE_BUFFER_BIT: Int32                        = 32
pub const VK_BUFFER_USAGE_INDEX_BUFFER_BIT: Int32                          = 64
pub const VK_BUFFER_USAGE_VERTEX_BUFFER_BIT: Int32                         = 128
pub const VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT: Int32                       = 256

pub const VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT: Int32       = 1
pub const VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT: Int32       = 2
pub const VK_MEMORY_PROPERTY_HOST_COHERENT_BIT: Int32      = 4
pub const VK_MEMORY_PROPERTY_HOST_CACHED_BIT: Int32        = 8
pub const VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT: Int32   = 16

pub const VK_SHADER_STAGE_VERTEX_BIT: Int32                  = 1
pub const VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT: Int32    = 2
pub const VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT: Int32 = 4
pub const VK_SHADER_STAGE_GEOMETRY_BIT: Int32                = 8
pub const VK_SHADER_STAGE_FRAGMENT_BIT: Int32                = 16
pub const VK_SHADER_STAGE_COMPUTE_BIT: Int32                 = 32
pub const VK_SHADER_STAGE_ALL_GRAPHICS: Int32                = 31
pub const VK_SHADER_STAGE_ALL: Int32                         = 2147483647

pub const VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT: Int32                       = 1
pub const VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT: Int32                     = 2
pub const VK_PIPELINE_STAGE_VERTEX_INPUT_BIT: Int32                      = 4
pub const VK_PIPELINE_STAGE_VERTEX_SHADER_BIT: Int32                     = 8
pub const VK_PIPELINE_STAGE_TESSELLATION_CONTROL_SHADER_BIT: Int32       = 16
pub const VK_PIPELINE_STAGE_TESSELLATION_EVALUATION_SHADER_BIT: Int32    = 32
pub const VK_PIPELINE_STAGE_GEOMETRY_SHADER_BIT: Int32                   = 64
pub const VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT: Int32                   = 128
pub const VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT: Int32              = 256
pub const VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT: Int32               = 512
pub const VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT: Int32           = 1024
pub const VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT: Int32                    = 2048
pub const VK_PIPELINE_STAGE_TRANSFER_BIT: Int32                          = 4096
pub const VK_PIPELINE_STAGE_ALL_GRAPHICS: Int32                          = 32768
pub const VK_PIPELINE_STAGE_ALL_COMMANDS_BIT: Int32                      = 65536

pub const VK_ACCESS_INDIRECT_COMMAND_READ_BIT: Int32           = 1
pub const VK_ACCESS_INDEX_READ_BIT: Int32                      = 2
pub const VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT: Int32           = 4
pub const VK_ACCESS_UNIFORM_READ_BIT: Int32                    = 8
pub const VK_ACCESS_SHADER_READ_BIT: Int32                     = 32
pub const VK_ACCESS_SHADER_WRITE_BIT: Int32                    = 64
pub const VK_ACCESS_COLOR_ATTACHMENT_READ_BIT: Int32           = 128
pub const VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT: Int32          = 256
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT: Int32   = 512
pub const VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT: Int32  = 1024
pub const VK_ACCESS_TRANSFER_READ_BIT: Int32                   = 2048
pub const VK_ACCESS_TRANSFER_WRITE_BIT: Int32                  = 4096
pub const VK_ACCESS_HOST_READ_BIT: Int32                       = 8192
pub const VK_ACCESS_HOST_WRITE_BIT: Int32                      = 16384
pub const VK_ACCESS_MEMORY_READ_BIT: Int32                     = 32768
pub const VK_ACCESS_MEMORY_WRITE_BIT: Int32                    = 65536

pub const VK_IMAGE_ASPECT_COLOR_BIT: Int32      = 1
pub const VK_IMAGE_ASPECT_DEPTH_BIT: Int32      = 2
pub const VK_IMAGE_ASPECT_STENCIL_BIT: Int32    = 4

pub const VK_DESCRIPTOR_TYPE_SAMPLER: Int32                = 0
pub const VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER: Int32 = 1
pub const VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE: Int32          = 2
pub const VK_DESCRIPTOR_TYPE_STORAGE_IMAGE: Int32          = 3
pub const VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER: Int32   = 4
pub const VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER: Int32   = 5
pub const VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER: Int32         = 6
pub const VK_DESCRIPTOR_TYPE_STORAGE_BUFFER: Int32         = 7
pub const VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC: Int32 = 8
pub const VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC: Int32 = 9
pub const VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT: Int32       = 10
