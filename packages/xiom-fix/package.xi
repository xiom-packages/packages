// XIOM -- xiom.fix package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// FIX tag=value message codec: SOH framing, flat tag/value spans, BodyLength
// and CheckSum validation, canonical emit. xiom.std is the standard library:
// a platform dependency, excluded from the registry install closure. The
// module itself imports xiom.string, xiom.string.builder and
// xiom.string.compare from it; the tests additionally use xiom.test,
// xiom.io and xiom.convert.

package xiom_fix {
  name: "xiom.fix";
  version: "0.1.0";
  description: "FIX tag=value message codec: SOH framing, BodyLength and CheckSum validation, canonical emit";
  categories: ["finance"];
  keywords: ["fix", "finance", "protocol", "trading"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.fix"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
