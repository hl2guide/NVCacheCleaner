if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

$global:nvidiaServices = @()
$global:stoppedServices = @()

function Stop-NVIDIAComponents {
    Write-Host "Stopping NVIDIA components..." -ForegroundColor Yellow
    $servicesToStop = @(
        "NVIDIA Display Container LS",
        "NVIDIA LocalSystem Container",
        "NVIDIA NetworkService Container",
        "NVIDIA Telemetry Container",
        "NVIDIA Display Service",
        "NVIDIA FrameView SDK service"
    )
    
    foreach ($service in $servicesToStop) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                $global:nvidiaServices += $svc
                Stop-Service -Name $service -Force -ErrorAction Stop
                $global:stoppedServices += $service
                Write-Host "Stopped service: $service" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Could not stop service $service : $_" -ForegroundColor DarkYellow
        }
    }

    $nvidiaProcesses = @(
        "nvcontainer", 
        "nvidia share", 
        "nvidia web helper", 
        "nvidia telemetry", 
        "nvidia display container",
        "nvidia broadcast",
        "nvidia geforce experience",
        "nvidia overlay"
    )
    
    foreach ($process in $nvidiaProcesses) {
        try {
            $procs = Get-Process -Name $process -ErrorAction SilentlyContinue
            if ($procs) {
                $procs | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 500

                if (Get-Process -Name $process -ErrorAction SilentlyContinue) {
                    Write-Host "Warning: Process still running after stop attempt: $process" -ForegroundColor DarkYellow
                } else {
                    Write-Host "Stopped process: $process" -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Host "Could not stop process $process : $_" -ForegroundColor DarkYellow
        }
    }
    
    Start-Sleep -Seconds 3
}

function Restore-NVIDIAComponents {
    Write-Host "`nRestoring NVIDIA components..." -ForegroundColor Yellow
    
    foreach ($service in $global:stoppedServices) {
        try {
            Start-Service -Name $service -ErrorAction Stop
            Write-Host "Restarted service: $service" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not restart service $service : $_" -ForegroundColor Red
        }
    }
    
    Write-Host "NVIDIA processes will restart automatically when needed." -ForegroundColor Cyan
}

function Remove-FileWithRetry {
    param (
        [string]$Path,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 1000
    )
    
    $retryCount = 0
    $success = $false
    
    while (-not $success -and $retryCount -lt $MaxRetries) {
        try {
            if (Test-Path $Path) {
                Remove-Item -Path $Path -Force -Recurse -Confirm:$false -ErrorAction Stop
                $success = $true
                return $true
            }
            return $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-Host "Retry $retryCount for $Path" -ForegroundColor DarkYellow
                Start-Sleep -Milliseconds $RetryDelay
            }
        }
    }
    
    if (-not $success) {
        Write-Host "Failed to delete after $MaxRetries attempts: $Path" -ForegroundColor Red
        return $false
    }
}

function Clean-CacheDirectory {
    param (
        [string]$Path,
        [switch]$PreserveStructure
    )
    
    if (Test-Path $Path) {
        Write-Host "Cleaning cache at: $Path" -ForegroundColor Yellow
        
        try {
            if ($PreserveStructure) {
                Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-FileWithRetry -Path $_.FullName
                }
            }
            else {
                Remove-FileWithRetry -Path $Path
            }
            
            Write-Host "Successfully cleaned: $Path" -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Partial cleanup completed for: $Path (some files might be in use)" -ForegroundColor Yellow
            return $false
        }
    }
    else {
        Write-Host "Path not found (skipping): $Path" -ForegroundColor Gray
        return $null
    }
}

function Test-CleanupResult {
    param (
        [string]$Path
    )
    
    if (Test-Path $Path) {
        $remainingItems = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue)
        if ($remainingItems.Count -gt 0) {
            Write-Host "Warning: $($remainingItems.Count) items remaining in $Path" -ForegroundColor Red
            return $false
        } else {
            Write-Host "Verified: $Path is empty" -ForegroundColor Green
            return $true
        }
    } else {
        Write-Host "Verified: $Path does not exist (cleanup successful)" -ForegroundColor Green
        return $true
    }
}

