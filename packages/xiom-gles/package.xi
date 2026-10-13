package xiom_gles {
  name: "xiom.gles";
  version: "0.1.0";
  description: "OpenGL ES 2.0/3.2 + EGL 1.5 bindings for XIOM via ANGLE (runtime libEGL.dll/libGLESv2.dll + eglGetProcAddress; generated GLES surface from the pinned Khronos registry + full EGL surface from the pinned EGL-Registry; probe/session with SKIP semantics)";
  categories: ["graphics"];
  keywords: ["gles", "egl", "angle", "gpu", "rendering", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
