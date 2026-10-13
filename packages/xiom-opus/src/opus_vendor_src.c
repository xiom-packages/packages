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

#include "../vendor/opus/opus.c"
#include "../vendor/opus/opus_decoder.c"
#include "../vendor/opus/opus_encoder.c"
#include "../vendor/opus/extensions.c"
#include "../vendor/opus/opus_multistream.c"
#include "../vendor/opus/opus_multistream_encoder.c"
#include "../vendor/opus/opus_multistream_decoder.c"
#include "../vendor/opus/repacketizer.c"
#include "../vendor/opus/opus_projection_encoder.c"
#include "../vendor/opus/opus_projection_decoder.c"
#include "../vendor/opus/mapping_matrix.c"
#include "../vendor/opus/analysis.c"
#include "../vendor/opus/mlp.c"
#include "../vendor/opus/mlp_data.c"
