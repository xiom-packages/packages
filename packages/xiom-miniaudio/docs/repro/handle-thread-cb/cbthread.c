/* MiniAudio handle-surface feasibility probe: XIOM fn pointer invoked from a
 * FOREIGN C thread (the miniaudio audio-thread shape), with a marker written
 * by the XIOM callback into the C-owned render buffer.
 *
 * Shapes:
 *   set render cb (fn-typed extern param) -> spawn a worker thread that calls
 *   it repeatedly on a 64-byte buffer -> C-side call/marker counters.
 *   xtc_burn() lets the main thread sit in C while the worker runs XIOM code.
 */
#include <stdint.h>

#if defined(_WIN32)
#include <windows.h>
typedef void (*xtc_render_cb)(unsigned char* out, int frames);

static xtc_render_cb g_render = 0;
static volatile long g_calls = 0;
static volatile long g_hits = 0;
static volatile int g_stop = 0;
static HANDLE g_thread = 0;

static DWORD WINAPI xtc_worker(LPVOID p) {
  (void)p;
  while (!g_stop) {
    if (g_render) {
      unsigned char buf[64];
      int i;
      int ok = 1;
      for (i = 0; i < 64; i++) buf[i] = 0;
      g_render(buf, 16);                /* XIOM code runs on THIS thread */
      if (buf[0] != 171) ok = 0;
      if (buf[63] != 205) ok = 0;
      if (ok) InterlockedIncrement(&g_hits);
      InterlockedIncrement(&g_calls);
    }
    Sleep(1);
  }
  return 0;
}

int xtc_set(xtc_render_cb f) { g_render = f; return 0; }

int xtc_start(void) {
  g_stop = 0;
  g_calls = 0;
  g_hits = 0;
  g_thread = CreateThread(0, 0, xtc_worker, 0, 0, 0);
  return g_thread ? 0 : -1;
}

int xtc_stop(void) {
  g_stop = 1;
  if (g_thread) {
    WaitForSingleObject(g_thread, 5000);
    CloseHandle(g_thread);
    g_thread = 0;
  }
  return 0;
}

int xtc_calls(void) { return (int)g_calls; }
int xtc_hits(void) { return (int)g_hits; }

/* Sit in C for approx n ms (the main thread is NOT executing XIOM code). */
int xtc_burn(int ms) { Sleep((DWORD)ms); return ms; }

/* Pure C control callee. */
int xtc_plus_one(int x) { return x + 1; }
#else
typedef void (*xtc_render_cb)(unsigned char* out, int frames);
int xtc_set(xtc_render_cb f) { (void)f; return -1; }
int xtc_start(void) { return -1; }
int xtc_stop(void) { return -1; }
int xtc_calls(void) { return 0; }
int xtc_hits(void) { return 0; }
int xtc_burn(int ms) { (void)ms; return 0; }
int xtc_plus_one(int x) { return x + 1; }
#endif
