@echo off
setlocal

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "APP_CMD=%~f0"
set "PROJECT_ROOT=%~dp0"
set "STARTUP_MODE="
set "NEED_SERVICE_START="
if /I "%~1"=="-Startup" set "STARTUP_MODE=1"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if (-not $isAdmin) { if ('%STARTUP_MODE%' -eq '1') { Start-Process -FilePath '%APP_CMD%' -ArgumentList '-Startup' -Verb RunAs } else { Start-Process -FilePath '%APP_CMD%' -Verb RunAs }; exit 1 }"
if errorlevel 1 exit /b

start "" "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PROJECT_ROOT%internal\scripts\ensure-startup-task.ps1" -Quiet
if defined STARTUP_MODE set "NEED_SERVICE_START=1"
if not defined NEED_SERVICE_START (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$pidFile = Join-Path '%PROJECT_ROOT%' 'logs\display-pids.json'; $running = $false; try { if (Test-Path $pidFile) { $d = Get-Content -Path $pidFile -Raw | ConvertFrom-Json; $g = Get-Process -Id ([int]$d.generatorPid) -ErrorAction SilentlyContinue; $u = Get-Process -Id ([int]$d.uploaderPid) -ErrorAction SilentlyContinue; if ($g -and $u) { $running = $true } } } catch { } if ($running) { exit 0 } else { exit 1 }" >nul 2>&1
    if errorlevel 1 set "NEED_SERVICE_START=1"
)
if defined STARTUP_MODE (
    set "NEED_SERVICE_START=1"
)
if defined NEED_SERVICE_START (
    start "" /wait "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PROJECT_ROOT%internal\scripts\start-display.ps1"
)
start "" "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PROJECT_ROOT%internal\app-ui.ps1"

exit /b
