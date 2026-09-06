@echo off
chcp 65001 >nul
cd /d "%~dp0.."

echo ========================================
echo   ModShot 运行时设置 - 无框面板
echo ========================================
echo.
echo  正在启动服务器, 面板将自动打开...
echo  关闭此窗口即停止服务器。
echo.

python tools\settings_server.py %*

if errorlevel 1 (
  echo.
  echo 启动失败，请确认已安装 Python。
  pause
)
