// XIOM — Vulkan Enum Constants (Part 3: Misc enums)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.vulkan.constants3

pub const VK_CULL_MODE_NONE: Int32           = 0
pub const VK_CULL_MODE_FRONT_BIT: Int32      = 1
pub const VK_CULL_MODE_BACK_BIT: Int32       = 2
pub const VK_CULL_MODE_FRONT_AND_BACK: Int32 = 3

pub const VK_COMPARE_OP_NEVER: Int32          = 0
pub const VK_COMPARE_OP_LESS: Int32           = 1
pub const VK_COMPARE_OP_EQUAL: Int32          = 2
pub const VK_COMPARE_OP_LESS_OR_EQUAL: Int32  = 3
pub const VK_COMPARE_OP_GREATER: Int32        = 4
pub const VK_COMPARE_OP_NOT_EQUAL: Int32      = 5
pub const VK_COMPARE_OP_GREATER_OR_EQUAL: Int32 = 6
pub const VK_COMPARE_OP_ALWAYS: Int32         = 7

pub const VK_PRIMITIVE_TOPOLOGY_POINT_LIST: Int32    = 0
pub const VK_PRIMITIVE_TOPOLOGY_LINE_LIST: Int32     = 1
pub const VK_PRIMITIVE_TOPOLOGY_LINE_STRIP: Int32    = 2
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST: Int32 = 3
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP: Int32 = 4
pub const VK_PRIMITIVE_TOPOLOGY_TRIANGLE_FAN: Int32  = 5

pub const VK_COMMAND_BUFFER_LEVEL_PRIMARY: Int32   = 0
pub const VK_COMMAND_BUFFER_LEVEL_SECONDARY: Int32 = 1
pub const VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT: Int32      = 1
pub const VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT: Int32 = 2
pub const VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT: Int32     = 4

pub const VK_SUBPASS_CONTENTS_INLINE: Int32 = 0
pub const VK_SUBPASS_CONTENTS_SECONDARY_COMMAND_BUFFERS: Int32 = 1

pub const VK_PIPELINE_BIND_POINT_GRAPHICS: Int32 = 0
pub const VK_PIPELINE_BIND_POINT_COMPUTE: Int32  = 1

pub const VK_ATTACHMENT_LOAD_OP_LOAD: Int32      = 0
pub const VK_ATTACHMENT_LOAD_OP_CLEAR: Int32     = 1
pub const VK_ATTACHMENT_LOAD_OP_DONT_CARE: Int32 = 2
pub const VK_ATTACHMENT_STORE_OP_STORE: Int32     = 0
pub const VK_ATTACHMENT_STORE_OP_DONT_CARE: Int32 = 1

pub const VK_INDEX_TYPE_UINT16: Int32 = 0
pub const VK_INDEX_TYPE_UINT32: Int32 = 1

pub const VK_FILTER_NEAREST: Int32 = 0
pub const VK_FILTER_LINEAR: Int32  = 1

pub const VK_SAMPLER_ADDRESS_MODE_REPEAT: Int32          = 0
pub const VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT: Int32 = 1
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE: Int32   = 2
pub const VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER: Int32 = 3

pub const VK_BLEND_FACTOR_ZERO: Int32                = 0
pub const VK_BLEND_FACTOR_ONE: Int32                 = 1
pub const VK_BLEND_FACTOR_SRC_COLOR: Int32           = 2
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR: Int32 = 3
pub const VK_BLEND_FACTOR_DST_COLOR: Int32           = 4
pub const VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR: Int32 = 5
pub const VK_BLEND_FACTOR_SRC_ALPHA: Int32           = 6
pub const VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA: Int32 = 7
pub const VK_BLEND_FACTOR_DST_ALPHA: Int32           = 8
pub const VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA: Int32 = 9

pub const VK_BLEND_OP_ADD: Int32 = 0
