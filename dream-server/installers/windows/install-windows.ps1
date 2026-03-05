# ============================================================================
# Dream Server Windows Installer — Main Orchestrator
# ============================================================================
# Standalone Windows installer. Does not modify any Linux installer files.
#
# NVIDIA: Docker Desktop handles GPU passthrough via WSL2. Existing
#         docker-compose.base.yml + docker-compose.nvidia.yml work unchanged.
#
# AMD Strix Halo: llama-server runs natively with Vulkan on Windows.
#         Everything else runs in Docker. Containers reach the host via
#         host.docker.internal.
#
# Usage:
#   .\install-windows.ps1                  # Interactive install
#   .\install-windows.ps1 --Tier 3         # Force tier 3
#   .\install-windows.ps1 --Cloud          # Cloud-only (no local GPU)
#   .\install-windows.ps1 --DryRun         # Validate without installing
#   .\install-windows.ps1 --All            # Enable all optional services
#   .\install-windows.ps1 --NonInteractive # Headless install (defaults)
#
# ============================================================================

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NonInteractive,
    [string]$Tier = "",
    [switch]$Voice,
    [switch]$Workflows,
    [switch]$Rag,
    [switch]$OpenClaw,
    [switch]$All,
    [switch]$Cloud,
    [string]$SummaryJsonPath = ""
)

$ErrorActionPreference = "Stop"

# ── Locate script directory and source tree root ──
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceRoot  = (Resolve-Path (Join-Path $ScriptDir ".." "..")).Path

# ── Source libraries ──
. (Join-Path $ScriptDir "lib" "constants.ps1")
. (Join-Path $ScriptDir "lib" "ui.ps1")
. (Join-Path $ScriptDir "lib" "tier-map.ps1")
. (Join-Path $ScriptDir "lib" "detection.ps1")
. (Join-Path $ScriptDir "lib" "env-generator.ps1")

# ── Resolve install directory ──
$InstallDir = $script:DS_INSTALL_DIR

# ============================================================================
# STEP 1 — PREFLIGHT
# ============================================================================
Write-DreamBanner
Write-Phase -Phase 1 -Total 6 -Name "PREFLIGHT CHECKS" -Estimate "30 seconds"

# PowerShell version
$psVer = Test-PowerShellVersion
Write-InfoBox "PowerShell:" "$($psVer.Version)"
if (-not $psVer.Sufficient) {
    Write-AIError "PowerShell 5.1 or later is required. Please update."
    exit 1
}
Write-AISuccess "PowerShell version OK"

# Docker Desktop
$docker = Test-DockerDesktop
if (-not $docker.Installed) {
    Write-AIError "Docker Desktop not found. Install from https://docs.docker.com/desktop/install/windows-install/"
    Write-AI "After installing, enable the WSL2 backend in Docker Desktop settings."
    exit 1
}
Write-AISuccess "Docker CLI found"

if (-not $docker.Running) {
    Write-AIError "Docker Desktop is not running. Start it and try again."
    exit 1
}
Write-AISuccess "Docker Desktop running (v$($docker.Version))"

if (-not $docker.WSL2Backend) {
    Write-AIWarn "WSL2 backend not detected. GPU passthrough requires WSL2."
    Write-AI "Enable WSL2 in Docker Desktop > Settings > General > Use WSL 2 based engine"
    if (-not $Force) { exit 1 }
}

# Disk space
$disk = Test-DiskSpace -Path $InstallDir -RequiredGB 20
Write-InfoBox "Disk free:" "$($disk.FreeGB) GB on $($disk.Drive)"
if (-not $disk.Sufficient) {
    Write-AIError "At least $($disk.RequiredGB) GB free space required. Found $($disk.FreeGB) GB."
    exit 1
}
Write-AISuccess "Disk space OK"

# ============================================================================
# STEP 2 — GPU DETECTION & TIER SELECTION
# ============================================================================
Write-Phase -Phase 2 -Total 6 -Name "HARDWARE DETECTION" -Estimate "10 seconds"

$gpuInfo = Get-GpuInfo
$systemRamGB = Get-SystemRamGB

Write-InfoBox "GPU:" "$($gpuInfo.Name)"
Write-InfoBox "VRAM:" "$($gpuInfo.VramMB) MB ($($gpuInfo.MemoryType))"
Write-InfoBox "System RAM:" "$systemRamGB GB"
Write-InfoBox "Backend:" "$($gpuInfo.Backend)"

