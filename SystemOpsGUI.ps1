Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# --- Helper Functions ---
function Format-DualMem {
    param([double]$Bytes)
    $mb = [math]::Round($Bytes / 1MB, 2)
    $gb = [math]::Round($Bytes / 1GB, 2)
    return "${mb} MB (${gb} GB)"
}

# --- XAML Interface Definition ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="SystemOps Memory Diagnostics" Height="620" Width="780"
        Background="#1E1E1E" Foreground="#ECECEC" WindowStartupLocation="CenterScreen">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Header / Vitals -->
        <Border Grid.Row="0" Background="#252526" CornerRadius="6" Padding="12" Margin="0,0,0,12">
            <StackPanel>
                <TextBlock Text="SYSTEM MEMORY VITALS" FontWeight="Bold" FontSize="14" Foreground="#007ACC" Margin="0,0,0,6"/>
                <TextBlock x:Name="TxtVitals" Text="Click 'Refresh Stats' to scan memory..." FontFamily="Consolas" FontSize="13"/>
            </StackPanel>
        </Border>

        <!-- Action Buttons: Diagnostic Readouts -->
        <GroupBox Grid.Row="1" Header=" Diagnostic Queries (Read-Only) " Foreground="#9CDCFE" Margin="0,0,0,8">
            <WrapPanel Margin="5">
                <Button x:Name="BtnRefresh" Content="Refresh Vitals" Width="140" Height="30" Margin="4" Background="#333333" Foreground="White"/>
                <Button x:Name="BtnTop10" Content="Top 10 Hogs" Width="140" Height="30" Margin="4" Background="#333333" Foreground="White"/>
                <Button x:Name="BtnTextInput" Content="Inspect TextInputHost" Width="150" Height="30" Margin="4" Background="#333333" Foreground="White"/>
            </WrapPanel>
        </GroupBox>

        <!-- Action Buttons: System Operations -->
        <GroupBox Grid.Row="2" Header=" Remediation Actions (Click to Run) " Foreground="#4EC9B0" Margin="0,0,0,10">
            <WrapPanel Margin="5">
                <Button x:Name="BtnFlushWSL" Content="Flush WSL Cache" Width="140" Height="30" Margin="4" Background="#2D4F38" Foreground="White"/>
                <Button x:Name="BtnTrimApps" Content="Trim Idle Apps" Width="140" Height="30" Margin="4" Background="#2D4F38" Foreground="White"/>
                <Button x:Name="BtnWSLPriority" Content="Demote WSL Priority" Width="150" Height="30" Margin="4" Background="#2D4F38" Foreground="White"/>
                <Button x:Name="BtnFullFix" Content="Run Full Quick-Fix" Width="140" Height="30" Margin="4" Background="#5A3D28" Foreground="White" FontWeight="Bold"/>
            </WrapPanel>
        </GroupBox>

        <!-- Console Log Output -->
        <Border Grid.Row="3" Background="#111111" CornerRadius="4" BorderBrush="#333333" BorderThickness="1">
            <TextBox x:Name="TxtOutput" Background="Transparent" Foreground="#D4D4D4" 
                     FontFamily="Consolas" FontSize="12" IsReadOnly="True" 
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     TextWrapping="NoWrap" Margin="8" BorderThickness="0"/>
        </Border>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Map Elements
$txtVitals     = $window.FindName("TxtVitals")
$txtOutput     = $window.FindName("TxtOutput")
$btnRefresh    = $window.FindName("BtnRefresh")
$btnTop10      = $window.FindName("BtnTop10")
$btnTextInput  = $window.FindName("BtnTextInput")
$btnFlushWSL   = $window.FindName("BtnFlushWSL")
$btnTrimApps   = $window.FindName("BtnTrimApps")
$btnWSLPriority= $window.FindName("BtnWSLPriority")
$btnFullFix    = $window.FindName("BtnFullFix")

