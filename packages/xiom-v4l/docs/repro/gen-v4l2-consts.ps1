#!/usr/bin/env pwsh
# ============================================================================
# xiom.v4l -- UAPI constant + struct-layout transcription generator.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# UPSTREAM-FIRST: every declared constant value and every struct
# size/offset in xiom.v4l is evaluated by a REAL compiler (gcc) against the
# PINNED kernel UAPI header text -- nothing is transcribed by hand:
#
#   oracle:  torvalds/linux v6.19 = 05f7e89ab9731565d8a62e3b5d1ec206485eeb0b
#            include/uapi/linux/videodev2.h   (includes v4l2-common.h and
#            include/uapi/linux/v4l2-controls.h transitively -- the whole
#            `#include <linux/videodev2.h>` userspace surface)
#   parse:   gcc -E -dM (macro name universe, userspace view) plus the
#            preprocessed text (enum members + struct bodies); the pinned
#            tag's videodev2.h line 63 references <linux/compiler.h> which is
#            absent from the uapi tree -- docs/repro/uapi-shim provides the
#            headers_install-equivalent empty surface (see the shim header)
#   values:  a generated C dumper prints every constant and every
#            sizeof/offsetof; the dump is committed as the raw evidence
#
# Emits (all generated, do not edit):
#   src/consts.xi                 module xiom.v4l.consts   (videodev2 + common)
#   src/cids.xi                   module xiom.v4l.cids    (controls-only names)
#   src/layout.xi                 module xiom.v4l.layout  (struct facts)
#   gen/v4l2_consts_dump.txt      raw evaluated dump (evidence)
#   gen/v4l2_const_asserts.h      _Static_assert gate vs the pinned headers
#   gen/v4l2_coverage.tsv         family/count coverage table
#   gen/v4l2_values_dumper.c      the generated dumper source (evidence)
#
# Usage:  pwsh scripts..\ docs\repro\gen-v4l2-consts.ps1
#   -KernelTree E:\repos\linux-uapi-v6.19   (light sparse clone at the pin)
#   -Distro Ubuntu                          (WSL distro providing gcc)
# ============================================================================
[CmdletBinding()]
param(
  [string]$KernelTree = "E:\repos\linux-uapi-v6.19",
  [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$pkg = Split-Path (Split-Path $here -Parent) -Parent
$gen = Join-Path $here "gen"
$src = Join-Path $pkg "src"
$shim = Join-Path $here "uapi-shim"
New-Item -ItemType Directory -Path $gen -Force | Out-Null

$pinCommit = "05f7e89ab9731565d8a62e3b5d1ec206485eeb0b"  # torvalds/linux v6.19
$headers = @("videodev2.h", "v4l2-common.h", "v4l2-controls.h")

function To-Wsl([string]$p) {
  # Absolute Windows path -> /mnt/<drive>/... (path need not exist yet).
  if (-not [System.IO.Path]::IsPathRooted($p)) { throw "path must be absolute: $p" }
  $d = $p.Substring(0, 1).ToLower()
  return "/mnt/$d" + ($p.Substring(2) -replace '\\', '/')
}

function Invoke-Wsl([string]$Cmd) {
  # All output is captured to a log file inside WSL; PowerShell only sees the
  # exit code (native stderr would otherwise abort under EA=Stop).  Callers
  # that need output get the merged log back.
  $wrapped = "( $Cmd ) > /tmp/xv-run.log 2>&1; exit `$?"
  & wsl -d $Distro -e bash -lc $wrapped | Out-Null
  $rc = $LASTEXITCODE
  $log = (& wsl -d $Distro -e bash -lc "cat /tmp/xv-run.log")
  if ($rc -ne 0) {
    throw "wsl command failed (exit $rc): $Cmd`n" + ($log -join "`n")
  }
  return $log
}

function Strip-Comments([string]$text) {
  $t = [regex]::Replace($text, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  $t = [regex]::Replace($t, '//[^\r\n]*', '')
  return $t
}

# ---------------------------------------------------------------------------
# 0. Sanity: pin the tree
# ---------------------------------------------------------------------------
$pinFile = Join-Path $KernelTree ".git"
if (-not (Test-Path -LiteralPath $pinFile)) { throw "kernel tree not found: $KernelTree" }
$headCommit = (& git -C $KernelTree rev-parse HEAD).Trim()
Write-Host "kernel tree: $KernelTree @ $headCommit"
foreach ($h in @($headers | ForEach-Object { Join-Path $KernelTree "include\uapi\linux\$_" })) {
  if (-not (Test-Path -LiteralPath $h)) { throw "missing header: $h" }
}

$wslTree = To-Wsl $KernelTree
$wslShim = To-Wsl $shim
$wslGen  = To-Wsl $gen
$incUapi = "$wslTree/include/uapi"
$incArch = "$wslTree/arch/x86/include/uapi"
$incFlags = "-D__EXPORTED_HEADERS__ -I '$wslShim' -I '$incUapi' -I '$incArch'"

# ---------------------------------------------------------------------------
# 1. Macro name universe (userspace view) via gcc -E -dM
# ---------------------------------------------------------------------------
$namesC = Join-Path $gen "v4l2_names_probe.c"
# <linux/bits.h> is pre-included from the same pinned tree: two public
# v4l2-controls.h macros (V4L2_FWHT_FL_COMPONENTS_NUM_MSK / _PIXENC_MSK)
# are GENMASK() expressions; the pinned UAPI tree provides GENMASK in
# include/uapi/linux/bits.h.  Recorded in PROVENANCE.md.
$probeSrc = "#include <linux/bits.h>`n#include <linux/videodev2.h>`n"
Set-Content -LiteralPath $namesC -Value $probeSrc -Encoding ASCII
$wslNamesC = To-Wsl $namesC

Write-Host "step 1: collecting macro names (gcc -E -dM) ..."
$dm = Invoke-Wsl "gcc $incFlags -E -dM '$wslNamesC'"
$constNames = New-Object System.Collections.Generic.HashSet[string]
$fnMacroNames = New-Object System.Collections.Generic.List[string]
foreach ($line in $dm) {
  if ($line -notmatch '^#define\s+([A-Za-z_][A-Za-z0-9_]*)(\(.*)?\s*(.*)$') { continue }
  $name = $Matches[1]
  $isFn = [bool]$Matches[2]
  if ($name -notmatch '^(V4L2_|VIDIOC_)') { continue }
  if ($isFn) {
    if (-not $fnMacroNames.Contains($name)) { $fnMacroNames.Add($name) }
  } else {
    [void]$constNames.Add($name)
  }
}
Write-Host ("  macros: {0} constant candidates, {1} function-like (mirrored as XIOM functions)" -f $constNames.Count, $fnMacroNames.Count)

# String-valued defines (V4L2_MPEG_VBI_IVTV_MAGIC0/1): declared as XIOM Str
# constants; the numeric dumper neither evaluates nor asserts them as integers.
$rawBodies = @{}
foreach ($h in $headers) {
  $rawBodies[$h] = Strip-Comments (Get-Content -LiteralPath (Join-Path $KernelTree "include\uapi\linux\$h") -Raw)
}
$stringConsts = New-Object System.Collections.Generic.List[object]
foreach ($h in $headers) {
  foreach ($m in [regex]::Matches($rawBodies[$h], '(?m)^\s*#define\s+(V4L2_[A-Z0-9_]+)\s+"([^"]*)"\s*$')) {
    $stringConsts.Add([pscustomobject]@{ Name = $m.Groups[1].Value; Value = $m.Groups[2].Value; Group = $h })
    [void]$constNames.Remove($m.Groups[1].Value)
  }
}
if ($stringConsts.Count -gt 0) {
  Write-Host ("  string defines: {0} ({1})" -f $stringConsts.Count, (($stringConsts | ForEach-Object { $_.Name }) -join ", "))
}

# ---------------------------------------------------------------------------
# 2. Preprocessed userspace text: enum members + struct bodies
# ---------------------------------------------------------------------------
Write-Host "step 2: preprocessing the header text (enum + struct parse base) ..."
$ppFile = Join-Path ([System.IO.Path]::GetTempPath()) "kilo\v4l-gen-preprocessed.i"
New-Item -ItemType Directory -Path (Split-Path $ppFile) -Force | Out-Null
$wslPp = To-Wsl $ppFile
Invoke-Wsl "gcc $incFlags -E -P -o '$wslPp' '$wslNamesC'" | Out-Null
$pp = (Get-Content -LiteralPath $ppFile -Raw) -replace "`r", ""

# enum members
foreach ($m in [regex]::Matches($pp, '(?s)\benum\s+[A-Za-z0-9_]*\s*\{(.*?)\}')) {
  foreach ($tok in [regex]::Matches($m.Groups[1].Value, '\b(V4L2_[A-Z0-9_]+|VIDIOC_[A-Z0-9_]+)\b')) {
    [void]$constNames.Add($tok.Groups[1].Value)
  }
}
Write-Host ("  constant set after enums: {0}" -f $constNames.Count)

# structs: struct v4l2_* { ... } at top level (v4l2_ prefix scopes to UAPI V4L2)
function Get-BraceBody([string]$text, [int]$openIndex) {
  $d = 0
  $i = $openIndex
  while ($i -lt $text.Length) {
    $c = $text[$i]
    if ($c -eq '{') { $d = $d + 1 }
    elseif ($c -eq '}') {
      $d = $d - 1
      if ($d -eq 0) { return @{ body = $text.Substring($openIndex + 1, $i - $openIndex - 1); end = $i } }
    }
    $i = $i + 1
  }
  throw "unbalanced braces at offset $openIndex"
}

function Get-FieldNames([string]$body) {
  # Returns depth-0 declarator names of a struct/union body; anonymous
  # nested struct/union members are lifted into the enclosing scope (that is
  # how C11 anonymous members work for offsetof purposes).
  $out = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Generic.List[string]
  $cur = New-Object System.Text.StringBuilder
  $d = 0
  foreach ($c in $body.ToCharArray()) {
    if ($c -eq '{') { $d = $d + 1 }
    elseif ($c -eq '}') { $d = $d - 1 }
    [void]$cur.Append($c)
    if ($c -eq ';' -and $d -eq 0) {
      $items.Add($cur.ToString())
      $cur = New-Object System.Text.StringBuilder
    }
  }
  foreach ($item in $items) {
    $it = ($item -replace '\s+', ' ').Trim()
    if ($it -eq "" -or $it -eq ";") { continue }
    $open = $it.IndexOf('{')
    if ($open -ge 0) {
      # nested definition: field name(s) after the final '}'
      $lastClose = $it.LastIndexOf('}')
      $tail = $it.Substring($lastClose + 1).Trim().TrimEnd(';').Trim()
      $tail = ($tail -replace '__attribute__.*$', '').Trim()
      $tail = [regex]::Replace($tail, '\[[^\]]*\]', '')
      $nm = [regex]::Match($tail, '[A-Za-z_][A-Za-z0-9_]*')
      if ($nm.Success) {
        $out.Add($nm.Value)
      } else {
        # anonymous -> lift inner fields
        $inner = Get-BraceBody $it $open
        foreach ($f in (Get-FieldNames $inner.body)) { $out.Add($f) }
      }
      continue
    }
    if ($it -match ':') { continue }  # bitfield: offsetof is not defined
    $decl = $it.TrimEnd(';').Trim()
    $decl = [regex]::Replace($decl, '\[[^\]]*\]', '')
    foreach ($part in ($decl -split ',')) {
      $ids = [regex]::Matches($part, '[A-Za-z_][A-Za-z0-9_]*')
      if ($ids.Count -eq 0) { continue }
      $name = $ids[$ids.Count - 1].Value
      if ($name -eq 'struct' -or $name -eq 'union' -or $name -eq 'enum') { continue }
      $out.Add($name)
    }
  }
  # dedupe, preserve order
  $seen = @{}
  $uniq = New-Object System.Collections.Generic.List[string]
  foreach ($f in $out) { if (-not $seen.ContainsKey($f)) { $seen[$f] = 1; $uniq.Add($f) } }
  return , $uniq
}

$structs = New-Object System.Collections.Generic.List[object]
$rxStruct = [regex]'(?m)^struct\s+(v4l2_[a-z0-9_]+)\s*\{'
$pos = 0
while ($true) {
  $m = $rxStruct.Match($pp, $pos)
  if (-not $m.Success) { break }
  $openIndex = $m.Index + $m.Length - 1
  $bb = Get-BraceBody $pp $openIndex
  $fields = Get-FieldNames $bb.body
  $structs.Add([pscustomobject]@{ Name = $m.Groups[1].Value; Fields = $fields })
  $pos = $bb.end + 1
}
Write-Host ("  structs: {0} (v4l2_* definitions), fields total: {1}" -f $structs.Count, (($structs | ForEach-Object { $_.Fields.Count }) | Measure-Object -Sum).Sum)

# ---------------------------------------------------------------------------
# 3. Emit the value+layout dumper and run it
# ---------------------------------------------------------------------------
Write-Host "step 3: evaluating values with gcc (pinned header) ..."
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("/* Generated by docs/repro/gen-v4l2-consts.ps1 -- do not edit.")
[void]$sb.AppendLine(" * Evaluates every xiom.v4l constant and struct layout fact against the")
[void]$sb.AppendLine(" * pinned kernel UAPI headers (torvalds/linux v6.19 = $pinCommit). */")
[void]$sb.AppendLine('#include <stdio.h>')
[void]$sb.AppendLine('#include <stddef.h>')
[void]$sb.AppendLine('#include <linux/bits.h>       /* pinned: __GENMASK for the two FWHT MSK macros */')
[void]$sb.AppendLine('#include <linux/videodev2.h>')
[void]$sb.AppendLine('/* GENMASK fallback: the pinned include/linux/bits.h defines GENMASK(h,l)')
[void]$sb.AppendLine(' * = __GENMASK(h,l) in its __ASSEMBLY__ branch; for the two literal')
[void]$sb.AppendLine(' * V4L2_FWHT_*_MSK arguments the C branch (GENMASK_TYPE) computes the')
[void]$sb.AppendLine(' * same value. Transcribed from the same pinned commit -- see PROVENANCE.md. */')
[void]$sb.AppendLine('#ifndef GENMASK')
[void]$sb.AppendLine('#define GENMASK(h, l) __GENMASK(h, l)')
[void]$sb.AppendLine('#endif')
[void]$sb.AppendLine('int main(void) {')
$sortedConsts = $constNames | Sort-Object
foreach ($n in $sortedConsts) {
  [void]$sb.AppendLine("  printf(`"C $n %lld\n`", (long long)($n));")
}
$layoutNames = New-Object System.Collections.Generic.HashSet[string]
$layoutForStruct = @{}
foreach ($s in $structs) {
  $upper = $s.Name.ToUpper()
  $sizeName = "${upper}_SIZE"
  if ($constNames.Contains($sizeName)) { throw "layout name collides with a const: $sizeName" }
  if (-not $layoutNames.Add($sizeName)) { continue }
  [void]$sb.AppendLine("  printf(`"L $sizeName %lld\n`", (long long)sizeof(struct $($s.Name)));")
  $fList = New-Object System.Collections.Generic.List[object]
  foreach ($f in $s.Fields) {
    $offName = "${upper}_$($f.ToUpper())_OFF"
    if ($constNames.Contains($offName)) { throw "layout name collides with a const: $offName" }
    if (-not $layoutNames.Add($offName)) { throw "duplicate layout name: $offName" }
    [void]$sb.AppendLine("  printf(`"L $offName %lld\n`", (long long)offsetof(struct $($s.Name), $f));")
    $fList.Add([pscustomobject]@{ Field = $f; OffName = $offName })
  }
  $layoutForStruct[$s.Name] = [pscustomobject]@{ SizeName = $sizeName; Fields = $fList }
}
[void]$sb.AppendLine('  return 0;')
[void]$sb.AppendLine('}')
$dumperC = Join-Path $gen "v4l2_values_dumper.c"
[System.IO.File]::WriteAllText($dumperC, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
$wslDumperC = To-Wsl $dumperC
$dumpFile = Join-Path $gen "v4l2_consts_dump.txt"
$wslDump = To-Wsl $dumpFile
Invoke-Wsl "gcc $incFlags -O0 -o /tmp/xv-dumper '$wslDumperC' && /tmp/xv-dumper > '$wslDump'" | Out-Null

$values = @{}
$layout = @{}
$ln = 0
foreach ($line in (Get-Content -LiteralPath $dumpFile)) {
  $ln = $ln + 1
  if ($line -match '^C (\S+) (-?\d+)$') { $values[$Matches[1]] = [long]$Matches[2] }
  elseif ($line -match '^L (\S+) (-?\d+)$') { $layout[$Matches[1]] = [long]$Matches[2] }
  else { throw "unexpected dump line $ln" + ": $line" }
}
$expected = $constNames.Count + $layoutNames.Count
if ($ln -lt $expected) { throw "dump incomplete: $ln lines for $expected facts" }
$missing = @($sortedConsts | Where-Object { -not $values.ContainsKey($_) })
if ($missing.Count -gt 0) { throw "names missing from dump: $($missing -join ', ')" }
Write-Host ("  dump: {0} constants + {1} layout facts" -f $values.Count, $layout.Count)

# ---------------------------------------------------------------------------
# 4. Ownership split (consts.xi vs cids.xi) by raw header occurrence
# ---------------------------------------------------------------------------
function Get-Ownership([string]$name) {
  foreach ($h in $headers) {
    $t = $rawBodies[$h]
    $isDefine = [regex]::IsMatch($t, "(?m)^\s*#define\s+" + [regex]::Escape($name) + "\b")
    $isMember = [regex]::IsMatch($t, "(?m)^\s+" + [regex]::Escape($name) + "\s*(,|=)")
    if ($isDefine -or $isMember) { return $h }
  }
  return ""
}

function Format-Val([long]$v) {
  if ($v -lt 0) { return "$v" }
  if ($v -ge 4096) { return "0x" + $v.ToString("X") }
  return "$v"
}

function Emit-Module([string]$moduleName, [string]$title, [object[]]$entries, [string]$outPath) {
  $b = New-Object System.Text.StringBuilder
  [void]$b.AppendLine("// GENERATED FILE -- do not edit.")
  [void]$b.AppendLine("// $title")
  [void]$b.AppendLine("// Values evaluated from the pinned kernel UAPI text (torvalds/linux v6.19,")
  [void]$b.AppendLine("// commit $pinCommit) by docs/repro/gen-v4l2-consts.ps1; raw dump:")
  [void]$b.AppendLine("// docs/repro/gen/v4l2_consts_dump.txt (gcc against the pinned headers).")
  [void]$b.AppendLine("// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors")
  [void]$b.AppendLine("// Licensed under the MIT or Apache-2.0 license, at your option.")
  [void]$b.AppendLine("")
  [void]$b.AppendLine("module $moduleName")
  [void]$b.AppendLine("")
  $lastGroup = ""
  foreach ($e in $entries) {
    if ($e.Group -ne $lastGroup) {
      [void]$b.AppendLine("// $($e.Group)")
      $lastGroup = $e.Group
    }
    if ($e.StrVal) {
      [void]$b.AppendLine("pub const $($e.Name): Str = `"$($e.StrVal)`";")
    } else {
      [void]$b.AppendLine("pub const $($e.Name): Int = $(Format-Val $e.Value);")
    }
  }
  [System.IO.File]::WriteAllText($outPath, $b.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "  wrote $outPath ($($entries.Count) constants)"
}

$constEntries = New-Object System.Collections.Generic.List[object]
$cidEntries = New-Object System.Collections.Generic.List[object]
foreach ($n in $sortedConsts) {
  $owner = Get-Ownership $n
  if ($owner -eq "") { throw "constant not found in any pinned header text: $n" }
  if ($owner -eq "v4l2-controls.h") { $cidEntries.Add([pscustomobject]@{ Name = $n; Value = $values[$n]; Group = "v4l2-controls.h" }) }
  else { $constEntries.Add([pscustomobject]@{ Name = $n; Value = $values[$n]; Group = $owner }) }
}
foreach ($sc in $stringConsts) {
  $constEntries.Add([pscustomobject]@{ Name = $sc.Name; Value = 0; Group = "$($sc.Group) (string constant)"; StrVal = $sc.Value })
}

# layout module entries, grouped per struct
$layoutEntries = New-Object System.Collections.Generic.List[object]
foreach ($s in $structs) {
  $info = $layoutForStruct[$s.Name]
  $layoutEntries.Add([pscustomobject]@{ Name = $info.SizeName; Value = $layout[$info.SizeName]; Group = "struct $($s.Name)" })
  foreach ($f in $info.Fields) {
    $layoutEntries.Add([pscustomobject]@{ Name = $f.OffName; Value = $layout[$f.OffName]; Group = "struct $($s.Name)" })
  }
}

Emit-Module "xiom.v4l.consts" "xiom.v4l constants -- videodev2.h + v4l2-common.h (full public surface)." $constEntries (Join-Path $src "consts.xi")
Emit-Module "xiom.v4l.cids" "xiom.v4l constants -- v4l2-controls.h control-ID universe (full public surface)." $cidEntries (Join-Path $src "cids.xi")
Emit-Module "xiom.v4l.layout" "xiom.v4l struct layout facts -- sizeof/offsetof for every v4l2_* struct (LP64)." $layoutEntries (Join-Path $src "layout.xi")

# ---------------------------------------------------------------------------
# 5. _Static_assert gate + coverage table
# ---------------------------------------------------------------------------
$as = New-Object System.Text.StringBuilder
[void]$as.AppendLine("/* Generated by docs/repro/gen-v4l2-consts.ps1 -- do not edit.")
[void]$as.AppendLine(" * _Static_assert gate: every xiom.v4l constant and layout fact must equal")
[void]$as.AppendLine(" * the value the PINNED kernel UAPI headers produce (torvalds/linux v6.19,")
[void]$as.AppendLine(" * commit $pinCommit). Compiled by docs/repro/v4l2_abi_probe.c. */")
[void]$as.AppendLine('#include <stddef.h>')
[void]$as.AppendLine('#include <linux/bits.h>')
[void]$as.AppendLine('#include <linux/videodev2.h>')
[void]$as.AppendLine('/* Pinned-commit GENMASK fallback (see gen-v4l2-consts.ps1 / PROVENANCE.md). */')
[void]$as.AppendLine('#ifndef GENMASK')
[void]$as.AppendLine('#define GENMASK(h, l) __GENMASK(h, l)')
[void]$as.AppendLine('#endif')
[void]$as.AppendLine("")
foreach ($n in $sortedConsts) {
  [void]$as.AppendLine("_Static_assert((long long)($n) == ($($values[$n])), `"$n`");")
}
foreach ($sc in $stringConsts) {
  [void]$as.AppendLine("_Static_assert(sizeof($($sc.Name)) == sizeof(`"$($sc.Value)`"), `"$($sc.Name)`");")
}
foreach ($s in $structs) {
  $info = $layoutForStruct[$s.Name]
  [void]$as.AppendLine("_Static_assert(($($layout[$info.SizeName])) == (long long)sizeof(struct $($s.Name)), `"$($info.SizeName)`");")
  foreach ($f in $info.Fields) {
    [void]$as.AppendLine("_Static_assert(($($layout[$f.OffName])) == (long long)offsetof(struct $($s.Name), $($f.Field)), `"$($f.OffName)`");")
  }
}
[System.IO.File]::WriteAllText((Join-Path $gen "v4l2_const_asserts.h"), $as.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  wrote gen/v4l2_const_asserts.h ($($sortedConsts.Count + $layoutNames.Count) assertions)"

# family coverage table
function Get-Family([string]$n) {
  if ($n.StartsWith("VIDIOC_")) { return "VIDIOC_* (ioctls)" }
  $known = @("V4L2_PIX_FMT_", "V4L2_CID_", "V4L2_CAP_", "V4L2_BUF_TYPE_", "V4L2_MEMORY_", "V4L2_FIELD_",
    "V4L2_COLORSPACE_", "V4L2_XFER_FUNC_", "V4L2_YCBCR_ENC_", "V4L2_HSV_ENC_", "V4L2_QUANTIZATION_",
    "V4L2_BT_", "V4L2_DV_", "V4L2_CTRL_CLASS_", "V4L2_CTRL_FLAG_", "V4L2_CTRL_TYPE_", "V4L2_CTRL_WHICH_",
    "V4L2_EVENT_", "V4L2_STD_", "V4L2_SEL_", "V4L2_MPEG_", "V4L2_FWHT_", "V4L2_H264_", "V4L2_VP8_",
    "V4L2_VP9_", "V4L2_AV1_", "V4L2_FRAME_", "V4L2_JPEG_", "V4L2_TC_", "V4L2_BUF_FLAG_", "V4L2_FBUF_",
    "V4L2_PIX_FMT_FLAG_", "V4L2_SLICED_")
  foreach ($k in $known) { if ($n.StartsWith($k)) { return "$k*" } }
  $seg = $n.Split('_')
  if ($seg.Count -ge 2) { return "$($seg[0])_$($seg[1])_*" }
  return "$n"
}

$cov = New-Object System.Text.StringBuilder
[void]$cov.AppendLine("family`tcount`tmodule")
$famConsts = @{}
foreach ($e in $constEntries) { $f = Get-Family $e.Name; if (-not $famConsts.ContainsKey($f)) { $famConsts[$f] = 0 }; $famConsts[$f] = $famConsts[$f] + 1 }
foreach ($k in ($famConsts.Keys | Sort-Object)) { [void]$cov.AppendLine("$k`t$($famConsts[$k])`txiom.v4l.consts") }
$famCids = @{}
foreach ($e in $cidEntries) { $f = Get-Family $e.Name; if (-not $famCids.ContainsKey($f)) { $famCids[$f] = 0 }; $famCids[$f] = $famCids[$f] + 1 }
foreach ($k in ($famCids.Keys | Sort-Object)) { [void]$cov.AppendLine("$k`t$($famCids[$k])`txiom.v4l.cids") }
[void]$cov.AppendLine("struct-layout-facts`t$($layoutEntries.Count)`txiom.v4l.layout")
[void]$cov.AppendLine("TOTAL-constants`t$($constEntries.Count + $cidEntries.Count)`tconsts+cids")
[System.IO.File]::WriteAllText((Join-Path $gen "v4l2_coverage.tsv"), $cov.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "SUMMARY"
Write-Host ("  constants: {0} (consts.xi {1} + cids.xi {2})" -f ($constEntries.Count + $cidEntries.Count), $constEntries.Count, $cidEntries.Count)
Write-Host ("  structs:   {0}, layout facts: {1}" -f $structs.Count, $layoutEntries.Count)
Write-Host ("  function-like macros mirrored as XIOM fns: {0}" -f $fnMacroNames.Count)
$fnMacroNames | Sort-Object | ForEach-Object { Write-Host "    $_" }
