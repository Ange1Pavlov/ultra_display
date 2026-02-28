param(
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$pidFile = Join-Path $projectRoot 'logs\display-pids.json'
$genScript = (Join-Path $projectRoot 'internal\src\generate-frame.ps1').ToLowerInvariant()
$uploadScript = (Join-Path $scriptsRoot 'upload-live.ps1').ToLowerInvariant()
$cpuAgentScript = (Join-Path $scriptsRoot 'cpu-temp-agent.ps1').ToLowerInvariant()
$cpuAgentToken = 'cpu-temp-agent.ps1'
$ohmExe = (Join-Path $projectRoot 'internal\tools\ohm_runtime\OpenHardwareMonitor\OpenHardwareMonitor.exe').ToLowerInvariant()
$legacyGenScript = (Join-Path $projectRoot 'src\generate-frame.ps1').ToLowerInvariant()
$legacyUploadScript = (Join-Path $projectRoot 'upload-live.ps1').ToLowerInvariant()

function Stop-PidIfRunning {
    param([int]$Pid)
    if ($Pid -le 0) { return }
    $p = Get-Process -Id $Pid -ErrorAction SilentlyContinue
    if ($p) { Stop-Process -Id $Pid -Force -ErrorAction SilentlyContinue }
}

# 1) Stop previously tracked PIDs first.
if (Test-Path $pidFile) {
    try {
        $data = Get-Content -Path $pidFile -Raw | ConvertFrom-Json
        Stop-PidIfRunning -Pid ([int]$data.generatorPid)
        Stop-PidIfRunning -Pid ([int]$data.uploaderPid)
        Stop-PidIfRunning -Pid ([int]$data.cpuAgentPid)
    } catch { }
}

# 2) Safety sweep: stop matching project processes by command line.
# Include both Windows PowerShell and PowerShell 7 hosts.
$procs = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(powershell|pwsh)\.exe$'
}
foreach ($proc in $procs) {
    $cmd = [string]$proc.CommandLine
    if (-not $cmd) { continue }
    $cmdL = $cmd.ToLowerInvariant()
    if ($cmdL.Contains($genScript) -or $cmdL.Contains($uploadScript) -or $cmdL.Contains($cpuAgentScript) -or $cmdL.Contains($cpuAgentToken) -or $cmdL.Contains($legacyGenScript) -or $cmdL.Contains($legacyUploadScript)) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# 3) Stop OHM runtime process from project path.
$ohmProcs = Get-CimInstance Win32_Process -Filter "name = 'OpenHardwareMonitor.exe'"
foreach ($p in $ohmProcs) {
    $exe = ([string]$p.ExecutablePath).ToLowerInvariant()
    if ($exe -eq $ohmExe) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue

if (-not $Quiet) {
    Write-Host 'Stopped display services (generator + uploader + cpuAgent).'
}
