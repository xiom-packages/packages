#include "xvk_math.h"
#include <math.h>
#include <string.h>

void mat4_identity(float m[16])
{
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

void mat4_mul(float c[16], const float a[16], const float b[16])
{
    for (int col = 0; col < 4; ++col) {
        for (int row = 0; row < 4; ++row) {
            float sum = 0.0f;
            for (int k = 0; k < 4; ++k) {
                sum += a[k * 4 + row] * b[col * 4 + k];
            }
            c[col * 4 + row] = sum;
        }
    }
}

void mat4_perspective(float m[16], float fov_y, float aspect,
                       float znear, float zfar)
{
    float t = 1.0f / tanf(fov_y * 0.5f);
    memset(m, 0, 16 * sizeof(float));
    m[0]  = t / aspect;
    m[5]  = -t;
    m[10] = -zfar / (zfar - znear);
    m[11] = -1.0f;
    m[14] = -znear * zfar / (zfar - znear);
}

void mat4_look_at(float m[16],
                   float ex, float ey, float ez,
                   float cx, float cy, float cz,
                   float ux, float uy, float uz)
{
    float f[3] = { cx - ex, cy - ey, cz - ez };
    float flen = sqrtf(f[0]*f[0] + f[1]*f[1] + f[2]*f[2]);
    if (flen < 1e-8f) { flen = 1.0f; }
    f[0] /= flen; f[1] /= flen; f[2] /= flen;

    float r[3] = {
        f[1] * uz - f[2] * uy,
        f[2] * ux - f[0] * uz,
        f[0] * uy - f[1] * ux
    };
    float rlen = sqrtf(r[0]*r[0] + r[1]*r[1] + r[2]*r[2]);
    if (rlen < 1e-8f) { rlen = 1.0f; }
    r[0] /= rlen; r[1] /= rlen; r[2] /= rlen;

    float u[3] = {
        r[1] * f[2] - r[2] * f[1],
        r[2] * f[0] - r[0] * f[2],
        r[0] * f[1] - r[1] * f[0]
    };

    memset(m, 0, 16 * sizeof(float));
    m[0]  = r[0]; m[4]  = u[0]; m[8]  = -f[0];
    m[1]  = r[1]; m[5]  = u[1]; m[9]  = -f[1];
    m[2]  = r[2]; m[6]  = u[2]; m[10] = -f[2];
    m[12] = -(r[0]*ex + r[1]*ey + r[2]*ez);
    m[13] = -(u[0]*ex + u[1]*ey + u[2]*ez);
    m[14] =  (f[0]*ex + f[1]*ey + f[2]*ez);
    m[15] = 1.0f;
}

void mat4_rotate_y(float m[16], float angle)
{
    float c = cosf(angle), s = sinf(angle);
    float rot[16];
    mat4_identity(rot);
    rot[0]  = c;   rot[2]  = -s;
    rot[8]  = s;   rot[10] = c;
    float tmp[16];
    mat4_mul(tmp, m, rot);
    memcpy(m, tmp, sizeof(tmp));
}

void mat4_rotate_x(float m[16], float angle)
{
    float c = cosf(angle), s = sinf(angle);
    float rot[16];
    mat4_identity(rot);
    rot[5]  = c;   rot[6]  = s;
    rot[9]  = -s;  rot[10] = c;
    float tmp[16];
    mat4_mul(tmp, m, rot);
    memcpy(m, tmp, sizeof(tmp));
}

void mat4_translation(float m[16], float tx, float ty, float tz)
{
    memset(m, 0, 16 * sizeof(float));
    m[0]  = 1.0f;
    m[5]  = 1.0f;
    m[10] = 1.0f;
    m[15] = 1.0f;
    m[12] = tx;
    m[13] = ty;
    m[14] = tz;
}

void mat4_scale_right(float m[16], float s)
{
    for (int j = 0; j < 3; ++j) {
        int idx = j * 4;
        m[idx]   *= s;
        m[idx+1] *= s;
        m[idx+2] *= s;
        m[idx+3] *= s;
    }
}
