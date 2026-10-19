// XIOM -- xiom.uf2 package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// UF2 firmware-image format and BOOTSEL flashing bindings, host side and
// pure XIOM: build/parse/validate 512-byte UF2 blocks and complete images,
// the upstream family-ID table (RP2040/RP2350, SAMD21/SAMD51), byte-exact
// build/parse roundtrip, and flash-to-mounted-volume with read-back
// verification plus unmount completion detection.  Typed errors; an absent
// mount/volume is a deterministic SKIP result.  No upstream code is
// vendored: microsoft/uf2 is reference-only (see PROVENANCE.md / SPEC.md).

package xiom_uf2 {
  name: "xiom.uf2";
  version: "0.1.0";
  description: "UF2 firmware-image format (512-byte blocks: magics, flags, target address, payload, block numbering, family ID) with validation and build/parse roundtrip, plus BOOTSEL flash-to-mount (binary copy, read-back verification, unmount completion detection, typed errors, SKIP-safe absent volume)";
  categories: ["systems"];
  keywords: ["uf2", "firmware", "flash", "bootsel", "mcu", "rp2040", "rp2350", "samd21", "samd51", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.uf2"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
