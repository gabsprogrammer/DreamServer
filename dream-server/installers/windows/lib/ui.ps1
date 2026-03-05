# ============================================================================
# Dream Server Windows Installer — UI Helpers
# ============================================================================
# Part of: installers/windows/lib/
# Purpose: Colored output, phase headers, progress, banners
#
# Matches the CRT narrator voice from installers/lib/ui.sh
# ============================================================================

function Write-DreamBanner {
    $banner = @"

    ____                              ____
   / __ \________  ____ _____ ___   / ___/___  ______   _____  _____
  / / / / ___/ _ \/ __ `/ __ `__ \  \__ \/ _ \/ ___/ | / / _ \/ ___/
 / /_/ / /  /  __/ /_/ / / / / / / ___/ /  __/ /   | |/ /  __/ /
/_____/_/   \___/\__,_/_/ /_/ /_/ /____/\___/_/    |___/\___/_/

"@
    Write-Host $banner -ForegroundColor Green
    Write-Host "  DREAMGATE Windows Installer v$($script:DS_VERSION)" -ForegroundColor White
    Write-Host "  One command to a full local AI stack." -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Phase {
    param(
        [int]$Phase,
        [int]$Total,
        [string]$Name,
        [string]$Estimate = ""
    )
    $elapsed = ((Get-Date) - $script:INSTALL_START).ToString("hh\:mm\:ss")
    Write-Host ""
    Write-Host "  DREAMGATE SEQUENCE [$elapsed]" -ForegroundColor DarkGray -NoNewline
    Write-Host "  PHASE $Phase/$Total" -ForegroundColor White -NoNewline
    Write-Host " -- $Name" -ForegroundColor Green
    if ($Estimate) {
        Write-Host "  Estimated: $Estimate" -ForegroundColor DarkGray
    }
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
}

function Write-AI {
    param([string]$Message)
    Write-Host "  > $Message" -ForegroundColor Green
}

function Write-AISuccess {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-AIWarn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
}

function Write-AIError {
    param([string]$Message)
    Write-Host "  [XX] $Message" -ForegroundColor Red
}

function Write-Chapter {
    param([string]$Title)
    Write-Host ""
    Write-Host ("  " + ("=" * 60)) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("  " + ("=" * 60)) -ForegroundColor DarkGray
}

function Write-InfoBox {
    param(
        [string]$Label,
        [string]$Value
    )
    Write-Host "  $Label" -ForegroundColor DarkGray -NoNewline
    Write-Host " $Value" -ForegroundColor White
}

function Show-ProgressDownload {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Label = "Downloading"
    )
    Write-AI "$Label..."
    # Use curl.exe (ships with Windows 10+) for resume-capable download with progress
    $partFile = "$Destination.part"
    $curlArgs = @("-C", "-", "-L", "--progress-bar", "-o", $partFile, $Url)
    $proc = Start-Process -FilePath "curl.exe" -ArgumentList $curlArgs -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -eq 0 -and (Test-Path $partFile)) {
        Move-Item -Path $partFile -Destination $Destination -Force
        Write-AISuccess "$Label complete"
        return $true
    } else {
        Write-AIError "$Label failed (curl exit code: $($proc.ExitCode))"
        return $false
    }
}

function Write-SuccessCard {
    param(
        [string]$WebUIPort = "3000",
        [string]$DashboardPort = "3001"
    )
    # Detect local IP for network access
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.PrefixOrigin -eq "Dhcp" } |
        Select-Object -First 1).IPAddress
    if (-not $localIP) { $localIP = "your-ip" }

    Write-Host ""
    Write-Host ("  " + ("=" * 60)) -ForegroundColor Green
    Write-Host ""
    Write-Host "       THE GATEWAY IS OPEN" -ForegroundColor White
    Write-Host ""
    Write-Host "       Chat UI:    " -ForegroundColor DarkGray -NoNewline
    Write-Host "http://localhost:$WebUIPort" -ForegroundColor White
    Write-Host "       Dashboard:  " -ForegroundColor DarkGray -NoNewline
    Write-Host "http://localhost:$DashboardPort" -ForegroundColor White
    Write-Host "       Network:    " -ForegroundColor DarkGray -NoNewline
    Write-Host "http://${localIP}:$WebUIPort" -ForegroundColor White
    Write-Host ""
    Write-Host "       Manage:     " -ForegroundColor DarkGray -NoNewline
    Write-Host ".\dream.ps1 status" -ForegroundColor Cyan
    Write-Host "       Logs:       " -ForegroundColor DarkGray -NoNewline
    Write-Host ".\dream.ps1 logs llama-server" -ForegroundColor Cyan
    Write-Host "       Stop:       " -ForegroundColor DarkGray -NoNewline
    Write-Host ".\dream.ps1 stop" -ForegroundColor Cyan
    Write-Host ""
    $elapsed = ((Get-Date) - $script:INSTALL_START).ToString("mm\:ss")
    Write-Host "       Install completed in $elapsed" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("  " + ("=" * 60)) -ForegroundColor Green
    Write-Host ""
}
