# utilities: debug/log rotation and small helpers
param()
$ScriptRoot = (Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve)
$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..\..\..'))
$LogDir = Join-Path $ProjectRoot 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not $Script:DebugLogPath) { $Script:DebugLogPath = Join-Path $LogDir 'frame_debug.txt' }
if (-not (Get-Variable -Name LastLogClear -Scope Script -ErrorAction SilentlyContinue)) { $Script:LastLogClear = Get-Date }

# Ensure drawing types are available for both renderer and Spotify cover loading.
try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch { }

function Write-DebugLine { param([string]$line)
    try {
        $now = Get-Date
        if (($now - $Script:LastLogClear).TotalSeconds -ge 120) {
            Remove-Item -ErrorAction SilentlyContinue -Path $Script:DebugLogPath
            $Script:LastLogClear = $now
        }
        $ts = $now.ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $Script:DebugLogPath -Value ("$ts`t$line") -Encoding UTF8
    } catch { }
}

function Safe-Resolve { param([string]$p) try { return (Resolve-Path $p).ProviderPath } catch { return $p } }

function Read-FileFirstLine { param([string]$path) try { if (Test-Path $path) { return (Get-Content -Path $path -Encoding UTF8 -TotalCount 1 -ErrorAction SilentlyContinue).Trim() } } catch {}; return $null }
