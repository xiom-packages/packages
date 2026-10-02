// XIOM -- xiom.azure package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library modules import only xiom.string,
// xiom.string.builder and xiom.string.compare; no FFI, no network, no crypto.

package xiom_azure {
  name: "xiom.azure";
  version: "0.1.0";
  description: "Pure-XIOM Microsoft Azure resource model: ARM resource ids, blob storage with ETag preconditions, VM power states, Functions routes/triggers, Cosmos DB partition keys, Service Bus delivery states, Entra token envelope; no network";
  categories: ["systems"];
  keywords: ["azure", "arm", "blob", "vm", "functions", "cosmos", "servicebus", "cloud"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: [
    "xiom.azure",
    "xiom.azure.base",
    "xiom.azure.arm",
    "xiom.azure.storage",
    "xiom.azure.compute",
    "xiom.azure.functions",
    "xiom.azure.cosmos",
    "xiom.azure.servicebus",
    "xiom.azure.auth",
  ];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
