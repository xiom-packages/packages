# xiom.ui Roadmap

## v0.1.0 (Current)

- [x] Core types: Rect, Color, Point, Size, Padding, Margin, enums, InputState
- [x] Layout engine: LayoutContext, layout_row, layout_column, layout_grid, alignment
- [x] Widget state types: Button, Checkbox, TextField, Slider, Dropdown, Panel, Tabs
- [x] Render command buffer: RectCmd, TextCmd, CircleCmd, LineCmd, ImageCmd, ClipCmd
- [x] Theme system: default, dark, high-contrast presets
- [x] Application framework: UIApp lifecycle (begin/end frame)
- [x] OpenGL render backend (via FFI bridge)
- [x] Safety contracts on geometry, layout, widget, and app constructors
- [x] Conformance test suite (98 tests)

## v0.2.0 -- Input & Interaction

- [ ] Widget hit-testing: dispatch mouse events to active widget
- [ ] Focus management: tab-focus cycling across input widgets
- [ ] Event system: `pub enum UIEvent` with routing and propagation
- [ ] Keyboard navigation: arrow keys, Enter/Escape for widgets
- [ ] Text selection: shift+arrow selection in TextFieldState

## v0.3.0 -- GLFW Window Integration

- [ ] xiom.glfw FFI binding: window creation, input polling, event translation
- [ ] GlfwApp: concrete UIApp runner with GLFW backend
- [ ] Resize handling: viewport updates on window resize
- [ ] Multi-window support: independent UIApps per window
- [ ] Clipboard integration: copy/paste for TextFieldState

## v0.4.0 -- Text Rendering

- [ ] Font atlas generation: stb_truetype integration for glyph rasterization
- [ ] Glyph placement: kerning, line height, word wrap
- [ ] Multi-font support: font families and weights in Theme
- [ ] Rich text: inline color/style spans within TextCmd
- [ ] Text input pipeline: keyboard events -> character composition

## v0.5.0 -- Styling & Theming

- [ ] Style sheets: JSON/XIOM-driven selectable styling
- [ ] Widget-level style override: per-instance color/size
- [ ] State-based styling: hover/active/focused/disabled selectors
- [ ] Inheritance model: style propagation through widget tree
- [ ] Custom theme editor: in-app theme tweaking and export

## v0.6.0 -- Advanced Widgets

- [ ] Tables: row/column data display with headers and sorting
- [ ] Tree View: expandable hierarchical list with drag-drop reorder
- [ ] Menu Bar: top-level menus with submenus and keyboard shortcuts
- [ ] Context Menu: right-click popup with action dispatch
- [ ] Tooltips: hover-delayed overlay text
- [ ] Progress Bar: determinate and indeterminate modes
- [ ] Combo Box: editable text field with dropdown suggestions

## v0.7.0 -- Layout Enhancements

- [ ] Flex layout: flex-grow/shrink, justify-content, align-items
- [ ] Grid layout: fixed/auto columns, spanning cells, gap control
- [ ] Constraint-based layout: minimum/maximum width and height
- [ ] Virtual scrolling: viewport-aware lazy widget allocation
- [ ] Split panes: resizable drag-bar between children

## v0.8.0 -- Animations

- [ ] Tween system: animated transitions for position, size, color, opacity
- [ ] Easing functions: linear, ease-in, ease-out, bounce, elastic
- [ ] Animation timeline: keyframe-based animation sequences
- [ ] Layout transitions: animate addition/removal/reorder of children

## v0.9.0 -- Backend Expansion

- [ ] Vulkan render backend: alternative to OpenGL via xiom.vulkan
- [ ] DirectX render backend: Windows-native rendering path
- [ ] Headless render target: render-to-texture for testing and caching
- [ ] Metal render backend: macOS-native rendering path
- [ ] WebGPU render backend: browser/wasm target

## v1.0.0 -- Production Release

- [ ] Full test coverage (80%+ on core logic)
- [ ] API stability freeze and deprecation policy
- [ ] Performance benchmarks: layout, rendering, memory
- [ ] Documentation: tutorial, API reference, migration guide
- [ ] Package registry: xiom install xiom.ui
- [ ] CI/CD: automated testing across platforms (Windows, Linux, macOS)
- [ ] Examples: counter, form, layout, image viewer, text editor demos

## Beyond v1.0

- [ ] Drag & Drop: drag sources, drop targets, clipboard serialization
- [ ] Accessibility: ARIA-like metadata, screen reader hooks
- [ ] IME support: composition string handling for CJK input
- [ ] Undo/Redo: command pattern for reversible widget mutations
- [ ] Localization: string tables, RTL layout support
- [ ] Plotting: 2D chart widget (line, bar, scatter, pie)
- [ ] Canvas widget: immediate-mode 2D drawing surface
- [ ] WebAssembly target: xiom.ui running in browsers
- [ ] Mobile touch: gesture recognition, soft keyboard integration
