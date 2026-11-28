<#
.SYNOPSIS
Upscale an animation or video (gif, mp4, webm, avif, webp, apng, mkv, mov...) with Upscayl
and save it as gif, mp4, webm or avif.

.DESCRIPTION
Windows version of upscale-gif. Anything not given on the command line is asked for in a
settings window. Frames are upscaled by the model (2x/3x/4x), then downsampled to the
chosen size (-d: lanczos, spline, bicubic or area). Every frame keeps its original timing; audio is kept for mp4/webm.
The "nearest" model is nearest-neighbour scaling for pixel art (no AI, no GPU needed).

Requirements: Windows PowerShell 5.1 or PowerShell 7, ffmpeg/ffprobe 7+ (8+ for animated
WebP input) and Upscayl. Both are found automatically; set UPSCAYL_BIN (path to
upscayl-bin.exe) and UPSCAYL_MODELS for another Upscayl install, or put ffmpeg.exe and
ffprobe.exe next to this script. Custom models come from the folder chosen in Upscayl
(Settings > Custom models folder), or from UPSCAYL_CUSTOM_MODELS. The GPU is -g, else
Upscayl's GPU ID setting, else auto. Temporary frames go to %TEMP%, or UPSCALE_GIF_TEMP.
#>
param(
    [Parameter(Position = 0)] [string]$Path,
    [Alias('m')] [string]$Model,
    [Alias('w')] [string]$Width,
    [string]$Height,
    [Alias('f')] [string]$Format,
    [Alias('g')] [string]$Gpu,
    [Alias('o')] [string]$Output,
    [Alias('q')] [string]$Quality,
    [Alias('d')] [string]$Downsampler,
    [Alias('c')] [switch]$Check,
    [Alias('h')] [switch]$Help,
    # Report errors and completion in message boxes (used by the shortcuts)
    [switch]$Dialogs,
    [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Extra
)

$ErrorActionPreference = 'Stop'
$Inv = [Globalization.CultureInfo]::InvariantCulture
$OnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$Title = 'Upscale GIF'
$Usage = @'
Usage: upscale-gif.ps1 [-m model] [-w width | -Height height] [-f format] [-q quality%]
                      [-d downsampler] [-g gpu] [-o output] [file]
       upscale-gif.ps1 -c    (show detected tools, models and GPUs)
Anything not given on the command line is asked for in a settings window. Formats: gif, webp,
mp4, webm, avif, and for single images png, jpg. -q: 1-100 (default 80; ignored for png).
Frames are upscaled by the model, then downsampled to the chosen size with -d: lanczos
(default), spline, bicubic or area. Every frame keeps its original timing, and audio is kept
for mp4/webm output. -m nearest is nearest-neighbour scaling for pixel art: no AI and no
GPU, whole multiples (2x, 3x...) of the size.
'@

$Desc = @{
    'upscayl-standard-4x' = 'General purpose'
    'upscayl-lite-4x' = 'General purpose, faster'
    'digital-art-4x' = 'Digital art, anime, cartoons'
    'high-fidelity-4x' = 'Photos, keeps fine detail'
    'realesr-animevideov3-x4' = 'Anime and cartoon video, fastest'
    'realesr-animevideov3-x3' = 'Anime and cartoon video, fastest, 3x'
    'realesr-animevideov3-x2' = 'Anime and cartoon video, fastest, 2x'
    'RealESRGAN_General_WDN_x4_v3' = 'General purpose, fast, less smoothing'
    '4x_NMKD-Siax_200k' = 'General purpose, clean or lightly compressed'
    '4xLSDIR' = 'Photos, clean sources'
    '4xLSDIRplusC' = 'Photos with JPEG artifacts'
    '4xLSDIRCompactC3' = 'Photos with JPEG artifacts, fast'
    '4xNomos8kSC' = 'Photos with JPEG artifacts or blur'
    '4x_NMKD-Superscale-SP_178000_G' = 'Photos with noise and artifacts'
    'remacri-4x' = 'Natural and sharp (non-commercial use only)'
    'ultrasharp-4x' = 'Very sharp (non-commercial use only)'
    'ultramix-balanced-4x' = 'Balance of sharp and smooth (non-commercial use only)'
    'uniscale_restore' = 'Heavily compressed or noisy images (non-commercial use only)'
    'realesrgan-x4plus' = 'General purpose'
    'RealESRGAN_General_x4_v3' = 'General purpose, faster'
    'realesrgan-x4plus-anime' = 'Digital art, anime, cartoons'
    '4xHFA2k' = 'Photos, keeps fine detail'
}
# Order of the model list, and the default (the first one available)
$ModelOrder = 'upscayl-standard-4x', 'upscayl-lite-4x', 'digital-art-4x', 'high-fidelity-4x',
    'realesr-animevideov3-x4', 'realesr-animevideov3-x3', 'realesr-animevideov3-x2',
    'RealESRGAN_General_WDN_x4_v3', '4x_NMKD-Siax_200k', '4xLSDIR', '4xLSDIRplusC',
    '4xLSDIRCompactC3', '4xNomos8kSC', '4x_NMKD-Superscale-SP_178000_G', 'remacri-4x',
    'ultrasharp-4x', 'ultramix-balanced-4x', 'uniscale_restore', 'realesrgan-x4plus',
    'RealESRGAN_General_x4_v3', 'realesrgan-x4plus-anime', '4xHFA2k'
# Not an AI model: plain nearest-neighbour scaling, which keeps pixel art's hard edges
$Nearest = 'nearest'
$NearestDesc = 'Pixel art: nearest neighbour, sharp square pixels (no AI, no GPU needed)'
# Release packages carry upscayl-bin, ffmpeg and ffprobe in bin\ and the models in models\
$BundleBin = Join-Path $PSScriptRoot 'bin'
$FmtDesc = @{
    gif = 'GIF'; webm = 'WebM (VP9, keeps transparency and audio)'
    avif = 'AVIF (AV1, keeps transparency)'; mp4 = 'MP4 (H.264, keeps audio, no transparency)'
    png = 'PNG (lossless, keeps transparency)'; jpg = 'JPEG (small, no transparency)'; webp = 'WebP (keeps transparency)'
}
$Encoder = @{ gif = 'gif'; mp4 = 'libx264'; webm = 'libvpx-vp9'; avif = 'libaom-av1'; png = 'png'; jpg = 'mjpeg'; webp = 'libwebp' }
$AnimFormats = 'gif', 'webp', 'webm', 'avif', 'mp4'
$ImageFormats = 'png', 'jpg', 'webp', 'avif', 'gif'   # offered when the input is a single image
$Qualities = 100, 95, 90, 85, 80, 75, 70, 60, 50, 40, 30, 20, 10
# ffmpeg filters for resizing the model's output to the chosen size
$Downsamplers = 'lanczos', 'spline', 'bicubic', 'area'
$DownsamplerDesc = @{
    lanczos = 'Sharpest (default)'
    spline = 'Sharp, fewer halos around edges'
    bicubic = 'Softer, smooth'
    area = 'Pixel averaging, no halos; softest, good for big reductions'
}

# --- Helpers ---------------------------------------------------------------------------
# %APPDATA% (on Linux, ~/.config, which .NET reports as "" until it exists)
function Get-AppData {
    $d = [Environment]::GetFolderPath('ApplicationData', 'Create')
    if (-not $d) { $d = Join-Path $HOME '.config' }
    $d
}
function Fail([string]$Message) { throw (New-Object Management.Automation.RuntimeException $Message) }
function Num([double]$X, [string]$Fmt = 'F6') { $X.ToString($Fmt, $Inv) }
function ToNum([string]$S) {
    $v = 0.0
    if ([double]::TryParse($S, [Globalization.NumberStyles]::Float, $Inv, [ref]$v)) { return $v }
    return $null
}
function Even([double]$N) { [long](2 * [math]::Floor(($N + 1) / 2)) }
function Human([double]$Bytes) {
    $units = 'B', 'KB', 'MB', 'GB', 'TB'; $i = 0
    while ($Bytes -ge 1024 -and $i -lt 4) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return "$Bytes B" }
    (Num $Bytes $(if ($Bytes -lt 10) { '0.0' } else { '0' })) + $units[$i]
}

# Quote one argument the way Windows programs (and .NET) split a command line
function Format-Arg([string]$A) {
    if ($A -ne '' -and $A -notmatch '[\s"]') { return $A }
    '"' + ($A -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}
# Run a program. -Capture returns its output; -Log saves it to a file; otherwise it
# writes straight to the console. -Watch (see New-Watch) updates the progress while it
# runs, and stops it when Cancel is pressed.
function Invoke-Tool {
    param([string]$Exe, [string[]]$Arguments, [switch]$Capture, [string]$Log, [int]$TimeoutSec = 0, [hashtable]$Watch)
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe
    $psi.Arguments = ($Arguments | ForEach-Object { Format-Arg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $redirect = $Capture -or $Log
    if ($redirect) {
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    }
    $p = [Diagnostics.Process]::Start($psi)
    $out = ''; $err = ''
    if ($redirect) {
        $errTask = $p.StandardError.ReadToEndAsync()
        $outTask = $p.StandardOutput.ReadToEndAsync()
    }
    if ($Watch) {
        $next = [DateTime]::MinValue
        try {
            while (-not $p.WaitForExit(100)) {
                if ($script:ProgressWindow) { [Windows.Forms.Application]::DoEvents() }
                if ($script:Cancelled) { Fail 'cancelled' }
                if ([DateTime]::UtcNow -ge $next) { Update-Watch $Watch; $next = [DateTime]::UtcNow.AddMilliseconds(500) }
            }
        } finally {
            if (-not $p.HasExited) { try { $p.Kill() } catch { }; $p.WaitForExit() }
        }
        $p.WaitForExit()
    } else {
        $ms = if ($TimeoutSec -gt 0) { $TimeoutSec * 1000 } else { -1 }
        if (-not $p.WaitForExit($ms)) { try { $p.Kill() } catch { }; $p.WaitForExit() }
    }
    if ($redirect) { $out = $outTask.Result; $err = $errTask.Result }
    if ($Log) { [IO.File]::WriteAllText($Log, $out + $err) }
    New-Object PSObject -Property @{ Code = $p.ExitCode; Out = $out; Err = $err }
}
function Lines([string]$Text) { @($Text -split "`r?`n" | Where-Object { $_ -ne '' }) }

# --- Windows dialogs ------------------------------------------------------------------
$script:FormsLoaded = $false
function Use-Forms {
    if ($script:FormsLoaded) { return }
    if (-not $OnWindows) { Fail 'missing -m/-f/-w options (the settings window needs Windows)' }
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:FormsLoaded = $true
}
# Dialogs are owned by an invisible topmost window so they don't open behind the console
function New-Owner {
    Use-Forms
    $o = New-Object Windows.Forms.Form
    $o.TopMost = $true; $o.ShowInTaskbar = $false; $o.Opacity = 0
    $o.StartPosition = 'Manual'; $o.Location = New-Object Drawing.Point(-2000, -2000)
    $o.Show(); $o
}
function Show-Message([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK') {
    $o = New-Owner
    try { [Windows.Forms.MessageBox]::Show($o, $Text, $Title, $Buttons, $Icon) } finally { $o.Dispose() }
}
function Select-InputFile([string]$Dir) {
    Use-Forms
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Title = 'Choose an image, animation or video to upscale'
    $d.Filter = 'Images, animations and videos|*.gif;*.webp;*.png;*.apng;*.avif;*.mp4;*.m4v;*.webm;*.mkv;*.mov;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff|All files|*.*'
    if ($Dir -and (Test-Path -LiteralPath $Dir -PathType Container)) { $d.InitialDirectory = $Dir }
    $o = New-Owner
    try { if ($d.ShowDialog($o) -eq 'OK') { return $d.FileName } } finally { $o.Dispose() }
    return $null
}
# Fields: @{ Label = '...'; Items = @(...) } for a list (returns the chosen index), or
# @{ Label = '...' } for a text box (returns its text); an optional Tip adds a tooltip.
# Returns $null when cancelled.
function Show-Settings([string]$Info, [object[]]$Fields) {
    Use-Forms
    $form = New-Object Windows.Forms.Form
    $form.Text = $Title; $form.FormBorderStyle = 'FixedDialog'; $form.StartPosition = 'CenterScreen'
    $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.TopMost = $true
    $form.AutoSize = $true; $form.AutoSizeMode = 'GrowAndShrink'
    $form.Padding = New-Object Windows.Forms.Padding 10
    $form.Font = New-Object Drawing.Font('Segoe UI', 9)
    $table = New-Object Windows.Forms.TableLayoutPanel
    $table.AutoSize = $true; $table.AutoSizeMode = 'GrowAndShrink'; $table.ColumnCount = 2
    $label = New-Object Windows.Forms.Label
    $label.Text = $Info; $label.AutoSize = $true; $label.MaximumSize = New-Object Drawing.Size(520, 0)
    $label.Margin = New-Object Windows.Forms.Padding(3, 3, 3, 12)
    $table.Controls.Add($label, 0, 0); $table.SetColumnSpan($label, 2)
    $row = 1
    $controls = New-Object Collections.Generic.List[object]
    foreach ($f in $Fields) {
        $l = New-Object Windows.Forms.Label
        $l.Text = $f.Label; $l.AutoSize = $true; $l.Anchor = 'Left'
        if ($f.ContainsKey('Items')) {
            $c = New-Object Windows.Forms.ComboBox
            $c.DropDownStyle = 'DropDownList'; $c.MaxDropDownItems = 15
            foreach ($item in $f.Items) { [void]$c.Items.Add($item) }
            $c.SelectedIndex = 0
        } else {
            $c = New-Object Windows.Forms.TextBox
        }
        $c.Width = 340
        if ($f.ContainsKey('Tip')) {
            $tip = New-Object Windows.Forms.ToolTip
            $tip.AutoPopDelay = 20000
            $tip.SetToolTip($l, $f.Tip); $tip.SetToolTip($c, $f.Tip)
        }
        $table.Controls.Add($l, 0, $row); $table.Controls.Add($c, 1, $row)
        $controls.Add($c); $row++
    }
    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.FlowDirection = 'RightToLeft'; $buttons.AutoSize = $true; $buttons.Dock = 'Fill'
    $buttons.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 0)
    $ok = New-Object Windows.Forms.Button; $ok.Text = 'Upscale'; $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.DialogResult = 'Cancel'
    $buttons.Controls.Add($cancel); $buttons.Controls.Add($ok)
    $table.Controls.Add($buttons, 0, $row); $table.SetColumnSpan($buttons, 2)
    $form.Controls.Add($table); $form.AcceptButton = $ok; $form.CancelButton = $cancel
    try {
        if ($form.ShowDialog() -ne 'OK') { return $null }
        $answers = New-Object Collections.Generic.List[object]
        foreach ($c in $controls) {
            if ($c -is [Windows.Forms.ComboBox]) { $answers.Add($c.SelectedIndex) } else { $answers.Add($c.Text) }
        }
        return , $answers.ToArray()
    } finally { $form.Dispose() }
}

# --- Progress ----------------------------------------------------------------------------
# Upscayl only reports progress per image, so progress comes from counting finished frames.
# It is shown in a window with a Cancel button when started from the shortcuts (-Dialogs),
# and with PowerShell's progress bar otherwise.
$script:ProgressWindow = $null
$script:Cancelled = $false
$script:ProgressShown = ''
$script:UpClock = $null
function Open-ProgressWindow([string]$Name) {
    Use-Forms
    $f = New-Object Windows.Forms.Form
    $f.Text = $Title; $f.FormBorderStyle = 'FixedDialog'; $f.StartPosition = 'CenterScreen'
    $f.MaximizeBox = $false; $f.MinimizeBox = $true; $f.ClientSize = New-Object Drawing.Size(440, 132)
    $f.Font = New-Object Drawing.Font('Segoe UI', 9)
    $file = New-Object Windows.Forms.Label
    $file.Text = $Name; $file.AutoEllipsis = $true; $file.UseMnemonic = $false
    $file.Location = New-Object Drawing.Point(12, 12); $file.Size = New-Object Drawing.Size(416, 18)
    $status = New-Object Windows.Forms.Label
    $status.Text = 'Starting...'; $status.UseMnemonic = $false
    $status.Location = New-Object Drawing.Point(12, 34); $status.Size = New-Object Drawing.Size(416, 18)
    $bar = New-Object Windows.Forms.ProgressBar
    $bar.Location = New-Object Drawing.Point(12, 58); $bar.Size = New-Object Drawing.Size(416, 22); $bar.Maximum = 100
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.Location = New-Object Drawing.Point(353, 94)
    $cancel.Add_Click({ $script:Cancelled = $true })
    # Closing the window also cancels, unless the script closes it
    $f.Add_FormClosing({ param($s, $e) if (-not $script:ProgressWindow.Done) { $script:Cancelled = $true; $e.Cancel = $true } })
    $f.Controls.AddRange(@($file, $status, $bar, $cancel))
    $script:ProgressWindow = @{ Form = $f; Bar = $bar; Status = $status; Done = $false }
    $f.Show(); [Windows.Forms.Application]::DoEvents()
}
function Close-Progress {
    if ($script:ProgressWindow) {
        $script:ProgressWindow.Done = $true
        $script:ProgressWindow.Form.Close(); $script:ProgressWindow.Form.Dispose()
        $script:ProgressWindow = $null
    } else {
        Write-Progress -Activity $Title -Completed
    }
}
function Format-Time([long]$Sec) {
    if ($Sec -ge 3600) { return '{0}:{1:D2}:{2:D2}' -f [long][math]::Floor($Sec / 3600), [long]([math]::Floor($Sec / 60) % 60), ($Sec % 60) }
    '{0}:{1:D2}' -f [long][math]::Floor($Sec / 60), ($Sec % 60)
}
# $Eta estimates the time left from the upscaling speed (it starts at 3% and takes most of the time)
function Show-Progress([int]$Percent, [string]$Text, [bool]$Eta) {
    if ($Percent -gt 99) { $Percent = 99 }
    $left = ''
    if ($Eta -and $script:UpClock -and $Percent -gt 4 -and $script:UpClock.Elapsed.TotalSeconds -ge 3) {
        $left = 'about ' + (Format-Time ([long]($script:UpClock.Elapsed.TotalSeconds * (100 - $Percent) / ($Percent - 3)) + 1)) + ' left'
    }
    $key = "$Percent $Text $left"
    if ($key -eq $script:ProgressShown) { return }
    $script:ProgressShown = $key
    if ($script:ProgressWindow) {
        $script:ProgressWindow.Bar.Value = $Percent
        $script:ProgressWindow.Status.Text = $(if ($left) { "$Text - $left" } else { $Text })
        [Windows.Forms.Application]::DoEvents()
    } else {
        Write-Progress -Activity $Title -Status $(if ($left) { "$Text, $left" } else { $Text }) -PercentComplete $Percent
    }
}
# Maps a count of finished frames (files in Dir, or ffmpeg's frame= lines in ProgressFile)
# onto From..To percent. Eta: 'eta', 'eta-started' (once the count moves) or ''.
function New-Watch([int]$From, [int]$To, [string]$Text, [long]$Total, [string]$Dir, [string]$ProgressFile, [string]$Eta = '') {
    @{ From = $From; To = $To; Text = $Text; Total = [math]::Max($Total, 1); Dir = $Dir; ProgressFile = $ProgressFile; Eta = $Eta }
}
function Update-Watch([hashtable]$W) {
    $n = 0L
    try {
        if ($W.Dir) { $n = @([IO.Directory]::GetFiles($W.Dir)).Count }
        elseif (Test-Path -LiteralPath $W.ProgressFile) {
            $fs = New-Object IO.FileStream($W.ProgressFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $sr = New-Object IO.StreamReader($fs)
            try { $m = [regex]::Matches($sr.ReadToEnd(), '(?m)^frame=(\d+)') } finally { $sr.Dispose() }
            if ($m.Count) { $n = [long]$m[$m.Count - 1].Groups[1].Value }
        }
    } catch { }
    if ($n -gt $W.Total) { $n = $W.Total }
    $eta = $W.Eta -eq 'eta' -or ($W.Eta -eq 'eta-started' -and $n -gt 0)
    Show-Progress ([int]($W.From + ($W.To - $W.From) * $n / $W.Total)) ($W.Text -f $n, $W.Total) $eta
}

# --- Locate ffmpeg ---------------------------------------------------------------------
function Find-Program([string]$Name, [string[]]$Dirs) {
    foreach ($d in $Dirs) {
        if (-not $d) { continue }
        foreach ($n in "$Name.exe", $Name) {
            $p = Join-Path $d $n
            if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).ProviderPath }
        }
    }
    $c = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}
function Find-FFmpeg {
    $dirs = @($BundleBin, $PSScriptRoot)
    if ($OnWindows) {
        $dirs += "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
        $dirs += @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*FFmpeg*\*\bin" -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | ForEach-Object { $_.FullName })
        $dirs += "$env:USERPROFILE\scoop\shims", "$env:ProgramData\chocolatey\bin", "$env:SystemDrive\ffmpeg\bin",
            "$env:ProgramFiles\ffmpeg\bin"
    }
    $ff = Find-Program 'ffmpeg' $dirs
    if (-not $ff) { return $null, $null }
    $probe = Find-Program 'ffprobe' (@(Split-Path $ff) + $dirs)
    return $ff, $probe
}

# --- Locate Upscayl --------------------------------------------------------------------
# upscayl-bin is Upscayl's command-line upscaler; its -z (model scale) option tells it
# apart from other Real-ESRGAN builds with a similar interface.
function Test-Upscayl([string]$Exe) {
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }
    if ((Split-Path $Exe -Leaf) -eq 'Upscayl.exe') { return $false }   # the app itself
    $r = Invoke-Tool $Exe @('-h') -Capture -TimeoutSec 10
    return ($r.Out + $r.Err) -like '*-z model-scale*'
}
function Get-UpscaylInstallDirs {
    if (-not $OnWindows) { return @() }
    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $dirs = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'Upscayl*' -and $_.PSObject.Properties['InstallLocation'] } |
        ForEach-Object { $_.InstallLocation.Trim('"') })
    $dirs + @("$env:ProgramFiles\Upscayl", "$env:LOCALAPPDATA\Programs\Upscayl", "${env:ProgramFiles(x86)}\Upscayl",
        "$env:USERPROFILE\scoop\apps\upscayl\current")
}
# The bundled upscayl-bin comes first, unless -Installed is given
function Find-Upscayl([switch]$Installed) {
    if ($env:UPSCAYL_BIN -and -not $Installed) {
        if (Test-Upscayl $env:UPSCAYL_BIN) { return (Resolve-Path -LiteralPath $env:UPSCAYL_BIN).ProviderPath }
        return $null
    }
    $candidates = @()
    if (-not $Installed) {
        $candidates += (Join-Path $BundleBin 'upscayl-bin.exe'), (Join-Path $BundleBin 'upscayl-bin')
        # Report a missing vulkan-1.dll through the exit code instead of a Windows error box
        if ($OnWindows -and -not ('UpscaleGif.ErrorMode' -as [type])) {
            try {
                Add-Type -Namespace UpscaleGif -Name ErrorMode -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);'
                [void][UpscaleGif.ErrorMode]::SetErrorMode(1)   # SEM_FAILCRITICALERRORS, inherited by child processes
            } catch { }
        }
    }
    $candidates += @(Get-Command upscayl-bin, upscayl-ncnn -CommandType Application -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Source })
    $candidates += @(Get-UpscaylInstallDirs | Where-Object { $_ } | ForEach-Object { Join-Path $_ 'resources\bin\upscayl-bin.exe' })
    foreach ($c in $candidates) { if (Test-Upscayl $c) { return (Resolve-Path -LiteralPath $c).ProviderPath } }
    return $null
}
# Models live beside the binary in every Upscayl layout (bin\ and models\ share a parent)
function Find-Models([string]$Exe) {
    if ($env:UPSCAYL_MODELS) { return $env:UPSCAYL_MODELS }
    $base = Split-Path $Exe
    foreach ($d in (Join-Path $base '../models'), (Join-Path $base 'models'), (Join-Path $base '../resources/models')) {
        if (@(Get-ChildItem -LiteralPath $d -Filter '*.param' -File -ErrorAction SilentlyContinue).Count) {
            return (Resolve-Path -LiteralPath $d).ProviderPath
        }
    }
    return $null
}

