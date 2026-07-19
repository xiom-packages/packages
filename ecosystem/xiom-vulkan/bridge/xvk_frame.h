#ifndef XVK_FRAME_H_
#define XVK_FRAME_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int32_t xvk_begin_frame(int64_t app_h);
void xvk_end_frame(int64_t app_h);
void xvk_set_clear_color(int64_t app_h, float r, float g, float b);
void xvk_app_poll(int64_t app_h);
double xvk_now(void);
int32_t xvk_app_should_close(int64_t app_h);
int32_t xvk_device_type(int64_t app_h);
int32_t xvk_app_valid(int64_t app_h);
const char* xvk_last_error(void);

/* Phase 8.2 extension: UI hit-testing in C (avoids Float64 codegen in XIOM).
 * Converts NDC coords to pixel space and checks mouse position.
 * Returns: 0=mouse outside, 1=hover, 2=pressed (left button down). */
int32_t xvk_button_hit_state(int64_t app_h,
                              float cx, float cy, float hw, float hh);

#endif
