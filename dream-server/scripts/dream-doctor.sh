#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    echo "Usage: $0 [REPORT_PATH]"
    echo "       $0 --help"
    echo ""
    echo "Generates a machine-readable diagnostics report for installer and runtime readiness."
    echo "Report includes capability profile, preflight-style analysis, and autofix_hints."
    echo ""
    echo "Arguments:"
    echo "  REPORT_PATH  Output JSON path (default: /tmp/dream-doctor-report.json)"
    echo ""
    echo "Exit codes: 0 = report generated, 1 = error (e.g. missing dependency)"
    echo ""
    echo "See docs/DREAM-DOCTOR.md for details."
}
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

REPORT_FILE="${1:-/tmp/dream-doctor-report.json}"

CAP_FILE="/tmp/dream-doctor-capabilities.json"
PREFLIGHT_FILE="/tmp/dream-doctor-preflight.json"

# Source service registry and safe env helpers
if [[ -f "$ROOT_DIR/lib/service-registry.sh" ]]; then
    export SCRIPT_DIR="$ROOT_DIR"
    . "$ROOT_DIR/lib/service-registry.sh"
    sr_load
fi
if [[ -f "$ROOT_DIR/lib/safe-env.sh" ]]; then
    . "$ROOT_DIR/lib/safe-env.sh"
fi

# Safe .env loading (no direct source to avoid injection)
load_env_safe() {
    local env_file="${1:-$ROOT_DIR/.env}"
    [[ -f "$env_file" ]] || return 0
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        export "$key=$value"
    done < "$env_file"
}
load_env_safe "$ROOT_DIR/.env"
sr_resolve_ports
_DASHBOARD_PORT="${SERVICE_PORTS[dashboard]:-3001}"
_WEBUI_PORT="${SERVICE_PORTS[open-webui]:-3000}"

# RAM: platform-branch. /proc/meminfo does not exist on macOS; use sysctl.
if [[ "$(uname -s)" == "Darwin" ]]; then
    RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    RAM_GB=$(( RAM_BYTES / 1024 / 1024 / 1024 ))
else
    RAM_GB="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1024/1024)}' || echo 0)"
fi
# Installer-recorded fallback: if detection returned 0 and .env has HOST_RAM_GB, trust that.
if (( RAM_GB == 0 )) && [[ -f "$ROOT_DIR/.env" ]]; then
    _env_ram=$(grep '^HOST_RAM_GB=' "$ROOT_DIR/.env" | cut -d= -f2 | tr -d '"' || true)
    [[ -n "${_env_ram:-}" ]] && RAM_GB="$_env_ram"
fi

# Disk: POSIX df -k — works on BSD and GNU identically (df -BG is GNU-only).
DISK_GB="$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print int($4/1024/1024)}' || echo 0)"

if [[ -x "$SCRIPT_DIR/scripts/build-capability-profile.sh" ]]; then
    CAP_ENV="$("$SCRIPT_DIR/scripts/build-capability-profile.sh" --output "$CAP_FILE" --env)"
    load_env_from_output <<< "$CAP_ENV"
else
    echo "scripts/build-capability-profile.sh not found/executable" >&2
    exit 1
fi

if [[ -x "$SCRIPT_DIR/scripts/preflight-engine.sh" ]]; then
    PREFLIGHT_ENV="$("$SCRIPT_DIR/scripts/preflight-engine.sh" \
        --report "$PREFLIGHT_FILE" \
        --tier "${CAP_RECOMMENDED_TIER:-T1}" \
        --ram-gb "$RAM_GB" \
        --disk-gb "$DISK_GB" \
        --gpu-backend "${CAP_LLM_BACKEND:-cpu}" \
        --gpu-vram-mb "${CAP_GPU_VRAM_MB:-0}" \
        --gpu-name "${CAP_GPU_NAME:-Unknown}" \
        --platform-id "${CAP_PLATFORM_ID:-unknown}" \
        --compose-overlays "${CAP_COMPOSE_OVERLAYS:-}" \
        --script-dir "$ROOT_DIR" \
        --env)"
    load_env_from_output <<< "$PREFLIGHT_ENV"
else
    echo "scripts/preflight-engine.sh not found/executable" >&2
    exit 1
fi

DOCKER_CLI="false"
DOCKER_DAEMON="false"
COMPOSE_CLI="false"
DASHBOARD_HTTP="false"
WEBUI_HTTP="false"

