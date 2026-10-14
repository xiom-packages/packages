# xiom.opus

libopus **v1.6.1** bindings for XIOM -- the Opus codec (RFC 6716) for
streaming audio: encode, decode, packet-loss concealment, repacketization,
multistream, Opus Custom, ambisonics projection (entry points), and the
DRED entry points of the pinned upstream release.

* Vendored upstream C (BSD-3-Clause) compiled at port time; no system
  libopus needed.
* 105/105 declared public functions bound, 0 skips
  (`docs/COVERAGE.md`).
* FFI discipline: handles cross as `Int`, PCM crosses as owned
  `Vec[UInt8]` byte buffers, all `unsafe` confined to `xiom.opus.ffi`.
* Suite: 26 conformance checks (encode/decode round-trips with SNR,
  repacketizer, multistream, custom modes, projection, error paths).

```xiom
use xiom.opus;
use xiom.opus.abi;   // OPUS_APPLICATION_*, OPUS_*_REQUEST, error codes

// encode 48 kHz mono, 20 ms frames
let encr = Encoder.create(48000, 1, abi.OPUS_APPLICATION_AUDIO);
if !encr.is_ok { return encr.error.code; }
let enc = encr.value;
Encoder.set_bitrate(&enc, 64000);

var pcm: Vec[UInt8] = /* 960 s16 samples, interleaved little-endian */;
var packet: Vec[UInt8] = /* 512-byte owned buffer */;
let nbytes = Encoder.encode(&enc, &pcm, 960, &mut packet);
if nbytes.is_ok {
  // use packet[0 .. nbytes.value]
}
Encoder.destroy(&enc);
```

Decode:

```xiom
let decr = Decoder.create(48000, 1);
let dec = decr.value;
var out: Vec[UInt8] = /* 960 * 2 bytes */;
let ns = Decoder.decode(&dec, &packet_slice, &mut out, 960);
// PLC for a lost packet:
let concealed = Decoder.decode_lost(&dec, &mut out, 960);
Decoder.destroy(&dec);
```

Full surface (multistream encoders/decoders, surround layout, Opus Custom,
ambisonics projection including the demixing-matrix round trip, DRED stub
behavior, packet parsing/padding, init-over-own-memory, ctl companions)
lives in `xiom.opus.ffi`. Constants and ctl request ids live in
`xiom.opus.abi`.
**Published**: `0.1.0` in `eco-v0.1.178` (sha256 `b2a7d3d7...`).

## Layout

| Path | Contents |
|------|----------|
| `src/opus.xi` | facade (`Encoder`/`Decoder`/`Repacketizer`) |
| `src/opus_ffi.xi` | safe wrappers; the only `unsafe` module (externs generated inline) |
| `src/opus_abi.xi` | generated constants + coverage ledger |
| `src/opus_types.xi` | `OpusError`, `PacketFrames`, `EncoderOutcome` |
| `src/opus_bridge.c` | C bridge (`xo_*`, one per public function) |
| `src/opus_abi_protos.h`, `src/opus_vendor_*.c` | generated (protos + unity build units) |
| `vendor/` | byte-identical upstream sources (flat tree), `COPYING`, `MANIFEST.sha256` |
| `tools/vendor_opus.py`, `tools/gen_opus.py` | vendoring + surface generation |
| `docs/COVERAGE.md`, `docs/gen_manifest.json` | generated coverage artifacts |

## Build

`./scripts/port.ps1 -Package xiom.opus -TimeoutSec 420` (toolchain
v0.64.4). First run compiles ~137 upstream C files (four unity units) and
the bridge; expect ~1 minute. See SPEC.md for the pinned build
configuration and re-pin procedure, AUDIT.md for the findings/discipline
mapping, PROVENANCE.md for the vendoring chain.

Upstream: <https://gitlab.xiph.org/xiph/opus> -- BSD-3-Clause. This
package: MIT OR Apache-2.0.
