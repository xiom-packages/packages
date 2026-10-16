/* XIOM -- xiom.gles: EGL + GLES runtime bridge (Windows ANGLE pair or the
 * Android system libraries; nothing is linked -- everything is resolved at
 * runtime).  Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: runtime loader/probe for OpenGL ES + EGL, resolved with
 * LoadLibraryA/GetProcAddress (Windows) or dlopen/dlsym (Android/POSIX) +
 * eglGetProcAddress.  No link-time dependency; the runtime must be on the
 * search path (Windows: an ANGLE pair such as an Electron app payload;
 * Android: the platform's system libraries).  The session uses a PBUFFER
 * surface (no window system dependency).
 *
 * Runtime-load candidate pairs (see xgs_pairs below; the two name lists are
 * mirrored by the generated modules `xiom.gles.egl_names`
 * (`egl_load_candidates()`) and `xiom.gles.gles_names`
 * (`gles_load_candidates()`), emitted by tools/gen_egl.py /
 * tools/gen_gles.py from the same source list):
 *   Windows ANGLE : libEGL.dll + libGLESv2.dll   (fallback EGL.dll + GLESv2.dll)
 *   Android system: libEGL.so + libGLESv2.so     (android leg; the GLES side
 *                   falls back to libGLESv3.so, then libGLESv1_CM.so when a
 *                   device only publishes those names)
 *
 * Contract (flat extern "C", called from module xiom.gles):
 *   int  xgs_load_named(const char* egl_soname, const char* gles_soname)
 *                                           0=ok 1=absent 2=abi
 *   int  xgs_load(void)                      the candidate pairs above
 *   const char* xgs_error(void)
 *   const char* xgs_loaded_pair(void)        e.g. "libEGL.so+libGLESv2.so"
 *   int  xgs_query(void)                     staged probe (strings)
 *                                            0=ok 1=no-context 2=abi
 *   const char* xgs_egl_version/vendor(void)
 *   const char* xgs_gles_vendor/renderer/version/glsl(void)
 *   int  xgs_session_open(int client_version)
 *                                            0=ok; pbuffer + context current
 *   int  xgs_session_active(void)            1 while the session lives
 *   long long xgs_session_display(void)      raw EGLDisplay of the session
 *   long long xgs_get_proc(const char* name) GLES chain: eglGetProcAddress ->
 *                                            libGLESv2 -> libEGL exports
 *   long long xgs_egl_proc(const char* name) EGL chain: eglGetProcAddress ->
 *                                            libEGL exports
 *   void xgs_session_close(void)             release surface/context
 *   void xgs_unload(void)                    (closes a live session first)
 *
 * Classification (the suite maps it to markers):
 *   XGS_LOAD_ABSENT     -> SKIP  (runtime libs missing)
 *   XGS_LOAD_NO_CONTEXT -> SKIP  (no display/config/context)
 *   XGS_LOAD_ABI        -> FAIL  (present but exports missing; never silent)
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
#define XGS_LIB_HANDLE HMODULE
#define XGS_LIB_OPEN(name)   ((HMODULE)LoadLibraryA(name))
#define XGS_LIB_SYM(h, name) ((void*)GetProcAddress((h), (name)))
#define XGS_LIB_CLOSE(h)     FreeLibrary(h)
#define XGS_APICALL WINAPI
#define XGS_LINKAGE __cdecl
#else
#include <dlfcn.h>
#define XGS_LIB_HANDLE void*
#define XGS_LIB_OPEN(name)   dlopen((name), RTLD_NOW | RTLD_LOCAL)
#define XGS_LIB_SYM(h, name) dlsym((h), (name))
#define XGS_LIB_CLOSE(h)     dlclose(h)
#define XGS_APICALL
#define XGS_LINKAGE
#endif

/* -- EGL manual declarations (no egl.h include; the ABI is pinned) ------- */

typedef void* EGLDisplay;
typedef void* EGLConfig;
typedef void* EGLSurface;
typedef void* EGLContext;
typedef void* EGLClientBuffer;
typedef unsigned int EGLBoolean;
typedef int EGLint;
typedef unsigned int EGLenum;
typedef intptr_t EGLAttrib;

