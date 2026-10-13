/* xiom.opus -- GENERATED unity build unit (tools/gen_opus.py).
 * Upstream libopus v1.6.1 sources are compiled byte-identically from
 * vendor/opus (flat tree); this unit only pins the upstream build
 * configuration (defines) and the per-directory source list.
 * Do not edit: regenerate with tools/gen_opus.py. */
#define OPUS_BUILD
#define PACKAGE_VERSION "1.6.1"
#define CUSTOM_MODES
#define ENABLE_HARDENING
#define VAR_ARRAYS
#define CELT_C
#define CELT_ENCODER_C
#define CELT_DECODER_C

#include "../vendor/opus/bands.c"
#include "../vendor/opus/celt.c"
#include "../vendor/opus/celt_encoder.c"
#include "../vendor/opus/celt_decoder.c"
#include "../vendor/opus/cwrs.c"
#include "../vendor/opus/entcode.c"
#include "../vendor/opus/entdec.c"
#include "../vendor/opus/entenc.c"
#include "../vendor/opus/kiss_fft.c"
#include "../vendor/opus/laplace.c"
#include "../vendor/opus/mathops.c"
#include "../vendor/opus/mdct.c"
#include "../vendor/opus/modes.c"
#include "../vendor/opus/pitch.c"
#include "../vendor/opus/celt_lpc.c"
#include "../vendor/opus/quant_bands.c"
#include "../vendor/opus/rate.c"
#include "../vendor/opus/vq.c"
