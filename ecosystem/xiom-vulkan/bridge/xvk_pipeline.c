#include "xvk_pipeline.h"
#include "xvk_shaders.h"

VkShaderModule create_shader_module(VkDevice dev,
                                     const unsigned int* code,
                                     unsigned int code_size_bytes)
{
    VkShaderModuleCreateInfo smci = {0};
    smci.sType    = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    smci.codeSize = code_size_bytes;
    smci.pCode    = code;
    VkShaderModule sm = VK_NULL_HANDLE;
    VkResult res = vkCreateShaderModule(dev, &smci, NULL, &sm);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateShaderModule failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return sm;
}

VkPipelineLayout create_pipeline_layout(VkDevice dev,
                                         VkPushConstantRange* pcrs,
                                         uint32_t pcr_count)
{
    VkPipelineLayoutCreateInfo plci = {0};
    plci.sType                  = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    plci.pushConstantRangeCount = pcr_count;
    plci.pPushConstantRanges    = pcrs;
    VkPipelineLayout pl = VK_NULL_HANDLE;
    VkResult res = vkCreatePipelineLayout(dev, &plci, NULL, &pl);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineLayout failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pl;
}

VkPipeline create_graphics_pipeline(VkDevice dev,
    VkPipelineLayout layout, VkRenderPass rp,
    VkShaderModule vert, VkShaderModule frag,
    uint32_t width, uint32_t height,
    int enable_depth)
{
    VkPipelineShaderStageCreateInfo stages[2] = {{0}};
    stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vert;
    stages[0].pName  = "main";
    stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = frag;
    stages[1].pName  = "main";

    VkPipelineVertexInputStateCreateInfo vi = {0};
    vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    VkPipelineInputAssemblyStateCreateInfo ia = {0};
    ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkViewport vp = {0};
    vp.x        = 0.0f;
    vp.y        = 0.0f;
    vp.width    = (float)width;
    vp.height   = (float)height;
    vp.minDepth = 0.0f;
    vp.maxDepth = 1.0f;

    VkRect2D scissor = {0};
    scissor.offset.x      = 0;
    scissor.offset.y      = 0;
    scissor.extent.width  = width;
    scissor.extent.height = height;

    VkPipelineViewportStateCreateInfo vs = {0};
    vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vs.viewportCount = 1;
    vs.pViewports    = &vp;
    vs.scissorCount  = 1;
    vs.pScissors     = &scissor;

    VkPipelineRasterizationStateCreateInfo rs = {0};
    rs.sType                   = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rs.polygonMode             = VK_POLYGON_MODE_FILL;
    rs.cullMode                = enable_depth ? VK_CULL_MODE_NONE : VK_CULL_MODE_BACK_BIT;
    rs.frontFace               = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth               = 1.0f;

    VkPipelineMultisampleStateCreateInfo ms = {0};
    ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineDepthStencilStateCreateInfo ds = {0};
    ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ds.depthTestEnable       = enable_depth ? VK_TRUE : VK_FALSE;
    ds.depthWriteEnable      = enable_depth ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp        = VK_COMPARE_OP_LESS;
    ds.depthBoundsTestEnable = VK_FALSE;
    ds.stencilTestEnable     = VK_FALSE;

    VkPipelineColorBlendAttachmentState cb = {0};
    cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    cb.blendEnable = VK_FALSE;

    VkPipelineColorBlendStateCreateInfo cbs = {0};
    cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cbs.attachmentCount = 1;
    cbs.pAttachments    = &cb;

    VkGraphicsPipelineCreateInfo gpci = {0};
    gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gpci.stageCount          = 2;
    gpci.pStages             = stages;
    gpci.pVertexInputState   = &vi;
    gpci.pInputAssemblyState = &ia;
    gpci.pViewportState      = &vs;
    gpci.pRasterizationState = &rs;
    gpci.pMultisampleState   = &ms;
    gpci.pDepthStencilState  = &ds;
    gpci.pColorBlendState    = &cbs;
    gpci.layout              = layout;
    gpci.renderPass          = rp;
    gpci.subpass             = 0;

    VkPipeline pipe = VK_NULL_HANDLE;
    VkResult res = vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE,
                                              1, &gpci, NULL, &pipe);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateGraphicsPipelines failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pipe;
}

