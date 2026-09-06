@echo off
chcp 65001 >nul
cd /d "%~dp0.."

echo ========================================
echo   ModShot 运行时设置 - 无框面板
echo ========================================
echo.

REM 检测浏览器 (优先 Edge, 其次 Chrome)
set "BROWSER="
if exist "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" set "BROWSER=C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if exist "C:\Program Files\Microsoft\Edge\Application\msedge.exe" set "BROWSER=C:\Program Files\Microsoft\Edge\Application\msedge.exe"
if exist "C:\Program Files\Google\Chrome\Application\chrome.exe" set "BROWSER=C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" set "BROWSER=C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"

if "%BROWSER%"=="" (
  echo [警告] 未检测到 Chrome/Edge, 将使用默认浏览器打开
  echo.
)

REM 启动服务器 (后台)
start "ModShot Settings Server" /min python tools\settings_server.py 8765

REM 等待服务器就绪
timeout /t 2 /nobreak >nul

REM 用 --app 模式打开 (无浏览器框: 无地址栏/标签栏)
if not "%BROWSER%"=="" (
  start "" "%BROWSER%" --app=http://127.0.0.1:8765/ --window-size=760,600 --window-position=center
) else (
  start http://127.0.0.1:8765/
)

echo 面板已打开。关闭面板后请手动关闭服务器窗口。
echo.
pause
