param(
    [string]$OutFileName = 'frame.jpg'
)
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition -Resolve) '00-utils.ps1')

function FitLine { param($g,$font,$text,$maxW)
    if ([string]::IsNullOrEmpty($text)) { return '' }
    $lo = 0; $hi = $text.Length
    while ($lo -lt $hi) {
        $mid = [int](($lo + $hi + 1) / 2)
        $candidate = $text.Substring(0, $mid)
        $w = $g.MeasureString($candidate, $font).Width
        if ($w -le $maxW) { $lo = $mid } else { $hi = $mid - 1 }
    }
    return $text.Substring(0, $lo)
}

function Ellipsize { param($g,$font,$text,$maxW)
    $t = $text.TrimEnd()
    if ($g.MeasureString($t, $font).Width -le $maxW) { return $t }
    $dots = "..."
    if ($g.MeasureString($dots, $font).Width -gt $maxW) { return "" }
    $mx = $t
    while ($mx.Length -gt 0 -and $g.MeasureString(($mx + $dots), $font).Width -gt $maxW) {
        $mx = $mx.Substring(0, $mx.Length - 1)
    }
    return ($mx.TrimEnd() + $dots)
}

function Draw-UniformBar {
    param(
        $g,[int]$x,[int]$y,[int]$w,[int]$h,[double]$pct,
        [System.Drawing.Color]$fillColor,[System.Drawing.Brush]$bgBrush
    )
    $clamped = [math]::Min(100, [math]::Max(0, $pct))
    $fillW = [int][math]::Round(($clamped / 100.0) * $w)
    if ($clamped -gt 0) { $fillW = [math]::Max(2, $fillW) }
    $g.FillRectangle($bgBrush, $x, $y, $w, $h)
    $fillBrush = New-Object System.Drawing.SolidBrush $fillColor
    $g.FillRectangle($fillBrush, $x, $y, $fillW, $h)
    $g.DrawRectangle([System.Drawing.Pens]::Gray, $x, $y, $w, $h)
    $fillBrush.Dispose()
}

function Draw-RoundedRectFilled {
    param(
        $g,[int]$x,[int]$y,[int]$w,[int]$h,[int]$radius,[System.Drawing.Color]$fillColor
    )
    $r2 = $radius * 2
    $brush = New-Object System.Drawing.SolidBrush $fillColor
    if ($r2 -gt $w -or $r2 -gt $h) {
        $g.FillRectangle($brush, $x, $y, $w, $h)
    } else {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc($x, $y, $r2, $r2, 180, 90)
        $path.AddArc($x + $w - $r2, $y, $r2, $r2, 270, 90)
        $path.AddArc($x + $w - $r2, $y + $h - $r2, $r2, $r2, 0, 90)
        $path.AddArc($x, $y + $h - $r2, $r2, $r2, 90, 90)
        $path.CloseFigure()
        $g.FillPath($brush, $path)
        $path.Dispose()
    }
    $brush.Dispose()
}

function Get-RenderStyleObject {
    if (Get-Variable -Name STYLE -Scope Script -ErrorAction SilentlyContinue) {
        return $Script:STYLE
    }
    return $null
}

function Get-StyleValue {
    param($style, [string]$name, $defaultValue)
    if ($null -eq $style) { return $defaultValue }
    $prop = $style.PSObject.Properties[$name]
    if ($prop -and $null -ne $prop.Value -and [string]$prop.Value -ne '') {
        return $prop.Value
    }
    return $defaultValue
}

function Get-StyleInt {
    param($style, [string]$name, [int]$defaultValue)
    try { return [int](Get-StyleValue -style $style -name $name -defaultValue $defaultValue) } catch { return $defaultValue }
}

function Get-StyleDouble {
    param($style, [string]$name, [double]$defaultValue)
    try { return [double](Get-StyleValue -style $style -name $name -defaultValue $defaultValue) } catch { return $defaultValue }
}

function Get-StyleBool {
    param($style, [string]$name, [bool]$defaultValue)
    try { return [bool](Get-StyleValue -style $style -name $name -defaultValue $defaultValue) } catch { return $defaultValue }
}

function Get-StyleString {
    param($style, [string]$name, [string]$defaultValue)
    try { return [string](Get-StyleValue -style $style -name $name -defaultValue $defaultValue) } catch { return $defaultValue }
}