int create_sync_objects(VkDevice dev, int count,
    VkSemaphore* image_avail, VkSemaphore* render_fin, VkFence* fences)
{
    VkSemaphoreCreateInfo sci = {0};
    sci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fci = {0};
    fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    for (int i = 0; i < count; ++i) {
        VkResult r;
        r = vkCreateSemaphore(dev, &sci, NULL, &image_avail[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateSemaphore (avail) failed: %d", (int)r);
            return 0;
        }
        r = vkCreateSemaphore(dev, &sci, NULL, &render_fin[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateSemaphore (render) failed: %d", (int)r);
            vkDestroySemaphore(dev, image_avail[i], NULL);
            return 0;
        }
        r = vkCreateFence(dev, &fci, NULL, &fences[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateFence failed: %d", (int)r);
            vkDestroySemaphore(dev, image_avail[i], NULL);
            vkDestroySemaphore(dev, render_fin[i], NULL);
            return 0;
        }
    }
    return 1;
}

VkCommandPool create_cmd_pool(VkDevice dev, uint32_t family)
{
    VkCommandPoolCreateInfo cpci = {0};
    cpci.sType            = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cpci.flags            = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cpci.queueFamilyIndex = family;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkResult res = vkCreateCommandPool(dev, &cpci, NULL, &pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateCommandPool failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pool;
}

int allocate_cmd_buffers(VkDevice dev, VkCommandPool pool,
                          VkCommandBuffer* bufs, int count)
{
    VkCommandBufferAllocateInfo cbai = {0};
    cbai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cbai.commandPool        = pool;
    cbai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbai.commandBufferCount = (uint32_t)count;
    VkResult res = vkAllocateCommandBuffers(dev, &cbai, bufs);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateCommandBuffers failed: %d", (int)res);
        return 0;
    }
    return 1;
}

int64_t xvk_shader_create(int64_t app_h, const unsigned int* code, int32_t code_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !code || code_size <= 0) return 0;
    return (int64_t)(intptr_t)create_shader_module(a->device, code, (unsigned int)code_size);
}

int64_t xvk_shader_create_named(int64_t app_h, const char* name)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !name) return 0;

    static const struct {
        const char* name;
        const unsigned int* code;
        unsigned int size;
    } table[] = {
        {"triangle_vert",      xvk_triangle_vert_spv,      xvk_triangle_vert_spv_len},
        {"triangle_frag",      xvk_triangle_frag_spv,      xvk_triangle_frag_spv_len},
        {"cube_vert",          xvk_cube_vert_spv,          xvk_cube_vert_spv_len},
        {"cube_frag",          xvk_cube_frag_spv,          xvk_cube_frag_spv_len},
        {"quad_vert",          xvk_quad_vert_spv,          xvk_quad_vert_spv_len},
        {"quad_frag",          xvk_quad_frag_spv,          xvk_quad_frag_spv_len},
        {"particle_vert",      xvk_particle_vert_spv,      xvk_particle_vert_spv_len},
        {"particle_frag",      xvk_particle_frag_spv,      xvk_particle_frag_spv_len},
        {"particle_render_vert", xvk_particle_render_vert_spv, xvk_particle_render_vert_spv_len},
        {"particle_render_frag", xvk_particle_render_frag_spv, xvk_particle_render_frag_spv_len},
        {"compute_particles",  xvk_compute_particles_spv,  xvk_compute_particles_spv_len},
        {"texture_quad_vert",  xvk_texture_quad_vert_spv,  xvk_texture_quad_vert_spv_len},
        {"texture_quad_frag",  xvk_texture_quad_frag_spv,  xvk_texture_quad_frag_spv_len},
        {"uniform_cube_vert",  xvk_uniform_cube_vert_spv,  xvk_uniform_cube_vert_spv_len},
        {"uniform_cube_frag",  xvk_uniform_cube_frag_spv,  xvk_uniform_cube_frag_spv_len},
    };
    int n = sizeof(table) / sizeof(table[0]);

    for (int i = 0; i < n; ++i) {
        if (strcmp(table[i].name, name) == 0 && table[i].code && table[i].size > 0) {
            return (int64_t)(intptr_t)create_shader_module(a->device, table[i].code, table[i].size);
        }
    }
    xvk_set_error_fmt("shader_create_named: unknown shader '%s'", name);
    return 0;
}

void xvk_shader_destroy(int64_t app_h, int64_t shader_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !shader_h) return;
    VkShaderModule sm = (VkShaderModule)(intptr_t)shader_h;
    vkDestroyShaderModule(a->device, sm, NULL);
}

