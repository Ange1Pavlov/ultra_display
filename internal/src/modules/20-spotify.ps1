# spotify + cover cache module (with TTL: delete cache if older than 1 day)
param()
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve) '00-utils.ps1')

if (-not (Get-Variable -Name SP_CLIENT_ID -Scope Script -ErrorAction SilentlyContinue)) { $Script:SP_CLIENT_ID = '' }
if (-not (Get-Variable -Name SP_CLIENT_SECRET -Scope Script -ErrorAction SilentlyContinue)) { $Script:SP_CLIENT_SECRET = '' }
if (-not (Get-Variable -Name SP_REFRESH_TOKEN -Scope Script -ErrorAction SilentlyContinue)) { $Script:SP_REFRESH_TOKEN = '' }

$Script:SP_ACCESS_TOKEN = $null
$Script:SP_TOKEN_EXPIRES = Get-Date '1970-01-01'
$Script:SP_LAST_API_CHECK = Get-Date '1970-01-01'
$Script:SP_LAST_LOCAL_TEXT = ''
$Script:SP_LAST_NOWPLAYING = @{ text=''; albumImageUrl=$null }
$Script:SP_API_MIN_SECONDS = 900

function Refresh-SpotifyToken {
    try {
        if (-not $SP_CLIENT_ID -or -not $SP_CLIENT_SECRET -or -not $SP_REFRESH_TOKEN) { Write-DebugLine 'RefreshSpotify: missing creds'; return $null }
        $now = Get-Date
        if ($SP_ACCESS_TOKEN -and $now -lt $SP_TOKEN_EXPIRES.AddSeconds(-30)) { return $SP_ACCESS_TOKEN }
        $authStr = ("{0}:{1}" -f $SP_CLIENT_ID, $SP_CLIENT_SECRET)
        $auth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($authStr))
        $body = @{ grant_type='refresh_token'; refresh_token=$SP_REFRESH_TOKEN }
        $resp = Invoke-RestMethod -Method Post -Uri 'https://accounts.spotify.com/api/token' -Body $body -Headers @{ Authorization = "Basic $auth" } -ErrorAction Stop
        $Script:SP_ACCESS_TOKEN = $resp.access_token
        $Script:SP_TOKEN_EXPIRES = (Get-Date).AddSeconds([int]$resp.expires_in)
        Write-DebugLine ("RefreshSpotify: got token expires_in={0}" -f $resp.expires_in)
        return $Script:SP_ACCESS_TOKEN
    } catch { Write-DebugLine ("RefreshSpotify err: {0}" -f $_.ToString()); return $null }
}

function Get-SpotifyNowPlayingViaWeb {
    $token = Refresh-SpotifyToken
    if (-not $token) { return @{ text=''; albumImageUrl=$null } }
    try {
        $h = @{ Authorization = "Bearer $token"; 'Accept' = 'application/json' }
        $resp = Invoke-RestMethod -Method Get -Uri 'https://api.spotify.com/v1/me/player/currently-playing' -Headers $h -ErrorAction Stop
        if ($null -eq $resp) { return @{ text=''; albumImageUrl=$null } }
        if (-not $resp.is_playing) { return @{ text=''; albumImageUrl=$null } }
        $artist = ($resp.item.artists | Select-Object -First 1).name
        $track = $resp.item.name
        $img = $null
        if ($resp.item.album -and $resp.item.album.images -and $resp.item.album.images.Count -gt 0) { $img = $resp.item.album.images[0].url }
        return @{ text=("{0} - {1}" -f $artist, $track); albumImageUrl=$img }
    } catch { Write-DebugLine ("GetSpotifyNow err: {0}" -f $_.ToString()); return @{ text=''; albumImageUrl=$null } }
}

function Get-SpotifyLocalState {
    try {
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ieq 'spotify' }
        if (-not $procs -or $procs.Count -eq 0) { return @{ running=$false; text=''; active=$false } }
        $generic = '^(Spotify|Spotify Premium|Home|Search|Browse|Now Playing)$'
        foreach ($p in $procs) {
            try { $title = $p.MainWindowTitle } catch { $title = $null }
            if (-not $title) { continue }
            $t = $title.Trim()
            if ($t -match '\S+\s-\s\S+' -and $t -notmatch $generic) { return @{ running=$true; text=$t; active=$true } }
        }
        return @{ running=$true; text=''; active=$false }
    } catch {
        Write-DebugLine ("Get-SpotifyLocalState err: {0}" -f $_.ToString())
        return @{ running=$false; text=''; active=$false }
    }
}

