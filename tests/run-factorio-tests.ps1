# Isolated Factorio 2.1 test harness for the production farming slice.
#
# Stages:
#   1. functional  - fresh map, full acceptance flow (headless benchmark)
#   2. capture     - fresh map driven in real time, saved in each controller
#                    phase plus a clean performance reference save
#   3. saveload    - each phase save is loaded and driven to exact completion
#   4. benchmark   - five-minute reference run with the script profiler enabled
#
# Everything lives under %LOCALAPPDATA%\FactorioFarmingProductionTests and no
# personal Factorio mods, saves, or configuration are touched.

[CmdletBinding()]
param(
  [string]$FactorioExe = "D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe",
  [switch]$SkipBenchmark
)

$ErrorActionPreference = "Stop"

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$TestRoot   = Join-Path $env:LOCALAPPDATA "FactorioFarmingProductionTests"
$RunRoot    = Join-Path $TestRoot "current"
$ModRoot    = Join-Path $RunRoot "mods"
$WriteRoot  = Join-Path $RunRoot "write-data"
$LogRoot    = Join-Path $RunRoot "logs"
$SavesRoot  = Join-Path $WriteRoot "saves"
$OutputRoot = Join-Path $WriteRoot "script-output\factorio-farming-tests"
$TestModDir = Join-Path $ModRoot "factorio-farming-tests_0.1.0"

# Slice acceptance gates from docs/technical/first-production-vertical-slice.md.
$AverageBudgetMs = 0.25
$P95BudgetMs     = 0.50

$script:Failures = @()

function Write-Stage($text) { Write-Host ""; Write-Host "=== $text ===" }
function Write-Pass($text)  { Write-Host "  PASS  $text" }
function Write-Fail($text)  { Write-Host "  FAIL  $text"; $script:Failures += $text }

if (-not (Test-Path $FactorioExe)) {
  Write-Host "Factorio was not found at $FactorioExe"
  exit 1
}

# ------------------------------------------------------------------ staging

