# CCS Installation Progress Monitor

param([int]$Interval = 30)

$containers = @(
    @{Name="ccs-v8-8.0.0.00016"; Major=8; Target=37000}
    @{Name="ccs-v7-7.3.0.00019"; Major=7; Target=42268}
    @{Name="ccs-v7-7.2.0.00013"; Major=7; Target=42268}
    @{Name="ccs-v7-7.1.0.00016"; Major=7; Target=42268}
)

$prevCounts = @{}

function Get-Status($name, $major, $target) {
    $files = docker exec $name bash -c "find /opt/ti/ccsv$major -type f 2>/dev/null | wc -l" 2>$null
    $disk = docker exec $name bash -c "du -sh /opt/ti/ccsv$major 2>&1 | cut -f1" 2>$null

    if ($files -match '^\d+$') { $files = [int]$files } else { $files = 0 }

    return @{Files=$files; Disk=$disk; Target=$target}
}

function Show-Bar($current, $target) {
    if ($target -eq 0) { return "[------------------------------] 0%" }
    $pct = [Math]::Round(($current/$target)*100, 1)
    $len = [Math]::Floor($pct/100 * 30)
    $bar = "#" * $len + "-" * (30-$len)
    return "[$bar] $pct%"
}

Clear-Host
Write-Host "=== CCS Installation Monitor ===" -ForegroundColor Cyan
Write-Host "Update every $Interval seconds (Ctrl+C to exit)" -ForegroundColor Yellow
Write-Host ""

$round = 0

while ($true) {
    $round++
    $time = Get-Date -Format "HH:mm:ss"

    Write-Host "--- Update #$round at $time ---" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($c in $containers) {
        $st = Get-Status $c.Name $c.Major $c.Target

        Write-Host "[$($c.Name)]" -ForegroundColor Yellow
        Write-Host "  Progress: $(Show-Bar $st.Files $st.Target)" -ForegroundColor Cyan
        Write-Host "  Files: $($st.Files) / $($st.Target)" -ForegroundColor White
        Write-Host "  Disk: $($st.Disk)" -ForegroundColor White

        if ($prevCounts.ContainsKey($c.Name)) {
            $diff = $st.Files - $prevCounts[$c.Name]
            $speed = [Math]::Round(($diff / $Interval) * 60, 0)
            $remain = $st.Target - $st.Files
            if ($speed -gt 0) {
                $eta = [Math]::Round($remain / $speed, 0)
                Write-Host "  Speed: $speed files/min | ETA: $eta min" -ForegroundColor Magenta
            }
        }

        $prevCounts[$c.Name] = $st.Files
        Write-Host ""
    }

    Write-Host "Next update in $Interval seconds..." -ForegroundColor DarkGray
    Write-Host ""

    Start-Sleep -Seconds $Interval
}
