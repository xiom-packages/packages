# XIOM Vulkan Showcase — Production Roadmap

A game-style GUI application showcasing the full Vulkan 1.3 API
through XIOM bindings. 4K responsive, modular, expandable.

## Architecture

```
examples/demo-vulkan/
├── main.xi                    Entry point, window, main loop
├── theme.xi                   Colors, spacing, fonts
├── panels/
│   ├── topbar.xi              Menu bar with dropdowns
│   ├── sidebar_left.xi        Scene browser / asset list
│   ├── sidebar_right.xi       Property inspector, tabs, controls
│   ├── viewport.xi            3D rendering viewport
│   └── statusbar.xi           FPS, frame time, GPU info
├── widgets/
│   ├── button.xi              Interactive button (3 states)
│   ├── label.xi               Text label
│   ├── slider.xi              Draggable slider
│   ├── panel.xi               Bordered container
│   └── tab.xi                 Tab container
├── scenes/
│   ├── scene_triangle.xi      Hello triangle (render pass 1)
│   ├── scene_cubes.xi         Rotating 3D cube grid
│   ├── scene_particles.xi     GPU particle fountain
│   ├── scene_sprites.xi       2D sprite sheet
│   └── scene_mesh.xi          OBJ mesh loader + render
├── resources/
│   ├── fonts/                 Font files (built-in used)
│   └── textures/              Procedurally generated textures
└── VULKAN_SHOWCASE.md         This file
```

## Phase Plan

### Phase 1: Core Scaffolding ✅
- [x] Folder structure
- [ ] theme.xi — color palette, spacing, font definitions
- [ ] widgets/button.xi — interactive button with hover/press/normal
- [ ] widgets/label.xi — text label
- [ ] widgets/slider.xi — draggable slider
- [ ] widgets/panel.xi — bordered container
- [ ] main.xi — window, main loop, FPS tracking

### Phase 2: Layout Panels
- [ ] panels/topbar.xi
- [ ] panels/viewport.xi
- [ ] panels/sidebar_left.xi
- [ ] panels/sidebar_right.xi
- [ ] panels/statusbar.xi

### Phase 3: Demo Scenes
- [ ] scenes/scene_triangle.xi
- [ ] scenes/scene_cubes.xi
- [ ] scenes/scene_particles.xi
- [ ] scenes/scene_sprites.xi

### Phase 4: Polish
- [ ] 4K responsive scaling
- [ ] Fullscreen toggle
- [ ] Animated transitions
- [ ] GPU stats overlay

## Color Theme — "Void Neon"

| Token | RGB | Usage |
|-------|-----|-------|
| bg-void | (0.04, 0.04, 0.06) | Main background |
| panel-bg | (0.08, 0.08, 0.11) | Panel fill |
| panel-border | (0.14, 0.44, 0.60) | Panel border (accent blue) |
| btn-normal | (0.12, 0.14, 0.18) | Button default |
| btn-hover | (0.18, 0.22, 0.28) | Button hover |
| btn-press | (0.07, 0.08, 0.11) | Button pressed |
| accent-1 | (0.16, 0.64, 0.88) | Primary accent (cyan-blue) |
| accent-2 | (0.88, 0.55, 0.16) | Secondary (amber) |
| accent-3 | (0.16, 0.88, 0.55) | Success (green) |
| accent-4 | (0.88, 0.16, 0.32) | Danger (red) |
| text-primary | (0.85, 0.85, 0.88) | Main text |
| text-muted | (0.48, 0.50, 0.55) | Secondary text |
