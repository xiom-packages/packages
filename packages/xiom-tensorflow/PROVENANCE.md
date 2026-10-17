# PROVENANCE -- xiom.tensorflow

Upstream oracle, pinned revisions, digests, and license facts for everything
this package derives from or loads at runtime. Nothing in this package is
vendored: the loader reaches a system-installed libtensorflow by soname (see
SPEC "Delivery model"), so the digests below are recorded for auditability,
not because any byte of TensorFlow ships in this repository.

## Upstream source (headers / API oracle)

| Item | Value |
| --- | --- |
| Project | tensorflow/tensorflow (https://github.com/tensorflow/tensorflow) |
| License | Apache License 2.0 (root `LICENSE`, verified before any clone) |
| Pin | commit `9dd1241c2a15417ac0c9eb3940f67bd7639b4646` |
| Pin date | 2026-10-16 (upstream `master` at clone time) |
| Clone | light: `git clone --depth 1 --filter=blob:none --sparse`, then `git sparse-checkout set tensorflow/c` (only `tensorflow/c/**` materialized; no full fetch) |
| Local | `E:\repos\tensorflow` (workstation clone; not part of the repo) |
| Headers used | `tensorflow/c/c_api.h`, `tf_status.h`, `tf_datatype.h`, `tf_attrtype.h`, `tf_tensor.h`, `tf_buffer.h`, `tf_attrtype.h` |
| `c_api.h` sha256 (clone@pin) | `C6A83FD3AC45E9B73DB3C89E4E0B6DA7D6C4FC5E716DCA2F6D9E3D4B4FE6D3C8` |

The constant tables in `src/types.xi` (TF_Code including the
`UNAUTHENTICATED = 16` quirk, the TF_DataType id set 1..34 with gaps,
TF_AttrType, dtype sizes) are transcribed from the headers above and
live cross-checked against the runtime (see SPEC coverage table, evidence
column).

## Live runtime (official CPU distribution)

| Item | Value |
| --- | --- |
| Artifact | `libtensorflow-cpu-windows-x86_64-2.18.1.zip` |
| Source URL | `https://storage.googleapis.com/tensorflow/versions/2.18.1/libtensorflow-cpu-windows-x86_64.zip` |
| License | Apache 2.0 (`LICENSE` + `THIRD_PARTY_TF_C_LICENSES` ship inside the zip; verified) |
| Zip sha256 | `28ACDCEA6C6B34828CF0E95E67802B0F3577D51BC2E8915DE811B7AA0B04452D` |
| Zip size | 253,550,386 bytes |
| Extracted to | `E:\repos\tensorflow-bin` (workstation; not part of the repo) |
| `lib/tensorflow.dll` sha256 | `07687DEFC3F36EE93E372B692D37317B348369A80B3A36201A55D69D7D9EDBA8` |
| Distribution headers (include/tensorflow/c, sha256) | `c_api.h` `4CCD0A99A0832BFFAC33EEB2A26A900710D50C212549EF8E66BE3F906D5BDAC5`; `tf_status.h` `2F581CEFE989344F91598DDD15E3F1433E07748904AE66D3414F210FFC4F879C`; `tf_datatype.h` `2700C38D3355F3769DF238E47E5413AF193C31B62291FD27438612C73B992EF5`; `tf_attrtype.h` `01BF629A52B523C070864CE11D31D33AA33FC2EB559552FEB986FC90F512EF0E`; `tf_tensor.h` `A2B0E05A9F72BD87B03525C22BD334AC7F58626361F8C79857998E361620CFB5`; `tf_buffer.h` `007F280677FC16FE49A153B1E41C6CD9E347EA45A59A2F88B85946BBD9BD7D56` |

The live leg of the suite ran against exactly this distribution (see
STATUS.json `tests.note` and README "Evidence"). The release headers differ
from the pinned `master` headers (distribution `c_api.h` vs clone
`c_api.h` digests above); the declared surface only uses entry points that
exist in both.

## How the suite finds a runtime

Probe order (see `tf_load_candidates`):

1. `XIOM_TENSORFLOW_RUNTIME` (explicit path or soname; used by the live leg)
2. `tensorflow.dll`
3. `libtensorflow.so`
4. `libtensorflow.so.2`
5. `libtensorflow.dylib`

Fresh CI without any of these takes the deterministic typed-SKIP path and
stays green (17 pure tests, no runtime); the SKIP classification itself is
exercised every run with a bogus soname.

## Policy notes

- **License check first:** the Apache-2.0 root `LICENSE` was read before the
  clone; the binary distribution ships its own `LICENSE` +
  `THIRD_PARTY_TF_C_LICENSES` (verified after extraction).
- **No vendoring:** no TensorFlow header, source, or binary is copied into
  this repository. The package is a runtime loader, matching the established
  `xiom.ssl` / `xiom.onnx` delivery model for C-API runtimes.
- **Version floor:** TF 2.x C API (`TF_MIN_MAJOR = 2`); the declared surface
  is resolved by symbol name at load and a missing symbol downgrades the
  candidate to a typed ABI error (runner falls through to the next
  candidate / reports FAIL only when a runtime is reachable but unusable).
- Package license: MIT OR Apache-2.0 (see `package.xi`).
