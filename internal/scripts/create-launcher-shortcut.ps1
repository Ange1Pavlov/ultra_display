param(
    [switch]$DesktopOnly
)

$ErrorActionPreference = 'Stop'
$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$target = Join-Path $projectRoot 'app.cmd'
$pngIconPath = Join-Path $projectRoot 'icon.png'
$icoIconPath = Join-Path $projectRoot 'icon.ico'

if (-not (Test-Path $target)) {
    throw "Missing launcher target: $target"
}

function Read-BE32 {
    param([byte[]]$Data, [int]$Offset)
    return ([int]$Data[$Offset] -shl 24) -bor ([int]$Data[$Offset + 1] -shl 16) -bor ([int]$Data[$Offset + 2] -shl 8) -bor [int]$Data[$Offset + 3]
}

function Convert-PngToIco {
    param(
        [string]$PngPath,
        [string]$IcoPath
    )
    if (-not (Test-Path $PngPath)) { return $false }

    $png = [System.IO.File]::ReadAllBytes($PngPath)
    if ($png.Length -lt 40) { return $false }

    $sig = @(137,80,78,71,13,10,26,10)
    for ($i = 0; $i -lt $sig.Count; $i++) {
        if ($png[$i] -ne [byte]$sig[$i]) { return $false }
    }

    $width = Read-BE32 -Data $png -Offset 16
    $height = Read-BE32 -Data $png -Offset 20
    if ($width -le 0 -or $height -le 0) { return $false }

    $wByte = if ($width -ge 256) { 0 } else { [byte]$width }
    $hByte = if ($height -ge 256) { 0 } else { [byte]$height }

    $iconDir = [byte[]](0,0,1,0,1,0)
    $entry = New-Object byte[] 16
    $entry[0] = $wByte
    $entry[1] = $hByte
    $entry[2] = 0
    $entry[3] = 0
    $entry[4] = 1
    $entry[5] = 0
    $entry[6] = 32
    $entry[7] = 0

    $sizeBytes = [BitConverter]::GetBytes([int]$png.Length)
    [Array]::Copy($sizeBytes, 0, $entry, 8, 4)
    $offsetBytes = [BitConverter]::GetBytes([int]22)
    [Array]::Copy($offsetBytes, 0, $entry, 12, 4)

    $ms = New-Object System.IO.MemoryStream
    try {
        $ms.Write($iconDir, 0, $iconDir.Length)
        $ms.Write($entry, 0, $entry.Length)
        $ms.Write($png, 0, $png.Length)
        [System.IO.File]::WriteAllBytes($IcoPath, $ms.ToArray())
    } finally {
        $ms.Dispose()
    }
    return $true
}

$iconLocation = "$env:SystemRoot\System32\imageres.dll,109"
if (Test-Path $pngIconPath) {
    $needRegen = (-not (Test-Path $icoIconPath)) -or ((Get-Item $pngIconPath).LastWriteTime -gt (Get-Item $icoIconPath).LastWriteTime)
    if ($needRegen) {
        $ok = Convert-PngToIco -PngPath $pngIconPath -IcoPath $icoIconPath
        if ($ok) {
            Write-Host "Generated icon: $icoIconPath"
        } else {
            Write-Host "Could not generate icon from: $pngIconPath"
        }
    }
}

if (Test-Path $icoIconPath) {
    $iconLocation = "$icoIconPath,0"
}

$ws = New-Object -ComObject WScript.Shell

function New-ShortcutFile {
    param([string]$path)
    $sc = $ws.CreateShortcut($path)
    $sc.TargetPath = $target
    $sc.WorkingDirectory = $projectRoot
    $sc.IconLocation = $iconLocation
    $sc.WindowStyle = 1
    $sc.Description = 'Ultra Display Panel'
    $sc.Save()
}

if (-not $DesktopOnly) {
    $rootShortcut = Join-Path $projectRoot 'Ultra Display Panel.lnk'
    New-ShortcutFile -path $rootShortcut
    Write-Host "Created: $rootShortcut"
}

$desktopDir = [Environment]::GetFolderPath('Desktop')
if ($desktopDir) {
    $desktopShortcut = Join-Path $desktopDir 'Ultra Display Panel.lnk'
    New-ShortcutFile -path $desktopShortcut
    Write-Host "Created: $desktopShortcut"
}
