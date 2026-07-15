module xiom.ui.theme

use xiom.ui.types;

pub type Theme = {
  bg_color: Color;
  text_color: Color;
  accent_color: Color;
  border_color: Color;
  hover_color: Color;
  active_color: Color;
  font_scale: Float32;
  corner_radius: Float32;
}

pub fn Theme.new(
  bg: Color,
  text: Color,
  accent: Color,
  border: Color,
  hover: Color,
  active: Color,
  scale: Float32,
  radius: Float32
) -> Theme {
  return Theme{
    bg_color: bg,
    text_color: text,
    accent_color: accent,
    border_color: border,
    hover_color: hover,
    active_color: active,
    font_scale: scale,
    corner_radius: radius,
  };
}

pub fn theme_default() -> Theme {
  return Theme{
    bg_color: Color.new(0.96, 0.96, 0.96, 1.0),
    text_color: Color.new(0.1, 0.1, 0.1, 1.0),
    accent_color: Color.new(0.2, 0.5, 0.9, 1.0),
    border_color: Color.new(0.7, 0.7, 0.7, 1.0),
    hover_color: Color.new(0.85, 0.85, 0.85, 1.0),
    active_color: Color.new(0.75, 0.75, 0.75, 1.0),
    font_scale: 1.0,
    corner_radius: 4.0,
  };
}

pub fn theme_dark() -> Theme {
  return Theme{
    bg_color: Color.new(0.15, 0.15, 0.15, 1.0),
    text_color: Color.new(0.9, 0.9, 0.9, 1.0),
    accent_color: Color.new(0.3, 0.6, 1.0, 1.0),
    border_color: Color.new(0.35, 0.35, 0.35, 1.0),
    hover_color: Color.new(0.25, 0.25, 0.25, 1.0),
    active_color: Color.new(0.2, 0.2, 0.2, 1.0),
    font_scale: 1.0,
    corner_radius: 4.0,
  };
}

pub fn theme_high_contrast() -> Theme {
  return Theme{
    bg_color: Color.new(0.0, 0.0, 0.0, 1.0),
    text_color: Color.new(1.0, 1.0, 1.0, 1.0),
    accent_color: Color.new(1.0, 1.0, 0.0, 1.0),
    border_color: Color.new(1.0, 1.0, 1.0, 1.0),
    hover_color: Color.new(0.2, 0.2, 0.2, 1.0),
    active_color: Color.new(0.3, 0.3, 0.3, 1.0),
    font_scale: 1.2,
    corner_radius: 0.0,
  };
}

pub fn Theme.clone() -> Theme {
  return Theme{
    bg_color: bg_color,
    text_color: text_color,
    accent_color: accent_color,
    border_color: border_color,
    hover_color: hover_color,
    active_color: active_color,
    font_scale: font_scale,
    corner_radius: corner_radius,
  };
}
