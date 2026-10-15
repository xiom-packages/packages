# xiom.glfw -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot C-bridge wrapper set (preserved in git history only; could not satisfy SKIP-when-absent)

## Phase 2 (Done) -- dynamic loader
- [x] 0.2.0 loader + smoke surface (init/terminate, version, timer, error accessor)
- [x] **0.3.0 engine surface**: hints, window lifecycle + attributes, events,
      input polling, monitors + video modes, clipboard, time, GL-context
      basics, Win32 native accessors, Vulkan helpers (28/28 x2)

## Phase 3 (Done) -- full surface
- [x] 0.4.0: cursors, joystick/gamepad, gamma ramps, window icons
- [x] 0.5.0: event-callback setters (20) + `glfwInitAllocator` -- 124/124
      exports; fixed-dispatcher + fn-registry ABI (probe:
      `docs/repro/bindings-pilot/cb-abi/`)
- [x] 0.6.0: callback DISPATCHER LIFT -- direct handoff (B-22 fixed m277;
      probe9; suite live 37/37 with 20/20 setters + key/close/error round
      trips); handlers now env-free (top-level fns)

## Phase 4 (Planned)
- [ ] POSIX soname (`libglfw.so.3`) resolution path
- [ ] File-based test fixtures for the absent-DLL CI shape
- [ ] Per-window callback routing helper (user pointer -> handler map)
