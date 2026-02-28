Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) '..'))
$startScript = Join-Path $projectRoot 'internal\scripts\start-display.ps1'
$stopScript = Join-Path $projectRoot 'internal\scripts\stop-display.ps1'
$startWebScript = Join-Path $projectRoot 'internal\scripts\start-web-preview.ps1'
$stopWebScript = Join-Path $projectRoot 'internal\scripts\stop-web-preview.ps1'
$renderOnceScript = Join-Path $projectRoot 'internal\src\render-once.ps1'
$logPath = Join-Path $projectRoot 'logs\frame_debug.txt'
$framePath = Join-Path $projectRoot 'frame.jpg'
$pidFile = Join-Path $projectRoot 'logs\display-pids.json'
$webPidFile = Join-Path $projectRoot 'logs\web-preview-pid.json'
$settingsPath = Join-Path $projectRoot 'settings.json'
$iconPath = Join-Path $projectRoot 'icon.ico'

if (-not ("DwmDarkMode" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DwmDarkMode {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@
}

if (-not ("UxThemeNative" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class UxThemeNative {
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);
}
"@
}

function Invoke-BypassFile {
    param([string]$path)
    $exe = 'powershell'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $path))
    $p = Start-Process -FilePath $exe -ArgumentList $args -WorkingDirectory $projectRoot -PassThru -WindowStyle Hidden
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
}

function Get-IsRunning {
    try {
        if (Test-Path $pidFile) {
            $d = Get-Content -Path $pidFile -Raw | ConvertFrom-Json
            $g = Get-Process -Id ([int]$d.generatorPid) -ErrorAction SilentlyContinue
            $u = Get-Process -Id ([int]$d.uploaderPid) -ErrorAction SilentlyContinue
            if ($g -and $u) { return $true }
        }
    } catch { }
    return $false
}

function Get-LocalIPv4 {
    try {
        $all = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and -not $_.IPAddressToString.StartsWith('127.') }
        if ($all -and $all.Count -gt 0) { return $all[0].IPAddressToString }
    } catch { }
    return '127.0.0.1'
}

function Get-WebPreviewState {
    $obj = @{
        running = $false
        port = 8090
        url = $null
    }
    try {
        if (Test-Path $webPidFile) {
            $d = Get-Content -Path $webPidFile -Raw | ConvertFrom-Json
            if ($d.port) { $obj.port = [int]$d.port }
            if ($d.pid) {
                $p = Get-Process -Id ([int]$d.pid) -ErrorAction SilentlyContinue
                if ($p) { $obj.running = $true }
            }
        }
    } catch { }
    $ip = Get-LocalIPv4
    $obj.url = "http://$ip`:$($obj.port)/"
    return $obj
}

function Get-LogTail {
    param([int]$lines = 12)
    if (-not (Test-Path $logPath)) { return "No log yet: $logPath" }
    try {
        return (Get-Content -Path $logPath -Tail $lines -ErrorAction Stop) -join [Environment]::NewLine
    } catch {
        return "Cannot read log: $($_.Exception.Message)"
    }
}

function Load-PreviewImage {
    if (-not (Test-Path $framePath)) { return $null }
    try {
        $fs = [System.IO.File]::Open($framePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $img = [System.Drawing.Image]::FromStream($fs)
            return New-Object System.Drawing.Bitmap $img
        } finally {
            $fs.Dispose()
        }
    } catch {
        return $null
    }
}

function Get-DefaultStyleSettings {
    return [ordered]@{
        fontFamily = 'Segoe UI'
        textColor = '#D3D3D3'
        bgColor = '#000000'

        clockColor = '#FF0000'
        clockBgColor = '#004040'
        clockOffColor = '#2E2E2E'
        clockDayColor = '#FFFFFF'
        clockFontSize = 28
        clockBottomGap = 4

        cpuFontSize = 16
        ramFontSize = 16
        gpuFontSize = 16

        cpuTextColor = '#D3D3D3'
        ramTextColor = '#D3D3D3'
        gpuTextColor = '#D3D3D3'

        cpuBarColor = '#40CBFF'
        ramBarColor = '#F744C1'
        gpuBarColor = '#FF361A'
        barBackgroundColor = '#323232'
        barTransparencyPct = 100
        barBackgroundTransparencyPct = 100

        labelToBarGap = 4
        sectionGap = 4
        ramToSpotifyGap = 7

        backgroundBlurPct = 80
        backgroundOverlayPct = 43

        spotifyBgColor = '#51F748'
        spotifyBgTransparencyPct = 50
        spotifyShowImage = $true
        spotifyTextColor = '#000000'
        spotifyArtistFontSize = 14
        spotifyTrackFontSize = 14
        spotifyLineHeight = 1.0
    }
}

function Convert-StyleToObject {
    param($styleValue)
    if ($null -eq $styleValue) { return @{} }
    if ($styleValue -is [System.Collections.IDictionary]) { return $styleValue }
    return $styleValue | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
}

