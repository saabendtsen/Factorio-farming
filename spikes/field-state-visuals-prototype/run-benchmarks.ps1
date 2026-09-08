param(
  [string[]]$Cases = @(),
  [string]$FactorioExe = 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'
)

$ErrorActionPreference = 'Stop'
$prototypeRoot = $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $env:LOCALAPPDATA "FactorioFarmingSpike2\$timestamp"
$factorioRoot = Split-Path (Split-Path (Split-Path $FactorioExe -Parent) -Parent) -Parent
$readData = Join-Path $factorioRoot 'data'

$caseDefinitions = @()
foreach ($mode in @('ranges', 'packed')) {
  foreach ($pattern in @('coherent', 'fragmented')) {
    foreach ($size in @(64, 256, 1024)) {
      $caseDefinitions += [pscustomobject]@{
        Name = "$mode-$pattern-$size"
        StateMode = $mode
        Pattern = $pattern
        FieldSize = $size
        VisualMode = 'none'
        VisualFields = 0
      }
    }
  }
}
foreach ($visualMode in @('tiles', 'render')) {
  foreach ($visualFields in @(1, 10)) {
    $logicalLabel = if ($visualFields -eq 1) { '1m' } else { '10m' }
    $caseDefinitions += [pscustomobject]@{
      Name = "$visualMode-$logicalLabel"
      StateMode = 'ranges'
      Pattern = 'coherent'
      FieldSize = 1024
      VisualMode = $visualMode
      VisualFields = $visualFields
    }
  }
}

if ($Cases.Count -gt 0) {
  $caseDefinitions = $caseDefinitions | Where-Object { $Cases -contains $_.Name }
}
if ($caseDefinitions.Count -eq 0) { throw 'No benchmark cases selected.' }

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$summaries = @()

function Get-ProfileMs([string]$Text, [string]$CaseName, [string]$Phase) {
  $escapedCase = [regex]::Escape($CaseName)
  $match = [regex]::Match($Text, "SPIKE2_PROFILE $escapedCase $Phase Duration:\s*([0-9.]+)ms")
  if (-not $match.Success) { return $null }
  return [double]$match.Groups[1].Value
}

function Get-LoadMs([string]$Text) {
  $loading = [regex]::Match($Text, '(?m)^\s*([0-9.]+) Loading map ')
  $checksumMatches = [regex]::Matches($Text, '(?m)^\s*([0-9.]+) Checksum for script __factorio-farming-field-spike__/control.lua')
  if (-not $loading.Success -or $checksumMatches.Count -eq 0) { return $null }
  $loaded = [double]$checksumMatches[$checksumMatches.Count - 1].Groups[1].Value
  return ($loaded - [double]$loading.Groups[1].Value) * 1000
}

