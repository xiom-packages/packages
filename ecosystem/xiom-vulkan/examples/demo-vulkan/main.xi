// XIOM Vulkan Showcase — Main Entry Point
// Game-style GUI demo. 4K responsive. Modular.
//
// Build: xiomc -o demo-vulkan.exe main.xi theme.xi core.xi
//   widgets/button.xi widgets/label.xi widgets/panel.xi widgets/slider.xi
//   panels/topbar.xi panels/viewport.xi panels/sidebar_left.xi
//   panels/sidebar_right.xi panels/statusbar.xi
//   ../../vulkan.xi ../../src/wrapper.xi
//   --c-source ../../bridge/xvk_bridge.obj --link vulkan-1 --link glfw3 ...

module demo_vulkan.main

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.topbar;
use demo_vulkan.viewport;
use demo_vulkan.sidebar_left;
use demo_vulkan.sidebar_right;
use demo_vulkan.statusbar;

fn main() -> Int {
  let app = create_app("XIOM Vulkan Showcase — Production Demo", 1280, 720);
  match app {
    Err(e) => { core.log(e); return 1; }
    Ok(a) => {
      core.g_app = a;
      core.g_fps = 60;
      core.g_exit = 0;
      core.g_frame = 0;

      viewport.init();
      sidebar_right.init();

      core.log("== XIOM Vulkan Showcase ==");
      core.log("Top bar: menu | Left: scene browser | Right: controls | Center: viewport");
      core.log("Click red Exit or press Escape to close.");

      var fc = 0;
      while !should_close(a) && core.g_exit == 0 {
        poll(a);
        fc = fc + 1;
        core.g_frame = core.g_frame + 1;

        let status = begin_frame(a);
        if status == 1 {
          set_clear_color(a, TK_BG_VOID_R(), TK_BG_VOID_G(), TK_BG_VOID_B());

          // Draw all panels in order
          topbar.draw();
          sidebar_left.draw();
          sidebar_right.draw();
          viewport.draw();
          statusbar.draw();

          end_frame(a);
          if is_key_down(a, 256) { core.log("[Showcase] Escape pressed."); break; }
        } elif status == -1 {
          core.log("ERROR: " + last_error());
          break;
        }
      }

      core.log("[Showcase] Shutting down.");
      destroy_app(a);
      return 0;
    }
  }
}
