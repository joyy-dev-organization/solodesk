# SoloDesk Release Packaging Engine
# Builds Flutter Windows Release, builds Mastra TypeScript service,
# stages complete standalone bundle with lean production dependencies,
# verifies all critical manifest files, and packages into solodesk-v0.1.0-windows-x64.zip.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$AppDir = Join-Path $RepoRoot "app"
$ServiceDir = Join-Path $RepoRoot "service"
$ReleaseRoot = Join-Path $RepoRoot "release"
$BundleDir = Join-Path $ReleaseRoot "solodesk-v0.1.0-windows-x64"
$ZipPath = Join-Path $ReleaseRoot "solodesk-v0.1.0-windows-x64.zip"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SoloDesk v0.1.0-challenge - Release Packager" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot" -ForegroundColor DarkGray
Write-Host ""

# Clean prior release directory
if (Test-Path $BundleDir) {
    Write-Host "Cleaning previous staged bundle..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $BundleDir
}
if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}
New-Item -ItemType Directory -Path $BundleDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $BundleDir "app") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $BundleDir "service") -Force | Out-Null

# 1. Compile Flutter Windows Release
Write-Host "[1/6] Compiling Flutter Windows release..." -ForegroundColor Yellow
Push-Location $AppDir
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build windows --release failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# 2. Compile TypeScript Mastra Service
Write-Host "[2/6] Compiling Mastra service production build..." -ForegroundColor Yellow
Push-Location $ServiceDir
try {
    & npm run build
    if ($LASTEXITCODE -ne 0) {
        throw "npm run build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# 3. Stage Flutter Windows Runner Manifest
Write-Host "[3/6] Staging complete Flutter Windows release runner manifest..." -ForegroundColor Yellow
$FlutterReleaseSource = Join-Path $AppDir "build\windows\x64\runner\Release"
if (-not (Test-Path $FlutterReleaseSource)) {
    throw "Flutter Release directory not found at $FlutterReleaseSource"
}

# Copy all files except .pdb (symbols) to reduce archive size
Get-ChildItem -Path $FlutterReleaseSource -Recurse | ForEach-Object {
    if ($_.Extension -ne ".pdb") {
        $relativePath = Resolve-Path $_.FullName -Relative
        $targetPath = Join-Path (Join-Path $BundleDir "app") ($_.FullName.Substring($FlutterReleaseSource.Length + 1))
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        } else {
            $parent = Split-Path -Parent $targetPath
            if (-not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetPath -Force
        }
    }
}

# Verify Mandatory Manifest Files
$RequiredFiles = @(
    "app\solodesk.exe",
    "app\flutter_windows.dll",
    "app\sqlite3.dll",
    "app\sqlite3_flutter_libs_plugin.dll",
    "app\data\icudtl.dat",
    "app\data\app.so"
)

Write-Host "  Verifying Flutter runtime manifest..." -ForegroundColor DarkGray
foreach ($rf in $RequiredFiles) {
    $fullRf = Join-Path $BundleDir $rf
    if (-not (Test-Path $fullRf)) {
        throw "CRITICAL RELEASE MANIFEST FAILURE: Missing $rf in staged package!"
    }
    Write-Host "    [OK] $rf" -ForegroundColor Green
}

# 4. Stage Lean Service Production Dependencies
Write-Host "[4/6] Staging Mastra production service and dependencies..." -ForegroundColor Yellow
$StagedServiceDir = Join-Path $BundleDir "service"
Copy-Item -Path (Join-Path $ServiceDir "dist") -Destination (Join-Path $StagedServiceDir "dist") -Recurse -Force
Copy-Item -Path (Join-Path $ServiceDir "package.json") -Destination (Join-Path $StagedServiceDir "package.json") -Force

Write-Host "  Installing production-only dependencies (omitting vitest/tsx/typescript)..." -ForegroundColor DarkGray
Push-Location $StagedServiceDir
try {
    # Install only production dependencies
    & npm install --omit=dev --no-audit --no-fund --loglevel=error
    if ($LASTEXITCODE -ne 0) {
        throw "npm install --omit=dev failed in staged service folder with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# 5. Package Launchers, License, and Clean-Machine README
Write-Host "[5/6] Bundling launchers, license, and quick-start instructions..." -ForegroundColor Yellow
Copy-Item -Path (Join-Path $ScriptDir "launch-solodesk.bat") -Destination (Join-Path $BundleDir "launch-solodesk.bat") -Force
Copy-Item -Path (Join-Path $ScriptDir "launch-solodesk.ps1") -Destination (Join-Path $BundleDir "launch-solodesk.ps1") -Force
if (Test-Path (Join-Path $RepoRoot "LICENSE")) {
    Copy-Item -Path (Join-Path $RepoRoot "LICENSE") -Destination (Join-Path $BundleDir "LICENSE") -Force
}

# Create README.txt with clean-machine instructions
$ReadmeTxtContent = @"
========================================================================
  SoloDesk v0.1.0-challenge - Windows Desktop Release
  Local AI Productivity Workspace for Independent Freelancers
========================================================================

SoloDesk is a local desktop application built with Flutter/Dart and a
local TypeScript/Mastra service orchestrating local open-weight models
(qwen3:1.7b) through Ollama. All client brief analysis, scope verification,
invoicing, and proposal drafting execute entirely on your machine without
sending client text to cloud models.

SYSTEM PREREQUISITES
--------------------
1. Windows 10/11 64-bit (x64)
2. Microsoft Visual C++ 2015-2022 Redistributable (x64)
   Download if needed: https://aka.ms/vs/17/release/vc_redist.x64.exe
3. Node.js LTS (v20+ or v22+): https://nodejs.org/
4. Ollama for Windows: https://ollama.com/download/windows
5. Local Model Weights:
   Open PowerShell and pull the open-weight model:
     ollama pull qwen3:1.7b

HOW TO LAUNCH
-------------
Double-click:
  launch-solodesk.bat
Or run in PowerShell:
  powershell -ExecutionPolicy Bypass -File .\launch-solodesk.ps1

The launcher automatically:
- Verifies Node.js and Ollama
- Starts the local Mastra backend service on 127.0.0.1:3141
- Generates an ephemeral local Bearer token for session security
- Launches the native solodesk.exe desktop window
- Cleanly terminates background processes when the window is closed

DATA STORAGE & PRIVACY
----------------------
- Relational data is stored locally in SQLite at:
  %APPDATA%\solodesk\solodesk.db
- Data at rest is unencrypted and protected by Windows user profile permissions.
- Network activity is restricted strictly to loopback (127.0.0.1).
- Offline use: SoloDesk operates 100% disconnected from the internet.

CLEAN-MACHINE / SMARTSCREEN NOTICE
----------------------------------
This hackathon submission executable is unsigned. Windows SmartScreen may
show an 'Unknown Publisher' notice on first run. Click 'More info' -> 'Run anyway'.

REPOSITORY & LICENSE
--------------------
GitHub: https://github.com/joyy-dev-organization/solodesk
License: MIT License (c) 2026 ladydiamond
"@

Set-Content -Path (Join-Path $BundleDir "README.txt") -Value $ReadmeTxtContent -Encoding UTF8
Write-Host "  [OK] README.txt and launchers staged." -ForegroundColor Green

# 6. Compress Release Bundle into ZIP using tar.exe (supports long paths in deep node_modules)
Write-Host "[6/6] Compressing release package into solodesk-v0.1.0-windows-x64.zip..." -ForegroundColor Yellow
Push-Location $BundleDir
try {
    & tar.exe -a -c -f $ZipPath *
} finally {
    Pop-Location
}

$zipFileInfo = Get-Item $ZipPath
$zipSizeMb = [math]::Round($zipFileInfo.Length / 1MB, 2)
$hash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  SoloDesk Release Packaging Complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Archive Path : $ZipPath" -ForegroundColor White
Write-Host "Archive Size : $zipSizeMb MB" -ForegroundColor White
Write-Host "SHA256 Hash  : $hash" -ForegroundColor White
Write-Host "Staged Folder: $BundleDir" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green
