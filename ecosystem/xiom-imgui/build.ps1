# xiom-imgui Build Script
# Compiles Dear ImGui + bridge into .obj files, then builds XIOM targets.

param(
    [ValidateSet('build','test','demo')]
    [string]$Target = 'build'
)

$BridgeDir = Join-Path $PSScriptRoot 'bridge'
$VkInc     = "$env:VULKAN_SDK\Include"
$GfInc     = "$env:GLFW_DIR\include"

$ImGuiSrc = @('imgui','imgui_draw','imgui_widgets','imgui_tables',
              'imgui_impl_glfw','imgui_impl_vulkan','imgui_bridge')

if ($Target -eq 'build') {
    foreach ($s in $ImGuiSrc) {
        $cpp = Join-Path $BridgeDir "$s.cpp"
        $obj = Join-Path $BridgeDir "$s.obj"
        if ((Test-Path $obj) -and ((Get-Item $cpp).LastWriteTime -lt (Get-Item $obj).LastWriteTime)) {
            continue  # up to date
        }
        Write-Host "  Compiling $s.cpp..."
        clang++ -c $cpp -o $obj -I$BridgeDir -I$VkInc -I$GfInc `
                -DIMGUI_IMPL_VULKAN_NO_PROTOTYPES -O2
        if ($LASTEXITCODE -ne 0) { throw "Failed: $s" }
    }
    Write-Host "[imgui] All 7 .obj files up to date."
}
elseif ($Target -eq 'test') {
    $xiomArgs = @('-o', 'test_imgui.exe', 'tests/test_imgui.xi', 'imgui.xi')
    foreach ($s in $ImGuiSrc) {
        $xiomArgs += @('--c-source', (Join-Path $BridgeDir "$s.obj"))
    }
    $xiomArgs += @('--link', 'vulkan-1', '--link', 'glfw3', '--link', 'gdi32', '--link', 'user32')
    $xiomArgs += @('--link-path', "$env:VULKAN_SDK\Lib", '--link-path', "$env:GLFW_DIR\lib-vc2022")
    & xiomc @xiomArgs
}
elseif ($Target -eq 'demo') {
    $xiomArgs = @('-o', 'demo_imgui.exe',
        'tests/demo_imgui.xi', 'imgui.xi',
        '../xiom-vulkan/vulkan.xi', '../xiom-vulkan/src/wrapper.xi')
    foreach ($s in $ImGuiSrc) {
        $xiomArgs += @('--c-source', (Join-Path $BridgeDir "$s.obj"))
    }
    $xiomArgs += @('--c-source', (Join-Path $PSScriptRoot '..\xiom-vulkan\bridge\xvk_bridge.obj'))
    $xiomArgs += @('--link', 'vulkan-1', '--link', 'glfw3', '--link', 'gdi32',
        '--link', 'user32', '--link', 'kernel32', '--link', 'shell32',
        '--link', 'ole32', '--link', 'winmm')
    $xiomArgs += @('--link-path', "$env:VULKAN_SDK\Lib",
        '--link-path', "$env:GLFW_DIR\lib-vc2022")
    & xiomc @xiomArgs
}
