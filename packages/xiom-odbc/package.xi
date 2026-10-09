package xiom_odbc {
  name: "xiom.odbc";
  version: "0.2.0";
  description: "ODBC driver-manager bindings for XIOM via dynamic loader (odbc32.dll at runtime, SKIP when absent)";
  categories: ["database"];
  keywords: ["odbc", "database", "sql", "windows", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
