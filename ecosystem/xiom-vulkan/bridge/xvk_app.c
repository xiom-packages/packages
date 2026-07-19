#include "xvk_app.h"
#include "xvk_shaders.h"
#include "xvk_instance.h"
#include "xvk_swapchain.h"
#include "xvk_pipeline.h"
#include "xvk_renderpass.h"
#include <stdlib.h>
#include <string.h>

void xvk_app_cleanup_internal(XvkApp* a)
{
    if (!a || a->magic != XVK_MAGIC) return;

    if (a->device != VK_NULL_HANDLE)
        vkDeviceWaitIdle(a->device);

    if (a->image_available) {
        for (int i = 0; i < XVK_MAX_FRAMES; ++i) {
            if (a->image_available[i])
                vkDestroySemaphore(a->device, a->image_available[i], NULL);
            if (a->render_finished[i])
                vkDestroySemaphore(a->device, a->render_finished[i], NULL);
            if (a->in_flight_fences[i])
                vkDestroyFence(a->device, a->in_flight_fences[i], NULL);
        }
        free(a->image_available);  a->image_available  = NULL;
        free(a->render_finished);  a->render_finished  = NULL;
        free(a->in_flight_fences); a->in_flight_fences = NULL;
    }

    if (a->cmd_buffers) {
        if (a->cmd_pool)
            vkFreeCommandBuffers(a->device, a->cmd_pool,
                                 (uint32_t)a->swapchain_image_count,
                                 a->cmd_buffers);
        free(a->cmd_buffers);
        a->cmd_buffers = NULL;
    }
    if (a->cmd_pool) {
        vkDestroyCommandPool(a->device, a->cmd_pool, NULL);
        a->cmd_pool = VK_NULL_HANDLE;
    }

    if (a->framebuffers) {
        for (int i = 0; i < a->swapchain_image_count; ++i)
            if (a->framebuffers[i])
                vkDestroyFramebuffer(a->device, a->framebuffers[i], NULL);
        free(a->framebuffers);
        a->framebuffers = NULL;
    }

    if (a->pipeline_2d)  vkDestroyPipeline(a->device, a->pipeline_2d, NULL);
    if (a->pipeline_3d)  vkDestroyPipeline(a->device, a->pipeline_3d, NULL);
    if (a->pipe_layout_2d) vkDestroyPipelineLayout(a->device, a->pipe_layout_2d, NULL);
    if (a->pipe_layout_3d) vkDestroyPipelineLayout(a->device, a->pipe_layout_3d, NULL);
    if (a->pipe_layout_quad) vkDestroyPipelineLayout(a->device, a->pipe_layout_quad, NULL);
    if (a->texquad_dsl)      vkDestroyDescriptorSetLayout(a->device, a->texquad_dsl, NULL);
    if (a->texquad_layout)   vkDestroyPipelineLayout(a->device, a->texquad_layout, NULL);
    if (a->lit3d_layout)     vkDestroyPipelineLayout(a->device, a->lit3d_layout, NULL);
    if (a->texquad_pool)     vkDestroyDescriptorPool(a->device, a->texquad_pool, NULL);
    if (a->particle_layout)   vkDestroyPipelineLayout(a->device, a->particle_layout, NULL);
    a->pipeline_2d    = VK_NULL_HANDLE;
    a->pipeline_3d    = VK_NULL_HANDLE;
    a->pipe_layout_2d = VK_NULL_HANDLE;
    a->pipe_layout_3d = VK_NULL_HANDLE;
    a->pipe_layout_quad = VK_NULL_HANDLE;
    a->texquad_dsl      = VK_NULL_HANDLE;
    a->texquad_layout   = VK_NULL_HANDLE;
    a->texquad_pool     = VK_NULL_HANDLE;
    a->texquad_ds       = VK_NULL_HANDLE;
    a->particle_layout   = VK_NULL_HANDLE;

    if (a->particle_pipeline) vkDestroyPipeline(a->device, a->particle_pipeline, NULL);
    if (a->texquad_pipeline)    vkDestroyPipeline(a->device, a->texquad_pipeline, NULL);
    if (a->lit3d_pipeline)      vkDestroyPipeline(a->device, a->lit3d_pipeline, NULL);
    if (a->pipeline_quad)     vkDestroyPipeline(a->device, a->pipeline_quad, NULL);
    if (a->particle_vbo)      vkDestroyBuffer(a->device, a->particle_vbo, NULL);
    if (a->particle_mem) {
        if (a->particle_mapped) vkUnmapMemory(a->device, a->particle_mem);
        vkFreeMemory(a->device, a->particle_mem, NULL);
    }
    free(a->particles);
    a->particle_pipeline = VK_NULL_HANDLE;
    a->texquad_pipeline    = VK_NULL_HANDLE;
    a->lit3d_pipeline      = VK_NULL_HANDLE;
    a->pipeline_quad     = VK_NULL_HANDLE;
    a->particle_vbo      = VK_NULL_HANDLE;
    a->particle_mem      = VK_NULL_HANDLE;
    a->particle_mapped   = NULL;
    a->particles         = NULL;
    a->particle_count    = 0;

    if (a->render_pass)
        vkDestroyRenderPass(a->device, a->render_pass, NULL);
    a->render_pass = VK_NULL_HANDLE;

    cleanup_swapchain(a);

    if (a->is_offscreen) {
        if (a->offs_fence)
            vkDestroyFence(a->device, a->offs_fence, NULL);
        if (a->offs_cmd && a->cmd_pool)
            vkFreeCommandBuffers(a->device, a->cmd_pool, 1, &a->offs_cmd);
        if (a->offs_pipeline)
            vkDestroyPipeline(a->device, a->offs_pipeline, NULL);
        if (a->offs_render_pass)
            vkDestroyRenderPass(a->device, a->offs_render_pass, NULL);
        if (a->offs_framebuffer)
            vkDestroyFramebuffer(a->device, a->offs_framebuffer, NULL);
        if (a->offs_mapped && a->offs_readback_mem)
            vkUnmapMemory(a->device, a->offs_readback_mem);
        if (a->offs_readback)
            vkDestroyBuffer(a->device, a->offs_readback, NULL);
        if (a->offs_readback_mem)
            vkFreeMemory(a->device, a->offs_readback_mem, NULL);
        if (a->offs_image_view)
            vkDestroyImageView(a->device, a->offs_image_view, NULL);
        if (a->offs_image)
            vkDestroyImage(a->device, a->offs_image, NULL);
        if (a->offs_memory)
            vkFreeMemory(a->device, a->offs_memory, NULL);
        a->offs_fence        = VK_NULL_HANDLE;
        a->offs_cmd          = VK_NULL_HANDLE;
        a->offs_pipeline     = VK_NULL_HANDLE;
        a->offs_render_pass  = VK_NULL_HANDLE;
        a->offs_framebuffer  = VK_NULL_HANDLE;
        a->offs_mapped       = NULL;
        a->offs_readback     = VK_NULL_HANDLE;
        a->offs_readback_mem = VK_NULL_HANDLE;
        a->offs_image_view   = VK_NULL_HANDLE;
        a->offs_image        = VK_NULL_HANDLE;
        a->offs_memory       = VK_NULL_HANDLE;
    }

    if (a->device)  vkDestroyDevice(a->device, NULL);
    a->device = VK_NULL_HANDLE;

    if (a->surface) {
        vkDestroySurfaceKHR(a->instance, a->surface, NULL);
        a->surface = VK_NULL_HANDLE;
    }

    if (a->window) {
        glfwDestroyWindow(a->window);
        a->window = NULL;
    }

    if (a->instance)
        vkDestroyInstance(a->instance, NULL);
    a->instance = VK_NULL_HANDLE;

    glfwTerminate();

    a->magic = 0;
}

