<#
.SYNOPSIS
  Build the xiom-vulkan bridge and XIOM target (demo / test).

.DESCRIPTION
  Four-step pipeline:
    1. Compile GLSL shaders to SPIR-V via glslc
    2. Generate bridge/xvk_shaders_generated.h with uint32 SPIR-V arrays
    3. Compile the C bridge to an object file
     4. Build the XIOM target with xiomc (demo2d, demo3d, test, particles, shapes, or cubes)

.PARAMETER Target
  Which XIOM entry to build: "demo2d" (default), "demo3d", "test", "particles", "shapes", or "cubes".

.PARAMETER GlfwDir
  Path to GLFW installation root.  Overrides $env:GLFW_DIR.
  Must contain include/ and a lib directory with glfw3.lib.

.PARAMETER GlfwLib
  Path to the directory containing glfw3.lib.
  Default: $GlfwDir\lib-vc2022

.PARAMETER Clang
  Path to clang executable.
  Defaults to "C:\Program Files\LLVM\bin\clang.exe" then "clang" on PATH.

.PARAMETER Run
  If set, runs the produced executable after a successful build
  (for demos) or passes --run for the test target.

.EXAMPLE
  # Build 2D demo (default)
  .\build.ps1

  # Build and run 3D demo
  .\build.ps1 -Target demo3d -Run

  # Build offscreen test
  .\build.ps1 -Target test

  # GPU particle fountain
  .\build.ps1 -Target particles -Run

  # Animated 2D quads + triangle
  .\build.ps1 -Target shapes -Run

  # Field of spinning 3D cubes
  .\build.ps1 -Target cubes -Run

  # Custom GLFW path
  .\build.ps1 -GlfwDir C:\dev\glfw-3.4 -GlfwLib C:\dev\glfw-3.4\lib-vc2022
#>