# --- Upscayl's own settings --------------------------------------------------------------
# The Upscayl app keeps its settings in Chromium localStorage, a LevelDB database whose
# table files are snappy-compressed. Read() returns the newest value of each requested key
# across the write-ahead log and table files ("" if unset). C# 5, for Windows PowerShell.
# Finds the pixel grid of pixel art that was already enlarged by 2.2x or more, possibly by
# an uneven factor such as 3.5x (pixels then alternate between 3 and 4 wide, with blurred
# edges). The colour change between neighbouring columns and rows peaks on the grid lines,
# so the grid is the strongest repeating pattern in those changes (a Fourier scan).
$PixelGridCode = @'
using System;
public static class UpscaleGifPixelGrid {
    // rgb: frames of w x h RGB24. Returns { sizeX, sizeY, offsetX, offsetY } or null.
    public static double[] Detect(byte[] rgb, int w, int h) {
        int frame = w * h * 3, frames = rgb.Length / frame;
        if (frames == 0 || w < 8 || h < 8) return null;
        double[] ex = new double[w], ey = new double[h];
        for (int f = 0; f < frames; f++) {
            int b = f * frame;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int i = b + (y * w + x) * 3;
                    if (x > 0) ex[x] += Math.Abs(rgb[i] - rgb[i - 3]) + Math.Abs(rgb[i + 1] - rgb[i - 2]) + Math.Abs(rgb[i + 2] - rgb[i - 1]);
                    if (y > 0) { int j = i - w * 3; ey[y] += Math.Abs(rgb[i] - rgb[j]) + Math.Abs(rgb[i + 1] - rgb[j + 1]) + Math.Abs(rgb[i + 2] - rgb[j + 2]); }
                }
            }
        }
        double[] gx = Grid(ex, 220, 1600), gy = Grid(ey, 220, 1600);
        if (gx == null || gy == null || gx[1] < 0.3 || gy[1] < 0.3 || Math.Abs(gx[0] - gy[0]) > 0.05 * gx[0]) return null;
        return new double[] { gx[0], gy[0], gx[2], gy[2] };
    }
    // { size, strength, offset } of the strongest grid of lo/100 to hi/100 px in an edge profile
    public static double[] Grid(double[] e, int lo, int hi) {
        int n = e.Length; double tot = 0;
        for (int i = 1; i < n; i++) tot += e[i];
        if (tot == 0) return null;
        double[] s = new double[hi + 1]; double best = 0; int bp = 0;
        for (int p = lo; p <= hi; p++) {
            s[p] = Strength(e, p / 100.0, 0, tot)[0];
            if (s[p] > best) { best = s[p]; bp = p; }
        }
        // A grid of size P also shows at P/2, P/3: prefer a multiple that is nearly as strong
        for (int k = 2; k * bp <= hi; k++) if (s[k * bp] >= 0.9 * best) { bp = k * bp; best = s[bp]; }
        // Refine to 0.001 px (0.01 adds up to a pixel across the picture), measuring the offset
        // from the middle, where an error in the size matters least
        int c = n / 2; double fine = 0, fp = 0, fph = 0;
        for (int p = bp * 10 - 10; p <= bp * 10 + 10; p++) {
            double[] r = Strength(e, p / 1000.0, c, tot);
            if (r[0] > fine) { fine = r[0]; fp = p / 1000.0; fph = r[1] + c; }
        }
        double off = fph - Math.Floor(fph / fp) * fp;
        return new double[] { fp, fine, off };
    }
    static double[] Strength(double[] e, double P, int c, double tot) {
        double re = 0, im = 0;
        for (int i = 1; i < e.Length; i++) { double a = 2 * Math.PI * (i - c) / P; re += e[i] * Math.Cos(a); im += e[i] * Math.Sin(a); }
        return new double[] { Math.Sqrt(re * re + im * im) / tot, Math.Atan2(im, re) / (2 * Math.PI) * P };
    }
}
// Restores enlarged pixel art to its original pixels (the same as the Linux version). Each
// grid cell becomes one pixel: the colour most common in the cell's middle (away from its
// edges, where the enlargement blurred the colours), with nearly identical colours counted as
// one. Some animations also have a layer on a grid of its own, such as text added at another
// size: Learn finds it from the cells the main grid explains badly, and where it fits clearly
// better it is restored on that grid as a second layer. Frames stream from one ffmpeg to
// others on a background thread.
public class UpscaleGifGridRestore {
    int w, h, bw, bh; double P, Q, fx, fy;
    int[] cx, cy, rx, ry, xs, xe, ys, ye;
    // The second grid
    bool ov; double P2, Q2, gx, gy; int ow, oh;
    int[] ocx, ocy, oxs, oxe, oys, oye, oc0, oc1, or0, or1;
    // The third grid
    bool ov3; double P3, Q3, hx, hy; int ow3, oh3;
    System.Collections.Generic.Dictionary<uint, uint> to = new System.Collections.Generic.Dictionary<uint, uint>();
    System.Collections.Generic.Dictionary<uint, long> tot = new System.Collections.Generic.Dictionary<uint, long>();
    System.Diagnostics.Process dec, enc, enc2, enc3; System.Threading.Thread thread;
    public volatile bool Done; public string Error;
    // From Learn: the second grid { size x, size y, offset x, offset y, strength x, strength y } or null
    public double[] Layer;
    // From LearnFrame: the third grid { size x, size y, offset x, offset y } or null
    public double[] Frame;

    public UpscaleGifGridRestore(int w, int h, double P, double Q, double fx, double fy, int bw, int bh) {
        this.w = w; this.h = h; this.bw = bw; this.bh = bh; this.P = P; this.Q = Q; this.fx = fx; this.fy = fy;
        cx = new int[w]; rx = new int[w]; cy = new int[h]; ry = new int[h];
        xs = Fill(bw, -1); xe = Fill(bw, -1); ys = Fill(bh, -1); ye = Fill(bh, -1);
        for (int x = 0; x < w; x++) { double t = (x + 0.5 - fx) / P; int k = (int)t; double f = t - k;
            rx[x] = (t >= 0 && k < bw) ? k : -1; cx[x] = (rx[x] >= 0 && f > 0.2 && f < 0.8) ? k : -1;
            if (rx[x] >= 0) { if (xs[k] < 0) xs[k] = x; xe[k] = x; } }
        for (int y = 0; y < h; y++) { double t = (y + 0.5 - fy) / Q; int k = (int)t; double f = t - k;
            ry[y] = (t >= 0 && k < bh) ? k : -1; cy[y] = (ry[y] >= 0 && f > 0.2 && f < 0.8) ? k : -1;
            if (ry[y] >= 0) { if (ys[k] < 0) ys[k] = y; ye[k] = y; } }
    }
    static int[] Fill(int n, int v) { var a = new int[n]; for (int i = 0; i < n; i++) a[i] = v; return a; }
    static int Fl(double v) { return (int)Math.Floor(v); }

    public void SetLayer(double P2, double Q2, double gx, double gy, int ow, int oh) {
        ov = true; this.P2 = P2; this.Q2 = Q2; this.gx = gx; this.gy = gy; this.ow = ow; this.oh = oh;
        ocx = new int[w]; ocy = new int[h]; oxs = Fill(ow, -1); oxe = Fill(ow, -1); oys = Fill(oh, -1); oye = Fill(oh, -1);
        for (int x = 0; x < w; x++) { double t = (x + 0.5 - gx) / P2; int k = (int)t; double f = t - k;
            ocx[x] = (t >= 0 && k < ow && f > 0.2 && f < 0.8) ? k : -1;
            if (ocx[x] >= 0) { if (oxs[k] < 0) oxs[k] = x; oxe[k] = x; } }
        for (int y = 0; y < h; y++) { double t = (y + 0.5 - gy) / Q2; int k = (int)t; double f = t - k;
            ocy[y] = (t >= 0 && k < oh && f > 0.2 && f < 0.8) ? k : -1;
            if (ocy[y] >= 0) { if (oys[k] < 0) oys[k] = y; oye[k] = y; } }
        // The main cells that each second-grid column and row overlaps
        oc0 = new int[ow]; oc1 = new int[ow]; or0 = new int[oh]; or1 = new int[oh];
        for (int k = 0; k < ow; k++) { oc0[k] = Fl((gx + k * P2 - fx) / P); oc1[k] = Fl((gx + (k + 1) * P2 - fx) / P - 0.000001); }
        for (int k = 0; k < oh; k++) { or0[k] = Fl((gy + k * Q2 - fy) / Q); or1[k] = Fl((gy + (k + 1) * Q2 - fy) / Q - 0.000001); }
    }
    public void SetFrame(double P3, double Q3, double hx, double hy, int ow3, int oh3) {
        ov3 = true; this.P3 = P3; this.Q3 = Q3; this.hx = hx; this.hy = hy; this.ow3 = ow3; this.oh3 = oh3;
    }

    static uint Px(byte[] b, int i) { return ((uint)b[i] << 24) | ((uint)b[i + 1] << 16) | ((uint)b[i + 2] << 8) | b[i + 3]; }
    static int Dist(uint a, uint b) {
        int s = 0;
        for (int sh = 24; sh >= 8; sh -= 8) s += Math.Abs((int)((a >> sh) & 255) - (int)((b >> sh) & 255));
        return s;
    }
    uint Map(uint c) { uint m; return to.TryGetValue(c, out m) ? m : c; }
    long Tot(uint c) { long t; return tot.TryGetValue(c, out t) ? t : 0; }
    // Is colour a a better choice than b: more common here, then overall, then the lower value
    bool Better(uint a, int na, uint b, int nb) {
        if (na != nb) return na > nb;
        long ta = Tot(a), tb = Tot(b);
        return ta != tb ? ta > tb : a < b;
    }
    uint Pick(System.Collections.Generic.Dictionary<uint, int> cnt, out bool any) {
        uint b = 0; int bn = 0; any = false;
        foreach (var e in cnt) if (!any || Better(e.Key, e.Value, b, bn)) { b = e.Key; bn = e.Value; any = true; }
        return b;
    }
    static int Key(int r, int c) { return r * 65536 + c; }

