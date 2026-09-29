// XIOM -- xiom.logging package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

package xiom_logging {
  name: "xiom.logging";
  version: "0.1.2";
  description: "Syslog message structure codecs: RFC 3164 and RFC 5424 parser";
  categories: ["data"];
  keywords: ["syslog", "logging", "rfc3164", "rfc5424", "parser"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.logging"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