try {
    Stop-NVIDIAComponents

    $nvidiaCachePaths = @(
        "${env:ProgramData}\NVIDIA Corporation\NV_Cache",
        "${env:LOCALAPPDATA}\NVIDIA\DXCache",
        "${env:LOCALAPPDATA}\NVIDIA\GLCache",
        "${env:USERPROFILE}\AppData\Local\NVIDIA Corporation\NV_Cache",
        "${env:USERPROFILE}\AppData\Local\Temp\NVIDIA Corporation\NV_Cache",
        "${env:LOCALAPPDATA}\NVIDIA Corporation\NvBackend",
        "${env:PROGRAMDATA}\NVIDIA Corporation\Downloader",
        "${env:ProgramData}\NVIDIA Corporation\GeForce Experience\Caches"
    )
    
    $shaderCachePaths = @(
        "${env:LOCALAPPDATA}\D3DSCache",
        "${env:LOCALAPPDATA}\AMD\DxCache",
        "${env:LOCALAPPDATA}\Intel\ShaderCache",
        "${env:LOCALAPPDATA}\Microsoft\D3D12\D3D12Cache"
    )

    $allCachePaths = $nvidiaCachePaths + $shaderCachePaths
    $cleanupResults = @{}
    foreach ($path in $allCachePaths) {
        $cleanupResults[$path] = Clean-CacheDirectory -Path $path -PreserveStructure
    }

    $nvidiaDriverStore = "${env:ProgramFiles}\NVIDIA Corporation\Installer2"
    if (Test-Path $nvidiaDriverStore) {
        try {
            Write-Host "Cleaning NVIDIA driver store at: $nvidiaDriverStore" -ForegroundColor Yellow
            Get-ChildItem -Path $nvidiaDriverStore -Filter "*" -Directory | 
                Where-Object { $_.Name -ne "Display.Driver" } | 
                ForEach-Object {
                    Remove-FileWithRetry -Path $_.FullName
                }
            Write-Host "Successfully cleaned NVIDIA driver store" -ForegroundColor Green
            $cleanupResults[$nvidiaDriverStore] = $true
        }
        catch {
            Write-Host "Error cleaning NVIDIA driver store: $_" -ForegroundColor Red
            $cleanupResults[$nvidiaDriverStore] = $false
        }
    }

    try {
        Write-Host "Clearing DirectX Shader Cache via cleanmgr (method 1)..." -ForegroundColor Yellow
        Start-Process -FilePath "cleanmgr" -ArgumentList "/sagerun:58" -Wait -NoNewWindow
        Write-Host "Clearing DirectX Shader Cache via cleanmgr (method 2)..." -ForegroundColor Yellow
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/verylowdisk" -Wait -NoNewWindow
        Write-Host "DirectX Shader Cache cleared via Disk Cleanup" -ForegroundColor Green
    }
    catch {
        Write-Host "Error running Disk Cleanup: $_" -ForegroundColor Red
    }

    try {
        Write-Host "Cleaning Windows Temp folders..." -ForegroundColor Yellow
        Get-ChildItem -Path $env:TEMP, "${env:WINDIR}\Temp" -Recurse -Force -ErrorAction SilentlyContinue | 
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "Windows Temp folders cleaned" -ForegroundColor Green
    }
    catch {
        Write-Host "Error cleaning Temp folders: $_" -ForegroundColor Red
    }

    Write-Host "`nVerifying cleanup results..." -ForegroundColor Cyan
    foreach ($path in $allCachePaths + $nvidiaDriverStore) {
        Test-CleanupResult -Path $path
    }
}
finally {
    Restore-NVIDIAComponents
}

cls
Write-Host "`nShader and NVIDIA cache cleanup completed." -ForegroundColor Green
Write-Host "Note: Some files might still be in use and couldn't be deleted." -ForegroundColor Yellow
Write-Host "For complete cleanup, boot in Safe mode and run the script again." -ForegroundColor Yellow
pause