int64_t xvk_pipeline_layout_create(int64_t app_h, int32_t push_size, int32_t push_stages,
                                    int32_t desc_layout_count, const int64_t* desc_layouts)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;

    XvkPipelineLayout* pl = (XvkPipelineLayout*)calloc(1, sizeof(XvkPipelineLayout));
    if (!pl) { xvk_set_error("calloc pipeline layout"); return 0; }

    VkPushConstantRange pcr = {0};
    int pcr_count = 0;
    if (push_size > 0) {
        pcr.stageFlags = xvk_map_stage_flags(push_stages);
        pcr.offset     = 0;
        pcr.size       = (uint32_t)push_size;
        pcr_count      = 1;
    }

    VkDescriptorSetLayout* dsl = NULL;
    if (desc_layout_count > 0 && desc_layouts) {
        dsl = (VkDescriptorSetLayout*)malloc((size_t)desc_layout_count * sizeof(VkDescriptorSetLayout));
        for (int i = 0; i < desc_layout_count; ++i) {
            XvkDescSetLayout* dl = xvk_dslayout_from_handle(desc_layouts[i]);
            dsl[i] = dl ? dl->layout : VK_NULL_HANDLE;
        }
    }

    VkPipelineLayoutCreateInfo plci = {0};
    plci.sType                  = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    plci.setLayoutCount         = (uint32_t)desc_layout_count;
    plci.pSetLayouts            = dsl;
    plci.pushConstantRangeCount = (uint32_t)pcr_count;
    plci.pPushConstantRanges    = pcr_count ? &pcr : NULL;

    VkResult res = vkCreatePipelineLayout(a->device, &plci, NULL, &pl->layout);
    if (dsl) free(dsl);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineLayout: %d", (int)res);
        free(pl); return 0;
    }
    pl->magic = XVK_PLAYOUT_MAGIC;
    return xvk_playout_to_handle(pl);
}

void xvk_pipeline_layout_destroy(int64_t app_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !pl) return;
    if (pl->layout) vkDestroyPipelineLayout(a->device, pl->layout, NULL);
    pl->magic = 0;
    free(pl);
}

int64_t xvk_pipeline_create_graphics(int64_t app_h,
    int32_t topology, int32_t cull_mode, int32_t depth_test, int32_t depth_write,
    int32_t blend_enable,
    int64_t vertex_shader_h, int64_t fragment_shader_h,
    int64_t layout_h, int64_t render_pass_h,
    const int32_t* bindings, int32_t binding_count,
    const int32_t* attributes, int32_t attr_count)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    XvkRenderPass* rp = xvk_rp_from_handle(render_pass_h);
    if (!a || !pl || !rp) return 0;
    if (!vertex_shader_h || !fragment_shader_h) { xvk_set_error("shader handles required"); return 0; }

    XvkPipeline* p = (XvkPipeline*)calloc(1, sizeof(XvkPipeline));
    if (!p) { xvk_set_error("calloc pipeline"); return 0; }

    VkPipelineShaderStageCreateInfo stages[2] = {{0}};
    stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = (VkShaderModule)(intptr_t)vertex_shader_h;
    stages[0].pName  = "main";
    stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = (VkShaderModule)(intptr_t)fragment_shader_h;
    stages[1].pName  = "main";

    VkVertexInputBindingDescription* vb = NULL;
    VkVertexInputAttributeDescription* va = NULL;
    if (binding_count > 0 && bindings) {
        vb = (VkVertexInputBindingDescription*)malloc((size_t)binding_count * sizeof(VkVertexInputBindingDescription));
        for (int i = 0; i < binding_count; ++i) {
            vb[i].binding   = (uint32_t)bindings[i * 3];
            vb[i].stride    = (uint32_t)bindings[i * 3 + 1];
            vb[i].inputRate = bindings[i * 3 + 2] == 1 ? VK_VERTEX_INPUT_RATE_INSTANCE : VK_VERTEX_INPUT_RATE_VERTEX;
        }
    }
    if (attr_count > 0 && attributes) {
        va = (VkVertexInputAttributeDescription*)malloc((size_t)attr_count * sizeof(VkVertexInputAttributeDescription));
        for (int i = 0; i < attr_count; ++i) {
            va[i].location = (uint32_t)attributes[i * 4];
            va[i].binding  = (uint32_t)attributes[i * 4 + 1];
            va[i].format   = xvk_map_vertex_format(attributes[i * 4 + 2]);
            va[i].offset   = (uint32_t)attributes[i * 4 + 3];
        }
    }

    VkPipelineVertexInputStateCreateInfo vi = {0};
    vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vi.vertexBindingDescriptionCount   = (uint32_t)binding_count;
    vi.pVertexBindingDescriptions      = vb;
    vi.vertexAttributeDescriptionCount = (uint32_t)attr_count;
    vi.pVertexAttributeDescriptions    = va;

    VkPipelineInputAssemblyStateCreateInfo ia = {0};
    ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = xvk_map_topology(topology);

    VkViewport vp = {0};
    vp.x = 0; vp.y = 0;
    vp.width  = (float)a->swapchain_extent.width;
    vp.height = (float)a->swapchain_extent.height;
    vp.minDepth = 0.0f;
    vp.maxDepth = 1.0f;

    VkRect2D sc = {0};
    sc.extent = a->swapchain_extent;

    VkPipelineViewportStateCreateInfo vs = {0};
    vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vs.viewportCount = 1; vs.pViewports = &vp;
    vs.scissorCount  = 1; vs.pScissors  = &sc;

    VkPipelineRasterizationStateCreateInfo rs = {0};
    rs.sType       = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode    = cull_mode == 1 ? VK_CULL_MODE_FRONT_BIT :
                     cull_mode == 2 ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE;
    rs.frontFace   = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth   = 1.0f;

    VkPipelineMultisampleStateCreateInfo ms = {0};
    ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineDepthStencilStateCreateInfo ds = {0};
    ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ds.depthTestEnable       = depth_test ? VK_TRUE : VK_FALSE;
    ds.depthWriteEnable      = depth_write ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp        = VK_COMPARE_OP_LESS;

    VkPipelineColorBlendAttachmentState cb = {0};
    cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    if (blend_enable) {
        cb.blendEnable         = VK_TRUE;
        cb.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        cb.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        cb.colorBlendOp        = VK_BLEND_OP_ADD;
        cb.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        cb.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
        cb.alphaBlendOp        = VK_BLEND_OP_ADD;
    } else {
        cb.blendEnable = VK_FALSE;
    }

    VkPipelineColorBlendStateCreateInfo cbs = {0};
    cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cbs.attachmentCount = 1;
    cbs.pAttachments    = &cb;

    VkPipelineDynamicStateCreateInfo dyn = {0};
    dyn.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;

    VkGraphicsPipelineCreateInfo gpci = {0};
    gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gpci.stageCount          = 2;
    gpci.pStages             = stages;
    gpci.pVertexInputState   = &vi;
    gpci.pInputAssemblyState = &ia;
    gpci.pViewportState      = &vs;
    gpci.pRasterizationState = &rs;
    gpci.pMultisampleState   = &ms;
    gpci.pDepthStencilState  = &ds;
    gpci.pColorBlendState    = &cbs;
    gpci.pDynamicState       = &dyn;
    gpci.layout              = pl->layout;
    gpci.renderPass          = rp->render_pass;
    gpci.subpass             = 0;

    VkResult res = vkCreateGraphicsPipelines(a->device, VK_NULL_HANDLE, 1, &gpci, NULL, &p->pipeline);
    if (vb) free(vb);
    if (va) free(va);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateGraphicsPipelines: %d", (int)res);
        free(p); return 0;
    }
    p->bind_point = VK_PIPELINE_BIND_POINT_GRAPHICS;
    p->magic = XVK_PIPELINE_MAGIC;
    return xvk_pipeline_to_handle(p);
}

