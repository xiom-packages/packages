#include "xvk_camera.h"
#include "xvk_math.h"
#include "xvk_types.h"
#include "xvk_util.h"
#include <string.h>
#include <math.h>

/* Helper: extract camera from opaque app handle */
static XvkApp* cam_from_handle(int64_t app_h) {
    return (XvkApp*)(intptr_t)app_h;
}

/* ── Public API (XIOM-callable, takes app_h first) ── */

void xvk_camera_set_view(int64_t app_h, float eye_x, float eye_y, float eye_z,
                          float target_x, float target_y, float target_z)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;
    a->cam_eye[0] = eye_x; a->cam_eye[1] = eye_y; a->cam_eye[2] = eye_z;
    a->cam_target[0] = target_x; a->cam_target[1] = target_y; a->cam_target[2] = target_z;
    a->cam_active = 1;
}

void xvk_camera_orbit(int64_t app_h, float delta_yaw, float delta_pitch, float delta_radius)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;

    float dx = a->cam_eye[0] - a->cam_target[0];
    float dy = a->cam_eye[1] - a->cam_target[1];
    float dz = a->cam_eye[2] - a->cam_target[2];
    float radius = sqrtf(dx*dx + dy*dy + dz*dz);
    float yaw   = atan2f(dz, dx);
    float pitch = asinf(dy / (radius > 0.001f ? radius : 0.001f));

    yaw   += delta_yaw;
    pitch += delta_pitch;
    if (pitch > 1.5f)  pitch = 1.5f;
    if (pitch < -1.5f) pitch = -1.5f;
    radius += delta_radius;
    if (radius < 0.5f)  radius = 0.5f;
    if (radius > 50.0f) radius = 50.0f;

    a->cam_eye[0] = a->cam_target[0] + radius * cosf(pitch) * cosf(yaw);
    a->cam_eye[1] = a->cam_target[1] + radius * sinf(pitch);
    a->cam_eye[2] = a->cam_target[2] + radius * cosf(pitch) * sinf(yaw);
}

void xvk_camera_zoom(int64_t app_h, float delta)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;
    float dir[3] = { a->cam_target[0] - a->cam_eye[0], a->cam_target[1] - a->cam_eye[1], a->cam_target[2] - a->cam_eye[2] };
    float len = sqrtf(dir[0]*dir[0] + dir[1]*dir[1] + dir[2]*dir[2]);
    if (len < 0.001f) len = 0.001f;
    a->cam_eye[0] += dir[0] / len * delta;
    a->cam_eye[1] += dir[1] / len * delta;
    a->cam_eye[2] += dir[2] / len * delta;
}

void xvk_camera_reset(int64_t app_h)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;
    a->cam_eye[0] = 2.0f; a->cam_eye[1] = 2.0f; a->cam_eye[2] = 2.0f;
    a->cam_target[0] = 0.0f; a->cam_target[1] = 0.0f; a->cam_target[2] = 0.0f;
    a->cam_fov = 45.0f; a->cam_near = 0.1f; a->cam_far = 100.0f;
}

void xvk_camera_set_aspect_ratio(int64_t app_h, float aspect)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;
    if (aspect > 0.0f) a->cam_aspect = aspect;
}

void xvk_camera_set_aspect_from_fb(int64_t app_h, int32_t fb_w, int32_t fb_h)
{
    XvkApp* a = cam_from_handle(app_h);
    if (!a) return;
    if (fb_w > 0 && fb_h > 0)
        a->cam_aspect = (float)fb_w / (float)fb_h;
}

/* ── Internal API (called from draw functions with direct XvkApp* access) ── */

void xvk_camera_get_view(int64_t app_h, int64_t out_matrix)
{
    XvkApp* a = cam_from_handle(app_h);
    float* m = (float*)(intptr_t)out_matrix;
    if (!a || !m) return;
    float view[16];
    mat4_look_at(view, a->cam_eye[0], a->cam_eye[1], a->cam_eye[2],
                       a->cam_target[0], a->cam_target[1], a->cam_target[2],
                       0.0f, 1.0f, 0.0f);
    memcpy(m, view, 64);
}

void xvk_camera_get_projection(int64_t app_h, int64_t out_matrix)
{
    XvkApp* a = cam_from_handle(app_h);
    float* m = (float*)(intptr_t)out_matrix;
    if (!a || !m) return;
    float proj[16];
    mat4_perspective(proj, a->cam_fov * (float)M_PI / 180.0f, a->cam_aspect, a->cam_near, a->cam_far);
    memcpy(m, proj, 64);
}

int xvk_camera_is_active(int64_t app_h)
{
    XvkApp* a = cam_from_handle(app_h);
    return a ? a->cam_active : 0;
}

/* ── Trigonometry bridge (stateless — no app handle needed) ── */
float xvk_cos(float x) { return cosf(x); }
float xvk_sin(float x) { return sinf(x); }
