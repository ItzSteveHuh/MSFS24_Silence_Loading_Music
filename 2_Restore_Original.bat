@echo off
rem Puts the original file back from the backup.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0msfs24_silence_loading_music.ps1" -Restore %*
echo.
pause