int64_t xvk_pipeline_create_compute(int64_t app_h, int64_t shader_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !pl || !shader_h) return 0;

    XvkPipeline* p = (XvkPipeline*)calloc(1, sizeof(XvkPipeline));
    if (!p) { xvk_set_error("calloc compute pipeline"); return 0; }

    VkPipelineShaderStageCreateInfo stage = {0};
    stage.sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stage.stage  = VK_SHADER_STAGE_COMPUTE_BIT;
    stage.module = (VkShaderModule)(intptr_t)shader_h;
    stage.pName  = "main";

    VkComputePipelineCreateInfo cpci = {0};
    cpci.sType  = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    cpci.stage  = stage;
    cpci.layout = pl->layout;

    VkResult res = vkCreateComputePipelines(a->device, VK_NULL_HANDLE, 1, &cpci, NULL, &p->pipeline);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateComputePipelines: %d", (int)res);
        free(p); return 0;
    }
    p->bind_point = VK_PIPELINE_BIND_POINT_COMPUTE;
    p->magic = XVK_PIPELINE_MAGIC;
    return xvk_pipeline_to_handle(p);
}

void xvk_pipeline_destroy(int64_t app_h, int64_t pipeline_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    if (!a || !p) return;
    if (p->pipeline) vkDestroyPipeline(a->device, p->pipeline, NULL);
    p->magic = 0;
    free(p);
}

void xvk_compute_dispatch(int64_t app_h, int64_t pipeline_h, int64_t layout_h,
                           int32_t x, int32_t y, int32_t z)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !p || !pl) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    if (a->in_render_pass) {
        vkCmdEndRenderPass(cb);
        a->in_render_pass = 0;
    }
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p->pipeline);
    vkCmdDispatch(cb, (uint32_t)x, (uint32_t)y, (uint32_t)z);
}
