@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\scripts\upload-live.ps1" %*
