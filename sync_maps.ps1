# ============================================================
#  sync_maps.ps1 - Map Data Sync (OneShot) - manual + auto watch
#
#  Merged from: watch_patch.ps1 + 同步更改.bat + 自动同步地图更改.bat
#  Pure ASCII on purpose (avoids cmd / PowerShell encoding issues with CJK).
#
#  Source : OneShot\Data        (RMXP project data, Game.rxproj lives here)
#  Target : OneShot\mods\mod\Data  (patch data layer the game loads)
#  Exclude: Scripts.rxdata / xScripts.rxdata (scripts use xscripts\ + pack_xscripts.rb)
#  Signal : after sync writes settings\map_update.signal -> in-game live_update.rb
#           hot-reloads the changed maps.
#
#  Usage:
#    1) Double-click 同步地图.bat -> menu: [1] manual sync  [2] auto watch  [3] quit
#    2) Command line:
#         powershell -NoProfile -ExecutionPolicy Bypass -File sync_maps.ps1 -Mode Manual
#         powershell -NoProfile -ExecutionPolicy Bypass -File sync_maps.ps1 -Mode Watch
# ============================================================

param([ValidateSet('Menu','Manual','Watch')]$Mode = 'Menu')

$ErrorActionPreference = 'Stop'

$src   = 'C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\Data'
$dst   = 'C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\Data'
$bak   = 'C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\backup\data_sync'
$exclude = @('Scripts.rxdata', 'xScripts.rxdata')
$sigDir  = Join-Path $dst '..\settings'
$sigFile = Join-Path $sigDir 'map_update.signal'

if (-not (Test-Path -LiteralPath $src)) { Write-Host "[ERROR] Source not found: $src" -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }
if (-not (Test-Path -LiteralPath $dst)) { Write-Host "[ERROR] Patch Data not found: $dst" -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }

# --- mirror source to patch Data (robocopy /MIR, exclude scripts) ---
function Sync-Robocopy {
    $xf = @()
    foreach ($e in $exclude) { $xf += '/XF'; $xf += $e }
    & robocopy $src $dst '/MIR' $xf '/R:2' '/W:1' '/NJH' '/NJS' '/NP' '/NFL' '/NDL' | Out-Null
    $code = $LASTEXITCODE
    $ts = Get-Date -Format 'HH:mm:ss'
    if ($code -le 7) {
        if ($code -eq 0) { Write-Host ("[{0}] no changes (already in sync)" -f $ts) -ForegroundColor DarkGray }
        else { Write-Host ("[{0}] synced to patch Data (robocopy exit {1})" -f $ts, $code) -ForegroundColor Green }
    } else {
        Write-Host ("[{0}] SYNC ERROR (robocopy exit {1})" -f $ts, $code) -ForegroundColor Red
    }
}

# --- write live-update signal: line1 timestamp, line2 'ALL' or comma-separated map ids ---
function Write-Signal {
    param([string[]]$FileNames)
    if (-not (Test-Path -LiteralPath $sigDir)) { New-Item -ItemType Directory -Path $sigDir -Force | Out-Null }
    if ($FileNames -contains 'ALL') {
        $line2 = 'ALL'
    } else {
        $ids = @()
        foreach ($f in $FileNames) {
            if ($f -match '^Map(\d{3})\.rxdata$') { $ids += [int]$Matches[1] }
        }
        if ($ids.Count -eq 0) { return }
        $line2 = $ids -join ','
    }
    $content = "{0}`n{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $line2
    [System.IO.File]::WriteAllText($sigFile, $content)
    Write-Host ("[{0}] live-update signal: {1}" -f (Get-Date -Format 'HH:mm:ss'), $line2) -ForegroundColor Cyan
}

# --- manual sync once: backup -> mirror -> signal ALL ---
function Sync-Manual {
    Write-Host '[1/3] Backing up current patch Data...'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $bdir = Join-Path $bak $stamp
    $hasData = Get-ChildItem -LiteralPath $dst -Filter '*.rxdata' -File -ErrorAction SilentlyContinue
    if ($hasData) {
        & robocopy $dst $bdir '/E' '/NFL' '/NDL' '/NJH' '/NJS' '/NP' | Out-Null
    }
    Write-Host '[2/3] Mirroring project Data -> patch Data...'
    $xf = @()
    foreach ($e in $exclude) { $xf += '/XF'; $xf += $e }
    & robocopy $src $dst '/MIR' $xf '/NJH' '/NJS' '/NP' | Out-Null
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        Write-Host "[SYNC ERROR robocopy exit $code]" -ForegroundColor Red
    } else {
        Write-Host '[3/3] Writing live-update signal (ALL)...'
        Write-Signal @('ALL')
        Write-Host ('Done. Old patch data backed up to: ' + $bdir) -ForegroundColor Green
        Write-Host 'Test the game with: build\modshot.exe  (NOT RMXP playtest)'
    }
}

# --- auto watch: poll source, sync after a 3s quiet period, write precise signal ---
function Start-Watch {
    Write-Host 'Watching OneShot\Data (RMXP project) for saves...' -ForegroundColor Cyan
    Write-Host '  source :' $src
    Write-Host '  target :' $dst
    Write-Host '  excluded:' ($exclude -join ', ')
    Write-Host '  Every save triggers a mirror sync after a 3s quiet period.'
    Write-Host '  Close this window to stop watching.'
    Write-Host ''

    Sync-Robocopy

    $last = @{}
    Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $last[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }

    while ($true) {
        Start-Sleep -Milliseconds 800
        $cur = @{}
        Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $cur[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }
        $changed = @{}
        foreach ($k in $cur.Keys) {
            if (-not $last.ContainsKey($k) -or $last[$k][0] -ne $cur[$k][0] -or $last[$k][1] -ne $cur[$k][1]) { $changed[$k] = $true }
        }
        foreach ($k in $last.Keys) { if (-not $cur.ContainsKey($k)) { $changed[$k] = $true } }
        if ($changed.Count -gt 0) {
            Write-Host ("[{0}] save detected: {1}" -f (Get-Date -Format 'HH:mm:ss'), (($changed.Keys | Sort-Object) -join ', ')) -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            # re-compare after quiet period (captures saves made during it)
            $cur2 = @{}
            Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $cur2[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }
            foreach ($k in $cur2.Keys) {
                if (-not $last.ContainsKey($k) -or $last[$k][0] -ne $cur2[$k][0] -or $last[$k][1] -ne $cur2[$k][1]) { $changed[$k] = $true }
            }
            foreach ($k in $last.Keys) { if (-not $cur2.ContainsKey($k)) { $changed[$k] = $true } }
            $last = $cur2
            Sync-Robocopy
            Write-Signal $changed.Keys
        }
    }
}

# --- entry ---
if ($Mode -eq 'Manual') { Sync-Manual; exit 0 }
if ($Mode -eq 'Watch')  { Start-Watch;  exit 0 }

# --- interactive menu ---
while ($true) {
    Write-Host ''
    Write-Host '===== Map Data Sync (OneShot) ====='
    Write-Host '  [1] Manual sync once (backup + mirror + signal ALL)'
    Write-Host '  [2] Auto watch (sync on RMXP save, keep window open)'
    Write-Host '  [3] Quit'
    $c = Read-Host 'Your choice'
    switch ($c) {
        '1' { Sync-Manual; break }
        '2' { Start-Watch; break }
        '3' { exit 0 }
        default { Write-Host 'Invalid choice. Enter 1, 2 or 3.' -ForegroundColor Red }
    }
}
