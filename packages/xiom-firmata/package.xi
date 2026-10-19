// XIOM -- xiom.firmata package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM host-side Firmata protocol bindings: MIDI-framed wire encode and
// decode plus a transport-agnostic session loop. No FFI, no vendored code,
// no hardware requirement. The optional xiom.serial wiring is documented in
// README.md but is not a dependency (the session takes injected bytes).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports only
// xiom.string.builder and xiom.utf8; the tests use xiom.io,
// xiom.string.compare and xiom.encoding.hex from it.

package xiom_firmata {
  name: "xiom.firmata";
  version: "0.1.0";
  description: "Pure-XIOM Firmata 2.x host bindings: version/firmware handshake, pin modes, digital and PWM writes, analog reporting, digital/analog/string decode with typed errors, and a transport-agnostic session loop with an injectable byte transport";
  categories: ["systems"];
  keywords: ["firmata", "arduino", "mcu", "protocol", "serial", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.firmata"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
