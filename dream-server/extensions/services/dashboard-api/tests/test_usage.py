"""Usage/cost report proxy tests."""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from unittest.mock import AsyncMock


def _usage_payload():
    return {
        "period": {"start": "2026-05-01", "end": "2026-05-31"},
        "source": {"name": "token-spy", "status": "ok", "detail": None},
        "summary": {
            "spend_usd": 1.25,
            "requests": 2,
            "input_tokens": 100,
            "output_tokens": 50,
            "cache_read_tokens": 25,
            "cache_write_tokens": 0,
            "total_tokens": 175,
            "tracked_providers": 1,
            "billing_providers": 1,
            "local_providers": 0,
            "untracked_providers": 0,
            "paid_cost_usd": 1.25,
            "local_cost_usd": 0,
        },
        "daily": [],
        "models": [],
        "services": [],
        "sources": [],
    }


def test_usage_report_requires_auth(test_client):
    resp = test_client.get("/api/usage/report?start=2026-05-01&end=2026-05-31")
    assert resp.status_code == 401


def test_usage_report_returns_token_spy_payload(test_client, monkeypatch):
    import routers.usage as usage_router

    fetch = AsyncMock(return_value=_usage_payload())
    monkeypatch.setattr(usage_router, "_fetch_token_spy_report", fetch)
    monkeypatch.setattr(usage_router, "_fetch_local_runtime_counters", AsyncMock(return_value=[]))

    resp = test_client.get(
        "/api/usage/report?start=2026-05-01&end=2026-05-31",
        headers=test_client.auth_headers,
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["summary"]["spend_usd"] == 1.25
    assert data["source"]["status"] == "ok"
    fetch.assert_awaited_once_with("2026-05-01", "2026-05-31")


def test_usage_report_returns_honest_empty_payload_when_token_spy_disabled(
    test_client,
    monkeypatch,
):
    import routers.usage as usage_router

    monkeypatch.setattr(usage_router, "TOKEN_SPY_URL", "")
    monkeypatch.setattr(usage_router, "_fetch_local_runtime_counters", AsyncMock(return_value=[]))

    resp = test_client.get(
        "/api/usage/report?start=2026-05-01&end=2026-05-03",
        headers=test_client.auth_headers,
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["source"]["status"] == "unavailable"
    assert data["summary"]["spend_usd"] == 0
    assert data["summary"]["requests"] == 0
    assert [day["date"] for day in data["daily"]] == [
        "2026-05-01",
        "2026-05-02",
        "2026-05-03",
    ]


def test_usage_report_rejects_reversed_date_range(test_client):
    resp = test_client.get(
        "/api/usage/report?start=2026-05-31&end=2026-05-01",
        headers=test_client.auth_headers,
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["source"]["status"] == "invalid_range"
    assert data["source"]["detail"] == "end must be on or after start"


def test_usage_report_includes_direct_local_runtime_counters(test_client, monkeypatch):
    import routers.usage as usage_router

    fetch = AsyncMock(return_value=usage_router._empty_report("2026-05-01", "2026-05-31", status="ok"))
    counters = [
        {
            "runtime": "llama.cpp",
            "adapter": "prometheus",
            "service": "llama-server",
            "model": "Qwen3.5-9B-Q4_K_M.gguf",
            "input_tokens": 178,
            "output_tokens": 62,
            "requests": 0,
            "request_count_available": False,
            "request_count_source": "unavailable",
        }
    ]
    monkeypatch.setattr(usage_router, "_fetch_token_spy_report", fetch)
    monkeypatch.setattr(usage_router, "_fetch_local_runtime_counters", AsyncMock(return_value=counters))
    monkeypatch.setattr(usage_router, "_today", lambda: date(2026, 5, 16))

    resp = test_client.get(
        "/api/usage/report?start=2026-05-01&end=2026-05-31",
        headers=test_client.auth_headers,
    )

    assert resp.status_code == 200
    data = resp.json()
    assert data["summary"]["input_tokens"] == 178
    assert data["summary"]["output_tokens"] == 62
    assert data["summary"]["total_tokens"] == 240
    assert data["summary"]["local_providers"] == 1
    assert round(data["summary"]["spend_usd"], 7) == 0.0000271
    assert data["models"] == [
        {
            "model": "Qwen3.5-9B-Q4_K_M.gguf",
            "provider": "local",
            "service": "llama-server",
            "input_tokens": 178,
            "output_tokens": 62,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
            "requests": 0,
            "cost_usd": data["models"][0]["cost_usd"],
            "cost_source": "local_estimated_from_tokens",
            "pricing_provider": "Together AI",
            "pricing_model": "Qwen3.5 9B",
            "pricing_input_usd_per_1m": 0.1,
            "pricing_output_usd_per_1m": 0.15,
            "pricing_source_url": "https://www.together.ai/pricing",
        }
    ]
    assert round(data["models"][0]["cost_usd"], 7) == 0.0000271
    assert data["daily"][15]["input_tokens"] == 178
    assert data["source"]["local_runtime"]["status"] == "ok"
    assert data["source"]["local_runtime"]["adapters"] == ["llama.cpp"]
    assert data["source"]["local_runtime"]["request_count_available"] is False
    assert data["source"]["local_runtime"]["request_count_sources"] == ["unavailable"]


def test_llama_cpp_prometheus_metrics_are_detected_as_local_runtime(monkeypatch):
    import routers.usage as usage_router

    monkeypatch.setenv("GGUF_FILE", "Qwen3.5-9B-Q4_K_M.gguf")
    usage_router._LOCAL_RUNTIME_REQUEST_STATE.clear()
    metrics = "\n".join(
        [
            "llamacpp:prompt_tokens_total 178",
            "llamacpp:tokens_predicted_total 62",
        ]
    )

    counters = usage_router._extract_llama_cpp_prometheus_counters(
        metrics,
        "http://llama-server:8080/metrics",
    )

    assert counters == {
        "runtime": "llama.cpp",
        "adapter": "prometheus",
        "service": "llama-server",
        "model": "Qwen3.5-9B-Q4_K_M.gguf",
        "input_tokens": 178,
        "output_tokens": 62,
        "requests": 0,
        "request_count_available": False,
        "request_count_source": "unavailable",
        "request_count_note": "llama.cpp did not expose a request counter; baseline initialized from current token counters",
    }


def test_llama_cpp_prometheus_request_count_uses_observed_delta_when_counter_is_missing(monkeypatch):
    import routers.usage as usage_router

    monkeypatch.setenv("GGUF_FILE", "Qwen3.5-9B-Q4_K_M.gguf")
    usage_router._LOCAL_RUNTIME_REQUEST_STATE.clear()

    first = usage_router._extract_llama_cpp_prometheus_counters(
        "\n".join(
            [
                "llamacpp:prompt_tokens_total 100",
                "llamacpp:tokens_predicted_total 50",
            ]
        ),
        "http://llama-server:8080/metrics",
    )
    second = usage_router._extract_llama_cpp_prometheus_counters(
        "\n".join(
            [
                "llamacpp:prompt_tokens_total 125",
                "llamacpp:tokens_predicted_total 75",
            ]
        ),
        "http://llama-server:8080/metrics",
    )

    assert first["requests"] == 0
    assert first["request_count_available"] is False
    assert second["requests"] == 1
    assert second["request_count_available"] is True
    assert second["request_count_source"] == "observed_counter_delta"


def test_local_equivalent_pricing_covers_model_library_catalog():
    import routers.usage as usage_router

    repo_root = Path(__file__).resolve().parents[4]
    models = json.loads((repo_root / "config" / "model-library.json").read_text(encoding="utf-8"))["models"]
    missing = []
    for model in models:
        names = [
            model.get("gguf_file", ""),
            model.get("llm_model_name", ""),
            model.get("id", ""),
            model.get("name", ""),
        ]
        if not any(usage_router._local_equivalent_price(name, 1000, 1000) for name in names if name):
            missing.append(model["id"])

    assert missing == []


def test_usage_token_spy_key_falls_back_to_shared_data_file(tmp_path, monkeypatch):
    import routers.usage as usage_router

    key_file = tmp_path / "token-spy-api-key.txt"
    key_file.write_text("file-key", encoding="utf-8")
    monkeypatch.setattr(usage_router, "TOKEN_SPY_API_KEY", "")
    monkeypatch.setattr(usage_router, "TOKEN_SPY_KEY_FILE", key_file)

    assert usage_router._token_spy_api_key() == "file-key"
