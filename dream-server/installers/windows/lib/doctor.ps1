# ============================================================================
# Dream Server Windows -- doctor diagnostics
# ============================================================================
# Part of: installers/windows/lib/
# Purpose: Operator-facing diagnostics for runtime readiness on Windows.
# Requires: ui.ps1, detection.ps1, llm-endpoint.ps1, install-report.ps1.
# ============================================================================

function Test-DreamWritableDirectory {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path -PathType Container)) {
        return $false
    }

    $probe = Join-Path $Path ".dream-doctor-write-test"
    try {
        Set-Content -Path $probe -Value "ok" -Encoding ASCII -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Test-DreamTcpPort {
    param(
        [string]$HostName = "127.0.0.1",
        [int]$Port,
        [int]$TimeoutMs = 600
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-DreamDockerImage {
    param([string]$Image)

    if ([string]::IsNullOrWhiteSpace($Image)) {
        return @{ image = $Image; status = "invalid"; reason = "empty image name" }
    }

    $local = Invoke-OptionalCommand -Command "docker" -CommandArgs @("image", "inspect", $Image) -MaxLines 1
    if ($local.ok) {
        return @{ image = $Image; status = "local"; reason = "" }
    }

    if ($env:DREAM_DOCTOR_IMAGE_MANIFEST -eq "0") {
        return @{ image = $Image; status = "unchecked"; reason = "remote manifest checks disabled" }
    }

    $remote = Invoke-OptionalCommand -Command "docker" -CommandArgs @("manifest", "inspect", $Image) -MaxLines 8
    if ($remote.ok) {
        return @{ image = $Image; status = "remote"; reason = "" }
    }

    return @{
        image = $Image
        status = "unavailable"
        reason = (($remote.lines | Select-Object -First 1) -join "")
    }
}

function New-DreamDoctorReport {
    param(
        [string]$InstallDir = $script:DS_INSTALL_DIR,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ComposeFlags
    )

    $envFile = Join-Path $InstallDir ".env"
    $envMap = Get-WindowsDreamEnvMap -InstallDir $InstallDir
    $gpu = Get-GpuInfo
    $nativeBackend = "none"
    if (Get-Command Get-NativeInferenceBackend -ErrorAction SilentlyContinue) {
        $nativeBackend = Get-NativeInferenceBackend
    }
    $llmEndpoint = Get-WindowsLocalLlmEndpoint -InstallDir $InstallDir -EnvMap $envMap -GpuBackend $gpu.Backend -NativeBackend $nativeBackend

    $dockerVersion = Invoke-OptionalCommand -Command "docker" -CommandArgs @("version") -MaxLines 40
    $dockerInfo = Invoke-OptionalCommand -Command "docker" -CommandArgs @("info") -MaxLines 80
    $composeVersion = Invoke-OptionalCommand -Command "docker" -CommandArgs @("compose", "version") -MaxLines 20
    $wslStatus = Invoke-OptionalCommand -Command "wsl.exe" -CommandArgs @("-l", "-v") -MaxLines 40

    $composeConfigArgs = @("compose") + $ComposeFlags + @("config", "--quiet")
    $composeImagesArgs = @("compose") + $ComposeFlags + @("config", "--images")
    $composeConfig = Invoke-OptionalCommand -Command "docker" -CommandArgs $composeConfigArgs -MaxLines 80
    $composeImages = Invoke-OptionalCommand -Command "docker" -CommandArgs $composeImagesArgs -MaxLines 120

    $images = @()
    if ($dockerInfo.ok -and $composeImages.ok) {
        $seen = @{}
        foreach ($line in $composeImages.lines) {
            $image = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($image) -or $seen.ContainsKey($image)) { continue }
            $seen[$image] = $true
            $images += Test-DreamDockerImage -Image $image
        }
    }

    $ggufFile = Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("GGUF_FILE") -Default ""
    $modelPath = ""
    $modelExists = $false
    $modelBytes = 0
    if (-not [string]::IsNullOrWhiteSpace($ggufFile)) {
        $modelPath = Join-Path (Join-Path $InstallDir "data\models") $ggufFile
        $modelExists = Test-Path $modelPath -PathType Leaf
        if ($modelExists) {
            $modelBytes = (Get-Item $modelPath).Length
        }
    }

    $requiredKeys = @("LLM_MODEL", "GGUF_FILE", "GPU_BACKEND", "CTX_SIZE")
    $missingKeys = @()
    foreach ($key in $requiredKeys) {
        if (-not $envMap.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$envMap[$key])) {
            $missingKeys += $key
        }
    }

    $modelsDir = Join-Path $InstallDir "data\models"
    $ports = @(
        @{ name = "llm_api"; port = [int](Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("OLLAMA_PORT") -Default "$($llmEndpoint.Port)") },
        @{ name = "open_webui"; port = [int](Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("WEBUI_PORT") -Default "3000") },
        @{ name = "dashboard"; port = [int](Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("DASHBOARD_PORT") -Default "3001") },
        @{ name = "dashboard_api"; port = [int](Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("DASHBOARD_API_PORT") -Default "3002") }
    )
    $portChecks = @()
    foreach ($p in $ports) {
        $portChecks += @{
            name = $p.name
            port = $p.port
            listening = Test-DreamTcpPort -Port $p.port
        }
    }

    $health = [ordered]@{
        llm_api = Test-HttpEndpoint -Url $llmEndpoint.HealthUrl
        open_webui = Test-HttpEndpoint -Url "http://localhost:$((Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("WEBUI_PORT") -Default "3000"))"
        dashboard = Test-HttpEndpoint -Url "http://localhost:$((Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("DASHBOARD_PORT") -Default "3001"))"
        dashboard_api = Test-HttpEndpoint -Url "http://localhost:$((Get-WindowsDreamEnvValue -EnvMap $envMap -Keys @("DASHBOARD_API_PORT") -Default "3002"))/health"
    }

    $dockerGpuPassthrough = "not_applicable"
    if ($gpu.Backend -eq "nvidia") {
        $nvidiaSmi = Invoke-OptionalCommand -Command "nvidia-smi" -CommandArgs @("--query-gpu=name", "--format=csv,noheader") -MaxLines 4
        $dockerGpuPassthrough = $(if ($dockerInfo.ok -and $nvidiaSmi.ok) { "probable" } else { "unconfirmed" })
    }

    $imageUnavailable = @($images | Where-Object { $_.status -eq "unavailable" }).Count
    $blockers = 0
    if (-not (Test-Path $InstallDir -PathType Container)) { $blockers++ }
    if (-not (Test-Path $envFile -PathType Leaf)) { $blockers++ }
    if ($missingKeys.Count -gt 0) { $blockers++ }
    if ($ggufFile -and -not $modelExists) { $blockers++ }
    if (-not $dockerVersion.ok) { $blockers++ }
    if (-not $dockerInfo.ok) { $blockers++ }
    if (-not $composeVersion.ok) { $blockers++ }
    if (-not $composeConfig.ok) { $blockers++ }
    if ($imageUnavailable -gt 0) { $blockers++ }

    $hints = @()
    if (-not (Test-Path $envFile -PathType Leaf)) { $hints += "Run the installer to regenerate .env." }
    if ($missingKeys.Count -gt 0) { $hints += "Regenerate .env or add missing required keys: $($missingKeys -join ', ')." }
    if ($ggufFile -and -not $modelExists) { $hints += "Download the configured model again: $modelPath." }
    if (-not $dockerInfo.ok) { $hints += "Start Docker Desktop and confirm the WSL 2 backend is enabled." }
    if (-not $composeConfig.ok) { $hints += "Fix the first docker compose config error shown in the report." }
    if ($imageUnavailable -gt 0) { $hints += "Replace unavailable Docker image tags or configure an explicit fallback." }
    if (-not (Test-DreamWritableDirectory -Path $InstallDir)) { $hints += "Fix permissions/ownership for $InstallDir." }
    if ((Test-Path $modelsDir) -and -not (Test-DreamWritableDirectory -Path $modelsDir)) { $hints += "Fix permissions/ownership for $modelsDir." }

    return [ordered]@{
        version = "1"
        generated_at = (Get-Date).ToString("o")
        platform = [ordered]@{
            os = "windows"
            powershell = $PSVersionTable.PSVersion.ToString()
            wsl2 = [ordered]@{
                available = $wslStatus.ok
                output = $wslStatus.lines
            }
        }
        runtime = [ordered]@{
            docker_cli = $dockerVersion.ok
            docker_daemon = $dockerInfo.ok
            compose_cli = $composeVersion.ok
            gpu_passthrough = $dockerGpuPassthrough
            llm_endpoint = $llmEndpoint
        }
        install = [ordered]@{
            env_file = [ordered]@{
                path = $envFile
                exists = Test-Path $envFile -PathType Leaf
                readable = Test-Path $envFile -PathType Leaf
                required_keys_present = ($missingKeys.Count -eq 0)
                missing_required_keys = $missingKeys
            }
            model = [ordered]@{
                gguf_file = $ggufFile
                path = $modelPath
                exists = $modelExists
                bytes = $modelBytes
            }
            permissions = [ordered]@{
                install_dir_writable = Test-DreamWritableDirectory -Path $InstallDir
                models_dir_exists = Test-Path $modelsDir -PathType Container
                models_dir_writable = Test-DreamWritableDirectory -Path $modelsDir
            }
        }
        compose = [ordered]@{
            flags = @($ComposeFlags)
            config_ok = $composeConfig.ok
            config_exit_code = $composeConfig.exit_code
            config_output = $composeConfig.lines
            images = @($images)
        }
        ports = @($portChecks)
        health = $health
        summary = [ordered]@{
            blockers = $blockers
            docker_images_unavailable = $imageUnavailable
            env_ready = ((Test-Path $envFile -PathType Leaf) -and $missingKeys.Count -eq 0)
            model_ready = ((-not $ggufFile) -or $modelExists)
            compose_config_ok = $composeConfig.ok
        }
        autofix_hints = @($hints | Select-Object -Unique)
    }
}

function Invoke-DreamDoctor {
    param(
        [string]$InstallDir = $script:DS_INSTALL_DIR,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ComposeFlags,
        [string]$ReportPath = "",
        [switch]$Json
    )

    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $artifactsDir = Join-Path (Join-Path $InstallDir "artifacts") "doctor"
        New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
        $ReportPath = Join-Path $artifactsDir "doctor.json"
    } else {
        $parent = Split-Path -Parent $ReportPath
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }

    $report = New-DreamDoctorReport -InstallDir $InstallDir -ComposeFlags $ComposeFlags
    ($report | ConvertTo-Json -Depth 10) | Set-Content -Path $ReportPath -Encoding UTF8
    $script:DreamDoctorLastBlockers = [int]$report.summary.blockers

    if ($Json) {
        Get-Content $ReportPath -Raw
        return
    }

    Write-Host ""
    Write-Chapter "DREAM DOCTOR"
    Write-AI "Report: $ReportPath"
    Write-Host ""

    $ok = "OK"
    $fail = "FAIL"
    Write-Host "Runtime" -ForegroundColor Cyan
    Write-Host "  Docker CLI:      $(if ($report.runtime.docker_cli) { $ok } else { $fail })"
    Write-Host "  Docker daemon:   $(if ($report.runtime.docker_daemon) { $ok } else { $fail })"
    Write-Host "  Docker Compose:  $(if ($report.runtime.compose_cli) { $ok } else { $fail })"
    Write-Host "  GPU passthrough: $($report.runtime.gpu_passthrough)"
    Write-Host ""

    Write-Host "Installation" -ForegroundColor Cyan
    Write-Host "  .env:            $(if ($report.install.env_file.exists -and $report.install.env_file.required_keys_present) { $ok } else { $fail })"
    Write-Host "  Model:           $(if ($report.install.model.exists -or -not $report.install.model.gguf_file) { $ok } else { $fail })"
    Write-Host "  Permissions:     $(if ($report.install.permissions.install_dir_writable) { $ok } else { $fail })"
    Write-Host ""

    Write-Host "Compose and Images" -ForegroundColor Cyan
    Write-Host "  Compose config:  $(if ($report.compose.config_ok) { $ok } else { $fail })"
    $imageCount = @($report.compose.images).Count
    $badImages = $report.summary.docker_images_unavailable
    Write-Host "  Images:          $($imageCount - $badImages)/$imageCount resolvable"
    Write-Host ""

    Write-Host "Health" -ForegroundColor Cyan
    foreach ($key in $report.health.Keys) {
        Write-Host ("  {0,-15} {1}" -f "${key}:", $(if ($report.health[$key].ok) { $ok } else { $fail }))
    }

    if ($report.autofix_hints.Count -gt 0) {
        Write-Host ""
        Write-Host "Suggested fixes" -ForegroundColor Cyan
        foreach ($hint in ($report.autofix_hints | Select-Object -First 8)) {
            Write-Host "  - $hint"
        }
    }

    return
}
