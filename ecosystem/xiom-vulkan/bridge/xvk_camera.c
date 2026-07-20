#include "xvk_camera.h"
#include "xvk_math.h"
#include <string.h>
#include <math.h>

static float g_eye[3]    = { 2.0f, 2.0f, 2.0f };
static float g_target[3] = { 0.0f, 0.0f, 0.0f };
static float g_up[3]     = { 0.0f, 1.0f, 0.0f };
static float g_fov        = 45.0f;
static float g_near       = 0.1f;
static float g_far        = 100.0f;
static float g_aspect     = 16.0f / 9.0f;  /* updated per-frame from swapchain */
static int   g_active     = 0;

void xvk_camera_set_view(float eye_x, float eye_y, float eye_z,
                          float target_x, float target_y, float target_z)
{
    g_eye[0] = eye_x; g_eye[1] = eye_y; g_eye[2] = eye_z;
    g_target[0] = target_x; g_target[1] = target_y; g_target[2] = target_z;
    g_active = 1;
}

void xvk_camera_set_projection(float fov_deg, float near_plane, float far_plane)
{
    g_fov = fov_deg;
    g_near = near_plane;
    g_far = far_plane;
}

void xvk_camera_set_aspect_ratio(float aspect)
{
    if (aspect > 0.0f) g_aspect = aspect;
}

void xvk_camera_get_view(int64_t out_matrix)
{
    float* m = (float*)(intptr_t)out_matrix;
    if (!m) return;
    float view[16];
    mat4_look_at(view, g_eye[0], g_eye[1], g_eye[2],
                       g_target[0], g_target[1], g_target[2],
                       g_up[0], g_up[1], g_up[2]);
    memcpy(m, view, 64);
}

void xvk_camera_get_projection(int64_t out_matrix)
{
    float* m = (float*)(intptr_t)out_matrix;
    if (!m) return;
    float proj[16];
    mat4_perspective(proj, g_fov * (float)M_PI / 180.0f, g_aspect, g_near, g_far);
    memcpy(m, proj, 64);
}

void xvk_camera_orbit(float delta_yaw, float delta_pitch, float delta_radius)
{
    /* Compute spherical coords from current eye relative to target */
    float dx = g_eye[0] - g_target[0];
    float dy = g_eye[1] - g_target[1];
    float dz = g_eye[2] - g_target[2];
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

    g_eye[0] = g_target[0] + radius * cosf(pitch) * cosf(yaw);
    g_eye[1] = g_target[1] + radius * sinf(pitch);
    g_eye[2] = g_target[2] + radius * cosf(pitch) * sinf(yaw);
}

void xvk_camera_pan(float dx, float dy)
{
    g_target[0] += dx;
    g_target[1] += dy;
    g_eye[0] += dx;
    g_eye[1] += dy;
}

void xvk_camera_zoom(float delta)
{
    float dir[3] = { g_target[0] - g_eye[0], g_target[1] - g_eye[1], g_target[2] - g_eye[2] };
    float len = sqrtf(dir[0]*dir[0] + dir[1]*dir[1] + dir[2]*dir[2]);
    if (len < 0.001f) len = 0.001f;
    g_eye[0] += dir[0] / len * delta;
    g_eye[1] += dir[1] / len * delta;
    g_eye[2] += dir[2] / len * delta;
}

void xvk_camera_reset(void)
{
    g_eye[0] = 2.0f; g_eye[1] = 2.0f; g_eye[2] = 2.0f;
    g_target[0] = 0.0f; g_target[1] = 0.0f; g_target[2] = 0.0f;
    g_fov = 45.0f; g_near = 0.1f; g_far = 100.0f;
}

int xvk_camera_is_active(void) { return g_active; }

/* ── Trigonometry bridge (Float32 sin/cos for XIOM orbit math) ── */
float xvk_cos(float x) { return cosf(x); }
float xvk_sin(float x) { return sinf(x); }
