#ifndef XVK_APP_H_
#define XVK_APP_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int64_t xvk_app_create(const char* title, int32_t width, int32_t height);
void xvk_app_destroy(int64_t app_h);
void xvk_app_cleanup_internal(XvkApp* a);

#endif