function Load-AppSettings {
    $obj = @{
        clockStyle = 'sevenseg'
        backgroundImage = '\\chroma\home\Drive\docs\pexels-dexter-fernandes-2646237.jpg'
        refreshIntervalSeconds = 2
        style = Get-DefaultStyleSettings
    }
    try {
        if (Test-Path $settingsPath) {
            $s = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
            if ($s.clockStyle) { $obj.clockStyle = ([string]$s.clockStyle).Trim().ToLowerInvariant() }
            if ($s.backgroundImage) { $obj.backgroundImage = ([string]$s.backgroundImage).Trim() }
            if ($s.refreshIntervalSeconds) {
                $v = [int]$s.refreshIntervalSeconds
                if ($v -ge 2 -and $v -le 120) { $obj.refreshIntervalSeconds = $v }
            }
            if ($s.style) {
                $loaded = Convert-StyleToObject $s.style
                foreach ($k in $loaded.Keys) { $obj.style[$k] = $loaded[$k] }
            }
        }
    } catch { }
    return $obj
}

function Save-AppSettings {
    param(
        [string]$style,
        [string]$backgroundImage,
        [int]$refreshIntervalSeconds,
        $styleObject
    )
    $normalized = switch ($style) {
        'classic' { 'classic' }
        'classic_plain' { 'classic_plain' }
        default { 'sevenseg' }
    }

    $bg = ''
    if (-not [string]::IsNullOrWhiteSpace($backgroundImage)) {
        try { $bg = [System.IO.Path]::GetFullPath($backgroundImage.Trim()) } catch { $bg = $backgroundImage.Trim() }
    }

    $styleHash = Convert-StyleToObject $styleObject
    if ($refreshIntervalSeconds -lt 2) { $refreshIntervalSeconds = 2 }
    if ($refreshIntervalSeconds -gt 120) { $refreshIntervalSeconds = 120 }

    $obj = [ordered]@{
        clockStyle = $normalized
        backgroundImage = $bg
        refreshIntervalSeconds = $refreshIntervalSeconds
        style = $styleHash
    }
    $json = $obj | ConvertTo-Json -Depth 16
    $dir = Split-Path -Parent $settingsPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = Join-Path $dir ('.settings.tmp.{0}.json' -f ([guid]::NewGuid().ToString('N')))
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -Path $tmp -Destination $settingsPath -Force
}

function Show-ApplyLoader {
    param(
        [int]$seconds = 8,
        [string]$title = 'Applying Settings'
    )
    if ($seconds -lt 1) { $seconds = 1 }

    $loader = New-Object System.Windows.Forms.Form
    $loader.Text = $title
    $loader.StartPosition = 'CenterParent'
    $loader.Size = New-Object System.Drawing.Size(430, 150)
    $loader.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $loader.MinimizeBox = $false
    $loader.MaximizeBox = $false
    $loader.ControlBox = $false
    $loader.TopMost = $true
    $loader.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 33)
    $loader.ForeColor = [System.Drawing.Color]::FromArgb(220, 226, 238)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(14, 14)
    $lbl.Size = New-Object System.Drawing.Size(390, 22)
    $lbl.Text = "Restarting services and waiting for next frame..."

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(14, 44)
    $bar.Size = New-Object System.Drawing.Size(390, 20)
    $bar.Minimum = 0
    $bar.Maximum = [Math]::Max(1, $seconds * 10)
    $bar.Value = 0

    $lblEta = New-Object System.Windows.Forms.Label
    $lblEta.Location = New-Object System.Drawing.Point(14, 72)
    $lblEta.Size = New-Object System.Drawing.Size(390, 22)

    $loader.Controls.AddRange(@($lbl, $bar, $lblEta))
    Set-DarkTitleBar -window $loader
    $loader.Show($form)
    $loader.Refresh()

    try {
        for ($i = 0; $i -le ($seconds * 10); $i++) {
            $bar.Value = [Math]::Min($bar.Maximum, $i)
            $remain = [Math]::Max(0, $seconds - [Math]::Floor($i / 10))
            $lblEta.Text = ("Estimated wait: {0}s" -f $remain)
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
    } finally {
        $loader.Close()
        $loader.Dispose()
    }
}

function Set-DoubleBufferedSafe {
    param([System.Windows.Forms.Control]$control)
    try {
        $prop = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if ($prop -and $control) { $prop.SetValue($control, $true, $null) }
    } catch { }
}

function Set-DarkTitleBar {
    param([System.Windows.Forms.Form]$window)
    try {
        if (-not $window.IsHandleCreated) { $null = $window.Handle }
        $enabled = 1
        [void][DwmDarkMode]::DwmSetWindowAttribute($window.Handle, 20, [ref]$enabled, 4)
        [void][DwmDarkMode]::DwmSetWindowAttribute($window.Handle, 19, [ref]$enabled, 4)
        $mica = 2
        [void][DwmDarkMode]::DwmSetWindowAttribute($window.Handle, 38, [ref]$mica, 4)
    } catch { }
}

function Set-DarkControlTheme {
    param([System.Windows.Forms.Control]$control)
    try {
        if (-not $control) { return }
        if (-not $control.IsHandleCreated) { $null = $control.Handle }
        [void][UxThemeNative]::SetWindowTheme($control.Handle, 'DarkMode_Explorer', $null)
    } catch { }
}

function New-FlatButton {
    param([string]$text,[int]$x,[int]$y,[int]$w,[int]$h)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 78, 92)
    $b.BackColor = [System.Drawing.Color]::FromArgb(33, 37, 48)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    $b.UseVisualStyleBackColor = $false
    return $b
}

function Apply-DarkTextBox {
    param([System.Windows.Forms.TextBox]$tb)
    $tb.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 22)
    $tb.ForeColor = [System.Drawing.Color]::FromArgb(220, 226, 238)
    $tb.BorderStyle = 'FixedSingle'
}

