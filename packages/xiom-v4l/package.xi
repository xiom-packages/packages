package xiom_v4l {
  name: "xiom.v4l";
  version: "0.1.0";
  description: "Video4Linux2 (V4L2) camera capture bindings -- full UAPI constant surface from the pinned kernel include/uapi/linux/videodev2.h include chain (2079 constants: all VIDIOC_* ioctl numbers, V4L2_CAP_*/V4L2_PIX_FMT_* FOURCCs, enums, plus the 1238-entry v4l2-controls.h CID universe), 122 struct layouts as size/offset facts (1028 facts, LP64) and the 29 function-like UAPI macros mirrored as XIOM functions; functional capture head via a self-contained ioctl bridge: probe/QUERYCAP device enumeration, G_FMT/S_FMT negotiation, REQBUFS/QUERYBUF/mmap/QBUF/DQBUF streaming, STREAMON/OFF, typed errors; Linux-only device layer (Windows suite takes the recorded SKIP path); Raspberry Pi arm64 leg documented";
  categories: ["platform"];
  keywords: ["v4l2", "videodev2", "video4linux", "camera", "capture", "ioctl", "uapi", "linux", "raspberry-pi", "pi-camera", "mmap", "streaming", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.v4l", "xiom.v4l.consts", "xiom.v4l.cids", "xiom.v4l.layout"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
