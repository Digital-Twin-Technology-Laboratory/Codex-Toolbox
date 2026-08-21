import copy
import datetime as dt
import json
import unittest

from scripts.update_api_price_card import (
    APIPriceCardError,
    apply_snapshot,
    parse_models_dev,
    parse_openai_model_page,
    normalized_models_dev_price,
    version_hash,
    validate_manifest,
)


NOW = dt.datetime(2026, 8, 20, 15, tzinfo=dt.timezone.utc)


def openai_html(input_price="2.00", cached="0.20", output="12.00"):
    return (
        "<section>Text tokens <span>Per 1M tokens</span> "
        f"Input ${input_price} Cached input ${cached} Output ${output}</section>"
    )


def models_dev_json():
    rows = {
        "xai": ("grok-4.6", {"input": 2, "output": 6, "cache_read": 0.5,
            "tiers": [{"input": 4, "output": 12, "cache_read": 1,
                "tier": {"type": "context", "size": 200000}}]}, "2026-08-12"),
        "moonshotai": ("kimi-k3", {"input": 3, "output": 15, "cache_read": 0.3}, "2026-07-16"),
        "deepseek": None,
    }
    providers = {f"padding-{index}": {"models": {}} for index in range(20)}
    for provider, value in rows.items():
        models = {}
        if provider == "deepseek":
            models = {
                "deepseek-v4-flash": {"cost": {"input": 0.14, "output": 0.28, "cache_read": 0.0028}, "last_updated": "2026-07-31"},
                "deepseek-v4-pro": {"cost": {"input": 0.435, "output": 0.87, "cache_read": 0.003625}, "last_updated": "2026-08-12"},
            }
        elif value:
            model_id, cost, updated = value
            models[model_id] = {"cost": cost, "last_updated": updated}
        providers[provider] = {"models": models}
    return json.dumps(providers)


def manifest(rows):
    version = {
        "id": "2026-08-20-v1",
        "effective_at": "2026-07-30T00:00:00Z",
        "models": rows,
    }
    version["content_sha256"] = version_hash(version)
    return {
        "schema": 1,
        "current_version": "2026-08-20-v1",
        "generated_at": "2026-08-20T14:30:00Z",
        "sources": ["official", "models.dev"],
        "versions": [version],
    }


def rows():
    official = [
        parse_openai_model_page("gpt-5.5", openai_html("5", "0.5", "30"), "2026-08-20"),
        parse_openai_model_page("gpt-5.6-sol", openai_html("5", "0.5", "30"), "2026-08-20"),
        parse_openai_model_page("gpt-5.6-terra", openai_html(), "2026-08-20"),
        parse_openai_model_page("gpt-5.6-luna", openai_html("0.2", "0.02", "1.2"), "2026-08-20"),
    ]
    return official + parse_models_dev(models_dev_json(), "2026-08-20T15:00:00Z")


class APIPriceCardScriptTests(unittest.TestCase):
    def test_refresh_date_alone_does_not_append_price_history(self):
        source = manifest(rows())
        current = source["versions"][-1]
        candidate_rows = copy.deepcopy(current["models"])
        for row in candidate_rows:
            row["source_updated_at"] = "2026-08-21"

        result, changed = apply_snapshot(
            source,
            candidate_rows,
            dt.datetime(2026, 8, 21, 5, 0, tzinfo=dt.timezone.utc),
        )

        self.assertFalse(changed)
        self.assertEqual(result, source)

    def test_openai_override_builds_fast_and_long_context_prices(self):
        row = parse_openai_model_page("gpt-5.6-terra", openai_html(), "2026-08-20")
        self.assertEqual(row["source"], "openai_official")
        self.assertEqual(row["standard"]["cache_write_usd_per_million"], 2.5)
        self.assertEqual(row["priority"]["output_usd_per_million"], 24)
        self.assertEqual(row["context_tiers"][0]["price"]["output_usd_per_million"], 18)
        self.assertEqual(row["context_tiers"][0]["priority_price"]["output_usd_per_million"], 36)

    def test_models_dev_normalizes_optional_zero_and_context_tier(self):
        result = parse_models_dev(models_dev_json(), "2026-08-20T15:00:00Z")
        grok = next(row for row in result if row["id"] == "modelsdev-xai-grok-4.6")
        self.assertEqual(grok["context_tiers"][0]["minimum_input_tokens"], 200000)
        self.assertNotIn("cache_write_usd_per_million", grok["standard"])
        explicit_zero = normalized_models_dev_price(
            {"input": 1, "output": 2, "cache_write": 0}
        )
        self.assertEqual(explicit_zero["cache_write_usd_per_million"], 0)

    def test_change_appends_and_preserves_published_history_and_first_capture(self):
        original_rows = rows()
        source = manifest(original_rows)
        changed_rows = copy.deepcopy(original_rows)
        changed_rows[0]["standard"]["input_usd_per_million"] = 6
        changed_rows[-1]["first_captured_at"] = "2026-08-21T00:00:00Z"
        result, changed = apply_snapshot(source, changed_rows, NOW)
        self.assertTrue(changed)
        self.assertEqual(result["versions"][0], source["versions"][0])
        self.assertEqual(len(result["versions"]), 2)
        self.assertEqual(
            result["versions"][-1]["models"][-1]["first_captured_at"],
            original_rows[-1]["first_captured_at"],
        )

    def test_duplicate_alias_negative_missing_openai_and_stale_source_fail_closed(self):
        base = manifest(rows())
        duplicate = copy.deepcopy(base)
        duplicate["versions"][0]["models"][1]["aliases"] = ["gpt-5.5"]
        with self.assertRaises(APIPriceCardError):
            validate_manifest(duplicate, now=NOW)
        negative = copy.deepcopy(base)
        negative["versions"][0]["models"][0]["standard"]["input_usd_per_million"] = -1
        with self.assertRaises(APIPriceCardError):
            validate_manifest(negative, now=NOW)
        missing = copy.deepcopy(base)
        missing["versions"][0]["models"] = missing["versions"][0]["models"][4:]
        with self.assertRaises(APIPriceCardError):
            validate_manifest(missing, now=NOW)
        stale = copy.deepcopy(base)
        stale["versions"][0]["models"][-1]["source_updated_at"] = "2025-01-01"
        with self.assertRaises(APIPriceCardError):
            validate_manifest(stale, now=NOW)

    def test_historical_content_hash_rejects_silent_rewrite(self):
        rewritten = manifest(rows())
        rewritten["versions"][0]["models"][0]["standard"]["input_usd_per_million"] = 999
        with self.assertRaisesRegex(APIPriceCardError, "content hash changed"):
            validate_manifest(rewritten, now=NOW)


if __name__ == "__main__":
    unittest.main()
