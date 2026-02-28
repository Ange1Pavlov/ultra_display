$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$stopScript = Join-Path $scriptsRoot 'stop-display.ps1'
$pidFile = Join-Path $projectRoot 'logs\display-pids.json'
if (-not (Test-Path (Split-Path -Parent $pidFile))) { New-Item -ItemType Directory -Path (Split-Path -Parent $pidFile) -Force | Out-Null }

# Cleanly stop old project processes before starting new ones.
& $stopScript -Quiet

$genScript = Join-Path $projectRoot 'internal\src\generate-frame.ps1'
$renderOnceScript = Join-Path $projectRoot 'internal\src\render-once.ps1'
$uploadScript = Join-Path $scriptsRoot 'upload-live.ps1'
$cpuAgentScript = Join-Path $scriptsRoot 'cpu-temp-agent.ps1'
$settingsPath = Join-Path $projectRoot 'settings.json'
$framePath = Join-Path $projectRoot 'frame.jpg'

$refreshIntervalSeconds = 2
try {
    if (Test-Path $settingsPath) {
        $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
        if ($settings.refreshIntervalSeconds) {
            $val = [int]$settings.refreshIntervalSeconds
            if ($val -ge 2 -and $val -le 120) { $refreshIntervalSeconds = $val }
        }
    }
} catch { }

# Prevent stale frame flash on startup.
Remove-Item -Path $framePath -Force -ErrorAction SilentlyContinue

$cpuAgentProc = Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $cpuAgentScript)
) -WindowStyle Hidden -WorkingDirectory $projectRoot -PassThru

# Render one frame immediately with current settings before uploader loop starts.
Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $renderOnceScript)
) -WindowStyle Hidden -WorkingDirectory $projectRoot -Wait | Out-Null

$genProc = Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $genScript),
    '-intervalSeconds', $refreshIntervalSeconds
) -WindowStyle Hidden -WorkingDirectory $projectRoot -PassThru

$uploadProc = Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $uploadScript),
    '-intervalSeconds', $refreshIntervalSeconds
) -WindowStyle Hidden -WorkingDirectory $projectRoot -PassThru

@{
    startedAt = (Get-Date).ToString('s')
    generatorPid = $genProc.Id
    uploaderPid = $uploadProc.Id
    cpuAgentPid = $cpuAgentProc.Id
} | ConvertTo-Json | Set-Content -Path $pidFile -Encoding UTF8

Write-Host ("Started display services. generator PID={0}, uploader PID={1}, cpuAgent PID={2}" -f $genProc.Id, $uploadProc.Id, $cpuAgentProc.Id)
