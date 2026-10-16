/* XIOM -- xiom.gles A9 android leg: on-device evidence probe
 * (docs/repro/README.md).  Cross-built for x86_64-linux-android26 against
 * the NDK r27b clang, pushed to /data/local/tmp/xiom-spike, run; the
 * recorded transcript lives next to this file.
 *
 * It drives the SAME bridge that the XIOM module loads at runtime
 * (src/gles_probe.c, compiled together with this file), so the evidence
 * covers the real loader path -- candidate sonames -> display -> strings ->
 * a live ES2 pbuffer context -> eglQueryString(EGL_EXTENSIONS) -> one real
 * GL call through the per-call resolver.
 *
 * Output contract: every line is stable; the last line is `RESULT: PASS` or
 * `RESULT: FAIL`.  Exit code 0 on PASS, 1 on FAIL.
 *
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* -- the bridge contract (src/gles_probe.c; extern "C", flat) ------------- */

extern int xgs_load(void);
extern const char* xgs_error(void);
extern const char* xgs_loaded_pair(void);
extern int xgs_query(void);
extern const char* xgs_egl_version(void);
extern const char* xgs_egl_vendor(void);
extern const char* xgs_gles_vendor(void);
extern const char* xgs_gles_renderer(void);
extern const char* xgs_gles_version(void);
extern const char* xgs_gles_glsl(void);
extern int xgs_session_open(int client_version);
extern int xgs_session_active(void);
extern long long xgs_session_display(void);
extern long long xgs_get_proc(const char* name);
extern long long xgs_egl_proc(const char* name);
extern void xgs_session_close(void);
extern void xgs_unload(void);

/* EGL/GL constants used by the probe (pinned) */
#define P_EGL_EXTENSIONS 0x3055
#define P_GL_VERSION 0x1F02
#define P_GL_EXTENSIONS 0x1F03
#define P_GL_COLOR_BUFFER_BIT 0x00004000

typedef const unsigned char* (*PFN_glGetString)(unsigned int name);
typedef const char* (*PFN_eglQueryString)(void* dpy, int name);
typedef void (*PFN_glClearColor)(float r, float g, float b, float a);
typedef void (*PFN_glClear)(unsigned int mask);
typedef unsigned int (*PFN_glGetError)(void);

static int s_fail = 0;

