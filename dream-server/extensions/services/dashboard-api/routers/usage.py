"""Usage and cost reporting backed by Token Spy telemetry."""

from __future__ import annotations

import asyncio
import copy
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, Query

from security import verify_api_key

router = APIRouter(prefix="/api/usage", tags=["usage"])

TOKEN_SPY_URL = os.environ.get("TOKEN_SPY_URL", "http://token-spy:8080")
TOKEN_SPY_API_KEY = os.environ.get("TOKEN_SPY_API_KEY", "")
TOKEN_SPY_KEY_FILE = Path(os.environ.get("TOKEN_SPY_KEY_FILE", "/data/token-spy/token-spy-api-key.txt"))
LLAMA_CPP_PROMETHEUS_METRICS = {
    "input_tokens": "llamacpp:prompt_tokens_total",
    "output_tokens": "llamacpp:tokens_predicted_total",
    "requests": "llamacpp:requests_total",
}
_LOCAL_RUNTIME_REQUEST_STATE: dict[str, dict[str, Any]] = {}
LOCAL_EQUIVALENT_PRICE_CATALOG = [
    {
        "id": "qwen3.5-2b",
        "aliases": [
            "qwen3.5-2b",
            "qwen 3.5 2b",
            "qwen3.5-2b-q4",
            "qwen3.5-2b-q4_k_m.gguf",
        ],
        "provider": "Artificial Analysis",
        "model": "Qwen3.5 2B",
        "input_usd_per_1m": 0.02,
        "output_usd_per_1m": 0.10,
        "source_url": "https://artificialanalysis.ai/models/qwen3-5-2b",
    },
    {
        "id": "qwen3.5-4b",
        "aliases": [
            "qwen3.5-4b",
            "qwen 3.5 4b",
            "qwen3.5-4b-q4",
            "qwen3.5-4b-q4_k_m.gguf",
        ],
        "provider": "Artificial Analysis",
        "model": "Qwen3.5 4B",
        "input_usd_per_1m": 0.03,
        "output_usd_per_1m": 0.15,
        "source_url": "https://artificialanalysis.ai/models/qwen3-5-4b",
    },
    {
        "id": "qwen3.5-9b",
        "aliases": [
            "qwen3.5-9b",
            "qwen 3.5 9b",
            "qwen3.5-9b-q4",
            "qwen3.5-9b-q4_k_m.gguf",
        ],
        "provider": "Together AI",
        "model": "Qwen3.5 9B",
        "input_usd_per_1m": 0.10,
        "output_usd_per_1m": 0.15,
        "source_url": "https://www.together.ai/pricing",
    },
    {
        "id": "qwen3.5-27b",
        "aliases": [
            "qwen3.5-27b",
            "qwen 3.5 27b",
            "qwen3.5-27b-q4",
            "qwen3.5-27b-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3.5-27b",
        "input_usd_per_1m": 0.30,
        "output_usd_per_1m": 2.40,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "qwen3.5-35b-a3b",
        "aliases": [
            "qwen3.5-35b-a3b",
            "qwen 3.5 35b-a3b",
            "qwen3.5-35b-a3b-q4",
            "qwen3.5-35b-a3b-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3.5-35b-a3b",
        "input_usd_per_1m": 0.25,
        "output_usd_per_1m": 2.00,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "qwen3.6-35b-a3b",
        "aliases": [
            "qwen3.6-35b-a3b",
            "qwen 3.6 35b-a3b",
            "qwen3.6-35b-a3b-ud-q4",
            "qwen3.6-35b-a3b-ud-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3.6-35b-a3b",
        "input_usd_per_1m": 0.248,
        "output_usd_per_1m": 1.485,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "qwen3-30b-a3b",
        "aliases": [
            "qwen3-30b-a3b",
            "qwen 3 30b-a3b",
            "qwen3-30b-a3b-q4",
            "qwen3-30b-a3b-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3-30b-a3b-fp8",
        "input_usd_per_1m": 0.09,
        "output_usd_per_1m": 0.45,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "qwen3-coder-next",
        "aliases": [
            "qwen3-coder-next",
            "qwen 3 coder next",
            "qwen3-coder-next-q4",
            "qwen3-coder-next-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3-coder-next",
        "input_usd_per_1m": 0.20,
        "output_usd_per_1m": 1.50,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "qwen3.5-122b-a10b",
        "aliases": [
            "qwen3.5-122b-a10b",
            "qwen 3.5 122b-a10b",
            "qwen3.5-122b-a10b-q4",
            "qwen3.5-122b-a10b-q4_k_m-00001-of-00003.gguf",
        ],
        "provider": "Novita AI",
        "model": "qwen/qwen3.5-122b-a10b",
        "input_usd_per_1m": 0.40,
        "output_usd_per_1m": 3.20,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "gemma4-26b-a4b",
        "aliases": [
            "gemma-4-26b-a4b-it",
            "gemma4-26b-a4b",
            "gemma 4 26b-a4b",
            "gemma-4-26b-a4b-it-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "google/gemma-4-26b-a4b-it",
        "input_usd_per_1m": 0.13,
        "output_usd_per_1m": 0.40,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "gemma4-e2b",
        "aliases": [
            "gemma-4-e2b-it",
            "gemma4-e2b",
            "gemma 4 e2b",
            "gemma-4-e2b-it-q4_k_m.gguf",
        ],
        "provider": "Pricepertoken",
        "model": "google/gemma-4-e2b-it",
        "input_usd_per_1m": 0.00,
        "output_usd_per_1m": 0.00,
        "source_url": "https://pricepertoken.com/pricing-page/model/google-gemma-4-e2b-it",
    },
    {
        "id": "gemma4-e4b",
        "aliases": [
            "gemma-4-e4b-it",
            "gemma4-e4b",
            "gemma 4 e4b",
            "gemma-4-e4b-it-q4_k_m.gguf",
        ],
        "provider": "Artificial Analysis",
        "model": "Gemma 4 E4B",
        "input_usd_per_1m": 0.30,
        "output_usd_per_1m": 1.25,
        "source_url": "https://artificialanalysis.ai/models/gemma-4-e4b",
    },
    {
        "id": "gemma4-31b",
        "aliases": [
            "gemma-4-31b-it",
            "gemma4-31b",
            "gemma 4 31b",
            "gemma-4-31b-it-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "google/gemma-4-31b-it",
        "input_usd_per_1m": 0.14,
        "output_usd_per_1m": 0.40,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "deepseek-r1-distill-qwen-7b",
        "aliases": [
            "deepseek-r1-distill-qwen-7b",
            "deepseek r1 7b",
            "deepseek-r1-7b-q4",
            "deepseek-r1-distill-qwen-7b-q4_k_m.gguf",
        ],
        "provider": "Pricepertoken",
        "model": "DeepSeek R1 Distill Qwen 7B",
        "input_usd_per_1m": 0.20,
        "output_usd_per_1m": 0.20,
        "source_url": "https://pricepertoken.com/pricing-page/model/deepseek-deepseek-r1-distill-qwen-7b",
    },
    {
        "id": "deepseek-r1-distill-qwen-14b",
        "aliases": [
            "deepseek-r1-distill-qwen-14b",
            "deepseek r1 14b",
            "deepseek-r1-14b-q4",
            "deepseek-r1-distill-qwen-14b-q4_k_m.gguf",
        ],
        "provider": "OpenRouter",
        "model": "deepseek/deepseek-r1-distill-qwen-14b",
        "input_usd_per_1m": 0.12,
        "output_usd_per_1m": 0.12,
        "source_url": "https://portkey.ai/models/openrouter/deepseek%2Fdeepseek-r1-distill-qwen-14b",
    },
    {
        "id": "deepseek-r1-distill-qwen-32b",
        "aliases": [
            "deepseek-r1-distill-qwen-32b",
            "deepseek r1 32b",
            "deepseek-r1-32b-q4",
            "deepseek-r1-distill-qwen-32b-q4_k_m.gguf",
        ],
        "provider": "OpenRouter",
        "model": "deepseek/deepseek-r1-distill-qwen-32b",
        "input_usd_per_1m": 0.29,
        "output_usd_per_1m": 0.29,
        "source_url": "https://openrouter.ai/deepseek/deepseek-r1-distill-qwen-32b/providers",
    },
    {
        "id": "deepseek-r1-distill-llama-70b",
        "aliases": [
            "deepseek-r1-distill-llama-70b",
            "deepseek r1 70b",
            "deepseek-r1-70b-q4",
            "deepseek-r1-distill-llama-70b-q4_k_m.gguf",
        ],
        "provider": "Novita AI",
        "model": "deepseek/deepseek-r1-distill-llama-70b",
        "input_usd_per_1m": 0.80,
        "output_usd_per_1m": 0.80,
        "source_url": "https://novita.ai/pricing",
    },
    {
        "id": "phi-4-mini",
        "aliases": [
            "phi-4-mini",
            "phi-4 mini",
            "phi4-mini-q4",
            "phi-4-mini-instruct-q4_k_m.gguf",
        ],
        "provider": "OpenRouter",
        "model": "microsoft/phi-4-mini-instruct",
        "input_usd_per_1m": 0.08,
        "output_usd_per_1m": 0.35,
        "source_url": "https://openrouter.ai/microsoft/",
    },
    {
        "id": "phi-4",
        "aliases": [
            "phi-4",
            "phi 4",
            "phi4-q4",
            "phi-4-q4_k_m.gguf",
        ],
        "provider": "OpenRouter",
        "model": "microsoft/phi-4",
        "input_usd_per_1m": 0.065,
        "output_usd_per_1m": 0.14,
        "source_url": "https://openrouter.ai/microsoft/phi-4",
    },
    {
        "id": "llama-4-scout",
        "aliases": [
            "llama-4-scout",
            "llama 4 scout",
            "llama4-scout-q4",
            "llama-4-scout-17b-16e-instruct-q4_k_m-00001-of-00002.gguf",
        ],
        "provider": "Novita AI",
        "model": "meta-llama/llama-4-scout-17b-16e-instruct",
        "input_usd_per_1m": 0.18,
        "output_usd_per_1m": 0.59,
        "source_url": "https://novita.ai/pricing",
    },
]


def _normalize_model_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def _parse_date(value: str) -> date:
    return date.fromisoformat(value)


def _date_range(start_day: date, end_day: date) -> list[str]:
    days = []
    current = start_day
    while current <= end_day:
        days.append(current.isoformat())
        current += timedelta(days=1)
    return days


def _empty_report(start: str, end: str, status: str = "unavailable", detail: str | None = None) -> dict[str, Any]:
    start_day = _parse_date(start)
    end_day = _parse_date(end)
    return {
        "period": {"start": start, "end": end},
        "source": {
            "name": "token-spy",
            "status": status,
            "detail": detail,
        },
        "summary": {
            "spend_usd": 0,
            "requests": 0,
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
            "total_tokens": 0,
            "tracked_providers": 0,
            "billing_providers": 0,
            "local_providers": 0,
            "untracked_providers": 0,
            "paid_cost_usd": 0,
            "local_cost_usd": 0,
        },
        "daily": [
            {
                "date": day,
                "spend_usd": 0,
                "requests": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cache_read_tokens": 0,
                "cache_write_tokens": 0,
            }
            for day in _date_range(start_day, end_day)
        ],
        "models": [],
        "services": [],
        "sources": [],
    }


def _token_spy_api_key() -> str:
    if TOKEN_SPY_API_KEY:
        return TOKEN_SPY_API_KEY
    try:
        return TOKEN_SPY_KEY_FILE.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _today() -> date:
    return date.today()


def _configured_local_runtime_metrics_urls() -> list[str]:
    explicit = os.environ.get("LOCAL_USAGE_METRICS_URLS") or os.environ.get("LLAMA_METRICS_URL")
    if explicit:
        return [item.strip() for item in explicit.split(",") if item.strip()]

    base = os.environ.get("LLM_API_URL") or os.environ.get("OLLAMA_URL") or "http://llama-server:8080"
    parsed = urllib.parse.urlparse(base.rstrip("/"))
    path = parsed.path.rstrip("/")
    if path in {"/v1", "/api/v1"}:
        path = ""
    target = parsed._replace(path=f"{path}/metrics", params="", query="", fragment="")
    return [urllib.parse.urlunparse(target)]


def _runtime_model_name() -> str:
    return os.environ.get("GGUF_FILE") or os.environ.get("LLM_MODEL") or "llama-server"


def _local_equivalent_price(model_name: str, input_tokens: int, output_tokens: int) -> dict[str, Any] | None:
    normalized_model = _normalize_model_key(model_name)
    for entry in LOCAL_EQUIVALENT_PRICE_CATALOG:
        aliases = {_normalize_model_key(alias) for alias in entry["aliases"]}
        if normalized_model not in aliases:
            continue
        cost = (
            (input_tokens / 1_000_000) * entry["input_usd_per_1m"]
            + (output_tokens / 1_000_000) * entry["output_usd_per_1m"]
        )
        return {
            "cost_usd": cost,
            "cost_source": "local_estimated_from_tokens",
            "pricing_provider": entry["provider"],
            "pricing_model": entry["model"],
            "pricing_input_usd_per_1m": entry["input_usd_per_1m"],
            "pricing_output_usd_per_1m": entry["output_usd_per_1m"],
            "pricing_source_url": entry["source_url"],
        }
    return None


async def _fetch_token_spy_report(start: str, end: str) -> dict[str, Any]:
    if not TOKEN_SPY_URL:
        return _empty_report(start, end, detail="TOKEN_SPY_URL is not configured")

    headers = {}
    api_key = _token_spy_api_key()
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    try:
        return await asyncio.to_thread(
            _request_token_spy_report,
            start,
            end,
            headers,
        )
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        return _empty_report(
            start,
            end,
            detail=f"Token Spy returned HTTP {exc.code}: {detail[:160]}",
        )
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return _empty_report(start, end, detail=f"Token Spy unavailable: {exc}")


def _request_token_spy_report(start: str, end: str, headers: dict[str, str]) -> dict[str, Any]:
    query = urllib.parse.urlencode({"start": start, "end": end})
    url = f"{TOKEN_SPY_URL.rstrip('/')}/api/report?{query}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.loads(response.read().decode("utf-8"))
    payload["source"] = {
        "name": "token-spy",
        "status": "ok",
        "detail": None,
    }
    return payload


async def _fetch_local_runtime_counters() -> list[dict[str, Any]]:
    counters = []
    for url in _configured_local_runtime_metrics_urls():
        try:
            metrics_text = await asyncio.to_thread(_request_text, url)
        except (urllib.error.URLError, TimeoutError, OSError):
            continue
        parsed = _extract_llama_cpp_prometheus_counters(metrics_text, url)
        if parsed:
            counters.append(parsed)
    return counters


def _request_text(url: str) -> str:
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.read().decode("utf-8", errors="replace")


def _metric_value(metrics_text: str, metric_name: str) -> float:
    match = re.search(rf"^{re.escape(metric_name)}\s+([0-9.eE+-]+)\s*$", metrics_text, flags=re.MULTILINE)
    if not match:
        return 0
    try:
        return float(match.group(1))
    except ValueError:
        return 0


def _has_metric(metrics_text: str, metric_name: str) -> bool:
    return re.search(rf"^{re.escape(metric_name)}\s+", metrics_text, flags=re.MULTILINE) is not None


def _extract_llama_cpp_prometheus_counters(metrics_text: str, url: str) -> dict[str, Any] | None:
    input_tokens = int(_metric_value(metrics_text, LLAMA_CPP_PROMETHEUS_METRICS["input_tokens"]))
    output_tokens = int(_metric_value(metrics_text, LLAMA_CPP_PROMETHEUS_METRICS["output_tokens"]))
    if input_tokens <= 0 and output_tokens <= 0:
        return None

    parsed = urllib.parse.urlparse(url)
    service = parsed.hostname or "local-runtime"
    if service in {"127.0.0.1", "localhost", "host.docker.internal"}:
        service = "local-runtime"
    request_metric_available = _has_metric(metrics_text, LLAMA_CPP_PROMETHEUS_METRICS["requests"])
    request_count = int(_metric_value(metrics_text, LLAMA_CPP_PROMETHEUS_METRICS["requests"])) if request_metric_available else 0
    request_count_source = "prometheus_counter" if request_metric_available else "unavailable"
    request_count_note = None
    if not request_metric_available:
        observed = _observe_runtime_request_delta(
            key=f"llama.cpp:{service}:{_runtime_model_name()}",
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )
        request_count = observed["requests"]
        request_count_source = observed["source"]
        request_count_note = observed["note"]

    return {
        "runtime": "llama.cpp",
        "adapter": "prometheus",
        "service": service,
        "model": _runtime_model_name(),
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "requests": request_count,
        "request_count_available": request_metric_available or request_count > 0,
        "request_count_source": request_count_source,
        "request_count_note": request_count_note,
    }


def _observe_runtime_request_delta(key: str, input_tokens: int, output_tokens: int) -> dict[str, Any]:
    total_tokens = input_tokens + output_tokens
    state = _LOCAL_RUNTIME_REQUEST_STATE.get(key)
    if state is None:
        _LOCAL_RUNTIME_REQUEST_STATE[key] = {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "total_tokens": total_tokens,
            "requests": 0,
        }
        return {
            "requests": 0,
            "source": "unavailable",
            "note": "llama.cpp did not expose a request counter; baseline initialized from current token counters",
        }

    previous_total = int(state.get("total_tokens") or 0)
    previous_input = int(state.get("input_tokens") or 0)
    previous_output = int(state.get("output_tokens") or 0)
    observed_requests = int(state.get("requests") or 0)
    if total_tokens < previous_total or input_tokens < previous_input or output_tokens < previous_output:
        observed_requests = 0
    elif total_tokens > previous_total:
        observed_requests += 1

    _LOCAL_RUNTIME_REQUEST_STATE[key] = {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": total_tokens,
        "requests": observed_requests,
    }
    if observed_requests <= 0:
        return {
            "requests": 0,
            "source": "unavailable",
            "note": "llama.cpp did not expose a request counter; no completed request delta observed yet",
        }
    return {
        "requests": observed_requests,
        "source": "observed_counter_delta",
        "note": "llama.cpp did not expose requests_total; count reflects observed token-counter increases while Dashboard API was running",
    }


def _tracked_local_model_tokens(report: dict[str, Any]) -> dict[str, int]:
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "requests": 0,
    }
    for row in report.get("models") or []:
        source = row.get("cost_source")
        if source == "local_zero_cost":
            totals["input_tokens"] += int(row.get("input_tokens") or 0)
            totals["output_tokens"] += int(row.get("output_tokens") or 0)
            totals["requests"] += int(row.get("requests") or 0)
    return totals


def _add_numbers(target: dict[str, Any], source: dict[str, Any], keys: list[str]) -> None:
    for key in keys:
        target[key] = (target.get(key) or 0) + (source.get(key) or 0)


def _merge_local_runtime_counters(
    report: dict[str, Any],
    start_day: date,
    end_day: date,
    runtime_counters: list[dict[str, Any]],
) -> dict[str, Any]:
    if not runtime_counters:
        return report

    today = _today()
    if not start_day <= today <= end_day:
        return report

    tracked = _tracked_local_model_tokens(report)
    merged = copy.deepcopy(report)
    added_rows = []
    remaining_tracked = tracked.copy()
    for counter in runtime_counters:
        input_tokens = max(int(counter.get("input_tokens") or 0) - remaining_tracked["input_tokens"], 0)
        output_tokens = max(int(counter.get("output_tokens") or 0) - remaining_tracked["output_tokens"], 0)
        requests = max(int(counter.get("requests") or 0) - remaining_tracked["requests"], 0)
        remaining_tracked["input_tokens"] = max(remaining_tracked["input_tokens"] - int(counter.get("input_tokens") or 0), 0)
        remaining_tracked["output_tokens"] = max(remaining_tracked["output_tokens"] - int(counter.get("output_tokens") or 0), 0)
        remaining_tracked["requests"] = max(remaining_tracked["requests"] - int(counter.get("requests") or 0), 0)
        if input_tokens <= 0 and output_tokens <= 0:
            continue
        model = counter.get("model") or _runtime_model_name()
        price = _local_equivalent_price(model, input_tokens, output_tokens) or {
            "cost_usd": 0,
            "cost_source": "local_zero_cost",
        }
        row = {
            "model": model,
            "provider": "local",
            "service": counter.get("service") or counter.get("runtime") or "local-runtime",
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
            "requests": requests,
            **price,
        }
        merged.setdefault("models", []).append(row)
        added_rows.append(row)

    if not added_rows:
        return report

    today_key = today.isoformat()
    for day in merged.setdefault("daily", []):
        if day.get("date") == today_key:
            for row in added_rows:
                _add_numbers(
                    day,
                    row,
                    [
                        "input_tokens",
                        "output_tokens",
                        "cache_read_tokens",
                        "cache_write_tokens",
                        "requests",
                        "cost_usd",
                    ],
                )
                day["spend_usd"] = (day.get("spend_usd") or 0) + (row.get("cost_usd") or 0)
            break
    else:
        day_row = {
            "date": today_key,
            "spend_usd": 0,
            "requests": 0,
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
        }
        for row in added_rows:
            _add_numbers(
                day_row,
                row,
                [
                    "input_tokens",
                    "output_tokens",
                    "cache_read_tokens",
                    "cache_write_tokens",
                    "requests",
                    "cost_usd",
                ],
            )
            day_row["spend_usd"] = (day_row.get("spend_usd") or 0) + (row.get("cost_usd") or 0)
        merged.setdefault("daily", []).append(
            day_row
        )

    _recompute_rollups(merged)
    source = merged.setdefault("source", {"name": "token-spy", "status": "unknown", "detail": None})
    source["local_runtime"] = {
        "status": "ok",
        "detail": "Local runtime counters included for model usage that bypassed Token Spy",
        "adapters": sorted({str(counter.get("runtime") or "unknown") for counter in runtime_counters}),
        "request_count_available": any(counter.get("request_count_available") for counter in runtime_counters),
        "request_count_sources": sorted(
            {
                str(counter.get("request_count_source") or "unavailable")
                for counter in runtime_counters
            }
        ),
        "request_count_note": next(
            (
                str(counter.get("request_count_note"))
                for counter in runtime_counters
                if counter.get("request_count_note")
            ),
            None,
        ),
    }
    if source.get("status") != "ok":
        source["status"] = "partial"
        source["detail"] = "Token Spy unavailable; local runtime counters included"
    return merged


def _recompute_rollups(report: dict[str, Any]) -> None:
    models = report.get("models") or []
    services: dict[str, dict[str, Any]] = {}
    sources: dict[str, dict[str, Any]] = {}
    providers = set()
    billing_providers = set()
    local_providers = set()
    untracked_providers = set()
    summary = {
        "spend_usd": 0,
        "requests": 0,
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_read_tokens": 0,
        "cache_write_tokens": 0,
        "total_tokens": 0,
        "tracked_providers": 0,
        "billing_providers": 0,
        "local_providers": 0,
        "untracked_providers": 0,
        "paid_cost_usd": 0,
        "local_cost_usd": 0,
    }
    numeric_keys = [
        "requests",
        "input_tokens",
        "output_tokens",
        "cache_read_tokens",
        "cache_write_tokens",
        "cost_usd",
    ]
    for row in models:
        provider = row.get("provider") or "unknown"
        service = row.get("service") or "unknown"
        source = row.get("cost_source") or "untracked"
        providers.add(provider)
        if source in {"actual_billed", "priced_from_tokens"}:
            billing_providers.add(provider)
        elif source in {"local_zero_cost", "local_estimated_from_tokens"}:
            local_providers.add(provider)
        else:
            untracked_providers.add(provider)

        service_row = services.setdefault(
            service,
            {
                "service": service,
                "requests": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cache_read_tokens": 0,
                "cache_write_tokens": 0,
                "cost_usd": 0,
            },
        )
        source_row = sources.setdefault(
            source,
            {
                "cost_source": source,
                "providers": 0,
                "requests": 0,
                "input_tokens": 0,
                "output_tokens": 0,
                "cache_read_tokens": 0,
                "cache_write_tokens": 0,
                "cost_usd": 0,
            },
        )
        _add_numbers(service_row, row, numeric_keys)
        _add_numbers(source_row, row, numeric_keys)
        _add_numbers(summary, row, numeric_keys)

    for source, source_row in sources.items():
        source_row["providers"] = len({row.get("provider") or "unknown" for row in models if (row.get("cost_source") or "untracked") == source})

    summary["spend_usd"] = summary.pop("cost_usd", 0)
    summary["total_tokens"] = (
        summary["input_tokens"]
        + summary["output_tokens"]
        + summary["cache_read_tokens"]
        + summary["cache_write_tokens"]
    )
    summary["tracked_providers"] = len(providers)
    summary["billing_providers"] = len(billing_providers)
    summary["local_providers"] = len(local_providers)
    summary["untracked_providers"] = len(untracked_providers)
    summary["paid_cost_usd"] = sum(row["cost_usd"] for row in sources.values() if row["cost_source"] in {"actual_billed", "priced_from_tokens"})
    summary["local_cost_usd"] = sum(row["cost_usd"] for row in sources.values() if row["cost_source"] in {"local_zero_cost", "local_estimated_from_tokens"})
    report["summary"] = summary
    report["services"] = sorted(services.values(), key=lambda row: row["cost_usd"], reverse=True)
    report["sources"] = sorted(sources.values(), key=lambda row: row["cost_source"])


@router.get("/report")
async def usage_report(
    start: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
    end: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
    api_key: str = Depends(verify_api_key),
):
    """Return real usage/cost metrics for the requested inclusive date range."""
    del api_key
    try:
        start_day = _parse_date(start)
        end_day = _parse_date(end)
    except ValueError:
        return _empty_report(start, end, status="invalid_range", detail="Dates must use YYYY-MM-DD")
    if end_day < start_day:
        return _empty_report(start, end, status="invalid_range", detail="end must be on or after start")

    report = await _fetch_token_spy_report(start, end)
    runtime_counters = await _fetch_local_runtime_counters()
    return _merge_local_runtime_counters(report, start_day, end_day, runtime_counters)
