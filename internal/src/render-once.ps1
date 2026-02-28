param(
    [string]$outDir = 'C:\display-test',
    [string]$outFile = 'frame.jpg'
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve
$modules = Join-Path $scriptRoot 'modules'

# Load secrets.json (project root)
$secretsPath = Join-Path $scriptRoot '..\..\secrets.json'
if (Test-Path $secretsPath) {
    try {
        $json = Get-Content -Path $secretsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($json.SP_CLIENT_ID) { Set-Variable -Name SP_CLIENT_ID -Value $json.SP_CLIENT_ID -Scope Script -Force }
        if ($json.SP_CLIENT_SECRET) { Set-Variable -Name SP_CLIENT_SECRET -Value $json.SP_CLIENT_SECRET -Scope Script -Force }
        if ($json.SP_REFRESH_TOKEN) { Set-Variable -Name SP_REFRESH_TOKEN -Value $json.SP_REFRESH_TOKEN -Scope Script -Force }
    } catch {
        Write-Host "Failed loading secrets.json: $_"
    }
}

# Load settings.json (project root)
$settingsPath = Join-Path $scriptRoot '..\..\settings.json'
$Script:CLOCK_STYLE = 'sevenseg'
$Script:BACKGROUND_IMAGE = ''
$Script:STYLE = $null
if (Test-Path $settingsPath) {
    $loaded = $false
    for ($attempt = 1; $attempt -le 3 -and -not $loaded; $attempt++) {
        try {
            $settings = Get-Content -Path $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($settings.clockStyle) { $Script:CLOCK_STYLE = ([string]$settings.clockStyle).Trim().ToLowerInvariant() }
            if ($settings.backgroundImage) {
                $bgPathRaw = ([string]$settings.backgroundImage).Trim()
                if ($bgPathRaw) {
                    if ([System.IO.Path]::IsPathRooted($bgPathRaw)) {
                        $Script:BACKGROUND_IMAGE = $bgPathRaw
                    } else {
                        $Script:BACKGROUND_IMAGE = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot "..\..\$bgPathRaw"))
                    }
                }
            }
            if ($settings.style) { $Script:STYLE = $settings.style }
            $loaded = $true
        } catch {
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds 120
            } else {
                Write-Host "Failed loading settings.json: $_"
            }
        }
    }
}

. (Join-Path $modules '00-utils.ps1')
. (Join-Path $modules '10-sensors.ps1')
. (Join-Path $modules '20-spotify.ps1')
. (Join-Path $modules '30-render.ps1')

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

try {
    Render-Frame -pathDir $outDir -outFileName $outFile
    Write-Host ("Rendered once: {0}\{1}" -f $outDir, $outFile)
} catch {
    Write-Host ("Render once error: {0}" -f $_.ToString())
}
