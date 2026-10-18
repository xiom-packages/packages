# ============================================================================
# XIOM XVECTOR script helpers (dot-source) -- reliable process execution with
# output-file capture, a watchdog, and a trustworthy exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Why not Start-Process: on Windows PowerShell 5.1 `$proc.ExitCode` is
# frequently $null for redirected child processes (race between process
# object disposal and exit-code capture), which silently turns green runs
# red and vice versa. The .NET ProcessStartInfo path with async stream
# readers is deterministic and deadlock-free.

function Invoke-XvectorProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = "",
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$StdOutFile,
        [Parameter(Mandatory = $true)][string]$StdErrFile,
        [int]$TimeoutSec = 120
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($Arguments) { $psi.Arguments = $Arguments }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()

    $exited = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $exited) {
        try { $p.Kill() } catch { }
        $p.WaitForExit(10000) | Out-Null
    }

    $outText = try { $outTask.GetAwaiter().GetResult() } catch { "" }
    $errText = try { $errTask.GetAwaiter().GetResult() } catch { "" }
    Set-Content -LiteralPath $StdOutFile -Value $outText -NoNewline
    Set-Content -LiteralPath $StdErrFile -Value $errText -NoNewline

    return [pscustomobject]@{
        ExitCode  = if ($exited) { $p.ExitCode } else { 124 }
        TimedOut  = (-not $exited)
        StdOut    = $outText
        StdErr    = $errText
    }
}
