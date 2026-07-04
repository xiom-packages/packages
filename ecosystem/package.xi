// XIOM Ecosystem — Package Manifest
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

package xiom_ecosystem {
  name: "xiom-ecosystem";
  version: "0.1.0";
  description: "XIOM Ecosystem Libraries";
  authors: ["XIOM Team"];
  deps: {
    "xiom-std": "0.1.0"
  };
  packages: [
    "xiom-http",
    "xiom-crypto",
    "xiom-sql",
    "xiom-vulkan",
    "xiom-glfw",
    "xiom-libsodium",
    "xiom-openal",
    "xiom-stb",
    "xiom-postgres",
    "xiom-redis",
    "xiom-bullet",
    "xiom-blas",
    "xiom-protobuf",
    "xiom-grpc"
  ];
}
