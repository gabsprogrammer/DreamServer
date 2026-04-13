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


def json_response(handler: "DreamMobileHandler", payload: dict[str, Any], status: int = 200) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


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


class ChatSession:
    def __init__(self, chat_bin: str, model_path: str, context: int) -> None:
        self.chat_bin = chat_bin
        self.model_path = model_path
        self.context = context
        self.process: subprocess.Popen[bytes] | None = None
        self.lock = threading.Lock()
        self.started_at: float | None = None
        self.turns = 0

    def _clean(self, data: bytes) -> str:
        text = ANSI_RE.sub(b"", data).decode("utf-8", errors="ignore")
        return text.replace("\r", "").strip()

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

            chunk = os.read(self.process.stdout.fileno(), 1024)
            if not chunk:
                if self.process.poll() is not None:
                    break
                continue

            buffer.extend(chunk)
            marker_index = buffer.find(PROMPT_MARKER)
            if marker_index != -1:
                return self._clean(bytes(buffer[:marker_index]))

        raise TimeoutError("timed out waiting for the local chat response")

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

    def ask(self, message: str) -> tuple[str, float]:
        with self.lock:
            self.ensure_started()
            assert self.process is not None and self.process.stdin is not None

            started = time.time()
            self.process.stdin.write(message.encode("utf-8") + b"\n")
            self.process.stdin.flush()
            reply = self._read_until_prompt(timeout=300)
            self.turns += 1
            return reply, round((time.time() - started) * 1000)

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

    def info(self) -> dict[str, Any]:
        return {
            "ready": bool(self.process and self.process.poll() is None),
            "turns": self.turns,
            "started_at": self.started_at,
        }


class Metrics:
    def __init__(self, model_name: str, model_path: str, export_dir: str, project_root: str, context: int, local_url: str) -> None:
        self.model_name = model_name
        self.model_path = model_path
        self.export_dir = export_dir
        self.project_root = project_root
        self.context = context
        self.local_url = local_url

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
        base = Path("/sys/class/power_supply")
        candidates = [base / "battery", base / "Battery", base / "BAT0"]
        for candidate in candidates:
            if candidate.exists():
                return {
                    "available": True,
                    "level": read_text(candidate / "capacity"),
                    "status": read_text(candidate / "status"),
                    "temp_c": parse_temp(read_text(candidate / "temp")),
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
            return {"available": False, "label": "GPU status unavailable"}

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

        def fmt_freq(raw: str | None) -> str | None:
            if not raw:
                return None
            try:
                value = int(raw)
            except ValueError:
                return None
            if value > 1_000_000:
                return f"{value / 1_000_000:.0f} MHz"
            if value > 1_000:
                return f"{value / 1_000:.0f} MHz"
            return f"{value} Hz"

        return {
            "available": True,
            "label": "Adreno / KGSL",
            "busy_percent": busy_percent,
            "freq": fmt_freq(freq),
            "max_freq": fmt_freq(max_freq),
        }

    def _cpu(self) -> dict[str, Any]:
        load = os.getloadavg() if hasattr(os, "getloadavg") else (0.0, 0.0, 0.0)
        cores = os.cpu_count() or 0
        return {
            "cores": cores,
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
            "model": {
                "name": self.model_name,
                "path": self.model_path,
                "context": self.context,
            },
            "cpu": self._cpu(),
            "gpu": self._gpu(),
            "memory": self._memory(),
            "battery": self._battery(),
            "storage": self._storage(),
            "exports": {
                "dir": self.export_dir,
            },
            "local_url": self.local_url,
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

        if self.path == "/api/reset":
            self.chat_session.reset()
            json_response(self, {"ok": True})
            return

        json_response(self, {"ok": False, "error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def handle_chat(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            json_response(self, {"ok": False, "error": "invalid JSON"}, status=HTTPStatus.BAD_REQUEST)
            return

        message = str(payload.get("message", "")).strip()
        if not message:
            json_response(self, {"ok": False, "error": "message is required"}, status=HTTPStatus.BAD_REQUEST)
            return

        try:
            reply, latency_ms = self.chat_session.ask(message)
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
