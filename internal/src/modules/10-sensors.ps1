# sensor getters: CPU via background agent + LHM + WMI fallback, GPU via nvidia-smi
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve) '00-utils.ps1')

$Script:SensorModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve
$Script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $Script:SensorModuleRoot '..\..\..'))
$Script:CpuAgentCachePath = Join-Path $Script:ProjectRoot 'cache\cpu_temp_agent.json'
$Script:CpuAgentCacheReadAt = [datetime]::MinValue
$Script:CpuAgentCacheTemp = $null
$Script:CpuAgentCacheSource = ''
$Script:CpuAgentWarnedMissing = $false
$Script:NVWarnedMissing = $false
$Script:LhmDllPath = Join-Path $Script:ProjectRoot 'internal\tools\lhm_runtime\LibreHardwareMonitorLib.dll'
$Script:LhmWarnedMissing = $false
$Script:LhmInitWarnedAt = [datetime]::MinValue
$Script:LhmReady = $false
$Script:LhmComputer = $null
$Script:CpuTempLogLastAt = [datetime]::MinValue
$Script:CpuTempLogLastValue = $null
$Script:CpuTempLogLastSource = ''
$Script:LhmZeroWarnedAt = [datetime]::MinValue

function Get-CPUTempFromAgent {
    $now = Get-Date
    if (($now - $Script:CpuAgentCacheReadAt).TotalSeconds -lt 3) {
        return $Script:CpuAgentCacheTemp
    }

    if (-not (Test-Path $Script:CpuAgentCachePath)) {
        if (-not $Script:CpuAgentWarnedMissing) {
            Write-DebugLine ("CPU agent cache missing at {0}" -f $Script:CpuAgentCachePath)
            $Script:CpuAgentWarnedMissing = $true
        }
        $Script:CpuAgentCacheTemp = $null
        $Script:CpuAgentCacheSource = ''
        $Script:CpuAgentCacheReadAt = $now
        return $null
    }

    try {
        $item = Get-Item -Path $Script:CpuAgentCachePath -ErrorAction Stop
        if (($now - $item.LastWriteTime).TotalSeconds -gt 20) {
            $Script:CpuAgentCacheTemp = $null
            $Script:CpuAgentCacheSource = ''
            $Script:CpuAgentCacheReadAt = $now
            return $null
        }

        $obj = Get-Content -Path $Script:CpuAgentCachePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $temp = $null
        if ($null -ne $obj.cpuTemp) {
            $parsed = [double]$obj.cpuTemp
            if ($parsed -ge 10 -and $parsed -le 120) {
                $temp = [math]::Round($parsed, 0)
            }
        }
        $Script:CpuAgentCacheTemp = $temp
        if ($temp -ne $null -and $obj.PSObject.Properties.Name -contains 'source' -and $obj.source) {
            $Script:CpuAgentCacheSource = [string]$obj.source
        } else {
            $Script:CpuAgentCacheSource = ''
        }
        $Script:CpuAgentCacheReadAt = $now
        $Script:CpuAgentWarnedMissing = $false
        return $temp
    } catch {
        $Script:CpuAgentCacheTemp = $null
        $Script:CpuAgentCacheSource = ''
        $Script:CpuAgentCacheReadAt = $now
        return $null
    }
}

function Get-CPUTempFromWMI {
    try {
        $zones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        if ($zones) {
            foreach ($z in $zones) {
                $raw = [double]$z.CurrentTemperature
                if ($raw -gt 0) {
                    $c = ($raw / 10.0) - 273.15
                    if ($c -ge 10 -and $c -le 120) { return [math]::Round($c, 0) }
                }
            }
        }
    } catch { }
    return $null
}

