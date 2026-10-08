/* xiom.opengl probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Tiny C shim for the OpenGL loader probes.  All libraries are resolved at
 * runtime (LoadLibraryA/GetProcAddress), so this object has no import
 * dependencies beyond kernel32 and does not need --link flags.
 *
 * Contract used by opengl.xi (extern "C"):
 *   int  xgl_load_named(const char* soname)   0=ok, 1=absent, 2=abi
 *   const char* xgl_error(void)
 *   int  xgl_contextless_len(void)            strlen(glGetString(VERSION)) with
 *                                             no current context (0 when NULL)
 *   int  xgl_query(void)                      classic-context strings
 *                                             0=ok, 1=no context, 2=internal
 *   int  xgl_query_core(int major, int minor, int flags)
 *                                             core-context probe; fills
 *                                             strings + core version +
 *                                             extension count/head
 *   int  xgl_core_major/minor(void)
 *   int  xgl_extension_count(void)
 *   const char* xgl_extension_head(void)      first up to 4 names, comma-joined
 *   int  xgl_has_extension(const char* name)  1=present, 0=absent, -1=failure
 *   const char* xgl_vendor/renderer/version/glsl(void)
 *   void xgl_unload(void)
 */

#include <windows.h>
#include <string.h>

typedef const char* (WINAPI *PFN_glGetString)(unsigned int);
typedef const char* (WINAPI *PFN_glGetStringi)(unsigned int, unsigned int);
typedef void (WINAPI *PFN_glGetIntegerv)(unsigned int, int*);
typedef HGLRC (WINAPI *PFN_wglCreateContext)(HDC);
typedef HGLRC (WINAPI *PFN_wglCreateContextAttribsARB)(HDC, HGLRC, const int*);
typedef BOOL (WINAPI *PFN_wglMakeCurrent)(HDC, HGLRC);
typedef BOOL (WINAPI *PFN_wglDeleteContext)(HGLRC);
typedef PROC (WINAPI *PFN_wglGetProcAddress)(LPCSTR);
typedef HWND (WINAPI *PFN_CreateWindowExA)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
typedef BOOL (WINAPI *PFN_DestroyWindow)(HWND);
typedef HDC (WINAPI *PFN_GetDC)(HWND);
typedef int (WINAPI *PFN_ReleaseDC)(HWND, HDC);
typedef int (WINAPI *PFN_ChoosePixelFormat)(HDC, const PIXELFORMATDESCRIPTOR*);
typedef BOOL (WINAPI *PFN_SetPixelFormat)(HDC, int, const PIXELFORMATDESCRIPTOR*);

/* WGL/GL constants used by the core probe. */
#define XIOM_WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define XIOM_WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define XIOM_WGL_CONTEXT_FLAGS_ARB         0x2094
#define XIOM_WGL_CONTEXT_PROFILE_MASK_ARB  0x9126
#define XIOM_WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001
#define XIOM_GL_MAJOR_VERSION 0x821B
#define XIOM_GL_MINOR_VERSION 0x821C
#define XIOM_GL_NUM_EXTENSIONS 0x821D
#define XIOM_GL_EXTENSIONS     0x1F03

static HMODULE m_gl = 0, m_user32 = 0, m_gdi32 = 0;
static PFN_glGetString p_glGetString = 0;
static PFN_wglCreateContext p_wglCreateContext = 0;
static PFN_wglMakeCurrent p_wglMakeCurrent = 0;
static PFN_wglDeleteContext p_wglDeleteContext = 0;
static PFN_wglGetProcAddress p_wglGetProcAddress = 0;
static PFN_CreateWindowExA p_CreateWindowExA = 0;
static PFN_DestroyWindow p_DestroyWindow = 0;
static PFN_GetDC p_GetDC = 0;
static PFN_ReleaseDC p_ReleaseDC = 0;
static PFN_ChoosePixelFormat p_ChoosePixelFormat = 0;
static PFN_SetPixelFormat p_SetPixelFormat = 0;

static char s_error[512];
static char s_vendor[256];
static char s_renderer[256];
static char s_version[256];
static char s_glsl[256];
static char s_ext_head[512];
static int s_core_major = 0;
static int s_core_minor = 0;
static int s_ext_count = 0;

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void copy_str(char* dst, size_t cap, const char* src) {
  if (!src) { dst[0] = 0; return; }
  strncpy(dst, src, cap - 1);
  dst[cap - 1] = 0;
}

