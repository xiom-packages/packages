#ifndef XVK_BIND_SYNC_H_
#define XVK_BIND_SYNC_H_

#include <stdint.h>

int64_t xvk_create_fence(int64_t device, int64_t create_info_struct);
void xvk_destroy_fence(int64_t device, int64_t fence);
int32_t xvk_wait_for_fences(int64_t device, int32_t count, int64_t fences, int32_t wait_all, int64_t timeout);
int32_t xvk_reset_fences(int64_t device, int32_t count, int64_t fences);
int64_t xvk_create_semaphore(int64_t device, int64_t create_info_struct);
void xvk_destroy_semaphore(int64_t device, int64_t semaphore);
int64_t xvk_create_event(int64_t device, int64_t create_info_struct);
void xvk_destroy_event(int64_t device, int64_t event);
int32_t xvk_queue_submit(int64_t queue, int32_t submit_count, int64_t submits_struct, int64_t fence);
int32_t xvk_queue_submit_multi(int64_t queue, int32_t cmd_buf_count, int64_t cmd_bufs_array, int64_t fence);
/* xvk_queue_present_khr lives in xvk_bind_swapchain.h */

#endif
