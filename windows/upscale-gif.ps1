<#
.SYNOPSIS
Upscale an animation or video (gif, mp4, webm, avif, webp, apng, mkv, mov...) with Upscayl
and save it as gif, mp4, webm or avif.

.DESCRIPTION
Windows version of upscale-gif. Anything not given on the command line is asked for in a
settings window. Frames are upscaled by the model (2x/3x/4x), then downsampled (Lanczos)
to the chosen size. Every frame keeps its original timing; audio is kept for mp4/webm.

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
Usage: upscale-gif.ps1 [-m model] [-w width | -Height height] [-f format] [-q quality%] [-g gpu] [-o output] [file]
       upscale-gif.ps1 -c    (show detected tools, models and GPUs)
Anything not given on the command line is asked for in a settings window. Formats: gif, mp4,
webm, avif, and for single images png, jpg, webp. -q: 1-100 (default 80; ignored for png).
Frames are upscaled by the model, then downsampled (Lanczos) to the chosen size; every frame
keeps its original timing, and audio is kept for mp4/webm output.
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
# Release packages carry upscayl-bin, ffmpeg and ffprobe in bin\ and the models in models\
$BundleBin = Join-Path $PSScriptRoot 'bin'
$FmtDesc = @{
    gif = 'GIF'; webm = 'WebM (VP9, keeps transparency and audio)'
    avif = 'AVIF (AV1, keeps transparency)'; mp4 = 'MP4 (H.264, keeps audio, no transparency)'
    png = 'PNG (lossless, keeps transparency)'; jpg = 'JPEG (small, no transparency)'; webp = 'WebP (keeps transparency)'
}
$Encoder = @{ gif = 'gif'; mp4 = 'libx264'; webm = 'libvpx-vp9'; avif = 'libaom-av1'; png = 'png'; jpg = 'mjpeg'; webp = 'libwebp' }
$AnimFormats = 'gif', 'webm', 'avif', 'mp4'
$ImageFormats = 'png', 'jpg', 'webp', 'avif', 'gif'   # offered when the input is a single image
$Qualities = 100, 95, 90, 85, 80, 75, 70, 60, 50, 40, 30, 20, 10

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
    if (-not $Installed) { $candidates += (Join-Path $BundleBin 'upscayl-bin.exe'), (Join-Path $BundleBin 'upscayl-bin') }
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
    else { Write-Host 'Upscayl binary: NOT FOUND (install Upscayl or set UPSCAYL_BIN)'; $ok = $false }
    if ($script:Models) { Write-Host "Models folder:  $script:Models"; Write-Host "Models:         $($builtin -join ' ')" }
    else { Write-Host 'Models folder:  NOT FOUND (set UPSCAYL_MODELS)'; $ok = $false }
    if ($script:AppModels) { Write-Host "Upscayl app:    $script:AppModels"; Write-Host "                $($app -join ' ')" }
    $src = if ($env:UPSCAYL_CUSTOM_MODELS) { 'UPSCAYL_CUSTOM_MODELS' } else { 'Upscayl settings' }
    if (-not $script:CustomModels) { Write-Host "Custom models:  none (choose a folder in Upscayl's settings, or set UPSCAYL_CUSTOM_MODELS)" }
    elseif (-not (Test-Path -LiteralPath $script:CustomModels -PathType Container)) { Write-Host "Custom models:  $script:CustomModels (from $src) is missing" }
    else {
        Write-Host "Custom models:  $script:CustomModels (from $src)"
        Write-Host "                $(if ($custom) { $custom -join ' ' } else { 'no usable .param/.bin pairs' })"
    }
    if ($script:Upscayl) {
        Write-Host 'GPUs:'
        foreach ($g in (Get-Gpus)) { Write-Host "  $g" }
        Write-Host "  default: $(if ($script:UpscaylGpu) { "$script:UpscaylGpu (from Upscayl settings)" } else { 'auto' })"
    }
    if ($script:FFmpeg) {
        $v = (-split ((Lines (Invoke-Tool $script:FFmpeg @('-version') -Capture).Out) | Select-Object -First 1))[2]
        Write-Host "ffmpeg:         $script:FFmpeg ($v)"
        if (-not $script:FFprobe) { Write-Host 'ffprobe:        NOT FOUND (it should be next to ffmpeg)'; $ok = $false }
        foreach ($f in 'gif', 'mp4', 'webm', 'avif', 'png', 'jpg', 'webp') {
            $e = $Encoder[$f]
            if ($script:Encoders.Contains($e)) { Write-Host ('  {0,-14} yes ({1})' -f "$f output:", $e) }
            else { Write-Host ('  {0,-14} no (ffmpeg lacks {1})' -f "$f output:", $e); $ok = $false }
        }
    } else {
        Write-Host 'ffmpeg:         NOT FOUND (install it with "winget install Gyan.FFmpeg", or put ffmpeg.exe and ffprobe.exe next to this script)'
        $ok = $false
    }
    $ok
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
    $script:ModelDir = @{}
    $script:ModelList = New-Object Collections.Generic.List[string]
    if ($script:Models) { Add-Models $script:Models }
    if ($script:AppModels) { Add-Models $script:AppModels }
    if ($script:CustomModels -and (Test-Path -LiteralPath $script:CustomModels -PathType Container)) { Add-Models $script:CustomModels }
    $script:Encoders = Get-Encoders

    if ($Check) { if (Show-Check) { return 0 } else { return 1 } }

    if (-not $script:FFmpeg) { Fail 'ffmpeg not found. Install it (for example "winget install Gyan.FFmpeg") or put ffmpeg.exe and ffprobe.exe next to this script.' }
    if (-not $script:FFprobe) { Fail "found $script:FFmpeg but no ffprobe next to it" }
    if (-not $script:Upscayl) { Fail 'Upscayl not found. Install it from upscayl.org, or set UPSCAYL_BIN to the path of upscayl-bin.exe (run with -c for details).' }
    if (-not $script:Models) { Fail "found $script:Upscayl but no models folder next to it; set UPSCAYL_MODELS" }
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
    $quality = $Quality -replace '%$', ''
    if ($quality -and ($quality -notmatch '^\d+$' -or [int]$quality -lt 1 -or [int]$quality -gt 100)) { Fail 'quality must be 1 to 100' }

    # Remembered choices from the last run
    $confDir = Join-Path ((Get-AppData)) 'upscale-gif'
    $conf = Join-Path $confDir 'settings.json'
    $last = @{ model = ''; format = 'gif'; imageFormat = ''; quality = '80'; dir = [Environment]::GetFolderPath('MyPictures') }
    if (Test-Path -LiteralPath $conf) {
        try {
            $saved = Get-Content -LiteralPath $conf -Raw | ConvertFrom-Json
            foreach ($k in 'model', 'format', 'imageFormat', 'quality', 'dir') { if ($saved.PSObject.Properties[$k] -and $saved.$k) { $last[$k] = [string]$saved.$k } }
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
    if ([string]$info['sample_aspect_ratio'] -match '^(\d+):(\d+)$' -and [long]$Matches[1] -gt 0 -and [long]$Matches[2] -gt 0 -and $formatName -ne 'gif') {
        $srcW = [long][math]::Round($srcW * [long]$Matches[1] / [long]$Matches[2], [MidpointRounding]::AwayFromZero)
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
        foreach ($m in @($last.model) + @($ModelOrder) + @($script:ModelList)) {
            if (-not $m -or -not $script:ModelDir.Contains($m) -or $modelValues -contains $m) { continue }
            if ($Desc.Contains($m)) { $item = "$m - $($Desc[$m])" }
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
        if (-not $gpu) {
            $gpuList = @(Get-Gpus)
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
        if ($count -gt 500) { $warn += "`n$count frames: this will take a while." }
        if ($need -gt $free) { $warn += "`nNot enough free space in $workRoot." }
        $customHelp = "Custom width: type a width in pixels, e.g. $(Even ($srcW * 3)), to use instead of Output size. " +
            'Height follows the original aspect ratio, and both are rounded to even numbers. ' +
            "Up to $($srcW * 4) px (the model's 4$x) stays sharp; larger values are stretched. Leave empty to use Output size."
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
        if ($askSize) {
            $custom = [string]$answer.custom -replace '\s', ''
            if ($custom) { $width = $custom } else { $width = [string]$sizeValues[$answer.size] }
        }
    }

    # --- Validate and work out the final size ---
    if (-not $script:ModelDir.Contains($model)) { Fail "unknown model '$model'. Available: $($script:ModelList -join ' ')" }
    if (-not $gpu) { $gpu = if ($script:UpscaylGpu) { $script:UpscaylGpu } else { 'auto' } }
    $scale = Get-ModelScale $model
    $maxW = $srcW * $scale; $need = & $spaceFor $scale
    $spaceNote = "Needs ~$(Human $need) of temporary space ($(Human $free) free)"
    if (-not $format) { $format = $defaultFormat }
    if (-not $quality) { $quality = '80' }
    $q = [int]$quality
    if ($format -notmatch '^(gif|mp4|webm|avif|png|jpg|webp)$') { Fail "unsupported format: $format" }
    if (-not $still -and $format -match '^(png|jpg|webp)$') {
        Fail "$format output is for single images, and $name has $count frames (use gif, webm, avif or mp4)"
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
    if ($need -gt $free) { Fail "not enough space in ${workRoot}: $spaceNote" }
    if ($outW -gt $maxW) { Write-Host "Note: ${outW}px is wider than the model's ${scale}x (${maxW}px); the last step will enlarge." }

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
        @{ model = $model; format = $last.format; imageFormat = $last.imageFormat; quality = $last.quality; dir = (Split-Path $inputFile) } |
            ConvertTo-Json | Set-Content -LiteralPath $conf -Encoding UTF8
    } catch { }

    Write-Host "Input:  $($about -replace " $x ", 'x')"
    $qNote = if ($format -eq 'png') { '' } else { ", quality $q%" }
    Write-Host "Output: ${outW}x${outH} $format$qNote, model $model (${scale}x), GPU $gpu"

    # Remove work folders left behind by runs that were killed (e.g. the window was closed)
    Get-ChildItem -LiteralPath $workRoot -Directory -Filter 'upscale-gif.*' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

    $work = Join-Path $workRoot ('upscale-gif.' + [IO.Path]::GetRandomFileName().Replace('.', ''))
    $frames = Join-Path $work 'frames'; $upscaled = Join-Path $work 'upscaled'
    [void](New-Item -ItemType Directory -Path $frames, $upscaled)
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

        # --- Upscale ---
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
        if ($format -ne 'gif') { & $frame $count }
        $list = Join-Path $work 'frames.txt'
        [IO.File]::WriteAllText($list, $sb.ToString(), (New-Object Text.UTF8Encoding $false))
        $finalDelay = [string][long][math]::Round($durations[$count - 1] * 100, [MidpointRounding]::AwayFromZero)

        Write-Host "Encoding $format..."
        $resize = "scale=${outW}:${outH}:flags=lanczos,setsar=1"
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
        $webpOpts = if ($q -lt 100) { @('-quality', "$q") } else { @('-lossless', '1', '-quality', '100') }
        $single = if ($still) { @('-frames:v', '1') } else { @() }   # a still AVIF, not a one-frame animation
        switch ($format) {
            'gif' {
                $a = $in + @('-fps_mode', 'vfr', '-filter_complex',
                    "[0:v]$resize,split[a][b];[a]palettegen=reserve_transparent=1:max_colors=$gifColors[p];[b][p]paletteuse=dither=sierra2_4a:alpha_threshold=128",
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
                $a = $in + @('-vf', $resize, '-c:v', 'libwebp') + $webpOpts + @('-frames:v', '1', '-f', 'webp', $outFile)
            }
        }
        # GIF output only appears at the end (the palette needs every frame first)
        $w = New-Watch 85 100 "Encoding $format, frame {0} of {1}" $count -ProgressFile $progressFile -Eta 'eta-started'
        if ((Invoke-Tool $script:FFmpeg $a -Watch $w).Code -ne 0) { Fail "ffmpeg could not encode $format" }
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
