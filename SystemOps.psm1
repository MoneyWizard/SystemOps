# Dot-source existing function files into the module scope
$moduleRoot = $PSScriptRoot
. (Join-Path $moduleRoot "Get-SystemVitals.ps1")
. (Join-Path $moduleRoot "Optimize-SystemMemory.ps1")
. (Join-Path $moduleRoot "SystemOps.ps1")

# Define module aliases
Set-Alias -Name sysops   -Value Start-SystemOps
Set-Alias -Name vitals   -Value Get-SystemVitals
Set-Alias -Name reclaim  -Value Invoke-MemoryReclaim

# Export public symbols
Export-ModuleMember -Function Start-SystemOps, Get-SystemVitals, Invoke-MemoryReclaim -Alias sysops, vitals, reclaim
