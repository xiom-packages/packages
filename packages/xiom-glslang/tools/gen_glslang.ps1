#!/usr/bin/env pwsh
# ============================================================================
# gen_glslang.ps1 -- mechanical oracle + constants generator for xiom.glslang
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# This is the committed generator required by the SDK-100 program: the
# function inventory and the constant tables of `xiom.glslang` are parsed
# MECHANICALLY from the pinned glslang headers (no hand-maintained lists).
#
# Oracle header set (default root: the Vulkan SDK 1.4.350.0 include dir):
#   Public/ShaderLang.h               legacy extern "C" entry points + enums
#   Include/glslang_c_interface.h     the C interface entry points + structs
#   Include/glslang_c_shader_types.h  the C interface enums
#   Public/resource_limits_c.h        the C resource-limits entry points
#   MachineIndependent/Versions.h     EProfile (+ TExtensionBehavior) enums
#   build_info.h                      GLSLANG_VERSION_* macros
#
# Actions:
#   -Action emit    write docs/oracle-functions.txt, docs/oracle-constants.txt
#                   and docs/glslang-constants-fragment.xi (the generated
#                   block that lives verbatim inside glslang.xi).
#   -Action verify  (default) recompute everything and check the committed
#                   artifacts: docs/oracle-functions.txt, the generated
#                   constant block inside glslang.xi, every `dl.dl_sym` name
#                   in glslang.xi, and (when the committed export dumps are
#                   present) the per-DLL export split. Exit 1 on any drift.
#
# Exit code: 0 = ok, 1 = drift/parse failure.
# ============================================================================
[CmdletBinding()]
param(
    [string]$IncludeDir = "C:\VulkanSDK\1.4.350.0\Include\glslang",
    [ValidateSet("emit", "verify")]
    [string]$Action = "verify"
)

$ErrorActionPreference = "Stop"

$pkgRoot = Split-Path -Parent $PSScriptRoot
$docsDir = Join-Path $pkgRoot "docs"
$moduleFile = Join-Path $pkgRoot "glslang.xi"
$oracleFnsFile = Join-Path $docsDir "oracle-functions.txt"
$oracleConstsFile = Join-Path $docsDir "oracle-constants.txt"
$fragmentFile = Join-Path $docsDir "glslang-constants-fragment.xi"
$exportsCoreFile = Join-Path $docsDir "exports-glslang.txt"
$exportsLimitsFile = Join-Path $docsDir "exports-glslang-default-resource-limits.txt"

$headersFunctions = @(
    @{ Name = "Public/ShaderLang.h"; Kind = "core" },
    @{ Name = "Include/glslang_c_interface.h"; Kind = "core" },
    @{ Name = "Public/resource_limits_c.h"; Kind = "limits" }
)
$headersConstants = @(
    "Public/ShaderLang.h",
    "Include/glslang_c_shader_types.h",
    "MachineIndependent/Versions.h"
)

$beginMarker = "===== BEGIN GENERATED CONSTANTS (tools/gen_glslang.ps1) ====="
$endMarker = "===== END GENERATED CONSTANTS ====="

function New-OrdinalMap {
    # Case-SENSITIVE name map (PowerShell hashtables are case-insensitive by
    # default; the glslang headers carry case-distinct names like
    # EShTargetSpv vs EshTargetSpv).
    return New-Object 'System.Collections.Generic.Dictionary[string,long]' ([System.StringComparer]::Ordinal)
}

function Read-HeaderLines {
    param([string]$Rel)
    $p = Join-Path $IncludeDir $Rel
    if (-not (Test-Path -LiteralPath $p)) {
        throw "oracle header not found: $p (pass -IncludeDir)"
    }
    return , (Get-Content -LiteralPath $p)
}

# --- extern "C" region function inventory -----------------------------------

function Get-ExternCFunctions {
    param([string]$Rel)
    $lines = Read-HeaderLines $Rel
    $names = New-Object System.Collections.Generic.List[string]
    $inRegion = $false
    $depth = 0
    foreach ($line in $lines) {
        if (-not $inRegion) {
            if ($line -match 'extern\s+"C"\s*\{') {
                $inRegion = $true
                $depth = 1
            }
            continue
        }
        if ($line -match 'GLSLANG_EXPORT\s' -and $line -notmatch '\bclass\b' -and
            $line -match '\b([A-Za-z_]\w*)\s*\(') {
            [void]$names.Add($Matches[1])
        }
        $open = ([regex]::Matches($line, '\{')).Count
        $close = ([regex]::Matches($line, '\}')).Count
        $depth = $depth + $open - $close
        if ($depth -le 0) { $inRegion = $false }
    }
    return $names
}

