// XIOM -- Jolt Physics Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_jolt {
  name: "xiom.jolt";
  version: "0.7.0";
  description: "Jolt Physics rigid-body dynamics bindings for XIOM (vendored v5.6.0 core; probes + caller-usable world/body surface + external force/torque input + world queries (raycast/sweep/overlap) + capsule shape + contacts/sensors + typed joints (fixed/hinge/slider/point with motors/limits) + convex/compound bodies + soft bodies (cloth/rope/volume presets with particle read-back) + heightfield terrain)";
  categories: ["graphics"];
  keywords: ["jolt", "physics", "collision", "rigid-body", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.jolt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
