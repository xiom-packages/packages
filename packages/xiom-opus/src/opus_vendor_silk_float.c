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

#include "../vendor/opus/apply_sine_window_FLP.c"
#include "../vendor/opus/corrMatrix_FLP.c"
#include "../vendor/opus/encode_frame_FLP.c"
#include "../vendor/opus/find_LPC_FLP.c"
#include "../vendor/opus/find_LTP_FLP.c"
#include "../vendor/opus/find_pitch_lags_FLP.c"
#include "../vendor/opus/find_pred_coefs_FLP.c"
#include "../vendor/opus/LPC_analysis_filter_FLP.c"
#include "../vendor/opus/LTP_analysis_filter_FLP.c"
#include "../vendor/opus/LTP_scale_ctrl_FLP.c"
#include "../vendor/opus/noise_shape_analysis_FLP.c"
#include "../vendor/opus/process_gains_FLP.c"
#include "../vendor/opus/regularize_correlations_FLP.c"
#include "../vendor/opus/residual_energy_FLP.c"
#include "../vendor/opus/warped_autocorrelation_FLP.c"
#include "../vendor/opus/wrappers_FLP.c"
#include "../vendor/opus/autocorrelation_FLP.c"
#include "../vendor/opus/burg_modified_FLP.c"
#include "../vendor/opus/bwexpander_FLP.c"
#include "../vendor/opus/energy_FLP.c"
#include "../vendor/opus/inner_product_FLP.c"
#include "../vendor/opus/k2a_FLP.c"
#include "../vendor/opus/LPC_inv_pred_gain_FLP.c"
#include "../vendor/opus/pitch_analysis_core_FLP.c"
#include "../vendor/opus/scale_copy_vector_FLP.c"
#include "../vendor/opus/scale_vector_FLP.c"
#include "../vendor/opus/schur_FLP.c"
#include "../vendor/opus/sort_FLP.c"
