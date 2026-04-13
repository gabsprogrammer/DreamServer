#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import select
import shutil
import subprocess
import sys
import threading
import time
from http import HTTPStatus
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ANSI_RE = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
PROMPT_MARKER = b"\x1b[32m> \x1b[0m"
PT_HINT_RE = re.compile(
    r"(?:\b(?:oi|ol[aá]|voc[eê]|voce|como|qual|quero|preciso|pode|pra|para|"
    r"me|minha|minhas|meu|meus|reuni[aã]o|amanh[aã]|email|celular|arquivo|"
    r"explica|resuma|gera|gerar|manda|enviar|obrigad[oa]|ajuda)\b|[ãõçáéíóú])",
    re.IGNORECASE,
)


def json_response(handler: "DreamMobileHandler", payload: dict[str, Any], status: int = 200) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def write_ndjson_event(handler: "DreamMobileHandler", payload: dict[str, Any]) -> None:
    handler.wfile.write(json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n")
    handler.wfile.flush()


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def parse_temp(raw: str | None) -> float | None:
    if not raw:
        return None
    try:
        value = float(raw)
    except ValueError:
        return None
    if value > 1000:
        value = value / 1000.0
    if 5 <= value <= 150:
        return round(value, 1)
    return None


def shell_json(command: list[str], timeout: float = 2.0) -> dict[str, Any] | None:
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def shell_text(command: list[str], timeout: float = 1.0) -> str | None:
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    text = proc.stdout.strip()
    return text or None


def compact_path(path: str, limit: int = 58) -> str:
    if len(path) <= limit:
        return path
    parts = Path(path).parts
    if len(parts) <= 3:
        return "…" + path[-(limit - 1) :]
    tail = str(Path(*parts[-3:]))
    if len(tail) + 4 <= limit:
        return f"…/{tail}"
    return "…" + tail[-(limit - 1) :]


class ChatSession:
    def __init__(self, chat_bin: str, model_path: str, context: int) -> None:
        self.chat_bin = chat_bin
        self.model_path = model_path
        self.context = context
        self.process: subprocess.Popen[bytes] | None = None
        self.lock = threading.Lock()
        self.started_at: float | None = None
        self.turns = 0
        self.total_messages = 0
        self.total_reply_chars = 0
        self.last_latency_ms: int | None = None
        self.last_reply_chars = 0
        self.last_reply_at: float | None = None
        self.warming = False

    def _clean(self, data: bytes) -> str:
        return ANSI_RE.sub(b"", data).decode("utf-8", errors="ignore").replace("\r", "")

    def _read_until_prompt(self, timeout: float) -> str:
        assert self.process is not None and self.process.stdout is not None

        deadline = time.time() + timeout
        buffer = bytearray()

        while time.time() < deadline:
            if self.process.poll() is not None and not buffer:
                raise RuntimeError("llama chat process exited unexpectedly")

            ready, _, _ = select.select([self.process.stdout], [], [], 0.2)
            if not ready:
                continue

            chunk = os.read(self.process.stdout.fileno(), 2048)
            if not chunk:
                if self.process.poll() is not None:
                    break
                continue

            buffer.extend(chunk)
            marker_index = buffer.find(PROMPT_MARKER)
            if marker_index != -1:
                return self._clean(bytes(buffer[:marker_index])).strip()

        raise TimeoutError("timed out waiting for the local chat response")

    def _prepare_user_message(self, message: str, locale_hint: str | None) -> str:
        locale = (locale_hint or "").lower()
        use_portuguese = bool(PT_HINT_RE.search(message)) or locale.startswith("pt")
        if use_portuguese:
            return (
                "Responda em portugues do Brasil. "
                "Seja natural, direto e util. "
                "Nao mostre raciocinio interno.\n\n"
                f"Pergunta do usuario:\n{message}"
            )
        return (
            "Reply in the same language as the user. "
            "Be direct, natural, and helpful. "
            "Do not reveal internal reasoning.\n\n"
            f"User message:\n{message}"
        )

    def ensure_started(self) -> None:
        if self.process and self.process.poll() is None:
            return

        self.process = subprocess.Popen(
            [
                self.chat_bin,
                "-m",
                self.model_path,
                "-c",
                str(self.context),
                "-ngl",
                "0",
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
        )
        self.started_at = time.time()
        self.turns = 0
        self._read_until_prompt(timeout=180)

    def prewarm(self) -> None:
        if self.warming:
            return
        self.warming = True
        try:
            with self.lock:
                self.ensure_started()
        except Exception:
            # Best effort only; the first real request will retry.
            self.reset()
        finally:
            self.warming = False

    def stream(self, message: str, locale_hint: str | None = None):
        with self.lock:
            self.ensure_started()
            assert self.process is not None and self.process.stdin is not None and self.process.stdout is not None

            prepared = self._prepare_user_message(message, locale_hint)
            self.process.stdin.write(prepared.encode("utf-8") + b"\n")
            self.process.stdin.flush()

            started = time.time()
            deadline = started + 300
            buffer = bytearray()
            emitted = ""

            while time.time() < deadline:
                if self.process.poll() is not None and not buffer:
                    raise RuntimeError("llama chat process exited unexpectedly")

                ready, _, _ = select.select([self.process.stdout], [], [], 0.2)
                if not ready:
                    continue

                chunk = os.read(self.process.stdout.fileno(), 2048)
                if not chunk:
                    if self.process.poll() is not None:
                        break
                    continue

                buffer.extend(chunk)
                marker_index = buffer.find(PROMPT_MARKER)

                if marker_index != -1:
                    visible = self._clean(bytes(buffer[:marker_index]))
                    delta = visible[len(emitted):] if visible.startswith(emitted) else visible
                    if delta:
                        emitted = visible
                        yield delta

                    final_reply = emitted.strip()
                    self.turns += 1
                    self.total_messages += 1
                    self.last_reply_chars = len(final_reply)
                    self.total_reply_chars += len(final_reply)
                    self.last_latency_ms = round((time.time() - started) * 1000)
                    self.last_reply_at = time.time()
                    return

                visible = self._clean(bytes(buffer))
                delta = visible[len(emitted):] if visible.startswith(emitted) else visible
                if delta:
                    emitted = visible
                    yield delta

            raise TimeoutError("timed out waiting for the local chat response")

    def ask(self, message: str, locale_hint: str | None = None) -> tuple[str, int]:
        reply = "".join(self.stream(message, locale_hint=locale_hint)).strip()
        return reply, self.last_latency_ms or 0

    def reset(self) -> None:
        with self.lock:
            if self.process and self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
            self.process = None
            self.started_at = None
            self.turns = 0
            self.last_latency_ms = None
            self.last_reply_chars = 0

    def info(self) -> dict[str, Any]:
        return {
            "ready": bool(self.process and self.process.poll() is None),
            "warming": self.warming,
            "turns": self.turns,
            "started_at": self.started_at,
            "last_latency_ms": self.last_latency_ms,
            "last_reply_chars": self.last_reply_chars,
            "last_reply_at": self.last_reply_at,
            "total_messages": self.total_messages,
            "total_reply_chars": self.total_reply_chars,
        }


class Metrics:
    def __init__(self, model_name: str, model_path: str, export_dir: str, project_root: str, context: int, local_url: str) -> None:
        self.model_name = model_name
        self.model_path = model_path
        self.export_dir = export_dir
        self.project_root = project_root
        self.context = context
        self.local_url = local_url
        self.device_info = self._device()
        self._last_cpu_total: int | None = None
        self._last_cpu_idle: int | None = None

    def _device(self) -> dict[str, Any]:
        manufacturer = shell_text(["getprop", "ro.product.manufacturer"]) or "Android"
        model = shell_text(["getprop", "ro.product.model"]) or "Local Device"
        android = shell_text(["getprop", "ro.build.version.release"]) or "?"
        chip = shell_text(["getprop", "ro.soc.model"]) or shell_text(["getprop", "ro.board.platform"])
        return {
            "manufacturer": manufacturer,
            "model": model,
            "android": android,
            "chip": chip,
        }

    def _uptime_seconds(self) -> int | None:
        try:
            with open("/proc/uptime", "r", encoding="utf-8") as handle:
                return int(float(handle.read().split()[0]))
        except (OSError, ValueError, IndexError):
            return None

    def _memory(self) -> dict[str, Any]:
        total_kb = available_kb = None
        try:
            with open("/proc/meminfo", "r", encoding="utf-8") as handle:
                for line in handle:
                    if line.startswith("MemTotal:"):
                        total_kb = int(line.split()[1])
                    elif line.startswith("MemAvailable:"):
                        available_kb = int(line.split()[1])
        except OSError:
            return {"available": False}

        if not total_kb or not available_kb:
            return {"available": False}

        used_kb = total_kb - available_kb
        return {
            "available": True,
            "used_gb": round(used_kb / 1024 / 1024, 2),
            "total_gb": round(total_kb / 1024 / 1024, 2),
            "used_percent": round((used_kb / total_kb) * 100, 1),
        }

    def _battery(self) -> dict[str, Any]:
        if shutil.which("termux-battery-status"):
            info = shell_json(["termux-battery-status"])
            if info:
                return {
                    "available": True,
                    "level": info.get("percentage"),
                    "status": info.get("status"),
                    "temp_c": info.get("temperature"),
                    "health": info.get("health"),
                    "source": "termux-api",
                }

        base = Path("/sys/class/power_supply")
        candidates = [base / "battery", base / "Battery", base / "BAT0"]
        for candidate in candidates:
            if candidate.exists():
                return {
                    "available": True,
                    "level": read_text(candidate / "capacity"),
                    "status": read_text(candidate / "status"),
                    "temp_c": parse_temp(read_text(candidate / "temp")),
                    "health": read_text(candidate / "health"),
                    "source": "sysfs",
                }
        return {"available": False}

    def _cpu_temp(self) -> float | None:
        temps: list[float] = []
        thermal = Path("/sys/class/thermal")
        if not thermal.exists():
            return None
        for zone in thermal.glob("thermal_zone*/temp"):
            value = parse_temp(read_text(zone))
            if value is not None:
                temps.append(value)
        return max(temps) if temps else None

    def _gpu(self) -> dict[str, Any]:
        base = Path("/sys/class/kgsl/kgsl-3d0")
        if not base.exists():
            return {
                "available": False,
                "limited": True,
                "label": "GPU counters not exposed",
            }

        busy = read_text(base / "gpubusy")
        busy_percent = None
        if busy and " " in busy:
            try:
                active, total = [int(part) for part in busy.split()[:2]]
                if total > 0:
                    busy_percent = round((active / total) * 100, 1)
            except ValueError:
                busy_percent = None

        freq = read_text(base / "devfreq" / "cur_freq") or read_text(base / "gpuclk")
        max_freq = read_text(base / "devfreq" / "max_freq") or read_text(base / "max_gpuclk")
        label = read_text(base / "gpu_model") or read_text(base / "model") or "Adreno / KGSL"

        def fmt_freq(raw: str | None) -> str | None:
            if not raw:
                return None
            try:
                value = int(raw)
            except ValueError:
                return None
            if value >= 1_000_000:
                return f"{value / 1_000_000:.0f} MHz"
            if value >= 1_000:
                return f"{value / 1_000:.0f} kHz"
            return f"{value} Hz"

        freq_fmt = fmt_freq(freq)
        max_freq_fmt = fmt_freq(max_freq)
        has_counters = busy_percent is not None or freq_fmt is not None or max_freq_fmt is not None

        return {
            "available": has_counters,
            "limited": not has_counters,
            "label": label,
            "busy_percent": busy_percent,
            "freq": freq_fmt,
            "max_freq": max_freq_fmt,
            "status": "live" if has_counters else "kernel hidden",
        }

    def _cpu_usage(self) -> float | None:
        try:
            with open("/proc/stat", "r", encoding="utf-8") as handle:
                line = handle.readline()
        except OSError:
            return None

        parts = line.split()
        if not parts or parts[0] != "cpu":
            return None

        values = [int(part) for part in parts[1:8]]
        idle = values[3] + values[4]
        total = sum(values)

        if self._last_cpu_total is None or self._last_cpu_idle is None:
            self._last_cpu_total = total
            self._last_cpu_idle = idle
            return None

        total_delta = total - self._last_cpu_total
        idle_delta = idle - self._last_cpu_idle
        self._last_cpu_total = total
        self._last_cpu_idle = idle

        if total_delta <= 0:
            return None
        return round((1.0 - (idle_delta / total_delta)) * 100.0, 1)

    def _cpu(self) -> dict[str, Any]:
        try:
            load = os.getloadavg() if hasattr(os, "getloadavg") else (0.0, 0.0, 0.0)
        except OSError:
            load = (0.0, 0.0, 0.0)
        cores = os.cpu_count() or 0
        usage = self._cpu_usage()
        return {
            "cores": cores,
            "usage_percent": usage,
            "load_1": round(load[0], 2),
            "load_5": round(load[1], 2),
            "temp_c": self._cpu_temp(),
        }

    def _storage(self) -> dict[str, Any]:
        try:
            export_usage = shutil.disk_usage(self.export_dir)
            project_usage = shutil.disk_usage(self.project_root)
        except OSError:
            return {"available": False}

        return {
            "available": True,
            "export_free_gb": round(export_usage.free / 1024 / 1024 / 1024, 2),
            "project_free_gb": round(project_usage.free / 1024 / 1024 / 1024, 2),
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "device": self.device_info,
            "model": {
                "name": self.model_name,
                "path": self.model_path,
                "path_short": compact_path(self.model_path),
                "context": self.context,
            },
            "cpu": self._cpu(),
            "gpu": self._gpu(),
            "memory": self._memory(),
            "battery": self._battery(),
            "storage": self._storage(),
            "exports": {
                "dir": self.export_dir,
                "dir_short": compact_path(self.export_dir),
            },
            "local_url": self.local_url,
            "uptime_s": self._uptime_seconds(),
            "updated_at": time.time(),
        }


class DreamMobileHandler(SimpleHTTPRequestHandler):
    assets_dir = Path(__file__).with_name("android-local-ui")
    chat_session: ChatSession
    metrics: Metrics

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(self.assets_dir), **kwargs)

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stdout.write("[dream-mobile-local] " + fmt % args + "\n")

    def do_GET(self) -> None:
        if self.path == "/api/health":
            json_response(self, {"ok": True})
            return

        if self.path == "/api/status":
            payload = self.metrics.snapshot()
            payload["session"] = self.chat_session.info()
            json_response(self, {"ok": True, "status": payload})
            return

        super().do_GET()

    def do_POST(self) -> None:
        if self.path == "/api/chat":
            self.handle_chat()
            return

        if self.path == "/api/chat-stream":
            self.handle_chat_stream()
            return

        if self.path == "/api/reset":
            self.chat_session.reset()
            threading.Thread(target=self.chat_session.prewarm, daemon=True).start()
            json_response(self, {"ok": True})
            return

        json_response(self, {"ok": False, "error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def _read_json_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            return None

    def handle_chat(self) -> None:
        payload = self._read_json_body()
        if payload is None:
            json_response(self, {"ok": False, "error": "invalid JSON"}, status=HTTPStatus.BAD_REQUEST)
            return

        message = str(payload.get("message", "")).strip()
        locale_hint = str(payload.get("locale", "")).strip()
        if not message:
            json_response(self, {"ok": False, "error": "message is required"}, status=HTTPStatus.BAD_REQUEST)
            return

        try:
            reply, latency_ms = self.chat_session.ask(message, locale_hint=locale_hint)
        except Exception as exc:  # pragma: no cover - best effort mobile runtime
            json_response(
                self,
                {"ok": False, "error": f"local chat failed: {exc}"},
                status=HTTPStatus.INTERNAL_SERVER_ERROR,
            )
            return

        json_response(
            self,
            {
                "ok": True,
                "reply": reply,
                "latency_ms": latency_ms,
                "session": self.chat_session.info(),
            },
        )

    def handle_chat_stream(self) -> None:
        payload = self._read_json_body()
        if payload is None:
            json_response(self, {"ok": False, "error": "invalid JSON"}, status=HTTPStatus.BAD_REQUEST)
            return

        message = str(payload.get("message", "")).strip()
        locale_hint = str(payload.get("locale", "")).strip()
        if not message:
            json_response(self, {"ok": False, "error": "message is required"}, status=HTTPStatus.BAD_REQUEST)
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        try:
            write_ndjson_event(self, {"type": "start", "session": self.chat_session.info()})
            for chunk in self.chat_session.stream(message, locale_hint=locale_hint):
                if chunk:
                    write_ndjson_event(self, {"type": "chunk", "text": chunk})

            write_ndjson_event(
                self,
                {
                    "type": "done",
                    "latency_ms": self.chat_session.info().get("last_latency_ms"),
                    "session": self.chat_session.info(),
                },
            )
        except BrokenPipeError:
            return
        except Exception as exc:  # pragma: no cover - best effort mobile runtime
            try:
                write_ndjson_event(self, {"type": "error", "error": f"local chat failed: {exc}"})
            except BrokenPipeError:
                return


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Dream Server Mobile Android local UI")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model", required=True)
    parser.add_argument("--chat-bin", required=True)
    parser.add_argument("--context", type=int, default=1024)
    parser.add_argument("--export-dir", required=True)
    parser.add_argument("--project-root", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    DreamMobileHandler.chat_session = ChatSession(
        chat_bin=args.chat_bin,
        model_path=args.model,
        context=args.context,
    )
    DreamMobileHandler.metrics = Metrics(
        model_name=Path(args.model).name,
        model_path=args.model,
        export_dir=args.export_dir,
        project_root=args.project_root,
        context=args.context,
        local_url=f"http://{args.host}:{args.port}",
    )

    threading.Thread(target=DreamMobileHandler.chat_session.prewarm, daemon=True).start()

    server = ThreadingHTTPServer((args.host, args.port), DreamMobileHandler)
    print(f"Dream Server Mobile local UI listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        DreamMobileHandler.chat_session.reset()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