static void check(int ok, const char* what) {
  printf("  [%s] %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) s_fail = 1;
}

/* Count space-separated extension names; optionally report presence. */
static int count_extensions(const char* s) {
  int n = 0;
  int in = 0;
  const char* p = s;
  if (!s) return -1;
  for (; *p; p++) {
    if (*p == ' ') { in = 0; }
    else if (!in) { in = 1; n++; }
  }
  return n;
}

static int has_extension(const char* s, const char* name) {
  const char* p = s;
  size_t n = strlen(name);
  if (!s) return 0;
  while (p && *p) {
    if (strncmp(p, name, n) == 0 && (p[n] == ' ' || p[n] == 0)) return 1;
    p = strchr(p, ' ');
    if (p) p++;
    while (p && *p == ' ') p++;
  }
  return 0;
}

int main(void) {
  int rc;

  printf("=== xiom.gles A9 android leg probe (x86_64-linux-android26) ===\n");
  printf("--- bridge: src/gles_probe.c (runtime-load, no link deps) ---\n");

  /* 1. loader: candidate pairs (Windows ANGLE names, then Android system). */
  rc = xgs_load();
  printf("load.rc=%d\n", rc);
  printf("load.error=%s\n", xgs_error());
  printf("load.pair=%s\n", xgs_loaded_pair());
  check(rc == 0, "loader resolved libEGL.so + a GLES system library");
  check(strncmp(xgs_loaded_pair(), "libEGL.so+", 10) == 0,
        "loaded pair is an Android system soname pair (candidate leg proven)");

  /* 2. staged probe: display + strings (GL_VERSION / GL_RENDERER / EGL). */
  rc = xgs_query();
  printf("query.rc=%d\n", rc);
  printf("egl.version=%s\n", xgs_egl_version());
  printf("egl.vendor=%s\n", xgs_egl_vendor());
  printf("gles.vendor=%s\n", xgs_gles_vendor());
  printf("gles.renderer=%s\n", xgs_gles_renderer());
  printf("gles.version=%s\n", xgs_gles_version());
  printf("gles.glsl=%s\n", xgs_gles_glsl());
  check(rc == 0, "display + strings stage (EGL_VERSION / GL_VERSION / GL_RENDERER live)");
  check(xgs_gles_version()[0] != 0, "GL_VERSION resolved on-device");
  check(xgs_gles_renderer()[0] != 0, "GL_RENDERER resolved on-device");

  /* 3. one real GLES2 context (client_version=2 exactly) on the live path. */
  rc = xgs_session_open(2);
  printf("session.rc=%d\n", rc);
  printf("session.error=%s\n", xgs_error());
  printf("session.active=%d\n", xgs_session_active());
  printf("session.display=%lld\n", xgs_session_display());
  check(rc == 0 && xgs_session_active() == 1, "live GLES2 context current (client_version=2)");
  check(xgs_session_display() != 0, "EGLDisplay resolved and live");

  if (rc == 0) {
    /* 4. eglQueryString(EGL_EXTENSIONS) through the per-call resolver. */
    PFN_eglQueryString qs = (PFN_eglQueryString)xgs_egl_proc("eglQueryString");
    check(qs != 0, "eglQueryString resolved through xgs_egl_proc");
    if (qs) {
      const char* exts = qs((void*)xgs_session_display(), P_EGL_EXTENSIONS);
      int n = count_extensions(exts);
      printf("egl.extensions.count=%d\n", n);
      printf("egl.extensions=%s\n", exts ? exts : "");
      check(n >= 10, "eglQueryString(EGL_EXTENSIONS) returned the device extension list");
      check(has_extension(exts, "EGL_KHR_fence_sync"), "extensions contain EGL_KHR_fence_sync");
      check(has_extension(exts, "EGL_ANDROID_native_fence_sync"), "extensions contain EGL_ANDROID_native_fence_sync");
      check(has_extension(exts, "EGL_ANDROID_presentation_time"), "extensions contain EGL_ANDROID_presentation_time");
      check(has_extension(exts, "EGL_ANDROID_recordable"), "extensions contain EGL_ANDROID_recordable");
      check(has_extension(exts, "EGL_ANDROID_front_buffer_auto_refresh"), "extensions contain EGL_ANDROID_front_buffer_auto_refresh");
      check(has_extension(exts, "EGL_ANDROID_get_frame_timestamps"), "extensions contain EGL_ANDROID_get_frame_timestamps");
      check(has_extension(exts, "EGL_ANDROID_get_native_client_buffer"), "extensions contain EGL_ANDROID_get_native_client_buffer");
      /* informational (device-conditional KHR names on this emulator) */
      printf("egl.extensions.khr_surfaceless_context=%s\n",
             has_extension(exts, "EGL_KHR_surfaceless_context") ? "present" : "absent");
      printf("egl.extensions.khr_no_config_context=%s\n",
             has_extension(exts, "EGL_KHR_no_config_context") ? "present" : "absent");
    }

    /* 5. GL strings through the GLES resolver + one real GL call. */
    PFN_glGetString ggs = (PFN_glGetString)xgs_get_proc("glGetString");
    check(ggs != 0, "glGetString resolved through xgs_get_proc");
    if (ggs) {
      const char* gver = (const char*)ggs(P_GL_VERSION);
      const char* gext = (const char*)ggs(P_GL_EXTENSIONS);
      printf("gl.version.via.proc=%s\n", gver ? gver : "");
      printf("gl.extensions.count=%d\n", count_extensions(gext));
      check(gver && gver[0] != 0, "glGetString(GL_VERSION) through the per-call resolver");
    }    PFN_glClearColor cc = (PFN_glClearColor)xgs_get_proc("glClearColor");
    PFN_glClear clr = (PFN_glClear)xgs_get_proc("glClear");
    PFN_glGetError ge = (PFN_glGetError)xgs_get_proc("glGetError");
    check(cc != 0 && clr != 0 && ge != 0, "glClearColor/glClear/glGetError resolved through the per-call resolver");
    if (cc && clr && ge) {
      unsigned int err;
      cc(0.0f, 0.0f, 0.0f, 1.0f);
      clr(P_GL_COLOR_BUFFER_BIT);
      err = ge();
      printf("gl.clear.error=%u\n", err);
      check(err == 0, "one real GL call on the live context (glClear -> glGetError==0)");
    }

    xgs_session_close();
    printf("session.closed.active=%d\n", xgs_session_active());
    check(xgs_session_active() == 0, "session closed cleanly");
  }

  xgs_unload();
  printf("RESULT: %s\n", s_fail ? "FAIL" : "PASS");
  return s_fail;
}