int64_t xvk_app_create(const char* title, int32_t width, int32_t height)
{
    XvkApp* a = (XvkApp*)calloc(1, sizeof(XvkApp));
    if (!a) {
        xvk_set_error("calloc failed");
        return 0;
    }

    if (!glfwInit()) {
        xvk_set_error("glfwInit failed");
        free(a);
        return 0;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    a->window = glfwCreateWindow(width, height, title ? title : "XIOM Vulkan",
                                 NULL, NULL);
    if (!a->window) {
        xvk_set_error("glfwCreateWindow failed");
        glfwTerminate();
        free(a);
        return 0;
    }

    int have_val = 0;
    a->instance = create_instance(title ? title : "XIOM App", &have_val);
    if (!a->instance) goto fail;

    a->surface = create_surface(a->instance, a->window);
    if (!a->surface) goto fail;

    if (!pick_physical_device(a->instance, a->surface,
                               &a->phys_dev, &a->device_type))
        goto fail;

    if (!find_queue_families(a->phys_dev, a->surface,
                              &a->graphics_family, &a->present_family))
        goto fail;

    a->device = create_device(a->phys_dev,
                               a->graphics_family, a->present_family,
                               a->surface);
    if (!a->device) goto fail;

    vkGetDeviceQueue(a->device, a->graphics_family, 0, &a->graphics_queue);
    vkGetDeviceQueue(a->device, a->present_family, 0, &a->present_queue);

    vkGetPhysicalDeviceMemoryProperties(a->phys_dev, &a->mem_props);

    if (!create_swapchain(a)) goto fail;

    if (!create_depth_resources(a)) goto fail;

    a->render_pass = create_render_pass(a->device, a->swapchain_fmt,
                                         a->depth_format);
    if (!a->render_pass) goto fail;

    VkShaderModule tri_vert = create_shader_module(a->device,
        xvk_triangle_vert_spv, xvk_triangle_vert_spv_len);
    VkShaderModule tri_frag = create_shader_module(a->device,
        xvk_triangle_frag_spv, xvk_triangle_frag_spv_len);
    VkShaderModule cube_vert = create_shader_module(a->device,
        xvk_cube_vert_spv, xvk_cube_vert_spv_len);
    VkShaderModule cube_frag = create_shader_module(a->device,
        xvk_cube_frag_spv, xvk_cube_frag_spv_len);

    if (!tri_vert || !tri_frag || !cube_vert || !cube_frag) {
        if (tri_vert) vkDestroyShaderModule(a->device, tri_vert, NULL);
        if (tri_frag) vkDestroyShaderModule(a->device, tri_frag, NULL);
        if (cube_vert) vkDestroyShaderModule(a->device, cube_vert, NULL);
        if (cube_frag) vkDestroyShaderModule(a->device, cube_frag, NULL);
        goto fail;
    }

    VkPushConstantRange pc_range_2d = {0};
    pc_range_2d.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range_2d.offset     = 0;
    pc_range_2d.size       = 16;

    a->pipe_layout_2d = create_pipeline_layout(a->device, &pc_range_2d, 1);
    if (!a->pipe_layout_2d) goto fail_shaders;

    VkPushConstantRange pc_range_3d = {0};
    pc_range_3d.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range_3d.offset     = 0;
    pc_range_3d.size       = 64;

    a->pipe_layout_3d = create_pipeline_layout(a->device, &pc_range_3d, 1);
    if (!a->pipe_layout_3d) goto fail_shaders;

    a->pipeline_2d = create_graphics_pipeline(a->device,
        a->pipe_layout_2d, a->render_pass,
        tri_vert, tri_frag, width, height, 0);
    if (!a->pipeline_2d) goto fail_shaders;

    a->pipeline_3d = create_graphics_pipeline(a->device,
        a->pipe_layout_3d, a->render_pass,
        cube_vert, cube_frag, width, height, 1);
    if (!a->pipeline_3d) goto fail_shaders;

    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);
    vkDestroyShaderModule(a->device, cube_vert, NULL);
    vkDestroyShaderModule(a->device, cube_frag, NULL);

    {
        VkShaderModule qv = create_shader_module(a->device,
            xvk_quad_vert_spv, xvk_quad_vert_spv_len);
        VkShaderModule qf = create_shader_module(a->device,
            xvk_quad_frag_spv, xvk_quad_frag_spv_len);
        if (!qv || !qf) {
            if (qv) vkDestroyShaderModule(a->device, qv, NULL);
            if (qf) vkDestroyShaderModule(a->device, qf, NULL);
            goto fail;
        }
        VkPushConstantRange pcr = {0};
        pcr.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        pcr.offset     = 0;
        pcr.size       = 32;
        a->pipe_layout_quad = create_pipeline_layout(a->device, &pcr, 1);
        if (!a->pipe_layout_quad) {
            vkDestroyShaderModule(a->device, qv, NULL);
            vkDestroyShaderModule(a->device, qf, NULL);
            goto fail;
        }
        a->pipeline_quad = create_graphics_pipeline(a->device,
            a->pipe_layout_quad, a->render_pass,
            qv, qf, width, height, 0);
        vkDestroyShaderModule(a->device, qv, NULL);
        vkDestroyShaderModule(a->device, qf, NULL);
        if (!a->pipeline_quad) goto fail;
    }

    /* Texture quad pipeline (descriptor set layout + push constants) */
    {
        VkDescriptorSetLayoutBinding dsl_binding = {0};
        dsl_binding.binding         = 1;
        dsl_binding.descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        dsl_binding.descriptorCount = 1;
        dsl_binding.stageFlags      = VK_SHADER_STAGE_FRAGMENT_BIT;

        VkDescriptorSetLayoutCreateInfo dslci = {0};
        dslci.sType        = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
        dslci.bindingCount = 1;
        dslci.pBindings    = &dsl_binding;

        VkResult res = vkCreateDescriptorSetLayout(a->device, &dslci, NULL, &a->texquad_dsl);
        if (res != VK_SUCCESS) { xvk_set_error_fmt("texquad DSL failed: %d", (int)res); goto fail; }

        VkPushConstantRange pcr = {0};
        pcr.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        pcr.offset     = 0;
        pcr.size       = 32;

        VkPipelineLayoutCreateInfo plci = {0};
        plci.sType                  = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
        plci.setLayoutCount         = 1;
        plci.pSetLayouts            = &a->texquad_dsl;
        plci.pushConstantRangeCount = 1;
        plci.pPushConstantRanges    = &pcr;

        res = vkCreatePipelineLayout(a->device, &plci, NULL, &a->texquad_layout);
        if (res != VK_SUCCESS) { xvk_set_error_fmt("texquad layout failed: %d", (int)res); goto fail; }

        VkShaderModule tv = create_shader_module(a->device,
            xvk_texture_quad_vert_spv, xvk_texture_quad_vert_spv_len);
        VkShaderModule tf = create_shader_module(a->device,
            xvk_texture_quad_frag_spv, xvk_texture_quad_frag_spv_len);
        if (!tv || !tf) {
            if (tv) vkDestroyShaderModule(a->device, tv, NULL);
            if (tf) vkDestroyShaderModule(a->device, tf, NULL);
            goto fail;
        }

        a->texquad_pipeline = create_graphics_pipeline(a->device,
            a->texquad_layout, a->render_pass,
            tv, tf, width, height, 0);
        vkDestroyShaderModule(a->device, tv, NULL);
        vkDestroyShaderModule(a->device, tf, NULL);
        if (!a->texquad_pipeline) goto fail;

        VkDescriptorPoolSize pool_size = {0};
        pool_size.type            = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        pool_size.descriptorCount = 1;

        VkDescriptorPoolCreateInfo dpci = {0};
        dpci.sType         = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        dpci.maxSets       = 1;
        dpci.poolSizeCount = 1;
        dpci.pPoolSizes    = &pool_size;

        res = vkCreateDescriptorPool(a->device, &dpci, NULL, &a->texquad_pool);
        if (res != VK_SUCCESS) { xvk_set_error_fmt("texquad pool failed: %d", (int)res); goto fail; }

        VkDescriptorSetAllocateInfo dsai = {0};
        dsai.sType              = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsai.descriptorPool     = a->texquad_pool;
        dsai.descriptorSetCount = 1;
        dsai.pSetLayouts        = &a->texquad_dsl;

        res = vkAllocateDescriptorSets(a->device, &dsai, &a->texquad_ds);
        if (res != VK_SUCCESS) { xvk_set_error_fmt("texquad DS alloc failed: %d", (int)res); goto fail; }
    }

    /* Lit 3D pipeline (vertex positions + normals, directional light) */
    {
        VkPushConstantRange pcr = {0};
        pcr.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        pcr.offset     = 0;
        pcr.size       = 96;

        a->lit3d_layout = create_pipeline_layout(a->device, &pcr, 1);
        if (!a->lit3d_layout) goto fail;

        VkShaderModule lv = create_shader_module(a->device,
            xvk_lit_3d_vert_spv, xvk_lit_3d_vert_spv_len);
        VkShaderModule lf = create_shader_module(a->device,
            xvk_lit_3d_frag_spv, xvk_lit_3d_frag_spv_len);
        if (!lv || !lf) {
            if (lv) vkDestroyShaderModule(a->device, lv, NULL);
            if (lf) vkDestroyShaderModule(a->device, lf, NULL);
            goto fail;
        }

        /* Build pipeline with vertex input for interleaved pos+normal (6 floats, 24 stride) */
        VkVertexInputBindingDescription vb = {0};
        vb.binding   = 0;
        vb.stride    = 24; /* float3 pos + float3 normal */
        vb.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

        VkVertexInputAttributeDescription va[2] = {{0}};
        va[0].binding  = 0;
        va[0].location = 0;
        va[0].format   = VK_FORMAT_R32G32B32_SFLOAT; /* position */
        va[0].offset   = 0;
        va[1].binding  = 0;
        va[1].location = 1;
        va[1].format   = VK_FORMAT_R32G32B32_SFLOAT; /* normal */
        va[1].offset   = 12;

        VkPipelineVertexInputStateCreateInfo vi = {0};
        vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount   = 1;
        vi.pVertexBindingDescriptions      = &vb;
        vi.vertexAttributeDescriptionCount = 2;
        vi.pVertexAttributeDescriptions    = va;

        VkPipelineShaderStageCreateInfo stages[2] = {{0}};
        stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
        stages[0].module = lv;
        stages[0].pName  = "main";
        stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
        stages[1].module = lf;
        stages[1].pName  = "main";

        VkPipelineInputAssemblyStateCreateInfo ia = {0};
        ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

        VkPipelineViewportStateCreateInfo vs = {0};
        vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vs.viewportCount = 1;
        vs.scissorCount  = 1;

        VkPipelineRasterizationStateCreateInfo rs = {0};
        rs.sType     = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode = VK_POLYGON_MODE_FILL;
        rs.lineWidth   = 1.0f;
        rs.cullMode    = VK_CULL_MODE_BACK_BIT;
        rs.frontFace   = VK_FRONT_FACE_COUNTER_CLOCKWISE;

        VkPipelineMultisampleStateCreateInfo ms = {0};
        ms.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

        VkPipelineColorBlendAttachmentState cb = {0};
        cb.colorWriteMask = 0xF;
        VkPipelineColorBlendStateCreateInfo cbs = {0};
        cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cbs.attachmentCount = 1;
        cbs.pAttachments    = &cb;

        VkDynamicState dyn_states[] = { VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR };
        VkPipelineDynamicStateCreateInfo dyn = {0};
        dyn.sType             = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
        dyn.dynamicStateCount = 2;
        dyn.pDynamicStates    = dyn_states;

        VkGraphicsPipelineCreateInfo gpci = {0};
        gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        gpci.stageCount          = 2;
        gpci.pStages             = stages;
        gpci.pVertexInputState   = &vi;
        gpci.pInputAssemblyState = &ia;
        gpci.pViewportState      = &vs;
        gpci.pRasterizationState = &rs;
        gpci.pMultisampleState   = &ms;
        gpci.pDynamicState       = &dyn;
        gpci.pColorBlendState    = &cbs;
        gpci.layout              = a->lit3d_layout;
        gpci.renderPass          = a->render_pass;
        gpci.subpass             = 0;

        VkResult res = vkCreateGraphicsPipelines(a->device, VK_NULL_HANDLE, 1, &gpci, NULL, &a->lit3d_pipeline);
        vkDestroyShaderModule(a->device, lv, NULL);
        vkDestroyShaderModule(a->device, lf, NULL);
        if (res != VK_SUCCESS || !a->lit3d_pipeline) {
            xvk_set_error_fmt("lit3d pipeline creation failed: %d", (int)res);
            goto fail;
        }
    }

    {
        VkShaderModule pv = create_shader_module(a->device,
            xvk_particle_vert_spv, xvk_particle_vert_spv_len);
        VkShaderModule pf = create_shader_module(a->device,
            xvk_particle_frag_spv, xvk_particle_frag_spv_len);
        if (!pv || !pf) {
            if (pv) vkDestroyShaderModule(a->device, pv, NULL);
            if (pf) vkDestroyShaderModule(a->device, pf, NULL);
            goto fail;
        }

        {
            VkPipelineLayoutCreateInfo plci = {0};
            plci.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
            VkResult res = vkCreatePipelineLayout(a->device, &plci, NULL,
                                                   &a->particle_layout);
            if (res != VK_SUCCESS) {
                xvk_set_error_fmt("vkCreatePipelineLayout (particle) failed: %d", (int)res);
                vkDestroyShaderModule(a->device, pv, NULL);
                vkDestroyShaderModule(a->device, pf, NULL);
                goto fail;
            }
        }

        VkVertexInputBindingDescription bind = {0};
        bind.binding   = 0;
        bind.stride    = 20;
        bind.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

        VkVertexInputAttributeDescription attrs[2] = {{0}};
        attrs[0].location = 0;
        attrs[0].binding  = 0;
        attrs[0].format   = VK_FORMAT_R32G32_SFLOAT;
        attrs[0].offset   = 0;
        attrs[1].location = 1;
        attrs[1].binding  = 0;
        attrs[1].format   = VK_FORMAT_R32G32B32_SFLOAT;
        attrs[1].offset   = 8;

        VkPipelineVertexInputStateCreateInfo vi = {0};
        vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount   = 1;
        vi.pVertexBindingDescriptions      = &bind;
        vi.vertexAttributeDescriptionCount = 2;
        vi.pVertexAttributeDescriptions    = attrs;

        VkPipelineShaderStageCreateInfo stages[2] = {{0}};
        stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
        stages[0].module = pv;
        stages[0].pName  = "main";
        stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
        stages[1].module = pf;
        stages[1].pName  = "main";

        VkPipelineInputAssemblyStateCreateInfo ia = {0};
        ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        ia.topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;

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
        scissor.extent.width  = (uint32_t)width;
        scissor.extent.height = (uint32_t)height;

        VkPipelineViewportStateCreateInfo vs = {0};
        vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vs.viewportCount = 1;
        vs.pViewports    = &vp;
        vs.scissorCount  = 1;
        vs.pScissors     = &scissor;

        VkPipelineRasterizationStateCreateInfo rs = {0};
        rs.sType                   = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode             = VK_POLYGON_MODE_FILL;
        rs.cullMode                = VK_CULL_MODE_NONE;
        rs.frontFace               = VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.lineWidth               = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms = {0};
        ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

        VkPipelineDepthStencilStateCreateInfo ds = {0};
        ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        ds.depthTestEnable       = VK_FALSE;
        ds.depthWriteEnable      = VK_FALSE;

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
        gpci.layout              = a->particle_layout;
        gpci.renderPass          = a->render_pass;
        gpci.subpass             = 0;

        VkResult res = vkCreateGraphicsPipelines(a->device, VK_NULL_HANDLE,
                                                  1, &gpci, NULL,
                                                  &a->particle_pipeline);
        vkDestroyShaderModule(a->device, pv, NULL);
        vkDestroyShaderModule(a->device, pf, NULL);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateGraphicsPipelines (particle) failed: %d", (int)res);
            goto fail;
        }
    }

    if (!create_framebuffers(a)) goto fail;

    a->cmd_pool = create_cmd_pool(a->device, a->graphics_family);
    if (!a->cmd_pool) goto fail;

    a->cmd_buffers = (VkCommandBuffer*)malloc(
        a->swapchain_image_count * sizeof(VkCommandBuffer));
    if (!a->cmd_buffers) { xvk_set_error("malloc failed for cmd_buffers"); goto fail; }
    if (!allocate_cmd_buffers(a->device, a->cmd_pool,
                               a->cmd_buffers, a->swapchain_image_count))
        goto fail;

    a->image_available = (VkSemaphore*)malloc(XVK_MAX_FRAMES * sizeof(VkSemaphore));
    a->render_finished = (VkSemaphore*)malloc(XVK_MAX_FRAMES * sizeof(VkSemaphore));
    a->in_flight_fences= (VkFence*)malloc(XVK_MAX_FRAMES * sizeof(VkFence));
    if (!a->image_available || !a->render_finished || !a->in_flight_fences) {
        xvk_set_error("malloc failed for sync objects");
        goto fail;
    }
    memset(a->image_available, 0, XVK_MAX_FRAMES * sizeof(VkSemaphore));
    memset(a->render_finished, 0, XVK_MAX_FRAMES * sizeof(VkSemaphore));
    memset(a->in_flight_fences, 0, XVK_MAX_FRAMES * sizeof(VkFence));
    if (!create_sync_objects(a->device, XVK_MAX_FRAMES,
                              a->image_available,
                              a->render_finished,
                              a->in_flight_fences))
        goto fail;

    a->clear_r = 0.0f;
    a->clear_g = 0.0f;
    a->clear_b = 0.0f;
    a->frame_index     = 0;
    a->recording       = 0;
    a->in_render_pass  = 0;
    a->magic       = XVK_MAGIC;
    a->is_offscreen = 0;

    xvk_set_error("");
    return xvk_to_handle(a);

