# SystemOps - PowerShell Memory Diagnostics & Management

A lightweight native PowerShell utility suite for monitoring Windows system resources, managing active working sets, and taming Hyper-V/WSL2 memory consumption during heavy workloads.

## Features
- **Dual-Unit Metrics:** Reports memory allocations dynamically in both MB and GB.
- **Aggregated Trees:** Groups multi-process footprints (Firefox content processes, background daemons).
- **WSL2 Dynamic Reclaim:** Safely flushes Linux page cache (`drop_caches`) and compacts memory inside WSL2 without killing active processes (e.g. FFmpeg).
- **Process Working Set Trimming:** Forces idle process page releases to disk standby lists.
- **Dual Interfaces:** Interactive CLI menu (`sysops`) and standalone dark-mode WPF GUI (`sysgui`).

## File Structure
- `SystemOps.ps1` - Core diagnostic console dashboard and CLI menu.
- `SystemOpsGUI.ps1` - Standalone WPF dark-theme diagnostic GUI.
- `Get-SystemVitals.ps1` - Fast memory and process tree inspection.
- `Optimize-SystemMemory.ps1` - Automated memory sweep and delta reporting.