static void clear_state(void) {
  m_gl = 0; m_user32 = 0; m_gdi32 = 0;
  p_glGetString = 0; p_wglCreateContext = 0; p_wglMakeCurrent = 0; p_wglDeleteContext = 0;
  p_wglGetProcAddress = 0;
  p_CreateWindowExA = 0; p_DestroyWindow = 0; p_GetDC = 0; p_ReleaseDC = 0;
  p_ChoosePixelFormat = 0; p_SetPixelFormat = 0;
  s_vendor[0] = 0; s_renderer[0] = 0; s_version[0] = 0; s_glsl[0] = 0;
  s_ext_head[0] = 0; s_core_major = 0; s_core_minor = 0; s_ext_count = 0;
}

int __cdecl xgl_load_named(const char* soname) {
  clear_state();
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_gl = LoadLibraryA(soname);
  if (!m_gl) { set_err("LoadLibrary failed for the requested soname"); return 1; }

  p_glGetString = (PFN_glGetString)GetProcAddress(m_gl, "glGetString");
  if (!p_glGetString) { set_err("missing export: glGetString"); FreeLibrary(m_gl); clear_state(); return 2; }
  p_wglCreateContext = (PFN_wglCreateContext)GetProcAddress(m_gl, "wglCreateContext");
  if (!p_wglCreateContext) { set_err("missing export: wglCreateContext"); FreeLibrary(m_gl); clear_state(); return 2; }
  p_wglMakeCurrent = (PFN_wglMakeCurrent)GetProcAddress(m_gl, "wglMakeCurrent");
  if (!p_wglMakeCurrent) { set_err("missing export: wglMakeCurrent"); FreeLibrary(m_gl); clear_state(); return 2; }
  p_wglDeleteContext = (PFN_wglDeleteContext)GetProcAddress(m_gl, "wglDeleteContext");
  if (!p_wglDeleteContext) { set_err("missing export: wglDeleteContext"); FreeLibrary(m_gl); clear_state(); return 2; }
  p_wglGetProcAddress = (PFN_wglGetProcAddress)GetProcAddress(m_gl, "wglGetProcAddress");
  if (!p_wglGetProcAddress) { set_err("missing export: wglGetProcAddress"); FreeLibrary(m_gl); clear_state(); return 2; }

  m_user32 = LoadLibraryA("user32.dll");
  if (!m_user32) { set_err("LoadLibrary failed: user32.dll"); FreeLibrary(m_gl); clear_state(); return 1; }
  p_CreateWindowExA = (PFN_CreateWindowExA)GetProcAddress(m_user32, "CreateWindowExA");
  p_DestroyWindow = (PFN_DestroyWindow)GetProcAddress(m_user32, "DestroyWindow");
  p_GetDC = (PFN_GetDC)GetProcAddress(m_user32, "GetDC");
  p_ReleaseDC = (PFN_ReleaseDC)GetProcAddress(m_user32, "ReleaseDC");
  if (!p_CreateWindowExA || !p_DestroyWindow || !p_GetDC || !p_ReleaseDC) {
    set_err("missing user32 exports"); FreeLibrary(m_user32); FreeLibrary(m_gl); clear_state(); return 2;
  }

  m_gdi32 = LoadLibraryA("gdi32.dll");
  if (!m_gdi32) { set_err("LoadLibrary failed: gdi32.dll"); FreeLibrary(m_user32); FreeLibrary(m_gl); clear_state(); return 1; }
  p_ChoosePixelFormat = (PFN_ChoosePixelFormat)GetProcAddress(m_gdi32, "ChoosePixelFormat");
  p_SetPixelFormat = (PFN_SetPixelFormat)GetProcAddress(m_gdi32, "SetPixelFormat");
  if (!p_ChoosePixelFormat || !p_SetPixelFormat) {
    set_err("missing gdi32 exports"); FreeLibrary(m_gdi32); FreeLibrary(m_user32); FreeLibrary(m_gl); clear_state(); return 2;
  }
  return 0;
}

int __cdecl xgl_load(void) {
  return xgl_load_named("opengl32.dll");
}

const char* __cdecl xgl_error(void) {
  return s_error;
}

int __cdecl xgl_contextless_len(void) {
  if (!p_glGetString) return -1;
  const char* p = p_glGetString(0x1F02); /* GL_VERSION */
  if (!p) return 0;
  return (int)strlen(p);
}

/* -- context helpers ------------------------------------------------------ */

