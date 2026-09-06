@echo off
chcp 65001 >nul
cd /d "%~dp0.."

echo ========================================
echo   ModShot 运行时设置
echo ========================================
echo.
echo  正在启动服务器...
start "ModShot Settings Server" /min python tools\settings_server.py 8765 --no-open

REM 等待服务器就绪
timeout /t 2 /nobreak >nul

REM 检测浏览器 (优先 Edge)
set "BROWSER="
if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" set "BROWSER=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if exist "C:\Program Files\Microsoft\Edge\Application\msedge.exe" set "BROWSER=C:\Program Files\Microsoft\Edge\Application\msedge.exe"
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" set "BROWSER=C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" set "BROWSER=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

echo  正在打开面板...
if "%BROWSER%"=="" (
  start http://127.0.0.1:8765/
) else (
  start "" "%BROWSER%" --app=http://127.0.0.1:8765/ --new-window --window-size=820,680
)

echo.
echo  面板已打开。关闭此窗口即停止服务器。
echo.
pause
