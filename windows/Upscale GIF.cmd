@echo off
rem Run upscale-gif without installing it. Drop a file on this to upscale it.
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0upscale-gif.ps1" -Dialogs %*
