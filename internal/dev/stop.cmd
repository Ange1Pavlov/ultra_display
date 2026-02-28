@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\stop-display.ps1" %*
