@echo off
chcp 65001 >nul
title OneShot 地图编辑器
cd /d "%~dp0"
echo 启动 OneShot 地图编辑器服务...
echo 浏览器将自动打开 http://localhost:8737
echo 关闭本窗口即停止服务
set "RUBY_BIN=C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\runtime\bin"
start "" "http://localhost:8737"
"%RUBY_BIN%\ruby.exe" server.rb
pause