function Convert-PercentToAlpha {
    param([double]$percent)
    $p = [math]::Min(100.0, [math]::Max(0.0, $percent))
    return [int][math]::Round((255.0 * $p) / 100.0)
}

function Parse-HexColor {
    param(
        [string]$hex,
        [System.Drawing.Color]$fallback,
        [int]$alpha = -1
    )
    if ([string]::IsNullOrWhiteSpace($hex)) {
        if ($alpha -ge 0) { return [System.Drawing.Color]::FromArgb($alpha, $fallback.R, $fallback.G, $fallback.B) }
        return $fallback
    }

    $h = $hex.Trim()
    if ($h.StartsWith('#')) { $h = $h.Substring(1) }
    try {
        if ($h.Length -eq 6) {
            $r = [Convert]::ToInt32($h.Substring(0,2), 16)
            $g = [Convert]::ToInt32($h.Substring(2,2), 16)
            $b = [Convert]::ToInt32($h.Substring(4,2), 16)
            $a = if ($alpha -ge 0) { $alpha } else { 255 }
            return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
        }
        if ($h.Length -eq 8) {
            $aHex = [Convert]::ToInt32($h.Substring(0,2), 16)
            $r = [Convert]::ToInt32($h.Substring(2,2), 16)
            $g = [Convert]::ToInt32($h.Substring(4,2), 16)
            $b = [Convert]::ToInt32($h.Substring(6,2), 16)
            $a = if ($alpha -ge 0) { $alpha } else { $aHex }
            return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
        }
    } catch { }

    if ($alpha -ge 0) { return [System.Drawing.Color]::FromArgb($alpha, $fallback.R, $fallback.G, $fallback.B) }
    return $fallback
}

function Get-SevenSegDigitMap {
    param([char]$digit)
    switch ($digit) {
        '0' { return @(0,1,2,3,4,5) }       # a,b,c,d,e,f
        '1' { return @(1,2) }               # b,c
        '2' { return @(0,1,6,4,3) }         # a,b,g,e,d
        '3' { return @(0,1,6,2,3) }         # a,b,g,c,d
        '4' { return @(5,6,1,2) }           # f,g,b,c
        '5' { return @(0,5,6,2,3) }         # a,f,g,c,d
        '6' { return @(0,5,6,4,2,3) }       # a,f,g,e,c,d
        '7' { return @(0,1,2) }             # a,b,c
        '8' { return @(0,1,2,3,4,5,6) }     # all
        '9' { return @(0,1,2,3,5,6) }       # a,b,c,d,f,g
        default { return @() }
    }
}

function Draw-SevenSegDigit {
    param(
        $g,
        [int]$x,
        [int]$y,
        [int]$w,
        [int]$h,
        [int]$t,
        [char]$digit,
        [System.Drawing.Color]$onColor,
        [System.Drawing.Color]$offColor
    )

    $halfH = [int][math]::Floor($h / 2)
    $x0 = [int]$x; $y0 = [int]$y; $w0 = [int]$w; $h0 = [int]$h; $t0 = [int]$t
    $segRects = @(
        [System.Drawing.Rectangle]::new([int]($x0 + $t0), [int]$y0, [int]($w0 - (2 * $t0)), [int]$t0),                                         # a
        [System.Drawing.Rectangle]::new([int]($x0 + $w0 - $t0), [int]($y0 + $t0), [int]$t0, [int]($halfH - $t0)),                             # b
        [System.Drawing.Rectangle]::new([int]($x0 + $w0 - $t0), [int]($y0 + $halfH), [int]$t0, [int]($halfH - $t0)),                         # c
        [System.Drawing.Rectangle]::new([int]($x0 + $t0), [int]($y0 + $h0 - $t0), [int]($w0 - (2 * $t0)), [int]$t0),                         # d
        [System.Drawing.Rectangle]::new([int]$x0, [int]($y0 + $halfH), [int]$t0, [int]($halfH - $t0)),                                       # e
        [System.Drawing.Rectangle]::new([int]$x0, [int]($y0 + $t0), [int]$t0, [int]($halfH - $t0)),                                          # f
        [System.Drawing.Rectangle]::new([int]($x0 + $t0), [int]($y0 + [int][math]::Floor(($h0 - $t0) / 2)), [int]($w0 - (2 * $t0)), [int]$t0) # g
    )

    $activeSegs = Get-SevenSegDigitMap $digit
    for ($i = 0; $i -lt 7; $i++) {
        $r = $segRects[$i]
        $isOn = ($activeSegs -contains $i)
        if ($isOn) {
            $glow = [System.Drawing.Color]::FromArgb(60, $onColor.R, $onColor.G, $onColor.B)
            $glowBrush = New-Object System.Drawing.SolidBrush $glow
            $g.FillRectangle($glowBrush, $r.X - 2, $r.Y - 2, $r.Width + 4, $r.Height + 4)
            $glowBrush.Dispose()
        }
        $c = if ($isOn) { $onColor } else { $offColor }
        $brush = New-Object System.Drawing.SolidBrush $c
        $g.FillRectangle($brush, $r)
        $brush.Dispose()
    }
}

