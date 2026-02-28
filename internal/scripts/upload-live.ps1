# upload-live.ps1
param(
    [string]$framePath = 'C:\display-test\frame.jpg',
    [string]$uploadUrl = 'http://192.168.0.243/doUpload?dir=/image/',
    [string]$targetFilename = 'live.jpg',
    [int]$intervalSeconds = 2
)

$mutexCreated = $false
try {
    $script:UploadMutex = New-Object System.Threading.Mutex($false, 'Global\UltraDisplay.UploadLive', [ref]$mutexCreated)
} catch {
    $script:UploadMutex = New-Object System.Threading.Mutex($false, 'UltraDisplay.UploadLive', [ref]$mutexCreated)
}
if (-not $mutexCreated) {
    Write-Host 'upload-live: existing instance detected, exiting.'
    exit 0
}

Add-Type -AssemblyName System.Net.Http

$http = New-Object System.Net.Http.HttpClient

Write-Host "Uploader started -> $uploadUrl (as $targetFilename), interval ${intervalSeconds}s"

while ($true) {
    try {
        if (-not (Test-Path $framePath)) {
            Write-Host "Frame missing: $framePath"
            Start-Sleep -Seconds $intervalSeconds
            continue
        }

        # read file bytes
        $bytes = [System.IO.File]::ReadAllBytes($framePath)
        $ms = New-Object System.IO.MemoryStream(,$bytes)

        $content = New-Object System.Net.Http.MultipartFormDataContent
        $streamContent = New-Object System.Net.Http.StreamContent($ms)
        $streamContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('image/jpeg')
        # match browser form-field name "file"
        $disposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue('form-data')
        $disposition.Name = '"file"'
        $disposition.FileName = '"' + $targetFilename + '"'
        $streamContent.Headers.ContentDisposition = $disposition
        $content.Add($streamContent)

        $resp = $http.PostAsync($uploadUrl, $content).Result
        $body = $resp.Content.ReadAsStringAsync().Result
        if ($resp.IsSuccessStatusCode) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') Uploaded OK -> $targetFilename"
        } else {
            Write-Warning "Upload failed: $($resp.StatusCode) - $body"
        }

        $content.Dispose(); $streamContent.Dispose(); $ms.Dispose()
    } catch {
        Write-Warning "Uploader error: $_"
    }
    Start-Sleep -Seconds $intervalSeconds
}
