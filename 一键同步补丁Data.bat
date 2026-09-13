@echo off
setlocal
title Sync Patch Data (RMXP Project to ModShot)

set "SRC=C:\Users\Qyxay\Documents\RPGXP\Project1\Data"
set "DST=C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\Data"
set "BAKROOT=C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\backup\data_sync"

echo [1/3] Checking directories...
if not exist "%SRC%" (echo [ERROR] Source Data not found: "%SRC%" & pause & exit /b 1)
if not exist "%DST%" (echo [ERROR] Patch Data not found: "%DST%" & pause & exit /b 1)

echo [2/3] Backing up current patch Data to backup\data_sync\...
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%i"
if exist "%DST%\*.rxdata" robocopy "%DST%" "%BAKROOT%\%STAMP%" /E /NFL /NDL /NJH /NJS >nul

echo [3/3] Syncing project Data to patch Data...
robocopy "%SRC%" "%DST%" /MIR /XF Scripts.rxdata xScripts.rxdata /NJH /NJS /NP

echo [4/4] Writing live-update signal (triggers in-game map reload)...
powershell -NoProfile -Command "$d='%DST%\..\settings'; if(-not(Test-Path -LiteralPath $d)){New-Item -ItemType Directory -Path $d -Force | Out-Null}; [System.IO.File]::WriteAllText((Join-Path $d 'map_update.signal'), ((Get-Date -Format 'yyyyMMdd_HHmmss_fff') + [char]10 + 'ALL'))"

echo.
echo Done. Summary:
echo - All .rxdata files (maps + database) mirrored to patch Data
echo - Skipped: Scripts.rxdata and xScripts.rxdata (scripts use xscripts\ + pack_xscripts.rb)
echo - Old patch data backed up to: "%BAKROOT%\%STAMP%"
echo - Live-update signal written: in-game map reloads within ~0.1s
echo - Test the game with: build\modshot.exe  (NOT RMXP playtest)
echo.
pause
