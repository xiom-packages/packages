// XIOM -- xiom.syslog package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_syslog {
  name: "xiom.syslog";
  version: "0.1.0";
  description: "RFC 5424 syslog codec: PRI, header fields, structured data and MSG round-trip";
  categories: ["systems"];
  keywords: ["syslog", "logging", "rfc5424", "protocol"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.syslog"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
