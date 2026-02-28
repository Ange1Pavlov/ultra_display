@echo off
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
start "" "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0internal\app-ui.ps1"
exit /b
