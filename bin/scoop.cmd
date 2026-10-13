@echo off
rem scoop wrapper from scoop-boot for cmd.exe; see scoop.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scoop.ps1" %*
exit /b %ERRORLEVEL%
