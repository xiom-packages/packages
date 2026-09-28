// XIOM -- xiom.pulsar package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.convert from it; the tests additionally use
// xiom.test, xiom.io, xiom.string.compare and xiom.encoding.hex.

package xiom_pulsar {
  name: "xiom.pulsar";
  version: "0.1.1";
  description: "Pure-XIOM Apache Pulsar wire codec: protobuf-wire subset, u32/u32 frame framing and the decoded BaseCommand/MessageMetadata/MessageIdData subset (no network, no brokers)";
  categories: ["protocol"];
  keywords: ["pulsar", "protobuf", "messaging", "protocol", "codec"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.pulsar"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
