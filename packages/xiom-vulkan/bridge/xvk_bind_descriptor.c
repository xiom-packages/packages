#include "xvk_bind_descriptor.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_descriptor_set_layout(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkDescriptorSetLayoutCreateInfo* ci =
        (const VkDescriptorSetLayoutCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_descriptor_set_layout: null device or create info");
        return 0;
    }
    VkDescriptorSetLayout layout = VK_NULL_HANDLE;
    VkResult res = vkCreateDescriptorSetLayout(dev, ci, NULL, &layout);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDescriptorSetLayout: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)layout;
}

void xvk_destroy_descriptor_set_layout(int64_t device, int64_t layout)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !layout) return;
    vkDestroyDescriptorSetLayout(dev, (VkDescriptorSetLayout)(uint64_t)layout, NULL);
}

int64_t xvk_create_descriptor_pool(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkDescriptorPoolCreateInfo* ci =
        (const VkDescriptorPoolCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_descriptor_pool: null device or create info");
        return 0;
    }
    VkDescriptorPool pool = VK_NULL_HANDLE;
    VkResult res = vkCreateDescriptorPool(dev, ci, NULL, &pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDescriptorPool: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)pool;
}

void xvk_destroy_descriptor_pool(int64_t device, int64_t pool)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !pool) return;
    vkDestroyDescriptorPool(dev, (VkDescriptorPool)(uint64_t)pool, NULL);
}

int32_t xvk_allocate_descriptor_sets(int64_t device, int64_t allocate_info_struct,
                                     int64_t out_sets)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkDescriptorSetAllocateInfo* ai =
        (const VkDescriptorSetAllocateInfo*)(intptr_t)allocate_info_struct;
    VkDescriptorSet* out = (VkDescriptorSet*)(intptr_t)out_sets;
    if (!dev || !ai || !out) {
        xvk_set_error("xvk_allocate_descriptor_sets: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkAllocateDescriptorSets(dev, ai, out);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateDescriptorSets: %d", (int)res);
    }
    return (int32_t)res;
}

int32_t xvk_free_descriptor_sets(int64_t device, int64_t pool, int32_t count,
                                 int64_t sets)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkDescriptorSet* s = (const VkDescriptorSet*)(intptr_t)sets;
    if (!dev || !pool || !s || count <= 0) {
        xvk_set_error("xvk_free_descriptor_sets: invalid arguments");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkFreeDescriptorSets(dev, (VkDescriptorPool)(uint64_t)pool,
                                        (uint32_t)count, s);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkFreeDescriptorSets: %d", (int)res);
    }
    return (int32_t)res;
}

void xvk_update_descriptor_sets(int64_t device, int32_t write_count, int64_t writes_struct,
                                int32_t copy_count, int64_t copies_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkWriteDescriptorSet* writes =
        (const VkWriteDescriptorSet*)(intptr_t)writes_struct;
    const VkCopyDescriptorSet* copies =
        (const VkCopyDescriptorSet*)(intptr_t)copies_struct;
    if (!dev) {
        xvk_set_error("xvk_update_descriptor_sets: null device");
        return;
    }
    if (write_count < 0) write_count = 0;
    if (copy_count < 0) copy_count = 0;
    if ((write_count > 0 && !writes) || (copy_count > 0 && !copies)) {
        xvk_set_error("xvk_update_descriptor_sets: null writes/copies array");
        return;
    }
    vkUpdateDescriptorSets(dev, (uint32_t)write_count, writes,
                           (uint32_t)copy_count, copies);
}

int64_t xvk_create_descriptor_update_template(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkDescriptorUpdateTemplateCreateInfo* ci =
        (const VkDescriptorUpdateTemplateCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_descriptor_update_template: null device or create info");
        return 0;
    }
    VkDescriptorUpdateTemplate tmpl = VK_NULL_HANDLE;
    VkResult res = vkCreateDescriptorUpdateTemplate(dev, ci, NULL, &tmpl);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDescriptorUpdateTemplate: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)tmpl;
}

void xvk_destroy_descriptor_update_template(int64_t device, int64_t update_template)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !update_template) return;
    vkDestroyDescriptorUpdateTemplate(dev,
        (VkDescriptorUpdateTemplate)(uint64_t)update_template, NULL);
}
