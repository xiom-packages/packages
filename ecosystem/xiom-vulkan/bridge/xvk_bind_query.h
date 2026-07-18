#ifndef XVK_BIND_QUERY_H_
#define XVK_BIND_QUERY_H_

#include <stdint.h>

int64_t xvk_create_query_pool(int64_t device, int64_t create_info_struct);
void xvk_destroy_query_pool(int64_t device, int64_t pool);
int32_t xvk_get_query_pool_results(int64_t device, int64_t pool, int32_t first, int32_t count, int64_t data_size, int64_t data, int64_t stride, int32_t flags);
void xvk_cmd_begin_query(int64_t cmd_buf, int64_t pool, int32_t query, int32_t flags);
void xvk_cmd_end_query(int64_t cmd_buf, int64_t pool, int32_t query);
void xvk_cmd_write_timestamp(int64_t cmd_buf, int32_t stage, int64_t pool, int32_t query);
void xvk_cmd_reset_query_pool(int64_t cmd_buf, int64_t pool, int32_t first, int32_t count);
void xvk_cmd_copy_query_pool_results(int64_t cmd_buf, int64_t pool, int32_t first, int32_t count, int64_t dst, int64_t dst_offset, int64_t stride, int32_t flags);

#endif