function Apply-DarkNumeric {
    param([System.Windows.Forms.NumericUpDown]$n)
    $n.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 22)
    $n.ForeColor = [System.Drawing.Color]::FromArgb(220, 226, 238)
    $n.BorderStyle = 'FixedSingle'
}

function Apply-DarkCombo {
    param([System.Windows.Forms.ComboBox]$cb)
    $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
    $cb.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 22)
    $cb.ForeColor = [System.Drawing.Color]::FromArgb(220, 226, 238)
    $cb.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $cb.Add_DrawItem({
        param($sender,$e)
        if ($e.Index -lt 0) { return }
        $bg = if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) {
            [System.Drawing.Color]::FromArgb(44, 52, 70)
        } else {
            [System.Drawing.Color]::FromArgb(15, 17, 22)
        }
        $fg = [System.Drawing.Color]::FromArgb(220, 226, 238)
        $b = New-Object System.Drawing.SolidBrush $bg
        $f = New-Object System.Drawing.SolidBrush $fg
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $e.Graphics.DrawString($sender.Items[$e.Index].ToString(), $sender.Font, $f, $e.Bounds.X + 4, $e.Bounds.Y + 2)
        $b.Dispose(); $f.Dispose()
        $e.DrawFocusRectangle()
    })
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Ultra Display Panel'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1060, 740)
$form.MinimumSize = New-Object System.Drawing.Size(760, 520)
$form.BackColor = [System.Drawing.Color]::FromArgb(17, 19, 25)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
Set-DoubleBufferedSafe -control $form
if (Test-Path $iconPath) { try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch { } }

$form.Add_Paint({
    $rect = $form.ClientRectangle
    $top = [System.Drawing.Color]::FromArgb(30, 34, 45)
    $bottom = [System.Drawing.Color]::FromArgb(17, 19, 25)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, 90.0)
    $_.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
})

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(16, 12)
$tabs.Size = New-Object System.Drawing.Size(1010, 680)
$tabs.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$tabs.Appearance = [System.Windows.Forms.TabAppearance]::Normal
$tabs.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 33)
$tabs.ForeColor = [System.Drawing.Color]::White
$tabs.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.ItemSize = New-Object System.Drawing.Size(110, 28)
$tabs.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
$tabs.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)

$tabs.Add_Paint({
    param($sender, $e)
    # Fill the full tabs header strip so no default white area remains.
    $headerH = $sender.ItemSize.Height + 4
    $headerRect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $headerH)
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(20, 23, 31))
    $e.Graphics.FillRectangle($bg, $headerRect)
    $bg.Dispose()
})

$tabs.Add_DrawItem({
    param($sender, $e)
    $g = $e.Graphics
    $rect = $sender.GetTabRect($e.Index)
    $selected = ($sender.SelectedIndex -eq $e.Index)
    $bg = if ($selected) { [System.Drawing.Color]::FromArgb(28, 32, 42) } else { [System.Drawing.Color]::FromArgb(20, 23, 31) }
    $fg = if ($selected) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(180, 190, 208) }
    $b = New-Object System.Drawing.SolidBrush $bg
    $f = New-Object System.Drawing.SolidBrush $fg
    $g.FillRectangle($b, $rect)
    $g.DrawRectangle([System.Drawing.Pens]::DimGray, $rect)
    [System.Windows.Forms.TextRenderer]::DrawText(
        $g,
        $sender.TabPages[$e.Index].Text,
        $sender.Font,
        $rect,
        $fg,
        [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
    )
    $b.Dispose(); $f.Dispose()
})


$tabDash = New-Object System.Windows.Forms.TabPage
$tabDash.Text = 'Dashboard'
$tabDash.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 33)
$tabDash.ForeColor = [System.Drawing.Color]::White
$tabDash.UseVisualStyleBackColor = $false

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = 'Settings'
$tabSettings.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 33)
$tabSettings.ForeColor = [System.Drawing.Color]::White
$tabSettings.UseVisualStyleBackColor = $false

$tabs.TabPages.Add($tabDash)
$tabs.TabPages.Add($tabSettings)
$form.Controls.Add($tabs)

# Dashboard tab
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Location = New-Object System.Drawing.Point(12, 12)
$panelTop.Size = New-Object System.Drawing.Size(970, 58)
$panelTop.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 42)
$panelTop.BorderStyle = 'FixedSingle'
$panelTop.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$btnStart = New-FlatButton 'Start' 14 11 100 32
$btnStop = New-FlatButton 'Stop' 122 11 100 32
$btnRestart = New-FlatButton 'Restart' 230 11 100 32
$btnRefresh = New-FlatButton 'Refresh Once' 338 11 130 32
$btnWebStart = New-FlatButton 'Start Web' 474 11 96 32
$btnWebStop = New-FlatButton 'Stop Web' 576 11 96 32
$btnWebOpen = New-FlatButton 'Open Web' 678 11 96 32

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(784, 7)
$lblStatus.Size = New-Object System.Drawing.Size(178, 22)
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$lblWeb = New-Object System.Windows.Forms.Label
$lblWeb.Location = New-Object System.Drawing.Point(784, 31)
$lblWeb.Size = New-Object System.Drawing.Size(178, 20)
$lblWeb.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lblWeb.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblWeb.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$panelTop.Controls.AddRange(@($btnStart,$btnStop,$btnRestart,$btnRefresh,$btnWebStart,$btnWebStop,$btnWebOpen,$lblStatus,$lblWeb))

