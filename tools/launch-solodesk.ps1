# SoloDesk Production Launcher
# Launches the local TypeScript/Mastra service, verifies health and runtime token,
# runs the native Flutter desktop app, and cleanly shuts down background processes on exit.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# If running from tools/ inside repo, adjust paths to repo structure.
# If running from release package root, app and service are direct subdirectories.
if (Test-Path (Join-Path $ScriptDir "app\solodesk.exe")) {
    $AppExe = Join-Path $ScriptDir "app\solodesk.exe"
    $ServiceDir = Join-Path $ScriptDir "service"
} elseif (Test-Path (Join-Path $ScriptDir "..\app\build\windows\x64\runner\Release\solodesk.exe")) {
    $AppExe = Resolve-Path (Join-Path $ScriptDir "..\app\build\windows\x64\runner\Release\solodesk.exe")
    $ServiceDir = Resolve-Path (Join-Path $ScriptDir "..\service")
} elseif (Test-Path (Join-Path $ScriptDir "..\app\build\windows\x64\runner\Debug\solodesk.exe")) {
    $AppExe = Resolve-Path (Join-Path $ScriptDir "..\app\build\windows\x64\runner\Debug\solodesk.exe")
    $ServiceDir = Resolve-Path (Join-Path $ScriptDir "..\service")
} else {
    Write-Host "[ERROR] Could not locate solodesk.exe." -ForegroundColor Red
    Write-Host "Please build the application first: flutter build windows --release" -ForegroundColor Yellow
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SoloDesk v0.1.0-challenge - Local Desktop Workspace" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check Node.js
Write-Host "[1/4] Checking Node.js runtime..." -ForegroundColor Yellow
try {
    $nodeVersion = & node -v
    Write-Host "  Node.js: $nodeVersion detected." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Node.js is not found in PATH." -ForegroundColor Red
    Write-Host "Please install Node.js LTS (v20+) from https://nodejs.org/" -ForegroundColor Yellow
    pause
    exit 1
}

# 2. Check Ollama loopback
Write-Host "[2/4] Checking Ollama local inference server (127.0.0.1:11434)..." -ForegroundColor Yellow
$ollamaReady = $false
try {
    $ollamaTags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 3 -ErrorAction Stop
    $ollamaReady = $true
    $hasModel = $false
    if ($ollamaTags.models) {
        foreach ($m in $ollamaTags.models) {
            if ($m.name -like "*qwen3:1.7b*") {
                $hasModel = $true
                break
            }
        }
    }
    if ($hasModel) {
        Write-Host "  Ollama: Running on 127.0.0.1:11434 with model 'qwen3:1.7b' ready." -ForegroundColor Green
    } else {
        Write-Host "  Ollama: Running, but model 'qwen3:1.7b' was not found in local models." -ForegroundColor Yellow
        Write-Host "  Run 'ollama pull qwen3:1.7b' to download the local model weights." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARNING] Ollama server is not running on 127.0.0.1:11434." -ForegroundColor Yellow
    Write-Host "  Please start Ollama for Windows to enable local AI workflows." -ForegroundColor Yellow
}

# 3. Check or Start Mastra Loopback Service (127.0.0.1:3141)
Write-Host "[3/4] Checking Mastra local loopback service (127.0.0.1:3141)..." -ForegroundColor Yellow
$serviceProcess = $null
$serviceAlreadyRunning = $false

try {
    $healthCheck = Invoke-RestMethod -Uri "http://127.0.0.1:3141/health" -Method Get -TimeoutSec 2 -ErrorAction Stop
    if ($healthCheck.status -eq "ok") {
        Write-Host "  Mastra service is already running on port 3141." -ForegroundColor Green
        $serviceAlreadyRunning = $true
    }
} catch {
    # Not running, spawn it
    Write-Host "  Starting local Mastra service from $ServiceDir..." -ForegroundColor Cyan
    
    $serviceEntry = Join-Path $ServiceDir "dist\index.js"
    if (-not (Test-Path $serviceEntry)) {
        # Fallback to tsx dev if dist not built
        if (Test-Path (Join-Path $ServiceDir "src\index.ts")) {
            $serviceProcess = Start-Process -FilePath "npx" -ArgumentList "tsx src/index.ts" -WorkingDirectory $ServiceDir -WindowStyle Hidden -PassThru
        } else {
            Write-Host "[ERROR] Could not find service entry at $serviceEntry" -ForegroundColor Red
            exit 1
        }
    } else {
        $serviceProcess = Start-Process -FilePath "node" -ArgumentList "dist/index.js" -WorkingDirectory $ServiceDir -WindowStyle Hidden -PassThru
    }

    # Wait for service health
    $retries = 20
    $healthy = $false
    while ($retries -gt 0 -and -not $healthy) {
        Start-Sleep -Milliseconds 500
        try {
            $h = Invoke-RestMethod -Uri "http://127.0.0.1:3141/health" -Method Get -TimeoutSec 1 -ErrorAction Stop
            if ($h.status -eq "ok") {
                $healthy = $true
            }
        } catch {
            $retries--
        }
    }

    if ($healthy) {
        Write-Host "  Mastra service successfully started and verified healthy." -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] Service health check timed out. Proceeding to launch app." -ForegroundColor Yellow
    }
}

# Discover Runtime Token and export to environment
$tokenFile = Join-Path $ServiceDir ".runtime-token"
if (Test-Path $tokenFile) {
    $env:SOLODESK_RUNTIME_TOKEN = (Get-Content $tokenFile -Raw).Trim()
    Write-Host "  Runtime Bearer token discovered and configured in session." -ForegroundColor Green
}

# 4. Launch Native Flutter Desktop Application
Write-Host "[4/4] Launching SoloDesk Desktop..." -ForegroundColor Yellow
Write-Host "  Executable: $AppExe" -ForegroundColor Cyan
Write-Host ""
Write-Host "SoloDesk is running. Closing the window will cleanly shut down background services." -ForegroundColor DarkGray
Write-Host ""

try {
    # Launch Flutter synchronously
    $appProcess = Start-Process -FilePath $AppExe -PassThru -Wait
} finally {
    # Clean shutdown of spawned service
    if ($serviceProcess -and -not $serviceProcess.HasExited) {
        Write-Host ""
        Write-Host "Stopping background Mastra service (PID: $($serviceProcess.Id))..." -ForegroundColor Cyan
        Stop-Process -Id $serviceProcess.Id -Force -ErrorAction SilentlyContinue
        Write-Host "SoloDesk terminated cleanly." -ForegroundColor Green
    }
}