    // One frame: the main colours (B) and badly explained cells (bad: a quarter or more of the
    // middle far from the main colour); px gets the frame's colours, mapped when restoring
    uint[] B; bool[] bad; uint[] px;
    void Cells(byte[] f, int b, bool map, System.Collections.Generic.Dictionary<uint, long> n) {
        B = new uint[bw * bh]; bad = new bool[bw * bh]; px = new uint[w * h];
        for (int i = 0; i < w * h; i++) { uint c = Px(f, b + i * 4); px[i] = map ? Map(c) : c; }
        var cnt = new System.Collections.Generic.Dictionary<uint, int>[bw];
        for (int k = 0; k < bw; k++) cnt[k] = new System.Collections.Generic.Dictionary<uint, int>();
        for (int r = 0; r < bh; r++) {
            for (int y = ys[r]; y >= 0 && y <= ye[r]; y++) {
                if (cy[y] < 0) continue;
                for (int x = 0; x < w; x++) {
                    if (cx[x] < 0) continue;
                    uint c = px[y * w + x];
                    int m; cnt[cx[x]].TryGetValue(c, out m); cnt[cx[x]][c] = m + 1;
                    if (n != null) { long v; n.TryGetValue(c, out v); n[c] = v + 1; }
                }
            }
            for (int k = 0; k < bw; k++) {
                bool any; uint best = Pick(cnt[k], out any);
                int all = 0, far = 0;
                foreach (var e in cnt[k]) { all += e.Value; if (Dist(e.Key, best) > 60) far += e.Value; }
                B[r * bw + k] = best; bad[r * bw + k] = all > 0 && (double)far / all >= 0.25;
                cnt[k].Clear();
            }
        }
    }
    int Near(System.Collections.Generic.HashSet<int> S, int r, int c) {
        int m = 0;
        for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) if ((i != 0 || j != 0) && S.Contains(Key(r + j, c + i))) m++;
        return m;
    }
    System.Collections.Generic.HashSet<int> BadSet() {
        var S = new System.Collections.Generic.HashSet<int>();
        for (int r = 0; r < bh; r++) for (int c = 0; c < bw; c++) if (bad[r * bw + c]) S.Add(Key(r, c));
        return S;
    }

    // Learns from some frames (RGBA): the colours, with nearly identical colours (RGB
    // differences adding up to 18 or less, same transparency) mapped to the most common of
    // them, and a second grid (Layer) from the edges inside clustered, badly explained cells
    public void Learn(byte[] rgba) {
        var n = new System.Collections.Generic.Dictionary<uint, long>();
        double[] ex = new double[w], ey = new double[h]; long ncand = 0, frames = 0;
        int frame = w * h * 4;
        for (int b = 0; b + frame <= rgba.Length; b += frame) {
            Cells(rgba, b, false, n);
            var bs = BadSet();
            foreach (int key in bs) {
                int r = key / 65536, c = key % 65536;
                if (Near(bs, r, c) < 2) continue;
                ncand++;
                for (int y = ys[r]; y <= ye[r]; y++) for (int x = xs[c]; x <= xe[c]; x++) {
                    if (x > 0) ex[x] += Dist(px[y * w + x], px[y * w + x - 1]);
                    if (y > 0) ey[y] += Dist(px[y * w + x], px[(y - 1) * w + x]);
                }
            }
            frames++;
        }
        Layer = null;
        if (ncand >= 0.002 * frames * bw * bh) {
            double[] X = UpscaleGifPixelGrid.Grid(ex, 150, 1600);
            if (X != null) {
                double[] Y = UpscaleGifPixelGrid.Grid(ey, (int)(X[0] * 90), (int)(X[0] * 110));
                if (Y != null) {
                    double fx2 = X[2], fy2 = Y[2];
                    if (fx2 >= 0.8 * X[0]) fx2 -= X[0];
                    if (fy2 >= 0.8 * Y[0]) fy2 -= Y[0];
                    Layer = new double[] { X[0], Y[0], fx2, fy2, X[1], Y[1] };
                }
            }
        }
        var list = new System.Collections.Generic.List<System.Collections.Generic.KeyValuePair<uint, long>>(n);
        list.Sort(delegate(System.Collections.Generic.KeyValuePair<uint, long> a, System.Collections.Generic.KeyValuePair<uint, long> c) {
            int r = c.Value.CompareTo(a.Value); return r != 0 ? r : a.Key.CompareTo(c.Key);
        });
        var kept = new System.Collections.Generic.List<uint>();
        foreach (var e in list) {
            uint into = 0; int bd = 19; bool found = false;
            foreach (uint k in kept) {
                if ((k & 255) != (e.Key & 255)) continue;
                int d = Dist(e.Key, k); if (d < bd) { bd = d; into = k; found = true; }
            }
            if (!found) { kept.Add(e.Key); into = e.Key; }
            to[e.Key] = into; tot[into] = Tot(into) + e.Value;
        }
    }

    // The second grid cell (i, j): the most common colour in its middle (any: false if none)
    System.Collections.Generic.Dictionary<int, uint> O = new System.Collections.Generic.Dictionary<int, uint>();
    System.Collections.Generic.HashSet<int> Onone = new System.Collections.Generic.HashSet<int>();
    uint OCell(int i, int j, out bool any) {
        int key = j * 65536 + i; uint v;
        if (O.TryGetValue(key, out v)) { any = true; return v; }
        if (Onone.Contains(key) || oxs[i] < 0 || oys[j] < 0) { Onone.Add(key); any = false; return 0; }
        var cc = new System.Collections.Generic.Dictionary<uint, int>();
        for (int y = oys[j]; y <= oye[j]; y++) for (int x = oxs[i]; x <= oxe[i]; x++) {
            uint c = px[y * w + x]; int m; cc.TryGetValue(c, out m); cc[c] = m + 1;
        }
        v = Pick(cc, out any);
        if (any) O[key] = v; else Onone.Add(key);
        return v;
    }
    // How far all the pixels of main cell (r, c) are from its colour (em) and from the second
    // grid cells over them (eo)
    System.Collections.Generic.Dictionary<int, long[]> E = new System.Collections.Generic.Dictionary<int, long[]>();
    void Errs(int r, int c, out long em, out long eo) {
        long[] v;
        if (E.TryGetValue(Key(r, c), out v)) { em = v[0]; eo = v[1]; return; }
        em = 0; eo = 0; uint bc = B[r * bw + c];
        for (int y = ys[r]; y <= ye[r]; y++) {
            int j = Fl((y + 0.5 - gy) / Q2);
            for (int x = xs[c]; x <= xe[c]; x++) {
                uint col = px[y * w + x]; em += Dist(col, bc);
                int i = Fl((x + 0.5 - gx) / P2); uint o = bc;
                if (i >= 0 && i < ow && j >= 0 && j < oh) { bool any; uint t = OCell(i, j, out any); if (any) o = t; }
                eo += Dist(col, o);
            }
        }
        E[Key(r, c)] = new long[] { em, eo };
    }
    bool Side(System.Collections.Generic.HashSet<int> U, int r, int c, int dr, int dc) {
        for (int d = 1; d <= 3; d++) if (U.Contains(Key(r + d * dr, c + d * dc))) return true;
        return false;
    }
    // Cell (i, j) of grid id, with its origin at X0, Y0 and cells pp by qq: the most common
    // colour in its middle (any: false if none)
    System.Collections.Generic.Dictionary<long, uint> GC = new System.Collections.Generic.Dictionary<long, uint>();
    System.Collections.Generic.HashSet<long> GCnone = new System.Collections.Generic.HashSet<long>();
    uint GCol(int id, double X0, double Y0, double pp, double qq, int i, int j, out bool any) {
        long key = ((long)id * 65536 + j) * 65536 + i; uint v;
        if (GC.TryGetValue(key, out v)) { any = true; return v; }
        if (GCnone.Contains(key)) { any = false; return 0; }
        int x0 = Fl(X0 + i * pp), x1 = Fl(X0 + (i + 1) * pp), y0 = Fl(Y0 + j * qq), y1 = Fl(Y0 + (j + 1) * qq);
        if (x0 < 0) x0 = 0; if (x1 >= w) x1 = w - 1; if (y0 < 0) y0 = 0; if (y1 >= h) y1 = h - 1;
        var cc = new System.Collections.Generic.Dictionary<uint, int>();
        for (int y = y0; y <= y1; y++) {
            double t = (y + 0.5 - Y0) / qq - j; if (t <= 0.2 || t >= 0.8) continue;
            for (int x = x0; x <= x1; x++) {
                t = (x + 0.5 - X0) / pp - i;
                if (t > 0.2 && t < 0.8) { uint c = px[y * w + x]; int m; cc.TryGetValue(c, out m); cc[c] = m + 1; }
            }
        }
        v = Pick(cc, out any);
        if (any) GC[key] = v; else GCnone.Add(key);
        return v;
    }
    // How far all the pixels of main cell (r, c) are from the cells of grid id (n by m of them)
    // over them
    long FErr(int id, double X0, double Y0, double pp, double qq, int n, int m, int r, int c) {
        long e = 0; uint bc = B[r * bw + c];
        for (int y = ys[r]; y <= ye[r]; y++) {
            int j = Fl((y + 0.5 - Y0) / qq);
            for (int x = xs[c]; x <= xe[c]; x++) {
                int i = Fl((x + 0.5 - X0) / pp); uint o = bc;
                if (i >= 0 && i < n && j >= 0 && j < m) { bool any; uint t = GCol(id, X0, Y0, pp, qq, i, j, out any); if (any) o = t; }
                e += Dist(px[y * w + x], o);
            }
        }
        return e;
    }
    // The main cells within 2 of the region U
    System.Collections.Generic.HashSet<int> Around(System.Collections.Generic.HashSet<int> U) { return Around(U, 2); }
    System.Collections.Generic.HashSet<int> Around(System.Collections.Generic.HashSet<int> U, int d) {
        var C = new System.Collections.Generic.HashSet<int>();
        foreach (int key in U) {
            int r0 = key / 65536, c0 = key % 65536;
            for (int i = -d; i <= d; i++) for (int j = -d; j <= d; j++) {
                int r = r0 + j, c = c0 + i;
                if (r >= 0 && r < bh && c >= 0 && c < bw) C.Add(Key(r, c));
            }
        }
        return C;
    }
    // The colours of main cell (r, c) that fill a 2 by 2 square of pixels starting in it: real
    // colours do, the blur between two colours is thinner
    System.Collections.Generic.Dictionary<int, System.Collections.Generic.HashSet<uint>> SD = new System.Collections.Generic.Dictionary<int, System.Collections.Generic.HashSet<uint>>();
    System.Collections.Generic.HashSet<uint> Solid(int r, int c) {
        System.Collections.Generic.HashSet<uint> S;
        if (SD.TryGetValue(Key(r, c), out S)) return S;
        S = new System.Collections.Generic.HashSet<uint>();
        for (int y = ys[r]; y <= ye[r] && y + 1 < h; y++)
            for (int x = xs[c]; x <= xe[c] && x + 1 < w; x++) {
                uint a = px[y * w + x];
                if (px[y * w + x + 1] == a && px[(y + 1) * w + x] == a && px[(y + 1) * w + x + 1] == a) S.Add(a);
            }
        SD[Key(r, c)] = S;
        return S;
    }
    bool IsSolid(uint col, int r, int c) {
        for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++)
            if (r + j >= 0 && r + j < bh && c + i >= 0 && c + i < bw && Solid(r + j, c + i).Contains(col)) return true;
        return false;
    }
    // Colour v of a pixel near main cell (r, c), snapped to the main colours of the cells within
    // 2 that are real colours there (with the same transparency): a blurred pixel is a mix of
    // two of them (close to the line between them: squared RGB distance under 300), and becomes
    // the one it is closer to; others become the nearest one (with PO set, only to colours in Pal)
    System.Collections.Generic.HashSet<uint> Pal = new System.Collections.Generic.HashSet<uint>();
    bool PO;
    System.Collections.Generic.Dictionary<ulong, uint> SN = new System.Collections.Generic.Dictionary<ulong, uint>();
    uint Snap(uint v, int r, int c) {
        ulong key = ((ulong)v << 32) | ((ulong)(uint)(r & 32767) << 16) | ((ulong)(uint)(c & 32767) << 1) | (PO ? 1UL : 0UL);
        uint res;
        if (SN.TryGetValue(key, out res)) return res;
        var K = new System.Collections.Generic.List<uint>(); var seen = new System.Collections.Generic.HashSet<uint>();
        for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
            if (r + j < 0 || r + j >= bh || c + i < 0 || c + i >= bw) continue;
            uint col = B[(r + j) * bw + c + i];
            if ((col & 255) != (v & 255) || seen.Contains(col) || (PO && !Pal.Contains(col))) continue;
            seen.Add(col);
            if (IsSolid(col, r, c)) K.Add(col);
        }
        if (K.Count == 0) { SN[key] = v; return v; }
        K.Sort();
        int m = K.Count; var R = new int[m]; var G = new int[m]; var Bl = new int[m];
        for (int k = 0; k < m; k++) { R[k] = (int)(K[k] >> 24); G[k] = (int)((K[k] >> 16) & 255); Bl[k] = (int)((K[k] >> 8) & 255); }
        int vr = (int)(v >> 24), vg = (int)((v >> 16) & 255), vb = (int)((v >> 8) & 255);
        double bd = -1; uint best = 0;
        for (int k = 0; k < m; k++) {
            double d = (double)(vr - R[k]) * (vr - R[k]) + (double)(vg - G[k]) * (vg - G[k]) + (double)(vb - Bl[k]) * (vb - Bl[k]);
            if (bd < 0 || d < bd) { bd = d; best = K[k]; }
        }
        for (int i = 0; i < m; i++) for (int j = i + 1; j < m; j++) {
            int dr = R[j] - R[i], dg = G[j] - G[i], db = Bl[j] - Bl[i]; double L = dr * dr + dg * dg + db * db;
            double t = ((vr - R[i]) * dr + (vg - G[i]) * dg + (vb - Bl[i]) * db) / L;
            if (t <= 0 || t >= 1) continue;
            double er = vr - (R[i] + t * dr), eg = vg - (G[i] + t * dg), eb = vb - (Bl[i] + t * db);
            double d = er * er + eg * eg + eb * eb;
            if (d < bd && d < 300) { bd = d; best = t < 0.5 ? K[i] : K[j]; }
        }
        SN[key] = best;
        return best;
    }
    // Removes the pieces of S (cells touching, also corner to corner) smaller than a quarter of
    // the biggest one
    void Pieces(System.Collections.Generic.HashSet<int> S) {
        var id = new System.Collections.Generic.Dictionary<int, int>(); var size = new System.Collections.Generic.List<int>(); int big = 0;
        foreach (int key in S) {
            if (id.ContainsKey(key)) continue;
            int np = size.Count; id[key] = np;
            var q = new System.Collections.Generic.List<int>(); q.Add(key);
            for (int k = 0; k < q.Count; k++) {
                int r0 = q[k] / 65536, c0 = q[k] % 65536;
                for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
                    int r = r0 + j, c = c0 + i;
                    if (r < 0 || c < 0) continue;
                    int k2 = Key(r, c);
                    if (S.Contains(k2) && !id.ContainsKey(k2)) { id[k2] = np; q.Add(k2); }
                }
            }
            size.Add(q.Count); if (q.Count > big) big = q.Count;
        }
        foreach (var e in id) if (size[e.Value] < big / 4.0) S.Remove(e.Key);
    }
    void ClearCaches() { O.Clear(); Onone.Clear(); E.Clear(); GC.Clear(); GCnone.Clear(); SN.Clear(); SD.Clear(); Pal.Clear(); PO = false; }

    // Learning a third grid: the cells of the second grid 1, 1.5 or 2 times as big, moved by any
    // number of half pixels. Each is tried around the region of up to 3 frames (RGBA), adding
    // up for each cell how badly the best of the three grids explains it, and of the first
    // two. The best one (the first of equals) becomes Frame if it leaves the badly explained
    // colours at least 10% lower. Speech bubbles can have their frame drawn at another size
    // and position than their text.
    public void LearnFrame(byte[] rgba) {
        Frame = null;
        var G = new System.Collections.Generic.List<double[]>();
        for (int kk = 0; kk < 3; kk++) {
            double k = 1 + kk * 0.5, pp = k * P2, qq = k * Q2;
            for (int dx = 0; dx * 0.5 < pp; dx++) for (int dy = 0; dy * 0.5 < qq; dy++) {
                double X0 = gx + dx * 0.5; while (X0 >= 0.8 * pp) X0 -= pp;
                double Y0 = gy + dy * 0.5; while (Y0 >= 0.8 * qq) Y0 -= qq;
                G.Add(new double[] { pp, qq, X0, Y0, (int)((w - X0) / pp + 0.2), (int)((h - Y0) / qq + 0.2) });
            }
        }
        var FT = new long[G.Count]; long FB = 0; int fdone = 0, frame = w * h * 4;
        for (int b = 0; b + frame <= rgba.Length && fdone < 3; b += frame) {
            Cells(rgba, b, true, null); ClearCaches();
            var U = Region();
            if (U.Count == 0) continue;
            var LC = new System.Collections.Generic.List<int>(); var LM = new System.Collections.Generic.List<long>();
            foreach (int key in Around(U)) {
                long em, eo; Errs(key / 65536, key % 65536, out em, out eo);
                long m = Math.Min(em, eo); if (m > 0) { LC.Add(key); LM.Add(m); FB += m; }
            }
            if (LC.Count == 0) continue;
            fdone++;
            for (int g = 0; g < G.Count; g++) {
                double[] d = G[g];
                for (int t = 0; t < LC.Count; t++) {
                    long e = FErr(g + 1, d[2], d[3], d[0], d[1], (int)d[4], (int)d[5], LC[t] / 65536, LC[t] % 65536);
                    FT[g] += Math.Min(e, LM[t]);
                }
            }
        }
        ClearCaches();
        int best = -1;
        for (int g = 0; g < G.Count; g++) if (best < 0 || FT[g] < FT[best]) best = g;
        if (best >= 0 && FT[best] < 0.9 * FB) Frame = new double[] { G[best][0], G[best][1], G[best][2], G[best][3] };
    }

    // This frame's region where the second grid fits clearly better
    System.Collections.Generic.HashSet<int> Region() { System.Collections.Generic.Dictionary<int, int> seen; return Region(out seen); }
    // (seen: how many flat cells each cell was reached across, 0 for the cells found as text)
    System.Collections.Generic.HashSet<int> Region(out System.Collections.Generic.Dictionary<int, int> seen) {
        long em, eo;
        var bs = BadSet();
        // Seeds: badly explained cells the second grid explains at least twice as well...
        var S = new System.Collections.Generic.HashSet<int>();
        foreach (int key in bs) {
            int r = key / 65536, c = key % 65536;
            if (Near(bs, r, c) == 0) continue;
            Errs(r, c, out em, out eo); if (eo < 0.5 * em) S.Add(key);
        }
        // ...in clusters (text), not alone (blurred sprite edges)
        var U = new System.Collections.Generic.HashSet<int>(); seen = new System.Collections.Generic.Dictionary<int, int>();
        var q = new System.Collections.Generic.List<int>();
        foreach (int key in S) if (Near(S, key / 65536, key % 65536) >= 2) { U.Add(key); seen[key] = 0; q.Add(key); }
        // Grow into the cells around them where the second grid is better, and across up to 3
        // cells where both fit equally (flat areas), so that what surrounds the text, such as
        // the frame of a speech bubble, joins it on the same grid (across flat cells, only a
        // clearly better fit counts as part of it again)
        for (int k = 0; k < q.Count; k++) {
            int r0 = q[k] / 65536, c0 = q[k] % 65536, d0 = seen[q[k]];
            for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
                int r = r0 + j, c = c0 + i, d, sd;
                if ((i == 0 && j == 0) || r < 0 || r >= bh || c < 0 || c >= bw) continue;
                Errs(r, c, out em, out eo);
                if (eo < em && (d0 == 0 || eo < 0.5 * em)) d = 0; else if (eo <= em) d = d0 + 1; else continue;
                if (d > 3 || (seen.TryGetValue(Key(r, c), out sd) && sd <= d)) continue;
                U.Add(Key(r, c)); seen[Key(r, c)] = d; q.Add(Key(r, c));
            }
        }
        // Those flat cells must not touch content that fits the main grid better (a sprite
        // beside the bubble): its second-grid pixels would overlap that content
        var drop = new System.Collections.Generic.List<int>();
        foreach (int key in U) {
            if (seen[key] == 0) continue;
            int r0 = key / 65536, c0 = key % 65536; bool touch = false;
            for (int i = -1; i <= 1 && !touch; i++) for (int j = -1; j <= 1; j++) {
                int r = r0 + j, c = c0 + i;
                if ((i == 0 && j == 0) || r < 0 || r >= bh || c < 0 || c >= bw || U.Contains(Key(r, c))) continue;
                Errs(r, c, out em, out eo); if (eo > em) { touch = true; break; }
            }
            if (touch) drop.Add(key);
        }
        foreach (int key in drop) U.Remove(key);
        // Fill gaps: cells with region cells within 3 on both sides, left and right or above
        // and below, unless the second grid fits them more than twice as badly
        for (int it = 0; it < 2; it++) {
            var cand = new System.Collections.Generic.HashSet<int>();
            foreach (int key in U) {
                int r0 = key / 65536, c0 = key % 65536;
                for (int d = 1; d <= 3; d++) {
                    if (c0 - d >= 0) cand.Add(Key(r0, c0 - d)); if (c0 + d < bw) cand.Add(Key(r0, c0 + d));
                    if (r0 - d >= 0) cand.Add(Key(r0 - d, c0)); if (r0 + d < bh) cand.Add(Key(r0 + d, c0));
                }
            }
            var add = new System.Collections.Generic.List<int>();
            foreach (int key in cand) {
                if (U.Contains(key)) continue;
                int r = key / 65536, c = key % 65536;
                if (!((Side(U, r, c, 0, -1) && Side(U, r, c, 0, 1)) || (Side(U, r, c, -1, 0) && Side(U, r, c, 1, 0)))) continue;
                Errs(r, c, out em, out eo); if (eo <= 2 * em) add.Add(key);
            }
            foreach (int key in add) U.Add(key);
        }
        return U;
    }
    // This frame of the second layer: its cells that overlap the main cells where it fits
    // clearly better (covering those entirely), transparent elsewhere; and of the third (fo)
    // This frame of the second layer: its cells that overlap the main cells where it fits
    // clearly better (covering those entirely), transparent elsewhere; and of the third (fo, at
    // the source size)
    byte[] LayerFrame(out byte[] fo) {
        ClearCaches();
        var o = new byte[ow * oh * 4];
        fo = ov3 ? new byte[w * h * 4] : null;
        System.Collections.Generic.Dictionary<int, int> seen;
        var U = Region(out seen);
        var F = new System.Collections.Generic.HashSet<int>();
        long em, eo;
        if (ov3 && U.Count > 0) {
            // Around the region, the third grid takes the cells it explains clearly better than
            // both others, and the less clear ones next to those (each pass) unless the main grid
            // fits them more than 1.5 times as well. The second layer keeps the rest.
            var C = Around(U);
            var EMv = new System.Collections.Generic.Dictionary<int, long>(); var ET = new System.Collections.Generic.Dictionary<int, long>();
            var EF = new System.Collections.Generic.Dictionary<int, long>();
            foreach (int key in C) {
                int r = key / 65536, c = key % 65536;
                Errs(r, c, out em, out eo); EMv[key] = em; ET[key] = eo;
                EF[key] = FErr(0, hx, hy, P3, Q3, ow3, oh3, r, c);
                if (EF[key] < em && EF[key] < 0.75 * eo) F.Add(key);
            }
            for (int it = 0; it < 3; it++) {
                var add = new System.Collections.Generic.List<int>();
                foreach (int key in C) {
                    if (F.Contains(key)) continue;
                    if (EMv[key] > 0 && EF[key] <= 1.5 * EMv[key] && EF[key] <= ET[key] && Near(F, key / 65536, key % 65536) > 0) add.Add(key);
                }
                foreach (int key in add) F.Add(key);
            }
            // A frame is all in one piece: small pieces (under a quarter of the biggest) are bits
            // of text that it happens to fit
            Pieces(F);
            // Then the flat cells of its colours next to it, outside the text and within 3 of it,
            // such as a stretch of border that happens to line up with the main grid
            foreach (int key in F) { uint b = B[(key / 65536) * bw + key % 65536]; if (!Pal.Contains(b) && IsSolid(b, key / 65536, key % 65536)) Pal.Add(b); }
            var C3 = Around(U, 3);
            int added;
            do {
                added = 0;
                foreach (int key in C3) {
                    int r = key / 65536, c = key % 65536;
                    if (F.Contains(key) || U.Contains(key) || !Pal.Contains(B[r * bw + c]) || Near(F, r, c) == 0) continue;
                    Errs(r, c, out em, out eo); if (em == 0) { F.Add(key); added++; }
                }
            } while (added > 0);
            // A frame goes around its text: none if it does not reach past the text (the cells
            // found as such, not the flat ones joined to them) on all sides
            int r0 = int.MaxValue, r1 = -1, c0 = int.MaxValue, c1 = -1;
            foreach (int key in U) {
                int sd; if (F.Contains(key) || (seen.TryGetValue(key, out sd) && sd != 0)) continue;
                int r = key / 65536, c = key % 65536;
                r0 = Math.Min(r0, r); r1 = Math.Max(r1, r); c0 = Math.Min(c0, c); c1 = Math.Max(c1, c);
            }
            bool tt = false, tb = false, tl = false, tr = false;
            foreach (int key in F) { int r = key / 65536, c = key % 65536; if (r < r0) tt = true; if (r > r1) tb = true; if (c < c0) tl = true; if (c > c1) tr = true; }
            if (!(tt && tb && tl && tr)) F.Clear();
            foreach (int key in F) U.Remove(key);
        }
        // It is the source itself (its pixels in those cells and the text cells next to them),
        // as drawn: plain nearest neighbour, as no grid fits a frame drawn at another size and
        // position than everything else. Its blurred pixels are snapped to the real colours of
        // those cells (SP)...
        var Gs = new System.Collections.Generic.HashSet<int>();
        if (ov3) foreach (int key in U) if (Near(F, key / 65536, key % 65536) > 0) Gs.Add(key);
        foreach (int key in F) Gs.Add(key);
        foreach (int key in Gs) { uint b = B[(key / 65536) * bw + key % 65536]; if (!Pal.Contains(b) && IsSolid(b, key / 65536, key % 65536)) Pal.Add(b); }
        if (ov3 && F.Count > 0) {
            PO = true;
            var SP = new System.Collections.Generic.Dictionary<int, uint>();
            for (int y = 0; y < h; y++) {
                if (ry[y] < 0) continue;
                for (int x = 0; x < w; x++) if (rx[x] >= 0 && Gs.Contains(Key(ry[y], rx[x]))) SP[y * w + x] = Snap(px[y * w + x], ry[y], rx[x]);
            }
            PO = false;
            // ...and single pixels (sharing their colour with at most one of the 4 around them, 3
            // or more of them drawn) take the colour most common around them (the first of
            // equals, in the order above, left, right, below): its lines are 3 or more pixels
            // wide, so those are blur
            var T2 = new System.Collections.Generic.Dictionary<int, uint>();
            int[] dx = { 0, -1, 1, 0 }, dy = { -1, 0, 0, 1 };
            foreach (var e in SP) {
                int x0 = e.Key % w, y0 = e.Key / w, nb = 0, m = 0;
                var TN = new System.Collections.Generic.Dictionary<uint, int>(); var nc = new uint?[4];
                for (int k = 0; k < 4; k++) {
                    int x = x0 + dx[k], y = y0 + dy[k]; uint v;
                    if (x < 0 || x >= w || y < 0 || y >= h || !SP.TryGetValue(y * w + x, out v)) continue;
                    nc[k] = v; m++;
                    if (v == e.Value) nb++; else { int t; TN.TryGetValue(v, out t); TN[v] = t + 1; }
                }
                if (m < 3 || nb > 1) continue;
                bool found = false; uint best = 0;
                for (int k = 0; k < 4; k++) {
                    if (nc[k] == null || nc[k].Value == e.Value) continue;
                    if (!found || TN[nc[k].Value] > TN[best]) { best = nc[k].Value; found = true; }
                }
                T2[e.Key] = best;
            }
            foreach (var e in T2) SP[e.Key] = e.Value;
            foreach (var e in SP) {
                int p = e.Key * 4; uint col = e.Value;
                fo[p] = (byte)(col >> 24); fo[p + 1] = (byte)(col >> 16); fo[p + 2] = (byte)(col >> 8); fo[p + 3] = (byte)col;
            }
        }
        if (U.Count == 0) return o;
        // (not where it would cover any of the third layer)
        for (int j = 0; j < oh; j++) for (int i = 0; i < ow; i++) {
            int hit = -1; bool under = false;
            for (int r = or0[j]; r <= or1[j]; r++)
                for (int c = oc0[i]; c <= oc1[i]; c++) {
                    if (r < 0 || r >= bh || c < 0 || c >= bw) continue;
                    if (Gs.Contains(Key(r, c))) under = true; else if (hit < 0 && U.Contains(Key(r, c))) hit = r * bw + c;
                }
            if (hit < 0 || under) continue;
            bool any; uint col = OCell(i, j, out any); if (!any) col = B[hit];
            int p = (j * ow + i) * 4;
            o[p] = (byte)(col >> 24); o[p + 1] = (byte)(col >> 16); o[p + 2] = (byte)(col >> 8); o[p + 3] = (byte)col;
        }
        return o;
    }

    public byte[] RestoreFrame(byte[] f, out byte[] layer, out byte[] frameLayer) {
        Cells(f, 0, true, null);
        var o = new byte[bw * bh * 4];
        for (int i = 0; i < bw * bh; i++) { uint c = B[i]; o[i * 4] = (byte)(c >> 24); o[i * 4 + 1] = (byte)(c >> 16); o[i * 4 + 2] = (byte)(c >> 8); o[i * 4 + 3] = (byte)c; }
        frameLayer = null;
        layer = ov ? LayerFrame(out frameLayer) : null;
        return o;
    }

    static System.Diagnostics.Process Spawn(string exe, string args, bool input, bool output) {
        var psi = new System.Diagnostics.ProcessStartInfo(exe, args);
        psi.UseShellExecute = false; psi.CreateNoWindow = true;
        psi.RedirectStandardInput = input; psi.RedirectStandardOutput = output; psi.RedirectStandardError = true;
        var p = System.Diagnostics.Process.Start(psi);
        p.ErrorDataReceived += delegate(object s, System.Diagnostics.DataReceivedEventArgs e) { };
        p.BeginErrorReadLine();
        return p;
    }
    static bool ReadFull(System.IO.Stream s, byte[] b) {
        int got = 0;
        while (got < b.Length) { int n = s.Read(b, got, b.Length - got); if (n <= 0) return false; got += n; }
        return true;
    }
    // Restores every frame from one ffmpeg (decodeArgs, RGBA out) into another (encodeArgs),
    // the second layer, if any, into a third (layerArgs), and the third layer into a fourth
    // (frameArgs)
    public void Start(string ffmpeg, string decodeArgs, string encodeArgs, string layerArgs, string frameArgs) {
        thread = new System.Threading.Thread(delegate() {
            try {
                dec = Spawn(ffmpeg, decodeArgs, false, true); enc = Spawn(ffmpeg, encodeArgs, true, false);
                if (ov) enc2 = Spawn(ffmpeg, layerArgs, true, false);
                if (ov3) enc3 = Spawn(ffmpeg, frameArgs, true, false);
                var f = new byte[w * h * 4];
                var src = dec.StandardOutput.BaseStream; var dst = enc.StandardInput.BaseStream;
                var dst2 = ov ? enc2.StandardInput.BaseStream : null;
                var dst3 = ov3 ? enc3.StandardInput.BaseStream : null;
                while (ReadFull(src, f)) {
                    byte[] l, fl; var o = RestoreFrame(f, out l, out fl);
                    dst.Write(o, 0, o.Length);
                    if (ov) dst2.Write(l, 0, l.Length);
                    if (ov3) dst3.Write(fl, 0, fl.Length);
                }
                dst.Close(); if (ov) dst2.Close(); if (ov3) dst3.Close();
                dec.WaitForExit(); enc.WaitForExit(); if (ov) enc2.WaitForExit(); if (ov3) enc3.WaitForExit();
                if (dec.ExitCode != 0 || enc.ExitCode != 0 || (ov && enc2.ExitCode != 0) || (ov3 && enc3.ExitCode != 0)) throw new Exception("ffmpeg failed");
            } catch (Exception e) { Error = e.Message; }
            Done = true;
        });
        thread.IsBackground = true; thread.Start();
    }
    public void Cancel() {
        foreach (var p in new[] { dec, enc, enc2, enc3 }) { try { if (p != null && !p.HasExited) p.Kill(); } catch { } }
    }
}
'@