$panelLeft = New-Object System.Windows.Forms.Panel
$panelLeft.Location = New-Object System.Drawing.Point(12, 84)
$panelLeft.Size = New-Object System.Drawing.Size(300, 540)
$panelLeft.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 42)
$panelLeft.BorderStyle = 'FixedSingle'
$panelLeft.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Text = 'Live Preview'
$lblPreview.Location = New-Object System.Drawing.Point(12, 10)
$lblPreview.Size = New-Object System.Drawing.Size(200, 22)
$lblPreview.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)

$preview = New-Object System.Windows.Forms.PictureBox
$preview.Location = New-Object System.Drawing.Point(14, 36)
$preview.Size = New-Object System.Drawing.Size(268, 268)
$preview.BorderStyle = 'FixedSingle'
$preview.SizeMode = 'StretchImage'
$preview.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 15)

$btnOpenFrame = New-FlatButton 'Open frame.jpg' 14 316 128 32
$btnOpenFolder = New-FlatButton 'Open project' 154 316 128 32

$panelLeft.Controls.AddRange(@($lblPreview,$preview,$btnOpenFrame,$btnOpenFolder))

$panelLog = New-Object System.Windows.Forms.Panel
$panelLog.Location = New-Object System.Drawing.Point(328, 84)
$panelLog.Size = New-Object System.Drawing.Size(654, 540)
$panelLog.BackColor = [System.Drawing.Color]::FromArgb(28, 32, 42)
$panelLog.BorderStyle = 'FixedSingle'
$panelLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Recent Logs'
$lblLog.Location = New-Object System.Drawing.Point(12, 10)
$lblLog.Size = New-Object System.Drawing.Size(200, 22)
$lblLog.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10, [System.Drawing.FontStyle]::Bold)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(14, 36)
$logBox.Size = New-Object System.Drawing.Size(624, 488)
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(15, 17, 22)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(220, 226, 238)
$logBox.BorderStyle = 'FixedSingle'
$logBox.Font = New-Object System.Drawing.Font('Cascadia Mono', 9)
$logBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$panelLog.Controls.AddRange(@($lblLog,$logBox))
$tabDash.Controls.AddRange(@($panelTop,$panelLeft,$panelLog))

# Settings tab
$styleControls = @{}

$lblS1 = New-Object System.Windows.Forms.Label
$lblS1.Text = 'Clock Style'
$lblS1.Location = New-Object System.Drawing.Point(16, 16)
$lblS1.Size = New-Object System.Drawing.Size(120, 20)

$cmbClockStyle = New-Object System.Windows.Forms.ComboBox
$cmbClockStyle.DropDownStyle = 'DropDownList'
$cmbClockStyle.Location = New-Object System.Drawing.Point(16, 38)
$cmbClockStyle.Size = New-Object System.Drawing.Size(190, 26)
[void]$cmbClockStyle.Items.Add('Seven-seg')
[void]$cmbClockStyle.Items.Add('Classic')
[void]$cmbClockStyle.Items.Add('Classic Plain')
Apply-DarkCombo $cmbClockStyle

$lblS2 = New-Object System.Windows.Forms.Label
$lblS2.Text = 'Refresh (sec)'
$lblS2.Location = New-Object System.Drawing.Point(222, 16)
$lblS2.Size = New-Object System.Drawing.Size(120, 20)

$numRefreshInterval = New-Object System.Windows.Forms.NumericUpDown
$numRefreshInterval.Location = New-Object System.Drawing.Point(222, 38)
$numRefreshInterval.Size = New-Object System.Drawing.Size(110, 24)
$numRefreshInterval.Minimum = [decimal]2
$numRefreshInterval.Maximum = [decimal]120
$numRefreshInterval.Value = [decimal]2
Apply-DarkNumeric $numRefreshInterval

$lblS3 = New-Object System.Windows.Forms.Label
$lblS3.Text = 'Background Image'
$lblS3.Location = New-Object System.Drawing.Point(346, 16)
$lblS3.Size = New-Object System.Drawing.Size(140, 20)

$txtBg = New-Object System.Windows.Forms.TextBox
$txtBg.Location = New-Object System.Drawing.Point(346, 38)
$txtBg.Size = New-Object System.Drawing.Size(406, 24)
$txtBg.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
Apply-DarkTextBox $txtBg

$btnBgBrowse = New-FlatButton 'Browse' 762 34 90 30
$btnBgBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnBgClear = New-FlatButton 'Clear' 858 34 90 30
$btnBgClear.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right

$settingsScroll = New-Object System.Windows.Forms.Panel
$settingsScroll.Location = New-Object System.Drawing.Point(16, 112)
$settingsScroll.Size = New-Object System.Drawing.Size(932, 486)
$settingsScroll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsScroll.AutoScroll = $true
$settingsScroll.AutoScrollMargin = New-Object System.Drawing.Size(0, 12)
$settingsScroll.BackColor = [System.Drawing.Color]::FromArgb(22, 25, 33)

function New-SettingLabel {
    param([string]$text,[int]$x,[int]$y,[int]$w=160)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x,$y)
    $l.Size = New-Object System.Drawing.Size($w,22)
    $l.AutoSize = $false
    $l.AutoEllipsis = $true
    $l.UseMnemonic = $false
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $l
}

