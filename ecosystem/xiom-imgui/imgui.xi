// XIOM — Dear ImGui Bindings (Immediate Mode GUI)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.imgui

pub fn create_context() -> Result[Unit, Str];
pub fn destroy_context();

pub fn new_frame();
pub fn render();

pub fn begin_window(title: Str, open: &Bool, flags: Int) -> Bool;
pub fn end_window();
pub fn begin_child(id: Str, width: Float32, height: Float32) -> Bool;
pub fn end_child();

pub fn separator();
pub fn same_line(offset: Float32, spacing: Float32);
pub fn spacing();

pub fn text(text: Str);
pub fn text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str);
pub fn button(label: Str, width: Float32, height: Float32) -> Bool;
pub fn checkbox(label: Str, value: &mut Bool) -> Bool;
pub fn slider_float(label: Str, value: &mut Float32, min: Float32, max: Float32) -> Bool;
pub fn slider_int(label: Str, value: &mut Int, min: Int, max: Int) -> Bool;
pub fn input_float(label: Str, value: &mut Float32) -> Bool;
pub fn input_int(label: Str, value: &mut Int) -> Bool;
pub fn input_text(label: Str, buffer: &mut Str, buf_size: Int) -> Bool;
pub fn combo(label: Str, current: &mut Int, items: Vec[Str]) -> Bool;

pub fn tree_node(label: Str) -> Bool;
pub fn tree_pop();
pub fn collapsing_header(label: Str) -> Bool;

pub fn plot_lines(label: Str, values: &Vec[Float32], scale_min: Float32, scale_max: Float32);
pub fn plot_histogram(label: Str, values: &Vec[Float32], scale_min: Float32, scale_max: Float32);

pub fn open_popup(name: Str);
pub fn begin_popup(name: Str) -> Bool;
pub fn end_popup();
pub fn begin_modal(name: Str, open: &Bool) -> Bool;
pub fn end_modal();

pub fn style_dark();
pub fn style_light();
pub fn style_classic();

pub fn init_for_vulkan(window: Int) -> Result[Unit, Str];
pub fn init_for_opengl(window: Int) -> Result[Unit, Str];
pub fn shutdown_backend();
pub fn render_vulkan(draw_data: Int, cmd_buffer: Int, pipeline: Int);

pub const WINDOW_NO_TITLE_BAR: Int = 1;
pub const WINDOW_NO_RESIZE: Int = 2;
pub const WINDOW_NO_MOVE: Int = 4;
pub const WINDOW_NO_SCROLLBAR: Int = 8;
pub const WINDOW_NO_COLLAPSE: Int = 16;
pub const WINDOW_ALWAYS_AUTO_RESIZE: Int = 32;
