<#
.SYNOPSIS
  Build and run any xiom-vulkan demo with a single command.
  Uses the INSTALLED xiomc (must be on PATH).
.DESCRIPTION
  One-step: compiles GLSL shaders, generates SPIR-V header,
  compiles C bridge, builds XIOM source, links Vulkan/GLFW, and
  optionally runs the result.

.PARAMETER Demo
  Which demo to build: demo2d, demo3d, particles, shapes, cubes,
  vertex_buffer, compute, models, sprites, ui, viewport, test.

.PARAMETER NoRun
  Build only, don't run.

.EXAMPLE
  .\run.ps1 demo2d
  .\run.ps1 particles
  .\run.ps1 test -NoRun
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('demo2d','demo3d','particles','shapes','cubes',
                 'vertex_buffer','compute','models','sprites','ui','viewport','test')]
    [string]$Demo,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Bridge  = Join-Path $Root 'bridge'
$Shader  = Join-Path $Bridge 'shaders'
$SpvDir  = Join-Path $Bridge 'spv'
$GenHdr  = Join-Path $Bridge 'xvk_shaders_generated.h'

# ---- Resolve toolchain ----
$Glslc  = Join-Path $env:VULKAN_SDK 'Bin\glslc.exe'
$Clang  = if (Test-Path 'C:\Program Files\LLVM\bin\clang.exe') { 'C:\Program Files\LLVM\bin\clang.exe' } else { 'clang' }
$Xiomc  = (Get-Command 'xiomc' -ErrorAction Stop).Source

# ---- Verify env ----
if (-not $env:VULKAN_SDK)   { throw 'VULKAN_SDK not set' }
if (-not $env:GLFW_DIR)     { throw 'GLFW_DIR not set. Download GLFW 3.4 from glfw.org' }
if (-not (Test-Path $Glslc)){ throw "glslc not found at $Glslc" }

$VkInc = Join-Path $env:VULKAN_SDK 'Include'
$VkLib = Join-Path $env:VULKAN_SDK 'Lib'
$GlfwInc = Join-Path $env:GLFW_DIR 'include'
$GlfwLib = Join-Path $env:GLFW_DIR 'lib-vc2022'

# ---- Target mapping ----
$Targets = @{
    demo2d        = @{ src='examples/demo_2d.xi';        out='demo_2d.exe' }
    demo3d        = @{ src='examples/demo_3d.xi';        out='demo_3d.exe' }
    particles     = @{ src='examples/demo_particles.xi';  out='demo_particles.exe' }
    shapes        = @{ src='examples/demo_shapes.xi';     out='demo_shapes.exe' }
    cubes         = @{ src='examples/demo_cubes.xi';      out='demo_cubes.exe' }
    vertex_buffer = @{ src='examples/demo_vertex_buffer.xi'; out='demo_vertex_buffer.exe' }
    compute       = @{ src='examples/demo_compute.xi';    out='demo_compute.exe' }
    models        = @{ src='examples/demo_models.xi';     out='demo_models.exe' }
    sprites       = @{ src='examples/demo_sprites.xi';    out='demo_sprites.exe' }
    ui            = @{ src='examples/demo_ui.xi';         out='demo_ui.exe' }
    viewport      = @{ src='examples/demo_viewport.xi';   out='demo_viewport.exe' }
    test          = @{ src='tests/test_vulkan.xi';        out='test_vulkan.exe' }
}
$t = $Targets[$Demo]

# ---- STEP 1: GLSL -> SPIR-V ----
Write-Host "[1/4] Compiling shaders..." -ForegroundColor Cyan
if (-not (Test-Path $SpvDir)) { New-Item -ItemType Directory -Path $SpvDir -Force | Out-Null }
$shaderFiles = @(
    @{ src = "$Shader\triangle.vert";  dst = "$SpvDir\triangle_vert.spv"  }
    @{ src = "$Shader\triangle.frag";  dst = "$SpvDir\triangle_frag.spv"  }
    @{ src = "$Shader\cube.vert";      dst = "$SpvDir\cube_vert.spv"      }
    @{ src = "$Shader\cube.frag";      dst = "$SpvDir\cube_frag.spv"      }
    @{ src = "$Shader\quad.vert";      dst = "$SpvDir\quad_vert.spv"      }
    @{ src = "$Shader\quad.frag";      dst = "$SpvDir\quad_frag.spv"      }
    @{ src = "$Shader\particle.vert";  dst = "$SpvDir\particle_vert.spv"  }
    @{ src = "$Shader\particle.frag";  dst = "$SpvDir\particle_frag.spv"  }
    @{ src = "$Shader\particle_render.vert"; dst = "$SpvDir\particle_render_vert.spv" }
    @{ src = "$Shader\particle_render.frag"; dst = "$SpvDir\particle_render_frag.spv" }
    @{ src = "$Shader\texture_quad.vert";    dst = "$SpvDir\texture_quad_vert.spv"    }
    @{ src = "$Shader\texture_quad.frag";    dst = "$SpvDir\texture_quad_frag.spv"    }
    @{ src = "$Shader\uniform_cube.vert";    dst = "$SpvDir\uniform_cube_vert.spv"    }
    @{ src = "$Shader\uniform_cube.frag";    dst = "$SpvDir\uniform_cube_frag.spv"    }
    @{ src = "$Shader\compute_particles.comp"; dst = "$SpvDir\compute_particles.spv"; extra='-fshader-stage=compute' }
)
foreach ($sf in $shaderFiles) {
    $rebuild = $true
    if (Test-Path $sf.dst) {
        $srcTime = (Get-Item $sf.src).LastWriteTime
        $dstTime = (Get-Item $sf.dst).LastWriteTime
        if ($dstTime -gt $srcTime) { $rebuild = $false }
    }
    if ($rebuild) {
        $args = @('-o', $sf.dst)
        if ($sf.extra) { $args += $sf.extra }
        $args += $sf.src
        & $Glslc @args 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "glslc failed for $($sf.src)" }
    }
}

