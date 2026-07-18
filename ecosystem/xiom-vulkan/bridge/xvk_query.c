#include "xvk_query.h"
#include <stdlib.h>

typedef struct {
    uint32_t magic;
    VkQueryPool pool;
    uint32_t count;
} XvkQueryPool;
#define XVK_QUERY_POOL_MAGIC 0x51555259

static XvkQueryPool* xvk_qp_from_handle(int64_t h) {
    if (h == 0) return NULL;
    XvkQueryPool* p = (XvkQueryPool*)(intptr_t)h;
    if (p->magic != XVK_QUERY_POOL_MAGIC) return NULL;
    return p;
}
static int64_t xvk_qp_to_handle(XvkQueryPool* p) {
    return p ? (int64_t)(intptr_t)p : 0;
}

int64_t xvk_query_pool_create(int64_t app_h, int32_t query_count, int32_t query_type)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || query_count <= 0) return 0;

    XvkQueryPool* qp = (XvkQueryPool*)calloc(1, sizeof(XvkQueryPool));
    if (!qp) { xvk_set_error("calloc query pool"); return 0; }

    VkQueryType vk_type;
    if (query_type == 1) vk_type = VK_QUERY_TYPE_TIMESTAMP;
    else if (query_type == 2) vk_type = VK_QUERY_TYPE_PIPELINE_STATISTICS;
    else vk_type = VK_QUERY_TYPE_OCCLUSION;

    VkQueryPoolCreateInfo qpci = {0};
    qpci.sType      = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
    qpci.queryType  = vk_type;
    qpci.queryCount = (uint32_t)query_count;

    VkResult res = vkCreateQueryPool(a->device, &qpci, NULL, &qp->pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateQueryPool failed: %d", (int)res);
        free(qp); return 0;
    }
    qp->magic = XVK_QUERY_POOL_MAGIC;
    qp->count = (uint32_t)query_count;
    return xvk_qp_to_handle(qp);
}

void xvk_query_pool_destroy(int64_t app_h, int64_t pool_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkQueryPool* qp = xvk_qp_from_handle(pool_h);
    if (!a || !qp) return;
    if (qp->pool) vkDestroyQueryPool(a->device, qp->pool, NULL);
    qp->magic = 0;
    free(qp);
}

void xvk_query_write_timestamp(int64_t app_h, int64_t pool_h, int32_t query_index)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkQueryPool* qp = xvk_qp_from_handle(pool_h);
    if (!a || !a->recording || !qp) return;
    if (query_index < 0 || (uint32_t)query_index >= qp->count) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdWriteTimestamp(cb, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, qp->pool, (uint32_t)query_index);
}

int32_t xvk_query_pool_get_results(int64_t app_h, int64_t pool_h,
                                    int32_t first_query, int32_t query_count,
                                    int64_t* out_data)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkQueryPool* qp = xvk_qp_from_handle(pool_h);
    if (!a || !qp || !out_data || query_count <= 0) return 0;

    VkResult res = vkGetQueryPoolResults(a->device, qp->pool,
        (uint32_t)first_query, (uint32_t)query_count,
        (size_t)(query_count * sizeof(int64_t)), out_data,
        sizeof(int64_t), VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT);

    if (res != VK_SUCCESS && res != VK_NOT_READY) {
        xvk_set_error_fmt("vkGetQueryPoolResults failed: %d", (int)res);
        return 0;
    }
    return res == VK_SUCCESS ? 1 : 0;
}