if (Test-Path $RunRoot) { Remove-Item -LiteralPath $RunRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ModRoot, $WriteRoot, $LogRoot, $TestModDir | Out-Null
$ModDir = Join-Path $ModRoot "factorio-farming_0.1.0"
New-Item -ItemType Directory -Force -Path $ModDir | Out-Null

& robocopy $RepoRoot $ModDir /E /XD .git tests docs /XF dashboard.html | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Failed to stage the production mod" }
& robocopy (Join-Path $PSScriptRoot "factorio-farming-tests") $TestModDir /E | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Failed to stage the test mod" }

'{"mods":[{"name":"base","enabled":true},{"name":"factorio-farming","enabled":true},{"name":"factorio-farming-tests","enabled":true}]}' |
  Out-File -FilePath (Join-Path $ModRoot "mod-list.json") -Encoding ascii

$writeForIni = $WriteRoot -replace '\\', '/'
@(
  "[path]",
  "read-data=__PATH__executable__/../../data",
  "write-data=$writeForIni"
) | Out-File -FilePath (Join-Path $RunRoot "config.ini") -Encoding ascii

# auto_pause must be off or a headless server with no players never ticks.
'{"name":"farming-slice-capture","description":"","visibility":{"public":false,"lan":false},"auto_pause":false,"require_user_verification":false}' |
  Out-File -FilePath (Join-Path $RunRoot "server-settings.json") -Encoding ascii

$ConfigIni = Join-Path $RunRoot "config.ini"

function Set-TestMode($mode) {
  "return `"$mode`"" | Out-File -FilePath (Join-Path $TestModDir "mode.lua") -Encoding ascii
}

function Save-StageLog($stage) {
  $current = Join-Path $WriteRoot "factorio-current.log"
  $target = Join-Path $LogRoot "$stage.log"
  if (Test-Path $current) { Copy-Item -LiteralPath $current -Destination $target -Force }
  return $target
}

function Invoke-Factorio($stage, [string[]]$factorioArgs) {
  $arguments = @("--config", $ConfigIni, "--mod-directory", $ModRoot, "--disable-audio") + $factorioArgs
  $proc = Start-Process -FilePath $FactorioExe -ArgumentList $arguments -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput (Join-Path $LogRoot "$stage.stdout.log") `
    -RedirectStandardError (Join-Path $LogRoot "$stage.stderr.log")
  Save-StageLog $stage | Out-Null
  return $proc.ExitCode
}

function Get-Result($name) {
  $path = Join-Path $OutputRoot "$name.json"
  if (-not (Test-Path $path)) { return $null }
  return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Show-ScriptError($stage) {
  $log = Join-Path $LogRoot "$stage.log"
  if (Test-Path $log) {
    Select-String -Path $log -Pattern "FACTORIO_FARMING_TEST_FAILURE|Error " |
      Select-Object -First 5 | ForEach-Object { Write-Host "        $($_.Line.Trim())" }
  }
}

# --------------------------------------------------------------- functional

Write-Stage "Stage 1/4  functional acceptance flow"
Set-TestMode "functional"
$functionalSave = Join-Path $RunRoot "slice-test.zip"
Invoke-Factorio "functional-create" @("--create", $functionalSave) | Out-Null
if (-not (Test-Path $functionalSave)) { Write-Fail "functional map creation"; }
else {
  Invoke-Factorio "functional" @("--benchmark", $functionalSave, "--benchmark-ticks", "12000", "--benchmark-runs", "1") | Out-Null
  $result = Get-Result "result"
  if ($result -and $result.passed) {
    Write-Pass "acceptance flow completed at tick $($result.tick): $($result.completed_area)/$($result.total_area) tiles"
  } else {
    Write-Fail "acceptance flow"
    Show-ScriptError "functional"
  }
}

# ------------------------------------------------------------------ capture

Write-Stage "Crop cycle acceptance flow"
Set-TestMode "cycle"
$cycleSave = Join-Path $RunRoot "cycle-test.zip"
Invoke-Factorio "cycle-create" @("--create", $cycleSave) | Out-Null
if (-not (Test-Path $cycleSave)) { Write-Fail "crop cycle map creation" }
else {
  Invoke-Factorio "cycle" @("--benchmark", $cycleSave, "--benchmark-ticks", "95000", "--benchmark-runs", "1") | Out-Null
  $cycle = Get-Result "cycle"
  if ($cycle -and $cycle.passed) { Write-Pass "crop cycle: $($cycle.wheat) wheat from $($cycle.completed_area) cultivated tiles" }
  else { Write-Fail "crop cycle acceptance flow"; Show-ScriptError "cycle" }
}

# ------------------------------------------------------------------ capture

Write-Stage "Stage 2/4  capture a save in every controller phase"
Set-TestMode "capture"
$captureSave = Join-Path $RunRoot "capture.zip"
Invoke-Factorio "capture-create" @("--create", $captureSave) | Out-Null

$capturedPhases = @()
if (-not (Test-Path $captureSave)) {
  Write-Fail "capture map creation"
} else {
  # A headless server is the only mode that honours game.auto_save; --benchmark
  # silently ignores it. The run is real time, so it is polled and then stopped.
  $captureResultPath = Join-Path $OutputRoot "capture.json"
  $proc = Start-Process -FilePath $FactorioExe -PassThru `
    -ArgumentList @("--config", $ConfigIni, "--mod-directory", $ModRoot, "--disable-audio",
                    "--start-server", $captureSave,
                    "--server-settings", (Join-Path $RunRoot "server-settings.json")) `
    -RedirectStandardOutput (Join-Path $LogRoot "capture.stdout.log") `
    -RedirectStandardError (Join-Path $LogRoot "capture.stderr.log")

  $deadline = (Get-Date).AddMinutes(6)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $captureResultPath) { break }
    if ($proc.HasExited) { break }
    Start-Sleep -Milliseconds 500
  }
  Start-Sleep -Seconds 2
  if (-not $proc.HasExited) { try { Stop-Process -Id $proc.Id -Force } catch {} }
  Start-Sleep -Seconds 1
  Save-StageLog "capture" | Out-Null

  $capture = Get-Result "capture"
  if ($capture -and $capture.passed) {
    $capturedPhases = @($capture.saved)
    Write-Pass "captured phases: $($capturedPhases -join ', ')"
  } else {
    Write-Fail "phase capture"
    Show-ScriptError "capture"
  }
}

# ----------------------------------------------------------------- saveload

Write-Stage "Stage 3/4  load each phase save and drive it to completion"
Set-TestMode "replay"
foreach ($phase in @("reserved", "travelling", "working", "paused")) {
  if ($capturedPhases -notcontains $phase) { Write-Fail "save/load $phase (no save captured)"; continue }
  $save = Get-ChildItem -LiteralPath $SavesRoot -Filter "*phase-$phase.zip" -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $save) { Write-Fail "save/load $phase (save file missing)"; continue }
  Invoke-Factorio "saveload-$phase" @("--benchmark", $save.FullName, "--benchmark-ticks", "20000", "--benchmark-runs", "1") | Out-Null
  $result = Get-Result "saveload-$phase"
  if ($result -and $result.passed) {
    Write-Pass ("save/load in {0}: loaded {1} tiles, completed {2}/{3} in {4} ticks" -f `
      $phase, $result.loaded_area, $result.completed_area, $result.total_area, $result.ticks_after_load)
  } else {
    Write-Fail "save/load $phase"
    Show-ScriptError "saveload-$phase"
  }
}