fail_shaders:
    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);
    vkDestroyShaderModule(a->device, cube_vert, NULL);
    vkDestroyShaderModule(a->device, cube_frag, NULL);
fail:
    xvk_app_cleanup_internal(a);
    free(a);
    return 0;
}

void xvk_app_destroy(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    xvk_app_cleanup_internal(a);
    free(a);
}

int64_t xvk_get_device(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->device;
}

int64_t xvk_get_physical_device(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->phys_dev;
}

int64_t xvk_get_graphics_queue(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->graphics_queue;
}

int64_t xvk_get_command_pool(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->cmd_pool;
}

int64_t xvk_get_instance(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->instance;
}

int64_t xvk_get_render_pass(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(uint64_t)a->render_pass;
}

int64_t xvk_get_command_buffer(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->cmd_buffers) return 0;
    return (int64_t)(uint64_t)a->cmd_buffers[a->current_image];
}

int64_t xvk_get_glfw_window(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    return (int64_t)(intptr_t)a->window;
}

int32_t xvk_get_fb_width(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->window) return 0;
    int w, h;
    glfwGetFramebufferSize(a->window, &w, &h);
    return (int32_t)w;
}

int32_t xvk_get_fb_height(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->window) return 0;
    int w, h;
    glfwGetFramebufferSize(a->window, &w, &h);
    return (int32_t)h;
}