typedef EGLDisplay (XGS_APICALL *PFN_eglGetDisplay)(void* native_display);
typedef EGLBoolean (XGS_APICALL *PFN_eglInitialize)(EGLDisplay dpy, EGLint* major, EGLint* minor);
typedef EGLBoolean (XGS_APICALL *PFN_eglTerminate)(EGLDisplay dpy);
typedef const char* (XGS_APICALL *PFN_eglQueryString)(EGLDisplay dpy, EGLint name);
typedef EGLint (XGS_APICALL *PFN_eglGetError)(void);
typedef EGLBoolean (XGS_APICALL *PFN_eglBindAPI)(EGLenum api);
typedef EGLBoolean (XGS_APICALL *PFN_eglChooseConfig)(EGLDisplay dpy, const EGLint* attrib_list,
                                                      EGLConfig* configs, EGLint config_size, EGLint* num_config);
typedef EGLSurface (XGS_APICALL *PFN_eglCreatePbufferSurface)(EGLDisplay dpy, EGLConfig config,
                                                              const EGLint* attrib_list);
typedef EGLContext (XGS_APICALL *PFN_eglCreateContext)(EGLDisplay dpy, EGLConfig config,
                                                       EGLContext share_context, const EGLint* attrib_list);
typedef EGLBoolean (XGS_APICALL *PFN_eglMakeCurrent)(EGLDisplay dpy, EGLSurface draw,
                                                     EGLSurface read, EGLContext ctx);
typedef EGLBoolean (XGS_APICALL *PFN_eglDestroySurface)(EGLDisplay dpy, EGLSurface surface);
typedef EGLBoolean (XGS_APICALL *PFN_eglDestroyContext)(EGLDisplay dpy, EGLContext ctx);
typedef void* (XGS_APICALL *PFN_eglGetProcAddress)(const char* procname);

typedef const unsigned char* (XGS_APICALL *PFN_glGetString)(unsigned int name);

/* EGL constants (pinned) */
#define XGS_EGL_DEFAULT_DISPLAY 0
#define XGS_EGL_NO_DISPLAY 0
#define XGS_EGL_NO_CONTEXT 0
#define XGS_EGL_NO_SURFACE 0
#define XGS_EGL_TRUE 1
#define XGS_EGL_OPENGL_ES_API 0x30A0
#define XGS_EGL_SURFACE_TYPE 0x3033
#define XGS_EGL_PBUFFER_BIT 0x0001
#define XGS_EGL_RENDERABLE_TYPE 0x3040
#define XGS_EGL_OPENGL_ES2_BIT 0x0004
#define XGS_EGL_OPENGL_ES3_BIT 0x0040
#define XGS_EGL_RED_SIZE 0x3024
#define XGS_EGL_GREEN_SIZE 0x3023
#define XGS_EGL_BLUE_SIZE 0x3022
#define XGS_EGL_ALPHA_SIZE 0x3021
#define XGS_EGL_DEPTH_SIZE 0x3025
#define XGS_EGL_STENCIL_SIZE 0x3026
#define XGS_EGL_NONE 0x3038
#define XGS_EGL_WIDTH 0x3057
#define XGS_EGL_HEIGHT 0x3056
#define XGS_EGL_CONTEXT_CLIENT_VERSION 0x3098
#define XGS_EGL_VENDOR 0x3053
#define XGS_EGL_VERSION 0x3054
#define XGS_EGL_EXTENSIONS 0x3055
#define XGS_EGL_CLIENT_APIS 0x308D

/* GL constants (pinned; GLES2/3 shared) */
#define XGS_GL_VENDOR 0x1F00
#define XGS_GL_RENDERER 0x1F01
#define XGS_GL_VERSION 0x1F02
#define XGS_GL_EXTENSIONS 0x1F03
#define XGS_GL_SHADING_LANGUAGE_VERSION 0x8B8C

/* -- module state -------------------------------------------------------- */

static XGS_LIB_HANDLE m_egl = 0;
static XGS_LIB_HANDLE m_gles = 0;

