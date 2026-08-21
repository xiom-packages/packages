#ifndef XVK_CAMERA_H_
#define XVK_CAMERA_H_

#include <stdint.h>

/* 3D Camera -- per-app state stored in XvkApp struct.
 * All functions take app_h (int64_t) as first parameter.
 * xvk_cos/xvk_sin are stateless trig bridges. */

/* -- Public API (app handle first) -- */
void xvk_camera_set_view(int64_t app_h,
    float eye_x, float eye_y, float eye_z,
    float target_x, float target_y, float target_z);
void xvk_camera_orbit(int64_t app_h, float dyaw, float dpitch, float dradius);
void xvk_camera_zoom(int64_t app_h, float delta);
void xvk_camera_reset(int64_t app_h);
void xvk_camera_set_aspect_ratio(int64_t app_h, float aspect);
void xvk_camera_set_aspect_from_fb(int64_t app_h, int32_t fb_w, int32_t fb_h);

/* -- Internal API (called by draw functions) -- */
void xvk_camera_get_view(int64_t app_h, int64_t out_matrix);
void xvk_camera_get_projection(int64_t app_h, int64_t out_matrix);
int  xvk_camera_is_active(int64_t app_h);

/* -- Stateless trig bridge -- */
float xvk_cos(float x);
float xvk_sin(float x);

#endif
