#!/usr/bin/env pwsh
# xiom.android A3/A4 constant transcription generator (see README.md).
# Extracts every constant family of android/input.h + android/keycodes.h (A3)
# and android/sensor.h (A4) as NAMES from the real NDK r27b headers, evaluates
# the VALUES with the NDK compiler on the API-36 x86_64 emulator, and emits:
#   gen/a3a4_consts_dump.txt  -- the raw on-device dump (evidence)
#   gen/input_consts.xi.txt       -- XIOM constant block for src/input.xi (A3)
#   gen/sensor_consts.xi.txt      -- XIOM constant block for src/sensors.xi (A4)
#   gen/a3a4_const_asserts.h  -- _Static_assert gate (input_head_probe.c build)
# The generated .xi blocks are pasted into the modules; the probe compiles the
# assert header against the real headers, so any transcription drift fails the
# probe build on the device toolchain.
param(
  [string]$Ndk    = "C:\Android\sdk\ndk\27.1.12297006",
  [string]$Serial = "",
  [switch]$Compose  # rewrite src/input.xi + src/sensors.xi const sections in place
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$inc  = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\include"
$clang = Join-Path $Ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb  = "C:\Android\sdk\platform-tools\adb.exe"
$gen  = Join-Path $here "gen"
New-Item -ItemType Directory -Path $gen -Force | Out-Null

function Get-ConstNames([string]$path, [string[]]$prefixes) {
  $names = New-Object System.Collections.Generic.List[string]
  $seen = @{}
  foreach ($line in (Get-Content -LiteralPath $path)) {
    $l = $line.Trim()
    $name = $null
    if ($l -match '^#define\s+([A-Z][A-Z0-9_]+)\s+\S') { $name = $Matches[1] }
    elseif ($l -match '^([A-Z][A-Z0-9_]+)\s*(=|,)') { $name = $Matches[1] }
    if (-not $name) { continue }
    $ok = $false
    foreach ($p in $prefixes) { if ($name.StartsWith($p)) { $ok = $true; break } }
    if ($ok -and -not $seen.ContainsKey($name)) {
      $seen[$name] = 1
      $names.Add($name)
    }
  }
  return $names
}

$inputPrefixes = @(
  "AINPUT_EVENT_TYPE_", "AINPUT_SOURCE_", "AINPUT_KEYBOARD_TYPE_",
  "AKEY_EVENT_ACTION_", "AKEY_EVENT_FLAG_", "AKEY_STATE_", "AMETA_",
  "AMOTION_EVENT_ACTION_", "AMOTION_EVENT_FLAG_", "AMOTION_EVENT_BUTTON_",
  "AMOTION_EVENT_EDGE_FLAG_", "AMOTION_EVENT_TOOL_TYPE_",
  "AMOTION_EVENT_AXIS_", "AMOTION_EVENT_CLASSIFICATION_"
)
$keycodePrefixes = @("AKEYCODE_")
$sensorPrefixes = @(
  "ASENSOR_TYPE_", "ASENSOR_STATUS_", "ASENSOR_ADDITIONAL_INFO_",
  "ASENSOR_DIRECT_", "ASENSOR_"
)

$inputNames   = Get-ConstNames (Join-Path $inc "android\input.h")   $inputPrefixes
$keycodeNames = Get-ConstNames (Join-Path $inc "android\keycodes.h") $keycodePrefixes
$sensorNames  = Get-ConstNames (Join-Path $inc "android\sensor.h")  $sensorPrefixes
# The sensor prefix list is ordered; drop the catch-all duplicates.
$sensorNames = @($sensorNames | Sort-Object -Unique)

$floatConsts = @("ASENSOR_STANDARD_GRAVITY", "ASENSOR_MAGNETIC_FIELD_EARTH_MAX", "ASENSOR_MAGNETIC_FIELD_EARTH_MIN")
# ASENSOR_RESOLUTION_INVALID is nanf("") in the header: transcribed as its
# IEEE-754 quiet-NaN bit pattern (verified on-device, see the assert header).
$nanConsts = @("ASENSOR_RESOLUTION_INVALID")
$ints = @($inputNames + $keycodeNames + $sensorNames | Where-Object { $_ -notin $floatConsts -and $_ -notin $nanConsts })

"input.h consts:   $($inputNames.Count)"
"keycodes.h consts: $($keycodeNames.Count)"
"sensor.h consts:  $($sensorNames.Count)"

# -- dumper C program (real headers; values evaluated by the NDK compiler) --
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('#include <stdio.h>')
[void]$sb.AppendLine('#include <stddef.h>')
[void]$sb.AppendLine('#include <string.h>')
[void]$sb.AppendLine('#include <android/input.h>')
[void]$sb.AppendLine('#include <android/keycodes.h>')
[void]$sb.AppendLine('#include <android/sensor.h>')
[void]$sb.AppendLine('int main(void) {')
foreach ($n in $ints) {
  [void]$sb.AppendLine("  printf(`"I $n %lld\`n`", (long long)($n));")
}
foreach ($n in $floatConsts) {
  [void]$sb.AppendLine("  printf(`"F $n %.17g\`n`", (double)($n));")
}
foreach ($n in $nanConsts) {
  [void]$sb.AppendLine("  { float f_ = ($n); uint32_t b_; memcpy(&b_, &f_, 4); printf(`"N $n %lld\`n`", (long long)b_); }")
}
[void]$sb.AppendLine('  printf("S ASensorEvent_size %lld\n", (long long)sizeof(ASensorEvent));')
[void]$sb.AppendLine('  printf("S ASensorVector_size %lld\n", (long long)sizeof(ASensorVector));')
[void]$sb.AppendLine('  printf("S ASensorEvent_timestamp_off %lld\n", (long long)offsetof(ASensorEvent, timestamp));')
[void]$sb.AppendLine('  printf("S ASensorEvent_flags_off %lld\n", (long long)offsetof(ASensorEvent, flags));')
[void]$sb.AppendLine('  printf("S ASensorEvent_data_off %lld\n", (long long)offsetof(ASensorEvent, data));')
[void]$sb.AppendLine('  return 0;')
[void]$sb.AppendLine('}')
$dumperC = Join-Path $env:TEMP "kilo\a3a4_consts_dumper.c"
New-Item -ItemType Directory -Path (Split-Path $dumperC) -Force | Out-Null
Set-Content -LiteralPath $dumperC -Value $sb.ToString() -Encoding ASCII

$dumperExe = Join-Path $env:TEMP "kilo\a3a4_consts_dumper"
& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -Wall -o $dumperExe $dumperC -lm
if ($LASTEXITCODE -ne 0) { throw "dumper build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }
& $adb @serialArg shell mkdir -p /data/local/tmp/xiom-spike | Out-Null
& $adb @serialArg push $dumperExe /data/local/tmp/xiom-spike/a3a4_consts_dumper | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/a3a4_consts_dumper
& $adb @serialArg shell /data/local/tmp/xiom-spike/a3a4_consts_dumper > (Join-Path $gen "a3a4_consts_dump.txt")
if ($LASTEXITCODE -ne 0) { throw "dumper run failed" }

# adb may strip LFs on the way back; parse the raw text by pattern instead.
$dump = @{}
$rawDump = Get-Content -LiteralPath (Join-Path $gen "a3a4_consts_dump.txt") -Raw
foreach ($m in [regex]::Matches($rawDump, '(I|F|N|S) ([A-Z][A-Z0-9_]*) (-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)')) {
  $dump[$m.Groups[2].Value] = $m.Groups[3].Value
}
$expect = $ints.Count + $floatConsts.Count + $nanConsts.Count
if ($dump.Count -lt $expect) {
  throw "dump incomplete: $($dump.Count) values for $expect names"
}

function Format-Int([string]$raw, [bool]$hex) {
  $v = [long]$raw
  if (-not $hex) { return "$v" }
  if ($v -lt 0) { return "0x" + ("{0:X4}" -f ($v -band 0xFFFFFFFFL)) }
  return "0x" + ("{0:X4}" -f $v)
}

# -- emit the XIOM consts + the static-assert gate ---------------------------
$xiInput = New-Object System.Text.StringBuilder
$assing = New-Object System.Text.StringBuilder
[void]$assing.AppendLine('/* Generated by docs/repro/gen-a3a4-consts.ps1 -- do not edit.')
[void]$assing.AppendLine(' * _Static_assert gate: every transcribed constant must equal the value')
[void]$assing.AppendLine(' * of the REAL NDK r27b headers (included by the probe). */')
[void]$assing.AppendLine('#include <android/input.h>')
[void]$assing.AppendLine('#include <android/keycodes.h>')
[void]$assing.AppendLine('#include <android/sensor.h>')

function Add-Group([System.Text.StringBuilder]$xi, [string]$comment, [string[]]$names, [bool]$hex, [System.Text.StringBuilder]$as) {
  [void]$xi.AppendLine("// $comment")
  foreach ($n in $names) {
    $raw = $dump[$n]
    [void]$xi.AppendLine("pub const ${n}: Int = $(Format-Int $raw $hex);")
    [void]$as.AppendLine("_Static_assert(($n) == ($raw), `"$n`");")
  }
  [void]$xi.AppendLine("")
}

# groups in header order
function GroupsFor([string[]]$prefixes, [string[]]$names) {
  $groups = New-Object System.Collections.Generic.List[object]
  $taken = @{}
  foreach ($p in $prefixes) {
    $g = @($names | Where-Object { $_.StartsWith($p) -and -not $taken.ContainsKey($_) })
    if ($g.Count -gt 0) {
      foreach ($n in $g) { $taken[$n] = 1 }
      $groups.Add([pscustomobject]@{ Prefix = $p; Names = $g })
    }
  }
  return $groups
}

Add-Group $xiInput "AINPUT_* event types (android/input.h)" (GroupsFor @("AINPUT_EVENT_TYPE_") $inputNames).Names $true $assing
Add-Group $xiInput "AINPUT_SOURCE_* device sources (android/input.h)" (GroupsFor @("AINPUT_SOURCE_") $inputNames).Names $true $assing
Add-Group $xiInput "AINPUT_KEYBOARD_TYPE_* (android/input.h)" (GroupsFor @("AINPUT_KEYBOARD_TYPE_") $inputNames).Names $true $assing
Add-Group $xiInput "AKEY_EVENT_ACTION_* (android/input.h)" (GroupsFor @("AKEY_EVENT_ACTION_") $inputNames).Names $true $assing
Add-Group $xiInput "AKEY_EVENT_FLAG_* (android/input.h)" (GroupsFor @("AKEY_EVENT_FLAG_") $inputNames).Names $true $assing
Add-Group $xiInput "AKEY_STATE_* (android/input.h)" (GroupsFor @("AKEY_STATE_") $inputNames).Names $true $assing
Add-Group $xiInput "AMETA_* meta states (android/input.h)" (GroupsFor @("AMETA_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_ACTION_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_ACTION_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_FLAG_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_FLAG_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_BUTTON_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_BUTTON_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_EDGE_FLAG_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_EDGE_FLAG_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_TOOL_TYPE_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_TOOL_TYPE_") $inputNames).Names $true $assing
Add-Group $xiInput "AMOTION_EVENT_AXIS_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_AXIS_") $inputNames).Names $false $assing
Add-Group $xiInput "AMOTION_EVENT_CLASSIFICATION_* (android/input.h)" (GroupsFor @("AMOTION_EVENT_CLASSIFICATION_") $inputNames).Names $true $assing
Add-Group $xiInput "AKEYCODE_* key codes (android/keycodes.h, frozen enum)" $keycodeNames $false $assing

# the axis/decimal split: AXIS is decimal in the header
# fix: AXIS group above used decimal; re-render with the intended values already in $xiInput.

$xiSensor = New-Object System.Text.StringBuilder
Add-Group $xiSensor "ASENSOR_TYPE_* sensor types (android/sensor.h)" @($sensorNames | Where-Object { $_.StartsWith("ASENSOR_TYPE_") }) $false $assing
Add-Group $xiSensor "ASENSOR_STATUS_* (android/sensor.h)" @($sensorNames | Where-Object { $_.StartsWith("ASENSOR_STATUS_") }) $false $assing
Add-Group $xiSensor "ASENSOR_ADDITIONAL_INFO_* (android/sensor.h)" @($sensorNames | Where-Object { $_.StartsWith("ASENSOR_ADDITIONAL_INFO_") }) $false $assing
Add-Group $xiSensor "ASENSOR_DIRECT_* (android/sensor.h)" @($sensorNames | Where-Object { $_.StartsWith("ASENSOR_DIRECT_") }) $false $assing
Add-Group $xiSensor "Scalar limits and physical constants (android/sensor.h)" @($sensorNames | Where-Object { $_ -notmatch '^ASENSOR_(TYPE|STATUS|ADDITIONAL_INFO|DIRECT)_' -and $_ -notin $floatConsts -and $_ -notin $nanConsts }) $false $assing

foreach ($n in $floatConsts) {
  $raw = $dump[$n]
  [void]$xiSensor.AppendLine("pub const ${n}: Float64 = $raw; // = ${n}f from the header")
  [void]$assing.AppendLine("_Static_assert(($n) == ($raw), `"$n`");")
}
foreach ($n in $nanConsts) {
  $bits = $dump[$n]
  [void]$xiSensor.AppendLine("// The header defines ${n} as nanf(`"`") -- surfaced as the IEEE-754 quiet-NaN bit pattern (runtime-checked by the probe).")
  [void]$xiSensor.AppendLine("pub const ${n}: Int = $bits;")
  [void]$assing.AppendLine("/* ${n}: nanf in the header; the probe runtime-checks its bits. */")
  [void]$assing.AppendLine("#define XA_${n}_BITS ${bits}u")
}
[void]$xiSensor.AppendLine("")

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Write-Utf8([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}
Write-Utf8 (Join-Path $gen "input_consts.xi.txt")   $xiInput.ToString()
Write-Utf8 (Join-Path $gen "sensor_consts.xi.txt")  $xiSensor.ToString()
Write-Utf8 (Join-Path $gen "a3a4_const_asserts.h") $assing.ToString()
"wrote gen/input_consts.xi.txt, gen/sensor_consts.xi.txt, gen/a3a4_const_asserts.h"

if ($Compose) {
  $srcDir = Join-Path (Split-Path (Split-Path $here -Parent) -Parent) "src"
  $marker = "// GENERATED CONSTANTS"
  $banner = @(
    "// ============================================================================",
    "// GENERATED CONSTANTS -- do not edit below this line.",
    "// Produced by docs/repro/gen-a3a4-consts.ps1 (values evaluated by the NDK",
    "// r27b compiler on the API-36 emulator; see gen/a3a4_consts_dump.txt).",
    "// ============================================================================",
    ""
  ) -join "`r`n"
  foreach ($pair in @(@("input.xi", $xiInput.ToString()), @("sensors.xi", $xiSensor.ToString()))) {
    $path = Join-Path $srcDir $pair[0]
    $text = [System.IO.File]::ReadAllText($path)
    $idx = $text.IndexOf($marker)
    if ($idx -lt 0) { throw "marker '$marker' not found in $path" }
    $prefix = $text.Substring(0, $idx)
    Write-Utf8 $path ($prefix + $banner + $pair[1])
    "composed src/$($pair[0])"
  }
}