# Extension diagnostics (JSON array of objects)
EXT_DIAGNOSTICS="[]"

if command -v docker >/dev/null 2>&1; then
    DOCKER_CLI="true"
    if docker info >/dev/null 2>&1; then
        DOCKER_DAEMON="true"
    fi
    if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CLI="true"
    fi
fi

if command -v curl >/dev/null 2>&1; then
    if curl -sf --max-time 10 "http://127.0.0.1:${_DASHBOARD_PORT}" >/dev/null 2>&1; then
        DASHBOARD_HTTP="true"
    fi
    if curl -sf --max-time 10 "http://127.0.0.1:${_WEBUI_PORT}" >/dev/null 2>&1; then
        WEBUI_HTTP="true"
    fi
fi

# STT model cache check: a common silent-failure mode is the installer's
# pre-download failing, so Whisper's /health passes (service up) but the
# model isn't cached. Transcription then returns 404. This check catches
# that case and surfaces the exact recovery command.
STT_MODEL_CACHED="unknown"
STT_MODEL_NAME=""
STT_RECOVERY_HINT=""
if [[ "${ENABLE_VOICE:-false}" == "true" ]] && command -v curl >/dev/null 2>&1; then
    STT_MODEL_NAME="${AUDIO_STT_MODEL:-Systran/faster-whisper-base}"
    _stt_whisper_port="${SERVICE_PORTS[whisper]:-9000}"
    _stt_model_encoded="${STT_MODEL_NAME//\//%2F}"
    _stt_whisper_url="http://127.0.0.1:${_stt_whisper_port}"
    if curl -sf --max-time 5 "${_stt_whisper_url}/v1/models/${_stt_model_encoded}" >/dev/null 2>&1; then
        STT_MODEL_CACHED="true"
    else
        # Distinguish "service down" from "model missing" for the hint.
        if curl -sf --max-time 5 "${_stt_whisper_url}/health" >/dev/null 2>&1; then
            STT_MODEL_CACHED="false"
            STT_RECOVERY_HINT="curl --max-time 3600 -X POST ${_stt_whisper_url}/v1/models/${_stt_model_encoded}"
        else
            STT_MODEL_CACHED="service_down"
        fi
    fi
fi

