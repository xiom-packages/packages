// XIOM -- xiom.aws package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library module imports xiom.crypto (SHA-256 /
// HMAC-SHA-256), xiom.encoding.hex and xiom.string; no FFI, no network.

package xiom_aws {
  name: "xiom.aws";
  version: "0.1.1";
  description: "Pure-XIOM AWS request model: SigV4 signing, credential resolution, service registry, retry/backoff and response classification; no network";
  categories: ["systems"];
  keywords: ["aws", "sigv4", "signing", "credentials", "cloud"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.aws", "xiom.aws.base"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
