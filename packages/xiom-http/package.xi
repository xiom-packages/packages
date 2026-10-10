package xiom_http {
  name: "xiom.http";
  version: "0.1.5";
  description: "XIOM HTTP Library -- types, parsing, client, and server";
  categories: ["web", "network"];
  keywords: ["http", "client", "server", "parsing", "rest"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.http", "xiom.http.client", "xiom.http.cookie", "xiom.http.demo", "xiom.http.mime", "xiom.http.parser", "xiom.http.server", "xiom.http.status", "xiom.http.types", "xiom.http.url"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
