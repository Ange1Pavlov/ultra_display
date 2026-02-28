param(
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$pidFile = Join-Path $projectRoot 'logs\web-preview-pid.json'
$serverToken = 'web-preview-server.ps1'

if (Test-Path $pidFile) {
    try {
        $data = Get-Content -Path $pidFile -Raw | ConvertFrom-Json
        if ($data -and $data.pid) {
            Stop-Process -Id ([int]$data.pid) -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}

# Safety sweep
Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^(powershell|pwsh)\.exe$' -and ([string]$_.CommandLine).ToLowerInvariant().Contains($serverToken)
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue

if (-not $Quiet) {
    Write-Host 'Stopped web preview server.'
}
