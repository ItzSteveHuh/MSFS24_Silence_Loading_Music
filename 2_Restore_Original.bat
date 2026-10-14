@echo off
rem Copyright (C) 2026 ItzSteveHuh - GNU GPL v3 or later, see LICENSE
rem Puts the original file back from the backup.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0msfs24_silence_loading_music.ps1" -Restore %*
echo.
pause
