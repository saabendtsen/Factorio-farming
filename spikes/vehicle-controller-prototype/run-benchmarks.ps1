param(
  [int[]]$VehicleCounts = @(1, 10, 100, 200, 300),
  [int]$Ticks = 7200,
  [int]$Runs = 3,
  [string]$FactorioExe = 'D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe'
)

$ErrorActionPreference = 'Stop'

$prototypeRoot = $PSScriptRoot
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $env:LOCALAPPDATA "FactorioFarmingSpike1\$timestamp"
$readData = Split-Path (Split-Path (Split-Path $FactorioExe -Parent) -Parent) -Parent
$readData = Join-Path $readData 'data'

New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$summaries = @()

foreach ($count in $VehicleCounts) {
  $caseRoot = Join-Path $runRoot "vehicles-$count"
  $writeData = Join-Path $caseRoot 'user-data'
  $modsRoot = Join-Path $caseRoot 'mods'
  $modRoot = Join-Path $modsRoot 'factorio-farming-vehicle-spike_0.1.0'
  New-Item -ItemType Directory -Force -Path $writeData, $modsRoot, $modRoot | Out-Null

  Copy-Item -LiteralPath (Join-Path $prototypeRoot 'info.json') -Destination $modRoot
  Copy-Item -LiteralPath (Join-Path $prototypeRoot 'control.lua') -Destination $modRoot

  $reportTick = $Ticks - 1
  $configLua = @"
return {
  vehicle_count = $count,
  cadence = 3,
  report_tick = $reportTick,
  obstruct_first_vehicle = true
}
"@
  Set-Content -LiteralPath (Join-Path $modRoot 'config.lua') -Value $configLua -Encoding utf8

  $modList = @{
    mods = @(
      @{ name = 'base'; enabled = $true },
      @{ name = 'elevated-rails'; enabled = $false },
      @{ name = 'factorio-farming-vehicle-spike'; enabled = $true },
      @{ name = 'quality'; enabled = $false },
      @{ name = 'space-age'; enabled = $false }
    )
  } | ConvertTo-Json -Depth 4
  Set-Content -LiteralPath (Join-Path $modsRoot 'mod-list.json') -Value $modList -Encoding utf8

  $configPath = Join-Path $caseRoot 'config.ini'
  $normalizedReadData = $readData.Replace('\', '/')
  $normalizedWriteData = $writeData.Replace('\', '/')
  $configIni = @"
[path]
read-data=$normalizedReadData
write-data=$normalizedWriteData
"@
  Set-Content -LiteralPath $configPath -Value $configIni -Encoding utf8

  $savePath = Join-Path $caseRoot 'initial.zip'
  $createLog = Join-Path $caseRoot 'create.log'
  $benchmarkLog = Join-Path $caseRoot 'benchmark.log'

  & $FactorioExe --config $configPath --mod-directory $modsRoot --create $savePath --map-gen-seed 424242 --disable-audio 2>&1 |
    Set-Content -LiteralPath $createLog -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Factorio map creation failed for $count vehicles." }

  & $FactorioExe --config $configPath --mod-directory $modsRoot --benchmark $savePath --benchmark-ticks $Ticks --benchmark-runs $Runs --benchmark-sanitize --disable-audio 2>&1 |
    Set-Content -LiteralPath $benchmarkLog -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Factorio benchmark failed for $count vehicles." }

  $profileLog = Join-Path $caseRoot 'profile.log'
  & $FactorioExe --config $configPath --mod-directory $modsRoot --benchmark $savePath --benchmark-ticks 600 --benchmark-runs 1 --benchmark-verbose all --disable-audio 2>&1 |
    Set-Content -LiteralPath $profileLog -Encoding utf8
  if ($LASTEXITCODE -ne 0) { throw "Factorio profile failed for $count vehicles." }

  $benchmarkText = Get-Content -Raw -LiteralPath $benchmarkLog
  $benchmarkMatches = [regex]::Matches($benchmarkText, 'avg:\s+([0-9.]+) ms, min:\s+([0-9.]+) ms, max:\s+([0-9.]+) ms')
  if ($benchmarkMatches.Count -eq 0) { throw "Could not parse benchmark timings for $count vehicles." }
  $averageUpdateMs = ($benchmarkMatches | ForEach-Object { [double]$_.Groups[1].Value } | Measure-Object -Average).Average
  $maxUpdateMs = ($benchmarkMatches | ForEach-Object { [double]$_.Groups[3].Value } | Measure-Object -Maximum).Maximum

  $profileLines = Get-Content -LiteralPath $profileLog
  $headerIndex = -1
  for ($lineIndex = 0; $lineIndex -lt $profileLines.Count; $lineIndex++) {
    if ($profileLines[$lineIndex].StartsWith('tick,timestamp,')) {
      $headerIndex = $lineIndex
      break
    }
  }
  if ($headerIndex -lt 0) { throw "Could not find verbose profile header for $count vehicles." }

  $headers = $profileLines[$headerIndex].TrimEnd(',').Split(',')
  $profileRows = @()
  for ($lineIndex = $headerIndex + 1; $lineIndex -lt $profileLines.Count; $lineIndex++) {
    if ($profileLines[$lineIndex] -match '^t\d+,') {
      $values = $profileLines[$lineIndex].TrimEnd(',').Split(',')
      $row = @{}
      for ($column = 0; $column -lt [Math]::Min($headers.Count, $values.Count); $column++) {
        $row[$headers[$column]] = $values[$column]
      }
      $profileRows += $row
    }
  }

  function Get-ProfileAverageMs([string]$Name) {
    $samples = $profileRows | ForEach-Object { if ($_.ContainsKey($Name)) { [double]$_[$Name] } }
    if (-not $samples) { return $null }
    return ($samples | Measure-Object -Average).Average / 1000000
  }

  $reportPath = Join-Path $writeData "script-output\factorio-farming-spike-1\result-$count.json"
  if (-not (Test-Path -LiteralPath $reportPath)) { throw "The mod did not write a result for $count vehicles." }
  $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
  $summary = [ordered]@{
    vehicle_count = $count
    benchmark_runs = $Runs
    benchmark_ticks = $Ticks
    average_update_ms = [Math]::Round($averageUpdateMs, 3)
    max_update_ms = [Math]::Round($maxUpdateMs, 3)
    average_update_budget_percent = [Math]::Round(($averageUpdateMs / (1000 / 60)) * 100, 2)
    profile_ticks = $profileRows.Count
    average_script_update_ms = [Math]::Round((Get-ProfileAverageMs 'scriptUpdate'), 4)
    average_pathfinder_ms = [Math]::Round((Get-ProfileAverageMs 'pathFinder'), 4)
    average_car_entity_ms = [Math]::Round((Get-ProfileAverageMs 'Car'), 4)
    completed = $report.completed
    failed = $report.failed
    completion_tick = $report.tick
    path_requests = $report.path_requests
    path_deferrals = $report.path_deferrals
    average_path_end_to_end_ticks = [Math]::Round($report.path_end_to_end_latency_ticks_average, 2)
    max_path_end_to_end_ticks = $report.path_end_to_end_latency_ticks_max
    stuck_events = $report.stuck_events
    repaths = $report.repaths
    average_arrival_error_tiles = [Math]::Round($report.arrival_error_tiles_average, 3)
    max_arrival_error_tiles = [Math]::Round($report.arrival_error_tiles_max, 3)
  }
  $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $caseRoot 'summary.json') -Encoding utf8
  $summaries += [pscustomobject]$summary
  Write-Host "$count vehicles: $($summary.completed)/$count complete, avg $($summary.average_update_ms) ms/update, script $($summary.average_script_update_ms) ms/update"
}

$summaries | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'summary.json') -Encoding utf8
$summaries | Export-Csv -LiteralPath (Join-Path $runRoot 'summary.csv') -NoTypeInformation -Encoding utf8
Write-Host "Spike artifacts: $runRoot"