static PROC resolve_proc(const char* name) {
  PROC p = 0;
  if (p_wglGetProcAddress) p = p_wglGetProcAddress(name);
  if (!p && m_gl) p = GetProcAddress(m_gl, name);
  return p;
}

/* Create a pixel-formatted window and a context.  core_major <= 0 creates a
 * classic context; core_major > 0 obtains wglCreateContextAttribsARB through
 * a temporary classic context and creates a core-profile context with the
 * requested version.  Returns 0 on success; on failure sets s_error and
 * cleans up everything it created. */
static int make_context(int core_major, int core_minor, int flags,
                        HWND* phwnd, HDC* phdc, HGLRC* prc) {
  HWND hwnd = p_CreateWindowExA(0, "STATIC", "xiom-opengl-probe", 0, 0, 0, 1, 1, 0, 0, 0, 0);
  if (!hwnd) { set_err("CreateWindowExA failed"); return 1; }
  HDC hdc = p_GetDC(hwnd);
  if (!hdc) { p_DestroyWindow(hwnd); set_err("GetDC failed"); return 1; }

  PIXELFORMATDESCRIPTOR pfd;
  memset(&pfd, 0, sizeof(pfd));
  pfd.nSize = (WORD)sizeof(pfd);
  pfd.nVersion = 1;
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
  pfd.iPixelType = PFD_TYPE_RGBA;
  pfd.cColorBits = 32;
  pfd.cDepthBits = 24;
  pfd.cStencilBits = 8;
  pfd.iLayerType = PFD_MAIN_PLANE;

  int fmt = p_ChoosePixelFormat(hdc, &pfd);
  if (!fmt) { p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd); set_err("ChoosePixelFormat failed"); return 1; }
  if (!p_SetPixelFormat(hdc, fmt, &pfd)) { p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd); set_err("SetPixelFormat failed"); return 1; }

  HGLRC rc = p_wglCreateContext(hdc);
  if (!rc) { p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd); set_err("wglCreateContext failed"); return 1; }
  if (!p_wglMakeCurrent(hdc, rc)) {
    p_wglDeleteContext(rc); p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd);
    set_err("wglMakeCurrent failed"); return 1;
  }

  if (core_major > 0) {
    PFN_wglCreateContextAttribsARB attribs_fn =
      (PFN_wglCreateContextAttribsARB)resolve_proc("wglCreateContextAttribsARB");
    if (!attribs_fn) {
      p_wglMakeCurrent(0, 0); p_wglDeleteContext(rc); p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd);
      set_err("wglCreateContextAttribsARB unavailable"); return 2;
    }
    const int attribs[] = {
      XIOM_WGL_CONTEXT_MAJOR_VERSION_ARB, core_major,
      XIOM_WGL_CONTEXT_MINOR_VERSION_ARB, core_minor,
      XIOM_WGL_CONTEXT_PROFILE_MASK_ARB, XIOM_WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
      XIOM_WGL_CONTEXT_FLAGS_ARB, flags,
      0
    };
    HGLRC core_rc = attribs_fn(hdc, 0, attribs);
    if (!core_rc) {
      p_wglMakeCurrent(0, 0); p_wglDeleteContext(rc); p_ReleaseDC(hwnd, hdc); p_DestroyWindow(hwnd);
      set_err("wglCreateContextAttribsARB failed for the requested version"); return 1;
    }
    p_wglMakeCurrent(hdc, core_rc);
    p_wglDeleteContext(rc);
    rc = core_rc;
  }

  *phwnd = hwnd;
  *phdc = hdc;
  *prc = rc;
  return 0;
}

static void release_context(HWND hwnd, HDC hdc, HGLRC rc) {
  p_wglMakeCurrent(0, 0);
  if (rc) p_wglDeleteContext(rc);
  if (hdc) p_ReleaseDC(hwnd, hdc);
  if (hwnd) p_DestroyWindow(hwnd);
}

static void query_strings(void) {
  copy_str(s_vendor, sizeof(s_vendor), p_glGetString(0x1F00));
  copy_str(s_renderer, sizeof(s_renderer), p_glGetString(0x1F01));
  copy_str(s_version, sizeof(s_version), p_glGetString(0x1F02));
  copy_str(s_glsl, sizeof(s_glsl), p_glGetString(0x8B8C));
}

/* -- classic-context probe ------------------------------------------------ */