function New-SettingText {
    param(
        [string]$key,
        [int]$x,
        [int]$y,
        [string]$default='',
        [switch]$isColor
    )
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x,$y)
    $textW = 160
    if ($isColor) { $textW = 128 }
    $t.Size = New-Object System.Drawing.Size($textW,24)
    $t.Text = $default
    Apply-DarkTextBox $t
    $styleControls[$key] = @{ type='string'; control=$t }
    return $t
}

function New-SettingNum {
    param([string]$key,[int]$x,[int]$y,[double]$min,[double]$max,[double]$step,[double]$default,[int]$decimals=0)
    $n = New-Object System.Windows.Forms.NumericUpDown
    $n.Location = New-Object System.Drawing.Point($x,$y)
    $n.Size = New-Object System.Drawing.Size(110,24)
    $n.Minimum = [decimal]$min
    $n.Maximum = [decimal]$max
    $n.Increment = [decimal]$step
    $n.DecimalPlaces = $decimals
    $n.Value = [decimal]$default
    Apply-DarkNumeric $n
    $styleControls[$key] = @{ type='number'; control=$n }
    return $n
}

function New-SettingCheck {
    param([string]$key,[int]$x,[int]$y,[bool]$default)
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Location = New-Object System.Drawing.Point($x,$y)
    $c.Size = New-Object System.Drawing.Size(40,24)
    $c.Checked = $default
    $c.ForeColor = [System.Drawing.Color]::FromArgb(220,226,238)
    $c.BackColor = [System.Drawing.Color]::FromArgb(22,25,33)
    $styleControls[$key] = @{ type='bool'; control=$c }
    return $c
}

function New-SettingGroup {
    param([string]$title,[int]$x,[int]$y,[int]$w,[int]$h)
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $title
    $g.Location = New-Object System.Drawing.Point($x,$y)
    $g.Size = New-Object System.Drawing.Size($w,$h)
    $g.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $g.ForeColor = [System.Drawing.Color]::FromArgb(232, 238, 252)
    $g.BackColor = [System.Drawing.Color]::FromArgb(24, 28, 38)
    $g.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
    return $g
}

function Try-ParseHexColor {
    param([string]$hex)
    try {
        if ([string]::IsNullOrWhiteSpace($hex)) { return $null }
        $h = $hex.Trim()
        if ($h -notmatch '^#[0-9A-Fa-f]{6}$') { return $null }
        return [System.Drawing.ColorTranslator]::FromHtml($h.ToUpperInvariant())
    } catch {
        return $null
    }
}

function New-ColorPickerButton {
    param([System.Windows.Forms.TextBox]$target,[int]$x,[int]$y)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = ''
    $b.Location = New-Object System.Drawing.Point($x,$y)
    $b.Size = New-Object System.Drawing.Size(24,24)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 1
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 78, 92)
    $b.BackColor = [System.Drawing.Color]::FromArgb(18, 22, 30)
    $b.ForeColor = [System.Drawing.Color]::White
    $b.UseVisualStyleBackColor = $false
    $b.Tag = $target
    $b.Add_Paint({
        param($sender, $e)
        $rect = New-Object System.Drawing.Rectangle(3, 3, ($sender.Width - 7), ($sender.Height - 7))
        $targetBox = [System.Windows.Forms.TextBox]$sender.Tag
        $picked = Try-ParseHexColor -hex $targetBox.Text
        if (-not $picked) { $picked = [System.Drawing.Color]::FromArgb(180, 180, 180) }
        $base = [System.Drawing.Color]::FromArgb(235, 235, 235)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $base, $picked, 45.0)
        $e.Graphics.FillRectangle($brush, $rect)
        $e.Graphics.DrawRectangle([System.Drawing.Pens]::Black, $rect)
        $brush.Dispose()
    })
    $b.Add_Click({
        param($sender, $eventArgs)
        $targetBox = [System.Windows.Forms.TextBox]$sender.Tag
        $dlg = New-Object System.Windows.Forms.ColorDialog
        $dlg.FullOpen = $true
        $parsed = Try-ParseHexColor -hex $targetBox.Text
        if ($parsed) { $dlg.Color = $parsed }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetBox.Text = ('#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B)
        }
        $dlg.Dispose()
    })
    $target.Tag = $b
    $target.Add_TextChanged({
        param($sender, $eventArgs)
        $picker = $sender.Tag
        if ($picker) { $picker.Invalidate() }
    })
    return $b
}

function Add-ColorField {
    param(
        [System.Windows.Forms.Control]$parent,
        [string]$label,
        [string]$key,
        [int]$x,
        [int]$y,
        [string]$default
    )
    $parent.Controls.Add((New-SettingLabel $label $x $y 102))
    $txt = New-SettingText -key $key -x ($x + 104) -y $y -default $default -isColor
    $parent.Controls.Add($txt)
    $pickerX = $txt.Left + $txt.Width + 2
    $parent.Controls.Add((New-ColorPickerButton -target $txt -x $pickerX -y $y))
}

