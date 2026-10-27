// XIOM -- xiom.otel package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// OpenTelemetry trace model, OTLP/JSON encoder and sink seam, pure XIOM: no
// FFI, no bridge C, no upstream OpenTelemetry code. Phase 1 of the PULSE
// tracing-export decided direction: the core model + the OTLP/JSON encoder +
// a sink/transport seam; HTTP transport stays caller-supplied. 0.2.0 adds a
// minimal deterministic OTLP/JSON gauge-metrics surface (model + encoder).
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure. The library modules import xiom.string,
// xiom.string.compare, xiom.string.builder and xiom.convert; the tests
// additionally use xiom.test and xiom.io.

package xiom_otel {
  name: "xiom.otel";
  version: "0.2.0";
  description: "OpenTelemetry trace model + deterministic OTLP/JSON encoder and sink seam, plus gauge metrics, pure XIOM (no FFI; transport stays caller-supplied)";
  categories: ["tooling", "data"];
  keywords: ["opentelemetry", "otlp", "tracing", "spans", "metrics", "gauges", "observability", "exporter", "json"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.otel", "xiom.otel.otlp", "xiom.otel.sink"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
