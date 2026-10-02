// XIOM -- xiom.deep package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// xiom.std is the standard library: a platform dependency, excluded from the
// registry install closure (is_platform_dep). Tests use xiom.test/xiom.io;
// the library module itself imports only xiom.string and xiom.convert.

package xiom_deep {
  name: "xiom.deep";
  version: "0.1.0";
  description: "Deep network assembly helpers: residual, convolutional, attention, recurrent blocks over fixed-point integers";
  categories: ["ai-ml"];
  keywords: ["deep-learning", "neural-network", "resnet", "convnet", "transformer", "lstm", "gru", "fixed-point"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.deep"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
