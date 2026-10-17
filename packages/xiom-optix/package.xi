// XIOM -- NVIDIA OptiX package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Reference-only, dynamic-loader package: no NVIDIA OptiX code, headers,
// samples, import libraries or binaries are vendored.  The full SDK download
// is registration-gated (see PROVENANCE.md); the runtime nvoptix.dll is the
// user's display-driver component, loaded at run time.  xiom.std is the
// standard library: a platform dependency, excluded from the registry
// install closure.

package xiom_optix {
  name: "xiom.optix";
  version: "0.1.0";
  description: "NVIDIA OptiX ray-tracing engine bindings for XIOM (reference-only dynamic loader, ABI 118; nothing vendored): device context create/destroy/validate + options, PTX module load, raygen/miss/hitgroup program groups, SBT build, pipeline create/link, launch-params buffer, launch; typed errors; SKIP-safe when the user's nvoptix.dll is absent";
  categories: ["graphics", "science"];
  keywords: ["optix", "ray-tracing", "nvidia", "rtx", "gpu", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.optix"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}