function Draw-SevenSegClock {
    param(
        $g,
        [string]$timeStr,
        [int]$canvasW,
        [int]$topY,
        [double]$scale,
        [System.Drawing.Color]$onColor,
        [System.Drawing.Color]$offColor,
        [System.Drawing.Color]$dayColor
    )

    if ($scale -le 0) { $scale = 1.0 }
    $digitW = [int][math]::Round(27 * $scale)
    $digitH = [int][math]::Round(48 * $scale)
    $segT = [int][math]::Max(2, [math]::Round(5 * $scale))
    $gap = [int][math]::Round(8 * $scale)
    $colonW = [int][math]::Round(10 * $scale)
    $prefixGap = [int][math]::Round(8 * $scale)
    $dayPrefix = switch ((Get-Date).DayOfWeek.ToString()) {
        'Monday'    { 'MO' }
        'Tuesday'   { 'TU' }
        'Wednesday' { 'WE' }
        'Thursday'  { 'TH' }
        'Friday'    { 'FR' }
        'Saturday'  { 'SA' }
        'Sunday'    { 'SU' }
        default     { '??' }
    }
    $dayFont = New-Object System.Drawing.Font('Consolas', [float](16.0 * $scale), [System.Drawing.FontStyle]::Bold)
    $daySize = $g.MeasureString($dayPrefix, $dayFont)
    $dayW = [int][math]::Ceiling($daySize.Width)
    $dayH = [int][math]::Ceiling($daySize.Height)

    $totalW = $dayW + $prefixGap + ($digitW * 4) + ($gap * 3) + $colonW
    $startX = [int](($canvasW - $totalW) / 2)

    $dayBrush = New-Object System.Drawing.SolidBrush $dayColor

    $chars = $timeStr.ToCharArray()
    $dayY = $topY + [int][math]::Floor(($digitH - $dayH) / 2)
    $g.DrawString($dayPrefix, $dayFont, $dayBrush, $startX, $dayY)
    $x = $startX + $dayW + $prefixGap

    Draw-SevenSegDigit -g $g -x $x -y $topY -w $digitW -h $digitH -t $segT -digit $chars[0] -onColor $onColor -offColor $offColor
    $x += $digitW + $gap
    Draw-SevenSegDigit -g $g -x $x -y $topY -w $digitW -h $digitH -t $segT -digit $chars[1] -onColor $onColor -offColor $offColor
    $x += $digitW + 2

    # colon
    $dotR = [int][math]::Max(2, [math]::Round(4 * $scale))
    $cx = $x + [int]($colonW / 2)
    $cy1 = $topY + [int]($digitH * 0.38)
    $cy2 = $topY + [int]($digitH * 0.62)
    $dotGlow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(65, $onColor.R, $onColor.G, $onColor.B))
    $dotBrush = New-Object System.Drawing.SolidBrush $onColor
    $g.FillEllipse($dotGlow, $cx - $dotR - 2, $cy1 - $dotR - 2, ($dotR * 2) + 4, ($dotR * 2) + 4)
    $g.FillEllipse($dotGlow, $cx - $dotR - 2, $cy2 - $dotR - 2, ($dotR * 2) + 4, ($dotR * 2) + 4)
    $g.FillEllipse($dotBrush, $cx - $dotR, $cy1 - $dotR, $dotR * 2, $dotR * 2)
    $g.FillEllipse($dotBrush, $cx - $dotR, $cy2 - $dotR, $dotR * 2, $dotR * 2)
    $dotGlow.Dispose(); $dotBrush.Dispose()

    $x += $colonW + 2
    Draw-SevenSegDigit -g $g -x $x -y $topY -w $digitW -h $digitH -t $segT -digit $chars[3] -onColor $onColor -offColor $offColor
    $x += $digitW + $gap
    Draw-SevenSegDigit -g $g -x $x -y $topY -w $digitW -h $digitH -t $segT -digit $chars[4] -onColor $onColor -offColor $offColor

    $dayBrush.Dispose()
    $dayFont.Dispose()
    return ($topY + $digitH)
}