function Initialize-LHM {
    if ($Script:LhmReady -and $Script:LhmComputer) { return $true }
    if (-not (Test-Path $Script:LhmDllPath)) {
        if (-not $Script:LhmWarnedMissing) {
            Write-DebugLine ("LHM: dll missing at {0}" -f $Script:LhmDllPath)
            $Script:LhmWarnedMissing = $true
        }
        return $false
    }

    try {
        $depRoot = Split-Path -Parent $Script:LhmDllPath
        Get-ChildItem -Path $depRoot -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
            try { [System.Reflection.Assembly]::LoadFrom($_.FullName) | Out-Null } catch { }
        }

        if (-not ("LibreHardwareMonitor.Hardware.Computer" -as [type])) {
            Add-Type -Path $Script:LhmDllPath -ErrorAction Stop
        }

        $comp = New-Object LibreHardwareMonitor.Hardware.Computer
        $comp.IsCpuEnabled = $true
        $comp.Open()
        $Script:LhmComputer = $comp
        $Script:LhmReady = $true
        Write-DebugLine 'LHM: initialized'
        return $true
    } catch {
        if ((Get-Date) -gt $Script:LhmInitWarnedAt.AddMinutes(5)) {
            Write-DebugLine ("LHM init err: {0}" -f $_.Exception.Message)
            if ($_.Exception.LoaderExceptions) {
                foreach ($lex in $_.Exception.LoaderExceptions) {
                    if ($lex -and $lex.Message) {
                        Write-DebugLine ("LHM loader err: {0}" -f $lex.Message)
                    }
                }
            }
            $Script:LhmInitWarnedAt = Get-Date
        }
        $Script:LhmComputer = $null
        $Script:LhmReady = $false
        return $false
    }
}

function Get-CPUTempFromLHM {
    if (-not (Initialize-LHM)) { return $null }
    try {
        $bestTemp = $null
        $bestScore = -1
        $cpuNodes = New-Object System.Collections.Generic.List[object]

        function Add-HardwareRecursive {
            param($node, [System.Collections.Generic.List[object]]$bucket)
            if ($null -eq $node) { return }
            try { $node.Update() } catch { }
            $bucket.Add($node) | Out-Null
            foreach ($child in $node.SubHardware) {
                Add-HardwareRecursive -node $child -bucket $bucket
            }
        }

        foreach ($hw in $Script:LhmComputer.Hardware) {
            if ($hw.HardwareType.ToString() -eq 'Cpu') {
                Add-HardwareRecursive -node $hw -bucket $cpuNodes
            }
        }

        foreach ($node in $cpuNodes) {
            foreach ($s in $node.Sensors) {
                if ($s.SensorType.ToString() -ne 'Temperature') { continue }
                if ($null -eq $s.Value) { continue }
                $n = [double]$s.Value
                if ($n -lt 10 -or $n -gt 120) { continue }
                $name = ([string]$s.Name).ToLowerInvariant()
                $score = 1
                if ($name -match 'package|tctl|tdie') { $score = 4 }
                elseif ($name -match 'cpu|die|ccd') { $score = 2 }
                if ($score -gt $bestScore) {
                    $bestScore = $score
                    $bestTemp = [math]::Round($n, 0)
                }
            }
        }

        if ($bestTemp -eq $null) {
            # AMD systems can expose Tctl/Tdie as 0 when low-level access is blocked.
            $hadZeroCpuTemp = $false
            foreach ($node in $cpuNodes) {
                foreach ($s in $node.Sensors) {
                    if ($s.SensorType.ToString() -ne 'Temperature') { continue }
                    if ($null -eq $s.Value) { continue }
                    $name = ([string]$s.Name).ToLowerInvariant()
                    if ($name -match 'tctl|tdie|cpu|package|die') {
                        $v = [double]$s.Value
                        if ($v -le 0) { $hadZeroCpuTemp = $true; break }
                    }
                }
                if ($hadZeroCpuTemp) { break }
            }
            if ($hadZeroCpuTemp -and (Get-Date) -gt $Script:LhmZeroWarnedAt.AddMinutes(5)) {
                Write-DebugLine 'LHM: CPU temp sensor is present but returns 0 (likely missing elevated hardware access).'
                $Script:LhmZeroWarnedAt = Get-Date
            }
        }

        return $bestTemp
    } catch {
        Write-DebugLine ("LHM read err: {0}" -f $_.Exception.Message)
        try { if ($Script:LhmComputer) { $Script:LhmComputer.Close() } } catch { }
        $Script:LhmComputer = $null
        $Script:LhmReady = $false
        return $null
    }
}

