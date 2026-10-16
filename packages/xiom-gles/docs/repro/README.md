# xiom.gles -- on-device evidence (android leg, A9)

## Android leg probe (0.2.0)

`gles_android_probe.c` drives the **same bridge the XIOM module loads**
(`../src/gles_probe.c`, compiled together with it) on the API-36
x86_64 emulator (`emulator-5554`; AVD `Medium_Phone_API_36.0`,
`-gpu swiftshader_indirect`), cross-built with the NDK r27b clang
(`--target=x86_64-linux-android26`).  Recorded transcript:
`recorded-gles-android.txt`.

| Evidence | Result |
|---|---|
| loader (system soname candidates) | `xgs_load` rc=0; **loaded pair `libEGL.so+libGLESv2.so`** (Windows ANGLE names probed first and skipped on-device; `libGLESv3.so`/`libGLESv1_CM.so` are the ranked fallbacks) |
| EGL display resolve | `xgs_session_display` != 0 (EGLDisplay live); `EGL_VERSION = 1.4 Android META-EGL`, `EGL_VENDOR = Android` |
| GL strings | `GL_RENDERER = Android Emulator OpenGL ES Translator (Google SwiftShader)`, `GL_VERSION = OpenGL ES 3.0 (OpenGL ES 3.0 SwiftShader 4.0.0.1)`, `GLSL = OpenGL ES GLSL ES 3.00` |
| one real GLES2 context | `xgs_session_open(2)` rc=0, `session.active=1` on the ES2 client version; `glGetString(GL_VERSION)` through the per-call resolver; `glClearColor` + `glClear` -> **`glGetError == 0`** |
| `eglQueryString(EGL_EXTENSIONS)` | **16** extensions reported: `EGL_ANDROID_front_buffer_auto_refresh`, `EGL_ANDROID_get_native_client_buffer`, `EGL_ANDROID_presentation_time`, `EGL_ANDROID_get_frame_timestamps`, `EGL_ANDROID_image_native_buffer`, `EGL_ANDROID_native_fence_sync`, `EGL_ANDROID_recordable`, `EGL_EXT_surface_CTA861_3_metadata`, `EGL_EXT_surface_SMPTE2086_metadata`, `EGL_KHR_get_all_proc_addresses`, `EGL_KHR_swap_buffers_with_damage`, `EGL_KHR_create_context`, `EGL_KHR_fence_sync`, `EGL_KHR_gl_texture_2D_image`, `EGL_KHR_image`, `EGL_KHR_image_base` |
| `EGL_ANDROID_*` presence | **7/7** advertised `EGL_ANDROID_*` extensions present (checked set above); informational: `EGL_KHR_surfaceless_context` / `EGL_KHR_no_config_context` are **not** advertised by this emulator's EGL (printed as `absent`, not gated) |
| GLES extensions | `glGetString(GL_EXTENSIONS)` = 50 extension names through the per-call resolver |
| session teardown | `xgs_session_close` -> `active=0` |

Bundle checks (same driver, both arches):

| Target | Result |
|---|---|
| `x86_64-linux-android26` | build + **run on emulator** (above) |
| `aarch64-linux-android26` | build-only (no arm64 device): `ELF64`, `DYN (Shared object file)`, `Machine: AArch64` |

Notes (honest, not papered over):

- The probe drives the bridge's C API; the XIOM-side suite's live leg
  runs on the Windows ANGLE payload (no XIOM-on-Android codegen yet --
  gate G1 in `docs/ANDROID-SDK100.md`).  This repro is the interim
  on-device evidence, as scoped by the A9 row.
- `eglQueryString(EGL_EXTENSIONS)` returning only 16 extensions is a
  property of the emulator's SwiftShader EGL, not of the loader; the
  `EGL_ANDROID_*` subset is what the delta declares and the record shows
  it live.

## Run

```
powershell -File build-and-run-android.ps1              # cross-build both arches; run x86_64
powershell -File build-and-run-android.ps1 -SkipRun     # cross-build only
```

The emulator must be up (`emulator.exe -avd Medium_Phone_API_36.0
-no-window -no-audio -no-boot-anim -no-snapshot -gpu
swiftshader_indirect`, then wait for `sys.boot_completed=1`).