function Get-NowPlayingLocal {
    $s = Get-SpotifyLocalState
    if ($s.active -and $s.text) { return @{ text=$s.text; albumImageUrl=$null } }
    return @{ text=''; albumImageUrl=$null }
}

function Get-NowPlaying {
    $local = Get-SpotifyLocalState
    $now = Get-Date

    if (-not $local.running) {
        $Script:SP_LAST_LOCAL_TEXT = ''
        $Script:SP_LAST_NOWPLAYING = @{ text=''; albumImageUrl=$null }
        return @{ text=''; albumImageUrl=$null }
    }

    # Only query Spotify API when local state strongly suggests active playback.
    if (-not $local.active -or -not $local.text) { return @{ text=''; albumImageUrl=$null } }

    $localText = $local.text.Trim()
    $trackChanged = $localText -ne $Script:SP_LAST_LOCAL_TEXT
    $cached = $Script:SP_LAST_NOWPLAYING
    $haveCoverForTrack = ($cached.text -eq $localText -and $cached.albumImageUrl)
    $dueByInterval = (($now - $Script:SP_LAST_API_CHECK).TotalSeconds -ge $Script:SP_API_MIN_SECONDS)
    $needWeb = $trackChanged -or ((-not $haveCoverForTrack) -and $dueByInterval)

    if ($needWeb) {
        $Script:SP_LAST_API_CHECK = $now
        $web = Get-SpotifyNowPlayingViaWeb
        if ($web.text -and $web.text.Trim() -ne '') {
            $Script:SP_LAST_NOWPLAYING = $web
        } else {
            # Fallback to local title when API is unavailable/paused.
            $Script:SP_LAST_NOWPLAYING = @{ text=$localText; albumImageUrl=$null }
        }
    } elseif ($cached.text -ne $localText) {
        $Script:SP_LAST_NOWPLAYING = @{ text=$localText; albumImageUrl=$null }
    }

    $Script:SP_LAST_LOCAL_TEXT = $localText
    return $Script:SP_LAST_NOWPLAYING
}

# cover cache in project cache folder
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve
$ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot '..\..\..'))
$CacheDir = Join-Path $ProjectRoot 'cache'
if (-not (Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
$Script:CoverCachePath = Join-Path $CacheDir 'cover_cache.jpg'
$Script:CoverCacheMeta = Join-Path $CacheDir 'cover_cache.url'

function Ensure-CoverCacheTTL {
    try {
        if (Test-Path $Script:CoverCachePath) {
            $fi = Get-Item $Script:CoverCachePath
            if ((Get-Date) -gt $fi.LastWriteTime.AddHours(24)) {
                Remove-Item -Force $Script:CoverCachePath -ErrorAction SilentlyContinue
                if (Test-Path $Script:CoverCacheMeta) { Remove-Item -Force $Script:CoverCacheMeta -ErrorAction SilentlyContinue }
                Write-DebugLine "CoverCache: expired and deleted"
            }
        }
    } catch { Write-DebugLine ("Ensure-CoverCacheTTL err: {0}" -f $_.ToString()) }
}

function Fetch-ImageFromUrlWithCache { param([string]$url)
    if (-not $url) { return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Ensure-CoverCacheTTL
        $meta = $null
        if (Test-Path $Script:CoverCacheMeta) { $meta = Get-Content -Path $Script:CoverCacheMeta -ErrorAction SilentlyContinue }
        if ($meta -and $meta.Trim() -eq $url -and (Test-Path $Script:CoverCachePath)) {
            return [System.Drawing.Image]::FromFile($Script:CoverCachePath)
        }
        $wc = New-Object System.Net.WebClient
        $bytes = $wc.DownloadData($url)
        [System.IO.File]::WriteAllBytes($Script:CoverCachePath, $bytes)
        Set-Content -Path $Script:CoverCacheMeta -Value $url -Encoding UTF8
        return [System.Drawing.Image]::FromFile($Script:CoverCachePath)
    } catch { Write-DebugLine ("FetchCover err: {0}" -f $_.ToString()); return $null }
}