if ($gpuInfo.Backend -eq "nvidia") {
    Write-InfoBox "Driver:" "$($gpuInfo.DriverVersion)"
    if ($gpuInfo.DriverMajor -lt $script:MIN_NVIDIA_DRIVER) {
        Write-AIWarn "NVIDIA driver $($gpuInfo.DriverVersion) is below minimum ($($script:MIN_NVIDIA_DRIVER))."
        Write-AI "Update at https://www.nvidia.com/Download/index.aspx"
        if (-not $Force) { exit 1 }
    }
    if ($docker.GpuSupport) {
        Write-AISuccess "Docker GPU support detected"
    } else {
        Write-AIWarn "Docker GPU support not confirmed. NVIDIA Container Toolkit may need configuration."
    }
}

# Auto-select tier (or use override)
if ($Cloud) {
    $selectedTier = "CLOUD"
} elseif ($Tier) {
    $selectedTier = $Tier.ToUpper()
    # Normalize T-prefix: T1 -> 1, T2 -> 2, etc.
    if ($selectedTier -match "^T(\d)$") { $selectedTier = $Matches[1] }
} else {
    $selectedTier = ConvertTo-TierFromGpu -GpuInfo $gpuInfo -SystemRamGB $systemRamGB
}

$tierConfig = Resolve-TierConfig -Tier $selectedTier
Write-AISuccess "Selected tier: $selectedTier ($($tierConfig.TierName))"
Write-InfoBox "Model:" "$($tierConfig.LlmModel)"
Write-InfoBox "GGUF:" "$($tierConfig.GgufFile)"
Write-InfoBox "Context:" "$($tierConfig.MaxContext)"

# ============================================================================
# STEP 3 — FEATURE SELECTION
# ============================================================================
Write-Phase -Phase 3 -Total 6 -Name "FEATURES" -Estimate "interactive"

# Default features
$enableVoice     = $Voice.IsPresent -or $All.IsPresent
$enableWorkflows = $Workflows.IsPresent -or $All.IsPresent
$enableRag       = $Rag.IsPresent -or $All.IsPresent
$enableOpenClaw  = $OpenClaw.IsPresent -or $All.IsPresent

if (-not $NonInteractive -and -not $All -and -not $DryRun) {
    Write-Chapter "Select Features"
    Write-AI "Choose your Dream Server configuration:"
    Write-Host ""
    Write-Host "  [1] Full Stack   — Everything enabled (voice, workflows, RAG, agents)" -ForegroundColor Green
    Write-Host "  [2] Core Only    — Chat + LLM inference (lean and fast)" -ForegroundColor White
    Write-Host "  [3] Custom       — Choose individually" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  Selection (1/2/3)"
    switch ($choice) {
        "1" {
            $enableVoice = $true; $enableWorkflows = $true
            $enableRag = $true; $enableOpenClaw = $true
        }
        "2" {
            $enableVoice = $false; $enableWorkflows = $false
            $enableRag = $false; $enableOpenClaw = $false
        }
        "3" {
            $enableVoice     = (Read-Host "  Enable Voice (Whisper + Kokoro)? [y/N]") -match "^[yY]"
            $enableWorkflows = (Read-Host "  Enable Workflows (n8n)?           [y/N]") -match "^[yY]"
            $enableRag       = (Read-Host "  Enable RAG (Qdrant + embeddings)? [y/N]") -match "^[yY]"
            $enableOpenClaw  = (Read-Host "  Enable OpenClaw (AI agents)?      [y/N]") -match "^[yY]"
        }
        default {
            $enableVoice = $true; $enableWorkflows = $true
            $enableRag = $true; $enableOpenClaw = $true
        }
    }
}

Write-AI "Features:"
Write-InfoBox "  Voice:"     $(if ($enableVoice)     { "enabled" } else { "disabled" })
Write-InfoBox "  Workflows:" $(if ($enableWorkflows) { "enabled" } else { "disabled" })
Write-InfoBox "  RAG:"       $(if ($enableRag)       { "enabled" } else { "disabled" })
Write-InfoBox "  OpenClaw:"  $(if ($enableOpenClaw)  { "enabled" } else { "disabled" })

