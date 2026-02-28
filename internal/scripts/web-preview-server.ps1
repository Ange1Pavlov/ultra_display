param(
    [string]$ProjectRoot = 'C:\display-test',
    [int]$Port = 8090
)

$ErrorActionPreference = 'Stop'

if ($Port -lt 1 -or $Port -gt 65535) {
    throw "Invalid port: $Port"
}

$framePath = Join-Path $ProjectRoot 'frame.jpg'

function Write-Response {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$Reason,
        [string]$ContentType,
        [byte[]]$Body
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $Reason",
        "Connection: close",
        "Cache-Control: no-store, no-cache, must-revalidate, max-age=0",
        "Pragma: no-cache",
        "Expires: 0",
        "Content-Type: $ContentType",
        "Content-Length: $($Body.Length)",
        ""
    ) -join "`r`n"

    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers + "`r`n")
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
}

function Get-PreviewHtml {
    param([int]$Port)
    return @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Ultra Display Web Preview</title>
  <style>
    body { margin: 0; background: #0f131a; color: #d8dfef; font-family: Segoe UI, Arial, sans-serif; }
    .wrap { display: flex; min-height: 100vh; align-items: center; justify-content: center; flex-direction: column; gap: 12px; }
    img { width: min(92vw, 360px); aspect-ratio: 1 / 1; object-fit: cover; border: 1px solid #37445a; background: #0b0e13; }
    .meta { font-size: 13px; color: #9fb2cf; }
    a { color: #7cc4ff; text-decoration: none; }
  </style>
</head>
<body>
  <div class="wrap">
    <img id="frame" src="/frame.jpg?t=0" alt="frame preview" />
    <div class="meta">Ultra Display Web Preview (port $Port)</div>
    <div class="meta"><a href="/frame.jpg" target="_blank">Open raw frame.jpg</a></div>
  </div>
  <script>
    const img = document.getElementById('frame');
    setInterval(() => { img.src = '/frame.jpg?t=' + Date.now(); }, 1000);
  </script>
</body>
</html>
"@
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Host ("Web preview server started on 0.0.0.0:{0}" -f $Port)

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 8192, $true)

            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }

            $parts = $requestLine.Split(' ')
            $rawPath = if ($parts.Count -ge 2) { $parts[1] } else { '/' }
            $urlPath = $rawPath.Split('?')[0]

            while ($true) {
                $line = $reader.ReadLine()
                if ($null -eq $line -or $line -eq '') { break }
            }

            switch ($urlPath) {
                '/' {
                    $html = Get-PreviewHtml -Port $Port
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                    Write-Response -Stream $stream -StatusCode 200 -Reason 'OK' -ContentType 'text/html; charset=utf-8' -Body $bytes
                }
                '/index.html' {
                    $html = Get-PreviewHtml -Port $Port
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
                    Write-Response -Stream $stream -StatusCode 200 -Reason 'OK' -ContentType 'text/html; charset=utf-8' -Body $bytes
                }
                '/frame.jpg' {
                    if (-not (Test-Path $framePath)) {
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes('frame.jpg not found')
                        Write-Response -Stream $stream -StatusCode 404 -Reason 'Not Found' -ContentType 'text/plain; charset=utf-8' -Body $bytes
                    } else {
                        $bytes = [System.IO.File]::ReadAllBytes($framePath)
                        Write-Response -Stream $stream -StatusCode 200 -Reason 'OK' -ContentType 'image/jpeg' -Body $bytes
                    }
                }
                '/health' {
                    $json = '{"ok":true}'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    Write-Response -Stream $stream -StatusCode 200 -Reason 'OK' -ContentType 'application/json; charset=utf-8' -Body $bytes
                }
                default {
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
                    Write-Response -Stream $stream -StatusCode 404 -Reason 'Not Found' -ContentType 'text/plain; charset=utf-8' -Body $bytes
                }
            }
        } catch {
        } finally {
            try { $client.Close() } catch { }
        }
    }
} finally {
    try { $listener.Stop() } catch { }
}