function Draw-ClassicClock {
    param(
        $g,
        [string]$timeStr,
        [int]$canvasW,
        [int]$topY,
        $fontClock,
        [System.Drawing.Color]$textColor,
        [System.Drawing.Color]$bgColor
    )

    $dayPrefix = switch ((Get-Date).DayOfWeek.ToString()) {
        'Monday'    { 'MO' }
        'Tuesday'   { 'TU' }
        'Wednesday' { 'WE' }
        'Thursday'  { 'TH' }
        'Friday'    { 'FR' }
        'Saturday'  { 'SA' }
        'Sunday'    { 'SU' }
        default     { '??' }
    }
    $timeWithDay = "$dayPrefix $timeStr"
    $sz = $g.MeasureString($timeWithDay, $fontClock)
    $clockPadX = 5
    $clockPadY = 1
    $clockW = [int][math]::Ceiling($sz.Width + ($clockPadX * 2))
    $clockH = [int][math]::Ceiling($sz.Height + ($clockPadY * 2))
    $clockX = [int](($canvasW - $clockW) / 2)
    Draw-RoundedRectFilled -g $g -x $clockX -y $topY -w $clockW -h $clockH -radius 12 -fillColor $bgColor
    $tx = [int](($canvasW - $sz.Width) / 2)
    $ty = $topY + $clockPadY - 1
    $clockBrush = New-Object System.Drawing.SolidBrush $textColor
    $g.DrawString($timeWithDay, $fontClock, $clockBrush, $tx, $ty)
    $clockBrush.Dispose()
    return ($topY + $clockH)
}

function Draw-ClassicPlainClock {
    param(
        $g,
        [string]$timeStr,
        [int]$canvasW,
        [int]$topY,
        $fontClock,
        [System.Drawing.Color]$textColor
    )

    $dayPrefix = switch ((Get-Date).DayOfWeek.ToString()) {
        'Monday'    { 'MO' }
        'Tuesday'   { 'TU' }
        'Wednesday' { 'WE' }
        'Thursday'  { 'TH' }
        'Friday'    { 'FR' }
        'Saturday'  { 'SA' }
        'Sunday'    { 'SU' }
        default     { '??' }
    }
    $timeWithDay = "$dayPrefix $timeStr"
    $sz = $g.MeasureString($timeWithDay, $fontClock)
    $tx = [int](($canvasW - $sz.Width) / 2)
    $clockBrush = New-Object System.Drawing.SolidBrush $textColor
    $g.DrawString($timeWithDay, $fontClock, $clockBrush, $tx, $topY)
    $clockBrush.Dispose()
    $clockH = [int][math]::Ceiling($sz.Height)
    return ($topY + $clockH)
}

