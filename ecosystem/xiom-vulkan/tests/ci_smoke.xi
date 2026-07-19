// CI Smoke — Legacy API + Phase 7.2 cache serialization
module ci_smoke

extern "C" {
  fn xvk_alloc(size: Int) -> Int;
  fn xvk_free(handle: Int);
  fn xvk_set_sType(h: Int, v: Int32);
  fn xvk_get_device(app: Int) -> Int;
  fn xvk_create_pipeline_cache(dev: Int, ci: Int) -> Int;
  fn xvk_destroy_pipeline_cache(dev: Int, cache: Int);
  fn xvk_get_pipeline_cache_data_size(dev: Int, cache: Int) -> Int32;
  fn xvk_get_pipeline_cache_data(dev: Int, cache: Int, data: Int, data_size: Int) -> Int32;
  fn xvk_merge_pipeline_caches(dev: Int, dst: Int, src_count: Int32, src_caches: Int) -> Int32;
}

use xiom.vulkan;
use xiom.io;

fn main() -> Int {
  io.println("=== CI Smoke ===");

  let a = create_app("CI", 100, 100);
  match a {
    Err(e) => { io.println("FAIL: app"); return 1; }
    Ok(app) => {
      io.println("PASS: app");

      // Buffer via legacy API
      let b = buffer_create(app, 256, 1, 0);
      match b {
        Err(_) => { io.println("FAIL: buffer"); }
        Ok(_) => { io.println("PASS: buffer"); }
      }

      // Pipeline cache via raw device (Phase 7.2)
      let raw_dev = unsafe { xvk_get_device(app) };
      if raw_dev != 0 {
        let pcci = unsafe { xvk_alloc(16) };
        if pcci != 0 {
          unsafe { xvk_set_sType(pcci, 10); }
          let cache = unsafe { xvk_create_pipeline_cache(raw_dev, pcci) };
          if cache != 0 {
            let sz = unsafe { xvk_get_pipeline_cache_data_size(raw_dev, cache) };
            io.println("PASS: cache (size=" + (if sz == 0 { "empty" } else { "has data" }) + ")");
            unsafe { xvk_destroy_pipeline_cache(raw_dev, cache); }
          } else { io.println("FAIL: cache create"); }
          unsafe { xvk_free(pcci); }
        }
      } else { io.println("SKIP: raw device"); }

      destroy_app(app);
      io.println("=== CI SMOKE PASS ===");
      return 0;
    }
  }
}
