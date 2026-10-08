/* xiom.opengl probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Tiny C shim for the OpenGL loader probe.  All libraries are resolved at
 * runtime (LoadLibraryA/GetProcAddress), so this object has no import
 * dependencies beyond kernel32 and does not need --link flags.
 *
 * Contract used by src/opengl.xi (extern "C"):
 *   int  xgl_load_named(const char* soname)  0=ok, 1=absent, 2=abi
 *   const char* xgl_error(void)
 *   int  xgl_contextless_len(void)           strlen(glGetString(VERSION)) with
 *                                            no current context (0 when NULL)
 *   int  xgl_query(void)                     0=ok, 1=no context, 2=internal
 *   const char* xgl_vendor/renderer/version/glsl(void)
 *   void xgl_unload(void)
 */

#include <windows.h>
#include <string.h>

typedef const char* (WINAPI *PFN_glGetString)(unsigned int);
typedef HGLRC (WINAPI *PFN_wglCreateContext)(HDC);
typedef BOOL (WINAPI *PFN_wglMakeCurrent)(HDC, HGLRC);
typedef BOOL (WINAPI *PFN_wglDeleteContext)(HGLRC);
typedef HWND (WINAPI *PFN_CreateWindowExA)(DWORD, LPCSTR, LPCSTR, DWORD, int, int, int, int, HWND, HMENU, HINSTANCE, LPVOID);
typedef BOOL (WINAPI *PFN_DestroyWindow)(HWND);
typedef HDC (WINAPI *PFN_GetDC)(HWND);
typedef int (WINAPI *PFN_ReleaseDC)(HWND, HDC);
typedef int (WINAPI *PFN_ChoosePixelFormat)(HDC, const PIXELFORMATDESCRIPTOR*);
typedef BOOL (WINAPI *PFN_SetPixelFormat)(HDC, int, const PIXELFORMATDESCRIPTOR*);

static HMODULE m_gl = 0, m_user32 = 0, m_gdi32 = 0;
static PFN_glGetString p_glGetString = 0;
static PFN_wglCreateContext p_wglCreateContext = 0;
static PFN_wglMakeCurrent p_wglMakeCurrent = 0;
static PFN_wglDeleteContext p_wglDeleteContext = 0;
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
  p_CreateWindowExA = 0; p_DestroyWindow = 0; p_GetDC = 0; p_ReleaseDC = 0;
  p_ChoosePixelFormat = 0; p_SetPixelFormat = 0;
  s_vendor[0] = 0; s_renderer[0] = 0; s_version[0] = 0; s_glsl[0] = 0;
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

int __cdecl xgl_query(void) {
  if (!p_glGetString || !p_wglCreateContext || !p_CreateWindowExA) return 2;

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

  copy_str(s_vendor, sizeof(s_vendor), p_glGetString(0x1F00));
  copy_str(s_renderer, sizeof(s_renderer), p_glGetString(0x1F01));
  copy_str(s_version, sizeof(s_version), p_glGetString(0x1F02));
  copy_str(s_glsl, sizeof(s_glsl), p_glGetString(0x8B8C));

  p_wglMakeCurrent(0, 0);
  p_wglDeleteContext(rc);
  p_ReleaseDC(hwnd, hdc);
  p_DestroyWindow(hwnd);
  return 0;
}

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
