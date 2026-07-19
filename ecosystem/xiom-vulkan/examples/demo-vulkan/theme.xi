// demo-vulkan theme — "Void Neon" palette
// All colors are Float32 RGB. Use these tokens throughout the UI.

module demo_vulkan.theme

// ── Backgrounds
pub fn TK_BG_VOID_R() -> Float32     { return 0.04; }
pub fn TK_BG_VOID_G() -> Float32     { return 0.04; }
pub fn TK_BG_VOID_B() -> Float32     { return 0.06; }
pub fn TK_PANEL_BG_R() -> Float32    { return 0.07; }
pub fn TK_PANEL_BG_G() -> Float32    { return 0.08; }
pub fn TK_PANEL_BG_B() -> Float32    { return 0.11; }
pub fn TK_PANEL_BORDER_R() -> Float32 { return 0.14; }
pub fn TK_PANEL_BORDER_G() -> Float32 { return 0.44; }
pub fn TK_PANEL_BORDER_B() -> Float32 { return 0.60; }

// ── Buttons
pub fn TK_BTN_NORMAL_R() -> Float32 { return 0.12; }
pub fn TK_BTN_NORMAL_G() -> Float32 { return 0.14; }
pub fn TK_BTN_NORMAL_B() -> Float32 { return 0.18; }
pub fn TK_BTN_HOVER_R() -> Float32  { return 0.20; }
pub fn TK_BTN_HOVER_G() -> Float32  { return 0.24; }
pub fn TK_BTN_HOVER_B() -> Float32  { return 0.30; }
pub fn TK_BTN_PRESS_R() -> Float32  { return 0.07; }
pub fn TK_BTN_PRESS_G() -> Float32  { return 0.08; }
pub fn TK_BTN_PRESS_B() -> Float32  { return 0.11; }

// ── Accent colors
pub fn TK_ACCENT_1_R() -> Float32 { return 0.16; }
pub fn TK_ACCENT_1_G() -> Float32 { return 0.64; }
pub fn TK_ACCENT_1_B() -> Float32 { return 0.88; }
pub fn TK_ACCENT_2_R() -> Float32 { return 0.88; }
pub fn TK_ACCENT_2_G() -> Float32 { return 0.55; }
pub fn TK_ACCENT_2_B() -> Float32 { return 0.16; }
pub fn TK_ACCENT_3_R() -> Float32 { return 0.16; }
pub fn TK_ACCENT_3_G() -> Float32 { return 0.88; }
pub fn TK_ACCENT_3_B() -> Float32 { return 0.55; }
pub fn TK_ACCENT_DANGER_R() -> Float32 { return 0.88; }
pub fn TK_ACCENT_DANGER_G() -> Float32 { return 0.20; }
pub fn TK_ACCENT_DANGER_B() -> Float32 { return 0.32; }

// ── Text
pub fn TK_TEXT_PRIMARY_R() -> Float32   { return 0.85; }
pub fn TK_TEXT_PRIMARY_G() -> Float32   { return 0.85; }
pub fn TK_TEXT_PRIMARY_B() -> Float32   { return 0.88; }
pub fn TK_TEXT_SECONDARY_R() -> Float32 { return 0.48; }
pub fn TK_TEXT_SECONDARY_G() -> Float32 { return 0.50; }
pub fn TK_TEXT_SECONDARY_B() -> Float32 { return 0.55; }

// ── Spacing (NDC normalized for 16:9 aspect)
pub fn TK_PAD_XS() -> Float32  { return 0.004; }
pub fn TK_PAD_SM() -> Float32  { return 0.008; }
pub fn TK_PAD_MD() -> Float32  { return 0.014; }
pub fn TK_BORDER_W() -> Float32 { return 0.003; }
pub fn TK_TITLE_H() -> Float32  { return 0.025; }

// ── Layout regions (NDC x,y center; hw,hh half-extents)
pub fn TK_LAYOUT_TOPBAR_CY() -> Float32  { return 0.94; }
pub fn TK_LAYOUT_TOPBAR_HH() -> Float32  { return 0.06; }
pub fn TK_LAYOUT_STATUSBAR_CY() -> Float32 { return -0.96; }
pub fn TK_LAYOUT_STATUSBAR_HH() -> Float32 { return 0.04; }
pub fn TK_LAYOUT_LEFT_CX() -> Float32    { return -0.84; }
pub fn TK_LAYOUT_LEFT_CY() -> Float32    { return -0.01; }
pub fn TK_LAYOUT_LEFT_HW() -> Float32    { return 0.16; }
pub fn TK_LAYOUT_RIGHT_CX() -> Float32   { return 0.84; }
pub fn TK_LAYOUT_RIGHT_CY() -> Float32   { return -0.01; }
pub fn TK_LAYOUT_RIGHT_HW() -> Float32   { return 0.16; }
pub fn TK_LAYOUT_VIEWPORT_CX() -> Float32 { return 0.0; }
pub fn TK_LAYOUT_VIEWPORT_CY() -> Float32 { return -0.01; }
pub fn TK_LAYOUT_VIEWPORT_HW() -> Float32 { return 0.34; }
pub fn TK_LAYOUT_PANEL_HH() -> Float32   { return 0.86; }
