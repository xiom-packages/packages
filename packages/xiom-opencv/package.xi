// XIOM -- Package Manifest
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_opencv {
  name: "xiom.opencv";
  version: "0.1.0";
  description: "OpenCV bindings for XIOM -- computer vision";
  authors: ["XIOM Team"];
  deps: { "xiom.std": "0.1.0" };
  modules: [
    "xiom.opencv.types",
    "xiom.opencv.io",
    "xiom.opencv.features",
    "xiom.opencv.filters",
  ];
}
