@echo off
title Auto Sync Patch Data (RMXP save to ModShot patch)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watch_patch.ps1"
if errorlevel 1 pause
