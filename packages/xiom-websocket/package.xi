package xiom_websocket {
  name: "xiom.websocket";
  version: "0.1.0";
  description: "WebSocket transport -- handshake, framing, connection lifecycle, heartbeat, backpressure, reconnect, pub/sub, built on xiom.http and xiom.net";
  categories: ["web", "network"];
  keywords: ["websocket", "framing", "pub-sub", "handshake"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": "0.1.0", "xiom.http": "0.1.0" };
}