function Draw-BackgroundImage {
    param(
        $g,
        [string]$path,
        [int]$canvasW,
        [int]$canvasH,
        [double]$blurPct
    )
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if (-not (Test-Path $path)) { return $false }

    $fs = $null
    $img = $null
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $img = [System.Drawing.Image]::FromStream($fs)
        if ($img.Width -le 0 -or $img.Height -le 0) { return $false }

        $scale = [math]::Max(($canvasW / [double]$img.Width), ($canvasH / [double]$img.Height))
        $drawW = [int][math]::Ceiling($img.Width * $scale)
        $drawH = [int][math]::Ceiling($img.Height * $scale)
        $drawX = [int][math]::Floor(($canvasW - $drawW) / 2)
        $drawY = [int][math]::Floor(($canvasH - $drawH) / 2)
        $destRect = [System.Drawing.Rectangle]::new($drawX, $drawY, $drawW, $drawH)
        $blur = [math]::Min(100.0, [math]::Max(0.0, $blurPct))
        if ($blur -le 0.1) {
            $g.DrawImage($img, $destRect)
            return $true
        }

        # Fast blur approximation: downscale then upscale.
        $factor = [math]::Max(0.08, (100.0 - $blur) / 100.0)
        $smallW = [int][math]::Max(1, [math]::Round($canvasW * $factor))
        $smallH = [int][math]::Max(1, [math]::Round($canvasH * $factor))
        $tmpBig = New-Object System.Drawing.Bitmap $canvasW, $canvasH
        $tmpSmall = New-Object System.Drawing.Bitmap $smallW, $smallH
        $gBig = [System.Drawing.Graphics]::FromImage($tmpBig)
        $gSmall = [System.Drawing.Graphics]::FromImage($tmpSmall)
        try {
            $gBig.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gSmall.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gBig.DrawImage($img, $destRect)
            $gSmall.DrawImage($tmpBig, [System.Drawing.Rectangle]::new(0, 0, $smallW, $smallH))
            $g.DrawImage($tmpSmall, [System.Drawing.Rectangle]::new(0, 0, $canvasW, $canvasH))
        } finally {
            $gSmall.Dispose()
            $gBig.Dispose()
            $tmpSmall.Dispose()
            $tmpBig.Dispose()
        }
        return $true
    } catch {
        Write-DebugLine ("BackgroundImage err: {0}" -f $_.Exception.Message)
        return $false
    } finally {
        if ($img) { $img.Dispose() }
        if ($fs) { $fs.Dispose() }
    }
}

