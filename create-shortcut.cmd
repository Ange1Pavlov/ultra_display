@echo off
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal\scripts\create-launcher-shortcut.ps1"
echo.
echo Shortcut created.
pause