function Get-GPUSensorsFromNV {
    try {
        $n = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if (-not $n) {
            if (-not $Script:NVWarnedMissing) {
                Write-DebugLine "nvidia-smi not found"
                $Script:NVWarnedMissing = $true
            }
            return $null
        }
        $out = & $n.Source --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null
        if (-not $out) { return $null }

        $parts = ($out -split ',') | ForEach-Object { $_.Trim() }
        if ($parts.Count -lt 2) { return $null }

        $temp = [double]::Parse($parts[0], [System.Globalization.CultureInfo]::InvariantCulture)
        $util = [double]::Parse($parts[1], [System.Globalization.CultureInfo]::InvariantCulture)
        return @{ temp = $temp; util = $util }
    } catch {
        Write-DebugLine ("Get-GPUSensorsFromNV err: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-GPULoad {
    $nv = Get-GPUSensorsFromNV
    if ($nv) { return [math]::Round($nv.util, 1) }
    return 0
}

function Get-GPUTemp {
    $nv = Get-GPUSensorsFromNV
    if ($nv) { return [math]::Round($nv.temp, 0) }
    return $null
}

function Get-CPUUsage {
    try {
        $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
        return [math]::Round($c.CounterSamples[0].CookedValue, 1)
    } catch {
        Write-DebugLine ("Get-CPUUsage err: {0}" -f $_.Exception.Message)
        return 0
    }
}

function Get-MemInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalKB = [float]$os.TotalVisibleMemorySize
        $freeKB = [float]$os.FreePhysicalMemory
        $usedKB = $totalKB - $freeKB
        return @{
            TotalMB = [math]::Round($totalKB / 1024, 0)
            UsedMB  = [math]::Round($usedKB / 1024, 0)
            UsedPct = [math]::Round(($usedKB / $totalKB) * 100, 0)
        }
    } catch {
        Write-DebugLine ("Get-MemInfo err: {0}" -f $_.Exception.Message)
        return @{ TotalMB = 0; UsedMB = 0; UsedPct = 0 }
    }
}

function Get-CPUTemp {
    $source = ''
    $temp = $null
    $agentTemp = Get-CPUTempFromAgent
    if ($agentTemp -ne $null) {
        $temp = $agentTemp
        $source = if ($Script:CpuAgentCacheSource) { $Script:CpuAgentCacheSource } else { 'agent' }
    } else {
        $lhmTemp = Get-CPUTempFromLHM
        if ($lhmTemp -ne $null) {
            $temp = $lhmTemp
            $source = 'lhm'
        } else {
            $wmiTemp = Get-CPUTempFromWMI
            if ($wmiTemp -ne $null) {
                $temp = $wmiTemp
                $source = 'wmi'
            } else {
                $source = 'none'
            }
        }
    }

    $now = Get-Date
    $valueChanged = ($Script:CpuTempLogLastValue -ne $temp)
    $sourceChanged = ($Script:CpuTempLogLastSource -ne $source)
    $intervalElapsed = (($now - $Script:CpuTempLogLastAt).TotalSeconds -ge 60)
    if ($valueChanged -or $sourceChanged -or $intervalElapsed) {
        if ($temp -ne $null) {
            Write-DebugLine ("CPUTemp: {0}C source={1}" -f $temp, $source)
        } else {
            Write-DebugLine ("CPUTemp: null source={0}" -f $source)
        }
        $Script:CpuTempLogLastAt = $now
        $Script:CpuTempLogLastValue = $temp
        $Script:CpuTempLogLastSource = $source
    }

    return $temp
}