function Log-Output {
    param([string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $txtOutput.AppendText("[$timestamp] $Message`r`n")
    $txtOutput.ScrollToEnd()
}

function Update-Vitals {
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $free  = [double]$os.FreePhysicalMemory * 1KB
    $used  = $total - $free
    $pct   = [math]::Round(($used / $total) * 100, 1)

    $txtVitals.Text = "Total: $(Format-DualMem $total)  |  Used: $(Format-DualMem $used) [$pct%]  |  Free: $(Format-DualMem $free)"
    Log-Output "Vitals refreshed."
}

# --- Event Handlers (Only execute when clicked) ---

$btnRefresh.Add_Click({ Update-Vitals })

$btnTop10.Add_Click({
    Log-Output "Fetching Top 10 processes by working set..."
    $data = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 `
        @{Name='PID'; Expression={$_.Id}},
        @{Name='Process'; Expression={$_.Name}},
        @{Name='RAM (MB / GB)'; Expression={ Format-DualMem $_.WorkingSet64 }},
        @{Name='Priority'; Expression={$_.PriorityClass}} |
        Format-Table -AutoSize | Out-String
    $txtOutput.AppendText("$data`r`n")
    $txtOutput.ScrollToEnd()
})

$btnTextInput.Add_Click({
    Log-Output "Inspecting TextInputHost..."
    $p = Get-Process TextInputHost -ErrorAction SilentlyContinue
    if ($p) {
        $info = $p | Select-Object `
            @{Name='PID'; Expression={$_.Id}},
            @{Name='Process'; Expression={$_.Name}},
            @{Name='RAM (MB / GB)'; Expression={ Format-DualMem $_.WorkingSet64 }},
            @{Name='Priority'; Expression={$_.PriorityClass}} |
            Format-Table -AutoSize | Out-String
        $txtOutput.AppendText("$info`r`n")
    } else {
        Log-Output "TextInputHost is not running or has no active footprint."
    }
})

$btnFlushWSL.Add_Click({
    Log-Output "Triggering WSL drop_caches & compact_memory..."
    $wsl = Get-Process vmmemWSL -ErrorAction SilentlyContinue
    if ($wsl) {
        $before = $wsl.WorkingSet64
        wsl -u root sh -c "sync; echo 3 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory" 2>$null
        Start-Sleep -Milliseconds 500
        $wsl.Refresh()
        $reclaimed = [math]::Round(($before - $wsl.WorkingSet64) / 1MB, 2)
        Log-Output "WSL cache flushed. Reclaimed approximately: $reclaimed MB."
    } else {
        Log-Output "vmmemWSL is not active."
    }
    Update-Vitals
})

$btnTrimApps.Add_Click({
    Log-Output "Trimming working sets on common memory hogs..."
    $targets = @('firefox', 'jetbrains-toolbox', 'SmartConnect', 'TextInputHost', 'explorer')
    $count = 0
    foreach ($t in $targets) {
        Get-Process -Name $t -ErrorAction SilentlyContinue | ForEach-Object {
            try { [void]$_.EmptyWorkingSet(); $count++ } catch {}
        }
    }
    Log-Output "Trimmed $count target process instances."
    Update-Vitals
})

$btnWSLPriority.Add_Click({
    $wsl = Get-Process vmmemWSL -ErrorAction SilentlyContinue
    if ($wsl) {
        $wsl.PriorityClass = 'BelowNormal'
        Log-Output "vmmemWSL priority shifted to 'BelowNormal'. Desktop responsiveness protected."
    } else {
        Log-Output "vmmemWSL is not active."
    }
})

$btnFullFix.Add_Click({
    Log-Output "Executing Full Quick-Fix routine..."
    & $btnFlushWSL.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    & $btnTrimApps.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    & $btnWSLPriority.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    Log-Output "Full Quick-Fix complete."
})

# Initial read on launch
Update-Vitals

# Show GUI
[void]$window.ShowDialog()