static PFN_eglGetDisplay p_eglGetDisplay = 0;
static PFN_eglInitialize p_eglInitialize = 0;
static PFN_eglTerminate p_eglTerminate = 0;
static PFN_eglQueryString p_eglQueryString = 0;
static PFN_eglGetError p_eglGetError = 0;
static PFN_eglBindAPI p_eglBindAPI = 0;
static PFN_eglChooseConfig p_eglChooseConfig = 0;
static PFN_eglCreatePbufferSurface p_eglCreatePbufferSurface = 0;
static PFN_eglCreateContext p_eglCreateContext = 0;
static PFN_eglMakeCurrent p_eglMakeCurrent = 0;
static PFN_eglDestroySurface p_eglDestroySurface = 0;
static PFN_eglDestroyContext p_eglDestroyContext = 0;
static PFN_eglGetProcAddress p_eglGetProcAddress = 0;
static PFN_glGetString p_glGetString = 0;

static char s_error[512];
static char s_pair[128];
static char s_egl_version[256];
static char s_egl_vendor[256];
static char s_gles_vendor[256];
static char s_gles_renderer[256];
static char s_gles_version[256];
static char s_gles_glsl[256];

/* session state */
static EGLDisplay s_dpy = 0;
static EGLSurface s_surf = 0;
static EGLContext s_ctx = 0;
static int s_active = 0;

