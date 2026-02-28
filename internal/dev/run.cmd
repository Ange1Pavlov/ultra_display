@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\src\generate-frame.ps1" %*
