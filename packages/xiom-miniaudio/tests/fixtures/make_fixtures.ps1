#!/usr/bin/env pwsh
# ============================================================================
# xiom.miniaudio -- regenerate the streamed-decode fixtures (dev-time only).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# The fixtures are a 64-frame 8 kHz mono s16 tone: four periods of the same
# 16-sample sine table the compile unit embeds (kSine16 in
# src/miniaudio_all.c), so the FLAC round trip can be compared sample-exact
# in tests/test_conformance.xi.
#
#   tone.flac  -- lossless encode of the tone (dr_flac decode is bit-exact)
#   tone.mp3   -- 64 kbps CBR MPEG-2.5 Layer III of the tone (lossy; the
#                 suite checks rate/channels/frame-count/energy, not samples)
#
# Usage (needs a local ffmpeg on PATH or pass -Ffmpeg):
#   .\make_fixtures.ps1 -Ffmpeg "C:\Program Files\Krita (x64)\bin\ffmpeg.exe"
#
# The test suite never runs this script; it only reads the committed
# fixtures. See tests/fixtures/README.md for the recorded hashes.
[CmdletBinding()]
param(
    [string]$Ffmpeg = "ffmpeg"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $PSCommandPath

# kSine16 (must stay in sync with src/miniaudio_all.c).
$sine16 = @(0, 7653, 14142, 18477, 20000, 18477, 14142, 7653,
            0, -7653, -14142, -18477, -20000, -18477, -14142, -7653)
$frames = 64
$samples = @()
for ($i = 0; $i -lt $frames; $i++) { $samples += $sine16[$i % 16] }

# Build the source WAV byte-wise (8 kHz mono s16).
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$dataSize = $frames * 2
$bw.Write([char[]]"RIFF"); $bw.Write([uint32](36 + $dataSize))
$bw.Write([char[]]"WAVE"); $bw.Write([char[]]"fmt ")
$bw.Write([uint32]16); $bw.Write([uint16]1); $bw.Write([uint16]1)
$bw.Write([uint32]8000); $bw.Write([uint32]16000); $bw.Write([uint16]2); $bw.Write([uint16]16)
$bw.Write([char[]]"data"); $bw.Write([uint32]$dataSize)
foreach ($s in $samples) { $bw.Write([int16]$s) }
$bw.Flush()
$src = Join-Path $env:TEMP "xma_tone_src.wav"
[System.IO.File]::WriteAllBytes($src, $ms.ToArray())

& $Ffmpeg -y -hide_banner -loglevel error -i $src -c:a flac -compression_level 12 (Join-Path $here "tone.flac")
if ($LASTEXITCODE -ne 0) { throw "flac encode failed" }
& $Ffmpeg -y -hide_banner -loglevel error -i $src -c:a libmp3lame -b:a 64k -ar 8000 -ac 1 (Join-Path $here "tone.mp3")
if ($LASTEXITCODE -ne 0) { throw "mp3 encode failed" }
Remove-Item -LiteralPath $src

Get-ChildItem -LiteralPath $here -Filter "tone.*" | ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    Write-Host ("{0}  {1} bytes  SHA256 {2}" -f $_.Name, $_.Length, $hash)
}
