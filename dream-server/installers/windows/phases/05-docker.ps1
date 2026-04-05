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
    # Only run if NVIDIA GPU was detected and the Docker Desktop WSL2 backend
    # is confirmed. This logic uses a three-state model:
    #   - CONFIRMED: real GPU validation succeeded with nvidia-smi
    #   - INCONCLUSIVE: NVIDIA-compatible runtime detected, but real validation
    #                   was skipped because the CUDA test image is not cached
    #                   locally (avoids a 150MB pull on fresh installs)
    #   - FAILED: runtime missing after auto-install attempt, or GPU execution
    #             failed after all recovery steps
    #
    # Phase 08 should fall back to CPU-only inference only on true FAILED.
    $script:gpuPassthroughFailed = $false

    if ($gpuInfo.Backend -eq "nvidia" -and $preflight_docker -and $preflight_docker.WSL2Backend) {
        Write-AI "Testing NVIDIA GPU passthrough in Docker..."

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"

        try {
            $testImage = "nvidia/cuda:12.0.0-base-ubuntu22.04"

            # ── Step 1: Check whether Docker exposes an NVIDIA-compatible runtime ──
            # Use 'docker info' instead of pulling an image — no network cost.
            $dockerRuntimesJson = & docker info --format '{{json .Runtimes}}' 2>&1
            $detectedRuntime = $null

            if ($dockerRuntimesJson -match '"nvidia"') {
                $detectedRuntime = "nvidia"
            } elseif ($dockerRuntimesJson -match '"cdi"') {
                $detectedRuntime = "cdi"
            }

            # ── Step 2: If no runtime found, attempt auto-install first ──
            if (-not $detectedRuntime) {
                Write-AIWarn "No NVIDIA-compatible Docker runtime detected. Attempting auto-install of NVIDIA Container Toolkit..."

                # Detect the WSL2 distro before blindly calling apt-get
                # (old code assumed Debian/Ubuntu — this is more robust)
                $wslDistroId = & wsl bash -c '. /etc/os-release 2>/dev/null && echo ${ID}' 2>$null
                $wslDistroId = ($wslDistroId | Select-Object -Last 1).Trim().ToLower()
                $canAutoInstall = $wslDistroId -in @("ubuntu", "debian", "linuxmint", "pop", "zorin", "elementary")

                if ($canAutoInstall) {
                    Write-AI "  WSL2 distro detected: $wslDistroId — running apt-get install..."

                    $toolkitTmp = Join-Path $env:TEMP "dream-nvidia-toolkit-install.sh"
                    $toolkitScript = @'
#!/bin/bash
set -e
if command -v nvidia-ctk &>/dev/null; then
    echo "NVIDIA Container Toolkit already installed"
    exit 0
fi
distribution=$(. /etc/os-release; echo ${ID}${VERSION_ID})
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null
curl -s -L "https://nvidia.github.io/libnvidia-container/${distribution}/libnvidia-container.list" | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
'@
                    [System.IO.File]::WriteAllText($toolkitTmp, $toolkitScript.Replace("`r`n", "`n"))
                    $wslPath = & wsl wslpath -u ($toolkitTmp.Replace('\', '\\')) 2>$null
                    & wsl bash $wslPath 2>&1 | ForEach-Object { Write-Host "    $_" }
                    Remove-Item -Path $toolkitTmp -Force -ErrorAction SilentlyContinue

                    Write-AI "  Restarting WSL2 to apply runtime configuration..."
                    & wsl --shutdown 2>$null
                    Start-Sleep -Seconds 5

                    # Re-check runtimes after install
                    $dockerRuntimesJson = & docker info --format '{{json .Runtimes}}' 2>&1
                    if ($dockerRuntimesJson -match '"nvidia"') {
                        $detectedRuntime = "nvidia"
                        Write-AISuccess "NVIDIA Container Toolkit installed successfully — runtime is now available."
                    } else {
                        Write-AIWarn "Toolkit install ran but Docker runtime still not detected."
                    }
                } else {
                    Write-AIWarn "  WSL2 distro '$wslDistroId' is not apt-get compatible — skipping auto-install."
                    Write-AI "  Install the NVIDIA Container Toolkit manually:"
                    Write-AI "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
                }
            }

            # ── Step 3: If runtime still unavailable after install attempt, FAILED ──
            if (-not $detectedRuntime) {
                Write-AIError "GPU Passthrough Status: FAILED (no NVIDIA-compatible Docker runtime detected)"
                Write-AI "  Installer will fall back to CPU-only inference."
                Write-AI "  Ensure Docker Desktop is using the WSL2 backend and that Windows NVIDIA drivers are installed."
                $script:gpuPassthroughFailed = $true
            } else {
                Write-AI "  Detected NVIDIA-compatible runtime: $detectedRuntime"

                # ── Step 4: Validate with real GPU execution only if image is already cached ──
                # This avoids pulling 150MB on a fresh install just to confirm what we already know.
                $null = & docker image inspect $testImage 2>&1
                $cudaImageCached = ($LASTEXITCODE -eq 0)

                if ($cudaImageCached) {
                    $null = & docker run --rm --gpus all --pull never $testImage nvidia-smi 2>&1
                    $gpuTestExit = $LASTEXITCODE

                    if ($gpuTestExit -eq 0) {
                        Write-AISuccess "GPU Passthrough Status: CONFIRMED (real GPU validation passed)"
                        $script:gpuPassthroughFailed = $false
                    } else {
                        # Runtime present but execution failed — try WSL restart (fixes post-driver staleness)
                        Write-AIWarn "GPU execution failed with runtime present. Restarting WSL2..."
                        & wsl --shutdown 2>$null
                        Start-Sleep -Seconds 5

                        $null = & docker run --rm --gpus all --pull never $testImage nvidia-smi 2>&1
                        $retryExit = $LASTEXITCODE

                        if ($retryExit -eq 0) {
                            Write-AISuccess "GPU Passthrough Status: CONFIRMED (recovered after WSL restart)"
                            $script:gpuPassthroughFailed = $false
                        } else {
                            Write-AIError "GPU Passthrough Status: FAILED (runtime detected, but GPU execution failed)"
                            Write-AI "  Installer will fall back to CPU-only inference."
                            Write-AI "  Ensure Windows NVIDIA drivers are up to date and Docker Desktop + WSL2 GPU support are healthy."
                            $script:gpuPassthroughFailed = $true
                        }
                    }
                } else {
                    # CUDA image not cached locally — skip the 150MB pull, stay INCONCLUSIVE
                    Write-AIWarn "GPU Passthrough Status: INCONCLUSIVE"
                    Write-AI "  NVIDIA-compatible runtime was detected, but real GPU execution was not validated"
                    Write-AI "  because the CUDA test image is not cached locally. Skipping CPU fallback."
                    Write-AI ("  To validate manually later, run: docker run --rm --gpus all {0} nvidia-smi" -f $testImage)
                    $script:gpuPassthroughFailed = $false
                }
            }
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    }
}
