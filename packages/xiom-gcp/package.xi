// XIOM -- xiom.gcp package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. Every module below is pure XIOM (strings and
// bounded scanners only): no network, no FFI, no clocks, no crypto. JWT
// signing is deliberately out of scope (the v0.62.2 stdlib crypto does not
// link from a package).

package xiom_gcp {
  name: "xiom.gcp";
  version: "0.1.0";
  description: "Pure-XIOM Google Cloud provider model: resource names, GCS, GCE, Cloud Functions, BigQuery, Pub/Sub and service-account auth shapes; no network";
  categories: ["systems"];
  keywords: ["gcp", "google-cloud", "provider", "cloud", "model"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: [
    "xiom.gcp",
    "xiom.gcp.core",
    "xiom.gcp.storage",
    "xiom.gcp.compute",
    "xiom.gcp.cloudfunctions",
    "xiom.gcp.bigquery",
    "xiom.gcp.pubsub",
    "xiom.gcp.auth",
  ];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
