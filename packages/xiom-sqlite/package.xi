package xiom_sqlite {
  name: "xiom.sqlite";
  version: "0.4.1";
  description: "SQLite bindings for XIOM (vendored amalgamation 3.53.4) + SQL driver facade";
  categories: ["database"];
  keywords: ["sqlite", "database", "embedded", "sql", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.sqlite", "xiom.sqlite.driver", "xiom.sqlite.ffi", "xiom.sqlite.migration", "xiom.sqlite.query", "xiom.sqlite.rows", "xiom.sqlite.schema", "xiom.sqlite.types"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
