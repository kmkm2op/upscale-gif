<#
.SYNOPSIS
Install upscale-gif for the current user (no administrator rights needed).

.DESCRIPTION
Copies upscale-gif, with the upscaler, ffmpeg and models it comes with, to
%LOCALAPPDATA%\Programs\upscale-gif and adds "Upscale GIF" to the Start menu, the desktop
and Explorer's "Send to" menu, plus an entry in Settings > Apps for uninstalling. Without
the bundled programs, it offers to install ffmpeg and Upscayl with winget.

    install.ps1              install or update
    install.ps1 -Uninstall   remove everything again
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$Version = 'dev'
$AppName = 'Upscale GIF'
$Dest = Join-Path $env:LOCALAPPDATA 'Programs\upscale-gif'
$Shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"),
    (Join-Path ([Environment]::GetFolderPath('SendTo')) "$AppName.lnk")
)
$AppsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\upscale-gif'
$PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Add-Type -AssemblyName System.Windows.Forms
function Show-Message([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK') {
    [Windows.Forms.MessageBox]::Show($Text, $AppName, $Buttons, $Icon)
}
function Test-Setup {
    $ErrorActionPreference = 'Continue'   # Windows PowerShell turns captured stderr lines into errors
    $out = & $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dest 'upscale-gif.ps1') -c 2>&1 | Out-String
    New-Object PSObject -Property @{ Ok = ($LASTEXITCODE -eq 0); Text = $out.Trim() }
}
function Install-WithWinget([string]$Id, [string]$What) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return }
    $answer = Show-Message "$What was not found, and upscale-gif needs it.`n`nInstall it now with winget ($Id)?" 'Question' 'YesNo'
    if ($answer -ne 'Yes') { return }
    Write-Host "Installing $Id..."
    & winget install --id $Id --exact --accept-source-agreements --accept-package-agreements
}

if ($Uninstall) {
    # Don't keep the install folder busy as the current directory
    Set-Location -LiteralPath $env:TEMP
    foreach ($s in $Shortcuts) { Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $AppsKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'upscale-gif') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue
    [void](Show-Message "$AppName has been removed.")
    exit 0
}

try {
    $src = $PSScriptRoot
    if (-not (Test-Path -LiteralPath (Join-Path $src 'upscale-gif.ps1'))) {
        throw 'upscale-gif.ps1 was not found next to the installer. Extract the whole zip file first, then run Install.cmd again.'
    }
    [void](New-Item -ItemType Directory -Force -Path $Dest)
    if ((Resolve-Path -LiteralPath $src).ProviderPath -ne (Resolve-Path -LiteralPath $Dest).ProviderPath) {
        # Replace the bundled folders, so files from an older version don't linger
        foreach ($d in 'bin', 'models', 'licenses') {
            $p = Join-Path $Dest $d
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        }
        foreach ($f in 'upscale-gif.ps1', 'install.ps1', 'README.txt', 'LICENSE.txt', 'THIRD-PARTY-NOTICES.txt',
            'upscale-gif.ico', 'bin', 'models', 'licenses') {
            $p = Join-Path $src $f
            if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $Dest -Recurse -Force }
        }
    }
    # Files from a downloaded zip carry the "came from the internet" mark
    Get-ChildItem -LiteralPath $Dest -File -Recurse | Unblock-File

    # Our icon, else Upscayl's when it is installed
    $icon = $null
    if (Test-Path -LiteralPath (Join-Path $Dest 'upscale-gif.ico')) { $icon = (Join-Path $Dest 'upscale-gif.ico') + ',0' }
    $apps = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'Upscayl*' }
    foreach ($a in $apps) {
        if ($icon) { break }
        if ($a.PSObject.Properties['DisplayIcon'] -and $a.DisplayIcon) {
            $file = ($a.DisplayIcon -split ',')[0].Trim('"')
            if (Test-Path -LiteralPath $file) { $icon = "$file,0" }
        }
    }
    if (-not $icon) {
        foreach ($d in "$env:ProgramFiles\Upscayl", "$env:LOCALAPPDATA\Programs\Upscayl") {
            if (Test-Path -LiteralPath "$d\Upscayl.exe") { $icon = "$d\Upscayl.exe,0" }
        }
    }

    $script = Join-Path $Dest 'upscale-gif.ps1'
    $shell = New-Object -ComObject WScript.Shell
    foreach ($s in $Shortcuts) {
        $l = $shell.CreateShortcut($s)
        $l.TargetPath = $PowerShell
        $l.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$script`" -Dialogs"
        $l.WorkingDirectory = $Dest
        $l.Description = 'Upscale an animation or video with Upscayl'
        if ($icon) { $l.IconLocation = $icon }
        $l.Save()
    }

    # Entry in Settings > Apps
    [void](New-Item -Path $AppsKey -Force)
    $values = @{
        DisplayName = $AppName; DisplayVersion = $Version; InstallLocation = $Dest
        UninstallString = "`"$PowerShell`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dest 'install.ps1')`" -Uninstall"
    }
    if ($icon) { $values.DisplayIcon = $icon }
    foreach ($k in $values.Keys) { [void](New-ItemProperty -Path $AppsKey -Name $k -Value $values[$k] -PropertyType String -Force) }
    foreach ($k in 'NoModify', 'NoRepair') { [void](New-ItemProperty -Path $AppsKey -Name $k -Value 1 -PropertyType DWord -Force) }

    # Check what upscale-gif needs, offering to install what is missing
    $check = Test-Setup
    if (-not $check.Ok) {
        if ($check.Text -match 'ffmpeg: +NOT FOUND') { Install-WithWinget 'Gyan.FFmpeg' 'ffmpeg' }
        if ($check.Text -match 'Upscayl binary: NOT FOUND') { Install-WithWinget 'Upscayl.Upscayl' 'Upscayl' }
        $check = Test-Setup
    }

    $how = "Start it from the Start menu or the desktop, drop a file on the desktop icon, or right-click a file and choose Send to > $AppName."
    if ($check.Ok) {
        [void](Show-Message "$AppName is installed.`n`n$how")
    } else {
        [void](Show-Message "$AppName is installed, but something it needs is missing:`n`n$($check.Text)`n`nInstall ffmpeg (winget install Gyan.FFmpeg) and Upscayl (upscayl.org), then try again.`n`n$how" 'Warning')
    }
} catch {
    Write-Host $_.Exception.Message
    [void](Show-Message "Installation failed: $($_.Exception.Message)" 'Error')
    exit 1
}
