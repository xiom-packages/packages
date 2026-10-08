# win32-gl-unsafe -- B-09 repro (xiom-packages bindings lane)

The pre-fix `xiom.opengl` probe created a Win32 window + WGL context inside a
single ~140-line confined `unsafe` block (12-argument fn-pointer casts,
`Vec[UInt8]` PIXELFORMATDESCRIPTOR via `as_mut_ptr`, nested early-return
cleanup paths). On compiler v0.64.0 that binary is poisoned: it exits
`-1073740791` (0xC0000409) with **no output at all** -- the crash happens
before the first `io.println`, so it is a build/codegen property, not a
runtime path. Deterministic across rebuilds (3/3 checked).

Isolated sub-parts are green, which bounds the trigger:

- `probe_q1.xi` (control): window + GetDC + ReleaseDC + DestroyWindow in one
  unsafe function with the same 12-argument cast -> runs, exit 0.
- `probe_q2.xi` (repro): adds ChoosePixelFormat/SetPixelFormat,
  wglCreateContext/wglMakeCurrent/wglDeleteContext and the string query ->
  crashes before output on every rebuild.

## Run

```
cd pkg
xiom --run tests\probe_q1.xi     # control: green (q1-start | roundtrip_rc=0)
xiom --run tests\probe_q2.xi     # repro:   exit 0xC0000409, no output
```

Both probes use only the stdlib (`xiom.ffi.dl`, `xiom.io`) and the Win32
libraries loaded at runtime; no package under test is involved.

## Workaround used by the package

`xiom.opengl` moved the whole staged probe into the vendored C bridge
`packages/xiom-opengl/src/gl_probe.c` (compiled with `--c-source` via
`port.args.json`); the XIOM module is a thin safe wrapper over ten
one-line `extern "C"` functions. The suite is green in both the full-context
and SKIP-classification paths (see `SPEC.md` §4).

Reported as **B-09** in `docs/BINDINGS-COMPILER-FINDINGS.md`.
