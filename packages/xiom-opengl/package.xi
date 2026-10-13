package xiom_opengl {
  name: "xiom.opengl";
  version: "0.5.0";
  description: "OpenGL + WGL bindings for XIOM (runtime opengl32.dll + wglGetProcAddress; generated core-profile 4.6 surface: 656 commands + 1358 enums, plus the full WGL surface: 146 commands + 298 enums from the pinned Khronos registry; live-session resolver, session handles, probes with SKIP semantics)";
  categories: ["graphics"];
  keywords: ["opengl", "gpu", "rendering", "cross-platform", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