foreach ($case in $caseDefinitions) {
  $caseRoot = Join-Path $runRoot $case.Name
  $writeData = Join-Path $caseRoot 'user-data'
  $modsRoot = Join-Path $caseRoot 'mods'
  $modRoot = Join-Path $modsRoot 'factorio-farming-field-spike_0.1.0'
  New-Item -ItemType Directory -Force -Path $writeData, $modsRoot, $modRoot | Out-Null

  foreach ($file in @('info.json', 'data.lua', 'control.lua')) {
    Copy-Item -LiteralPath (Join-Path $prototypeRoot $file) -Destination $modRoot
  }

  $configLua = @"
return {
  case_name = "$($case.Name)",
  state_mode = "$($case.StateMode)",
  pattern = "$($case.Pattern)",
  field_size = $($case.FieldSize),
  visual_mode = "$($case.VisualMode)",
  visual_fields = $($case.VisualFields),
  tile_batch_size = 16384
}
"@
  Set-Content -LiteralPath (Join-Path $modRoot 'config.lua') -Value $configLua -Encoding utf8

  $modList = @{
    mods = @(
      @{ name = 'base'; enabled = $true },
      @{ name = 'elevated-rails'; enabled = $false },
      @{ name = 'factorio-farming-field-spike'; enabled = $true },
      @{ name = 'quality'; enabled = $false },
      @{ name = 'space-age'; enabled = $false }
    )
  } | ConvertTo-Json -Depth 4
  Set-Content -LiteralPath (Join-Path $modsRoot 'mod-list.json') -Value $modList -Encoding utf8

  $configPath = Join-Path $caseRoot 'config.ini'
  $normalizedReadData = $readData.Replace('\', '/')
  $normalizedWriteData = $writeData.Replace('\', '/')
  @"
[path]
read-data=$normalizedReadData
write-data=$normalizedWriteData
"@ | Set-Content -LiteralPath $configPath -Encoding utf8

  $savePath = Join-Path $caseRoot 'projected.zip'
  $createLog = Join-Path $caseRoot 'create.log'
  & $FactorioExe --config $configPath --mod-directory $modsRoot --create $savePath --map-gen-seed 424242 --disable-audio 2>&1 |
    Set-Content -LiteralPath $createLog -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Map creation failed for $($case.Name)." }

  $loadLog = Join-Path $caseRoot 'load.log'
  $loadTicks = if ($case.VisualMode -eq 'none') { 1 } else { 2 }
  & $FactorioExe --config $configPath --mod-directory $modsRoot --benchmark $savePath --benchmark-ticks $loadTicks --benchmark-runs 1 --disable-audio 2>&1 |
    Set-Content -LiteralPath $loadLog -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Load benchmark failed for $($case.Name)." }

  $createText = Get-Content -Raw -LiteralPath $createLog
  $loadText = Get-Content -Raw -LiteralPath $loadLog
  $reportPath = Join-Path $writeData "script-output\factorio-farming-spike-2\$($case.Name).json"
  if (-not (Test-Path -LiteralPath $reportPath)) { throw "No report produced for $($case.Name)." }
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json

  $restorationMs = $null
  $restoredSaveBytes = $null
  $restoredLoadMs = $null
  if ($case.VisualMode -ne 'none') {
    $restorationMs = Get-ProfileMs $loadText $case.Name 'restoration'
    $serverLog = Join-Path $caseRoot 'restore.log'
    $serverSettingsPath = Join-Path $caseRoot 'server-settings.json'
    $serverSettings = Get-Content -Raw -LiteralPath (Join-Path $readData 'server-settings.example.json') | ConvertFrom-Json
    $serverSettings.auto_pause = $false
    $serverSettings.require_user_verification = $false
    $serverSettings.visibility.public = $false
    $serverSettings.visibility.lan = $false
    $serverSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $serverSettingsPath -Encoding utf8

    $restoredSave = Join-Path $writeData "saves\_autosave-spike2-$($case.Name)-restored.zip"
    $serverPort = 35000 + ($summaries.Count % 1000)
    $serverArguments = @(
      '--config', $configPath,
      '--mod-directory', $modsRoot,
      '--start-server', $savePath,
      '--server-settings', $serverSettingsPath,
      '--console-log', $serverLog,
      '--bind', "127.0.0.1:$serverPort",
      '--disable-audio'
    )
    $serverProcess = Start-Process -FilePath $FactorioExe -ArgumentList $serverArguments -PassThru -WindowStyle Hidden
    $saveDeadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $restoredSave) -and -not $serverProcess.HasExited -and (Get-Date) -lt $saveDeadline) {
      Start-Sleep -Milliseconds 200
      $serverProcess.Refresh()
    }
    if (-not (Test-Path -LiteralPath $restoredSave)) {
      if (-not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id }
      throw "Restored save missing for $($case.Name)."
    }
    Start-Sleep -Milliseconds 500
    if (-not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id }
    Wait-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue

    $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
    $restoredSaveBytes = (Get-Item -LiteralPath $restoredSave).Length

    $restoredLoadLog = Join-Path $caseRoot 'restored-load.log'
    & $FactorioExe --config $configPath --mod-directory $modsRoot --benchmark $restoredSave --benchmark-ticks 1 --benchmark-runs 1 --disable-audio 2>&1 |
      Set-Content -LiteralPath $restoredLoadLog -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "Restored load benchmark failed for $($case.Name)." }
    $restoredLoadMs = Get-LoadMs (Get-Content -Raw -LiteralPath $restoredLoadLog)
  }

  $summary = [ordered]@{
    case_name = $case.Name
    state_mode = $case.StateMode
    pattern = $case.Pattern
    field_size = $case.FieldSize
    visual_mode = $case.VisualMode
    visual_fields = $case.VisualFields
    logical_cells = $report.logical_cells
    completed_area = $report.state.completed_area
    range_count = $report.state.range_count
    numeric_endpoints = $report.state.numeric_endpoints
    chunk_count = $report.state.chunk_count
    encoded_bytes = $report.state.encoded_bytes
    overlap_passed = $report.state.overlap_passed
    interruption_resume_passed = $report.state.interruption_resume_passed
    state_build_ms = Get-ProfileMs $createText $case.Name 'state'
    projected_units = $report.visual_projected_units
    projection_ms = Get-ProfileMs $createText $case.Name 'projection'
    projected_save_bytes = (Get-Item -LiteralPath $savePath).Length
    projected_load_ms = Get-LoadMs $loadText
    restored_units = $report.visual_restored_units
    restoration_ms = $restorationMs
    restoration_passed = $report.restoration_passed
    restored_save_bytes = $restoredSaveBytes
    restored_load_ms = $restoredLoadMs
  }
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $caseRoot 'summary.json') -Encoding utf8
  $summaries += [pscustomobject]$summary
  Write-Host "$($case.Name): state $($summary.state_build_ms) ms, projection $($summary.projection_ms) ms, save $([Math]::Round($summary.projected_save_bytes / 1MB, 2)) MiB"
}

$summaries | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'summary.json') -Encoding utf8
$summaries | Export-Csv -LiteralPath (Join-Path $runRoot 'summary.csv') -NoTypeInformation -Encoding utf8
Write-Host "Spike artifacts: $runRoot"