# --- enum / macro constants --------------------------------------------------

function Invoke-EnumExpr {
    param([string]$Expr, [hashtable]$Map)
    $e = $Expr
    # resolve identifiers from the accumulated map (exact, case-sensitive)
    $e = [regex]::Replace($e, '[A-Za-z_]\w*', {
        param($m)
        if ($Map.ContainsKey($m.Value)) { return [string]$Map[$m.Value] }
        throw "unknown identifier in enum expression: $($m.Value) (raw: $Expr)"
    })
    $e = $e -replace '<<', ' -shl ' -replace '>>', ' -shr '
    $e = $e -replace '\|', ' -bor ' -replace '&', ' -band ' -replace '\^', ' -bxor '
    $v = Invoke-Expression "($e)"
    return [long]$v
}

function Get-EnumConstants {
    # Brace-matching enum body extraction + comma-split member parsing
    # (handles: named/unnamed/typed enums, base typing `: unsigned`,
    # single-line enums, LAST_ELEMENT_MARKER with and without explicit value,
    # expressions over previously defined names).
    param([string]$Rel)
    $lines = Read-HeaderLines $Rel
    $text = ($lines -join "`n")
    # strip block comments (may span lines) and line comments
    $text = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
    $text = [regex]::Replace($text, '(?m)//[^\n]*', '')
    $map = New-OrdinalMap
    $order = New-Object System.Collections.Generic.List[string]
    $pos = 0
    while ($true) {
        $m = [regex]::Match($text.Substring($pos), '(?m)^[ \t]*(?:typedef[ \t]+)?enum(?:[ \t]+[A-Za-z_]\w*)?(?:[ \t]*:[ \t]*[A-Za-z_]\w*)?\s*\{')
        if (-not $m.Success) { break }
        $bodyStart = $pos + $m.Index + $m.Length
        # scan chars for the matching close brace
        $depth = 1
        $i = $bodyStart
        while ($i -lt $text.Length -and $depth -gt 0) {
            $ch = $text[$i]
            if ($ch -eq '{') { $depth = $depth + 1 }
            elseif ($ch -eq '}') { $depth = $depth - 1 }
            $i = $i + 1
        }
        if ($depth -ne 0) { throw "unbalanced enum braces in $Rel" }
        $body = $text.Substring($bodyStart, $i - 1 - $bodyStart)
        $pos = $i
        $prev = -1
        foreach ($tokRaw in ($body -split ',')) {
            $tok = $tokRaw.Trim()
            if ($tok -eq '') { continue }
            if ($tok -match '^LAST_ELEMENT_MARKER\(\s*([A-Za-z_]\w*)\s*(?:=\s*(.+?))?\s*\)$') {
                $name = $Matches[1]
                if ($Matches[2]) { $val = Invoke-EnumExpr -Expr $Matches[2] -Map $map } else { $val = $prev + 1 }
            } elseif ($tok -match '^([A-Za-z_]\w*)\s*(?:=\s*(.+))?$') {
                $name = $Matches[1]
                if ($Matches[2]) { $val = Invoke-EnumExpr -Expr $Matches[2] -Map $map } else { $val = $prev + 1 }
            } else {
                throw "unparsed enum token in ${Rel}: [$tok]"
            }
            if ($map.ContainsKey($name)) { throw "duplicate constant $name in $Rel" }
            $map[$name] = $val
            [void]$order.Add($name)
            $prev = $val
        }
    }
    return @{ Map = $map; Order = $order }
}

function Get-VersionMacros {
    $lines = Read-HeaderLines "build_info.h"
    $map = New-OrdinalMap
    foreach ($line in $lines) {
        if ($line -match '^#define\s+(GLSLANG_VERSION_(?:MAJOR|MINOR|PATCH))\s+(\d+)\s*$') {
            $map[$Matches[1]] = [long]$Matches[2]
        }
    }
    if ($map.Count -ne 3) { throw "build_info.h: expected 3 GLSLANG_VERSION_* macros, found $($map.Count)" }
    return $map
}

# --- committed-export parsing (evidence files) -------------------------------

function Get-CommittedExports {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)\s*$') {
            $nm = $Matches[1]
            if ($nm -notmatch '^\?') { [void]$names.Add($nm) }
        }
    }
    return , $names
}

function Extract-Between {
    param([string]$Text, [string]$Begin, [string]$End)
    $i = $Text.IndexOf($Begin)
    if ($i -lt 0) { throw "begin marker not found: $Begin" }
    $j = $Text.IndexOf($End, $i)
    if ($j -lt 0) { throw "end marker not found: $End" }
    return $Text.Substring($i + $Begin.Length, $j - $i - $Begin.Length)
}