# ---- STEP 2: Generate SPIR-V header ----
Write-Host "[2/4] Generating shader header..." -ForegroundColor Cyan
$symbols = @{
    triangle_vert='xvk_triangle_vert_spv'; triangle_frag='xvk_triangle_frag_spv'
    cube_vert='xvk_cube_vert_spv'; cube_frag='xvk_cube_frag_spv'
    quad_vert='xvk_quad_vert_spv'; quad_frag='xvk_quad_frag_spv'
    particle_vert='xvk_particle_vert_spv'; particle_frag='xvk_particle_frag_spv'
    particle_render_vert='xvk_particle_render_vert_spv'; particle_render_frag='xvk_particle_render_frag_spv'
    texture_quad_vert='xvk_texture_quad_vert_spv'; texture_quad_frag='xvk_texture_quad_frag_spv'
    uniform_cube_vert='xvk_uniform_cube_vert_spv'; uniform_cube_frag='xvk_uniform_cube_frag_spv'
    compute_particles='xvk_compute_particles_spv'
}
$lines = @('#ifndef XVK_SHADERS_GENERATED_H_', '#define XVK_SHADERS_GENERATED_H_', '')
foreach ($name in $symbols.Keys) {
    $spvFile = Join-Path $SpvDir "$name.spv"
    if (-not (Test-Path $spvFile)) { Write-Warning "Missing SPIR-V: $spvFile"; continue }
    $bytes = [IO.File]::ReadAllBytes($spvFile)
    $words = for ($i=0; $i -lt $bytes.Length; $i+=4) {
        "0x{0:X8}" -f ($bytes[$i] -bor ($bytes[$i+1] -shl 8) -bor ($bytes[$i+2] -shl 16) -bor ($bytes[$i+3] -shl 24))
    }
    $sym = $symbols[$name]
    $lines += "const unsigned int ${sym}[] = { $($words -join ', ') };"
    $lines += "const unsigned int ${sym}_len = $($bytes.Length);"
    $lines += ''
}
$lines += '#endif'
[IO.File]::WriteAllText($GenHdr, ($lines -join "`r`n"), [Text.UTF8Encoding]::new($false))

# ---- STEP 3: Compile C bridge ----
Write-Host "[3/4] Compiling C bridge..." -ForegroundColor Cyan
$BridgeSrc = Join-Path $Bridge 'xiom_vk_bridge.c'
$BridgeObj = Join-Path $Bridge 'xvk_bridge.obj'
$needRebuild = $true
if (Test-Path $BridgeObj) {
    $srcTime = (Get-Item $BridgeSrc).LastWriteTime
    $objTime = (Get-Item $BridgeObj).LastWriteTime
    $hdrTime = (Get-Item $GenHdr).LastWriteTime
    if ($objTime -gt $srcTime -and $objTime -gt $hdrTime) { $needRebuild = $false }
}
if ($needRebuild) {
    & $Clang -c $BridgeSrc -o $BridgeObj "-I$VkInc" "-I$GlfwInc" -O2 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Bridge compilation failed" }
    Write-Host "  -> $((Get-Item $BridgeObj).Length) bytes"
} else {
    Write-Host "  up to date"
}

# ---- STEP 4: Build XIOM + Link + Run ----
Write-Host "[4/4] Building $Demo..." -ForegroundColor Cyan
$outExe = Join-Path $Root $t.out
$src  = Join-Path $Root $t.src
$vk   = Join-Path $Root 'vulkan.xi'
$wrap = Join-Path $Root 'src\wrapper.xi'

# Also include wrapper only for demos that use it (most demos don't; only test uses it via wrapper)
# For simplicity, always include both vulkan.xi and wrapper.xi
$xiomArgs = @(
    '-o', $outExe,
    $src, $vk, $wrap,
    '--c-source', $BridgeObj,
    '--link', 'vulkan-1', '--link', 'glfw3',
    '--link', 'gdi32', '--link', 'user32', '--link', 'kernel32',
    '--link', 'shell32', '--link', 'ole32',
    '--link-path', $VkLib, '--link-path', $GlfwLib
)
if ($Demo -eq 'test') { $xiomArgs += '--run' }

$cmdline = "$Xiomc $($xiomArgs -join ' ')"
Write-Host "  $Xiomc -o $outExe $src vulkan.xi src/wrapper.xi [flags]"
$proc = Start-Process -FilePath $Xiomc -ArgumentList $xiomArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "xiomc failed (exit $($proc.ExitCode))" }
Write-Host "[build] $outExe" -ForegroundColor Green

if (-not $NoRun -and $Demo -ne 'test') {
    Write-Host "[run] Starting $outExe..." -ForegroundColor Green
    & $outExe
}