# ============================================================================
# STEP 4 — SETUP (directories, copy source, generate .env)
# ============================================================================
Write-Phase -Phase 4 -Total 6 -Name "SETUP" -Estimate "1-2 minutes"

if ($DryRun) {
    Write-AI "[DRY RUN] Would create: $InstallDir"
    Write-AI "[DRY RUN] Would copy source files via robocopy"
    Write-AI "[DRY RUN] Would generate .env with secrets"
    Write-AI "[DRY RUN] Would generate SearXNG config"
    if ($enableOpenClaw) { Write-AI "[DRY RUN] Would configure OpenClaw" }
} else {
    # Create directory structure
    $dirs = @(
        (Join-Path $InstallDir "config" "searxng"),
        (Join-Path $InstallDir "config" "n8n"),
        (Join-Path $InstallDir "config" "litellm"),
        (Join-Path $InstallDir "config" "openclaw"),
        (Join-Path $InstallDir "config" "llama-server"),
        (Join-Path $InstallDir "data" "open-webui"),
        (Join-Path $InstallDir "data" "whisper"),
        (Join-Path $InstallDir "data" "tts"),
        (Join-Path $InstallDir "data" "n8n"),
        (Join-Path $InstallDir "data" "qdrant"),
        (Join-Path $InstallDir "data" "models")
    )
    foreach ($d in $dirs) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    Write-AISuccess "Created directory structure"

    # Copy source tree (skip .git, data, logs, .env, models)
    if ($SourceRoot -ne $InstallDir) {
        Write-AI "Copying source files to $InstallDir..."
        $robocopyArgs = @(
            $SourceRoot, $InstallDir,
            "/E", "/NFL", "/NDL", "/NJH", "/NJS",
            "/XD", ".git", "data", "logs", "models", "node_modules", "dist",
            "/XF", ".env", "*.log", ".current-mode", ".profiles",
                   ".target-model", ".target-quantization", ".offline-mode"
        )
        & robocopy @robocopyArgs | Out-Null
        # robocopy exit codes 0-7 are success
        if ($LASTEXITCODE -gt 7) {
            Write-AIError "File copy failed (robocopy exit code: $LASTEXITCODE)"
            exit 1
        }
        Write-AISuccess "Source files installed"
    } else {
        Write-AI "Running in-place, skipping file copy"
    }

    # Copy dream.ps1 CLI to install root so users can run .\dream.ps1
    $dreamSrc = Join-Path $ScriptDir "dream.ps1"
    $dreamDst = Join-Path $InstallDir "dream.ps1"
    if (Test-Path $dreamSrc) {
        Copy-Item -Path $dreamSrc -Destination $dreamDst -Force
        # Also copy the lib/ directory dream.ps1 needs
        $libSrc = Join-Path $ScriptDir "lib"
        $libDst = Join-Path $InstallDir "lib"
        New-Item -ItemType Directory -Path $libDst -Force | Out-Null
        Copy-Item -Path (Join-Path $libSrc "*") -Destination $libDst -Recurse -Force
        Write-AISuccess "Installed dream.ps1 CLI"
    }

    # Generate .env
    # NOTE: $(if ...) syntax required for PS 5.1 compatibility
    $dreamMode = $(if ($Cloud) { "cloud" } else { "local" })
    $envResult = New-DreamEnv -InstallDir $InstallDir -TierConfig $tierConfig `
        -Tier $selectedTier -GpuBackend $gpuInfo.Backend -DreamMode $dreamMode
    Write-AISuccess "Generated .env with secure secrets"

    # Generate SearXNG config
    $searxngPath = New-SearxngConfig -InstallDir $InstallDir -SecretKey $envResult.SearxngSecret
    Write-AISuccess "Generated SearXNG config"

    # Generate OpenClaw configs (if enabled)
    if ($enableOpenClaw) {
        $providerUrl = $(if ($gpuInfo.Backend -eq "amd") {
            "http://host.docker.internal:8080"
        } else {
            "http://llama-server:8080"
        })
        New-OpenClawConfig -InstallDir $InstallDir `
            -LlmModel $tierConfig.LlmModel `
            -MaxContext $tierConfig.MaxContext `
            -Token $envResult.OpenclawToken `
            -ProviderUrl $providerUrl
        Write-AISuccess "Generated OpenClaw configs"
    }

    # Create llama-server models.ini (empty — populated later)
    $modelsIni = Join-Path $InstallDir "config" "llama-server" "models.ini"
    if (-not (Test-Path $modelsIni)) {
        Write-Utf8NoBom -Path $modelsIni -Content "# Dream Server model registry"
    }
}

# ============================================================================
# STEP 5 — LAUNCH (download model, start services)
# ============================================================================
Write-Phase -Phase 5 -Total 6 -Name "LAUNCH" -Estimate "2-30 minutes (model download)"

if ($DryRun) {
    if ($tierConfig.GgufUrl) {
        Write-AI "[DRY RUN] Would download: $($tierConfig.GgufFile)"
    }
    if ($gpuInfo.Backend -eq "amd") {
        Write-AI "[DRY RUN] Would download llama-server.exe (Vulkan build)"
        Write-AI "[DRY RUN] Would start native llama-server on port 8080"
    }
    Write-AI "[DRY RUN] Would run: docker compose up -d"
} else {
    # Change to install directory for docker compose
    Push-Location $InstallDir

    try {
        # ── Download GGUF model (if not cloud-only) ──
        if ($tierConfig.GgufUrl -and -not $Cloud) {
            $modelPath = Join-Path $InstallDir "data" "models" $tierConfig.GgufFile
            if (Test-Path $modelPath) {
                Write-AISuccess "Model already downloaded: $($tierConfig.GgufFile)"
            } else {
                $downloadOk = Show-ProgressDownload -Url $tierConfig.GgufUrl `
                    -Destination $modelPath -Label "Downloading $($tierConfig.GgufFile)"
                if (-not $downloadOk) {
                    Write-AIError "Model download failed. Re-run the installer to resume."
                    exit 1
                }
            }
        }

        # ── AMD: Download and start native llama-server.exe ──
        if ($gpuInfo.Backend -eq "amd" -and -not $Cloud) {
            Write-Chapter "NATIVE LLAMA-SERVER (VULKAN)"

            # Download llama.cpp Vulkan build
            $llamaZip = Join-Path $env:TEMP $script:LLAMA_CPP_VULKAN_ASSET
            if (-not (Test-Path $script:LLAMA_SERVER_EXE)) {
                if (-not (Test-Path $llamaZip)) {
                    $dlOk = Show-ProgressDownload -Url $script:LLAMA_CPP_VULKAN_URL `
                        -Destination $llamaZip -Label "Downloading llama-server (Vulkan)"
                    if (-not $dlOk) {
                        Write-AIError "llama-server download failed."
                        exit 1
                    }
                }
                # Extract
                Write-AI "Extracting llama-server..."
                New-Item -ItemType Directory -Path $script:LLAMA_SERVER_DIR -Force | Out-Null
                Expand-Archive -Path $llamaZip -DestinationPath $script:LLAMA_SERVER_DIR -Force
                # The zip may contain a subdirectory — find llama-server.exe
                $exeFound = Get-ChildItem -Path $script:LLAMA_SERVER_DIR -Recurse -Filter "llama-server.exe" |
                    Select-Object -First 1
                if ($exeFound -and $exeFound.DirectoryName -ne $script:LLAMA_SERVER_DIR) {
                    # Move files from subdirectory to llama-server root
                    Get-ChildItem -Path $exeFound.DirectoryName -Force |
                        Move-Item -Destination $script:LLAMA_SERVER_DIR -Force
                }
                if (-not (Test-Path $script:LLAMA_SERVER_EXE)) {
                    Write-AIError "llama-server.exe not found after extraction."
                    exit 1
                }
                Write-AISuccess "Extracted llama-server.exe"
            } else {
                Write-AISuccess "llama-server.exe already present"
            }

            # Start native llama-server
            Write-AI "Starting native llama-server (Vulkan)..."
            $modelFullPath = Join-Path $InstallDir "data" "models" $tierConfig.GgufFile
            $llamaArgs = @(
                "--model", $modelFullPath,
                "--host", "0.0.0.0",
                "--port", "8080",
                "--n-gpu-layers", "999",
                "--ctx-size", "$($tierConfig.MaxContext)"
            )
            $pidDir = Split-Path $script:LLAMA_SERVER_PID_FILE
            New-Item -ItemType Directory -Path $pidDir -Force | Out-Null

            $proc = Start-Process -FilePath $script:LLAMA_SERVER_EXE `
                -ArgumentList $llamaArgs -WindowStyle Hidden -PassThru
            Set-Content -Path $script:LLAMA_SERVER_PID_FILE -Value $proc.Id

            # Wait for health endpoint
            Write-AI "Waiting for llama-server to load model..."
            $maxWait = 120
            $waited = 0
            $healthy = $false
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 2
                $waited += 2
                try {
                    $resp = Invoke-WebRequest -Uri "http://localhost:8080/health" `
                        -TimeoutSec 3 -UseBasicParsing -ErrorAction SilentlyContinue
                    if ($resp.StatusCode -eq 200) {
                        $healthy = $true
                        break
                    }
                } catch { }
                if ($waited % 10 -eq 0) {
                    Write-AI "  Still loading... ($waited seconds)"
                }
            }

            if ($healthy) {
                Write-AISuccess "Native llama-server healthy (PID $($proc.Id))"
            } else {
                Write-AIWarn "llama-server did not become healthy within ${maxWait}s. It may still be loading."
            }
        }

        # ── Assemble Docker Compose flags ──
        $composeFlags = @("-f", "docker-compose.base.yml")

        if ($Cloud) {
            # Cloud mode: disable llama-server (no GPU overlay, no local model)
            $composeFlags += @("-f", "installers/windows/docker-compose.windows-amd.yml")
        } elseif ($gpuInfo.Backend -eq "nvidia") {
            $composeFlags += @("-f", "docker-compose.nvidia.yml")
        } elseif ($gpuInfo.Backend -eq "amd") {
            $composeFlags += @("-f", "installers/windows/docker-compose.windows-amd.yml")
        }

        # Discover enabled extension compose fragments via manifests
        # Mirrors resolve-compose-stack.sh: reads manifest.yaml, checks schema_version
        # and gpu_backends before including a service's compose file.
        $extDir = Join-Path $InstallDir "extensions" "services"
        $currentBackend = $(if ($Cloud) { "none" } else { $gpuInfo.Backend })

        if (Test-Path $extDir) {
            $extServices = Get-ChildItem -Path $extDir -Directory | Sort-Object Name
            foreach ($svcDir in $extServices) {
                # Read manifest (YAML parsed as simple key-value — no YAML lib needed)
                $manifestPath = Join-Path $svcDir.FullName "manifest.yaml"
                if (-not (Test-Path $manifestPath)) {
                    $manifestPath = Join-Path $svcDir.FullName "manifest.yml"
                }
                if (-not (Test-Path $manifestPath)) { continue }

                $manifestLines = Get-Content $manifestPath -ErrorAction SilentlyContinue
                if (-not $manifestLines) { continue }

                # Quick manifest validation: must contain schema_version: dream.services.v1
                $hasSchema = $manifestLines | Where-Object { $_ -match "schema_version:\s*dream\.services\.v1" }
                if (-not $hasSchema) { continue }

                # Check gpu_backends compatibility
                $backendsLine = $manifestLines | Where-Object { $_ -match "gpu_backends:" }
                if ($backendsLine -and $currentBackend -ne "none") {
                    $backendsStr = ($backendsLine -split "gpu_backends:")[1]
                    if ($backendsStr -notmatch $currentBackend -and $backendsStr -notmatch "all") {
                        continue  # Service not compatible with current GPU
                    }
                }

                # Find compose file reference in manifest
                $composeFile = "compose.yaml"  # default
                $composeRefLine = $manifestLines | Where-Object { $_ -match "compose_file:" }
                if ($composeRefLine) {
                    $composeFile = (($composeRefLine -split "compose_file:")[1]).Trim().Trim('"').Trim("'")
                }

                $composePath = Join-Path $svcDir.FullName $composeFile
                if (-not (Test-Path $composePath)) { continue }

                # Check feature flags
                $svcName = $svcDir.Name
                $skip = $false
                switch ($svcName) {
                    "whisper"    { if (-not $enableVoice) { $skip = $true } }
                    "tts"        { if (-not $enableVoice) { $skip = $true } }
                    "n8n"        { if (-not $enableWorkflows) { $skip = $true } }
                    "qdrant"     { if (-not $enableRag) { $skip = $true } }
                    "embeddings" { if (-not $enableRag) { $skip = $true } }
                    "openclaw"   { if (-not $enableOpenClaw) { $skip = $true } }
                }
                if ($skip) { continue }

                $relPath = $composePath.Substring($InstallDir.Length + 1) -replace "\\", "/"
                $composeFlags += @("-f", $relPath)

                # GPU-specific overlay for this extension (filesystem discovery)
                if ($currentBackend -eq "nvidia") {
                    $gpuOverlay = Join-Path $svcDir.FullName "compose.nvidia.yaml"
                    if (Test-Path $gpuOverlay) {
                        $relOverlay = $gpuOverlay.Substring($InstallDir.Length + 1) -replace "\\", "/"
                        $composeFlags += @("-f", $relOverlay)
                    }
                }
            }
        }

        # Docker compose override (user customizations)
        if (Test-Path (Join-Path $InstallDir "docker-compose.override.yml")) {
            $composeFlags += @("-f", "docker-compose.override.yml")
        }

        # ── Start Docker services ──
        Write-Chapter "STARTING SERVICES"
        Write-AI "Running: docker compose $($composeFlags -join ' ') up -d"
        & docker compose @composeFlags up -d 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) {
            Write-AIError "docker compose up failed (exit code: $LASTEXITCODE)"
            exit 1
        }
        Write-AISuccess "Docker services started"

        # Save compose flags for dream.ps1 (BOM-free for reliable parsing)
        $flagsFile = Join-Path $InstallDir ".compose-flags"
        Write-Utf8NoBom -Path $flagsFile -Content ($composeFlags -join " ")

    } finally {
        Pop-Location
    }
}

# ============================================================================
# STEP 6 — VERIFY
# ============================================================================
Write-Phase -Phase 6 -Total 6 -Name "VERIFICATION" -Estimate "30 seconds"

if ($DryRun) {
    Write-AI "[DRY RUN] Would health-check all services"
    Write-AI "[DRY RUN] Install validation complete"
    Write-AISuccess "Dry run finished — no changes made"
    exit 0
}

# Health check loop
$healthChecks = @(
    @{ Name = "LLM (llama-server)"; Url = "http://localhost:8080/health" }
    @{ Name = "Chat UI (Open WebUI)"; Url = "http://localhost:3000" }
)

# Add optional service checks
if ($enableVoice) {
    $healthChecks += @{ Name = "Whisper (STT)"; Url = "http://localhost:9000/health" }
}
if ($enableWorkflows) {
    $healthChecks += @{ Name = "n8n (Workflows)"; Url = "http://localhost:5678/healthz" }
}

Write-AI "Running health checks..."
$maxAttempts = 30
$allHealthy = $true

foreach ($check in $healthChecks) {
    $healthy = $false
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $check.Url -TimeoutSec 3 `
                -UseBasicParsing -ErrorAction SilentlyContinue
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
                $healthy = $true
                break
            }
        } catch { }
        if ($i -le 3 -or $i % 5 -eq 0) {
            Write-AI "  Waiting for $($check.Name)... ($i/$maxAttempts)"
        }
        Start-Sleep -Seconds 2
    }

    if ($healthy) {
        Write-AISuccess "$($check.Name): healthy"
    } else {
        Write-AIWarn "$($check.Name): not responding after $maxAttempts attempts"
        $allHealthy = $false
    }
}

# ── Success card ──
if ($allHealthy) {
    Write-SuccessCard
} else {
    Write-Host ""
    Write-AIWarn "Some services may still be starting. Check with:"
    Write-Host "  .\dream.ps1 status" -ForegroundColor Cyan
    Write-Host ""
    Write-SuccessCard
}

# ── Summary JSON (for CI/automation) ──
if ($SummaryJsonPath) {
    $summary = @{
        version     = $script:DS_VERSION
        tier        = $selectedTier
        tierName    = $tierConfig.TierName
        model       = $tierConfig.LlmModel
        gpuBackend  = $gpuInfo.Backend
        gpuName     = $gpuInfo.Name
        installDir  = $InstallDir
        features    = @{
            voice     = $enableVoice
            workflows = $enableWorkflows
            rag       = $enableRag
            openclaw  = $enableOpenClaw
        }
        healthy     = $allHealthy
        timestamp   = (Get-Date -Format "o")
    }
    $jsonContent = $summary | ConvertTo-Json -Depth 3
    Write-Utf8NoBom -Path $SummaryJsonPath -Content $jsonContent
    Write-AI "Summary written to $SummaryJsonPath"
}
