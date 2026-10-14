# ROADMAP: xiom.nis

## Phase 1 (0.1.0, current)

Vendored NIS v1.0.3 CPU-visible surface (11/11 declarations), owned-buffer
config interop, typed GPU-path SKIP. See `SPEC.md` section 4.

## Phase 2 candidates

- **Renderer-side dispatch helpers (consumer-driven):** a documented
  recipe/optional helpers for the DX12/VK constant-buffer upload +
  coefficient-texture creation (the samples' usage pattern; no sample code
  is vendored -- any helper is written fresh against the vendored headers).
- **NV12 support surface:** NIS_NV12_SUPPORT shader variant constants
  (define-level; the vendored header already carries them).
- **Viewport-extension coverage:** exercise NIS_VIEWPORT_SUPPORT config
  combinations beyond the viewport subset checks (config side only; pixel
  execution still GPU).
- **Re-pin watch:** v1.0.3 is the latest release; if NVIDIA ships a v1.0.4+,
  follow `SPEC.md` section 2 (re-pin procedure).

## Explicit non-goals

- CPU/scalar pixel path (does not exist upstream).
- Shader compilation or GPU execution in CI.
- Vendoring sample integration code (DX11/DX12/VK/Streamline).