$LevelDbReader = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public static class UpscaylLocalStorage {
    class Entry { public byte[] Key; public ulong Seq; public bool Live; public byte[] Value; }

    static int Varint(byte[] b, ref int i) {
        int r = 0, s = 0;
        while (true) {
            byte c = b[i++];
            r |= (c & 0x7f) << s; s += 7;
            if (c < 0x80) return r;
        }
    }

    static byte[] Unsnappy(byte[] b) {
        int i = 0;
        byte[] o = new byte[Varint(b, ref i)];
        int op = 0;
        while (i < b.Length) {
            int t = b[i++], n, off;
            if ((t & 3) == 0) {
                n = t >> 2;
                if (n >= 60) {
                    int w = n - 59; n = 0;
                    for (int k = 0; k < w; k++) n |= b[i + k] << (8 * k);
                    i += w;
                }
                n += 1;
                Buffer.BlockCopy(b, i, o, op, n); i += n; op += n;
                continue;
            }
            if ((t & 3) == 1) { n = ((t >> 2) & 7) + 4; off = ((t >> 5) << 8) | b[i]; i += 1; }
            else if ((t & 3) == 2) { n = (t >> 2) + 1; off = b[i] | (b[i + 1] << 8); i += 2; }
            else { n = (t >> 2) + 1; off = BitConverter.ToInt32(b, i); i += 4; }
            for (int k = 0; k < n; k++, op++) o[op] = o[op - off];
        }
        return o;
    }

    static byte[] Slice(byte[] b, int off, int len) {
        byte[] r = new byte[len];
        Buffer.BlockCopy(b, off, r, 0, len);
        return r;
    }

    static byte[] Block(byte[] f, int off, int size) {
        byte[] d = Slice(f, off, size);
        return f[off + size] == 1 ? Unsnappy(d) : d;
    }

    static List<KeyValuePair<byte[], byte[]>> Entries(byte[] b) {
        var list = new List<KeyValuePair<byte[], byte[]>>();
        int end = b.Length - 4 - 4 * BitConverter.ToInt32(b, b.Length - 4);
        int i = 0;
        byte[] key = new byte[0];
        while (i < end) {
            int shared = Varint(b, ref i), fresh = Varint(b, ref i), vlen = Varint(b, ref i);
            byte[] k = new byte[shared + fresh];
            Buffer.BlockCopy(key, 0, k, 0, shared);
            Buffer.BlockCopy(b, i, k, shared, fresh);
            key = k; i += fresh;
            list.Add(new KeyValuePair<byte[], byte[]>(key, Slice(b, i, vlen)));
            i += vlen;
        }
        return list;
    }

    static byte[] ReadShared(string path) {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
            byte[] data = new byte[fs.Length];
            int read = 0;
            while (read < data.Length) {
                int n = fs.Read(data, read, data.Length - read);
                if (n <= 0) break;
                read += n;
            }
            return data;
        }
    }

    static List<Entry> Table(string path) {
        var result = new List<Entry>();
        byte[] f = ReadShared(path);
        byte[] foot = Slice(f, f.Length - 48, 48);
        int i = 0;
        Varint(foot, ref i); Varint(foot, ref i);
        int ioff = Varint(foot, ref i), isize = Varint(foot, ref i);
        foreach (var h in Entries(Block(f, ioff, isize))) {
            int j = 0;
            int boff = Varint(h.Value, ref j), bsize = Varint(h.Value, ref j);
            foreach (var e in Entries(Block(f, boff, bsize))) {
                ulong tag = BitConverter.ToUInt64(e.Key, e.Key.Length - 8);
                var entry = new Entry();
                entry.Key = Slice(e.Key, 0, e.Key.Length - 8); entry.Seq = tag >> 8;
                entry.Live = (tag & 0xff) == 1; entry.Value = e.Value;
                result.Add(entry);
            }
        }
        return result;
    }

    static List<Entry> Log(string path) {
        var result = new List<Entry>();
        byte[] data = ReadShared(path);
        int pos = 0;
        var rec = new MemoryStream();
        while (pos + 7 <= data.Length) {
            int left = 32768 - pos % 32768;
            if (left < 7) { pos += left; continue; }
            int n = data[pos + 4] | data[pos + 5] << 8, kind = data[pos + 6];
            if (pos + 7 + n > data.Length) break;
            if (kind == 1 || kind == 2) rec.SetLength(0);
            else if (kind != 3 && kind != 4) break;
            rec.Write(data, pos + 7, n);
            pos += 7 + n;
            if (kind != 1 && kind != 4) continue;
            byte[] r = rec.ToArray();
            ulong seq = BitConverter.ToUInt64(r, 0);
            int count = BitConverter.ToInt32(r, 8), i = 12;
            for (int c = 0; c < count; c++) {
                var entry = new Entry();
                entry.Live = r[i++] == 1;
                int kl = Varint(r, ref i);
                entry.Key = Slice(r, i, kl); i += kl;
                entry.Value = new byte[0];
                if (entry.Live) { int vl = Varint(r, ref i); entry.Value = Slice(r, i, vl); i += vl; }
                entry.Seq = seq + (ulong)c;
                result.Add(entry);
            }
        }
        return result;
    }

    static bool EndsWith(byte[] a, byte[] b) {
        if (a.Length < b.Length) return false;
        for (int i = 0; i < b.Length; i++) if (a[a.Length - b.Length + i] != b[i]) return false;
        return true;
    }

    // Values are JSON (jotai atomWithStorage); only strings and numbers are needed
    static string FromJson(string s) {
        s = s.Trim();
        if (s.Length < 2 || s[0] != '"') return s == "null" ? "" : s;
        var o = new StringBuilder();
        for (int i = 1; i < s.Length - 1; i++) {
            char c = s[i];
            if (c != '\\') { o.Append(c); continue; }
            c = s[++i];
            switch (c) {
                case 'b': o.Append('\b'); break;
                case 'f': o.Append('\f'); break;
                case 'n': o.Append('\n'); break;
                case 'r': o.Append('\r'); break;
                case 't': o.Append('\t'); break;
                case 'u': o.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16)); i += 4; break;
                default: o.Append(c); break;
            }
        }
        return o.ToString();
    }

    public static string[] Read(string dir, string[] names) {
        Encoding latin1 = Encoding.GetEncoding(28591);
        var files = new List<string>();
        files.AddRange(Directory.GetFiles(dir, "*.ldb"));
        files.AddRange(Directory.GetFiles(dir, "*.sst"));
        int tables = files.Count;
        files.AddRange(Directory.GetFiles(dir, "*.log"));
        // localStorage keys are "_<origin>\0\1<name>"
        var suffixes = new byte[names.Length][];
        for (int n = 0; n < names.Length; n++) {
            byte[] nb = latin1.GetBytes(names[n]);
            suffixes[n] = new byte[nb.Length + 2];
            suffixes[n][1] = 1;
            Buffer.BlockCopy(nb, 0, suffixes[n], 2, nb.Length);
        }
        var best = new Entry[names.Length];
        for (int fi = 0; fi < files.Count; fi++) {
            List<Entry> entries;
            try { entries = fi < tables ? Table(files[fi]) : Log(files[fi]); }
            catch (Exception) { continue; }
            foreach (var e in entries) {
                if (e.Key.Length == 0 || e.Key[0] != (byte)'_') continue;
                for (int n = 0; n < names.Length; n++)
                    if (EndsWith(e.Key, suffixes[n]) && (best[n] == null || e.Seq > best[n].Seq)) best[n] = e;
            }
        }
        var result = new string[names.Length];
        for (int n = 0; n < names.Length; n++) {
            result[n] = "";
            var e = best[n];
            if (e == null || !e.Live || e.Value.Length == 0) continue;
            // A \0 prefix marks UTF-16 text, \1 Latin-1
            string s = e.Value[0] == 0
                ? Encoding.Unicode.GetString(e.Value, 1, e.Value.Length - 1)
                : latin1.GetString(e.Value, 1, e.Value.Length - 1);
            try { result[n] = FromJson(s).Replace("\n", " "); } catch (Exception) { }
        }
        return result;
    }
}
'@
function Get-UpscaylSettings([string[]]$Names) {
    $dirs = @(Join-Path ((Get-AppData)) 'Upscayl')
    if ($OnWindows) {
        $dirs += @(Get-ChildItem "$env:LOCALAPPDATA\Packages\*Upscayl*\LocalCache\Roaming\Upscayl" -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName })
    }
    foreach ($d in $dirs) {
        $db = Join-Path $d 'Local Storage/leveldb'
        if (-not (Test-Path -LiteralPath $db -PathType Container)) { continue }
        try {
            if (-not ('UpscaylLocalStorage' -as [type])) { Add-Type -TypeDefinition $LevelDbReader -Language CSharp }
            return [UpscaylLocalStorage]::Read($db, $Names)
        } catch { }
    }
    return @($Names | ForEach-Object { '' })
}