int __cdecl xgl_query(void) {
  if (!p_glGetString || !p_wglCreateContext || !p_CreateWindowExA) return 2;
  HWND hwnd = 0; HDC hdc = 0; HGLRC rc = 0;
  int r = make_context(0, 0, 0, &hwnd, &hdc, &rc);
  if (r != 0) return (r == 1) ? 1 : 2;
  query_strings();
  release_context(hwnd, hdc, rc);
  return 0;
}

/* -- core-context probe + extension loading ------------------------------ */

int __cdecl xgl_query_core(int major, int minor, int flags) {
  if (!p_glGetString || !p_wglCreateContext || !p_CreateWindowExA) return 2;
  if (major <= 0) { set_err("core major version must be positive"); return 2; }

  HWND hwnd = 0; HDC hdc = 0; HGLRC rc = 0;
  int r = make_context(major, minor, flags, &hwnd, &hdc, &rc);
  if (r != 0) return (r == 1) ? 1 : 2;

  PFN_glGetIntegerv get_int = (PFN_glGetIntegerv)resolve_proc("glGetIntegerv");
  PFN_glGetStringi get_stringi = (PFN_glGetStringi)resolve_proc("glGetStringi");
  if (!get_int) {
    release_context(hwnd, hdc, rc);
    set_err("missing glGetIntegerv for the core probe");
    return 2;
  }

  query_strings();

  int vmajor = 0, vminor = 0, count = 0;
  get_int(XIOM_GL_MAJOR_VERSION, &vmajor);
  get_int(XIOM_GL_MINOR_VERSION, &vminor);
  get_int(XIOM_GL_NUM_EXTENSIONS, &count);
  s_core_major = vmajor;
  s_core_minor = vminor;
  s_ext_count = count;

  s_ext_head[0] = 0;
  if (get_stringi && count > 0) {
    int shown = (count < 4) ? count : 4;
    for (int i = 0; i < shown; i++) {
      const char* name = get_stringi(XIOM_GL_EXTENSIONS, (unsigned int)i);
      if (!name) continue;
      if (s_ext_head[0]) strncat(s_ext_head, ",", sizeof(s_ext_head) - strlen(s_ext_head) - 1);
      strncat(s_ext_head, name, sizeof(s_ext_head) - strlen(s_ext_head) - 1);
    }
  }

  release_context(hwnd, hdc, rc);
  return 0;
}

int __cdecl xgl_core_major(void) { return s_core_major; }
int __cdecl xgl_core_minor(void) { return s_core_minor; }
int __cdecl xgl_extension_count(void) { return s_ext_count; }
const char* __cdecl xgl_extension_head(void) { return s_ext_head; }

int __cdecl xgl_has_extension(const char* name) {
  if (!name || !name[0]) return -1;
  if (!p_glGetString || !p_wglCreateContext || !p_CreateWindowExA) return -1;

  HWND hwnd = 0; HDC hdc = 0; HGLRC rc = 0;
  int r = make_context(3, 3, 0, &hwnd, &hdc, &rc);
  if (r != 0) return -1;

  PFN_glGetIntegerv get_int = (PFN_glGetIntegerv)resolve_proc("glGetIntegerv");
  PFN_glGetStringi get_stringi = (PFN_glGetStringi)resolve_proc("glGetStringi");
  int found = 0;
  if (get_int && get_stringi) {
    int count = 0;
    get_int(XIOM_GL_NUM_EXTENSIONS, &count);
    for (int i = 0; i < count; i++) {
      const char* ext = get_stringi(XIOM_GL_EXTENSIONS, (unsigned int)i);
      if (ext && strcmp(ext, name) == 0) { found = 1; break; }
    }
  } else {
    set_err("missing glGetIntegerv/glGetStringi for the extension scan");
    release_context(hwnd, hdc, rc);
    return -1;
  }

  release_context(hwnd, hdc, rc);
  return found;
}

/* -- accessors + teardown ------------------------------------------------- */

const char* __cdecl xgl_vendor(void) { return s_vendor; }
const char* __cdecl xgl_renderer(void) { return s_renderer; }
const char* __cdecl xgl_version(void) { return s_version; }
const char* __cdecl xgl_glsl(void) { return s_glsl; }

void __cdecl xgl_unload(void) {
  if (m_gdi32) FreeLibrary(m_gdi32);
  if (m_user32) FreeLibrary(m_user32);
  if (m_gl) FreeLibrary(m_gl);
  clear_state();
}
