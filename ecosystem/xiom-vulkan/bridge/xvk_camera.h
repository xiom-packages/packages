#ifndef XVK_CAMERA_H_
#define XVK_CAMERA_H_

#include <stdint.h>

/* 3D Camera for viewport control (Phase X: 3D viewport).
 * Stores view + projection state. All 3D draw functions use this
 * instead of hardcoded matrices when a camera is active. */

void xvk_camera_set_view(float eye_x, float eye_y, float eye_z,
                          float target_x, float target_y, float target_z);
void xvk_camera_set_projection(float fov_deg, float near_plane, float far_plane);
void xvk_camera_get_view(int64_t out_matrix);     /* 16 floats = 64 bytes */
void xvk_camera_get_projection(int64_t out_matrix); /* 16 floats */
void xvk_camera_orbit(float delta_yaw, float delta_pitch, float delta_radius);
void xvk_camera_pan(float dx, float dy);
void xvk_camera_zoom(float delta);
void xvk_camera_reset(void);
int  xvk_camera_is_active(void);

#endif
