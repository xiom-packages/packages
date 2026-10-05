# Crypto linkability repro (stdlib `xiom.crypto` / `xiom.crypto.hash`)

Packages lane -> stdlib lane, 2026-10-02. Requested by the wishlist row
"SHA-256/HMAC linkability: source ships but does not link from a
package". This is the exact repro packet the fix can be validated with.

## Environment

- Windows x64, PowerShell 5.1.
- Compiler `v0.62.2` (installed copy in `%LOCALAPPDATA%\xiom.new\bin`).
- Stdlib checkout `E:\xiom-lang\stdlib` (`stdlib-perf1`).
- Harness: `scripts/port.ps1 -Package <pkg> -TimeoutSec 60` (in the
  packages repo). It compiles and **links** a real program (`a.exe`).
  `--emit-ir` alone type-checks fine -- only the link step fails.

## Call shapes that trigger it

Facade (`use xiom.crypto;`):

```xiom
var data = Vec[UInt8].new();
data.push(97); data.push(98); data.push(99);   // "abc"
let hexed: Str = crypto.sha256_hex(&data);
```

Module (`use xiom.crypto.hash;`):

```xiom
let digest: Vec[UInt8] = hash.crypto_hash_sha256(&data);
```

Observed at link time (both shapes, on v0.62.2):

```
lld-link: undefined symbol: xiom_sha256_hash
```

First reported by the `xiom.aws` lane while implementing SigV4; `xiom.saml`
had already hand-rolled SHA-256 per an earlier brief. The failure is
recorded in `docs/COMPILER-FINDINGS.md` (Open findings, 2026-10-02) and
`docs/STDLIB-WISHLIST.md`.

## Public API surface (copied from the checkout)

- `xiom/crypto/crypto.xi`: `sha256(&Vec[UInt8]) -> Vec[UInt8]` (L306),
  `sha256_hex(&Vec[UInt8]) -> Str` (L331),
  `hmac_sha256(k: &Vec[UInt8], d: &Vec[UInt8]) -> Vec[UInt8]` (L1113).
- `xiom/crypto/hash.xi`: `crypto_hash_sha256(&Vec[UInt8]) -> Vec[UInt8]`
  (L697), `crypto_hash_sha256_hex` (L731),
  `crypto_hash_hmac_sha256(k, d) -> Vec[UInt8]` (L744).
- Also untested **from a package** (please verify while fixing):
  `xiom/encoding/base64.xi` (`base64_encode` L98, `base64_decode` L133,
  `base64url_*` L296/L345) and `xiom/encoding/encoding.xi` re-exports
  (L140/L175). `xiom.i2p` hand-rolled base64 defensively because package
  linkage was unverified.

## Probe files

- `crypto_link_probe.xi` -- facade shape.
- `crypto_hash_link_probe.xi` -- module shape.

Compile them with linking (a package/test run or a direct compile).
Adjust only if the public signatures differ in the checkout.

## Validation vectors already pinned by the packages lanes

A fix is done when these pass from a package context (we will re-run them
before retiring the hand-rolled copies):

- SHA-256: NIST vectors -- `"abc"`, empty input, 448-bit message.
- HMAC-SHA256: RFC 4231 test cases 1, 2, 3, 6.
- AWS SigV4 end-to-end: IAM ListUsers signature
  `5d672d79...2b5d7`; aws-sig-v4-test-suite `get-vanilla`
  `5fa00fa3...fbf31`; canonical-request hash and derived signing key
  vectors.
- base64: RFC 4648 KATs (standard + url-safe, padded/unpadded).

## Retirement plan

`docs/MAINTENANCE.md` workaround registry:
"Hand-rolled SHA-256/HMAC -- `aws`, `saml`". Once the symbols link and
the vectors pass, the packages lane retires the in-package copies in a
Tier-2 maintenance wave (probe RED -> GREEN + port x2 green + record).

## Update 2026-10-05 -- v0.63.1: fixed by the runtime-link change

This is the same class as `docs/repro/runtime-link/`: the AOT link never
scans `<install>\lib\runtime`, so `sha256_sw.c` (the provider of
`xiom_sha256_hash`) was not linked. With the supported override

```powershell
$env:XIOM_RUNTIME_DIR = "E:\xiom-lang\stdlib\runtime"
```

both probes link and run correctly on the installed **v0.63.1**:

| Probe | no override | `XIOM_RUNTIME_DIR` set |
|---|---|---|
| `crypto_link_probe.xi` (facade) | FAIL, `undefined symbol: xiom_sha256_hash` | exit 0, prints `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` (SHA-256 "abc" NIST KAT) |
| `crypto_hash_link_probe.xi` (module) | FAIL, same symbol | exit 0, prints `linked` (digest length 32) |

Compiler lane (relayed 2026-10-05): the runtime-discovery fix in the next
archive compiles `sha256_sw.c`; its `sha256_sw.h` is verified present in
the install. Re-test on the next archive; once green **without** the
override, run the Tier-2 retirement of the hand-rolled `aws`/`saml`
copies per the plan above.
