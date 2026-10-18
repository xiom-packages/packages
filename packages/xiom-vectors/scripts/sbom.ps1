# SBOM + security gate (M-S4): emits out/sbom.json (components + per-module
# SHA-256) and fails when `unsafe` appears anywhere in src/.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "out"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$stdlibPin = (& git -C "E:\xiom-lang\stdlib" rev-parse --short HEAD 2>$null)
# Lane-local compiler first (dev-env convention); the global install is the
# fallback only when XIOM_COMPILER is unset (pre-2026-10-16 this recorded
# whatever the global install was, not the pinned toolchain).
$comp = $env:XIOM_COMPILER
if (-not $comp) { $comp = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe" }
$compiler = (& $comp --version 2>$null | Select-Object -First 1)
$appVersion = (Get-Content (Join-Path $root "VERSION") -ErrorAction SilentlyContinue | Select-Object -First 1)

$srcRoot = Join-Path $root "src"
$hits = Get-ChildItem -Recurse -File -Filter *.xi -Path $srcRoot | Select-String -SimpleMatch "unsafe"
if ($hits) {
  Write-Host "sbom: FAILED -- unsafe usage found in src/:"
  $hits | ForEach-Object { Write-Host ("  " + $_.Path + ":" + $_.LineNumber) }
  exit 1
}

$files = @(Get-ChildItem -Recurse -File -Filter *.xi -Path $srcRoot | Sort-Object FullName)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("{")
$lines.Add('  "project": "xiom.xvector",')
$lines.Add('  "version": "' + $appVersion + '",')
$lines.Add('  "compiler": "' + $compiler + '",')
$lines.Add('  "stdlib_pin": "' + $stdlibPin + '",')
$lines.Add('  "registry_dependencies": [],')
$lines.Add('  "unsafe_blocks_in_src": 0,')
$lines.Add('  "modules": [')
$i = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1).Replace('\','/')
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower()
  $comma = ","
  if ($i -eq $files.Count - 1) { $comma = "" }
  $lines.Add('    { "path": "' + $rel + '", "sha256": "' + $hash + '" }' + $comma)
  $i = $i + 1
}
$lines.Add("  ]")
$lines.Add("}")
Set-Content -LiteralPath (Join-Path $out "sbom.json") -Value $lines -Encoding ascii
Write-Host ("sbom: OK -- " + $files.Count + " modules, unsafe=0, compiler " + $compiler)
exit 0