# --- Models and GPUs -------------------------------------------------------------------
# Same rule as Upscayl: names with x2/2x or x3/3x are 2x/3x models, everything else 4x
function Get-ModelScale([string]$Name) {
    $n = $Name.ToLowerInvariant()
    if ($n -match 'x2|2x') { return 2 }
    if ($n -match 'x3|3x') { return 3 }
    return 4
}
function Add-Models([string]$Dir) {
    foreach ($p in @(Get-ChildItem -LiteralPath $Dir -Filter '*.param' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $n = $p.BaseName
        if ((Test-Path -LiteralPath (Join-Path $Dir "$n.bin")) -and -not $script:ModelDir.Contains($n)) {
            $script:ModelDir[$n] = $Dir; $script:ModelList.Add($n)
        }
    }
}
function Test-Custom([string]$Name) { $script:CustomModels -and $script:ModelDir[$Name] -eq $script:CustomModels -and -not $Desc.Contains($Name) }
function Test-Bundled { $script:Upscayl -and (Split-Path $script:Upscayl) -eq $BundleBin }
# GPUs as upscayl-bin numbers them ("id name" per line): it lists them before failing on
# the missing input.
function Get-Gpus {
    if ($script:ModelList.Count -eq 0) { return @() }
    $m = $script:ModelList[0]
    $missing = Join-Path ([IO.Path]::GetTempPath()) 'upscale-gif-probe/missing.png'
    $r = Invoke-Tool $script:Upscayl @('-i', $missing, '-o', $missing, '-m', $script:ModelDir[$m], '-n', $m) -Capture -TimeoutSec 30
    @(Lines ($r.Out + "`n" + $r.Err) | ForEach-Object { if ($_ -match '^\[(\d+) (.*)\]  queueC=') { "$($Matches[1]) $($Matches[2])" } })
}
# Software Vulkan drivers run on the CPU: they work, but extremely slowly
function Test-SoftwareGpu([string]$Line) { $Line -match 'llvmpipe|lavapipe|swiftshader' }
$NoGpuHelp = if ($OnWindows) {
    "No GPU with a Vulkan driver was found, and the AI models need one.`n" +
    "Install or update the driver for your graphics card from AMD, NVIDIA or Intel (the basic " +
    "driver from Windows Update may not include Vulkan). Virtual machines and Remote Desktop " +
    "sessions usually have no Vulkan GPU."
} else {
    "No GPU with a Vulkan driver was found, and the AI models need one.`n" +
    "Install the Vulkan driver for your graphics card (Mesa for AMD and Intel, NVIDIA's own " +
    "driver for NVIDIA). Virtual machines and remote sessions usually have no Vulkan GPU."
}
# Why the bundled upscaler can't run, or $null
function Get-BundleError {
    if ($script:Upscayl -or $env:UPSCAYL_BIN) { return $null }
    $b = @((Join-Path $BundleBin 'upscayl-bin.exe'), (Join-Path $BundleBin 'upscayl-bin') | Where-Object { Test-Path -LiteralPath $_ })
    if (-not $b) { return $null }
    try { $r = Invoke-Tool $b[0] @('-h') -Capture -TimeoutSec 10 } catch { return "the bundled upscaler can't start: $($_.Exception.Message)" }
    # 0xC0000135: a DLL is missing; the only one not shipped or part of Windows is vulkan-1.dll
    if ($r.Code -eq -1073741515) {
        return "the bundled upscaler can't start because vulkan-1.dll is missing. It comes with the " +
            'graphics driver: install or update the driver for your graphics card from AMD, NVIDIA or Intel.'
    }
    $first = @(Lines ($r.Err + "`n" + $r.Out))[0]
    "the bundled upscaler can't start: $(if ($first) { $first } else { "exit code $($r.Code)" })"
}

function Get-Encoders {
    $set = New-Object 'Collections.Generic.HashSet[string]'
    if ($script:FFmpeg) {
        foreach ($l in (Lines (Invoke-Tool $script:FFmpeg @('-hide_banner', '-encoders') -Capture).Out)) {
            $t = -split $l
            if ($t.Count -ge 2 -and $t[0] -match '^[VAS][F.][S.][X.][B.][D.]$') { [void]$set.Add($t[1]) }
        }
    }
    , $set
}

# Prints the detected setup; returns whether everything needed was found
function Show-Check {
    $ok = $true
    $builtin = @(); $app = @(); $custom = @()
    foreach ($m in $script:ModelList) {
        $s = Get-ModelScale $m; $f = $m; if ($s -ne 4) { $f += " (${s}x)" }
        if ($script:ModelDir[$m] -eq $script:Models) { $builtin += $f }
        elseif ($script:ModelDir[$m] -eq $script:AppModels) { $app += $f }
        else { $custom += $f }
    }
    if (Test-Bundled) { Write-Host "Upscayl binary: $script:Upscayl (bundled)" }
    elseif ($script:Upscayl) { Write-Host "Upscayl binary: $script:Upscayl" }
    elseif (Get-BundleError) { Write-Host "Upscayl binary: NOT WORKING, $(Get-BundleError)"; $ok = $false }
    else { Write-Host 'Upscayl binary: NOT FOUND (install Upscayl or set UPSCAYL_BIN)'; $ok = $false }
    if ($script:Models) { Write-Host "Models folder:  $script:Models"; Write-Host "Models:         $($builtin -join ' ')" }
    else { Write-Host 'Models folder:  NOT FOUND (set UPSCAYL_MODELS)'; $ok = $false }
    Write-Host "                (also ${Nearest}: nearest neighbour for pixel art, no AI or GPU needed)"
    if ($script:AppModels) { Write-Host "Upscayl app:    $script:AppModels"; Write-Host "                $($app -join ' ')" }
    $src = if ($env:UPSCAYL_CUSTOM_MODELS) { 'UPSCAYL_CUSTOM_MODELS' } else { 'Upscayl settings' }
    if (-not $script:CustomModels) { Write-Host "Custom models:  none (choose a folder in Upscayl's settings, or set UPSCAYL_CUSTOM_MODELS)" }
    elseif (-not (Test-Path -LiteralPath $script:CustomModels -PathType Container)) { Write-Host "Custom models:  $script:CustomModels (from $src) is missing" }
    else {
        Write-Host "Custom models:  $script:CustomModels (from $src)"
        Write-Host "                $(if ($custom) { $custom -join ' ' } else { 'no usable .param/.bin pairs' })"
    }
    if ($script:Upscayl -and $script:Models) {
        Write-Host 'GPUs:'
        $gpuList = @(Get-Gpus)
        if (-not $gpuList) {
            Write-Host '  NONE FOUND'
            foreach ($l in ($NoGpuHelp -split "`n")) { Write-Host "  $l" }
            $ok = $false
        } else {
            foreach ($g in $gpuList) {
                Write-Host "  $g"
                if (Test-SoftwareGpu $g) { Write-Host '    (software renderer on the CPU: works, but very slowly)' }
            }
            Write-Host "  default: $(if ($script:UpscaylGpu) { "$script:UpscaylGpu (from Upscayl settings)" } else { 'auto' })"
        }
    }
    if ($script:FFmpeg) {
        $v = (-split ((Lines (Invoke-Tool $script:FFmpeg @('-version') -Capture).Out) | Select-Object -First 1))[2]
        Write-Host "ffmpeg:         $script:FFmpeg ($v)"
        if (-not $script:FFprobe) { Write-Host 'ffprobe:        NOT FOUND (it should be next to ffmpeg)'; $ok = $false }
        foreach ($f in 'gif', 'webp', 'mp4', 'webm', 'avif', 'png', 'jpg') {
            $e = if ($f -eq 'webp') { 'libwebp_anim' } else { $Encoder[$f] }
            if ($script:Encoders.Contains($e)) { Write-Host ('  {0,-14} yes ({1})' -f "$f output:", $e) }
            else { Write-Host ('  {0,-14} no (ffmpeg lacks {1})' -f "$f output:", $e); $ok = $false }
        }
    } else {
        Write-Host 'ffmpeg:         NOT FOUND (install it with "winget install Gyan.FFmpeg", or put ffmpeg.exe and ffprobe.exe next to this script)'
        $ok = $false
    }
    $ok
}

# ffmpeg doesn't pass the last frame's length to libwebp, which then uses the average frame
# length. The delay is a 24-bit millisecond field in each ANMF chunk, 20 bytes after the
# chunk's start, so the last one is set here directly: to the total length minus the frames
# before it, because libwebp merges identical frames and the last one may stand for several.
function Set-WebpLastDelay([string]$File, [long]$TotalMs) {
    $fs = New-Object IO.FileStream($File, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite)
    try {
        $h = New-Object byte[] 8; $d = New-Object byte[] 3
        $off = 12L; $last = -1L; $before = 0L; $prev = 0L
        while ($off + 8 -le $fs.Length) {
            [void]$fs.Seek($off, 'Begin')
            if ($fs.Read($h, 0, 8) -lt 8) { break }
            $len = [long][BitConverter]::ToUInt32($h, 4)
            if ([Text.Encoding]::ASCII.GetString($h, 0, 4) -eq 'ANMF') {
                [void]$fs.Seek($off + 20, 'Begin'); [void]$fs.Read($d, 0, 3)
                $before += $prev; $prev = [long]$d[0] + ([long]$d[1] -shl 8) + ([long]$d[2] -shl 16); $last = $off
            }
            $off += 8 + $len + ($len -band 1)
        }
        if ($last -lt 0) { return }
        $Ms = [math]::Min([math]::Max($TotalMs - $before, 1), 16777215)
        [void]$fs.Seek($last + 20, 'Begin')
        $fs.Write([byte[]]@(($Ms -band 255), (($Ms -shr 8) -band 255), (($Ms -shr 16) -band 255)), 0, 3)
    } finally { $fs.Dispose() }
}

# Pixel grid of enlarged pixel art (see $PixelGridCode): @(sizeX, sizeY, offsetX, offsetY) or
# $null. Looks at up to 6 frames and the middle 480x480 pixels.
function Get-PixelGrid([string]$File, [int]$Stream, [long]$W, [long]$H, [string]$TempDir) {
    $cw = [math]::Min($W, 480); $ch = [math]::Min($H, 480)
    $cx = [math]::Floor(($W - $cw) / 2); $cy = [math]::Floor(($H - $ch) / 2)
    $raw = Join-Path $TempDir ('upscale-gif-grid.' + [IO.Path]::GetRandomFileName() + '.rgb')
    try {
        $r = Invoke-Tool $script:FFmpeg @('-nostdin', '-v', 'error', '-i', $File, '-map', "0:$Stream", '-frames:v', '6',
            '-vf', "crop=${cw}:${ch}:${cx}:${cy}", '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-y', $raw) -Capture
        if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $raw)) { return $null }
        if (-not ('UpscaleGifPixelGrid' -as [type])) { Add-Type -TypeDefinition $PixelGridCode -Language CSharp }
        $g = [UpscaleGifPixelGrid]::Detect([IO.File]::ReadAllBytes($raw), [int]$cw, [int]$ch)
        if (-not $g) { return $null }
        # Offsets relative to the whole picture, rounded like the Linux version's
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $r3 = { param($v) [double]::Parse(([double]$v).ToString('F3', $inv), $inv) }
        $fx = ($g[2] + $cx) % $g[0]; $fy = ($g[3] + $cy) % $g[1]
        # A strip at the picture edge that is nearly a whole cell is one (its edge with the
        # outside can't be seen)
        if ($fx -ge 0.8 * $g[0]) { $fx -= $g[0] }
        if ($fy -ge 0.8 * $g[1]) { $fy -= $g[1] }
        return , @((& $r3 $g[0]), (& $r3 $g[1]), (& $r3 $fx), (& $r3 $fy))
    } catch { return $null }
    finally { Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue }
}

