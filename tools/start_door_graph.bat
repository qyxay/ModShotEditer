@echo off
rem Door graph editor launcher (ANSI, no Chinese to avoid codepage issues)
setlocal
cd /d "%~dp0.."

rem start server if not already listening on 8765
powershell -NoProfile -Command "if (-not (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue)) { Start-Process python -ArgumentList 'tools\door_graph_server.py' -WindowStyle Hidden }"

rem wait ~2s for server (ping-based, works in non-interactive cmd)
ping -n 3 127.0.0.1 >nul

rem open Edge in app mode (frameless)
set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
start "" "%EDGE%" --app=http://127.0.0.1:8765 --new-window

endlocal
