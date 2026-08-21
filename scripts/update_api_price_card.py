#!/usr/bin/env python3
"""Build the versioned API-equivalent price manifest from authoritative snapshots."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import re
import sys
import urllib.request


MODELS_DEV_URL = "https://models.dev/api.json"
OPENAI_MODEL_URLS = {
    "gpt-5.5": "https://developers.openai.com/api/docs/models/gpt-5.5",
    "gpt-5.6-sol": "https://developers.openai.com/api/docs/models/gpt-5.6-sol",
    "gpt-5.6-terra": "https://developers.openai.com/api/docs/models/gpt-5.6-terra",
    "gpt-5.6-luna": "https://developers.openai.com/api/docs/models/gpt-5.6-luna",
}
MODELS_DEV_SELECTIONS = (
    ("xai", "grok-4.6", "xai", ("grok-4.6",)),
    ("moonshotai", "kimi-k3", "moonshot", ("k3", "kimi-k3")),
    (
        "deepseek",
        "deepseek-v4-flash",
        "deepseek",
        ("deepseek-v4-flash", "deepseek-v4-flash-preview"),
    ),
    (
        "deepseek",
        "deepseek-v4-pro",
        "deepseek",
        ("deepseek-v4-pro", "deepseek-v4-pro-preview"),
    ),
)
REQUIRED_OPENAI_MODELS = set(OPENAI_MODEL_URLS)
MAX_SOURCE_AGE_DAYS = 180


class APIPriceCardError(RuntimeError):
    pass


class TextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def fetch(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/html,application/json",
            "User-Agent": "Mozilla/5.0 CodexToolboxAPIPriceCard/1.3",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise APIPriceCardError(f"unexpected HTTP {response.status} for {url}")
            return response.read().decode("utf-8")
    except Exception as error:
        if isinstance(error, APIPriceCardError):
            raise
        raise APIPriceCardError(f"failed to fetch {url}: {error}") from error


def parse_datetime(value: str) -> dt.datetime:
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = dt.datetime.fromisoformat(normalized)
    except Exception as error:
        raise APIPriceCardError(f"invalid ISO-8601 date: {value!r}") from error
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def normalize_html(source: str) -> str:
    parser = TextParser()
    parser.feed(source)
    return " ".join(" ".join(parser.parts).split())


def parse_openai_model_page(model_id: str, source: str, updated_at: str) -> dict:
    text = normalize_html(source)
    marker = re.search(
        r"Text tokens\s+Per\s+1M tokens.*?Input\s+\$([0-9.]+)\s+"
        r"Cached input\s+\$([0-9.]+)\s+Output\s+\$([0-9.]+)",
        text,
        re.I,
    )
    if not marker:
        raise APIPriceCardError(f"official pricing structure changed for {model_id}")
    input_price, cached_price, output_price = map(float, marker.groups())
    standard = price(input_price, cached_price, output_price)
    long_standard = price(input_price * 2, cached_price * 2, output_price * 1.5)
    if model_id.startswith("gpt-5.6-"):
        standard["cache_write_usd_per_million"] = clean_number(input_price * 1.25)
        priority_factor = 2
        long_standard["cache_write_usd_per_million"] = clean_number(input_price * 2.5)
        long_priority = price(input_price * 4, cached_price * 4, output_price * 3)
        long_priority["cache_write_usd_per_million"] = clean_number(input_price * 5)
        priority_long = {"priority_price": long_priority}
    else:
        priority_factor = 2.5
        priority_long = {}
    context_tiers = [
        {
            "minimum_input_tokens": 272000,
            "price": long_standard,
            **priority_long,
        }
    ]
    priority = price(
        input_price * priority_factor,
        cached_price * priority_factor,
        output_price * priority_factor,
    )
    if model_id.startswith("gpt-5.6-"):
        priority["cache_write_usd_per_million"] = clean_number(input_price * 2.5)
    return {
        "id": f"openai-{model_id}",
        "provider_id": "openai",
        "aliases": [model_id, "gpt-5.5-instant"] if model_id == "gpt-5.5" else [model_id],
        "source": "openai_official",
        "source_updated_at": updated_at,
        "standard": standard,
        "priority": priority,
        "context_tiers": context_tiers,
    }


def price(input_price: float, cache_read: float | None, output_price: float) -> dict:
    result = {
        "input_usd_per_million": clean_number(input_price),
        "output_usd_per_million": clean_number(output_price),
    }
    if cache_read is not None:
        result["cached_input_usd_per_million"] = clean_number(cache_read)
    return result


def parse_models_dev(source: str, captured_at: str) -> list[dict]:
    try:
        providers = json.loads(source)
    except Exception as error:
        raise APIPriceCardError("models.dev returned invalid JSON") from error
    if not isinstance(providers, dict) or len(providers) < 20:
        raise APIPriceCardError("models.dev provider catalog is unexpectedly small")

    rows: list[dict] = []
    for source_provider, model_id, provider_id, aliases in MODELS_DEV_SELECTIONS:
        provider = providers.get(source_provider)
        model = provider.get("models", {}).get(model_id) if isinstance(provider, dict) else None
        if not isinstance(model, dict) or not isinstance(model.get("cost"), dict):
            raise APIPriceCardError(f"models.dev is missing {source_provider}/{model_id}")
        cost = model["cost"]
        standard = normalized_models_dev_price(cost)
        tiers = []
        for tier in cost.get("tiers", []):
            condition = tier.get("tier", {}) if isinstance(tier, dict) else {}
            if condition.get("type") != "context" or not positive_int(condition.get("size")):
                raise APIPriceCardError(f"unsupported models.dev tier for {model_id}")
            tiers.append(
                {
                    "minimum_input_tokens": condition["size"],
                    "price": normalized_models_dev_price(tier),
                }
            )
        rows.append(
            {
                "id": f"modelsdev-{model_id}"
                if model_id.startswith(f"{provider_id}-")
                else f"modelsdev-{provider_id}-{model_id}",
                "provider_id": provider_id,
                "aliases": list(aliases),
                "source": "models_dev",
                "source_updated_at": model.get("last_updated"),
                "first_captured_at": captured_at,
                "standard": standard,
                "context_tiers": tiers,
            }
        )
    return rows


def normalized_models_dev_price(cost: dict) -> dict:
    for required in ("input", "output"):
        if not valid_number(cost.get(required)):
            raise APIPriceCardError(f"invalid models.dev {required} price")
    result = price(cost["input"], cost.get("cache_read"), cost["output"])
    if "cache_write" in cost:
        if not valid_number(cost["cache_write"]):
            raise APIPriceCardError("invalid models.dev cache_write price")
        result["cache_write_usd_per_million"] = cost["cache_write"]
    return result


def preserve_local_fields(rows: list[dict], previous: list[dict]) -> list[dict]:
    previous_by_id = {row["id"]: row for row in previous}
    result = copy.deepcopy(rows)
    for row in result:
        old = previous_by_id.get(row["id"], {})
        if old.get("aliases"):
            row["aliases"] = old["aliases"]
        if row["source"] == "models_dev" and old.get("first_captured_at"):
            row["first_captured_at"] = old["first_captured_at"]
        if old and price_definition(row) == price_definition(old):
            if old.get("source_updated_at"):
                row["source_updated_at"] = old["source_updated_at"]
    order = {row["id"]: index for index, row in enumerate(previous)}
    result.sort(key=lambda row: (order.get(row["id"], len(order)), row["id"]))
    return result


def price_definition(row: dict) -> dict:
    """Return fields that change the price calculation, excluding refresh metadata."""
    return {
        "id": row.get("id"),
        "provider_id": row.get("provider_id"),
        "aliases": row.get("aliases"),
        "source": row.get("source"),
        "standard": row.get("standard"),
        "priority": row.get("priority"),
        "context_tiers": row.get("context_tiers", []),
    }


def validate_price(value: dict) -> None:
    required = ("input_usd_per_million", "output_usd_per_million")
    optional = ("cached_input_usd_per_million", "cache_write_usd_per_million")
    if any(not valid_number(value.get(key)) for key in required):
        raise APIPriceCardError("price is missing required input/output fields")
    if any(key in value and not valid_number(value[key]) for key in optional):
        raise APIPriceCardError("price has a negative or non-finite optional field")


def validate_manifest(manifest: dict, now: dt.datetime | None = None) -> None:
    if manifest.get("schema") != 1 or not isinstance(manifest.get("versions"), list):
        raise APIPriceCardError("manifest schema or versions are invalid")
    versions = manifest["versions"]
    ids = [version.get("id") for version in versions]
    if not ids or len(ids) != len(set(ids)) or manifest.get("current_version") != ids[-1]:
        raise APIPriceCardError("current version must be the unique latest version")
    parse_datetime(manifest.get("generated_at", ""))
    previous_effective: dt.datetime | None = None
    for version in versions:
        effective = parse_datetime(version.get("effective_at", ""))
        if previous_effective is not None and effective <= previous_effective:
            raise APIPriceCardError("historical price versions are not strictly monotonic")
        previous_effective = effective
        models = version.get("models")
        if not isinstance(models, list) or not models:
            raise APIPriceCardError("price version has no models")
        if len({row.get("id") for row in models}) != len(models):
            raise APIPriceCardError("price version contains duplicate model IDs")
        if version.get("content_sha256") != version_hash(version):
            raise APIPriceCardError("historical price version content hash changed")
        aliases: set[tuple[str, str]] = set()
        for row in models:
            if not row.get("id") or not row.get("provider_id") or not row.get("aliases"):
                raise APIPriceCardError("model identity or aliases are missing")
            for alias in row["aliases"]:
                key = (row["provider_id"], alias.strip().lower().split("/")[-1])
                if key in aliases:
                    raise APIPriceCardError("duplicate provider/model alias")
                aliases.add(key)
            if row.get("source") not in {"openai_official", "models_dev"}:
                raise APIPriceCardError("unknown price source")
            validate_price(row.get("standard", {}))
            if row.get("priority") is not None:
                validate_price(row["priority"])
            for tier in row.get("context_tiers", []):
                if not positive_int(tier.get("minimum_input_tokens")):
                    raise APIPriceCardError("invalid context tier threshold")
                validate_price(tier.get("price", {}))
                if tier.get("priority_price") is not None:
                    validate_price(tier["priority_price"])
            if row.get("source_updated_at"):
                parse_datetime(row["source_updated_at"])
            if row.get("first_captured_at"):
                parse_datetime(row["first_captured_at"])

    current = versions[-1]
    openai_models = {
        alias
        for row in current["models"]
        if row.get("provider_id") == "openai" and row.get("source") == "openai_official"
        for alias in row.get("aliases", [])
    }
    if not REQUIRED_OPENAI_MODELS.issubset(openai_models):
        raise APIPriceCardError("required official OpenAI prices are missing")
    reference = (now or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc)
    for row in current["models"]:
        updated = row.get("source_updated_at")
        if updated and reference - parse_datetime(updated) > dt.timedelta(days=MAX_SOURCE_AGE_DAYS):
            raise APIPriceCardError(f"price source is stale for {row['id']}")


def apply_snapshot(manifest: dict, rows: list[dict], now: dt.datetime) -> tuple[dict, bool]:
    validate_manifest(manifest, now=now)
    current = manifest["versions"][-1]
    rows = preserve_local_fields(rows, current["models"])
    candidate = {"id": "candidate", "effective_at": now.isoformat(), "models": rows}
    candidate["content_sha256"] = version_hash(candidate)
    validate_manifest(
        {
            "schema": 1,
            "current_version": "candidate",
            "generated_at": now.isoformat(),
            "sources": list(OPENAI_MODEL_URLS.values()) + [MODELS_DEV_URL],
            "versions": [candidate],
        },
        now=now,
    )
    if current["models"] == rows:
        return manifest, False

    updated = copy.deepcopy(manifest)
    timestamp = now.astimezone(dt.timezone.utc).replace(microsecond=0)
    version_id = timestamp.date().isoformat()
    if version_id in {version["id"] for version in updated["versions"]}:
        version_id = timestamp.strftime("%Y-%m-%dT%H%M%SZ")
    next_version = {
        "id": version_id,
        "effective_at": timestamp.isoformat().replace("+00:00", "Z"),
        "models": rows,
    }
    next_version["content_sha256"] = version_hash(next_version)
    updated["versions"].append(next_version)
    updated["current_version"] = version_id
    updated["generated_at"] = timestamp.isoformat().replace("+00:00", "Z")
    updated["sources"] = list(OPENAI_MODEL_URLS.values()) + [MODELS_DEV_URL]
    validate_manifest(updated, now=now)
    return updated, True


def valid_number(value: object) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(value) and value >= 0


def clean_number(value: float) -> int | float:
    rounded = round(float(value), 12)
    return int(rounded) if rounded.is_integer() else rounded


def version_hash(version: dict) -> str:
    payload = {
        "id": version.get("id"),
        "effective_at": version.get("effective_at"),
        "models": version.get("models"),
    }
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("Sources/CodexToolbox/Resources/api-price-card-v1.json"),
    )
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    openai_rows = [
        parse_openai_model_page(model_id, fetch(url), now.date().isoformat())
        for model_id, url in OPENAI_MODEL_URLS.items()
    ]
    models_dev_rows = parse_models_dev(
        fetch(MODELS_DEV_URL),
        now.isoformat().replace("+00:00", "Z"),
    )
    updated, changed = apply_snapshot(manifest, openai_rows + models_dev_rows, now)
    if changed and args.write:
        args.manifest.write_text(
            json.dumps(updated, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print("api-price-card-changed" if changed else "api-price-card-unchanged")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except APIPriceCardError as error:
        print(f"api-price-card-error: {error}", file=sys.stderr)
        sys.exit(1)
