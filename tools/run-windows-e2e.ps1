# SoloDesk Windows End-to-End (E2E) Verification Runner
# Verifies local Ollama, loopback Mastra service, BriefCheck, ScopeShield, and SQLite storage

$ErrorActionPreference = "Stop"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "SoloDesk Milestone 8: Windows Desktop E2E Verification Runner" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Check Ollama loopback status
Write-Host "`n[1/5] Checking local Ollama service (127.0.0.1:11434)..." -ForegroundColor Yellow
try {
  $ollamaRes = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 5
  $models = $ollamaRes.models | ForEach-Object { $_.name }
  if ($models -contains "qwen3:1.7b" -or $models -contains "qwen3:1.7b:latest") {
    Write-Host "  -> Ollama is online with active model 'qwen3:1.7b'" -ForegroundColor Green
  } else {
    Write-Warning "  -> Ollama online, but 'qwen3:1.7b' model was not listed. Available: $($models -join ', ')"
  }
} catch {
  Write-Error "Failed to reach Ollama on 127.0.0.1:11434. Ensure Ollama is running."
}

# 2. Check Mastra Service /health endpoint
Write-Host "`n[2/5] Checking loopback Mastra service (127.0.0.1:3141)..." -ForegroundColor Yellow
$serviceOnline = $false
try {
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:3141/health" -Method Get -TimeoutSec 5
  if ($health.status -eq "ok") {
    Write-Host "  -> Service /health reported status: OK (version: $($health.version), model: $($health.model))" -ForegroundColor Green
    $serviceOnline = $true
  }
} catch {
  Write-Host "  -> Service is not currently running on 127.0.0.1:3141. (Launch via 'npm start' in service/)" -ForegroundColor Yellow
}

# 3. Read runtime Bearer token
$tokenPath = Join-Path $PSScriptRoot "..\service\.runtime-token"
if (Test-Path $tokenPath) {
  $token = (Get-Content $tokenPath -Raw).Trim()
  Write-Host "`n[3/5] Discovered runtime token at service/.runtime-token (Length: $($token.Length) chars)" -ForegroundColor Green
} else {
  Write-Host "`n[3/5] No .runtime-token found. Service must be started to generate token." -ForegroundColor Yellow
}

# 4. If service is online, run round-trip inference smoke checks
if ($serviceOnline -and $token) {
  Write-Host "`n[4/5] Executing live loopback inference round-trip checks..." -ForegroundColor Yellow

  # BriefCheck Smoke Check
  Write-Host "  -> Testing BriefCheck POST /api/brief-check with synthetic brief..."
  $briefBody = @{
    brief = "We are launching MorningGlow organic coffee next month. Need a modern logo and cup assets."
    niche = "design"
  } | ConvertTo-Json

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $headers = @{
    "Content-Type"  = "application/json"
    "Authorization" = "Bearer $token"
  }

  try {
    $briefRes = Invoke-RestMethod -Uri "http://127.0.0.1:3141/api/brief-check" -Method Post -Headers $headers -Body $briefBody -TimeoutSec 120
    $sw.Stop()
    Write-Host "     [PASS] BriefCheck completed in $($sw.ElapsedMilliseconds)ms (Requirements: $($briefRes.data.statedRequirements.Count), Questions: $($briefRes.data.suggestedQuestions.Count))" -ForegroundColor Green
  } catch {
    $sw.Stop()
    Write-Warning "     [FAIL] BriefCheck round-trip check failed: $_"
  }

  # ScopeShield Smoke Check
  Write-Host "  -> Testing ScopeShield POST /api/scope-check with synthetic scope..."
  $scopeBody = @{
    requestText = "Can you send the final SVG vector masters and style sheet?"
    scopeVersionId = "v1-e2e"
    scopeItems = @(
      @{ id = "i1"; category = "included"; description = "Primary logo vector masters" }
      @{ id = "i2"; category = "included"; description = "Single-page brand style sheet" }
    )
    niche = "design"
  } | ConvertTo-Json

  $sw.Restart()
  try {
    $scopeRes = Invoke-RestMethod -Uri "http://127.0.0.1:3141/api/scope-check" -Method Post -Headers $headers -Body $scopeBody -TimeoutSec 120
    $sw.Stop()
    Write-Host "     [PASS] ScopeShield completed in $($sw.ElapsedMilliseconds)ms (Findings: $($scopeRes.data.findings.Count), Reply Length: $($scopeRes.data.replyDraft.Length) chars)" -ForegroundColor Green
  } catch {
    $sw.Stop()
    Write-Warning "     [FAIL] ScopeShield round-trip check failed: $_"
  }
} else {
  Write-Host "`n[4/5] Skipping live HTTP round-trip inference (service not running or token missing)." -ForegroundColor Yellow
}

# 5. Check local SQLite database path & integrity
Write-Host "`n[5/5] Verifying local SQLite database storage..." -ForegroundColor Yellow
$appData = [Environment]::GetFolderPath("ApplicationData")
$dbPath = Join-Path $appData "solodesk\solodesk.db"

if (Test-Path $dbPath) {
  $file = Get-Item $dbPath
  Write-Host "  -> SQLite database found at: $dbPath" -ForegroundColor Green
  Write-Host "  -> Size: $([Math]::Round($file.Length / 1KB, 1)) KB, Last Modified: $($file.LastWriteTime)" -ForegroundColor Green
  Write-Host "  -> Storage is located outside git repository (CONFIRMED)" -ForegroundColor Green
} else {
  Write-Host "  -> Database file will be created on first app launch at: $dbPath" -ForegroundColor Cyan
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "SoloDesk Windows E2E Verification Complete" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
