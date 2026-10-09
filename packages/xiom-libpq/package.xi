package xiom_libpq {
  name: "xiom.libpq";
  version: "0.2.0";
  description: "PostgreSQL client library bindings for XIOM via dynamic loader (libpq.dll at runtime, SKIP when absent)";
  categories: ["database"];
  keywords: ["libpq", "postgresql", "client", "sql", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
