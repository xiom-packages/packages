# xiom.glfw -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot C-bridge wrapper set (preserved in git history only; could not satisfy SKIP-when-absent)

## Phase 2 (Done) -- dynamic loader
- [x] 0.2.0 loader + smoke surface (init/terminate, version, timer, error accessor)
- [x] **0.3.0 engine surface**: hints, window lifecycle + attributes, events,
      input polling, monitors + video modes, clipboard, time, GL-context
      basics, Win32 native accessors, Vulkan helpers (28/28 x2)

## Phase 3 (Planned)
- [ ] 0.4.0: cursors, joystick/gamepad, gamma ramps, window icons
- [ ] 0.4.0: event-callback setters (needs a proven XIOM-fn->C-callback ABI)
- [ ] POSIX soname (`libglfw.so.3`) resolution path
- [ ] File-based test fixtures for the absent-DLL CI shape
