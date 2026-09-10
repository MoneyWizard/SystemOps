function Get-SystemVitals {
    [CmdletBinding()]
    param (
        [int]$TopProcesses = 10
    )

    Clear-Host
    Write-Host "=== SYSTEM HEALTH & MEMORY SNAPSHOT ===" -ForegroundColor Cyan
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

    # --- RAM Summary ---
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemGB  = [math]::Round($totalMemGB - $freeMemGB, 2)
    $pctUsed    = [math]::Round(($usedMemGB / $totalMemGB) * 100, 1)

    Write-Host "RAM Utilization:" -ForegroundColor Yellow
    [PSCustomObject]@{
        "Total (GB)"  = $totalMemGB
        "Used (GB)"   = $usedMemGB
        "Free (GB)"   = $freeMemGB
        "Utilization" = "$pctUsed%"
    } | Format-Table -AutoSize

    # --- Top Memory Consumers ---
    Write-Host "Top $TopProcesses Processes by Working Set:" -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First $TopProcesses `
        @{Name='PID'; Expression={$_.Id}},
        @{Name='ProcessName'; Expression={$_.Name}},
        @{Name='RAM_MB'; Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}},
        @{Name='CPU(s)'; Expression={[math]::Round($_.CPU, 1)}} |
        Format-Table -AutoSize

    # --- Aggregated View by Process Name ---
    Write-Host "Top Grouped App Footprints (e.g. Multi-process browsers):" -ForegroundColor Yellow
    Get-Process | Group-Object Name | Select-Object `
        @{Name='AppName'; Expression={$_.Name}},
        @{Name='Instances'; Expression={$_.Count}},
        @{Name='Total_RAM_MB'; Expression={[math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 2)}} |
        Sort-Object Total_RAM_MB -Descending | Select-Object -First 5 |
        Format-Table -AutoSize

    # --- Virtual & Swap Memory Pressure ---
    $pageFile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($pageFile) {
        Write-Host "Pagefile / Swap Usage:" -ForegroundColor Yellow
        $pageFile | Select-Object `
            @{Name='Location'; Expression={$_.Name}},
            @{Name='Allocated_MB'; Expression={$_.AllocatedBaseSize}},
            @{Name='Current_MB'; Expression={$_.CurrentUsage}},
            @{Name='Peak_MB'; Expression={$_.PeakUsage}} |
            Format-Table -AutoSize
    }
}

# Set an alias so you can just type 'vitals' or 'ram'
Set-Alias -Name vitals -Value Get-SystemVitals
Set-Alias -Name memcheck -Value Get-SystemVitals