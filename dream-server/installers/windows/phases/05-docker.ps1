# ============================================================================
# Dream Server Windows Installer -- Phase 05: Docker Validation
# ============================================================================
# Part of: installers/windows/phases/
# Purpose: Deep Docker health check -- daemon responsiveness, Compose v1/v2
#          detection, NVIDIA GPU passthrough smoke test, compose file syntax
#          validation. On Windows, Docker Desktop is a prerequisite (installed
#          by the user); this phase does NOT install Docker.
#
# Reads:
#   $gpuInfo     -- from phase 02, for GPU passthrough test
#   $sourceRoot  -- from orchestrator, for compose syntax validation
#   $dryRun      -- skip live checks
#   $script:DOCKER_COMPOSE_CMD  -- from constants.ps1 (default: "docker compose")
#
# Writes:
#   $dockerComposeCmd  -- string: resolved compose command
#                         ("docker compose" or "docker-compose")
#
# Modder notes:
#   To add Podman support, add a Podman detection branch after the Docker
#   Compose v1 fallback.
# ============================================================================

Write-Phase -Phase 5 -Total 13 -Name "DOCKER VALIDATION" -Estimate "~15 seconds"
Write-AI "Validating container runtime..."

# ── Docker daemon health ──────────────────────────────────────────────────────
if ($dryRun) {
    Write-AI "[DRY RUN] Would verify Docker daemon is responsive (docker info)"
    Write-AI "[DRY RUN] Would detect Docker Compose v1 vs v2"
    $dockerComposeCmd = $script:DOCKER_COMPOSE_CMD
} else {
    # Suppress stderr -- `docker info` emits warnings to stderr on first run
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $null = & docker info 2>&1
    $dockerInfoExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($dockerInfoExit -ne 0) {
        Write-AIError "Docker daemon is not responding (docker info exit code: $dockerInfoExit)."
        Write-AI "  Make sure Docker Desktop is running and the WSL2 backend is active."
        Write-AI "  Start Docker Desktop from the Start Menu, wait for it to fully initialize,"
        Write-AI "  then re-run this installer."
        exit 1
    }
    Write-AISuccess "Docker daemon healthy"

    # ── Docker Compose detection (prefer v2, fall back to v1) ─────────────────
    $dockerComposeCmd = ""
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"

    # Try v2: `docker compose version`
    $null = & docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerComposeCmd = "docker compose"
    } else {
        # Try v1: standalone `docker-compose`
        $dcCmd = Get-Command docker-compose -ErrorAction SilentlyContinue
        if ($dcCmd) {
            $dockerComposeCmd = "docker-compose"
            Write-AIWarn "Docker Compose v1 (docker-compose) detected. Upgrade to v2 is recommended."
        }
    }
    $ErrorActionPreference = $prevEAP

    if (-not $dockerComposeCmd) {
        Write-AIError "Docker Compose not found (tried: 'docker compose' and 'docker-compose')."
        Write-AI "  Install Docker Desktop, which bundles Compose v2:"
        Write-AI "  https://docs.docker.com/desktop/install/windows-install/"
        exit 1
    }
    Write-AISuccess "Docker Compose available: $dockerComposeCmd"

    # ── Compose file syntax validation ────────────────────────────────────────
    # Quick config check on the base compose file to catch syntax errors early.
    $_baseCompose = Join-Path $sourceRoot "docker-compose.base.yml"
    if (Test-Path $_baseCompose) {
        Push-Location $sourceRoot
        try {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            $null = & docker compose -f "docker-compose.base.yml" config 2>&1
            $composeConfigExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP

            if ($composeConfigExit -ne 0) {
                Write-AIWarn "Compose stack syntax check returned non-zero (may be OK if overlays are missing at this stage)."
            } else {
                Write-AISuccess "docker-compose.base.yml syntax OK"
            }
        } finally {
            Pop-Location
        }
    }

    # ── NVIDIA GPU passthrough smoke test ─────────────────────────────────────
    # Three-state model:
    #   CONFIRMED    -> runtime verified, safe to use NVIDIA compose overlay
    #   INCONCLUSIVE -> runtime unavailable or test couldn't prove passthrough
    #   FAILED       -> auto-remediation exhausted, fall back to CPU overlay
    function Test-DockerGpuPassthroughNoPull {
        $result = @{
            Status  = "INCONCLUSIVE"
            Message = "Runtime check did not confirm GPU passthrough"
        }

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        try {
            # Zero-download check: inspect runtimes only (no image pull).
            $runtimesRaw = & docker info --format "{{json .Runtimes}}" 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $runtimesRaw) {
                $result.Message = "docker info runtime query failed"
                return $result
            }

            $runtimes = $runtimesRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            $hasGpuRuntime = $false
            if ($runtimes) {
                if ($runtimes.PSObject.Properties.Name -contains "nvidia") { $hasGpuRuntime = $true }
                if ($runtimes.PSObject.Properties.Name -contains "cdi") { $hasGpuRuntime = $true }
            }
            if (-not $hasGpuRuntime) {
                $result.Message = "No NVIDIA/CDI runtime entry in docker info"
                return $result
            }

            # Zero-download real validation only if CUDA image is already local.
            $cudaImage = "nvidia/cuda:12.0.0-base-ubuntu22.04"
            $null = & docker image inspect $cudaImage 2>$null
            if ($LASTEXITCODE -ne 0) {
                $result.Status = "INCONCLUSIVE"
                $result.Message = "NVIDIA runtime detected, but CUDA test image is not cached locally"
                return $result
            }

            $null = & docker run --rm --pull never --gpus all $cudaImage nvidia-smi 2>$null
            if ($LASTEXITCODE -eq 0) {
                $result.Status = "CONFIRMED"
                $result.Message = "NVIDIA GPU passthrough confirmed without image download"
            } else {
                $result.Status = "FAILED"
                $result.Message = "GPU runtime detected but local CUDA nvidia-smi probe failed"
            }
            return $result
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    function Invoke-WslNvidiaToolkitAutoInstall {
        $result = @{
            Ran      = $false
            Succeeded = $false
        }

        $toolkitTmp = Join-Path $env:TEMP "dream-nvidia-toolkit-install.sh"
        $toolkitScript = @'
#!/bin/bash
set -euo pipefail
if command -v nvidia-ctk >/dev/null 2>&1; then
    echo "NVIDIA Container Toolkit already installed"
    exit 0
fi
if ! command -v apt-get >/dev/null 2>&1; then
    echo "AUTO_INSTALL_UNSUPPORTED:apt-get not found"
    exit 10
fi
if ! command -v sudo >/dev/null 2>&1; then
    echo "AUTO_INSTALL_UNSUPPORTED:sudo not found"
    exit 11
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ] && [ "${ID_LIKE:-}" != "debian" ]; then
    echo "AUTO_INSTALL_UNSUPPORTED:requires Debian/Ubuntu distro"
    exit 12
fi
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
'@
        [System.IO.File]::WriteAllText($toolkitTmp, $toolkitScript.Replace("`r`n", "`n"))
        try {
            $wslPath = & wsl wslpath -u ($toolkitTmp.Replace('\', '\\')) 2>$null
            if (-not $wslPath) { return $result }
            $result.Ran = $true
            & wsl bash $wslPath 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -eq 0) {
                $result.Succeeded = $true
            }
        } finally {
            Remove-Item -Path $toolkitTmp -Force -ErrorAction SilentlyContinue
        }
        return $result
    }

    $script:gpuPassthroughFailed = $false
    $script:gpuPassthroughStatus = "INCONCLUSIVE"
    if ($gpuInfo.Backend -eq "nvidia" -and $preflight_docker -and $preflight_docker.WSL2Backend) {
        Write-AI "Testing NVIDIA GPU passthrough in Docker (non-fatal, no image pull)..."

        $probe = Test-DockerGpuPassthroughNoPull
        $script:gpuPassthroughStatus = $probe.Status

        if ($probe.Status -eq "CONFIRMED") {
            Write-AISuccess $probe.Message
        } else {
            Write-AIWarn "GPU passthrough check: $($probe.Status) ($($probe.Message))"
            Write-AI "  Attempting automatic remediation before CPU fallback..."

            Write-AI "  Restarting WSL2 kernel..."
            & wsl --shutdown 2>$null
            Start-Sleep -Seconds 5

            $retryProbe = Test-DockerGpuPassthroughNoPull
            $script:gpuPassthroughStatus = $retryProbe.Status
            if ($retryProbe.Status -eq "CONFIRMED") {
                Write-AISuccess "GPU passthrough recovered after WSL restart"
            } else {
                Write-AI "  Installing NVIDIA Container Toolkit in WSL2 (auto-fix)..."
                $toolkitInstall = Invoke-WslNvidiaToolkitAutoInstall

                if (-not $toolkitInstall.Ran) {
                    Write-AIWarn "Toolkit auto-install could not start in WSL. Continuing with guided fallback."
                } elseif (-not $toolkitInstall.Succeeded) {
                    Write-AIWarn "Toolkit auto-install did not complete successfully."
                }

                & wsl --shutdown 2>$null
                Start-Sleep -Seconds 5

                $finalProbe = Test-DockerGpuPassthroughNoPull
                $script:gpuPassthroughStatus = $finalProbe.Status
                if ($finalProbe.Status -eq "CONFIRMED") {
                    Write-AISuccess "GPU passthrough working after auto-remediation"
                } elseif ($finalProbe.Status -eq "INCONCLUSIVE") {
                    Write-AIWarn "GPU passthrough remains INCONCLUSIVE (runtime detected, but CUDA test image is not cached)."
                    Write-AI "  Continuing with NVIDIA backend to avoid false CPU downgrade."
                } else {
                    $script:gpuPassthroughStatus = "FAILED"
                    $script:gpuPassthroughFailed = $true
                    Write-AIWarn "GPU passthrough still not confirmed after auto-remediation."
                    Write-AI "  Continuing with CPU-only inference (slower)."
                    Write-AI "  Manual fix: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
                }
            }
        }
    }
}
