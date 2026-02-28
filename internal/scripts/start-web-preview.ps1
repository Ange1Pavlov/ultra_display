param(
    [int]$Port = 8090
)

$ErrorActionPreference = 'SilentlyContinue'
$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$serverScript = Join-Path $scriptsRoot 'web-preview-server.ps1'
$pidFile = Join-Path $projectRoot 'logs\web-preview-pid.json'

if (-not (Test-Path (Split-Path -Parent $pidFile))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $pidFile) -Force | Out-Null
}

$existing = $null
if (Test-Path $pidFile) {
    try {
        $existing = Get-Content -Path $pidFile -Raw | ConvertFrom-Json
        if ($existing -and $existing.pid) {
            $p = Get-Process -Id ([int]$existing.pid) -ErrorAction SilentlyContinue
            if ($p) {
                Write-Host ("Web preview already running on port {0} (PID={1})" -f $existing.port, $existing.pid)
                exit 0
            }
        }
    } catch { }
}

$proc = Start-Process -FilePath 'powershell' -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $serverScript),
    '-ProjectRoot', ('"{0}"' -f $projectRoot),
    '-Port', $Port
) -WindowStyle Hidden -WorkingDirectory $projectRoot -PassThru

@{
    startedAt = (Get-Date).ToString('s')
    pid = $proc.Id
    port = $Port
} | ConvertTo-Json | Set-Content -Path $pidFile -Encoding UTF8

Write-Host ("Started web preview on port {0} (PID={1})" -f $Port, $proc.Id)
