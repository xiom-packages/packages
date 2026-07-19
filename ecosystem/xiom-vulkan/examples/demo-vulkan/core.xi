// demo-vulkan core — shared global state

module demo_vulkan.core

use xiom.io;

pub var g_app: Int = 0;
pub var g_frame: Int = 0;
pub var g_fps: Int = 0;
pub var g_exit: Int = 0;

pub fn log(msg: Str) { io.println(msg); }
