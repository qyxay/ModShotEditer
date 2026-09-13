# Auto-sync: watch RMXP project Data, mirror changes to ModShot patch Data on save.
# Pure ASCII on purpose (avoids cmd / PowerShell encoding issues with CJK).
$ErrorActionPreference = 'Stop'

$src = 'C:\Users\Qyxay\Documents\RPGXP\Project1\Data'
$dst = 'C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\Data'
$exclude = @('Scripts.rxdata', 'xScripts.rxdata')
$sigDir = 'C:\Users\Qyxay\Desktop\onehsot\ModShot-mkxp-z\OneShot\mods\mod\settings'
$sigFile = Join-Path $sigDir 'map_update.signal'

if (-not (Test-Path -LiteralPath $src)) { Write-Host '[ERROR] Source not found:' $src -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }
if (-not (Test-Path -LiteralPath $dst)) { Write-Host '[ERROR] Patch Data not found:' $dst -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }

function Sync-Patch {
    param($Src, $Dst, $Exclude)
    $xf = @()
    foreach ($e in $Exclude) { $xf += '/XF'; $xf += $e }
    & robocopy $Src $Dst '/MIR' $xf '/R:2' '/W:1' '/NJH' '/NJS' '/NP' '/NFL' '/NDL' | Out-Null
    $code = $LASTEXITCODE
    $ts = Get-Date -Format 'HH:mm:ss'
    if ($code -le 7) {
        if ($code -eq 0) { Write-Host ("[{0}] no changes (already in sync)" -f $ts) -ForegroundColor DarkGray }
        else { Write-Host ("[{0}] synced to patch Data (robocopy exit {1})" -f $ts, $code) -ForegroundColor Green }
    } else {
        Write-Host ("[{0}] SYNC ERROR (robocopy exit {1})" -f $ts, $code) -ForegroundColor Red
    }
}

# Write live-update signal: timestamp + changed map ids (line 2), consumed by live_update.rb in-game.
function Write-MapSignal {
    param($FileNames)
    if (-not (Test-Path -LiteralPath $sigDir)) { New-Item -ItemType Directory -Path $sigDir -Force | Out-Null }
    $ids = @()
    foreach ($f in $FileNames) {
        if ($f -match '^Map(\d{3})\.rxdata$') { $ids += [int]$Matches[1] }
    }
    if ($ids.Count -eq 0) { return }
    $content = "{0}`n{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), ($ids -join ',')
    [System.IO.File]::WriteAllText($sigFile, $content)
    Write-Host ("[{0}] live-update signal: maps {1}" -f (Get-Date -Format 'HH:mm:ss'), ($ids -join ',')) -ForegroundColor Cyan
}

Write-Host 'Watching RMXP project Data for saves...' -ForegroundColor Cyan
Write-Host '  source :' $src
Write-Host '  target :' $dst
Write-Host '  excluded:' ($exclude -join ', ')
Write-Host '  Every save triggers a mirror sync after a 3s quiet period.'
Write-Host '  Keep this window open. Close it to stop watching.'
Write-Host ''

# Initial sync (so the patch Data is complete before you start editing)
Sync-Patch $src $dst $exclude

$last = @{}
Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $last[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }

while ($true) {
    Start-Sleep -Milliseconds 800
    $cur = @{}
    Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $cur[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }
    $changedFiles = @{}
    foreach ($k in $cur.Keys) {
        if (-not $last.ContainsKey($k) -or $last[$k][0] -ne $cur[$k][0] -or $last[$k][1] -ne $cur[$k][1]) { $changedFiles[$k] = $true }
    }
    foreach ($k in $last.Keys) { if (-not $cur.ContainsKey($k)) { $changedFiles[$k] = $true } }
    if ($changedFiles.Count -gt 0) {
        Write-Host ("[{0}] RMXP save detected: {1}" -f (Get-Date -Format 'HH:mm:ss'), (($changedFiles.Keys | Sort-Object) -join ', ')) -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        # Re-compare after the quiet period (captures saves made during it)
        $cur2 = @{}
        Get-ChildItem -LiteralPath $src -Filter '*.rxdata' -File | ForEach-Object { $cur2[$_.Name] = @($_.LastWriteTimeUtc.Ticks, $_.Length) }
        foreach ($k in $cur2.Keys) {
            if (-not $last.ContainsKey($k) -or $last[$k][0] -ne $cur2[$k][0] -or $last[$k][1] -ne $cur2[$k][1]) { $changedFiles[$k] = $true }
        }
        foreach ($k in $last.Keys) { if (-not $cur2.ContainsKey($k)) { $changedFiles[$k] = $true } }
        $last = $cur2
        Sync-Patch $src $dst $exclude
        Write-MapSignal $changedFiles.Keys
    }
}
