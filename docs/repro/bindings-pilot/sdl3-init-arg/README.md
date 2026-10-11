# sdl3-init-arg -- B-19 repro (regression in fde5548e)

Through the dynamic-loader cast-call shape
(`let f = lib.p_init as fn(Int) -> UInt8; f(16385)`), `SDL_Init` returns
success on the fix build but **initializes nothing**: `SDL_WasInit(0)` --
the mask of all initialized subsystems -- reads `0` instead of `16384`
(SDL_INIT_EVENTS).  The same function's `SDL_Delay(100)` passes its
argument correctly (`elapsed=100`), so plain Int args to loader cast-calls
are not generally dropped.

## Run

SDL3.dll must be resolvable (dev box: the Vulkan SDK dir on PATH).
`use xiom.sdl3` needs package discovery, so run from the package:

```
copy probe.xi packages\xiom-sdl3\tests\probe_tmp.xi
cd packages\xiom-sdl3
$env:XIOM_STDLIB = 'E:\xiom-lang\stdlib'
& <toolchain>\xiom.exe --run tests\probe_tmp.xi
```

## Observed

| Toolchain | Output |
|-----------|--------|
| v0.64.3 (installed slot) | `elapsed=100 init=1 w_all=16384` |
| fde5548e (rebuilt release, m263-m265) | `elapsed=100 init=1 w_all=0` |

Suite-level effect (same builds):

| Suite | v0.64.3 | fde5548e |
|-------|---------|----------|
| xiom.sdl3 0.13.0 conformance | 52/52 | **51/52** -- `init: SDL_WasInit(TIMER|EVENTS) reflects the flags` FAILS |
| xiom.glfw 0.5.0 conformance | 37/37 | 37/37 (with `--link user32`; unaffected) |

The rest of the sdl3 suite still passes on fde5548e because SDL3 lazily
initializes most subsystems on first use -- only the explicit
WasInit reflects-the-flags contract breaks.

Found 2026-10-11 by the bindings lane while re-verifying
`REL-20261011-1533-compiler` (B-13/1904/B-14/B-15 verdicts; see the cb-abi
README re-verify section).  Filed as B-19.