# ---------------------------------------------------------------- benchmark

function Get-Percentile($sorted, $fraction) {
  if ($sorted.Count -eq 0) { return 0 }
  $index = [Math]::Ceiling($fraction * $sorted.Count) - 1
  if ($index -lt 0) { $index = 0 }
  if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
  return $sorted[$index]
}

Write-Stage "Stage 4/4  five-minute performance reference run"
if ($SkipBenchmark) {
  Write-Host "  skipped by request"
} elseif ($capturedPhases -notcontains "benchmark") {
  Write-Fail "benchmark (no reference save captured)"
} else {
  $save = Get-ChildItem -LiteralPath $SavesRoot -Filter "*phase-benchmark.zip" -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if (-not $save) {
    Write-Fail "benchmark (save file missing)"
  } else {
    Invoke-Factorio "benchmark" @("--benchmark", $save.FullName, "--benchmark-ticks", "18100", "--benchmark-runs", "1") | Out-Null
    $result = Get-Result "benchmark"
    $log = Join-Path $LogRoot "benchmark.log"
    $all = New-Object System.Collections.Generic.List[double]
    $active = New-Object System.Collections.Generic.List[double]
    if (Test-Path $log) {
      foreach ($line in [System.IO.File]::ReadLines($log)) {
        if ($line -match 'FARMING_PROFILE (\d+) (\d+) Duration: ([0-9.]+)ms') {
          $ms = [double]$Matches[3]
          $all.Add($ms)
          if ([int]$Matches[2] -gt 0) { $active.Add($ms) }
        }
      }
    }
    if (-not $result -or -not $result.passed -or $all.Count -eq 0) {
      Write-Fail "benchmark run"
      Show-ScriptError "benchmark"
    } else {
      $allSorted = ($all | Sort-Object)
      $activeSorted = ($active | Sort-Object)
      $allAvg = ($all | Measure-Object -Average).Average
      $allP95 = Get-Percentile $allSorted 0.95
      $activeAvg = if ($active.Count) { ($active | Measure-Object -Average).Average } else { 0 }
      $activeP95 = Get-Percentile $activeSorted 0.95

      Write-Host ("  profiled ticks      : {0} ({1:N1} s at 60 UPS)" -f $all.Count, ($all.Count / 60))
      Write-Host ("  active-job ticks    : {0}" -f $active.Count)
      Write-Host ("  field completed tick: {0}" -f $result.field_completed_tick)
      Write-Host ("  whole run   average {0:N4} ms   p95 {1:N4} ms" -f $allAvg, $allP95)
      Write-Host ("  active work average {0:N4} ms   p95 {1:N4} ms" -f $activeAvg, $activeP95)

      if ($activeAvg -le $AverageBudgetMs) {
        Write-Pass ("average script update {0:N4} ms <= {1} ms" -f $activeAvg, $AverageBudgetMs)
      } else {
        Write-Fail ("average script update {0:N4} ms > {1} ms" -f $activeAvg, $AverageBudgetMs)
      }
      if ($activeP95 -le $P95BudgetMs) {
        Write-Pass ("p95 script update {0:N4} ms <= {1} ms" -f $activeP95, $P95BudgetMs)
      } else {
        Write-Fail ("p95 script update {0:N4} ms > {1} ms" -f $activeP95, $P95BudgetMs)
      }

      [pscustomobject]@{
        profiled_ticks     = $all.Count
        active_ticks       = $active.Count
        seconds            = [Math]::Round($all.Count / 60, 1)
        whole_run_avg_ms   = [Math]::Round($allAvg, 4)
        whole_run_p95_ms   = [Math]::Round($allP95, 4)
        active_avg_ms      = [Math]::Round($activeAvg, 4)
        active_p95_ms      = [Math]::Round($activeP95, 4)
        average_budget_ms  = $AverageBudgetMs
        p95_budget_ms      = $P95BudgetMs
        field_completed_tick = $result.field_completed_tick
      } | ConvertTo-Json | Out-File -FilePath (Join-Path $OutputRoot "performance.json") -Encoding ascii
    }
  }
}

# ------------------------------------------------------------------ summary

Write-Stage "Summary"
if ($script:Failures.Count -eq 0) {
  Write-Host "  All Factorio production slice gates passed."
  Write-Host "  Artifacts: $OutputRoot"
  exit 0
}
Write-Host "  $($script:Failures.Count) gate(s) failed:"
foreach ($failure in $script:Failures) { Write-Host "    - $failure" }
Write-Host "  Logs: $LogRoot"
exit 1
