package xiom_openssl {
  name: "xiom.openssl";
  version: "0.2.0";
  description: "OpenSSL (libcrypto) bindings for XIOM via dynamic loader (multi-soname, SKIP when absent)";
  categories: ["crypto-security"];
  keywords: ["openssl", "tls", "cryptography", "certificates", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
