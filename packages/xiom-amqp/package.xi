// XIOM -- xiom.amqp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module itself imports nothing; the tests use
// xiom.test, xiom.io, xiom.string and xiom.encoding.hex from it.

package xiom_amqp {
  name: "xiom.amqp";
  version: "0.1.0";
  description: "Pure-XIOM AMQP 0-9-1 frame codec: protocol header, method, content header, body and heartbeat frames";
  categories: ["protocol"];
  keywords: ["amqp", "rabbitmq", "messaging", "protocol", "codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.amqp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