static void set_err(const char* msg) {
  if (!msg) msg = "";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void copy_str(char* dst, size_t cap, const char* src) {
  if (!src) { dst[0] = 0; return; }
  strncpy(dst, src, cap - 1);
  dst[cap - 1] = 0;
}

const char* XGS_LINKAGE xgs_error(void) { return s_error; }
const char* XGS_LINKAGE xgs_loaded_pair(void) { return s_pair; }

static void clear_state(void) {
  m_egl = 0; m_gles = 0;
  p_eglGetDisplay = 0; p_eglInitialize = 0; p_eglTerminate = 0;
  p_eglQueryString = 0; p_eglGetError = 0; p_eglBindAPI = 0;
  p_eglChooseConfig = 0; p_eglCreatePbufferSurface = 0; p_eglCreateContext = 0;
  p_eglMakeCurrent = 0; p_eglDestroySurface = 0; p_eglDestroyContext = 0;
  p_eglGetProcAddress = 0; p_glGetString = 0;
  s_pair[0] = 0;
  s_egl_version[0] = 0; s_egl_vendor[0] = 0;
  s_gles_vendor[0] = 0; s_gles_renderer[0] = 0;
  s_gles_version[0] = 0; s_gles_glsl[0] = 0;
  s_dpy = 0; s_surf = 0; s_ctx = 0; s_active = 0;
}

typedef struct { const char* egl; const char* gles; } xgs_soname_pair;

/* The default candidate pairs.  Windows ANGLE first (stream 0.x behavior on
 * the Windows leg), then the Android system sonames: libGLESv2.so carries
 * ES 2.0/3.x on every device, libGLESv3.so is a legacy alias some devices
 * publish, and libGLESv1_CM.so is the last-resort name (ES1-era CM --
 * enough for the loader/probe classification, never for an ES2 context).
 * Mirrored by `egl_load_candidates()` / `gles_load_candidates()` in the
 * generated name modules (tools/gen_egl.py, tools/gen_gles.py). */
static const xgs_soname_pair xgs_pairs[] = {
  { "libEGL.dll", "libGLESv2.dll" },
  { "EGL.dll",    "GLESv2.dll" },
  { "libEGL.so",  "libGLESv2.so" },
  { "libEGL.so",  "libGLESv3.so" },
  { "libEGL.so",  "libGLESv1_CM.so" },
};
#define XGS_PAIR_COUNT ((int)(sizeof(xgs_pairs) / sizeof(xgs_pairs[0])))

static int try_load_pair(const char* egl_name, const char* gles_name) {
  XGS_LIB_HANDLE egl = XGS_LIB_OPEN(egl_name);
  if (!egl) return 0;
  XGS_LIB_HANDLE gles = XGS_LIB_OPEN(gles_name);
  if (!gles) { XGS_LIB_CLOSE(egl); return 0; }
  m_egl = egl; m_gles = gles;
  return 1;
}

int XGS_LINKAGE xgs_load_named(const char* egl_name, const char* gles_name) {
  clear_state();
  if (!egl_name || !egl_name[0] || !gles_name || !gles_name[0]) {
    set_err("empty soname"); return 1;
  }
  if (!try_load_pair(egl_name, gles_name)) {
    set_err("runtime library open failed for the EGL/GLES pair"); return 1;
  }

  p_eglGetDisplay = (PFN_eglGetDisplay)XGS_LIB_SYM(m_egl, "eglGetDisplay");
  p_eglInitialize = (PFN_eglInitialize)XGS_LIB_SYM(m_egl, "eglInitialize");
  p_eglTerminate = (PFN_eglTerminate)XGS_LIB_SYM(m_egl, "eglTerminate");
  p_eglQueryString = (PFN_eglQueryString)XGS_LIB_SYM(m_egl, "eglQueryString");
  p_eglGetError = (PFN_eglGetError)XGS_LIB_SYM(m_egl, "eglGetError");
  p_eglBindAPI = (PFN_eglBindAPI)XGS_LIB_SYM(m_egl, "eglBindAPI");
  p_eglChooseConfig = (PFN_eglChooseConfig)XGS_LIB_SYM(m_egl, "eglChooseConfig");
  p_eglCreatePbufferSurface = (PFN_eglCreatePbufferSurface)XGS_LIB_SYM(m_egl, "eglCreatePbufferSurface");
  p_eglCreateContext = (PFN_eglCreateContext)XGS_LIB_SYM(m_egl, "eglCreateContext");
  p_eglMakeCurrent = (PFN_eglMakeCurrent)XGS_LIB_SYM(m_egl, "eglMakeCurrent");
  p_eglDestroySurface = (PFN_eglDestroySurface)XGS_LIB_SYM(m_egl, "eglDestroySurface");
  p_eglDestroyContext = (PFN_eglDestroyContext)XGS_LIB_SYM(m_egl, "eglDestroyContext");
  p_eglGetProcAddress = (PFN_eglGetProcAddress)XGS_LIB_SYM(m_egl, "eglGetProcAddress");

  if (!p_eglGetDisplay || !p_eglInitialize || !p_eglQueryString || !p_eglGetProcAddress) {
    set_err("missing libEGL exports");
    XGS_LIB_CLOSE(m_gles); XGS_LIB_CLOSE(m_egl); clear_state();
    return 2;
  }

  p_glGetString = (PFN_glGetString)p_eglGetProcAddress("glGetString");
  if (!p_glGetString) p_glGetString = (PFN_glGetString)XGS_LIB_SYM(m_gles, "glGetString");
  if (!p_glGetString) {
    set_err("missing glGetString (libGLESv2/eglGetProcAddress)");
    XGS_LIB_CLOSE(m_gles); XGS_LIB_CLOSE(m_egl); clear_state();
    return 2;
  }
  snprintf(s_pair, sizeof(s_pair), "%s+%s", egl_name, gles_name);
  set_err("");
  return 0;
}

int XGS_LINKAGE xgs_load(void) {
  int abi = 0;
  int i;
  for (i = 0; i < XGS_PAIR_COUNT; i++) {
    int r = xgs_load_named(xgs_pairs[i].egl, xgs_pairs[i].gles);
    if (r == 0) return 0;
    if (r == 2) abi = 1;
  }
  if (abi) {
    set_err("EGL/GLES pair present but exports missing");
    return 2;
  }
  set_err("EGL/GLES libraries not found (Windows ANGLE pair or Android system sonames)");
  return 1;
}

static void query_strings(void) {
  copy_str(s_egl_version, sizeof(s_egl_version), p_eglQueryString(s_dpy, XGS_EGL_VERSION));
  copy_str(s_egl_vendor, sizeof(s_egl_vendor), p_eglQueryString(s_dpy, XGS_EGL_VENDOR));
  if (p_glGetString) {
    copy_str(s_gles_vendor, sizeof(s_gles_vendor), (const char*)p_glGetString(XGS_GL_VENDOR));
    copy_str(s_gles_renderer, sizeof(s_gles_renderer), (const char*)p_glGetString(XGS_GL_RENDERER));
    copy_str(s_gles_version, sizeof(s_gles_version), (const char*)p_glGetString(XGS_GL_VERSION));
    copy_str(s_gles_glsl, sizeof(s_gles_glsl), (const char*)p_glGetString(XGS_GL_SHADING_LANGUAGE_VERSION));
  }
}

/* Create display + config + pbuffer + context; keep them in *out params.
 * client_version: 3 first, 2 as a fallback.  Returns 0/1/2 like xgs_query. */
static int make_context(int client_version, EGLDisplay* out_dpy, EGLSurface* out_surf, EGLContext* out_ctx) {
  EGLDisplay dpy = p_eglGetDisplay((void*)(intptr_t)XGS_EGL_DEFAULT_DISPLAY);
  if (!dpy) { set_err("eglGetDisplay failed"); return 1; }
  EGLint major = 0, minor = 0;
  if (!p_eglInitialize(dpy, &major, &minor)) { set_err("eglInitialize failed"); return 1; }
  if (p_eglBindAPI && !p_eglBindAPI(XGS_EGL_OPENGL_ES_API)) { set_err("eglBindAPI(ES) failed"); return 1; }

  const EGLint cfg_attribs[] = {
    XGS_EGL_SURFACE_TYPE, XGS_EGL_PBUFFER_BIT,
    XGS_EGL_RENDERABLE_TYPE, XGS_EGL_OPENGL_ES2_BIT | XGS_EGL_OPENGL_ES3_BIT,
    XGS_EGL_RED_SIZE, 8, XGS_EGL_GREEN_SIZE, 8, XGS_EGL_BLUE_SIZE, 8,
    XGS_EGL_ALPHA_SIZE, 8, XGS_EGL_DEPTH_SIZE, 0, XGS_EGL_STENCIL_SIZE, 0,
    XGS_EGL_NONE
  };
  EGLConfig cfg = 0;
  EGLint ncfg = 0;
  if (!p_eglChooseConfig || !p_eglChooseConfig(dpy, cfg_attribs, &cfg, 1, &ncfg) || ncfg < 1) {
    set_err("eglChooseConfig failed (pbuffer/ES2|ES3/RGBA8)");
    if (p_eglTerminate) p_eglTerminate(dpy);
    return 1;
  }

  const EGLint pb_attribs[] = { XGS_EGL_WIDTH, 64, XGS_EGL_HEIGHT, 64, XGS_EGL_NONE };
  EGLSurface surf = p_eglCreatePbufferSurface ? p_eglCreatePbufferSurface(dpy, cfg, pb_attribs) : 0;
  if (!surf) {
    set_err("eglCreatePbufferSurface failed");
    if (p_eglTerminate) p_eglTerminate(dpy);
    return 1;
  }

  EGLContext ctx = 0;
  if (p_eglCreateContext) {
    const EGLint ctx3[] = { XGS_EGL_CONTEXT_CLIENT_VERSION, client_version, XGS_EGL_NONE };
    ctx = p_eglCreateContext(dpy, cfg, 0, ctx3);
    if (!ctx && client_version != 2) {
      const EGLint ctx2[] = { XGS_EGL_CONTEXT_CLIENT_VERSION, 2, XGS_EGL_NONE };
      ctx = p_eglCreateContext(dpy, cfg, 0, ctx2);
    }
  }
  if (!ctx) {
    set_err("eglCreateContext failed");
    if (p_eglDestroySurface) p_eglDestroySurface(dpy, surf);
    if (p_eglTerminate) p_eglTerminate(dpy);
    return 1;
  }
  if (!p_eglMakeCurrent || !p_eglMakeCurrent(dpy, surf, surf, ctx)) {
    set_err("eglMakeCurrent failed");
    if (p_eglDestroyContext) p_eglDestroyContext(dpy, ctx);
    if (p_eglDestroySurface) p_eglDestroySurface(dpy, surf);
    if (p_eglTerminate) p_eglTerminate(dpy);
    return 1;
  }
  *out_dpy = dpy; *out_surf = surf; *out_ctx = ctx;
  return 0;
}

int XGS_LINKAGE xgs_query(void) {
  if (!p_eglGetDisplay) { set_err("not loaded"); return 2; }
  EGLDisplay dpy = 0; EGLSurface surf = 0; EGLContext ctx = 0;
  int r = make_context(3, &dpy, &surf, &ctx);
  if (r != 0) { return (r == 1) ? 1 : 2; }
  s_dpy = dpy;
  query_strings();
  s_dpy = 0;
  if (p_eglMakeCurrent) p_eglMakeCurrent(dpy, XGS_EGL_NO_SURFACE, XGS_EGL_NO_SURFACE, XGS_EGL_NO_CONTEXT);
  if (p_eglDestroyContext) p_eglDestroyContext(dpy, ctx);
  if (p_eglDestroySurface) p_eglDestroySurface(dpy, surf);
  if (p_eglTerminate) p_eglTerminate(dpy);
  return 0;
}

int XGS_LINKAGE xgs_session_open(int client_version) {
  if (s_active) return 0;
  if (!p_eglGetDisplay) { set_err("not loaded"); return 2; }
  if (client_version < 2) { set_err("client version must be >= 2"); return 2; }
  EGLDisplay dpy = 0; EGLSurface surf = 0; EGLContext ctx = 0;
  int r = make_context(client_version, &dpy, &surf, &ctx);
  if (r != 0) return (r == 1) ? 1 : 2;
  s_dpy = dpy; s_surf = surf; s_ctx = ctx; s_active = 1;
  query_strings();
  return 0;
}

int XGS_LINKAGE xgs_session_active(void) { return s_active; }
long long XGS_LINKAGE xgs_session_display(void) { return (long long)(intptr_t)s_dpy; }

long long XGS_LINKAGE xgs_get_proc(const char* name) {
  if (!name || !name[0]) return 0;
  void* p = 0;
  if (p_eglGetProcAddress) p = p_eglGetProcAddress(name);
  if (!p && m_gles) p = XGS_LIB_SYM(m_gles, name);
  if (!p && m_egl) p = XGS_LIB_SYM(m_egl, name);
  return (long long)(intptr_t)p;
}

long long XGS_LINKAGE xgs_egl_proc(const char* name) {
  if (!name || !name[0]) return 0;
  void* p = 0;
  if (p_eglGetProcAddress) p = p_eglGetProcAddress(name);
  if (!p && m_egl) p = XGS_LIB_SYM(m_egl, name);
  return (long long)(intptr_t)p;
}

void XGS_LINKAGE xgs_session_close(void) {
  if (!s_active) return;
  if (p_eglMakeCurrent) p_eglMakeCurrent(s_dpy, XGS_EGL_NO_SURFACE, XGS_EGL_NO_SURFACE, XGS_EGL_NO_CONTEXT);
  if (p_eglDestroyContext) p_eglDestroyContext(s_dpy, s_ctx);
  if (p_eglDestroySurface) p_eglDestroySurface(s_dpy, s_surf);
  if (p_eglTerminate) p_eglTerminate(s_dpy);
  s_dpy = 0; s_surf = 0; s_ctx = 0; s_active = 0;
}

/* accessors */
const char* XGS_LINKAGE xgs_egl_version(void) { return s_egl_version; }
const char* XGS_LINKAGE xgs_egl_vendor(void) { return s_egl_vendor; }
const char* XGS_LINKAGE xgs_gles_vendor(void) { return s_gles_vendor; }
const char* XGS_LINKAGE xgs_gles_renderer(void) { return s_gles_renderer; }
const char* XGS_LINKAGE xgs_gles_version(void) { return s_gles_version; }
const char* XGS_LINKAGE xgs_gles_glsl(void) { return s_gles_glsl; }

void XGS_LINKAGE xgs_unload(void) {
  if (s_active) xgs_session_close();
  if (m_gles) XGS_LIB_CLOSE(m_gles);
  if (m_egl) XGS_LIB_CLOSE(m_egl);
  clear_state();
}
