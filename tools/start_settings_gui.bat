@echo off
cd /d "%~dp0.."

echo Starting ModShot Settings Server...
start "ModShotServer" /min python tools\settings_server.py 8765 --no-open
timeout /t 2 /nobreak >nul

set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"

if exist "%EDGE%" (
  start "" "%EDGE%" --app=http://127.0.0.1:8765/ --new-window --window-size=820,680
) else (
  start http://127.0.0.1:8765/
)

echo.
echo Panel opened. Close this window to stop the server.
echo.
pause
