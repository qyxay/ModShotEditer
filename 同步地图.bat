@echo off
title Map Data Sync (OneShot)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync_maps.ps1"
if errorlevel 1 pause
