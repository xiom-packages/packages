// XIOM -- xiom.android.configuration: A2 configuration head (W2c).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// SCOPE: android/configuration.h of NDK r27b (docs/ANDROID-SDK100.md
// slice A2; wave brief docs/prep/android-wave.md).  The whole header
// surface is in the bridge export set (50 platform exports; the 51st
// prototype -- AConfiguration_setScreenRound -- is declared by the
// header but NOT exported by the platform libraries, verified against
// the API-36 device libandroid.so and the API-35 stubs).  All 50
// exported functions are wrapped FUNCTIONALLY here: AConfiguration is a
// pure value object, no app context needed.
//
//   new/delete/copy/diff/match/isBetterThan + 19 int32 get/set pairs +
//   language/country (char[2]) + getScreenRound.
//
//   AConfiguration_fromAssetManager (the 50th export) needs a live
//   AAssetManager -> A11 JNI seam; export-set ABI-checked by the bridge.
//
// Minimum API level: grammaticalGender is API 34, screenRound getter is
// API 30 (the bridge's ABI check is strict; older images report the
// honest delta).

module xiom.android.configuration

use xiom.android;

extern "C" {
  fn xa_config_new() -> Int64;
  fn xa_config_delete(config: Int64) -> Int32;
  fn xa_config_copy(dest: Int64, src: Int64) -> Int32;
  fn xa_config_diff(a: Int64, b: Int64) -> Int32;
  fn xa_config_match(base: Int64, requested: Int64) -> Int32;
  fn xa_config_is_better_than(base: Int64, test: Int64, requested: Int64) -> Int32;
  fn xa_config_get_screen_round(config: Int64) -> Int32;
  fn xa_config_get_language(config: Int64) -> *UInt8;
  fn xa_config_set_language(config: Int64, language: *UInt8) -> Int32;
  fn xa_config_get_country(config: Int64) -> *UInt8;
  fn xa_config_set_country(config: Int64, country: *UInt8) -> Int32;
  fn xa_config_get_mcc(config: Int64) -> Int32;
  fn xa_config_set_mcc(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_mnc(config: Int64) -> Int32;
  fn xa_config_set_mnc(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_orientation(config: Int64) -> Int32;
  fn xa_config_set_orientation(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_touchscreen(config: Int64) -> Int32;
  fn xa_config_set_touchscreen(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_density(config: Int64) -> Int32;
  fn xa_config_set_density(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_keyboard(config: Int64) -> Int32;
  fn xa_config_set_keyboard(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_navigation(config: Int64) -> Int32;
  fn xa_config_set_navigation(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_keys_hidden(config: Int64) -> Int32;
  fn xa_config_set_keys_hidden(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_nav_hidden(config: Int64) -> Int32;
  fn xa_config_set_nav_hidden(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_sdk_version(config: Int64) -> Int32;
  fn xa_config_set_sdk_version(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_screen_size(config: Int64) -> Int32;
  fn xa_config_set_screen_size(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_screen_long(config: Int64) -> Int32;
  fn xa_config_set_screen_long(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_ui_mode_type(config: Int64) -> Int32;
  fn xa_config_set_ui_mode_type(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_ui_mode_night(config: Int64) -> Int32;
  fn xa_config_set_ui_mode_night(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_screen_width_dp(config: Int64) -> Int32;
  fn xa_config_set_screen_width_dp(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_screen_height_dp(config: Int64) -> Int32;
  fn xa_config_set_screen_height_dp(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_smallest_screen_width_dp(config: Int64) -> Int32;
  fn xa_config_set_smallest_screen_width_dp(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_layout_direction(config: Int64) -> Int32;
  fn xa_config_set_layout_direction(config: Int64, value: Int32) -> Int32;
  fn xa_config_get_grammatical_gender(config: Int64) -> Int32;
  fn xa_config_set_grammatical_gender(config: Int64, value: Int32) -> Int32;
}

// =========================================================================
// ACONFIGURATION_* constants (android/configuration.h)
// =========================================================================

// Orientation (ACONFIGURATION_ORIENTATION_*).
pub const ACONFIGURATION_ORIENTATION_ANY: Int = 0x0000;
pub const ACONFIGURATION_ORIENTATION_PORT: Int = 0x0001;
pub const ACONFIGURATION_ORIENTATION_LAND: Int = 0x0002;
pub const ACONFIGURATION_ORIENTATION_SQUARE: Int = 0x0003;

// Touchscreen (ACONFIGURATION_TOUCHSCREEN_*).
pub const ACONFIGURATION_TOUCHSCREEN_ANY: Int = 0x0000;
pub const ACONFIGURATION_TOUCHSCREEN_NOTOUCH: Int = 0x0001;
pub const ACONFIGURATION_TOUCHSCREEN_STYLUS: Int = 0x0002;
pub const ACONFIGURATION_TOUCHSCREEN_FINGER: Int = 0x0003;

// Density (ACONFIGURATION_DENSITY_*).
pub const ACONFIGURATION_DENSITY_DEFAULT: Int = 0;
pub const ACONFIGURATION_DENSITY_LOW: Int = 120;
pub const ACONFIGURATION_DENSITY_MEDIUM: Int = 160;
pub const ACONFIGURATION_DENSITY_TV: Int = 213;
pub const ACONFIGURATION_DENSITY_HIGH: Int = 240;
pub const ACONFIGURATION_DENSITY_XHIGH: Int = 320;
pub const ACONFIGURATION_DENSITY_XXHIGH: Int = 480;
pub const ACONFIGURATION_DENSITY_XXXHIGH: Int = 640;
pub const ACONFIGURATION_DENSITY_ANY: Int = 0xfffe;
pub const ACONFIGURATION_DENSITY_NONE: Int = 0xffff;

// Keyboard (ACONFIGURATION_KEYBOARD_*).
pub const ACONFIGURATION_KEYBOARD_ANY: Int = 0x0000;
pub const ACONFIGURATION_KEYBOARD_NOKEYS: Int = 0x0001;
pub const ACONFIGURATION_KEYBOARD_QWERTY: Int = 0x0002;
pub const ACONFIGURATION_KEYBOARD_12KEY: Int = 0x0003;

// Navigation (ACONFIGURATION_NAVIGATION_*).
pub const ACONFIGURATION_NAVIGATION_ANY: Int = 0x0000;
pub const ACONFIGURATION_NAVIGATION_NONAV: Int = 0x0001;
pub const ACONFIGURATION_NAVIGATION_DPAD: Int = 0x0002;
pub const ACONFIGURATION_NAVIGATION_TRACKBALL: Int = 0x0003;
pub const ACONFIGURATION_NAVIGATION_WHEEL: Int = 0x0004;

// Keyboard availability (ACONFIGURATION_KEYSHIDDEN_*).
pub const ACONFIGURATION_KEYSHIDDEN_ANY: Int = 0x0000;
pub const ACONFIGURATION_KEYSHIDDEN_NO: Int = 0x0001;
pub const ACONFIGURATION_KEYSHIDDEN_YES: Int = 0x0002;
pub const ACONFIGURATION_KEYSHIDDEN_SOFT: Int = 0x0003;

// Navigation availability (ACONFIGURATION_NAVHIDDEN_*).
pub const ACONFIGURATION_NAVHIDDEN_ANY: Int = 0x0000;
pub const ACONFIGURATION_NAVHIDDEN_NO: Int = 0x0001;
pub const ACONFIGURATION_NAVHIDDEN_YES: Int = 0x0002;

// Screen size (ACONFIGURATION_SCREENSIZE_*).
pub const ACONFIGURATION_SCREENSIZE_ANY: Int = 0x00;
pub const ACONFIGURATION_SCREENSIZE_SMALL: Int = 0x01;
pub const ACONFIGURATION_SCREENSIZE_NORMAL: Int = 0x02;
pub const ACONFIGURATION_SCREENSIZE_LARGE: Int = 0x03;
pub const ACONFIGURATION_SCREENSIZE_XLARGE: Int = 0x04;

// Screen long (ACONFIGURATION_SCREENLONG_*).
pub const ACONFIGURATION_SCREENLONG_ANY: Int = 0x00;
pub const ACONFIGURATION_SCREENLONG_NO: Int = 0x1;
pub const ACONFIGURATION_SCREENLONG_YES: Int = 0x2;

// Screen round (ACONFIGURATION_SCREENROUND_*).
pub const ACONFIGURATION_SCREENROUND_ANY: Int = 0x00;
pub const ACONFIGURATION_SCREENROUND_NO: Int = 0x1;
pub const ACONFIGURATION_SCREENROUND_YES: Int = 0x2;

// Wide color gamut (ACONFIGURATION_WIDE_COLOR_GAMUT_*).
pub const ACONFIGURATION_WIDE_COLOR_GAMUT_ANY: Int = 0x00;
pub const ACONFIGURATION_WIDE_COLOR_GAMUT_NO: Int = 0x1;
pub const ACONFIGURATION_WIDE_COLOR_GAMUT_YES: Int = 0x2;

// HDR (ACONFIGURATION_HDR_*).
pub const ACONFIGURATION_HDR_ANY: Int = 0x00;
pub const ACONFIGURATION_HDR_NO: Int = 0x1;
pub const ACONFIGURATION_HDR_YES: Int = 0x2;

// UI mode type (ACONFIGURATION_UI_MODE_TYPE_*).
pub const ACONFIGURATION_UI_MODE_TYPE_ANY: Int = 0x00;
pub const ACONFIGURATION_UI_MODE_TYPE_NORMAL: Int = 0x01;
pub const ACONFIGURATION_UI_MODE_TYPE_DESK: Int = 0x02;
pub const ACONFIGURATION_UI_MODE_TYPE_CAR: Int = 0x03;
pub const ACONFIGURATION_UI_MODE_TYPE_TELEVISION: Int = 0x04;
pub const ACONFIGURATION_UI_MODE_TYPE_APPLIANCE: Int = 0x05;
pub const ACONFIGURATION_UI_MODE_TYPE_WATCH: Int = 0x06;
pub const ACONFIGURATION_UI_MODE_TYPE_VR_HEADSET: Int = 0x07;

// UI night mode (ACONFIGURATION_UI_MODE_NIGHT_*).
pub const ACONFIGURATION_UI_MODE_NIGHT_ANY: Int = 0x00;
pub const ACONFIGURATION_UI_MODE_NIGHT_NO: Int = 0x1;
pub const ACONFIGURATION_UI_MODE_NIGHT_YES: Int = 0x2;

// Screen width/height/smallest dp "not specified" values.
pub const ACONFIGURATION_SCREEN_WIDTH_DP_ANY: Int = 0x0000;
pub const ACONFIGURATION_SCREEN_HEIGHT_DP_ANY: Int = 0x0000;
pub const ACONFIGURATION_SMALLEST_SCREEN_WIDTH_DP_ANY: Int = 0x0000;

// Layout direction (ACONFIGURATION_LAYOUTDIR_*).
pub const ACONFIGURATION_LAYOUTDIR_ANY: Int = 0x00;
pub const ACONFIGURATION_LAYOUTDIR_LTR: Int = 0x01;
pub const ACONFIGURATION_LAYOUTDIR_RTL: Int = 0x02;

// Diff/match bit masks (ACONFIGURATION_*).
pub const ACONFIGURATION_MCC: Int = 0x0001;
pub const ACONFIGURATION_MNC: Int = 0x0002;
pub const ACONFIGURATION_LOCALE: Int = 0x0004;
pub const ACONFIGURATION_TOUCHSCREEN: Int = 0x0008;
pub const ACONFIGURATION_KEYBOARD: Int = 0x0010;
pub const ACONFIGURATION_KEYBOARD_HIDDEN: Int = 0x0020;
pub const ACONFIGURATION_NAVIGATION: Int = 0x0040;
pub const ACONFIGURATION_ORIENTATION: Int = 0x0080;
pub const ACONFIGURATION_DENSITY: Int = 0x0100;
pub const ACONFIGURATION_SCREEN_SIZE: Int = 0x0200;
pub const ACONFIGURATION_VERSION: Int = 0x0400;
pub const ACONFIGURATION_SCREEN_LAYOUT: Int = 0x0800;
pub const ACONFIGURATION_UI_MODE: Int = 0x1000;
pub const ACONFIGURATION_SMALLEST_SCREEN_SIZE: Int = 0x2000;
pub const ACONFIGURATION_LAYOUTDIR: Int = 0x4000;
pub const ACONFIGURATION_SCREEN_ROUND: Int = 0x8000;
pub const ACONFIGURATION_COLOR_MODE: Int = 0x10000;
pub const ACONFIGURATION_GRAMMATICAL_GENDER: Int = 0x20000;
pub const ACONFIGURATION_MNC_ZERO: Int = 0xffff;

// Grammatical gender (ACONFIGURATION_GRAMMATICAL_GENDER_*).
pub const ACONFIGURATION_GRAMMATICAL_GENDER_ANY: Int = 0;
pub const ACONFIGURATION_GRAMMATICAL_GENDER_NEUTER: Int = 1;
pub const ACONFIGURATION_GRAMMATICAL_GENDER_FEMININE: Int = 2;
pub const ACONFIGURATION_GRAMMATICAL_GENDER_MASCULINE: Int = 3;

// =========================================================================
// AConfiguration functional head
// =========================================================================

pub type Config = {
  handle: Int;
}

/// Create a new AConfiguration initialized with no values.  Free with
/// `config_delete`.
/// Complexity: O(1).
pub fn config_new() -> Result[Config, AndroidProbeError]
  requires: true
{
  let h = unsafe { xa_config_new() } as Int;
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI, message: android_error() });
  }
  return Ok(Config{ handle: h });
}

/// Free an AConfiguration previously created with config_new/config_clone.
/// Complexity: O(1).
pub fn config_delete(config: Config) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_delete(config.handle as Int64) } as Int;
  return rc == 0;
}

/// Create a config and copy `src` into it (new + copy convenience).
/// Complexity: O(1).
pub fn config_clone(src: &Config) -> Result[Config, AndroidProbeError]
  requires: src.handle != 0
{
  let a = config_new();
  if a.is_ok {
    let dest: Config = a.value;
    let rc = unsafe { xa_config_copy(dest.handle as Int64, src.handle as Int64) } as Int;
    if rc != 0 {
      let _ = config_delete(dest);
      return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI, message: android_error() });
    }
    return Ok(dest);
  } else {
    return Err(a.error);
  }
}

/// Copy the contents of src into dest.
/// Complexity: O(1).
pub fn config_copy(dest: &Config, src: &Config) -> Bool
  requires: dest.handle != 0
  requires: src.handle != 0
{
  let rc = unsafe { xa_config_copy(dest.handle as Int64, src.handle as Int64) } as Int;
  return rc == 0;
}

/// Diff bit mask of ACONFIGURATION_* constants different between a and b
/// (negative = error).
/// Complexity: O(1).
pub fn config_diff(a: &Config, b: &Config) -> Int
  requires: a.handle != 0
  requires: b.handle != 0
{
  unsafe { return xa_config_diff(a.handle as Int64, b.handle as Int64) as Int; }
}

/// True when `base` is a valid configuration for the environment
/// `requested` (no conflicting values); false on conflict/error.
/// Complexity: O(1).
pub fn config_match(base: &Config, requested: &Config) -> Bool
  requires: base.handle != 0
  requires: requested.handle != 0
{
  let rc = unsafe { xa_config_match(base.handle as Int64, requested.handle as Int64) } as Int;
  return rc == 1;
}

/// True when `test` is better than `base` for `requested` (NULL-free:
/// pass any config as `requested`; the bridge passes it through).
/// Complexity: O(1).
pub fn config_is_better_than(base: &Config, test: &Config, requested: &Config) -> Bool
  requires: base.handle != 0
  requires: test.handle != 0
  requires: requested.handle != 0
{
  let rc = unsafe {
    xa_config_is_better_than(base.handle as Int64, test.handle as Int64,
                             requested.handle as Int64) as Int
  };
  return rc != 0;
}

/// Screen round (ACONFIGURATION_SCREENROUND_*); read-only: the platform
/// does not export AConfiguration_setScreenRound (header-only prototype).
/// Complexity: O(1).
pub fn config_screen_round(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_screen_round(config.handle as Int64) as Int; }
}

/// Language code (two chars; "" when unset).
/// Complexity: O(1).
pub fn config_language(config: &Config) -> Str
  requires: config.handle != 0
{
  unsafe {
    let p = xa_config_get_language(config.handle as Int64);
    if p == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Set the language from the first two chars of `language`.
/// Complexity: O(1).
pub fn config_set_language(config: &Config, language: Str) -> Bool
  requires: config.handle != 0
  requires: language.len() >= 2
{
  let rc = unsafe { xa_config_set_language(config.handle as Int64, language.c_str()) } as Int;
  return rc == 0;
}

/// Country code (two chars; "" when unset).
/// Complexity: O(1).
pub fn config_country(config: &Config) -> Str
  requires: config.handle != 0
{
  unsafe {
    let p = xa_config_get_country(config.handle as Int64);
    if p == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Set the country from the first two chars of `country`.
/// Complexity: O(1).
pub fn config_set_country(config: &Config, country: Str) -> Bool
  requires: config.handle != 0
  requires: country.len() >= 2
{
  let rc = unsafe { xa_config_set_country(config.handle as Int64, country.c_str()) } as Int;
  return rc == 0;
}

// ---- 19 scalar int32 fields: get/set (ACONFIGURATION_* values) ----------

/// Mobile country code (0 = unset).
/// Complexity: O(1).
pub fn config_mcc(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_mcc(config.handle as Int64) as Int; }
}

/// Set the mobile country code (0 clears).
/// Complexity: O(1).
pub fn config_set_mcc(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_mcc(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Mobile network code (0 = unset; ACONFIGURATION_MNC_ZERO for the
/// special zero code).
/// Complexity: O(1).
pub fn config_mnc(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_mnc(config.handle as Int64) as Int; }
}

/// Set the mobile network code (0 clears).
/// Complexity: O(1).
pub fn config_set_mnc(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_mnc(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Orientation (ACONFIGURATION_ORIENTATION_*).
/// Complexity: O(1).
pub fn config_orientation(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_orientation(config.handle as Int64) as Int; }
}

/// Set the orientation (ACONFIGURATION_ORIENTATION_*).
/// Complexity: O(1).
pub fn config_set_orientation(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_orientation(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Touchscreen (ACONFIGURATION_TOUCHSCREEN_*).
/// Complexity: O(1).
pub fn config_touchscreen(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_touchscreen(config.handle as Int64) as Int; }
}

/// Set the touchscreen (ACONFIGURATION_TOUCHSCREEN_*).
/// Complexity: O(1).
pub fn config_set_touchscreen(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_touchscreen(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Density (ACONFIGURATION_DENSITY_*).
/// Complexity: O(1).
pub fn config_density(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_density(config.handle as Int64) as Int; }
}

/// Set the density (ACONFIGURATION_DENSITY_*).
/// Complexity: O(1).
pub fn config_set_density(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_density(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Keyboard (ACONFIGURATION_KEYBOARD_*).
/// Complexity: O(1).
pub fn config_keyboard(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_keyboard(config.handle as Int64) as Int; }
}

/// Set the keyboard (ACONFIGURATION_KEYBOARD_*).
/// Complexity: O(1).
pub fn config_set_keyboard(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_keyboard(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Navigation (ACONFIGURATION_NAVIGATION_*).
/// Complexity: O(1).
pub fn config_navigation(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_navigation(config.handle as Int64) as Int; }
}

/// Set the navigation (ACONFIGURATION_NAVIGATION_*).
/// Complexity: O(1).
pub fn config_set_navigation(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_navigation(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Keyboard availability (ACONFIGURATION_KEYSHIDDEN_*).
/// Complexity: O(1).
pub fn config_keys_hidden(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_keys_hidden(config.handle as Int64) as Int; }
}

/// Set the keyboard availability (ACONFIGURATION_KEYSHIDDEN_*).
/// Complexity: O(1).
pub fn config_set_keys_hidden(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_keys_hidden(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Navigation availability (ACONFIGURATION_NAVHIDDEN_*).
/// Complexity: O(1).
pub fn config_nav_hidden(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_nav_hidden(config.handle as Int64) as Int; }
}

/// Set the navigation availability (ACONFIGURATION_NAVHIDDEN_*).
/// Complexity: O(1).
pub fn config_set_nav_hidden(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_nav_hidden(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// SDK (API) version.
/// Complexity: O(1).
pub fn config_sdk_version(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_sdk_version(config.handle as Int64) as Int; }
}

/// Set the SDK (API) version.
/// Complexity: O(1).
pub fn config_set_sdk_version(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_sdk_version(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Screen size (ACONFIGURATION_SCREENSIZE_*).
/// Complexity: O(1).
pub fn config_screen_size(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_screen_size(config.handle as Int64) as Int; }
}

/// Set the screen size (ACONFIGURATION_SCREENSIZE_*).
/// Complexity: O(1).
pub fn config_set_screen_size(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_screen_size(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Screen long (ACONFIGURATION_SCREENLONG_*).
/// Complexity: O(1).
pub fn config_screen_long(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_screen_long(config.handle as Int64) as Int; }
}

/// Set the screen long (ACONFIGURATION_SCREENLONG_*).
/// Complexity: O(1).
pub fn config_set_screen_long(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_screen_long(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// UI mode type (ACONFIGURATION_UI_MODE_TYPE_*).
/// Complexity: O(1).
pub fn config_ui_mode_type(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_ui_mode_type(config.handle as Int64) as Int; }
}

/// Set the UI mode type (ACONFIGURATION_UI_MODE_TYPE_*).
/// Complexity: O(1).
pub fn config_set_ui_mode_type(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_ui_mode_type(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// UI night mode (ACONFIGURATION_UI_MODE_NIGHT_*).
/// Complexity: O(1).
pub fn config_ui_mode_night(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_ui_mode_night(config.handle as Int64) as Int; }
}

/// Set the UI night mode (ACONFIGURATION_UI_MODE_NIGHT_*).
/// Complexity: O(1).
pub fn config_set_ui_mode_night(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_ui_mode_night(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Screen width in dp (ACONFIGURATION_SCREEN_WIDTH_DP_ANY = unset).
/// Complexity: O(1).
pub fn config_screen_width_dp(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_screen_width_dp(config.handle as Int64) as Int; }
}

/// Set the screen width in dp.
/// Complexity: O(1).
pub fn config_set_screen_width_dp(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_screen_width_dp(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Screen height in dp (ACONFIGURATION_SCREEN_HEIGHT_DP_ANY = unset).
/// Complexity: O(1).
pub fn config_screen_height_dp(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_screen_height_dp(config.handle as Int64) as Int; }
}

/// Set the screen height in dp.
/// Complexity: O(1).
pub fn config_set_screen_height_dp(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_screen_height_dp(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Smallest screen width in dp
/// (ACONFIGURATION_SMALLEST_SCREEN_WIDTH_DP_ANY = unset).
/// Complexity: O(1).
pub fn config_smallest_screen_width_dp(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_smallest_screen_width_dp(config.handle as Int64) as Int; }
}

/// Set the smallest screen width in dp.
/// Complexity: O(1).
pub fn config_set_smallest_screen_width_dp(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe {
    xa_config_set_smallest_screen_width_dp(config.handle as Int64, value as Int32) as Int
  };
  return rc == 0;
}

/// Layout direction (ACONFIGURATION_LAYOUTDIR_*).
/// Complexity: O(1).
pub fn config_layout_direction(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_layout_direction(config.handle as Int64) as Int; }
}

/// Set the layout direction (ACONFIGURATION_LAYOUTDIR_*).
/// Complexity: O(1).
pub fn config_set_layout_direction(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe { xa_config_set_layout_direction(config.handle as Int64, value as Int32) } as Int;
  return rc == 0;
}

/// Grammatical gender (ACONFIGURATION_GRAMMATICAL_GENDER_*; API 34+).
/// Complexity: O(1).
pub fn config_grammatical_gender(config: &Config) -> Int
  requires: config.handle != 0
{
  unsafe { return xa_config_get_grammatical_gender(config.handle as Int64) as Int; }
}

/// Set the grammatical gender (API 34+).
/// Complexity: O(1).
pub fn config_set_grammatical_gender(config: &Config, value: Int) -> Bool
  requires: config.handle != 0
{
  let rc = unsafe {
    xa_config_set_grammatical_gender(config.handle as Int64, value as Int32) as Int
  };
  return rc == 0;
}
