#!/usr/bin/env python3
"""Strictly refresh the versioned Codex credit rate manifest from OpenAI pages."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import html
from html.parser import HTMLParser
import json
import math
from pathlib import Path
import re
import sys
import urllib.request


RATE_SOURCE = "https://help.openai.com/en/articles/20001106-codex-rate-card"
RATE_FETCH_URL = "https://help.openai.com/articles/20001106-codex-rate-card.json"
SPEED_SOURCE = "https://learn.chatgpt.com/docs/agent-configuration/speed"


class RateCardError(RuntimeError):
    pass


class TableParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.tables: list[list[list[str]]] = []
        self._table: list[list[str]] | None = None
        self._row: list[str] | None = None
        self._cell: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "table":
            self._table = []
        elif tag == "tr" and self._table is not None:
            self._row = []
        elif tag in {"th", "td"} and self._row is not None:
            self._cell = []

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag in {"th", "td"} and self._cell is not None and self._row is not None:
            self._row.append(normalize_text(" ".join(self._cell)))
            self._cell = None
        elif tag == "tr" and self._row is not None and self._table is not None:
            if any(self._row):
                self._table.append(self._row)
            self._row = None
        elif tag == "table" and self._table is not None:
            if self._table:
                self.tables.append(self._table)
            self._table = None


class TextParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def normalize_text(value: str) -> str:
    return " ".join(html.unescape(value).split())


def fetch(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/html,application/json",
            "User-Agent": "Mozilla/5.0 CodexToolboxRateCard/1.3",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RateCardError(f"unexpected HTTP {response.status} for {url}")
            return response.read().decode("utf-8")
    except Exception as error:
        if isinstance(error, RateCardError):
            raise
        raise RateCardError(f"failed to fetch {url}: {error}") from error


def model_id(name: str) -> str:
    value = name.lower().replace("–", "-").replace("—", "-")
    value = re.sub(r"\s+", "-", value)
    value = re.sub(r"[^a-z0-9.-]+", "-", value).strip("-")
    if not value.startswith("gpt-"):
        raise RateCardError(f"unexpected model label: {name!r}")
    return value


def numeric_credit(value: str) -> float:
    match = re.fullmatch(r"~?\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s+credits?", value, re.I)
    if not match:
        raise RateCardError(f"invalid credit value: {value!r}")
    number = float(match.group(1).replace(",", ""))
    if not number >= 0 or number == float("inf"):
        raise RateCardError(f"non-finite credit value: {value!r}")
    return number


def parse_rate_page(source: str) -> tuple[list[dict], list[dict]]:
    parser = TableParser()
    parser.feed(source)
    token_table = next(
        (
            table
            for table in parser.tables
            if table
            and [cell.lower() for cell in table[0]]
            == ["model", "input tokens", "cached input tokens", "output tokens"]
        ),
        None,
    )
    if token_table is None or len(token_table) < 6:
        raise RateCardError("token rate table structure changed or has too few models")

    models: list[dict] = []
    for row in token_table[1:]:
        if len(row) != 4:
            raise RateCardError(f"unexpected token rate row: {row!r}")
        if row[0].lower().startswith("gpt-image-"):
            continue
        if all(value.lower() == "research preview" for value in row[1:]):
            continue
        identifier = model_id(row[0])
        models.append(
            {
                "id": identifier,
                "aliases": [identifier],
                "input_credits_per_million": numeric_credit(row[1]),
                "cached_input_credits_per_million": numeric_credit(row[2]),
                "output_credits_per_million": numeric_credit(row[3]),
            }
        )

    legacy_table = next(
        (
            table
            for table in parser.tables
            if table
            and len(table[0]) >= 4
            and table[0][1].lower() == "unit"
            and any("gpt-5.6" in cell.lower() for cell in table[0])
        ),
        None,
    )
    if legacy_table is None:
        raise RateCardError("legacy rate table structure changed")
    local_row = next(
        (row for row in legacy_table[1:] if row and row[0].lower() == "local tasks"),
        None,
    )
    if local_row is None or len(local_row) != len(legacy_table[0]):
        raise RateCardError("legacy local-task row is missing or malformed")
    legacy: list[dict] = []
    for label, value in zip(legacy_table[0][2:], local_row[2:]):
        if value.lower() == "not available":
            continue
        identifier = model_id(label)
        legacy.append(
            {
                "id": identifier,
                "aliases": [identifier],
                "credits_per_message": numeric_credit(value),
            }
        )

    text_parser = TextParser()
    text_parser.feed(source)
    page_text = normalize_text(" ".join(text_parser.parts)).lower()
    if "codex does not charge for cache writes" not in page_text:
        raise RateCardError("official cache-write-free statement is missing")
    if len(models) < 9:
        raise RateCardError("too few numeric Codex model rates after filtering previews")
    return models, legacy


def parse_speed_page(source: str) -> list[dict]:
    parser = TextParser()
    parser.feed(source)
    text = normalize_text(" ".join(parser.parts))
    combined = re.search(
        r"GPT-5\.6 and GPT-5\.5 consume credits at ([0-9]+(?:\.[0-9]+)?)x",
        text,
        re.I,
    )
    gpt54 = re.search(
        r"GPT-5\.4 consumes credits at ([0-9]+(?:\.[0-9]+)?)x",
        text,
        re.I,
    )
    supported = re.search(
        r"supports GPT-5\.6, GPT-5\.5, and GPT-5\.4",
        text,
        re.I,
    )
    if not combined or not gpt54 or not supported:
        raise RateCardError("Fast-mode support or multiplier text changed")
    multipliers = [
        {"model_prefix": "gpt-5.6", "multiplier": float(combined.group(1))},
        {"model_prefix": "gpt-5.5", "multiplier": float(combined.group(1))},
        {"model_prefix": "gpt-5.4", "multiplier": float(gpt54.group(1))},
    ]
    if any(row["multiplier"] <= 1 for row in multipliers):
        raise RateCardError("Fast multiplier must be greater than one")
    return multipliers


def preserve_aliases(rows: list[dict], previous: list[dict]) -> list[dict]:
    aliases = {row["id"]: row.get("aliases", []) for row in previous}
    result = copy.deepcopy(rows)
    for row in result:
        saved = aliases.get(row["id"])
        if saved:
            row["aliases"] = saved
    previous_order = {row["id"]: index for index, row in enumerate(previous)}
    result.sort(key=lambda row: (previous_order.get(row["id"], len(previous_order)), row["id"]))
    return result


def validate_manifest(manifest: dict) -> None:
    if manifest.get("schema") != 1 or not manifest.get("versions"):
        raise RateCardError("manifest schema or versions are invalid")
    identifiers = [version.get("id") for version in manifest["versions"]]
    if len(identifiers) != len(set(identifiers)) or manifest.get("current_version") not in identifiers:
        raise RateCardError("manifest version identifiers are invalid")
    if manifest.get("current_version") != identifiers[-1]:
        raise RateCardError("current version must be the latest historical version")
    try:
        dt.datetime.fromisoformat(manifest["generated_at"].replace("Z", "+00:00"))
    except Exception as error:
        raise RateCardError("invalid manifest generated_at") from error
    previous_effective: dt.datetime | None = None
    for version in manifest["versions"]:
        try:
            effective = dt.datetime.fromisoformat(version["effective_at"].replace("Z", "+00:00"))
        except Exception as error:
            raise RateCardError("invalid version effective_at") from error
        if previous_effective is not None and effective <= previous_effective:
            raise RateCardError("historical rate versions are not strictly monotonic")
        previous_effective = effective
        for key in ("models", "fast_multipliers", "legacy_models"):
            rows = version.get(key)
            if not isinstance(rows, list):
                raise RateCardError(f"missing {key}")
            row_ids = [row.get("id", row.get("model_prefix")) for row in rows]
            if len(row_ids) != len(set(row_ids)):
                raise RateCardError(f"duplicate rows in {key}")
        for row in version["models"]:
            values = [
                row.get("input_credits_per_million"),
                row.get("cached_input_credits_per_million"),
                row.get("output_credits_per_million"),
            ]
            if not row.get("id") or not row.get("aliases") or any(
                not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0
                for value in values
            ):
                raise RateCardError("invalid model token rate")
            if values[1] > values[0]:
                raise RateCardError("cached input rate exceeds input rate")
        model_ids = {row["id"] for row in version["models"]}
        for row in version["fast_multipliers"]:
            prefix = row.get("model_prefix")
            if (
                not isinstance(row.get("multiplier"), (int, float))
                or not math.isfinite(row["multiplier"])
                or row["multiplier"] <= 1
            ):
                raise RateCardError("invalid Fast multiplier")
            if not any(identifier.startswith(prefix) for identifier in model_ids):
                raise RateCardError("Fast multiplier has no matching model")
        for row in version["legacy_models"]:
            if (
                not isinstance(row.get("credits_per_message"), (int, float))
                or not math.isfinite(row["credits_per_message"])
                or row["credits_per_message"] < 0
            ):
                raise RateCardError("invalid legacy rate")


def apply_snapshot(
    manifest: dict,
    models: list[dict],
    legacy: list[dict],
    fast: list[dict],
    now: dt.datetime,
) -> tuple[dict, bool]:
    validate_manifest(manifest)
    current = next(
        version for version in manifest["versions"] if version["id"] == manifest["current_version"]
    )
    if {row.get("model_prefix") for row in fast} != {"gpt-5.6", "gpt-5.5", "gpt-5.4"}:
        raise RateCardError("unexpected Fast-mode support range")
    models = preserve_aliases(models, current["models"])
    legacy = preserve_aliases(legacy, current["legacy_models"])
    comparable = {
        "models": models,
        "fast_multipliers": fast,
        "legacy_models": legacy,
    }
    if all(current[key] == comparable[key] for key in comparable):
        return manifest, False

    updated = copy.deepcopy(manifest)
    timestamp = now.astimezone(dt.timezone.utc).replace(microsecond=0)
    base_id = timestamp.date().isoformat()
    identifiers = {version["id"] for version in updated["versions"]}
    version_id = base_id
    if version_id in identifiers:
        version_id = timestamp.strftime("%Y-%m-%dT%H%M%SZ")
    new_version = {
        "id": version_id,
        "effective_at": timestamp.isoformat().replace("+00:00", "Z"),
        **comparable,
    }
    updated["versions"].append(new_version)
    updated["current_version"] = version_id
    updated["generated_at"] = new_version["effective_at"]
    updated["sources"] = [RATE_SOURCE, SPEED_SOURCE]
    validate_manifest(updated)
    return updated, True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("Sources/CodexToolbox/Resources/codex-rate-card-v1.json"),
    )
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    models, legacy = parse_rate_page(fetch(RATE_FETCH_URL))
    fast = parse_speed_page(fetch(SPEED_SOURCE))
    updated, changed = apply_snapshot(
        manifest,
        models,
        legacy,
        fast,
        dt.datetime.now(dt.timezone.utc),
    )
    if changed and args.write:
        args.manifest.write_text(
            json.dumps(updated, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
            encoding="utf-8",
        )
    print("rate-card-changed" if changed else "rate-card-unchanged")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RateCardError as error:
        print(f"rate-card-error: {error}", file=sys.stderr)
        sys.exit(1)
