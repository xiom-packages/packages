// XIOM -- SDL3 Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.sdl3"
  version: "0.16.0"
  description: "SDL3 (Simple DirectMedia Layer 3) bindings for XIOM -- dynamic loader + window/renderer/texture/gamepad resources + SDL_Event decoding (128-byte owned buffer, typed accessors incl. mouse wheel + drag-drop payload decode) + event filter/watch callbacks + displays/video modes + keyboard state + filesystem basics + display blit + mouse state + window contract + audio/joystick enumeration + push audio streaming + capture streams + pointer capture/relative mouse + joystick open/axis/button reads (virtual-joystick instrumented) + full source-generated constant tables"
  categories: ["graphics", "media"]
  keywords: ["sdl3", "windowing", "input", "audio", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}
