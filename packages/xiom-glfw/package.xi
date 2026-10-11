package xiom_glfw {
  name: "xiom.glfw";
  version: "0.5.0";
  description: "GLFW bindings for XIOM via dynamic loader (glfw3.dll at runtime, SKIP when absent); full 124/124 surface: engine + gamma ramps, cursors, window icons, joystick/gamepad polling, 20 event-callback setters, glfwInitAllocator, Vulkan helpers";
  categories: ["graphics"];
  keywords: ["glfw", "windowing", "input", "monitors", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