function Update-SettingsScrollLayout {
    if (-not $settingsScroll) { return }
    $targetW = [Math]::Max(700, $settingsScroll.ClientSize.Width - 24)
    if ($script:settingGroups) {
        foreach ($g in $script:settingGroups) {
            if ($g) { $g.Width = $targetW }
        }
    }

    $maxBottom = 0
    $maxRight = 0
    foreach ($ctrl in $settingsScroll.Controls) {
        if (-not $ctrl.Visible) { continue }
        if ($ctrl.Bottom -gt $maxBottom) { $maxBottom = $ctrl.Bottom }
        if ($ctrl.Right -gt $maxRight) { $maxRight = $ctrl.Right }
    }
    # Hide horizontal scrollbar by pinning content width to viewport width.
    $minW = [Math]::Max(0, $settingsScroll.ClientSize.Width)
    $minH = [Math]::Max($settingsScroll.ClientSize.Height + 2, $maxBottom + 32)
    $settingsScroll.AutoScrollMinSize = New-Object System.Drawing.Size($minW, $minH)
    $settingsScroll.PerformLayout()
    $settingsScroll.Refresh()
}

function Update-SettingsHeaderLayout {
    if (-not $tabSettings) { return }
    if (-not $btnApplySettings -or -not $btnResetStyle) { return }
    if (-not $btnBgBrowse -or -not $btnBgClear -or -not $txtBg) { return }

    $rightPad = 16
    $gap = 8

    $btnApplySettings.Top = 74
    $btnResetStyle.Top = 74
    $btnApplySettings.Left = [Math]::Max(16, $tabSettings.ClientSize.Width - $rightPad - $btnApplySettings.Width)
    $btnResetStyle.Left = [Math]::Max(16, $btnApplySettings.Left - $gap - $btnResetStyle.Width)

    $btnBgClear.Left = [Math]::Max(16, $tabSettings.ClientSize.Width - $rightPad - $btnBgClear.Width)
    $btnBgBrowse.Left = [Math]::Max(16, $btnBgClear.Left - $gap - $btnBgBrowse.Width)
    $txtBg.Width = [Math]::Max(260, $btnBgBrowse.Left - $gap - $txtBg.Left)

    $settingsScroll.Width = [Math]::Max(320, $tabSettings.ClientSize.Width - 32)
    $settingsScroll.Height = [Math]::Max(180, $tabSettings.ClientSize.Height - $settingsScroll.Top - 14)
}

$fullW = 910
$currentY = 8

$grpGlobal = New-SettingGroup 'Typography and Global Colors' 8 $currentY $fullW 90
$grpGlobal.Controls.Add((New-SettingLabel 'Font Family' 12 30 88))
$grpGlobal.Controls.Add((New-SettingText 'fontFamily' 102 30 'Segoe UI'))
Add-ColorField -parent $grpGlobal -label 'Text Color' -key 'textColor' -x 300 -y 30 -default '#D3D3D3'
Add-ColorField -parent $grpGlobal -label 'Background' -key 'bgColor' -x 588 -y 30 -default '#141414'
$settingsScroll.Controls.Add($grpGlobal)
$currentY += 102

$grpClock = New-SettingGroup 'Clock' 8 $currentY $fullW 126
Add-ColorField -parent $grpClock -label 'Clock Color' -key 'clockColor' -x 12 -y 28 -default '#F51414'
Add-ColorField -parent $grpClock -label 'Clock BG' -key 'clockBgColor' -x 300 -y 28 -default '#AA1E23'
Add-ColorField -parent $grpClock -label 'Clock Off' -key 'clockOffColor' -x 588 -y 28 -default '#460000'
Add-ColorField -parent $grpClock -label 'Day Color' -key 'clockDayColor' -x 12 -y 62 -default '#F51414'
$grpClock.Controls.Add((New-SettingLabel 'Font Size' 300 64 72))
$grpClock.Controls.Add((New-SettingNum 'clockFontSize' 374 62 10 80 1 28 0))
$grpClock.Controls.Add((New-SettingLabel 'Bottom Gap' 588 64 72))
$grpClock.Controls.Add((New-SettingNum 'clockBottomGap' 664 62 0 40 1 4 0))
$settingsScroll.Controls.Add($grpClock)
$currentY += 138

$grpMetrics = New-SettingGroup 'CPU / RAM / GPU' 8 $currentY $fullW 200
$grpMetrics.Controls.Add((New-SettingLabel 'CPU Font Size' 12 28 88))
$grpMetrics.Controls.Add((New-SettingNum 'cpuFontSize' 102 26 8 48 1 16 0))
$grpMetrics.Controls.Add((New-SettingLabel 'RAM Font Size' 300 28 88))
$grpMetrics.Controls.Add((New-SettingNum 'ramFontSize' 392 26 8 48 1 16 0))
$grpMetrics.Controls.Add((New-SettingLabel 'GPU Font Size' 588 28 88))
$grpMetrics.Controls.Add((New-SettingNum 'gpuFontSize' 680 26 8 48 1 16 0))
Add-ColorField -parent $grpMetrics -label 'CPU Text' -key 'cpuTextColor' -x 12 -y 62 -default '#D3D3D3'
Add-ColorField -parent $grpMetrics -label 'RAM Text' -key 'ramTextColor' -x 300 -y 62 -default '#D3D3D3'
Add-ColorField -parent $grpMetrics -label 'GPU Text' -key 'gpuTextColor' -x 588 -y 62 -default '#D3D3D3'
Add-ColorField -parent $grpMetrics -label 'CPU Bar' -key 'cpuBarColor' -x 12 -y 96 -default '#28C850'
Add-ColorField -parent $grpMetrics -label 'RAM Bar' -key 'ramBarColor' -x 300 -y 96 -default '#3C78FF'
Add-ColorField -parent $grpMetrics -label 'GPU Bar' -key 'gpuBarColor' -x 588 -y 96 -default '#B450C8'
Add-ColorField -parent $grpMetrics -label 'Bar BG' -key 'barBackgroundColor' -x 12 -y 130 -default '#323232'
$grpMetrics.Controls.Add((New-SettingLabel 'Bar Opacity %' 300 132 88))
$grpMetrics.Controls.Add((New-SettingNum 'barTransparencyPct' 392 130 0 100 1 100 0))
$grpMetrics.Controls.Add((New-SettingLabel 'Bar BG Opacity %' 588 132 100))
$grpMetrics.Controls.Add((New-SettingNum 'barBackgroundTransparencyPct' 692 130 0 100 1 100 0))
$settingsScroll.Controls.Add($grpMetrics)
$currentY += 212