# --- build the oracle --------------------------------------------------------

$oracleFns = New-Object System.Collections.Generic.List[string]
$coreFns = New-Object System.Collections.Generic.List[string]
$limitsFns = New-Object System.Collections.Generic.List[string]
foreach ($h in $headersFunctions) {
    $fns = Get-ExternCFunctions -Rel $h.Name
    if ($fns.Count -eq 0) { throw "no extern-C functions parsed from $($h.Name)" }
    foreach ($f in $fns) {
        [void]$oracleFns.Add($f)
        if ($h.Kind -eq "core") { [void]$coreFns.Add($f) } else { [void]$limitsFns.Add($f) }
    }
}
$oracleFnsArr = @($oracleFns | Sort-Object -Unique)
if ($oracleFnsArr.Count -ne $oracleFns.Count) { throw "duplicate function names in oracle" }

$constMap = New-OrdinalMap
$constOrder = New-Object System.Collections.Generic.List[string]
foreach ($h in $headersConstants) {
    $r = Get-EnumConstants -Rel $h
    foreach ($k in $r.Order) {
        if ($constMap.ContainsKey($k)) { throw "duplicate constant across headers: $k" }
        $constMap[$k] = $r.Map[$k]
        [void]$constOrder.Add($k)
    }
}
foreach ($kv in (Get-VersionMacros).GetEnumerator()) {
    if ($constMap.ContainsKey($kv.Key)) { throw "duplicate constant: $($kv.Key)" }
    $constMap[$kv.Key] = $kv.Value
    [void]$constOrder.Add($kv.Key)
}

# --- artifact rendering ------------------------------------------------------

function Render-OracleFunctions {
    $ordered = @($oracleFns)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# glslang C entry-point oracle -- parsed mechanically from the pinned headers")
    [void]$sb.AppendLine("# by tools/gen_glslang.ps1 (SDK-100 program; do not edit by hand).")
    [void]$sb.AppendLine("#")
    [void]$sb.AppendLine("# core   (glslang.dll):                      $($coreFns.Count)")
    [void]$sb.AppendLine("# limits (glslang-default-resource-limits.dll): $($limitsFns.Count)")
    [void]$sb.AppendLine("# total:                                     $($oracleFns.Count)")
    [void]$sb.AppendLine("#")
    [void]$sb.AppendLine("# name<TAB>source-header")
    $srcOf = @{}
    foreach ($h in $headersFunctions) {
        foreach ($f in (Get-ExternCFunctions -Rel $h.Name)) { $srcOf[$f] = $h.Name }
    }
    foreach ($f in $ordered) {
        [void]$sb.AppendLine("$f`t$($srcOf[$f])")
    }
    return $sb.ToString()
}

function Render-OracleConstants {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# glslang constant oracle -- parsed mechanically from the pinned headers")
    [void]$sb.AppendLine("# by tools/gen_glslang.ps1 (SDK-100 program; do not edit by hand).")
    [void]$sb.AppendLine("# count: $($constOrder.Count)")
    [void]$sb.AppendLine("#")
    [void]$sb.AppendLine("# name=value")
    foreach ($k in $constOrder) {
        [void]$sb.AppendLine("$k=$($constMap[$k])")
    }
    return $sb.ToString()
}

