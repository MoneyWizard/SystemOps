function Format-DualMem {
    param([double]$Bytes)
    $mb = [math]::Round($Bytes / 1MB, 2)
    $gb = [math]::Round($Bytes / 1GB, 2)
    return "${mb} MB (${gb} GB)"
}

function Show-DashboardHeader {
    Clear-Host
    $os = Get-CimInstance Win32_OperatingSystem
    $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
    $freeBytes  = [double]$os.FreePhysicalMemory * 1KB
    $usedBytes  = $totalBytes - $freeBytes
    $pctUsed    = [math]::Round(($usedBytes / $totalBytes) * 100, 1)

    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "                    SYSTEMOPS DIAGNOSTIC CONSOLE                 " -ForegroundColor White
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "  Total Memory : $(Format-DualMem $totalBytes)"
    Write-Host "  Used Memory  : $(Format-DualMem $usedBytes) [$pctUsed%]" -ForegroundColor $(if ($pctUsed -gt 85) { 'Red' } elseif ($pctUsed -gt 70) { 'Yellow' } else { 'Green' })
    Write-Host "  Free Memory  : $(Format-DualMem $freeBytes)"
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
}

function Get-TopConsumers {
    param([int]$Count = 10)
    Write-Host "`n[ TOP $Count WORKING SET PROCESSES ]" -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $Count `
        @{Name='PID'; Expression={$_.Id}},
        @{Name='ProcessName'; Expression={$_.Name}},
        @{Name='RAM (MB / GB)'; Expression={ Format-DualMem $_.WorkingSet64 }},
        @{Name='Priority'; Expression={$_.PriorityClass}} |
        Format-Table -AutoSize
}

function Invoke-TrimWorkingSets {
    param(
        [string[]]$Targets = @('firefox', 'tailscaled', 'jetbrains-toolbox', 'SmartConnect', 'TextInputHost', 'explorer')
    )
    Write-Host "`n[!] Forcing working set page trim on targets: $($Targets -join ', ')..." -ForegroundColor Cyan
    $trimmed = 0
    foreach ($name in $Targets) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                try {
                    [void]$p.EmptyWorkingSet()
                    $trimmed++
                } catch {}
            }
        }
    }
    Write-Host "    Successfully trimmed $trimmed instances." -ForegroundColor Green
}

function Invoke-FlushWSLCache {
    Write-Host "`n[!] Flushing WSL page caches & compacting memory..." -ForegroundColor Cyan
    $wslProc = Get-Process vmmemWSL -ErrorAction SilentlyContinue
    if (-not $wslProc) {
        Write-Host "    vmmemWSL is not currently running." -ForegroundColor DarkYellow
        return
    }

    $beforeBytes = $wslProc.WorkingSet64
    wsl -u root sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory" 2>$null
    Start-Sleep -Seconds 1
    
    $wslProc.Refresh()
    $afterBytes = $wslProc.WorkingSet64
    $diffMB = [math]::Round(($beforeBytes - $afterBytes) / 1MB, 2)

    Write-Host "    WSL cache dropped. Working set delta: $diffMB MB." -ForegroundColor Green
}

function Set-WSLPriority {
    Write-Host "`n[!] Adjusting vmmemWSL scheduling priority..." -ForegroundColor Cyan
    $wslProc = Get-Process vmmemWSL -ErrorAction SilentlyContinue
    if ($wslProc) {
        $wslProc.PriorityClass = 'BelowNormal'
        Write-Host "    vmmemWSL priority switched to 'BelowNormal'." -ForegroundColor Green
    } else {
        Write-Host "    vmmemWSL is not running." -ForegroundColor DarkYellow
    }
}

function Inspect-TextInputHost {
    Write-Host "`n[ INSPECT: TextInputHost ]" -ForegroundColor Yellow
    $procs = Get-Process TextInputHost -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Select-Object `
            @{Name='PID'; Expression={$_.Id}},
            @{Name='ProcessName'; Expression={$_.Name}},
            @{Name='RAM (MB / GB)'; Expression={ Format-DualMem $_.WorkingSet64 }},
            @{Name='Priority'; Expression={$_.PriorityClass}} |
            Format-Table -AutoSize
    } else {
        Write-Host "    TextInputHost is currently idle or not found." -ForegroundColor DarkGray
    }
}

function Start-SystemOps {
    do {
        Show-DashboardHeader
        Write-Host " [1] View Top 10 Memory Hogs (MB & GB)"
        Write-Host " [2] Inspect TextInputHost Details"
        Write-Host " [3] Trim Idle Apps (Firefox, Tailscale, Toolbox, SmartConnect, TextInputHost)"
        Write-Host " [4] Drop WSL2 Cache (Safe Live Flush)"
        Write-Host " [5] Set WSL2 to 'BelowNormal' Priority (Stops desktop hitching)"
        Write-Host " [6] Run Full Quick-Fix (Flush WSL + Trim Apps + Demote Priority)"
        Write-Host " [R] Refresh Dashboard Stats"
        Write-Host " [Q] Exit"
        Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

        $choice = Read-Host "Select an action (1-6, R, Q)"
        switch ($choice.ToUpper()) {
            '1' { Get-TopConsumers -Count 10; Read-Host "`nPress Enter to continue..." }
            '2' { Inspect-TextInputHost; Read-Host "`nPress Enter to continue..." }
            '3' { Invoke-TrimWorkingSets; Start-Sleep -Seconds 1 }
            '4' { Invoke-FlushWSLCache; Start-Sleep -Seconds 1 }
            '5' { Set-WSLPriority; Start-Sleep -Seconds 1 }
            '6' {
                Invoke-FlushWSLCache
                Invoke-TrimWorkingSets
                Set-WSLPriority
                Start-Sleep -Seconds 2
            }
            'R' { continue }
            'Q' { Write-Host "`nExiting SystemOps.`n" -ForegroundColor Green; break }
            Default { Write-Host "`nInvalid option." -ForegroundColor Red; Start-Sleep -Milliseconds 750 }
        }
    } while ($true)
}