# DGX Spark / GB10 CUDA arch check. Generic llama.cpp CUDA images can run on
# GB10 while missing sm_121 support, which has been observed to produce
# syntactically valid but unusable model output. Surface that mismatch in
# doctor so operators do not have to infer it from llama-server logs.
DGX_SPARK_GPU="false"
DGX_SPARK_GPU_NAME=""
DGX_SPARK_COMPUTE_CAP=""
LLAMA_CUDA_ARCHS=""
DGX_SPARK_CUDA_ARCH_STATUS="unknown"
DGX_SPARK_CUDA_ARCH_MESSAGE=""
_doctor_gpu_backend="${GPU_BACKEND:-${CAP_LLM_BACKEND:-}}"
if [[ "$_doctor_gpu_backend" == "nvidia" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    _dgx_gpu_raw="$(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader,nounits 2>/dev/null | head -1 || true)"
    if [[ -n "$_dgx_gpu_raw" ]]; then
        DGX_SPARK_GPU_NAME="$(echo "$_dgx_gpu_raw" | cut -d',' -f1 | xargs)"
        DGX_SPARK_COMPUTE_CAP="$(echo "$_dgx_gpu_raw" | cut -d',' -f2 | xargs)"
        if [[ "$DGX_SPARK_GPU_NAME" == *"GB10"* || "$DGX_SPARK_COMPUTE_CAP" == "12.1" ]]; then
            DGX_SPARK_GPU="true"
            if [[ "$DOCKER_DAEMON" == "true" ]] && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'dream-llama-server'; then
                _llama_arch_line="$(docker logs dream-llama-server 2>&1 | grep 'CUDA : ARCHS =' | tail -1 || true)"
                LLAMA_CUDA_ARCHS="$(echo "$_llama_arch_line" | sed -n 's/.*CUDA : ARCHS = \([^|]*\).*/\1/p' | xargs)"
                if [[ -z "$LLAMA_CUDA_ARCHS" ]]; then
                    DGX_SPARK_CUDA_ARCH_STATUS="unknown"
                    DGX_SPARK_CUDA_ARCH_MESSAGE="DGX Spark detected, but llama-server CUDA archs were not found in logs."
                elif [[ ",${LLAMA_CUDA_ARCHS}," == *",1210,"* || ",${LLAMA_CUDA_ARCHS}," == *",121,"* || ",${LLAMA_CUDA_ARCHS}," == *",121a,"* ]]; then
                    DGX_SPARK_CUDA_ARCH_STATUS="pass"
                    DGX_SPARK_CUDA_ARCH_MESSAGE="DGX Spark llama-server binary includes sm_121 support."
                else
                    DGX_SPARK_CUDA_ARCH_STATUS="warn"
                    DGX_SPARK_CUDA_ARCH_MESSAGE="DGX Spark detected, but llama-server reports CUDA archs '${LLAMA_CUDA_ARCHS}' without sm_121."
                fi
            else
                DGX_SPARK_CUDA_ARCH_STATUS="unknown"
                DGX_SPARK_CUDA_ARCH_MESSAGE="DGX Spark detected, but dream-llama-server is not available for CUDA arch inspection."
            fi
        fi
    fi
fi

# Collect extension diagnostics (wrapped in function to allow local variables)
collect_extension_diagnostics() {
    # Use outer GPU_BACKEND or default to nvidia (don't make local to avoid set -u issues)
    local backend="${GPU_BACKEND-nvidia}"
    local EXT_DIAG_ITEMS=()

    for sid in "${SERVICE_IDS[@]}"; do
        # Skip core services
        [[ "${SERVICE_CATEGORIES[$sid]:-}" == "core" ]] && continue

        # Check if extension is enabled
        local compose_file="${SERVICE_COMPOSE[$sid]:-}"
        [[ -z "$compose_file" || ! -f "$compose_file" ]] && continue

        # Build diagnostic entry
        local container="${SERVICE_CONTAINERS[$sid]:-}"
        local container_state="unknown"
        local health_status="unknown"
        local issues=()

        # Check container state
        if [[ "$DOCKER_DAEMON" == "true" && -n "$container" ]]; then
            local inspect_output
            inspect_output=$(docker inspect --format '{{.State.Status}}' "$container" 2>&1)
            if [[ $? -eq 0 ]]; then
                container_state="$inspect_output"
            else
                container_state="not_found"
            fi

            # Check health endpoint if container running
            if [[ "$container_state" == "running" ]]; then
                local port="${SERVICE_PORTS[$sid]:-0}"
                local health="${SERVICE_HEALTH[$sid]:-}"
                if [[ "$port" != "0" && -n "$health" ]]; then
                    if curl -sf --max-time 5 "http://127.0.0.1:${port}${health}" >/dev/null 2>&1; then
                        health_status="healthy"
                    else
                        health_status="unhealthy"
                        issues+=("health_check_failed")
                    fi
                fi
            else
                issues+=("container_not_running")
            fi
        fi

        # Check GPU backend compatibility (only if SERVICE_GPU_BACKENDS array exists from PR #357).
        # dashboard-api uses GPU_BACKEND=nvidia internally on macOS (see
        # installers/macos/docker-compose.macos.yml) so service manifests are
        # discovered. doctor/preflight path doesn't have that workaround, so the
        # raw gpu_backends check produces false positives for CPU-only services
        # declaring gpu_backends: [amd, nvidia]. Skip the check on apple — if a
        # service genuinely needs GPU and isn't available on Apple, it's a
        # manifest-level concern, not a runtime doctor warning.
        if [[ "$backend" != "apple" ]] && declare -p SERVICE_GPU_BACKENDS &>/dev/null; then
            local gpu_backends="${SERVICE_GPU_BACKENDS[$sid]:-}"
            if [[ -n "$gpu_backends" && ! " $gpu_backends " =~ " $backend " ]]; then
                issues+=("gpu_backend_incompatible")
            fi
        fi

        # Check dependencies
        local deps="${SERVICE_DEPENDS[$sid]:-}"
        if [[ -n "$deps" ]]; then
            local dep
            for dep in $deps; do
                local dep_compose="${SERVICE_COMPOSE[$dep]:-}"
                local dep_cat="${SERVICE_CATEGORIES[$dep]:-}"
                if [[ "$dep_cat" != "core" && ! -f "$dep_compose" ]]; then
                    issues+=("missing_dependency:$dep")
                fi
            done
        fi

        # Build JSON object (escape quotes in values)
        local issues_json="[]"
        if [[ ${#issues[@]} -gt 0 ]]; then
            # Use printf with newline separator, then convert to JSON array
            issues_json="[\"$(printf '%s\n' "${issues[@]}" | sed 's/"/\\"/g' | tr '\n' ',' | sed 's/,$//' | sed 's/,/","/g')\"]"
        fi

        EXT_DIAG_ITEMS+=("{\"id\":\"$sid\",\"container_state\":\"$container_state\",\"health_status\":\"$health_status\",\"issues\":$issues_json}")
    done

    if [[ ${#EXT_DIAG_ITEMS[@]} -gt 0 ]]; then
        echo "[$(IFS=,; echo "${EXT_DIAG_ITEMS[*]}")]"
    else
        echo "[]"
    fi
}

# Collect extension diagnostics if service registry loaded
EXT_DIAGNOSTICS="[]"
if [[ "${#SERVICE_IDS[@]}" -gt 0 ]]; then
    EXT_DIAGNOSTICS=$(collect_extension_diagnostics)
fi

PYTHON_CMD="python3"
if [[ -f "$ROOT_DIR/lib/python-cmd.sh" ]]; then
    . "$ROOT_DIR/lib/python-cmd.sh"
    PYTHON_CMD="$(ds_detect_python_cmd)"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
fi

"$PYTHON_CMD" - "$CAP_FILE" "$PREFLIGHT_FILE" "$REPORT_FILE" "$DOCKER_CLI" "$DOCKER_DAEMON" "$COMPOSE_CLI" "$DASHBOARD_HTTP" "$WEBUI_HTTP" "$_DASHBOARD_PORT" "$_WEBUI_PORT" "$EXT_DIAGNOSTICS" "$STT_MODEL_CACHED" "$STT_MODEL_NAME" "$STT_RECOVERY_HINT" "$DGX_SPARK_GPU" "$DGX_SPARK_GPU_NAME" "$DGX_SPARK_COMPUTE_CAP" "$LLAMA_CUDA_ARCHS" "$DGX_SPARK_CUDA_ARCH_STATUS" "$DGX_SPARK_CUDA_ARCH_MESSAGE" "$ROOT_DIR" <<'PY'
import json
import os
import pathlib
import shlex
import subprocess
import sys
from datetime import datetime, timezone

cap_file, preflight_file, report_file, docker_cli, docker_daemon, compose_cli, dashboard_http, webui_http, dashboard_port, webui_port, ext_diagnostics_json, stt_cached, stt_model_name, stt_recovery, dgx_spark_gpu, dgx_spark_gpu_name, dgx_spark_compute_cap, llama_cuda_archs, dgx_spark_arch_status, dgx_spark_arch_message, root_dir_arg = sys.argv[1:]

cap = json.load(open(cap_file, "r", encoding="utf-8"))
pre = json.load(open(preflight_file, "r", encoding="utf-8"))
ext_diagnostics = json.loads(ext_diagnostics_json)
root_dir = pathlib.Path(root_dir_arg)

def read_env(path):
    env = {}
    if not path.exists():
        return env
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if (
            not key
            or not (key[0].isalpha() or key[0] == "_")
            or not all(ch.isalnum() or ch == "_" for ch in key)
        ):
            continue
        value = value.strip().strip('"').strip("'")
        env[key] = value
    return env

def run_cmd(args, timeout=15, cwd=None):
    try:
        proc = subprocess.run(
            args,
            cwd=str(cwd or root_dir),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        return {
            "ok": proc.returncode == 0,
            "exit_code": proc.returncode,
            "stdout": proc.stdout[-4000:],
            "stderr": proc.stderr[-4000:],
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "exit_code": 124,
            "stdout": (exc.stdout or "")[-4000:] if isinstance(exc.stdout, str) else "",
            "stderr": (exc.stderr or "")[-4000:] if isinstance(exc.stderr, str) else "",
            "timed_out": True,
        }
    except Exception as exc:
        return {
            "ok": False,
            "exit_code": -1,
            "stdout": "",
            "stderr": str(exc),
            "timed_out": False,
        }

def is_writable_dir(path):
    if not path.exists() or not path.is_dir():
        return False
    probe = path / ".dream-doctor-write-test"
    try:
        probe.write_text("ok", encoding="utf-8")
        probe.unlink(missing_ok=True)
        return True
    except Exception:
        try:
            probe.unlink(missing_ok=True)
        except Exception:
            pass
        return False

def resolve_compose_flags(env):
    flags_file = root_dir / ".compose-flags"
    if flags_file.exists():
        try:
            return shlex.split(flags_file.read_text(encoding="utf-8").strip())
        except Exception:
            pass
    flags = ["--env-file", ".env"]
    base = root_dir / "docker-compose.base.yml"
    if base.exists():
        flags += ["-f", "docker-compose.base.yml"]
        backend = (env.get("GPU_BACKEND") or cap.get("runtime", {}).get("llm_backend") or "nvidia").lower()
        overlay_map = {
            "nvidia": "docker-compose.nvidia.yml",
            "cpu": "docker-compose.cpu.yml",
            "intel": "docker-compose.intel.yml",
            "sycl": "docker-compose.intel.yml",
            "amd": "docker-compose.amd.yml",
            "apple": "docker-compose.apple.yml",
        }
        overlay = overlay_map.get(backend)
        if overlay and (root_dir / overlay).exists():
            flags += ["-f", overlay]
    elif (root_dir / "docker-compose.yml").exists():
        flags += ["-f", "docker-compose.yml"]
    return flags

def collect_install_diagnostics(env):
    env_path = root_dir / ".env"
    models_dir = root_dir / "data" / "models"
    gguf_file = env.get("GGUF_FILE", "")
    model_path = models_dir / gguf_file if gguf_file else None
    required_keys = ["LLM_MODEL", "GGUF_FILE", "GPU_BACKEND", "CTX_SIZE"]
    missing_keys = [key for key in required_keys if not env.get(key)]
    model_exists = bool(model_path and model_path.exists() and model_path.is_file())
    model_bytes = model_path.stat().st_size if model_exists else 0
    return {
        "env_file": {
            "path": str(env_path),
            "exists": env_path.exists(),
            "readable": os.access(env_path, os.R_OK) if env_path.exists() else False,
            "writable": os.access(env_path, os.W_OK) if env_path.exists() else False,
            "required_keys_present": len(missing_keys) == 0,
            "missing_required_keys": missing_keys,
        },
        "model": {
            "gguf_file": gguf_file,
            "path": str(model_path) if model_path else "",
            "exists": model_exists,
            "bytes": model_bytes,
        },
        "permissions": {
            "install_dir_writable": is_writable_dir(root_dir),
            "models_dir_exists": models_dir.exists(),
            "models_dir_writable": is_writable_dir(models_dir) if models_dir.exists() else False,
        },
    }

def collect_compose_and_images(env):
    flags = resolve_compose_flags(env)
    compose = {
        "flags": flags,
        "config_ok": False,
        "config_exit_code": -1,
        "config_error": "",
        "images": [],
    }
    if docker_cli != "true" or not flags:
        compose["config_error"] = "docker CLI missing or compose flags unavailable"
        return compose

    cfg = run_cmd(["docker", "compose", *flags, "config", "--quiet"], timeout=30)
    compose["config_ok"] = cfg["ok"]
    compose["config_exit_code"] = cfg["exit_code"]
    compose["config_error"] = cfg["stderr"] or cfg["stdout"]

    image_cfg = run_cmd(["docker", "compose", *flags, "config", "--images"], timeout=30)
    raw_images = []
    if image_cfg["ok"]:
        raw_images = [line.strip() for line in image_cfg["stdout"].splitlines() if line.strip()]
    else:
        compose["images_error"] = image_cfg["stderr"] or image_cfg["stdout"]

    seen = set()
    images = []
    manifest_checks = os.environ.get("DREAM_DOCTOR_IMAGE_MANIFEST", "1") != "0"
    for image in raw_images:
        if image in seen:
            continue
        seen.add(image)
        item = {"image": image, "status": "unchecked", "source": "compose"}
        if docker_daemon != "true":
            item["reason"] = "docker daemon unavailable"
        else:
            local = run_cmd(["docker", "image", "inspect", image], timeout=8)
            if local["ok"]:
                item["status"] = "local"
            elif manifest_checks:
                remote = run_cmd(["docker", "manifest", "inspect", image], timeout=20)
                item["status"] = "remote" if remote["ok"] else "unavailable"
                if not remote["ok"]:
                    item["reason"] = "manifest inspect failed"
            else:
                item["reason"] = "manifest checks disabled"
        images.append(item)
    compose["images"] = images
    return compose

env_map = read_env(root_dir / ".env")
install_diag = collect_install_diagnostics(env_map)
compose_diag = collect_compose_and_images(env_map)

report = {
    "version": "1",
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "autofix_hints": [],
    "capability_profile": cap,
    "preflight": pre,
    "runtime": {
        "docker_cli": docker_cli == "true",
        "docker_daemon": docker_daemon == "true",
        "compose_cli": compose_cli == "true",
        "dashboard_http": dashboard_http == "true",
        "webui_http": webui_http == "true",
        "stt_model_cached": stt_cached,
        "stt_model_name": stt_model_name,
        "dgx_spark_gpu": dgx_spark_gpu == "true",
        "dgx_spark_gpu_name": dgx_spark_gpu_name,
        "dgx_spark_compute_cap": dgx_spark_compute_cap,
        "llama_cuda_archs": llama_cuda_archs,
        "dgx_spark_cuda_arch_check": {
            "status": dgx_spark_arch_status,
            "message": dgx_spark_arch_message,
        },
    },
    "install": install_diag,
    "compose": compose_diag,
    "extensions": ext_diagnostics,
    "summary": {
        "preflight_blockers": pre.get("summary", {}).get("blockers", 0),
        "preflight_warnings": pre.get("summary", {}).get("warnings", 0),
        "runtime_warnings": 1 if dgx_spark_arch_status == "warn" else 0,
        "runtime_ready": (docker_daemon == "true" and compose_cli == "true"),
        "env_ready": install_diag["env_file"]["exists"] and install_diag["env_file"]["required_keys_present"],
        "model_ready": install_diag["model"]["exists"],
        "compose_config_ok": compose_diag["config_ok"],
        "docker_images_unavailable": sum(1 for i in compose_diag["images"] if i.get("status") == "unavailable"),
        "extensions_total": len(ext_diagnostics),
        "extensions_healthy": sum(1 for e in ext_diagnostics if e.get("health_status") == "healthy"),
        "extensions_issues": sum(1 for e in ext_diagnostics if len(e.get("issues", [])) > 0),
    },
}

fix_hints = []
for check in pre.get("checks", []):
    status = check.get("status")
    action = (check.get("action") or "").strip()
    if status in {"blocker", "warn"} and action:
        fix_hints.append(action)

runtime = report["runtime"]
if not runtime["docker_cli"]:
    fix_hints.append("Install Docker CLI/Docker Desktop and reopen your terminal.")
if runtime["docker_cli"] and not runtime["docker_daemon"]:
    fix_hints.append("Start Docker daemon/Desktop before launching Dream Server.")
if not runtime["compose_cli"]:
    fix_hints.append("Install Docker Compose v2 plugin (or docker-compose).")
if runtime["docker_daemon"] and not runtime["dashboard_http"]:
    fix_hints.append(f"Run installer/start command, then verify dashboard on http://127.0.0.1:{dashboard_port}.")
if runtime["docker_daemon"] and not runtime["webui_http"]:
    fix_hints.append(f"Verify Open WebUI container and port {webui_port} mapping.")

env_diag = report["install"]["env_file"]
if not env_diag["exists"]:
    fix_hints.append("Run the installer to generate .env, or restore .env from backup.")
elif not env_diag["required_keys_present"]:
    fix_hints.append("Regenerate .env or add missing required keys: " + ", ".join(env_diag["missing_required_keys"]))

model_diag = report["install"]["model"]
if model_diag["gguf_file"] and not model_diag["exists"]:
    fix_hints.append(f"Model file missing: {model_diag['path']}. Re-run the installer or model download step.")

perms = report["install"]["permissions"]
if not perms["install_dir_writable"]:
    fix_hints.append(f"Fix ownership/permissions for install directory: {root_dir}")
if perms["models_dir_exists"] and not perms["models_dir_writable"]:
    fix_hints.append(f"Fix ownership/permissions for model directory: {root_dir / 'data' / 'models'}")

if not report["compose"]["config_ok"]:
    fix_hints.append("Run `docker compose ... config` using the reported compose flags and fix the first YAML/env error.")
missing_images = [i["image"] for i in report["compose"]["images"] if i.get("status") == "unavailable"]
if missing_images:
    fix_hints.append("Docker image tag unavailable: " + ", ".join(missing_images[:3]))

# STT model cache: service up but model missing is a common silent failure
if stt_cached == "false" and stt_recovery:
    fix_hints.append(
        f"Whisper STT model '{stt_model_name}' not cached — transcription will 404. "
        f"Run: {stt_recovery}"
    )

if dgx_spark_arch_status == "warn":
    fix_hints.append(
        "DGX Spark / GB10 detected, but llama-server was not built with sm_121 support. "
        "Build llama.cpp with -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=121 or use a GB10-specific llama-server image."
    )

# Extension-specific hints
for ext in ext_diagnostics:
    ext_id = ext.get("id", "unknown")
    container_state = ext.get("container_state", "unknown")
    issues = ext.get("issues", [])
    for issue in issues:
        if issue == "container_not_running":
            if container_state == "not_found":
                fix_hints.append(f"Extension {ext_id}: not installed (image not built). Skipped by installer or disabled by tier system.")
            else:
                fix_hints.append(f"Extension {ext_id}: container not running. Run 'dream start {ext_id}'.")
        elif issue == "health_check_failed":
            fix_hints.append(f"Extension {ext_id}: health check failed. Check logs with 'docker logs dream-{ext_id}'.")
        elif issue == "gpu_backend_incompatible":
            fix_hints.append(f"Extension {ext_id}: incompatible with current GPU backend. Consider disabling.")
        elif issue.startswith("missing_dependency:"):
            dep = issue.split(":", 1)[1]
            fix_hints.append(f"Extension {ext_id}: missing dependency '{dep}'. Run 'dream enable {dep}'.")


# Deduplicate while preserving order
seen = set()
uniq_hints = []
for hint in fix_hints:
    if hint in seen:
        continue
    seen.add(hint)
    uniq_hints.append(hint)

report["autofix_hints"] = uniq_hints  # overwrite initial empty list

path = pathlib.Path(report_file)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
PY

echo "Dream Doctor report: $REPORT_FILE"
echo "  Preflight blockers: ${PREFLIGHT_BLOCKERS:-0}"
echo "  Preflight warnings: ${PREFLIGHT_WARNINGS:-0}"
echo "  Docker daemon: $DOCKER_DAEMON"
echo "  Compose CLI:   $COMPOSE_CLI"
"$PYTHON_CMD" - "$REPORT_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    data = json.load(open(path, "r", encoding="utf-8"))
except Exception:
    raise SystemExit(0)

# Show extension summary
summary = data.get("summary", {})
ext_total = summary.get("extensions_total", 0)
ext_healthy = summary.get("extensions_healthy", 0)
ext_issues = summary.get("extensions_issues", 0)

if ext_total > 0:
    print(f"  Extensions:    {ext_healthy}/{ext_total} healthy, {ext_issues} with issues")

install = data.get("install", {})
if install:
    env_file = install.get("env_file", {})
    model = install.get("model", {})
    env_ready = env_file.get("exists") and env_file.get("required_keys_present")
    model_ready = model.get("exists") if model.get("gguf_file") else None
    print(f"  Env file:      {'ready' if env_ready else 'needs attention'}")
    if model_ready is None:
        print("  Model file:    not configured")
    else:
        print(f"  Model file:    {'present' if model_ready else 'missing'}")

compose = data.get("compose", {})
if compose:
    images = compose.get("images") or []
    unavailable = [i for i in images if i.get("status") == "unavailable"]
    print(f"  Compose:       {'ok' if compose.get('config_ok') else 'needs attention'}")
    if images:
        print(f"  Images:        {len(images) - len(unavailable)}/{len(images)} resolvable")

dgx_check = data.get("runtime", {}).get("dgx_spark_cuda_arch_check", {})
if dgx_check.get("status") == "warn":
    print(f"  DGX Spark:     warning - {dgx_check.get('message')}")
elif dgx_check.get("status") == "pass":
    print("  DGX Spark:     llama-server includes sm_121 support")

hints = data.get("autofix_hints") or []
if hints:
    print("  Suggested fixes:")
    for hint in hints[:10]:
        print(f"    - {hint}")
PY
