function Invoke-MemoryReclaim {
    [CmdletBinding()]
    param (
        [string[]]$TrimProcesses = @('firefox', 'jetbrains-toolbox', 'SmartConnect', 'TextInputHost', 'explorer'),
        [switch]$DemoteWSL
    )

    Write-Host "`n[1/4] Capturing Initial State..." -ForegroundColor Cyan
    $beforeOS = Get-CimInstance Win32_OperatingSystem
    $beforeFreeMB = [math]::Round($beforeOS.FreePhysicalMemory / 1KB, 2)
    $vmmemBefore = Get-Process vmmemWSL -ErrorAction SilentlyContinue

    if ($vmmemBefore) {
        $vmmemMB = [math]::Round($vmmemBefore.WorkingSet64 / 1MB, 2)
        Write-Host "  -> vmmemWSL current working set: ${vmmemMB} MB" -ForegroundColor DarkGray
    }

    # --- 1. Flush Linux / WSL2 Cache ---
    Write-Host "[2/4] Flushing WSL page cache and compacting memory..." -ForegroundColor Cyan
    if ($vmmemBefore) {
        try {
            wsl -u root sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory" 2>$null
            if ($DemoteWSL -or ($vmmemBefore.PriorityClass -eq 'Normal')) {
                $vmmemBefore.PriorityClass = 'BelowNormal'
                Write-Host "  -> Set vmmemWSL priority to 'BelowNormal' to reduce desktop hitching." -ForegroundColor DarkGray
            }
            Write-Host "  -> WSL cache drop & compaction command dispatched." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to execute drop_caches inside WSL: $_"
        }
    } else {
        Write-Host "  -> WSL is not actively running. Skipping." -ForegroundColor DarkGray
    }

    # --- 2. Trim Idle Windows Processes ---
    Write-Host "[3/4] Trimming working sets on selected Windows processes..." -ForegroundColor Cyan
    $trimmedCount = 0
    foreach ($procName in $TrimProcesses) {
        $targets = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($targets) {
            foreach ($proc in $targets) {
                try {
                    [void]$proc.EmptyWorkingSet()
                    $trimmedCount++
                } catch {
                    # Ignore processes where handle access is restricted
                }
            }
            Write-Host "  -> Trimmed working set for: $procName" -ForegroundColor DarkGray
        }
    }
    Write-Host "  -> Completed working set trim ($trimmedCount process instances touched)." -ForegroundColor Green

    # --- 3. Compute Delta and Output Stats ---
    Write-Host "[4/4] Gathering post-optimization metrics..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2 # Allow OS balloon/reclaim settling

    $afterOS = Get-CimInstance Win32_OperatingSystem
    $afterFreeMB = [math]::Round($afterOS.FreePhysicalMemory / 1KB, 2)
    $totalMemGB  = [math]::Round($afterOS.TotalVisibleMemorySize / 1MB, 2)
    $freedDeltaMB = [math]::Round($afterFreeMB - $beforeFreeMB, 2)

    Write-Host "`n================ MEMORY RECLAIM SUMMARY ================" -ForegroundColor Yellow
    [PSCustomObject]@{
        "Host Total (GB)"  = $totalMemGB
        "Free Before (MB)" = $beforeFreeMB
        "Free After (MB)"  = $afterFreeMB
        "Memory Reclaimed" = "$freedDeltaMB MB"
    } | Format-Table -AutoSize

    # Show top 5 remaining hogs
    Write-Host "Top 5 Working Sets Remaining:" -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 `
        @{Name='PID'; Expression={$_.Id}},
        @{Name='ProcessName'; Expression={$_.Name}},
        @{Name='RAM (MB)'; Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}},
        @{Name='Priority'; Expression={$_.PriorityClass}} |
        Format-Table -AutoSize
}

Set-Alias -Name reclaim -Value Invoke-MemoryReclaim