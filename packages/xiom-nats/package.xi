// XIOM -- xiom.nats package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test, xiom.io and xiom.encoding.hex.

package xiom_nats {
  name: "xiom.nats";
  version: "0.1.1";
  description: "Pure-XIOM NATS 1.x text protocol codec: client CONNECT/PUB/HPUB/SUB/UNSUB/PING/PONG and server INFO/MSG/HMSG/+OK/-ERR ops with CRLF framing and byte-count payloads";
  categories: ["protocol"];
  keywords: ["nats", "pubsub", "messaging", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.nats"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
