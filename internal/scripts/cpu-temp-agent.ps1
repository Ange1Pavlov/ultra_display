param(
    [int]$IntervalSeconds = 5
)

$mutexCreated = $false
try {
    $script:CpuAgentMutex = New-Object System.Threading.Mutex($false, 'Global\UltraDisplay.CpuTempAgent', [ref]$mutexCreated)
} catch {
    $script:CpuAgentMutex = New-Object System.Threading.Mutex($false, 'UltraDisplay.CpuTempAgent', [ref]$mutexCreated)
}
if (-not $mutexCreated) {
    Write-Host 'cpu-temp-agent: existing instance detected, exiting.'
    exit 0
}

$ErrorActionPreference = 'SilentlyContinue'
$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$cacheDir = Join-Path $projectRoot 'cache'
$cachePath = Join-Path $cacheDir 'cpu_temp_agent.json'
$ohmExe = Join-Path $projectRoot 'internal\tools\ohm_runtime\OpenHardwareMonitor\OpenHardwareMonitor.exe'
$startedOhmPid = 0

if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }

function Write-AgentCache {
    param($Temp, [string]$Source)
    $normalized = $null
    if ($null -ne $Temp) {
        try { $normalized = [int]$Temp } catch { $normalized = $null }
    }
    @{
        updatedAt = (Get-Date).ToString('s')
        cpuTemp = $normalized
        source = $Source
    } | ConvertTo-Json | Set-Content -Path $cachePath -Encoding UTF8
}

function Get-CPUTempFromOhmWmi {
    try {
        $rows = Get-CimInstance -Namespace root/OpenHardwareMonitor -ClassName Sensor -ErrorAction Stop |
            Where-Object { $_.SensorType -eq 'Temperature' }
        if (-not $rows) { return $null }

        $bestTemp = $null
        $bestScore = -1
        foreach ($r in $rows) {
            $name = ([string]$r.Name).ToLowerInvariant()
            $id = ([string]$r.Identifier).ToLowerInvariant()
            if (($name -notmatch 'cpu|package|tctl|tdie|die') -and ($id -notmatch '/amdcpu/.*/temperature|/intelcpu/.*/temperature')) {
                continue
            }
            $n = [double]$r.Value
            if ($n -lt 10 -or $n -gt 120) { continue }
            $score = 1
            if ($name -match 'package|tctl|tdie') { $score = 3 }
            elseif ($name -match 'cpu|die') { $score = 2 }
            if ($score -gt $bestScore) {
                $bestScore = $score
                $bestTemp = [math]::Round($n, 0)
            }
        }
        return $bestTemp
    } catch {
        return $null
    }
}

try {
    Write-AgentCache -Temp $null -Source 'starting'

    if (Test-Path $ohmExe) {
        $proc = Get-CimInstance Win32_Process -Filter "name='OpenHardwareMonitor.exe'" | Where-Object {
            ([string]$_.ExecutablePath).ToLowerInvariant() -eq $ohmExe.ToLowerInvariant()
        } | Select-Object -First 1
        if (-not $proc) {
            $p = Start-Process -FilePath $ohmExe -WorkingDirectory (Split-Path $ohmExe -Parent) -WindowStyle Hidden -PassThru
            $startedOhmPid = $p.Id
            Start-Sleep -Seconds 2
        }
    }

    while ($true) {
        $temp = Get-CPUTempFromOhmWmi
        if ($temp -ne $null) {
            Write-AgentCache -Temp $temp -Source 'ohm_wmi'
        } else {
            Write-AgentCache -Temp $null -Source 'none'
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    if ($startedOhmPid -gt 0) {
        Stop-Process -Id $startedOhmPid -Force -ErrorAction SilentlyContinue
    }
}
