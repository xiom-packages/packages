package xiom_portaudio {
  name: "xiom.portaudio";
  version: "0.2.0";
  description: "PortAudio bindings for XIOM via dynamic loader (portaudio_x64.dll at runtime, SKIP when absent)";
  categories: ["media"];
  keywords: ["portaudio", "audio", "io", "streams", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
