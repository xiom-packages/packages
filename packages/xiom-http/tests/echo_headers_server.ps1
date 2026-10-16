#!/usr/bin/env pwsh
# echo_headers_server.ps1 -- loopback header-echo endpoint for the xiom.http
# live header probe (tests/probe_real_libcurl.xi, leg 2).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Listens on 127.0.0.1:18094 (the loopback convention shared with
# probe_client's POST leg) and answers every request with 200 and a body
# that reflects the raw request head (request line + headers + blank line)
# followed by "BODY:" and the request body text. The live probe asserts
# that the reflected head contains the custom headers it sent
# (X-Xiom-Probe + Authorization), so a bridge that drops headers makes the
# probe fail loudly.
#
# Run in a second terminal, then run probe_real_libcurl.xi:
#   pwsh -File packages\xiom-http\tests\echo_headers_server.ps1
# Stop with Ctrl+C. One instance only (the port must stay free).
$ErrorActionPreference = "Stop"

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 18094)
$listener.Start()
Write-Host "echo_headers_server: listening on 127.0.0.1:18094 (Ctrl+C to stop)"
try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $headBytes = New-Object System.Collections.Generic.List[byte]
      $state = 0
      while ($state -lt 4) {
        $b = $stream.ReadByte()
        if ($b -lt 0) { break }
        $headBytes.Add([byte]$b)
        if ($state -eq 0 -and $b -eq 13) { $state = 1 }
        elseif ($state -eq 1 -and $b -eq 10) { $state = 2 }
        elseif ($state -eq 2 -and $b -eq 13) { $state = 3 }
        elseif ($state -eq 3 -and $b -eq 10) { $state = 4 }
        else { $state = 0 }
      }
      $headText = [System.Text.Encoding]::ASCII.GetString($headBytes.ToArray())
      $len = 0
      foreach ($line in ($headText -split "`r`n")) {
        if ($line -match "^Content-Length:\s*(\d+)\s*$") { $len = [int]$Matches[1] }
      }
      $bodyText = ""
      if ($len -gt 0) {
        $buf = New-Object byte[] ([Math]::Max($len, 1))
        $read = 0
        while ($read -lt $len) {
          $n = $stream.Read($buf, $read, $len - $read)
          if ($n -le 0) { break }
          $read += $n
        }
        $bodyText = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
      }
      $respBody = $headText + "BODY:" + $bodyText
      $respBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($respBody)
      $respHead = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: " + $respBodyBytes.Length + "`r`nConnection: close`r`n`r`n"
      $resp = [System.Text.Encoding]::ASCII.GetBytes($respHead)
      $stream.Write($resp, 0, $resp.Length)
      $stream.Write($respBodyBytes, 0, $respBodyBytes.Length)
      $stream.Flush()
    } finally {
      $client.Close()
    }
  }
} finally {
  $listener.Stop()
}
