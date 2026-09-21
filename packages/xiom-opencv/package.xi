// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_opencv {
  name: "xiom.opencv";
  version: "0.1.0";
  description: "OpenCV bindings for XIOM -- computer vision";
  categories: ["ai-ml", "media"];
  keywords: ["opencv", "vision", "images", "video"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": "0.1.0" };
  modules: [
    "xiom.opencv.types",
    "xiom.opencv.io",
    "xiom.opencv.features",
    "xiom.opencv.filters",
  ];
}
