@echo off
rem Silences the MSFS 2024 loading-screen music (Steam/Store). Close the sim first.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0msfs24_silence_loading_music.ps1" %*
echo.
pause