param(
    [ValidateSet('demo2d', 'demo3d', 'test', 'particles', 'shapes', 'cubes', 'vertex_buffer', 'compute', 'models', 'sprites', 'ui', 'viewport')]
    [string]$Target = 'demo2d',

    [string]$GlfwDir = '',

    [string]$GlfwLib = '',

    [string]$Clang = '',

    [switch]$Run
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------
$RootDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BridgeDir  = Join-Path $RootDir 'bridge'
$ShaderDir  = Join-Path $BridgeDir 'shaders'
$SpvDir     = Join-Path $BridgeDir 'spv'
$GenHeader  = Join-Path $BridgeDir 'xvk_shaders_generated.h'

# ------------------------------------------------------------------
# Resolve clang
# ------------------------------------------------------------------
function Find-Clang {
    if ($Clang -and (Test-Path $Clang)) { return $Clang }
    $candidates = @(
        $Clang
        'C:\Program Files\LLVM\bin\clang.exe'
        'C:\Program Files\LLVM\bin\clang-cl.exe'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $fromPath = Get-Command 'clang.exe' -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    throw "clang not found. Install LLVM or set -Clang."
}

# ------------------------------------------------------------------
# Resolve Vulkan SDK
# ------------------------------------------------------------------
$VulkanSdk = $env:VULKAN_SDK
if (-not $VulkanSdk) {
    throw "VULKAN_SDK environment variable is not set.  Install the Vulkan SDK from https://vulkan.lunarg.com/"
}
if (-not (Test-Path $VulkanSdk)) {
    throw "VULKAN_SDK path '$VulkanSdk' does not exist."
}
$VkInclude = Join-Path $VulkanSdk 'Include'
$VkLib     = Join-Path $VulkanSdk 'Lib'
if (-not (Test-Path $VkInclude)) {
    throw "Vulkan SDK include directory not found at '$VkInclude'"
}

# glslc
$Glslc = Join-Path $VulkanSdk 'Bin\glslc.exe'
if (-not (Test-Path $Glslc)) {
    $Glslc = (Get-Command 'glslc' -ErrorAction SilentlyContinue).Source
}
if (-not $Glslc) {
    throw "glslc not found at '$env:VULKAN_SDK\Bin\glslc.exe' nor on PATH."
}

Write-Host "[build] Vulkan SDK: $VulkanSdk"
Write-Host "[build] glslc:      $Glslc"

# ------------------------------------------------------------------
# Resolve GLFW
# ------------------------------------------------------------------
if (-not $GlfwDir) { $GlfwDir = $env:GLFW_DIR }
if (-not $GlfwDir) {
    throw "GLFW_DIR environment variable or -GlfwDir parameter is required.  Download GLFW 3.4 from https://www.glfw.org/.  Set GLFW_DIR to the root directory (the folder containing include/ and lib-vc2022/)."
}
$GlfwDir = $GlfwDir.TrimEnd('\', '/')
if (-not (Test-Path $GlfwDir)) {
    throw "GLFW directory '$GlfwDir' does not exist."
}

# Auto-correct: if GLFW_DIR was set to a lib subfolder (common mistake),
# walk up to the real root.
$GlfwInclude = Join-Path $GlfwDir 'include'
if (-not (Test-Path $GlfwInclude)) {
    $parent = Split-Path -Parent $GlfwDir
    $parentInclude = Join-Path $parent 'include'
    if ($parent -and (Test-Path $parentInclude)) {
        Write-Warning "[build] GLFW_DIR was set to '$GlfwDir' but 'include/' is at '$parent'. Auto-correcting to '$parent'."
        $GlfwDir = $parent
        $GlfwInclude = $parentInclude
    }
}
if (-not (Test-Path $GlfwInclude)) {
    throw "GLFW include directory not found.  GLFW_DIR is '$GlfwDir' -- expected '$GlfwDir\include\GLFW\glfw3.h' to exist."
}

if (-not $GlfwLib) {
    # Common layouts: lib-vc2022, lib, lib-vc2021, etc.
    $candidates = @(
        Join-Path $GlfwDir 'lib-vc2022'
        Join-Path $GlfwDir 'lib'
        Join-Path $GlfwDir 'lib-vc2021'
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'glfw3.lib')) {
            $GlfwLib = $c
            break
        }
    }
}
if (-not $GlfwLib -or -not (Test-Path (Join-Path $GlfwLib 'glfw3.lib'))) {
    throw "glfw3.lib not found.  Set -GlfwLib to the directory containing glfw3.lib (e.g. '$GlfwDir\lib-vc2022')."
}

Write-Host "[build] GLFW dir:   $GlfwDir"
Write-Host "[build] GLFW lib:   $GlfwLib"

$ClangExe = Find-Clang
Write-Host "[build] clang:      $ClangExe"

# ------------------------------------------------------------------
# Target mapping
# ------------------------------------------------------------------
$TargetMap = @{
    demo2d = @{
        entry = 'examples/demo_2d.xi'
        out   = 'demo_2d'
    }
    demo3d = @{
        entry = 'examples/demo_3d.xi'
        out   = 'demo_3d'
    }
    test   = @{
        entry = 'tests/test_vulkan.xi'
        out   = 'test_vulkan'
    }
    particles = @{
        entry = 'examples/demo_particles.xi'
        out   = 'demo_particles'
    }
    shapes = @{
        entry = 'examples/demo_shapes.xi'
        out   = 'demo_shapes'
    }
    cubes = @{
        entry = 'examples/demo_cubes.xi'
        out   = 'demo_cubes'
    }
    vertex_buffer = @{
        entry = 'examples/demo_vertex_buffer.xi'
        out   = 'demo_vertex_buffer'
    }
    compute = @{
        entry = 'examples/demo_compute.xi'
        out   = 'demo_compute'
    }
    models = @{
        entry = 'examples/demo_models.xi'
        out   = 'demo_models'
    }
    sprites = @{
        entry = 'examples/demo_sprites.xi'
        out   = 'demo_sprites'
    }
    ui = @{
        entry = 'examples/demo_ui.xi'
        out   = 'demo_ui'
    }
    viewport = @{
        entry = 'examples/demo_viewport.xi'
        out   = 'demo_viewport'
    }
    ui = @{
        entry = 'examples/ui/ui_demo.xi'
        out   = 'ui_demo'
    }
}
$t = $TargetMap[$Target]
$EntryFile = Join-Path $RootDir $t.entry
$OutName   = $t.out
$OutExe    = Join-Path $RootDir "$OutName.exe"

# ------------------------------------------------------------------
# STEP 1  —  Compile shaders with glslc
# ------------------------------------------------------------------
Write-Host "`n=== STEP 1: Compile GLSL shaders to SPIR-V ==="

if (-not (Test-Path $SpvDir)) {
    New-Item -ItemType Directory -Path $SpvDir -Force | Out-Null
}

$ShaderFiles = @(
    @{ src = Join-Path $ShaderDir 'triangle.vert'; spv = Join-Path $SpvDir 'triangle_vert.spv'; name='triangle_vert' }
    @{ src = Join-Path $ShaderDir 'triangle.frag'; spv = Join-Path $SpvDir 'triangle_frag.spv'; name='triangle_frag' }
    @{ src = Join-Path $ShaderDir 'cube.vert';     spv = Join-Path $SpvDir 'cube_vert.spv';     name='cube_vert' }
    @{ src = Join-Path $ShaderDir 'cube.frag';     spv = Join-Path $SpvDir 'cube_frag.spv';     name='cube_frag' }
    @{ src = Join-Path $ShaderDir 'quad.vert';     spv = Join-Path $SpvDir 'quad_vert.spv';     name='quad_vert' }
    @{ src = Join-Path $ShaderDir 'quad.frag';     spv = Join-Path $SpvDir 'quad_frag.spv';     name='quad_frag' }
    @{ src = Join-Path $ShaderDir 'particle.vert'; spv = Join-Path $SpvDir 'particle_vert.spv'; name='particle_vert' }
    @{ src = Join-Path $ShaderDir 'particle.frag'; spv = Join-Path $SpvDir 'particle_frag.spv'; name='particle_frag' }
    # Phase 1 — new shaders
    @{ src = Join-Path $ShaderDir 'particle_render.vert'; spv = Join-Path $SpvDir 'particle_render_vert.spv'; name='particle_render_vert' }
    @{ src = Join-Path $ShaderDir 'particle_render.frag'; spv = Join-Path $SpvDir 'particle_render_frag.spv'; name='particle_render_frag' }
    @{ src = Join-Path $ShaderDir 'compute_particles.comp'; spv = Join-Path $SpvDir 'compute_particles.spv'; name='compute_particles'; extra='-fshader-stage=compute' }
    @{ src = Join-Path $ShaderDir 'texture_quad.vert'; spv = Join-Path $SpvDir 'texture_quad_vert.spv'; name='texture_quad_vert' }
    @{ src = Join-Path $ShaderDir 'texture_quad.frag'; spv = Join-Path $SpvDir 'texture_quad_frag.spv'; name='texture_quad_frag' }
    @{ src = Join-Path $ShaderDir 'uniform_cube.vert'; spv = Join-Path $SpvDir 'uniform_cube_vert.spv'; name='uniform_cube_vert' }
    @{ src = Join-Path $ShaderDir 'uniform_cube.frag'; spv = Join-Path $SpvDir 'uniform_cube_frag.spv'; name='uniform_cube_frag' }
)

$ShaderData = @()  # will hold name, spv_path, words, byte_len

foreach ($sf in $ShaderFiles) {
    Write-Host "  glslc: $($sf.name)..."
    $spvFile = $sf.spv
    $extraArgs = @()
    if ($sf.extra) { $extraArgs = $sf.extra -split '\s+' }
    & $Glslc @extraArgs -o $spvFile $sf.src
    if ($LASTEXITCODE -ne 0) {
        throw "glslc failed for $($sf.src)"
    }

    # Verify file size is multiple of 4
    $fi = Get-Item $spvFile
    if ($fi.Length -eq 0) {
        throw "SPIR-V file for $($sf.name) is empty!"
    }
    if ($fi.Length % 4 -ne 0) {
        throw "SPIR-V file for $($sf.name) has length $($fi.Length) which is not a multiple of 4!"
    }
    $byteLen = [int]$fi.Length

    # Read binary and convert to uint32 words (little-endian)
    $bytes = [System.IO.File]::ReadAllBytes($spvFile)
    $words = @()
    for ($i = 0; $i -lt $bytes.Length; $i += 4) {
        $w  = [int]$bytes[$i]
        $w += [int]$bytes[$i+1] -shl 8
        $w += [int]$bytes[$i+2] -shl 16
        $w += [int]$bytes[$i+3] -shl 24
        $words += "0x{0:X8}u" -f $w
    }

    $ShaderData += @{
        name    = $sf.name
        words   = $words
        byteLen = $byteLen
    }
    Write-Host "    -> $($fi.Length) bytes, $($words.Count) words"
}

# ------------------------------------------------------------------
# STEP 2  —  Generate xvk_shaders_generated.h
# ------------------------------------------------------------------
Write-Host "`n=== STEP 2: Generate $GenHeader ==="

# Mapping from our internal names to the EXACT symbols the bridge expects
$SymbolNames = @{
    triangle_vert = 'xvk_triangle_vert_spv'
    triangle_frag = 'xvk_triangle_frag_spv'
    cube_vert     = 'xvk_cube_vert_spv'
    cube_frag     = 'xvk_cube_frag_spv'
    quad_vert     = 'xvk_quad_vert_spv'
    quad_frag     = 'xvk_quad_frag_spv'
    particle_vert = 'xvk_particle_vert_spv'
    particle_frag = 'xvk_particle_frag_spv'
    particle_render_vert = 'xvk_particle_render_vert_spv'
    particle_render_frag = 'xvk_particle_render_frag_spv'
    compute_particles = 'xvk_compute_particles_spv'
    texture_quad_vert = 'xvk_texture_quad_vert_spv'
    texture_quad_frag = 'xvk_texture_quad_frag_spv'
    uniform_cube_vert = 'xvk_uniform_cube_vert_spv'
    uniform_cube_frag = 'xvk_uniform_cube_frag_spv'
}

$lines = @(
    '// AUTO-GENERATED — do not edit',
    '#ifndef XVK_SHADERS_GENERATED_H_',
    '#define XVK_SHADERS_GENERATED_H_',
    ''
)

foreach ($sd in $ShaderData) {
    $sym  = $SymbolNames[$sd.name]
    $lenSym = $sym + '_len'
    $wordsStr = $sd.words -join ', '
    $lines += "const unsigned int ${sym}[] = { $wordsStr };"
    $lines += "const unsigned int ${lenSym} = $($sd.byteLen);"
    $lines += ''
}

$lines += '#endif /* XVK_SHADERS_GENERATED_H_ */'
$lines += ''

$content = $lines -join "`r`n"
[System.IO.File]::WriteAllText($GenHeader, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "  Wrote $($ShaderData.Count) shader arrays to $GenHeader"

# ------------------------------------------------------------------
# STEP 3  —  Compile C bridge to object file
# ------------------------------------------------------------------
Write-Host "`n=== STEP 3: Compile C bridge ==="

$BridgeSrc  = Join-Path $BridgeDir 'xiom_vk_bridge.c'
$BridgeObj  = Join-Path $BridgeDir 'xiom_vk_bridge.obj'
$PrebuiltObj = Join-Path $BridgeDir 'xvk_bridge.obj'

# If the prebuilt .obj is newer than all bridge source files, reuse it.
# Otherwise recompile from source.
$needRebuild = $true
if (Test-Path $PrebuiltObj) {
    $objTime = (Get-Item $PrebuiltObj).LastWriteTime
    $srcTime = (Get-Item $BridgeSrc).LastWriteTime
    $hdrTime = (Get-Item (Join-Path $BridgeDir 'xvk_shaders_generated.h')).LastWriteTime
    $allSrcNewer = ($srcTime -gt $objTime) -or ($hdrTime -gt $objTime)
    # Also check any bridge .c module files
    $modFiles = Get-ChildItem (Join-Path $BridgeDir '*.c') -EA SilentlyContinue | Where-Object { $_.LastWriteTime -gt $objTime }
    if (-not $allSrcNewer -and -not $modFiles) {
        Write-Host "  Using prebuilt (up to date): $PrebuiltObj"
        $BridgeObj = $PrebuiltObj
        $needRebuild = $false
    }
}
if ($needRebuild) {
    Remove-Item $BridgeObj -Force -EA SilentlyContinue
    $BridgeObj = Join-Path $BridgeDir 'xvk_bridge.obj'
    $clangArgs = @(
        '-c', $BridgeSrc,
        "-o", $BridgeObj,
        "-I$VkInclude",
        "-I$GlfwInclude",
        '-O2'
    )
    Write-Host "  Recompiling: $ClangExe $($clangArgs -join ' ')"
    & $ClangExe $clangArgs
    if ($LASTEXITCODE -ne 0) {
        throw "clang compilation of bridge failed (exit code $LASTEXITCODE)"
    }
}
Write-Host "  -> $BridgeObj"

# ------------------------------------------------------------------
# STEP 4  —  Build XIOM target with xiomc
# ------------------------------------------------------------------
Write-Host "`n=== STEP 4: Build XIOM target ($Target) ==="

# Source files to pass to xiomc
$XiFiles = @(
    $EntryFile
    (Join-Path $RootDir 'vulkan.xi')
    (Join-Path $RootDir 'src/wrapper.xi')
)

# Use xiomc directly since it's installed on PATH.
# Fall back to cargo if xiomc is not available.
$XiomcExe = Get-Command 'xiomc' -ErrorAction SilentlyContinue
if (-not $XiomcExe) {
    $XiomcExe = 'cargo'
    $XiomcArgs = @('run', '-p', 'xiomc', '--')
} else {
    $XiomcExe = $XiomcExe.Source
    $XiomcArgs = @()
}

$XiomcArgs += @(
    '-o', $OutExe
)

$XiomcArgs += $XiFiles
$XiomcArgs += @('--c-source', $BridgeObj)
# NOTE: xiom_runtime.c is NOT passed — xiomc v0.47.7 auto-injects
# runtime symbols; passing it again causes duplicate symbol errors.
$XiomcArgs += @('--link', 'vulkan-1')
$XiomcArgs += @('--link', 'glfw3')
$XiomcArgs += @('--link', 'gdi32')
$XiomcArgs += @('--link', 'user32')
$XiomcArgs += @('--link', 'kernel32')
$XiomcArgs += @('--link', 'shell32')
$XiomcArgs += @('--link', 'ole32')
$XiomcArgs += @('--link-path', $VkLib)
$XiomcArgs += @('--link-path', $GlfwLib)

if ($Target -eq 'test') {
    $XiomcArgs += '--run'
}

$cmdline = "$XiomcExe $($XiomcArgs -join ' ')"
Write-Host "  $cmdline"
$proc = Start-Process -FilePath $XiomcExe -ArgumentList $XiomcArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "xiomc build failed (exit code $($proc.ExitCode))"
}

Write-Host "[build] SUCCESS: $OutExe"

# ------------------------------------------------------------------
# Run (optional)
# ------------------------------------------------------------------
if ($Run) {
    if ($Target -eq 'test') {
        # Test already ran above via --run; just report
        Write-Host "[build] Test completed (exit code $LASTEXITCODE)"
    } else {
        Write-Host "[build] Running $OutExe ...`n"
        & $OutExe
    }
}
