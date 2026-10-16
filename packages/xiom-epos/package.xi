// XIOM -- maxon EPOS (EPOS/EPOS2/EPOS4) Bindings Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package {
  name: "xiom.epos"
  version: "0.1.0"
  description: "maxon EPOS positioning-controller bindings for XIOM -- dynamic loader for the closed EPOS Command Library (EposCmd64.dll / EposCmd.dll / libEposCmd.so) with typed SKIP when the runtime is absent; 177/177 declared VCS_* entry points bound (communication, gateway/sub-device, configuration, state machine, error handling, motion info, profile position/velocity, homing, interpolated position, position/velocity/current, master encoder, step/direction, inputs/outputs, position compare/marker, CAN layer) + 2 declared Linux-layer helpers; typed flat outcomes with rc + error code; nothing vendored from the closed SDK"
  categories: ["systems"]
  keywords: ["epos", "maxon", "motion-control", "positioning-controller", "actuator", "canopen", "robotics", "binding"]
  license: "MIT OR Apache-2.0"
  repository: "https://github.com/xiom-packages/packages"
  authors: ["XIOM Team"]
  modules: ["xiom.epos", "xiom.epos.system", "xiom.epos.config", "xiom.epos.operate", "xiom.epos.motion", "xiom.epos.io"]
  deps: {
    "xiom.std": ">=0.60.0 <1.0.0"
  }
}