$grpSpacing = New-SettingGroup 'Spacing and Background Effects' 8 $currentY $fullW 96
$grpSpacing.Controls.Add((New-SettingLabel 'Label->Bar' 12 28 70))
$grpSpacing.Controls.Add((New-SettingNum 'labelToBarGap' 84 26 0 20 1 4 0))
$grpSpacing.Controls.Add((New-SettingLabel 'Section Gap' 196 28 72))
$grpSpacing.Controls.Add((New-SettingNum 'sectionGap' 270 26 0 30 1 4 0))
$grpSpacing.Controls.Add((New-SettingLabel 'RAM->Spotify Gap' 380 28 116))
$grpSpacing.Controls.Add((New-SettingNum 'ramToSpotifyGap' 500 26 0 40 1 7 0))
$grpSpacing.Controls.Add((New-SettingLabel 'BG Blur %' 570 28 62))
$grpSpacing.Controls.Add((New-SettingNum 'backgroundBlurPct' 636 26 0 100 1 0 0))
$grpSpacing.Controls.Add((New-SettingLabel 'Overlay %' 748 28 62))
$grpSpacing.Controls.Add((New-SettingNum 'backgroundOverlayPct' 816 26 0 100 1 43 0))
$settingsScroll.Controls.Add($grpSpacing)
$currentY += 108

$grpSpotify = New-SettingGroup 'Spotify Box' 8 $currentY $fullW 124
$grpSpotify.Controls.Add((New-SettingLabel 'Show Image' 12 28 70))
$grpSpotify.Controls.Add((New-SettingCheck 'spotifyShowImage' 84 26 $true))
Add-ColorField -parent $grpSpotify -label 'BG Color' -key 'spotifyBgColor' -x 170 -y 28 -default '#28C850'
Add-ColorField -parent $grpSpotify -label 'Text Color' -key 'spotifyTextColor' -x 458 -y 28 -default '#000000'
$grpSpotify.Controls.Add((New-SettingLabel 'BG Opacity %' 748 30 74))
$grpSpotify.Controls.Add((New-SettingNum 'spotifyBgTransparencyPct' 822 28 0 100 1 100 0))
$grpSpotify.Controls.Add((New-SettingLabel 'Artist Font Size' 12 64 88))
$grpSpotify.Controls.Add((New-SettingNum 'spotifyArtistFontSize' 102 62 8 48 1 14 0))
$grpSpotify.Controls.Add((New-SettingLabel 'Track Font Size' 300 64 88))
$grpSpotify.Controls.Add((New-SettingNum 'spotifyTrackFontSize' 392 62 8 48 1 14 0))
$grpSpotify.Controls.Add((New-SettingLabel 'Line Height' 588 64 72))
$grpSpotify.Controls.Add((New-SettingNum 'spotifyLineHeight' 662 62 0.5 2.0 0.1 1.0 1))
$settingsScroll.Controls.Add($grpSpotify)

$btnResetStyle = New-FlatButton 'Reset Settings' 698 74 120 32
$btnApplySettings = New-FlatButton 'Apply Settings' 826 74 120 32
$btnResetStyle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnApplySettings.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnApplySettings.BackColor = [System.Drawing.Color]::FromArgb(38, 92, 64)
$btnApplySettings.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(56, 136, 96)
$script:settingGroups = @($grpGlobal, $grpClock, $grpMetrics, $grpSpacing, $grpSpotify)
$settingsScroll.AutoScrollMinSize = New-Object System.Drawing.Size(980, ($grpSpotify.Bottom + 72))

$tabSettings.Add_Resize({
    Update-SettingsHeaderLayout
    Update-SettingsScrollLayout
})
$settingsScroll.Add_Resize({ Update-SettingsScrollLayout })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabSettings) {
        Update-SettingsHeaderLayout
        Update-SettingsScrollLayout
    }
})

$tabSettings.Controls.AddRange(@($lblS1,$cmbClockStyle,$lblS2,$numRefreshInterval,$lblS3,$txtBg,$btnBgBrowse,$btnBgClear,$btnResetStyle,$btnApplySettings,$settingsScroll))

function Update-Ui {
    $running = Get-IsRunning
    if ($running) {
        $lblStatus.Text = 'Status: RUNNING'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(70, 235, 138)
    } else {
        $lblStatus.Text = 'Status: STOPPED'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(240, 108, 108)
    }

    $web = Get-WebPreviewState
    if ($web.running) {
        $lblWeb.Text = ("Web: ON ({0})" -f $web.port)
        $lblWeb.ForeColor = [System.Drawing.Color]::FromArgb(90, 204, 255)
    } else {
        $lblWeb.Text = 'Web: OFF'
        $lblWeb.ForeColor = [System.Drawing.Color]::FromArgb(160, 170, 186)
    }

    $logBox.Text = Get-LogTail -lines 18
    $img = Load-PreviewImage
    if ($img) {
        if ($preview.Image) { $preview.Image.Dispose() }
        $preview.Image = $img
    }
}

