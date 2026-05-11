# Build and run all CCS versions in parallel

Write-Host "=== Fetching CCS versions..." -ForegroundColor Cyan

# Get all buildable versions from pre-generated file
if (-not (Test-Path "versions-temp.json")) {
    Write-Host "Error: versions-temp.json not found. Please run:" -ForegroundColor Red
    Write-Host "  bash .github/scripts/parse-versions.sh > versions-temp.json"
    exit 1
}

$versionsJson = Get-Content "versions-temp.json" -Raw
$versions = $versionsJson | ConvertFrom-Json

# Filter public_download=true versions
$publicVersions = $versions | Where-Object { $_.public_download -eq $true }

$total = $publicVersions.Count
Write-Host "=== Found $total buildable versions" -ForegroundColor Green
Write-Host ""

# Build configuration
$CONCURRENT_BUILDS = 4
$CONCURRENT_RUNS = 8

# Function to determine base image
function Get-BaseImage {
    param([int]$major)

    if ($major -le 8) {
        return "ubuntu:16.04"
    } elseif ($major -le 11) {
        return "ubuntu:20.04"
    } elseif ($major -le 19) {
        return "ubuntu:22.04"
    } else {
        return "ubuntu:24.04"
    }
}

# Arrays to track containers
$containerNames = @()

# Build all versions in batches
Write-Host "=== Starting parallel builds (max $CONCURRENT_BUILDS concurrent)..." -ForegroundColor Cyan
Write-Host ""

$buildCount = 0
$jobs = @()

foreach ($versionInfo in $publicVersions) {
    $version = $versionInfo.version
    $major = [int]$versionInfo.major
    $minor = [int]$versionInfo.minor
    $patch = [int]$versionInfo.patch
    $build = $versionInfo.build
    $baseImage = Get-BaseImage -major $major

    # Wait if we've reached max concurrent builds
    while (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $CONCURRENT_BUILDS) {
        Start-Sleep -Seconds 2
        $jobs | Where-Object { $_.State -eq 'Completed' } | ForEach-Object {
            Receive-Job -Job $_ -ErrorAction SilentlyContinue
            Remove-Job -Job $_
        }
    }

    Write-Host ">>> Starting build: CCS $version (Base: $baseImage)" -ForegroundColor Yellow

    # Start build job
    $currentDir = Get-Location
    $job = Start-Job -ScriptBlock {
        param($version, $baseImage, $major, $minor, $patch, $build, $workDir)

        Set-Location $workDir

        docker buildx build `
            --build-arg BASE_IMAGE="$baseImage" `
            --build-arg CCS_VERSION="$version" `
            --build-arg MAJOR_VER="$major" `
            --build-arg MINOR_VER="$minor" `
            --build-arg PATCH_VER="$patch" `
            --build-arg BUILD_VER="$build" `
            --tag "ccstudio-ide:$version" `
            --load `
            . 2>&1 | ForEach-Object { "[BUILD $version] $_" }

        if ($LASTEXITCODE -eq 0) {
            Write-Output "✓ Build complete: $version"
        } else {
            Write-Error "✗ Build failed: $version"
        }
    } -ArgumentList $version, $baseImage, $major, $minor, $patch, $build, $currentDir

    $jobs += $job
    $buildCount++
    Write-Host "Progress: $buildCount/$total builds started" -ForegroundColor Cyan
}

# Wait for all builds to complete
Write-Host ""
Write-Host "--- Waiting for all builds to complete..." -ForegroundColor Yellow
$jobs | Wait-Job | Receive-Job -ErrorAction SilentlyContinue
$jobs | Remove-Job

Write-Host ""
Write-Host "=== All builds complete! ($total versions)" -ForegroundColor Green
Write-Host ""

# Start all containers
Write-Host "=== Starting all containers..." -ForegroundColor Cyan
Write-Host ""

$runCount = 0

foreach ($versionInfo in $publicVersions) {
    $version = $versionInfo.version
    $major = [int]$versionInfo.major
    $containerName = "ccs-v$major-$version"

    # Wait if we've reached max concurrent runs
    while ((docker ps -q).Count -ge $CONCURRENT_RUNS) {
        Start-Sleep -Seconds 2
    }

    Write-Host ">>> Starting container: $containerName" -ForegroundColor Yellow

    docker run -d `
        --name $containerName `
        --memory=2g `
        -e COMPONENTS=PF_C28 `
        "ccstudio-ide:$version" `
        sleep infinity 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Container started: $containerName" -ForegroundColor Green
        $containerNames += $containerName
    } else {
        Write-Host "✗ Container failed: $containerName" -ForegroundColor Red
    }

    $runCount++
    Write-Host "Progress: $runCount/$total containers started" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "=== All containers started! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Container names:" -ForegroundColor Cyan
foreach ($name in $containerNames) {
    Write-Host "  - $name"
}

Write-Host ""
Write-Host "=== Installation in progress ===" -ForegroundColor Yellow
Write-Host "Use 'docker ps' to see running containers"
Write-Host "Use 'docker logs <container_name>' to check installation progress"
Write-Host ""
Write-Host "Verification commands:" -ForegroundColor Cyan
Write-Host "  # Check v20+ installation:"
Write-Host '  docker exec <container> test -x /opt/ti/ccs/eclipse/ccs-server-cli.sh && echo "Ready"'
Write-Host ""
Write-Host "  # Check v9-v19 installation:"
Write-Host '  docker exec <container> test -x /opt/ti/ccs/eclipse/eclipse && echo "Ready"'
Write-Host ""
Write-Host "  # Check v7-v8 installation:"
Write-Host '  docker exec <container> test -x /opt/ti/ccsv7/eclipse/eclipse && echo "Ready"'
Write-Host ""
