#!/usr/bin/env pwsh
# ============================================================================
# Registry Index Generator -- XIOM Package Registry (LEGACY local fallback)
# ============================================================================
# NOTE (legacy): https://registry.xiom-lang.org is the canonical package index.
# This generator exists only for the client's offline/local fallback index;
# keep the output shape stable (packages[] entries with name, version,
# description, source_files, dependencies, download_url, repository).
#
# Scans the packages/ directory and generates an index.json manifest.
# The package name is read from the package.xi `name:` field (dotted, e.g.
# "xiom.core"); the folder name is only a fallback when the manifest has no
# name. Release URLs stay folder-keyed because folders (and the future split
# repos) remain hyphenated.
#
# Output: packages/index.json
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
    $folderName = $_.Name
    # Package names are dotted (`xiom.core`); folders stay hyphenated. The
    # manifest `name:` is authoritative -- the registry never sees folders.
    $pkgName = $folderName

    # Read package.xi for version and metadata
    $pkgXi = Join-Path $pkgDir "package.xi"
    $version = "0.1.0"
    $description = ""
    $dependencies = @()

    if (Test-Path $pkgXi) {
        $content = Get-Content $pkgXi -Raw
        # Package name (dotted, e.g. "xiom.core"). Folder name is only a
        # fallback, and warns so a missing manifest is visible.
        if ($content -match 'name:\s*"([^"]*)"') { $pkgName = $matches[1] }
        elseif ($content -match 'name:\s*(\S+)') { $pkgName = ($matches[1] -replace '[;,"]', '') }
        else { Write-Warning "package.xi in $folderName has no name field; using folder name '$folderName'" }
        # Extract version (handle both "0.1.0" and 0.1.0 formats)
        if ($content -match 'version:\s*"([^"]*)"') { $version = $matches[1] }
        elseif ($content -match 'version:\s*(\S+)') { $version = ($matches[1] -replace '[;,"]', '') }
        # Extract description
        if ($content -match 'description:\s*"([^"]+)"') { $description = $matches[1] }
        # Extract runtime dependencies from `deps:` (not `dev-deps:`), which
        # may be inline (`deps: { "xiom.core": "0.1.0" };`) or multiline.
        # Dependency keys use dotted package names.
        if ($content -match '(?<![\w-])deps\s*:\s*\{([^}]*)\}') {
            $depsBlock = $matches[1]
            $depsBlock -split ',' | ForEach-Object {
                if ($_ -match '"([^"]+)"\s*:\s*"([^"]+)"') {
                    $dependencies += @{ name = $matches[1]; version = $matches[2] }
                }
            }
        }
    } else {
        Write-Warning "no package.xi in $folderName; using folder name '$folderName'"
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
        # Releases stay folder-keyed: folders (and future split repos) remain
        # hyphenated while package names are dotted.
        download_url = "$REGISTRY_BASE/$folderName/v$version/package.tar.gz"
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