$btnStart.Add_Click({ Invoke-BypassFile -path $startScript; Update-Ui })
$btnStop.Add_Click({ Invoke-BypassFile -path $stopScript; Update-Ui })
$btnRestart.Add_Click({ Invoke-BypassFile -path $stopScript; Invoke-BypassFile -path $startScript; Update-Ui })
$btnRefresh.Add_Click({ Invoke-BypassFile -path $renderOnceScript; Update-Ui })
$btnWebStart.Add_Click({ Invoke-BypassFile -path $startWebScript; Update-Ui })
$btnWebStop.Add_Click({ Invoke-BypassFile -path $stopWebScript; Update-Ui })
$btnWebOpen.Add_Click({
    $web = Get-WebPreviewState
    if (-not $web.running) {
        Invoke-BypassFile -path $startWebScript
        Start-Sleep -Milliseconds 300
        $web = Get-WebPreviewState
    }
    Start-Process -FilePath $web.url | Out-Null
    Update-Ui
})
$btnOpenFrame.Add_Click({ if (Test-Path $framePath) { Start-Process -FilePath $framePath | Out-Null } })
$btnOpenFolder.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $projectRoot) | Out-Null })

$btnBgBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Select background image'
    $dlg.Filter = 'Image files (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp|All files (*.*)|*.*'
    $dlg.InitialDirectory = $projectRoot
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtBg.Text = $dlg.FileName }
    $dlg.Dispose()
})

$btnBgClear.Add_Click({ $txtBg.Text = '' })

$btnResetStyle.Add_Click({
    $defaultStyle = Get-DefaultStyleSettings
    foreach ($k in $styleControls.Keys) {
        if (-not $defaultStyle.Contains($k)) { continue }
        $meta = $styleControls[$k]
        $ctrl = $meta.control
        switch ($meta.type) {
            'number' { try { $ctrl.Value = [decimal]$defaultStyle[$k] } catch { } }
            'bool' { $ctrl.Checked = [bool]$defaultStyle[$k] }
            default { $ctrl.Text = [string]$defaultStyle[$k] }
        }
    }
    $settingsScroll.PerformLayout()
    $settingsScroll.Refresh()
    $tabSettings.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    Update-SettingsScrollLayout
})

$btnApplySettings.Add_Click({
    $styleName = switch ([string]$cmbClockStyle.SelectedItem) {
        'Classic' { 'classic' }
        'Classic Plain' { 'classic_plain' }
        default { 'sevenseg' }
    }
    $bg = ([string]$txtBg.Text).Trim()
    if (-not [string]::IsNullOrWhiteSpace($bg) -and -not (Test-Path $bg)) {
        [System.Windows.Forms.MessageBox]::Show("Background file not found:`n$bg", 'Invalid Background', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $styleObj = [ordered]@{}
    foreach ($k in $styleControls.Keys) {
        $meta = $styleControls[$k]
        $ctrl = $meta.control
        switch ($meta.type) {
            'number' { $styleObj[$k] = [double]$ctrl.Value }
            'bool' { $styleObj[$k] = [bool]$ctrl.Checked }
            default { $styleObj[$k] = [string]$ctrl.Text }
        }
    }

    $intervalSec = [int]$numRefreshInterval.Value
    Save-AppSettings -style $styleName -backgroundImage $bg -refreshIntervalSeconds $intervalSec -styleObject $styleObj
    Invoke-BypassFile -path $stopScript
    Invoke-BypassFile -path $startScript
    Show-ApplyLoader -seconds $intervalSec -title 'Applying Settings'
    Invoke-BypassFile -path $renderOnceScript
    Update-Ui
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-Ui })
$timer.Start()

$form.Add_Shown({
    Set-DarkTitleBar -window $form
    Set-DarkControlTheme -control $tabs
    Set-DarkControlTheme -control $settingsScroll

    $app = Load-AppSettings
    switch ($app.clockStyle) {
        'classic' { $cmbClockStyle.SelectedItem = 'Classic' }
        'classic_plain' { $cmbClockStyle.SelectedItem = 'Classic Plain' }
        default { $cmbClockStyle.SelectedItem = 'Seven-seg' }
    }
    $txtBg.Text = $app.backgroundImage
    try { $numRefreshInterval.Value = [decimal]$app.refreshIntervalSeconds } catch { $numRefreshInterval.Value = [decimal]2 }
    foreach ($k in $styleControls.Keys) {
        if (-not $app.style.Contains($k)) { continue }
        $meta = $styleControls[$k]
        $ctrl = $meta.control
        $v = $app.style[$k]
        switch ($meta.type) {
            'number' { try { $ctrl.Value = [decimal]$v } catch { } }
            'bool' { $ctrl.Checked = [bool]$v }
            default { $ctrl.Text = [string]$v }
        }
    }
    Update-SettingsScrollLayout
    Update-SettingsHeaderLayout
    Update-Ui
})

$form.Add_FormClosed({
    $timer.Stop()
    $timer.Dispose()
    if ($preview.Image) { $preview.Image.Dispose() }
})

[void]$form.ShowDialog()