# --- Main --------------------------------------------------------------------------------
function Invoke-Main {
    if ($Help) {
        # PowerShell options ignore case, so -H is -Help here rather than the height
        if ($Path -or $Model -or $Width -or $Format -or $Output) { Fail 'for the output height use -Height (-h shows the help)' }
        Write-Host $Usage; return 0
    }
    if ($Extra) { Fail "unexpected argument '$($Extra[0])' (choose one file at a time)" }

    $script:FFmpeg, $script:FFprobe = Find-FFmpeg
    $script:Upscayl = Find-Upscayl
    $script:Models = if ($script:Upscayl) { Find-Models $script:Upscayl } else { $null }
    # With the bundled upscaler, an installed Upscayl app still contributes its own models
    $script:AppModels = $null
    if ($script:Models -and (Test-Bundled) -and -not $env:UPSCAYL_MODELS) {
        $app = Find-Upscayl -Installed
        if ($app) { $script:AppModels = Find-Models $app }
        if ($script:AppModels -eq $script:Models) { $script:AppModels = $null }
    }
    $settings = Get-UpscaylSettings @('customModelsPath', 'gpuId')
    $script:UpscaylGpu = $settings[1]
    $script:CustomModels = if ($env:UPSCAYL_CUSTOM_MODELS) { $env:UPSCAYL_CUSTOM_MODELS } else { $settings[0] }
    $script:ModelDir = @{ $Nearest = '-' }
    $script:ModelList = New-Object Collections.Generic.List[string]
    if ($script:Models) { Add-Models $script:Models }
    if ($script:AppModels) { Add-Models $script:AppModels }
    if ($script:CustomModels -and (Test-Path -LiteralPath $script:CustomModels -PathType Container)) { Add-Models $script:CustomModels }
    $script:Encoders = Get-Encoders

    if ($Check) { if (Show-Check) { return 0 } else { return 1 } }

    if (-not $script:FFmpeg) { Fail 'ffmpeg not found. Install it (for example "winget install Gyan.FFmpeg") or put ffmpeg.exe and ffprobe.exe next to this script.' }
    if (-not $script:FFprobe) { Fail "found $script:FFmpeg but no ffprobe next to it" }
    $gpu = if ($Gpu) { $Gpu.ToLowerInvariant() } else { '' }
    # The output name's extension picks the format when -f isn't given
    $format = if ($Format) { $Format.ToLowerInvariant() -replace '^jpeg$', 'jpg' } else { '' }
    if ($Output) {
        $ext = [IO.Path]::GetExtension($Output).TrimStart('.').ToLowerInvariant() -replace '^jpeg$', 'jpg'
        if ($ext -match '^(gif|mp4|webm|avif|png|jpg|webp)$') {
            if ($format -and $format -ne $ext) { Fail "output name ends in .$ext but the format is $format" }
            $format = $ext
        }
    }
    if ($gpu -and $gpu -notmatch '^(auto|\d+(,\d+)*)$') { Fail 'GPU must be auto, a number or a list like 0,1 (see -c)' }
    # Check the upscaler and GPU before asking for anything, rather than failing after
    # extracting the frames. Without them only nearest-neighbour scaling is possible.
    $upscalerError = ''
    $script:GpuList = @()
    if ($Model -ne $Nearest) {
        $upscalerError = Get-BundleError
        if (-not $upscalerError -and -not $script:Upscayl) {
            $upscalerError = 'Upscayl not found. Install it from upscayl.org, or set UPSCAYL_BIN to the path of upscayl-bin.exe (run with -c for details).'
        }
        if (-not $upscalerError -and -not $script:Models) { $upscalerError = "found $script:Upscayl but no models folder next to it; set UPSCAYL_MODELS" }
        if (-not $upscalerError) { $script:GpuList = @(Get-Gpus); if (-not $script:GpuList) { $upscalerError = $NoGpuHelp } }
    }
    if ($upscalerError) {
        if ($Model) { Fail "$upscalerError`n(-m $Nearest, nearest neighbour for pixel art, works without it.)" }
        # The settings window then offers only nearest neighbour, and says why
        $script:ModelDir = @{ $Nearest = '-' }; $script:ModelList.Clear()
    }
    if ($script:GpuList) { foreach ($g in @($gpu -split ',' | Where-Object { $_ -and $_ -ne 'auto' })) {
        if (-not @($script:GpuList | Where-Object { ($_ -split ' ', 2)[0] -eq $g })) {
            Fail "there is no GPU $g. Available: $($script:GpuList -join '; ')"
        }
    } }
    $gpuWarn = ''
    if ($script:GpuList -and -not @($script:GpuList | Where-Object { -not (Test-SoftwareGpu $_) })) {
        $gpuWarn = "Only a software Vulkan driver was found ($((($script:GpuList[0]) -split ' ', 2)[1])): upscaling runs on the CPU " +
            "and is very slow. Install your graphics card's driver to use the GPU."
    }
    $quality = $Quality -replace '%$', ''
    if ($quality -and ($quality -notmatch '^\d+$' -or [int]$quality -lt 1 -or [int]$quality -gt 100)) { Fail 'quality must be 1 to 100' }
    $downsampler = if ($Downsampler) { $Downsampler.ToLowerInvariant() } else { '' }
    if ($downsampler -and $Downsamplers -notcontains $downsampler) { Fail "downsampler must be one of: $($Downsamplers -join ' ')" }

    # Remembered choices from the last run
    $confDir = Join-Path ((Get-AppData)) 'upscale-gif'
    $conf = Join-Path $confDir 'settings.json'
    $last = @{ model = ''; format = 'gif'; imageFormat = ''; quality = '80'; downsampler = 'lanczos'; dir = [Environment]::GetFolderPath('MyPictures') }
    if (Test-Path -LiteralPath $conf) {
        try {
            $saved = Get-Content -LiteralPath $conf -Raw | ConvertFrom-Json
            foreach ($k in 'model', 'format', 'imageFormat', 'quality', 'downsampler', 'dir') { if ($saved.PSObject.Properties[$k] -and $saved.$k) { $last[$k] = [string]$saved.$k } }
        } catch { }
    }
    if (-not $script:ModelDir.Contains($last.model)) {
        $last.model = @(@($ModelOrder | Where-Object { $script:ModelDir.Contains($_) }) + @($script:ModelList))[0]
    }

    # --- Choose file ---
    $inputFile = $Path
    if (-not $inputFile) {
        $inputFile = Select-InputFile $last.dir
        if (-not $inputFile) { return 0 }
    }
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) { Fail "file not found: $inputFile" }
    $inputFile = (Resolve-Path -LiteralPath $inputFile).ProviderPath
    $name = Split-Path $inputFile -Leaf

    # --- Probe ---
    # Use the video stream with the most frames: AVIF files also carry a still image (and
    # alpha) as separate streams, and the animation is the longer one.
    $streams = @(Lines (Invoke-Tool $script:FFprobe @('-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=index,nb_frames',
        '-of', 'csv=p=0:s=|', $inputFile) -Capture).Out | ForEach-Object {
        $p = $_.Split('|'); $n = 0L
        if ($p.Count -lt 2 -or -not [long]::TryParse($p[1], [ref]$n)) { $n = 0L }
        New-Object PSObject -Property @{ Index = [int]$p[0]; Frames = $n }
    })
    if (-not $streams) { Fail "no video found in $name" }
    $best = $streams[0]
    foreach ($s in $streams) { if ($s.Frames -gt $best.Frames) { $best = $s } }
    $vidx = $best.Index; $aidx = $null

    # Animated AVIF keeps transparency in a second track with the same frame count
    $brand = ((Invoke-Tool $script:FFprobe @('-v', 'error', '-show_entries', 'format_tags=major_brand', '-of', 'csv=p=0', $inputFile) -Capture).Out).Trim()
    if ($brand -match '^avi[fs]$' -and $best.Frames -gt 0) {
        $alpha = $streams | Where-Object { $_.Index -gt $vidx -and $_.Frames -eq $best.Frames } | Select-Object -First 1
        if ($alpha) { $aidx = $alpha.Index }
    }

    $info = @{}
    foreach ($l in (Lines (Invoke-Tool $script:FFprobe @('-v', 'error', '-select_streams', "$vidx", '-of', 'default=nw=1', '-show_entries',
        'stream=width,height,avg_frame_rate,sample_aspect_ratio:stream_side_data=rotation', $inputFile) -Capture).Out)) {
        $p = $l.Split([char[]]'=', 2)
        if ($p.Count -eq 2 -and -not $info.Contains($p[0])) { $info[$p[0]] = $p[1].Trim() }
    }
    $srcW = 0L; $srcH = 0L
    if (-not ([long]::TryParse([string]$info['width'], [ref]$srcW) -and [long]::TryParse([string]$info['height'], [ref]$srcH)) -or $srcW -le 0 -or $srcH -le 0) {
        Fail "can't read the picture size of $name"
    }
    # Work with the size as displayed: non-square pixels (anamorphic video; viewers ignore
    # the GIF header's aspect field) and phone videos stored sideways with a rotation flag,
    # which ffmpeg turns upright when decoding.
    $formatName = ((Invoke-Tool $script:FFprobe @('-v', 'error', '-show_entries', 'format=format_name', '-of', 'csv=p=0', $inputFile) -Capture).Out).Trim()
    $sarFixed = $false
    if ([string]$info['sample_aspect_ratio'] -match '^(\d+):(\d+)$' -and [long]$Matches[1] -gt 0 -and [long]$Matches[2] -gt 0 -and $formatName -ne 'gif') {
        $srcW = [long][math]::Round($srcW * [long]$Matches[1] / [long]$Matches[2], [MidpointRounding]::AwayFromZero)
        $sarFixed = $Matches[1] -ne $Matches[2]
    }
    $rotation = ToNum ([string]$info['rotation'])
    # Photos keep their orientation (EXIF) on the frame instead of the stream
    if (-not $rotation) {
        $rotation = ToNum ((Lines (Invoke-Tool $script:FFprobe @('-v', 'error', '-select_streams', "$vidx", '-read_intervals', '%+#1',
            '-show_entries', 'frame_side_data=rotation', '-of', 'default=nw=1:nk=1', $inputFile) -Capture).Out) | Select-Object -First 1)
    }
    if ($null -ne $rotation -and ([long]$rotation) % 180 -ne 0) { $t = $srcW; $srcW = $srcH; $srcH = $t }
    $fallback = 0.1
    $rate = ([string]$info['avg_frame_rate']).Split('/')
    if ($rate.Count -eq 2) {
        $num = ToNum $rate[0]; $den = ToNum $rate[1]
        if ($num -gt 0 -and $den -gt 0) { $fallback = $den / $num }
    }

    # Per-frame durations: gap to the next frame's timestamp, else the frame's own
    # duration, else the average frame time. Zero GIF delays play at 0.1 s in browsers.
    $ts = New-Object Collections.Generic.List[object]; $du = New-Object Collections.Generic.List[object]
    foreach ($l in (Lines (Invoke-Tool $script:FFprobe @('-v', 'error', '-select_streams', "$vidx", '-show_entries',
        'frame=best_effort_timestamp_time,duration_time', '-of', 'compact=p=0', $inputFile) -Capture).Out)) {
        $t = $null; $d = $null
        foreach ($kv in $l.Split('|')) {
            $p = $kv.Split([char[]]'=', 2)
            if ($p[0] -eq 'best_effort_timestamp_time') { $t = ToNum $p[1] }
            if ($p[0] -eq 'duration_time') { $d = ToNum $p[1] }
        }
        $ts.Add($t); $du.Add($d)
    }
    $count = $ts.Count
    if ($count -eq 0) { Fail "no frames found in $name" }
    $durations = New-Object 'double[]' $count
    for ($i = 0; $i -lt $count; $i++) {
        $g = 0.0
        if ($i -lt $count - 1 -and $null -ne $ts[$i] -and $null -ne $ts[$i + 1]) { $g = $ts[$i + 1] - $ts[$i] }
        if ($g -le 0) { $g = if ($null -ne $du[$i] -and $du[$i] -gt 0) { $du[$i] } else { $fallback } }
        if ($g -le 0) { $g = 0.1 }
        $durations[$i] = [double](Num $g)
    }
    $totalSec = ($durations | Measure-Object -Sum).Sum
    $total = Num $totalSec 'F1'
    $fps = Num $(if ($totalSec -gt 0) { $count / $totalSec } else { 0 }) 'F1'
    $maxH = $srcH * 4

    # Temporary space: PNG frames compress to roughly half of raw RGBA; original + upscaled copies
    $workRoot = if ($env:UPSCALE_GIF_TEMP) { $env:UPSCALE_GIF_TEMP } else { [IO.Path]::GetTempPath() }
    if (-not (Test-Path -LiteralPath $workRoot -PathType Container)) { Fail "temporary folder not found: $workRoot" }
    $workRoot = (Resolve-Path -LiteralPath $workRoot).ProviderPath
    $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($workRoot))).AvailableFreeSpace
    $spaceFor = { param($s) [long]($count * $srcW * $srcH * 4 * (1 + $s * $s) / 2) }
    # Until the model is chosen, assume a 4x model (the largest)
    $need = & $spaceFor 4
    $spaceNote = "Needs ~$(Human $need) of temporary space ($(Human $free) free)"

    $model = $Model; $width = $Width; $height = $Height
    $x = [char]0xD7   # multiplication sign

    # A single frame is a still image: it can also be saved as png, jpg or webp
    $still = $count -eq 1
    if (-not $still) {
        $Encoder['webp'] = 'libwebp_anim'
        $FmtDesc['webp'] = 'Animated WebP (full colour, keeps transparency, smaller than GIF)'
    }
    if ($still) {
        $formats = $ImageFormats
        $inExt = [IO.Path]::GetExtension($inputFile).TrimStart('.').ToLowerInvariant() -replace '^jpeg$', 'jpg'
        $defaultFormat = if ($last.imageFormat) { $last.imageFormat } elseif ($ImageFormats -contains $inExt) { $inExt } else { 'png' }
        $about = "$srcW $x $srcH, still image"
    } else {
        $formats = $AnimFormats
        $defaultFormat = $last.format
        $about = "$srcW $x $srcH, $count frames, ${total}s, ~$fps fps"
    }
    if ($formats -notcontains $defaultFormat) { $defaultFormat = $formats[0] }

    # --- Settings window (only for what wasn't given on the command line) ---
    if (-not $model -or -not $format -or (-not $width -and -not $height)) {
        $modelValues = @(); $modelItems = @()
        foreach ($m in @($last.model) + @($ModelOrder) + @($Nearest) + @($script:ModelList)) {
            if (-not $m -or -not $script:ModelDir.Contains($m) -or $modelValues -contains $m) { continue }
            if ($m -eq $Nearest) { $item = "$m - $NearestDesc" }
            elseif ($Desc.Contains($m)) { $item = "$m - $($Desc[$m])" }
            else {
                $item = $m; if (Test-Custom $m) { $item += ' - Custom model' }
                $s = Get-ModelScale $m; if ($s -ne 4) { $item += $(if (Test-Custom $m) { ', ' } else { ' - ' }) + "$s$x" }
            }
            $modelValues += $m; $modelItems += $item
        }

        $sizeValues = @(); $sizeItems = @()
        foreach ($f in 4, 3, 2) {
            $sizeValues += (Even ($srcW * $f)); $sizeItems += "$(Even ($srcW * $f)) $x $(Even ($srcH * $f))  ($f$x)"
        }
        foreach ($target in 720, 1080, 1440, 2160) {
            if ($target -le $srcH -or $target -ge $maxH) { continue }
            $w = Even ([math]::Floor($srcW * $target / $srcH))
            $sizeValues += $w; $sizeItems += "$w $x $target  (fits ${target}p)"
        }

        $formatValues = @(); $formatItems = @()
        foreach ($f in @($defaultFormat) + @($formats)) {
            if (-not $Encoder.Contains($f) -or -not $script:Encoders.Contains($Encoder[$f]) -or $formatValues -contains $f) { continue }
            $formatValues += $f; $formatItems += "$f - $($FmtDesc[$f])"
        }
        if (-not $formatValues) { Fail 'this ffmpeg build has none of the needed encoders (run with -c)' }

        # Only offer a GPU choice when there is one to make; the default comes first
        $gpuValues = @(); $gpuItems = @()
        if (-not $gpu -and -not $upscalerError) {
            $gpuList = $script:GpuList
            if ($gpuList.Count -gt 1) {
                $first = if ($script:UpscaylGpu) { $script:UpscaylGpu } else { 'auto' }
                foreach ($g in @($first, 'auto') + @($gpuList | ForEach-Object { ($_ -split ' ', 2)[0] })) {
                    if ($gpuValues -contains $g) { continue }
                    if ($g -eq 'auto') { $item = 'auto - Let Upscayl choose' }
                    else {
                        $item = "$g - Upscayl setting"
                        foreach ($l in $gpuList) { $p = $l -split ' ', 2; if ($p[0] -eq $g) { $item = "$g - $($p[1])" } }
                    }
                    $gpuValues += $g; $gpuItems += $item
                }
            }
        }

        $warn = ''
        if ($count -gt 500) { $warn += "`n$count frames: this will take a while. Long videos are better served by a video upscaler such as Video2X." }
        if ($gpuWarn) { $warn += "`n$gpuWarn" }
        if ($upscalerError) { $warn += "`nOnly nearest-neighbour scaling is available: $upscalerError" }
        if ($need -gt $free) { $warn += "`nNot enough free space in $workRoot." }
        $customHelp = "Custom width: type a width in pixels, e.g. $(Even ($srcW * 3)), to use instead of Output size. " +
            'Height follows the original aspect ratio, and both are rounded to even numbers. ' +
            "Up to $($srcW * 4) px (4$x the original) stays sharp with 4$x models; beyond a model's scale it's stretched. " +
            "$Nearest uses whole multiples (2$x, 3$x...) of the original, rounding down, with no upper limit. Leave empty to use Output size."
        # Only ask for what the command line didn't settle
        $fields = @(); $keys = @()
        $askSize = -not $width -and -not $height
        if (-not $model) { $fields += @{ Label = 'Model'; Items = $modelItems }; $keys += 'model' }
        if ($askSize) {
            $fields += @{ Label = 'Output size'; Items = $sizeItems }; $keys += 'size'
            $fields += @{ Label = 'Custom width in pixels (optional)'; Tip = $customHelp }; $keys += 'custom'
        }
        if (-not $format) { $fields += @{ Label = 'Format'; Items = $formatItems }; $keys += 'format' }
        $qualityValues = @()
        if (-not $quality -and $format -ne 'png') {
            foreach ($q in @([int]$last.quality) + @($Qualities)) { if ($qualityValues -notcontains $q) { $qualityValues += $q } }
            $label = 'Quality (higher is better but larger)'; if ($still) { $label += ', not used for PNG' }
            $fields += @{ Label = $label; Items = @($qualityValues | ForEach-Object { "$_%" }) }; $keys += 'quality'
        }
        $downsamplerValues = @()
        if (-not $downsampler -and $model -ne $Nearest) {
            foreach ($d in @($last.downsampler) + @($Downsamplers)) {
                if ($DownsamplerDesc.Contains($d) -and $downsamplerValues -notcontains $d) { $downsamplerValues += $d }
            }
            $fields += @{ Label = 'Downsampler (for AI models)'
                Items = @($downsamplerValues | ForEach-Object { "$_ - $($DownsamplerDesc[$_])" }) }; $keys += 'downsampler'
        }
        if ($gpuItems) { $fields += @{ Label = 'GPU'; Items = $gpuItems }; $keys += 'gpu' }
        $text = "$name`n$about`n$spaceNote$warn"
        if ($askSize) { $text += "`n`n$customHelp" }
        $result = Show-Settings $text $fields
        if ($null -eq $result) { return 0 }
        $answer = @{}
        for ($i = 0; $i -lt $keys.Count; $i++) { $answer[$keys[$i]] = $result[$i] }

        if (-not $model) { $model = $modelValues[$answer.model] }
        if (-not $format) { $format = $formatValues[$answer.format] }
        if ($gpuItems) { $gpu = $gpuValues[$answer.gpu] }
        if ($qualityValues) { $quality = [string]$qualityValues[$answer.quality] }
        if ($downsamplerValues) { $downsampler = $downsamplerValues[$answer.downsampler] }
        if ($askSize) {
            $custom = [string]$answer.custom -replace '\s', ''
            if ($custom) { $width = $custom } else { $width = [string]$sizeValues[$answer.size] }
        }
    }

    # --- Validate and work out the final size ---
    if (-not $script:ModelDir.Contains($model)) { Fail "unknown model '$model'. Available: $($script:ModelList -join ' ') $Nearest" }
    $nearestMode = $model -eq $Nearest
    if (-not $gpu) { $gpu = if ($script:UpscaylGpu) { $script:UpscaylGpu } else { 'auto' } }
    if ($nearestMode) {
        $scale = 1; $maxW = 0; $need = & $spaceFor 0; $gpuWarn = ''
    } else {
        $scale = Get-ModelScale $model
        $maxW = $srcW * $scale; $need = & $spaceFor $scale
    }
    $spaceNote = "Needs ~$(Human $need) of temporary space ($(Human $free) free)"
    if (-not $format) { $format = $defaultFormat }
    if (-not $quality) { $quality = '80' }
    if (-not $downsampler) { $downsampler = 'lanczos' }
    $q = [int]$quality
    if ($format -notmatch '^(gif|mp4|webm|avif|png|jpg|webp)$') { Fail "unsupported format: $format" }
    if (-not $still -and $format -match '^(png|jpg)$') {
        Fail "$format output is for single images, and $name has $count frames (use gif, webp, webm, avif or mp4)"
    }
    if (-not $script:Encoders.Contains($Encoder[$format])) { Fail "this ffmpeg build can't encode $format (missing $($Encoder[$format]))" }
    if ($width) {
        if ($width -notmatch '^\d+$' -or [long]$width -le 0) { Fail 'width must be a whole number' }
        $outW = Even $width; $outH = Even ([math]::Floor([long]$width * $srcH / $srcW))
    } else {
        if ($height -notmatch '^\d+$' -or [long]$height -le 0) { Fail 'height must be a whole number' }
        $outH = Even $height; $outW = Even ([math]::Floor([long]$height * $srcW / $srcH))
    }
    $outW = [math]::Max($outW, 2); $outH = [math]::Max($outH, 2)
    $pad = ''; $grid = $null; $layer = $null; $frameGrid = $null; $baseW = $srcW; $baseH = $srcH
    if ($nearestMode -and -not $sarFixed) {
        # Pixel art that was already enlarged is first brought back to its own pixels: each grid
        # cell becomes one pixel, of the colour most common in the cell's middle
        $grid = Get-PixelGrid $inputFile $vidx $srcW $srcH $workRoot
        if ($grid) {
            # A last cell 80% inside the picture counts
            $baseW = [long][math]::Floor(($srcW - $grid[2]) / $grid[0] + 0.2); $baseH = [long][math]::Floor(($srcH - $grid[3]) / $grid[1] + 0.2)
            $restorer = New-Object UpscaleGifGridRestore ([int]$srcW), ([int]$srcH), $grid[0], $grid[1], $grid[2], $grid[3], ([int]$baseW), ([int]$baseH)
            # Learn the colours from frames spread over the whole animation (up to 2 million
            # pixels), and whether part of it is on a second grid
            $n = [math]::Min([math]::Max([math]::Floor(2000000 / ($srcW * $srcH)), 1), 60)
            $sel = "select=not(mod(n\,$([math]::Floor(($count + $n - 1) / $n))))"
            $f = if ($null -ne $aidx) { @('-filter_complex', "[0:$vidx][0:$aidx]alphamerge,format=rgba,$sel") } else { @('-map', "0:$vidx", '-vf', $sel, '-pix_fmt', 'rgba') }
            $raw = Join-Path $workRoot ('upscale-gif-learn.' + [IO.Path]::GetRandomFileName() + '.rgba')
            $sample = $null
            try {
                $r = Invoke-Tool $script:FFmpeg (@('-nostdin', '-v', 'error', '-i', $inputFile) + $f + @('-fps_mode', 'passthrough', '-frames:v', "$n",
                    '-f', 'rawvideo', '-pix_fmt', 'rgba', '-y', $raw)) -Capture
                if ($r.Code -eq 0 -and (Test-Path -LiteralPath $raw)) { $sample = [IO.File]::ReadAllBytes($raw); $restorer.Learn($sample) }
            } finally { Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue }
            $enlarged = '{0:0.##}' -f $grid[0]
            $layer = $null; $layerA = 0; $layerB = 1; $frameGrid = $null
            # Rounded like the Linux version's
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $f3 = { param($v) @($v | ForEach-Object { [double]::Parse(([double]$_).ToString('F3', $inv), $inv) }) }
            # "A, B" where grid p by q is A/B of the main one (B up to 8, within 1%), or 0, 1
            $fraction = { param($p, $q)
                $ratio = ($p + $q) / ($grid[0] + $grid[1])
                for ($b = 1; $b -le 8; $b++) {
                    $a = [math]::Floor($ratio * $b + 0.5)
                    if ($a -ge 1 -and [math]::Abs($a / $b - $ratio) -le 0.01 * $ratio) { return @($a, $b) }
                }
                return @(0, 1)
            }
            if ($restorer.Layer) {
                $l = & $f3 $restorer.Layer
                # A clear second grid (with square cells of 1.5 px or more) that isn't the main
                # one: not the same size or a whole multiple of it with lines on the main grid's
                $ratio = $l[0] / $grid[0]; $k = [math]::Floor($ratio + 0.5); $same = $false
                if ($k -ge 1 -and [math]::Abs($ratio - $k) -lt 0.03 * $ratio) {
                    $d = ($l[2] - $grid[2]) / $grid[0]; $d -= [math]::Truncate($d); if ($d -lt 0) { $d += 1 }; if ($d -gt 0.5) { $d = 1 - $d }
                    $same = $d -lt 0.15
                }
                if ($l[4] -ge 0.25 -and $l[5] -ge 0.25 -and $l[0] -ge 1.5 -and [math]::Abs($l[0] - $l[1]) -lt 0.02 * $l[0] -and -not $same) { $layer = $l }
            }
            if ($layer) {
                $ow = [long][math]::Floor(($srcW - $layer[2]) / $layer[0] + 0.2); $oh = [long][math]::Floor(($srcH - $layer[3]) / $layer[1] + 0.2)
                $restorer.SetLayer($layer[0], $layer[1], $layer[2], $layer[3], [int]$ow, [int]$oh)
                # Both layers get whole pixels when the output scale is a multiple of B, where the
                # second grid is A/B of the main one (B up to 8, within 1%): e.g. 3.01/3.49 = 6/7,
                # so at 14x the main pixels are 14 px and the second layer's 12 px
                $layerA, $layerB = & $fraction $layer[0] $layer[1]
                # Around that part, a third grid that fits clearly better marks a frame (a speech
                # bubble's, drawn at another size or position than its text). No grid of whole
                # pixels fits it, so it is kept as drawn in the source (plain nearest neighbour),
                # only without its blur.
                if ($layerA -and $sample) {
                    $restorer.LearnFrame($sample)
                    if ($restorer.Frame) {
                        $frameGrid = & $f3 $restorer.Frame
                        $ow3 = [long][math]::Floor(($srcW - $frameGrid[2]) / $frameGrid[0] + 0.2); $oh3 = [long][math]::Floor(($srcH - $frameGrid[3]) / $frameGrid[1] + 0.2)
                        $restorer.SetFrame($frameGrid[0], $frameGrid[1], $frameGrid[2], $frameGrid[3], [int]$ow3, [int]$oh3)
                    }
                }
                $its = if ($frameGrid) { ' (its frame kept as drawn, without the blur)' } else { '' }
                Write-Host "Note: this looks like pixel art that was enlarged ${enlarged}x, with a part such as text at $('{0:0.##}' -f $layer[0])x; restoring the original pixels of both${its}."
            } else {
                Write-Host "Note: this looks like pixel art that was enlarged ${enlarged}x; restoring its original ${baseW}x${baseH} pixels."
            }
        }
    }
    if ($nearestMode) {
        # Whole multiples only, so every source pixel becomes the same size square. MP4 and
        # WebM need even sizes: an odd one gets a 1-pixel transparent (MP4: black) edge.
        $scale = if ($width) { [math]::Floor($outW / $baseW) } else { [math]::Floor($outH / $baseH) }
        $scale = [long][math]::Max($scale, 1)
        $step = if ($layer -and $layerA) { $layerB } else { 1 }
        # (with a third grid, a multiple of both)
        $scale = [long][math]::Max([math]::Floor($scale / $step) * $step, $step)
        $req = "${outW}x${outH}"
        $outW = $baseW * $scale; $outH = $baseH * $scale
        if ($format -match '^(mp4|webm)$' -and ($outW % 2 -or $outH % 2)) {
            $pad = ",pad=$(Even $outW):$(Even $outH):0:0:black@0"
            $outW = Even $outW; $outH = Even $outH
        }
        if ($req -ne "${outW}x${outH}") {
            $why = if ($step -gt 1) { " (here of ${step}x, so that the layers have whole pixels)" } else { '' }
            Write-Host "Note: nearest neighbour uses whole multiples of ${baseW}x${baseH}${why}: ${outW}x${outH} (${scale}x) instead of $req."
        }
    }
    if ($need -gt $free) { Fail "not enough space in ${workRoot}: $spaceNote" }
    if (-not $nearestMode -and $outW -gt $maxW) { Write-Host "Note: ${outW}px is wider than the model's ${scale}x (${maxW}px); the last step will enlarge." }

    $outFile = $Output
    if (-not $outFile) {
        $outFile = Join-Path (Split-Path $inputFile) ('{0}_{1}x{2}.{3}' -f [IO.Path]::GetFileNameWithoutExtension($inputFile), $outW, $outH, $format)
    }
    $outFile = [IO.Path]::GetFullPath([IO.Path]::Combine((Get-Location).ProviderPath, $outFile))
    $same = if ($OnWindows) { $outFile -ieq $inputFile } else { $outFile -ceq $inputFile }
    if ($same) { Fail 'output would overwrite the input' }
    $outDir = Split-Path $outFile
    if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Fail "folder not found: $outDir" }

    try {
        if (-not (Test-Path -LiteralPath $confDir)) { [void](New-Item -ItemType Directory -Path $confDir) }
        if ($still) { $last.imageFormat = $format } else { $last.format = $format }
        if ($format -ne 'png') { $last.quality = $quality }
        if (-not $nearestMode) { $last.downsampler = $downsampler }
        @{ model = $model; format = $last.format; imageFormat = $last.imageFormat; quality = $last.quality; downsampler = $last.downsampler; dir = (Split-Path $inputFile) } |
            ConvertTo-Json | Set-Content -LiteralPath $conf -Encoding UTF8
    } catch { }

    Write-Host "Input:  $($about -replace " $x ", 'x')"
    $qNote = if ($format -eq 'png') { '' } else { ", quality $q%" }
    if ($nearestMode) {
        if ($format -eq 'webp') { $qNote = ', lossless' }
        Write-Host "Output: ${outW}x${outH} $format$qNote, nearest neighbour (${scale}x)"
    } else {
        Write-Host "Output: ${outW}x${outH} $format$qNote, model $model (${scale}x), $downsampler downsampling, GPU $gpu"
    }
    if ($gpuWarn) { Write-Host "Note: $gpuWarn" }

    # Remove work folders left behind by runs that were killed (e.g. the window was closed)
    Get-ChildItem -LiteralPath $workRoot -Directory -Filter 'upscale-gif.*' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

    $work = Join-Path $workRoot ('upscale-gif.' + [IO.Path]::GetRandomFileName().Replace('.', ''))
    $frames = Join-Path $work 'frames'; $upscaled = Join-Path $work 'upscaled'
    [void](New-Item -ItemType Directory -Path $frames, $upscaled)
    # Nearest neighbour scales the original frames while encoding
    if ($nearestMode) { $upscaled = $frames }
    try {
        if ($Dialogs -and $OnWindows) { Open-ProgressWindow $name }
        # --- Extract (lossless PNG, every frame, transparency kept) ---
        Write-Host 'Extracting frames...'
        $pattern = Join-Path $frames '%06d.png'
        if ($null -ne $aidx) {
            $a = @('-nostdin', '-v', 'error', '-i', $inputFile, '-filter_complex', "[0:$vidx][0:$aidx]alphamerge,format=rgba", '-fps_mode', 'passthrough', $pattern)
        } else {
            $a = @('-nostdin', '-v', 'error', '-i', $inputFile, '-map', "0:$vidx", '-fps_mode', 'passthrough', '-pix_fmt', 'rgba', $pattern)
        }
        $w = New-Watch 0 3 'Reading frame {0} of {1}' $count -Dir $frames
        if ((Invoke-Tool $script:FFmpeg $a -Watch $w).Code -ne 0) { Fail 'ffmpeg could not read the frames' }
        $extracted = @(Get-ChildItem -LiteralPath $frames -Filter '*.png').Count
        if ($extracted -ne $count) {
            Write-Host "Note: decoded $extracted frames (probe saw $count); spacing them evenly over ${total}s."
            if ($extracted -eq 0) { Fail "no frames could be decoded from $name" }
            $d = [double](Num ($totalSec / $extracted))
            $durations = New-Object 'double[]' $extracted
            for ($i = 0; $i -lt $extracted; $i++) { $durations[$i] = $d }
            $count = $extracted
        }

        # --- Restore enlarged pixel art ---
        if ($grid) {
            Write-Host 'Restoring the original pixels...'
            $restored = Join-Path $work 'upscaled'
            $framesIn = Join-Path $frames '%06d.png'
            $job = $restorer
            $layerDir = Join-Path $work 'layer'
            $layerArgs = $null
            if ($layer) {
                [void](New-Item -ItemType Directory -Path $layerDir)
                $layerArgs = (@('-nostdin', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', "${ow}x${oh}", '-i', '-',
                    '-start_number', '1', (Join-Path $layerDir '%06d.png')) | ForEach-Object { Format-Arg $_ }) -join ' '
            }
            $frameDir = Join-Path $work 'frame'
            $frameArgs = $null
            # "width, height, x, y" of a layer at the output size
            $rnd = { param($v) [long][math]::Round($v, [MidpointRounding]::AwayFromZero) }
            $place = { param($g, $n, $m, $la, $lb)
                if ($la) { $t = $scale * $la / $lb; $pw = $n * $t; $ph = $m * $t }
                else { $pw = & $rnd ($n * $g[0] * $scale / $grid[0]); $ph = & $rnd ($m * $g[1] * $scale / $grid[1]) }
                @($pw, $ph, (& $rnd (($g[2] + $n * $g[0] / 2 - $grid[2]) * $scale / $grid[0] - $pw / 2)),
                    (& $rnd (($g[3] + $m * $g[1] / 2 - $grid[3]) * $scale / $grid[1] - $ph / 2)))
            }
            if ($frameGrid) {
                [void](New-Item -ItemType Directory -Path $frameDir)
                # (the source at the output's pixels per source pixel)
                $fw, $fh, $fx3, $fy3 = & $place @(1, 1, 0, 0) $srcW $srcH 0 1
                $frameArgs = (@('-nostdin', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', "${srcW}x${srcH}", '-i', '-',
                    '-start_number', '1', (Join-Path $frameDir '%06d.png')) | ForEach-Object { Format-Arg $_ }) -join ' '
            }
            $job.Start($script:FFmpeg,
                ((@('-nostdin', '-v', 'error', '-i', $framesIn, '-f', 'rawvideo', '-pix_fmt', 'rgba', '-') | ForEach-Object { Format-Arg $_ }) -join ' '),
                ((@('-nostdin', '-v', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', "${baseW}x${baseH}", '-i', '-',
                    '-start_number', '1', (Join-Path $restored '%06d.png')) | ForEach-Object { Format-Arg $_ }) -join ' '), $layerArgs, $frameArgs)
            $script:UpClock = [Diagnostics.Stopwatch]::StartNew()
            $w = New-Watch 3 $(if ($layer) { 42 } else { 50 }) 'Restoring pixels, frame {0} of {1}' $count -Dir $restored -Eta 'eta'
            $next = [DateTime]::MinValue
            try {
                while (-not $job.Done) {
                    if ($script:ProgressWindow) { [Windows.Forms.Application]::DoEvents() }
                    if ($script:Cancelled) { Fail 'cancelled' }
                    if ([DateTime]::UtcNow -ge $next) { Update-Watch $w; $next = [DateTime]::UtcNow.AddMilliseconds(500) }
                    Start-Sleep -Milliseconds 100
                }
            } finally { if (-not $job.Done) { $job.Cancel() } }
            if ($job.Error) { Fail "could not restore the pixel art's original pixels: $($job.Error)" }
            $done = @(Get-ChildItem -LiteralPath $restored -Filter '*.png').Count
            if ($done -ne $count) { Fail "restored $done of $count frames" }
            $upscaled = $restored
            if ($layer) {
                # Both layers at the output size, each with its own whole pixels: the second
                # layer's pixels are its grid size times the output's pixels per source pixel
                $lw, $lh, $lx, $ly = & $place $layer $ow $oh $layerA $layerB
                $combined = Join-Path $work 'combined'
                [void](New-Item -ItemType Directory -Path $combined)
                # A third layer goes between the two
                $in = @('-framerate', '25', '-i', (Join-Path $restored '%06d.png')); $mid = ''; $top = '[a]'
                if ($frameGrid) {
                    $in += @('-framerate', '25', '-i', (Join-Path $frameDir '%06d.png'))
                    $mid = "[1:v]scale=${fw}:${fh}:flags=neighbor[f];[a][f]overlay=x=${fx3}:y=${fy3}:format=rgb[m];"; $top = '[m]'
                }
                $in += @('-framerate', '25', '-i', (Join-Path $layerDir '%06d.png'))
                $a = @('-nostdin', '-v', 'error') + $in + @(
                    '-filter_complex', "[0:v]scale=$($baseW * $scale):$($baseH * $scale):flags=neighbor[a];$mid[$($in.Count / 4 - 1):v]scale=${lw}:${lh}:flags=neighbor[b];$top[b]overlay=x=${lx}:y=${ly}:format=rgb,format=rgba",
                    '-fps_mode', 'passthrough', '-start_number', '1', (Join-Path $combined '%06d.png'))
                $w = New-Watch 42 50 'Adding the second layer, frame {0} of {1}' $count -Dir $combined
                if ((Invoke-Tool $script:FFmpeg $a -Watch $w).Code -ne 0) { Fail 'could not combine the layers' }
                $upscaled = $combined
            }
        }

        # --- Upscale ---
        if (-not $nearestMode) {
            Write-Host "Upscaling $count frames with $model..."
            $log = Join-Path $work 'upscayl.log'
            $a = @('-i', $frames, '-o', $upscaled, '-m', $script:ModelDir[$model], '-n', $model, '-z', "$scale", '-s', "$scale")
            if ($gpu -ne 'auto') { $a += '-g', $gpu }
            # Saving the PNGs is the slow part with Upscayl's default of 2 saving threads; one per
            # CPU thread made upscaling 2-5x faster without using more memory. -j takes one GPU
            # thread count per GPU.
            $procs = if ($gpu -eq 'auto') { '2' } else { (@($gpu.Split(',') | ForEach-Object { '2' })) -join ',' }
            $savers = [math]::Min([math]::Max([Environment]::ProcessorCount, 2), 16)
            $a += '-j', "2:${procs}:$savers", '-f', 'png'
            $script:UpClock = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Tool $script:Upscayl $a -Log $log -Watch (New-Watch 3 85 'Upscaling frame {0} of {1}' $count -Dir $upscaled -Eta 'eta')
            $tail = { (Get-Content -LiteralPath $log -Tail 20) -join "`n" }
            if ($r.Code -ne 0) { Write-Host (& $tail); Fail 'Upscayl failed' }
            $done = @(Get-ChildItem -LiteralPath $upscaled -Filter '*.png').Count
            if ($done -ne $count) { Write-Host (& $tail); Fail "Upscayl produced $done of $count frames" }
        }

        # --- Reassemble with each frame's original timing ---
        # The concat demuxer takes its time base from the images (1/25 s by default), which
        # would round every timestamp to 0.04 s; 1/90000 s is exact for all common frame rates.
        # The last entry's duration is ignored (it lasts one tick), so GIF sets the final delay
        # directly and the other formats end with a one-tick copy of the last frame.
        $sb = New-Object Text.StringBuilder
        $frame = {
            param($n)
            $p = (Join-Path $upscaled ('{0:D6}.png' -f $n)).Replace('\', '/').Replace("'", "'\''")
            [void]$sb.Append("file '$p'`noption framerate 90000`n")
        }
        for ($i = 0; $i -lt $count; $i++) {
            & $frame ($i + 1)
            [void]$sb.Append("duration $(Num $durations[$i])`n")
        }
        if ($format -notmatch '^(gif|webp)$') { & $frame $count }
        $list = Join-Path $work 'frames.txt'
        [IO.File]::WriteAllText($list, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
        $finalDelay = [string][long][math]::Round($durations[$count - 1] * 100, [MidpointRounding]::AwayFromZero)

        Write-Host "Encoding $format..."
        $resize = "scale=${outW}:${outH}:flags=$downsampler,setsar=1"
        $dither = 'sierra2_4a'; $encFrom = 85
        if ($nearestMode) {
            $resize = "scale=$($baseW * $scale):$($baseH * $scale):flags=neighbor,setsar=1$pad"
            # Pixel art keeps its colours: no dithering in GIFs, and lossless WebP (lossy WebP
            # smears colour across the hard edges). Encoding is the rest of the work.
            $dither = 'none'
            if ($grid) { $encFrom = 50 } else { $encFrom = 3; $script:UpClock = [Diagnostics.Stopwatch]::StartNew() }
        }
        $progressFile = Join-Path $work 'progress.txt'
        $in = @('-nostdin', '-v', 'error', '-nostats', '-progress', $progressFile, '-stats_period', '0.5', '-y', '-f', 'concat', '-safe', '0', '-i', $list)
        # The frames start at 0; when the picture starts later than the audio, skip that
        # much audio so they stay in sync
        $first = ToNum ((Lines (Invoke-Tool $script:FFprobe @('-v', 'error', '-select_streams', "$vidx", '-read_intervals', '%+#1',
            '-show_entries', 'frame=best_effort_timestamp_time', '-of', 'default=nw=1:nk=1', $inputFile) -Capture).Out) | Select-Object -First 1)
        $start = ToNum ((Invoke-Tool $script:FFprobe @('-v', 'error', '-show_entries', 'format=start_time', '-of', 'default=nw=1:nk=1', $inputFile) -Capture).Out.Trim())
        $audio = @()
        if ($null -ne $first -and $null -ne $start -and $first - $start -gt 0.001) { $audio += '-ss', (Num ($first - $start)) }
        $audio += '-i', $inputFile, '-map', '0:v', '-map', '1:a:0?'
        # Quality (1-100) on each encoder's own scale; 80 gives the earlier defaults. 100 is
        # lossless for WebP, 256 colours for GIF from 80 up.
        $qmap = { param($a, $b, $lo, $hi) [int][math]::Min($hi, [math]::Max($lo, [math]::Floor($a - $q * $b + 0.5))) }
        $crfX264 = & $qmap 51 0.4375 0 51; $crfVp9 = & $qmap 63 0.5625 0 63; $crfAom = & $qmap 63 0.5375 0 63
        $qJpeg = & $qmap 31 0.3 1 31; $gifColors = & $qmap 0 -3.2 2 256
        $webpOpts = if ($q -lt 100 -and -not $nearestMode) { @('-quality', "$q") } else { @('-lossless', '1', '-quality', '100') }
        $single = if ($still) { @('-frames:v', '1') } else { @() }   # a still AVIF, not a one-frame animation
        switch ($format) {
            'gif' {
                $a = $in + @('-fps_mode', 'vfr', '-filter_complex',
                    "[0:v]$resize,split[a][b];[a]palettegen=reserve_transparent=1:max_colors=$gifColors[p];[b][p]paletteuse=dither=${dither}:alpha_threshold=128",
                    '-loop', '0', '-final_delay', $finalDelay, '-f', 'gif', $outFile)
            }
            'mp4' {
                # H.264 has no alpha: transparent areas become black
                $a = $in + $audio + @('-fps_mode', 'vfr', '-vf', "$resize,format=rgba,premultiply=inplace=1,format=yuv420p",
                    '-c:v', 'libx264', '-preset', 'slow', '-crf', "$crfX264", '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-f', 'mp4', $outFile)
            }
            'webm' {
                $opus = if ($script:Encoders.Contains('libopus')) { 'libopus' } else { 'libvorbis' }
                $a = $in + $audio + @('-fps_mode', 'vfr', '-vf', $resize, '-pix_fmt', 'yuva420p',
                    '-c:v', 'libvpx-vp9', '-crf', "$crfVp9", '-b:v', '0', '-row-mt', '1', '-auto-alt-ref', '0', '-c:a', $opus, '-b:a', '160k', '-f', 'webm', $outFile)
            }
            'avif' {
                # AVIF stores transparency as a second AV1 stream
                $a = $in + @('-fps_mode', 'vfr', '-filter_complex', "[0:v]$resize,format=yuva444p,split[c][a];[a]alphaextract[al]",
                    '-map', '[c]', '-map', '[al]', '-c:v', 'libaom-av1', '-crf', "$crfAom", '-cpu-used', '6', '-row-mt', '1', '-pix_fmt:0', 'yuv444p') + $single + @('-f', 'avif', $outFile)
            }
            'png' {
                $a = $in + @('-vf', $resize, '-frames:v', '1', '-update', '1', '-f', 'image2', $outFile)
            }
            'jpg' {
                # JPEG has no alpha: transparent areas become white
                $a = $in + @('-filter_complex',
                    "color=white:s=${outW}x${outH},format=rgb24[bg];[0:v]$resize[fg];[bg][fg]overlay=shortest=1:format=auto,scale=out_range=full,format=yuv444p",
                    '-c:v', 'mjpeg', '-q:v', "$qJpeg", '-qmin', '1', '-color_range', 'pc', '-frames:v', '1', '-update', '1', '-f', 'image2', $outFile)
            }
            'webp' {
                if ($still) {
                    $a = $in + @('-vf', $resize, '-c:v', 'libwebp') + $webpOpts + @('-frames:v', '1', '-f', 'webp', $outFile)
                } else {
                    $pix = if ($q -lt 100 -and -not $nearestMode) { 'yuva420p' } else { 'bgra' }
                    $a = $in + @('-fps_mode', 'vfr', '-vf', $resize, '-pix_fmt', $pix, '-c:v', 'libwebp_anim') + $webpOpts + @('-loop', '0', '-f', 'webp', $outFile)
                }
            }
        }
        # GIF output only appears at the end (the palette needs every frame first)
        $w = New-Watch $encFrom 100 "Encoding $format, frame {0} of {1}" $count -ProgressFile $progressFile -Eta 'eta-started'
        if ((Invoke-Tool $script:FFmpeg $a -Watch $w).Code -ne 0) { Fail "ffmpeg could not encode $format" }
        if ($format -eq 'webp' -and -not $still) {
            Set-WebpLastDelay $outFile ([long][math]::Round(($durations | Measure-Object -Sum).Sum * 1000, [MidpointRounding]::AwayFromZero))
        }
    } finally {
        Close-Progress
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $msg = "Saved $(Split-Path $outFile -Leaf) ($(Human (Get-Item -LiteralPath $outFile).Length))"
    Write-Host $msg
    if ($Dialogs -and $OnWindows) {
        if ((Show-Message "$msg`n`nShow it in its folder?" 'Information' 'YesNo') -eq 'Yes') {
            Start-Process explorer.exe -ArgumentList "/select,`"$outFile`""
        }
    }
    return 0
}

try {
    $code = Invoke-Main
} catch {
    if ($script:Cancelled) {
        Write-Host 'Cancelled.'
        $code = 130
    } else {
        $msg = $_.Exception.Message
        [Console]::Error.WriteLine("upscale-gif: $msg")
        if ($Dialogs -and $OnWindows) { try { [void](Show-Message $msg 'Error') } catch { } }
        $code = 1
    }
}
exit $code
