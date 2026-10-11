/* cb-abi probe host -- xiom.glfw 0.5.0 callback-ABI gate (bindings lane).
 *
 * Shapes probed (the GLFW callback surface reduces to these):
 *   1. int (*)(int) called immediately          (G-16 "fn as Int" pattern)
 *   2. int (*)(int) stored, invoked later       (registry lifetime)
 *   3. GLFW key shape void (*)(void*, int, int, int, int)
 *   4. GLFW close shape void (*)(void*)
 *
 * The XIOM callbacks record received values through xt_cb_note* (a C-side
 * recorder), so param marshalling C -> XIOM is observable.
 * Ground-truth control: xt_cb_plus_one (a pure C callee).
 */
#include <stdint.h>

/* ---- ground truth control ------------------------------------------------ */
int xt_cb_plus_one(int x) { return x + 1; }

/* fn-TYPED extern param variant: C sees an ordinary int(*)(int). */
int xt_cb_int_fn(int (*f)(int), int x) { return f(x); }

/* Exported twin for the dynamic-loader cast-call variant (dl_sym finds it). */
#if defined(_WIN32)
__declspec(dllexport) int xt_cb_int_fn_export(int (*f)(int), int x) { return f(x); }
#else
int xt_cb_int_fn_export(int (*f)(int), int x) { return f(x); }
#endif

/* ---- shape 1: immediate int(*)(int) call --------------------------------- */
int xt_cb_int(int (*f)(int), int x) { return f(x); }

/* ---- shape 2: stored int(*)(int) ----------------------------------------- */
static int (*g_int)(int) = 0;
void xt_cb_store_int(int (*f)(int)) { g_int = f; }
int xt_cb_invoke_stored(int x) { return g_int ? g_int(x) : -9999; }

/* ---- shape 3: GLFW key callback ------------------------------------------ */
typedef void (*xt_key_cb)(void* win, int key, int scancode, int action, int mods);
static xt_key_cb g_key = 0;
static int64_t g_key_calls = 0;
static int64_t g_key_win = 0;
static int g_last_key = -1, g_last_sc = -1, g_last_action = -1, g_last_mods = -1;

void xt_cb_set_key(xt_key_cb f) { g_key = f; }
int xt_cb_fire_key(void* win, int key, int scancode, int action, int mods) {
  if (!g_key) return -1;
  g_key(win, key, scancode, action, mods);
  return 0;
}

/* ---- shape 4: GLFW close callback ---------------------------------------- */
typedef void (*xt_close_cb)(void* win);
static xt_close_cb g_close = 0;
static int64_t g_close_calls = 0;
static int64_t g_close_win = 0;

void xt_cb_set_close(xt_close_cb f) { g_close = f; }
int xt_cb_fire_close(void* win) {
  if (!g_close) return -1;
  g_close(win);
  return 0;
}

/* ---- recorders (called from the XIOM callbacks) --------------------------- */
void xt_cb_note_key(int64_t win, int key, int scancode, int action, int mods) {
  g_key_calls++;
  g_key_win = win;
  g_last_key = key; g_last_sc = scancode; g_last_action = action; g_last_mods = mods;
}
void xt_cb_note_close(int64_t win) {
  g_close_calls++;
  g_close_win = win;
}

/* ---- readback + reset ------------------------------------------------------ */
int64_t xt_cb_key_calls(void) { return g_key_calls; }
int xt_cb_last_key(void) { return g_last_key; }
int xt_cb_last_scancode(void) { return g_last_sc; }
int xt_cb_last_action(void) { return g_last_action; }
int xt_cb_last_mods(void) { return g_last_mods; }
int64_t xt_cb_key_win(void) { return g_key_win; }
int64_t xt_cb_close_calls(void) { return g_close_calls; }
int64_t xt_cb_close_win(void) { return g_close_win; }

void xt_cb_reset(void) {
  g_key_calls = 0; g_close_calls = 0;
  g_key_win = 0; g_close_win = 0;
  g_last_key = g_last_sc = g_last_action = g_last_mods = -1;
}
