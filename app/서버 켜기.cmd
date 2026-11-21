@echo off
setlocal
title PASS PACE - Spring Boot
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0scripts\Start-TeamServer.ps1" %*
if errorlevel 1 (
    pause
    exit /b 1
)
timeout /t 3 /nobreak >nul 2>nul
exit /b 0
