#ifndef XVK_QUERY_H_
#define XVK_QUERY_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int64_t xvk_query_pool_create(int64_t app_h, int32_t query_count, int32_t query_type);
void xvk_query_pool_destroy(int64_t app_h, int64_t pool_h);
void xvk_cmd_write_timestamp(int64_t app_h, int64_t pool_h, int32_t query_index);
int32_t xvk_query_pool_get_results(int64_t app_h, int64_t pool_h,
                                    int32_t first_query, int32_t query_count,
                                    int64_t* out_data);

#endif
