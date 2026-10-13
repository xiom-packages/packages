package xiom_harfbuzz {
  name: "xiom.harfbuzz";
  version: "0.1.0";
  description: "harfbuzz 14.6.0 bindings for XIOM (vendored amalgam; full declared surface: 582 functions across hb.h + hb-ot.h + hb-subset.h + hb-version.h; shaping, subsetting, OT layout/introspection)";
  categories: ["text", "media"];
  keywords: ["harfbuzz", "text", "shaping", "subset", "opentype", "font", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.harfbuzz", "xiom.harfbuzz.gen.blob", "xiom.harfbuzz.gen.buffer", "xiom.harfbuzz.gen.common", "xiom.harfbuzz.gen.deprecated", "xiom.harfbuzz.gen.draw", "xiom.harfbuzz.gen.face", "xiom.harfbuzz.gen.font", "xiom.harfbuzz.gen.hb", "xiom.harfbuzz.gen.map", "xiom.harfbuzz.gen.ot", "xiom.harfbuzz.gen.ot_color", "xiom.harfbuzz.gen.ot_deprecated", "xiom.harfbuzz.gen.ot_fetch", "xiom.harfbuzz.gen.ot_font", "xiom.harfbuzz.gen.ot_layout", "xiom.harfbuzz.gen.ot_math", "xiom.harfbuzz.gen.ot_meta", "xiom.harfbuzz.gen.ot_metrics", "xiom.harfbuzz.gen.ot_name", "xiom.harfbuzz.gen.ot_shape", "xiom.harfbuzz.gen.ot_var", "xiom.harfbuzz.gen.paint", "xiom.harfbuzz.gen.script_list", "xiom.harfbuzz.gen.set", "xiom.harfbuzz.gen.shape", "xiom.harfbuzz.gen.shape_plan", "xiom.harfbuzz.gen.style", "xiom.harfbuzz.gen.subset", "xiom.harfbuzz.gen.subset_depend", "xiom.harfbuzz.gen.subset_serialize", "xiom.harfbuzz.gen.surface", "xiom.harfbuzz.gen.unicode", "xiom.harfbuzz.gen.version"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
