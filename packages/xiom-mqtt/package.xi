// XIOM -- xiom.mqtt package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing; the tests use
// xiom.test, xiom.io, xiom.string, xiom.string.compare and xiom.encoding.hex
// from it.

package xiom_mqtt {
  name: "xiom.mqtt";
  version: "0.1.0";
  description: "Pure-XIOM MQTT 3.1.1 packet codec for CONNECT, PUBLISH, SUBSCRIBE and friends";
  categories: ["protocol"];
  keywords: ["mqtt", "iot", "pubsub", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.mqtt"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
