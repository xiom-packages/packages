// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.serverless package manifest
// Serverless compute abstractions as a pure deterministic model (no
// networking): functions, triggers, deploys, invocations, runtimes.
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The modules import xiom.convert; the tests
// additionally use xiom.test, xiom.io and xiom.string.compare.

package xiom_serverless {
  name: "xiom.serverless";
  version: "0.1.0";
  description: "Serverless compute abstractions as a deterministic model: functions, triggers, deploys, runtimes, sync/async invoke, cold-start accounting";
  categories: ["systems"];
  keywords: ["serverless", "faas", "functions", "triggers", "deploy", "invoke", "cold-start"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.serverless", "xiom.serverless.deploy", "xiom.serverless.invoke", "xiom.serverless.check"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
