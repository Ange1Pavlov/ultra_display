param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$toolsRoot = Join-Path $projectRoot 'internal\tools'
$lhmRuntimeDir = Join-Path $toolsRoot 'lhm_runtime'
$ohmRuntimeDir = Join-Path $toolsRoot 'ohm_runtime\OpenHardwareMonitor'
$lhmDll = Join-Path $lhmRuntimeDir 'LibreHardwareMonitorLib.dll'
$ohmExe = Join-Path $ohmRuntimeDir 'OpenHardwareMonitor.exe'

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) { Write-Host $Message }
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile
    )
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

function Install-LhmRuntime {
    if (Test-Path $lhmDll) {
        Write-Info 'install-tools: LibreHardwareMonitor runtime already present.'
        return
    }

    Ensure-Dir -Path $lhmRuntimeDir
    $tempRoot = Join-Path $env:TEMP ("ud-lhm-" + [guid]::NewGuid().ToString('N'))
    Ensure-Dir -Path $tempRoot
    $zipPath = Join-Path $tempRoot 'lhm.zip'

    try {
        Write-Info 'install-tools: resolving latest LibreHardwareMonitor release...'
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest'
        $asset = $release.assets | Where-Object { $_.name -like 'LibreHardwareMonitor.NET*.zip' } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -eq 'LibreHardwareMonitor.zip' } | Select-Object -First 1
        }
        if (-not $asset) {
            throw 'No downloadable LibreHardwareMonitor zip asset found.'
        }

        Write-Info ("install-tools: downloading {0}..." -f $asset.name)
        Download-File -Url $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

        $dllCandidate = Get-ChildItem -Path $tempRoot -Recurse -File -Filter 'LibreHardwareMonitorLib.dll' | Select-Object -First 1
        if (-not $dllCandidate) {
            throw 'LibreHardwareMonitorLib.dll not found in downloaded archive.'
        }

        $srcRoot = Split-Path -Parent $dllCandidate.FullName
        Copy-Item -Path (Join-Path $srcRoot '*') -Destination $lhmRuntimeDir -Recurse -Force
        Write-Info 'install-tools: LibreHardwareMonitor runtime installed.'
    } finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-OhmRuntime {
    if (Test-Path $ohmExe) {
        Write-Info 'install-tools: OpenHardwareMonitor runtime already present.'
        return
    }

    Ensure-Dir -Path $ohmRuntimeDir
    $tempRoot = Join-Path $env:TEMP ("ud-ohm-" + [guid]::NewGuid().ToString('N'))
    Ensure-Dir -Path $tempRoot
    $zipPath = Join-Path $tempRoot 'ohm.zip'

    try {
        $ohmUrl = 'https://openhardwaremonitor.org/files/openhardwaremonitor-v0.9.6.zip'
        Write-Info 'install-tools: downloading OpenHardwareMonitor runtime...'
        Download-File -Url $ohmUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

        $exeCandidate = Get-ChildItem -Path $tempRoot -Recurse -File -Filter 'OpenHardwareMonitor.exe' | Select-Object -First 1
        if (-not $exeCandidate) {
            throw 'OpenHardwareMonitor.exe not found in downloaded archive.'
        }

        $srcRoot = Split-Path -Parent $exeCandidate.FullName
        Copy-Item -Path (Join-Path $srcRoot '*') -Destination $ohmRuntimeDir -Recurse -Force
        Write-Info 'install-tools: OpenHardwareMonitor runtime installed.'
    } finally {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Install-LhmRuntime
Install-OhmRuntime
