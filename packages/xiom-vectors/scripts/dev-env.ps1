# XIOM XVECTOR dev environment -- dot-source in every terminal:
#   . .\scripts\dev-env.ps1
#
# VERSION POLICY (owner decision, inherited from PULSE): XVECTOR tracks the
# LATEST compiler / stdlib / packages to harden the ecosystem by real-world
# use. Record the exact versions and lane hashes in SESSION.md at every wrap.
#
# PACKAGES POLICY (owner directive 2026-10-17): always run against the
# NEWEST registry package versions -- `xiom pkg info <pkg>` for each
# consumed package (xiom.wal/metrics/rate/http/vectors/ann), then install
# the latest into THIS XIOM_HOME and the WSL ~/.xvector-home before the
# batteries. Bug fixes land there first; our feedback drives the hardening.
#
# ISOLATION (2026-10-10): concurrent sessions on the build machine had the
# shared toolchain state deleted mid-battery (the global
# %LOCALAPPDATA%\xiom\packages home, and parts of %LOCALAPPDATA%\xiom.new
# down to the process-locked files); see the bus incident
# REL-20261010-1835-xvector. The lane therefore pins its OWN toolchain and
# package home, which no other session touches:
#   compiler  out\toolchain\bin\xiom.exe (lane-local v0.64.3; falls back to
#             %LOCALAPPDATA%\xiom.new\bin\xiom.exe when the lane copy is
#             absent)
#   packages  out\xiom-home (lane-local XIOM_HOME; xiom pkg installs of
#             xiom.wal 0.1.0 + xiom.metrics 0.2.0 + xiom.rate 0.2.0, trust
#             pinned from the registry key)
#   stdlib    E:\xiom-lang\stdlib (stdlib-lane checkout = latest lane work)
#
# XIOM_RUNTIME_DIR is retired since v0.64.0: release R65 makes the installed
# compiler link lib\runtime and lib\xiom without overrides (verified env-free
# by PULSE 2026-10-05).
#
# PATH warning: a v0.62.3 staging dir shadows xiom.new in PATH -- always set
# XIOM_COMPILER explicitly instead of relying on `xiom` from PATH.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

$laneCompiler = Join-Path $repoRoot "out\toolchain\bin\xiom.exe"
if (Test-Path -LiteralPath $laneCompiler) {
    $env:XIOM_COMPILER = $laneCompiler
} else {
    $env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
}
$env:XIOM_STDLIB = "E:\xiom-lang\stdlib"
$env:XIOM_HOME   = Join-Path $repoRoot "out\xiom-home"
New-Item -ItemType Directory -Force -Path $env:XIOM_HOME | Out-Null
Remove-Item Env:XIOM_RUNTIME_DIR -ErrorAction SilentlyContinue   # retired

$missing = @()
if (-not (Test-Path -LiteralPath $env:XIOM_COMPILER)) { $missing += "XIOM_COMPILER ($env:XIOM_COMPILER)" }
if (-not (Test-Path -LiteralPath $env:XIOM_STDLIB))   { $missing += "XIOM_STDLIB   ($env:XIOM_STDLIB)" }

if ($missing.Count -gt 0) {
    Write-Warning "dev-env: missing toolchain paths:"
    $missing | ForEach-Object { Write-Warning "  $_" }
    return
}

$ver = (& $env:XIOM_COMPILER --version 2>&1 | Select-Object -First 1)
Write-Host "dev-env: $ver"
Write-Host "dev-env: XIOM_STDLIB = $env:XIOM_STDLIB"
Write-Host "dev-env: XIOM_HOME   = $env:XIOM_HOME (lane-local)"
Write-Host "dev-env: XIOM_RUNTIME_DIR retired (v0.64.1 R65 install-layout fix)"
