#ifndef XVK_MATH_H_
#define XVK_MATH_H_

void mat4_identity(float m[16]);
void mat4_mul(float c[16], const float a[16], const float b[16]);
void mat4_perspective(float m[16], float fov_y, float aspect, float znear, float zfar);
void mat4_look_at(float m[16], float ex, float ey, float ez, float cx, float cy, float cz, float ux, float uy, float uz);
void mat4_rotate_y(float m[16], float angle);
void mat4_rotate_x(float m[16], float angle);
void mat4_translation(float m[16], float tx, float ty, float tz);
void mat4_scale_right(float m[16], float s);

#endif