function Render-Frame {
    param([string]$pathDir, [string]$outFileName)

    $W = 240; $H = 240
    $pixFmt = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    $bmp = New-Object System.Drawing.Bitmap $W, $H, $pixFmt
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $style = Get-RenderStyleObject

    $bgColor = Parse-HexColor -hex (Get-StyleString $style 'bgColor' '#141414') -fallback ([System.Drawing.Color]::FromArgb(20,20,20))
    $textColorDefault = Parse-HexColor -hex (Get-StyleString $style 'textColor' '#D3D3D3') -fallback ([System.Drawing.Color]::LightGray)
    $clockTextColor = Parse-HexColor -hex (Get-StyleString $style 'clockColor' '#F51414') -fallback ([System.Drawing.Color]::FromArgb(240, 245, 20, 20))
    $clockBgColor = Parse-HexColor -hex (Get-StyleString $style 'clockBgColor' '#AA1E23') -fallback ([System.Drawing.Color]::FromArgb(190, 170, 30, 35))
    $clockOffColor = Parse-HexColor -hex (Get-StyleString $style 'clockOffColor' '#460000') -fallback ([System.Drawing.Color]::FromArgb(70, 60, 0, 0))
    $clockDayColor = Parse-HexColor -hex (Get-StyleString $style 'clockDayColor' '#F51414') -fallback ([System.Drawing.Color]::FromArgb(220, 245, 20, 20))

    $cpuTextColor = Parse-HexColor -hex (Get-StyleString $style 'cpuTextColor' '') -fallback $textColorDefault
    $ramTextColor = Parse-HexColor -hex (Get-StyleString $style 'ramTextColor' '') -fallback $textColorDefault
    $gpuTextColor = Parse-HexColor -hex (Get-StyleString $style 'gpuTextColor' '') -fallback $textColorDefault
    $spotifyTextColor = Parse-HexColor -hex (Get-StyleString $style 'spotifyTextColor' '#000000') -fallback ([System.Drawing.Color]::Black)

    $barAlpha = Convert-PercentToAlpha (Get-StyleDouble $style 'barTransparencyPct' 100)
    $barBgAlpha = Convert-PercentToAlpha (Get-StyleDouble $style 'barBackgroundTransparencyPct' 100)
    $cpuBarColor = Parse-HexColor -hex (Get-StyleString $style 'cpuBarColor' '#28C850') -fallback ([System.Drawing.Color]::FromArgb(40,200,80)) -alpha $barAlpha
    $ramBarColor = Parse-HexColor -hex (Get-StyleString $style 'ramBarColor' '#3C78FF') -fallback ([System.Drawing.Color]::FromArgb(60,120,255)) -alpha $barAlpha
    $gpuBarColor = Parse-HexColor -hex (Get-StyleString $style 'gpuBarColor' '#B450C8') -fallback ([System.Drawing.Color]::FromArgb(180,80,200)) -alpha $barAlpha
    $barBgColor = Parse-HexColor -hex (Get-StyleString $style 'barBackgroundColor' '#323232') -fallback ([System.Drawing.Color]::FromArgb(50,50,50)) -alpha $barBgAlpha
    $barBgBrush = New-Object System.Drawing.SolidBrush $barBgColor

    $spotifyBgAlpha = Convert-PercentToAlpha (Get-StyleDouble $style 'spotifyBgTransparencyPct' 100)
    $spotifyBgColor = Parse-HexColor -hex (Get-StyleString $style 'spotifyBgColor' '#28C850') -fallback ([System.Drawing.Color]::FromArgb(40,200,80)) -alpha $spotifyBgAlpha
    $spotifyShowImage = Get-StyleBool $style 'spotifyShowImage' $true

    $fontFamily = Get-StyleString $style 'fontFamily' 'Segoe UI'
    $clockFontSize = [float](Get-StyleDouble $style 'clockFontSize' 28)
    $cpuFontSize = [float](Get-StyleDouble $style 'cpuFontSize' 16)
    $ramFontSize = [float](Get-StyleDouble $style 'ramFontSize' $cpuFontSize)
    $gpuFontSize = [float](Get-StyleDouble $style 'gpuFontSize' $cpuFontSize)
    $spotifyArtistFontSize = [float](Get-StyleDouble $style 'spotifyArtistFontSize' 14)
    $spotifyTrackFontSize = [float](Get-StyleDouble $style 'spotifyTrackFontSize' 14)

    $sectionGap = Get-StyleInt $style 'sectionGap' 4
    $labelToBarGap = Get-StyleInt $style 'labelToBarGap' 4
    $clockBottomGap = Get-StyleInt $style 'clockBottomGap' 4
    $ramToSpotifyGap = Get-StyleInt $style 'ramToSpotifyGap' 7
    $spotifyLineHeightMul = Get-StyleDouble $style 'spotifyLineHeight' 1.0

    $bgBlurPct = Get-StyleDouble $style 'backgroundBlurPct' 0
    $bgOverlayPct = Get-StyleDouble $style 'backgroundOverlayPct' 43
    $bgOverlayAlpha = Convert-PercentToAlpha $bgOverlayPct

    $bgPath = ''
    if (Get-Variable -Name BACKGROUND_IMAGE -Scope Script -ErrorAction SilentlyContinue) {
        $bgPath = [string]$Script:BACKGROUND_IMAGE
    }

    $bgDrawn = Draw-BackgroundImage -g $g -path $bgPath -canvasW $W -canvasH $H -blurPct $bgBlurPct
    if (-not $bgDrawn) {
        $g.Clear($bgColor)
    } else {
        $overlay = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($bgOverlayAlpha, 0, 0, 0))
        $g.FillRectangle($overlay, 0, 0, $W, $H)
        $overlay.Dispose()
    }

    $fontClock = New-Object System.Drawing.Font($fontFamily, $clockFontSize, [System.Drawing.FontStyle]::Bold)
    $fontCpu = New-Object System.Drawing.Font($fontFamily, $cpuFontSize, [System.Drawing.FontStyle]::Regular)
    $fontRam = New-Object System.Drawing.Font($fontFamily, $ramFontSize, [System.Drawing.FontStyle]::Regular)
    $fontGpu = New-Object System.Drawing.Font($fontFamily, $gpuFontSize, [System.Drawing.FontStyle]::Regular)
    $fontNow = New-Object System.Drawing.Font($fontFamily, $spotifyTrackFontSize, [System.Drawing.FontStyle]::Regular)
    $fontNowBold = New-Object System.Drawing.Font($fontFamily, $spotifyArtistFontSize, [System.Drawing.FontStyle]::Bold)

    $cpuTextBrush = New-Object System.Drawing.SolidBrush $cpuTextColor
    $ramTextBrush = New-Object System.Drawing.SolidBrush $ramTextColor
    $gpuTextBrush = New-Object System.Drawing.SolidBrush $gpuTextColor
    $spotifyTextBrush = New-Object System.Drawing.SolidBrush $spotifyTextColor

    try {
        $timeStr = Get-Date -Format 'HH:mm'
        $clockY = 4
        $clockStyle = 'sevenseg'
        if (Get-Variable -Name CLOCK_STYLE -Scope Script -ErrorAction SilentlyContinue) {
            $clockStyle = ([string]$Script:CLOCK_STYLE).Trim().ToLowerInvariant()
        }
        switch ($clockStyle) {
            'classic' {
                $clockBottom = Draw-ClassicClock -g $g -timeStr $timeStr -canvasW $W -topY $clockY -fontClock $fontClock -textColor $clockTextColor -bgColor $clockBgColor
            }
            'classic_plain' {
                $clockBottom = Draw-ClassicPlainClock -g $g -timeStr $timeStr -canvasW $W -topY $clockY -fontClock $fontClock -textColor $clockTextColor
            }
            default {
                $clockScale = [double]($clockFontSize / 28.0)
                $clockBottom = Draw-SevenSegClock -g $g -timeStr $timeStr -canvasW $W -topY $clockY -scale $clockScale -onColor $clockTextColor -offColor $clockOffColor -dayColor $clockDayColor
            }
        }
        $cpuY = $clockBottom + $clockBottomGap
        $left = 10
        $barX = $left
        $barW = 220
        $barH = 12

        $cpuPct = Get-CPUUsage
        $cpuTemp = Get-CPUTemp
        $mem = Get-MemInfo

        $deg = [char]176
        if ($cpuTemp -ne $null) { $cpuText = ("CPU: {0}% / {1}{2}C" -f $cpuPct, $cpuTemp, $deg) } else { $cpuText = ("CPU: {0}%" -f $cpuPct) }
        $g.DrawString($cpuText, $fontCpu, $cpuTextBrush, $left, $cpuY)
        $cpuLabelH = [int][math]::Ceiling($g.MeasureString('Ag', $fontCpu).Height)
        $cpuBarY = $cpuY + $cpuLabelH + $labelToBarGap
        Draw-UniformBar -g $g -x $barX -y $cpuBarY -w $barW -h $barH -pct $cpuPct -fillColor $cpuBarColor -bgBrush $barBgBrush

        $ramY = $cpuBarY + $barH + $sectionGap
        $usedGB = [math]::Round(($mem.UsedMB / 1024.0), 1)
        $totalGB = [math]::Round(($mem.TotalMB / 1024.0), 1)
        $usedGBText = ('{0:N1}' -f $usedGB).Replace('.', ',')
        $totalGBText = ('{0:N1}' -f $totalGB).Replace('.', ',')
        $ramText = ("RAM: {0} / {1} GB" -f $usedGBText, $totalGBText)
        $g.DrawString($ramText, $fontRam, $ramTextBrush, $left, $ramY)
        $ramLabelH = [int][math]::Ceiling($g.MeasureString('Ag', $fontRam).Height)
        $ramBarY = $ramY + $ramLabelH + $labelToBarGap
        Draw-UniformBar -g $g -x $barX -y $ramBarY -w $barW -h $barH -pct $mem.UsedPct -fillColor $ramBarColor -bgBrush $barBgBrush

        $blockY = $ramBarY + $barH + $ramToSpotifyGap
        $now = Get-NowPlaying

        if ($now.text -and $now.text.Trim() -ne '') {
            $bx = 10; $by = $blockY; $bw = 220; $bh = 86; $radius = 16; $r2 = $radius * 2
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            if ($r2 -gt $bw -or $r2 -gt $bh) {
                $bgBrush = New-Object System.Drawing.SolidBrush $spotifyBgColor
                $g.FillRectangle($bgBrush, $bx, $by, $bw, $bh)
                $bgBrush.Dispose()
            } else {
                $path.AddArc($bx, $by, $r2, $r2, 180, 90)
                $path.AddArc($bx + $bw - $r2, $by, $r2, $r2, 270, 90)
                $path.AddArc($bx + $bw - $r2, $by + $bh - $r2, $r2, $r2, 0, 90)
                $path.AddArc($bx, $by + $bh - $r2, $r2, $r2, 90, 90)
                $path.CloseFigure()
                $bgBrush = New-Object System.Drawing.SolidBrush $spotifyBgColor
                $g.FillPath($bgBrush, $path)
                $bgBrush.Dispose()
            }

            $albumImg = $null
            if ($spotifyShowImage -and $now.albumImageUrl) { $albumImg = Fetch-ImageFromUrlWithCache $now.albumImageUrl }
            $imgPad = 8; $imgSize = 64
            if ($albumImg) {
                try {
                    $destRect = New-Object System.Drawing.Rectangle -ArgumentList @([int]($bx + $imgPad), [int]($by + $imgPad), [int]$imgSize, [int]$imgSize)
                    $oldClip = $g.Clip
                    $clipPath = New-Object System.Drawing.Drawing2D.GraphicsPath
                    $clipPath.AddEllipse($destRect)
                    $g.SetClip($clipPath)
                    $g.DrawImage($albumImg, $destRect)
                    $g.Clip = $oldClip
                    $clipPath.Dispose()
                    $albumImg.Dispose()
                } catch { Write-DebugLine ("DrawImage: error {0}" -f $_.ToString()) }
            } else {
                if ($spotifyShowImage) {
                    $g.FillEllipse([System.Drawing.Brushes]::White, $bx + $imgPad, $by + $imgPad, $imgSize, $imgSize)
                    $g.DrawEllipse([System.Drawing.Pens]::Gray, $bx + $imgPad, $by + $imgPad, $imgSize, $imgSize)
                }
            }

            $textX = if ($spotifyShowImage) { $bx + $imgPad + $imgSize + 10 } else { $bx + 12 }
            $textW = $bw - ($textX - $bx) - 12
            $padY = 10
            $nowText = $now.text
            $lineGap = [int][math]::Round([math]::Max(0.0, ($spotifyLineHeightMul - 1.0) * 10.0))
            $parts = $nowText -split '\s-\s', 2
            $line1 = ''
            $line2 = ''
            if ($parts.Count -ge 2) {
                $line1 = Ellipsize $g $fontNowBold $parts[0].Trim() $textW
                $line2 = Ellipsize $g $fontNow $parts[1].Trim() $textW
            } else {
                $line1 = Ellipsize $g $fontNowBold $nowText.Trim() $textW
            }
            $sy = $by + $padY
            $line1H = [int][math]::Ceiling($g.MeasureString("Ag", $fontNowBold).Height)
            if ($line1) { $g.DrawString($line1, $fontNowBold, $spotifyTextBrush, $textX, $sy) }
            if ($line2) { $g.DrawString($line2, $fontNow, $spotifyTextBrush, $textX, $sy + $line1H + $lineGap) }
            if ($path) { $path.Dispose() }
        } else {
            $gpuLoad = Get-GPULoad
            $gpuTemp = Get-GPUTemp
            $gpuY = $blockY
            if ($gpuTemp) { $g.DrawString(("GPU: {0}% / {1}{2}C" -f $gpuLoad, $gpuTemp, $deg), $fontGpu, $gpuTextBrush, $left, $gpuY) } else { $g.DrawString(("GPU: {0}%" -f $gpuLoad), $fontGpu, $gpuTextBrush, $left, $gpuY) }
            $gpuLabelH = [int][math]::Ceiling($g.MeasureString('Ag', $fontGpu).Height)
            $gpuBarY = $gpuY + $gpuLabelH + $labelToBarGap
            Draw-UniformBar -g $g -x $barX -y $gpuBarY -w $barW -h $barH -pct $gpuLoad -fillColor $gpuBarColor -bgBrush $barBgBrush
        }

        $tmp = [System.IO.Path]::Combine($env:TEMP, 'frame_tmp.jpg')
        $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
        $eps = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $eps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, 90L)
        $bmp.Save($tmp, $enc, $eps)
        $dest = Join-Path $pathDir $outFileName
        Move-Item -Force -Path $tmp -Destination $dest
        Write-DebugLine (("Render: saved {0}" -f $dest))
    }
    finally {
        $g.Dispose(); $bmp.Dispose()
        $fontClock.Dispose(); $fontCpu.Dispose(); $fontRam.Dispose(); $fontGpu.Dispose(); $fontNow.Dispose(); $fontNowBold.Dispose()
        $cpuTextBrush.Dispose(); $ramTextBrush.Dispose(); $gpuTextBrush.Dispose(); $spotifyTextBrush.Dispose()
        $barBgBrush.Dispose()
    }
}

if ($PSModuleRoot) { Export-ModuleMember -Function Render-Frame -ErrorAction SilentlyContinue }