function Render-Fragment {
    $srcOf = @{}
    foreach ($h in $headersConstants) {
        $r = Get-EnumConstants -Rel $h
        foreach ($k in $r.Order) { $srcOf[$k] = $h }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("// $beginMarker")
    [void]$sb.AppendLine("// Source-generated from the pinned glslang 1.4.350.0 SDK headers by")
    [void]$sb.AppendLine("// tools/gen_glslang.ps1; re-run with -Action verify to check for drift.")
    [void]$sb.AppendLine("// Constant count: $($constOrder.Count)")
    [void]$sb.AppendLine("")
    $lastSrc = ""
    foreach ($k in $constOrder) {
        $src = if ($srcOf.ContainsKey($k)) { $srcOf[$k] } else { "build_info.h" }
        if ($src -ne $lastSrc) {
            [void]$sb.AppendLine("// ---- $src ----")
            $lastSrc = $src
        }
        [void]$sb.AppendLine("pub const ${k}: Int = $($constMap[$k]);")
    }
    [void]$sb.AppendLine("// $endMarker")
    return $sb.ToString()
}

# --- action: emit ------------------------------------------------------------

if ($Action -eq "emit") {
    if (-not (Test-Path -LiteralPath $docsDir)) { [void](New-Item -ItemType Directory -Force -Path $docsDir) }
    [System.IO.File]::WriteAllText($oracleFnsFile, (Render-OracleFunctions), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($oracleConstsFile, (Render-OracleConstants), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($fragmentFile, (Render-Fragment), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "gen_glslang emit: functions=$($oracleFns.Count) (core=$($coreFns.Count) limits=$($limitsFns.Count)) constants=$($constOrder.Count)"
    Write-Host "  wrote $oracleFnsFile"
    Write-Host "  wrote $oracleConstsFile"
    Write-Host "  wrote $fragmentFile"
    exit 0
}

# --- action: verify ----------------------------------------------------------

$problems = New-Object System.Collections.Generic.List[string]

# 1. oracle-functions.txt matches the header parse.
if (-not (Test-Path -LiteralPath $oracleFnsFile)) {
    [void]$problems.Add("docs/oracle-functions.txt missing (run -Action emit)")
} else {
    $committed = @(Get-Content -LiteralPath $oracleFnsFile | Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' } |
        ForEach-Object { ($_ -split "`t")[0] })
    $diff = Compare-Object -CaseSensitive $oracleFns $committed
    if ($diff) { [void]$problems.Add("oracle-functions.txt drift: $(($diff | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ', ')") }
}

# 2. glslang.xi: constant block matches; dl_sym inventory matches the oracle.
if (-not (Test-Path -LiteralPath $moduleFile)) {
    [void]$problems.Add("glslang.xi missing")
} else {
    $text = Get-Content -LiteralPath $moduleFile -Raw
    try {
        $block = Extract-Between -Text $text -Begin $beginMarker -End $endMarker
        $seen = New-OrdinalMap
        foreach ($m in [regex]::Matches($block, 'pub const ([A-Za-z_]\w*): Int = (\d+);')) {
            $seen[$m.Groups[1].Value] = [long]$m.Groups[2].Value
        }
        foreach ($k in $constOrder) {
            if (-not $seen.ContainsKey($k)) { [void]$problems.Add("glslang.xi constant missing: $k") }
            elseif ($seen[$k] -ne $constMap[$k]) { [void]$problems.Add("glslang.xi constant drift: $k = $($seen[$k]) (oracle $($constMap[$k]))") }
        }
        foreach ($k in $seen.Keys) {
            if (-not $constMap.ContainsKey($k)) { [void]$problems.Add("glslang.xi constant not in oracle: $k") }
        }
        $symNames = @([regex]::Matches($text, 'dl\.dl_sym\(handle,\s*"(\w+)"\)') | ForEach-Object { $_.Groups[1].Value })
        $symLims = @([regex]::Matches($text, 'dl\.dl_sym\(lim_handle,\s*"(\w+)"\)') | ForEach-Object { $_.Groups[1].Value })
        $boundAll = @($symNames + $symLims)
        $d1 = Compare-Object -CaseSensitive $oracleFns $boundAll
        if ($d1) { [void]$problems.Add("dl_sym inventory drift: $(($d1 | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ', ')") }
        # per-loader split vs committed export dumps (when present).
        $expCore = Get-CommittedExports -Path $exportsCoreFile
        $expLims = Get-CommittedExports -Path $exportsLimitsFile
        if ($expCore) {
            $d2 = Compare-Object -CaseSensitive $expCore $symNames
            if ($d2) { [void]$problems.Add("core dl_sym vs exports-glslang.txt: $(($d2 | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ', ')") }
            $notExported = @($coreFns | Where-Object { $_ -notin $expCore })
            foreach ($n in $notExported) {
                if ($n -in $symNames) { [void]$problems.Add("$n is header-declared but not exported by glslang.dll yet is resolved in the core loader") }
            }
        }
        if ($expLims) {
            $d3 = Compare-Object -CaseSensitive $expLims $symLims
            if ($d3) { [void]$problems.Add("limits dl_sym vs exports-glslang-default-resource-limits.txt: $(($d3 | ForEach-Object { $_.SideIndicator + $_.InputObject }) -join ', ')") }
        }
    } catch {
        [void]$problems.Add("glslang.xi parse: $($_.Exception.Message)")
    }
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "DRIFT $p" }
    Write-Host "gen_glslang verify: $($problems.Count) problem(s)"
    exit 1
}
Write-Host "gen_glslang verify: OK -- functions=$($oracleFns.Count) (core=$($coreFns.Count) limits=$($limitsFns.Count)) constants=$($constOrder.Count)"
exit 0
