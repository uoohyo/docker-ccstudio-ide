# CCS Installation Monitor
# Real-time monitoring of CCS installation progress

param(
    [int]$IntervalSeconds = 30
)

$versions = @(
    @{Name="ccs-v8-8.0.0.00016"; Major=8; TargetFiles=37000; TargetSize="3.0G"}
    @{Name="ccs-v7-7.3.0.00019"; Major=7; TargetFiles=42268; TargetSize="3.3G"}
    @{Name="ccs-v7-7.2.0.00013"; Major=7; TargetFiles=42268; TargetSize="3.3G"}
    @{Name="ccs-v7-7.1.0.00016"; Major=7; TargetFiles=42268; TargetSize="3.3G"}
)

# Store previous counts for speed calculation
$script:previousCounts = @{}

function Get-InstallationStatus {
    param($containerName, $major, $targetFiles)

    $fileCount = docker exec $containerName bash -c "find /opt/ti/ccsv$major -type f 2>/dev/null | wc -l" 2>$null
    $diskUsage = docker exec $containerName bash -c "du -sh /opt/ti/ccsv$major 2>&1 | cut -f1" 2>$null
    $status = docker inspect $containerName --format "{{.State.Status}}" 2>$null

    if ($fileCount -match '^\d+$') {
        $fileCount = [int]$fileCount
    } else {
        $fileCount = 0
    }

    return @{
        FileCount = $fileCount
        DiskUsage = $diskUsage
        Status = $status
        TargetFiles = $targetFiles
    }
}

function Format-Progress {
    param($current, $target)

    if ($target -gt 0) {
        $percent = [Math]::Round(($current / $target) * 100, 1)
        $barLength = 30
        $filled = [Math]::Floor(($percent / 100) * $barLength)
        $empty = $barLength - $filled
        $bar = ("[" + ("#" * $filled) + ("-" * $empty) + "]")
        return "$bar $percent%"
    }
    return "[" + ("-" * 30) + "] 0.0%"
}

function Get-SpeedAndETA {
    param($containerName, $current, $previous, $target, $intervalSec)

    if ($previous -gt 0 -and $current -gt $previous) {
        $filesPerSec = ($current - $previous) / $intervalSec
        $filesPerMin = [Math]::Round($filesPerSec * 60, 0)

        $remaining = $target - $current
        if ($filesPerSec -gt 0) {
            $etaSeconds = $remaining / $filesPerSec
            $etaMinutes = [Math]::Round($etaSeconds / 60, 0)
            return @{
                Speed = "$filesPerMin files/min"
                ETA = "$etaMinutes min"
            }
        }
    }
    return @{Speed = "계산 중..."; ETA = "계산 중..."}
}

Clear-Host
Write-Host "╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           CCS Installation Real-Time Monitor                           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "업데이트 간격: $IntervalSeconds 초" -ForegroundColor Yellow
Write-Host "종료하려면 Ctrl+C를 누르세요"
Write-Host ""

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "HH:mm:ss"

    Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  업데이트 #$iteration - $timestamp" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($ver in $versions) {
        $status = Get-InstallationStatus -containerName $ver.Name -major $ver.Major -targetFiles $ver.TargetFiles

        # Calculate speed and ETA
        $speedInfo = @{Speed = "N/A"; ETA = "N/A"}
        if ($script:previousCounts.ContainsKey($ver.Name)) {
            $speedInfo = Get-SpeedAndETA -containerName $ver.Name `
                -current $status.FileCount `
                -previous $script:previousCounts[$ver.Name] `
                -target $status.TargetFiles `
                -intervalSec $IntervalSeconds
        }
        $script:previousCounts[$ver.Name] = $status.FileCount

        # Display
        Write-Host "  [$($ver.Name)]" -ForegroundColor Yellow

        if ($status.Status -ne "running") {
            Write-Host "    상태: " -NoNewline
            Write-Host "중지됨" -ForegroundColor Red
            Write-Host ""
            continue
        }

        # Check if completed
        $isComplete = $false
        if ($ver.Major -ge 9) {
            $eclipseCheck = docker exec $ver.Name test -x /opt/ti/ccs/eclipse/eclipse 2>$null
            $isComplete = $LASTEXITCODE -eq 0
        } else {
            $eclipseCheck = docker exec $ver.Name test -x "/opt/ti/ccsv$($ver.Major)/eclipse/eclipse" 2>$null
            $isComplete = $LASTEXITCODE -eq 0
        }

        $installerExists = docker exec $ver.Name test -d /opt/ccs-installer 2>$null
        $installerRemoved = $LASTEXITCODE -ne 0

        if ($isComplete -and $installerRemoved) {
            Write-Host "    상태: " -NoNewline -ForegroundColor Green
            Write-Host "✓ 설치 완료" -ForegroundColor Green
            Write-Host "    파일: $($status.FileCount) 개 | 디스크: $($status.DiskUsage)" -ForegroundColor Green
            Write-Host ""
            continue
        }

        Write-Host "    진행: " -NoNewline
        Write-Host "$(Format-Progress -current $status.FileCount -target $status.TargetFiles)" -ForegroundColor Cyan

        Write-Host "    파일: " -NoNewline
        Write-Host "$($status.FileCount)" -NoNewline -ForegroundColor White
        Write-Host " / $($status.TargetFiles) 개" -ForegroundColor DarkGray

        Write-Host "    디스크: " -NoNewline
        Write-Host "$($status.DiskUsage)" -NoNewline -ForegroundColor White
        Write-Host " / $($ver.TargetSize)" -ForegroundColor DarkGray

        Write-Host "    속도: " -NoNewline
        Write-Host "$($speedInfo.Speed)" -ForegroundColor Magenta

        Write-Host "    예상: " -NoNewline
        Write-Host "$($speedInfo.ETA) 남음" -ForegroundColor Yellow

        Write-Host ""
    }

    Write-Host "다음 업데이트까지 $IntervalSeconds 초..." -ForegroundColor DarkGray
    Write-Host ""

    Start-Sleep -Seconds $IntervalSeconds

    # Clear screen for next iteration (optional)
    # Clear-Host
}
