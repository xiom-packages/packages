# xiom.nis

NVIDIA Image Scaling (NIS) SDK v1.0.3 bindings for XIOM.

The upstream SDK core (MIT) is vendored byte-exact (`vendor/NIS/`) and this
package binds **100% of its CPU-visible surface**: the `NISConfig` builder
for both algorithms (`NVScaler` = upscale+sharpen, `NVSharpen` =
sharpen-only), the `NISOptimizer` dispatch geometry and the four filter
coefficient tables (f32/fp16). All buffers crossing the boundary are
XIOM-owned; the pixel pipeline itself is the upstream compute shader pair,
reported as a typed SKIP (`nis_gpu_path()`).

## Usage

```xiom
use xiom.nis;

// Build the shader constant buffer for a 1920x1080 -> 2560x1440 upscale.
var cfg = nis_config_new();
let p = NisScalerParams{
  sharpness: 0.5;
  input_viewport_origin_x: 0; input_viewport_origin_y: 0;
  input_viewport_width: 0; input_viewport_height: 0;   // 0 = texture size
  input_texture_width: 1920; input_texture_height: 1080;
  output_viewport_origin_x: 0; output_viewport_origin_y: 0;
  output_viewport_width: 0; output_viewport_height: 0; // 0 = texture size
  output_texture_width: 2560; output_texture_height: 1440;
  hdr_mode: NIS_HDR_MODE_NONE;
};
if nis_scaler_update_config(&mut cfg, &p) {
  // upload cfg (nis_config_size() bytes) as the NVScaler constant buffer,
  // bind nis_copy_coefficients(NIS_COEF_SCALE_F32 / NIS_COEF_USM_F32)
  // (or the fp16 tables) and dispatch NVScaler with the geometry from
  // nis_optimal_block_width/height/thread_group_size.
}
```

Sharpen-only: `NisSharpenParams` + `nis_sharpen_update_config` (output
viewport = input viewport, scale 1.0). Reads for tests/debugging:
`nis_config_field_f32` / `nis_config_field_u32` with the `NIS_FIELD_*`
indices.

## GPU path

The NIS SDK ships no CPU pixel implementation: `NVScaler`/`NVSharpen` are
compute shaders (`vendor/NIS/NIS_Scaler.h`, MIT) dispatched by the consumer's
renderer. `nis_gpu_path()` returns the typed descriptor
(`NIS_GPU_PATH_SHADER_ONLY`, `cpu_pixel_path = false`).

## Verify

```
.\scripts\port.ps1 -Package xiom.nis
```

See `SPEC.md` (pin, surface inventory, SKIP model), `PROVENANCE.md`
(upstream-first record) and `AUDIT.md` (run evidence).
