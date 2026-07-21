#!/usr/bin/env pwsh
# ============================================================================
# Registry Index Generator — XIOM Package Registry
# ============================================================================
# Scans the packages/ directory and generates an index.json manifest.
# Each package gets a version entry based on its package.xi version field.
#
# Output: packages/index.json
# Format:  { "version": 1, "packages": [{ "name": "...", "versions": [...] }] }
#
# Usage: .\generate_index.ps1
#        .\generate_index.ps1 -RepoRoot "E:\Projects\AXIOM"
# ============================================================================

param(
    [string]$RepoRoot = ""
)

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSCommandPath
}

$packagesDir = Join-Path $RepoRoot "packages"
if (-not (Test-Path $packagesDir)) {
    Write-Error "packages/ directory not found at $packagesDir"
    exit 1
}

# GitHub org and repo for package hosting
$GITHUB_ORG = "xiom-lang"
$REGISTRY_BASE = "https://github.com/$GITHUB_ORG/packages/releases/download"

$registry = @{
    version = 1
    updated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    registry_url = "https://registry.xiom-lang.org"
    packages = @()
}

Get-ChildItem $packagesDir -Directory | ForEach-Object {
    $pkgDir = $_.FullName
    $pkgName = $_.Name

    # Read package.xi for version and metadata
    $pkgXi = Join-Path $pkgDir "package.xi"
    $version = "0.1.0"
    $description = ""
    $dependencies = @()

    if (Test-Path $pkgXi) {
        $content = Get-Content $pkgXi -Raw
        # Extract version (handle both "0.1.0" and 0.1.0 formats)
        if ($content -match 'version:\s*"([^"]*)"') { $version = $matches[1] }
        elseif ($content -match 'version:\s*(\S+)') { $version = ($matches[1] -replace '[;,"]', '') }
        # Extract description
        if ($content -match 'description:\s*"([^"]+)"') { $description = $matches[1] }
        # Extract dependencies
        if ($content -match 'dependencies:\s*\{([^}]+)\}') {
            $depsBlock = $matches[1]
            $depsBlock -split ',' | ForEach-Object {
                if ($_ -match '"([^"]+)"\s*:\s*"([^"]+)"') {
                    $dependencies += @{ name = $matches[1]; version = $matches[2] }
                }
            }
        }
    }

    # Count source files
    $sourceFiles = @()
    $srcDir = Join-Path $pkgDir "src"
    if (Test-Path $srcDir) {
        Get-ChildItem $srcDir -Recurse -Filter "*.xi" | ForEach-Object {
            $sourceFiles += $_.Name
        }
    }
    # Root-level .xi files
    Get-ChildItem $pkgDir -Filter "*.xi" | ForEach-Object {
        $sourceFiles += $_.Name
    }

    $pkgEntry = @{
        name = $pkgName
        version = $version
        description = $description
        source_files = $sourceFiles
        dependencies = $dependencies
        download_url = "$REGISTRY_BASE/$pkgName/v$version/package.tar.gz"
        repository = "https://github.com/$GITHUB_ORG/packages"
    }

    $registry.packages += $pkgEntry
}

# Sort by name
$registry.packages = @($registry.packages | Sort-Object { $_.name })

# Write index.json
$indexPath = Join-Path $packagesDir "index.json"
$json = $registry | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($indexPath, $json)
Write-Output "Generated index.json: $indexPath"
Write-Output "Packages indexed: $($registry.packages.Count)"
