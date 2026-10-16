package xiom_gles {
  name: "xiom.gles";
  version: "0.2.0";
  description: "OpenGL ES 2.0/3.2 + EGL 1.5 bindings for XIOM via a runtime-loaded implementation -- the Windows ANGLE pair (libEGL.dll/libGLESv2.dll) or the Android system libraries (libEGL.so + libGLESv2.so/libGLESv3.so/libGLESv1_CM.so); generated GLES core + NDK r27b android-delta surface (494 extension commands + 1225 constants) + full EGL surface (incl. every EGL_ANDROID_* entry point); probe/session with SKIP semantics";
  categories: ["graphics"];
  keywords: ["gles", "egl", "angle", "android", "gpu", "rendering", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
