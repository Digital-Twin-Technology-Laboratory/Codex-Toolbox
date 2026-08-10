import copy
import datetime as dt
import unittest

from scripts.update_rate_card import (
    RateCardError,
    apply_snapshot,
    parse_rate_page,
    parse_speed_page,
)


TOKEN_ROWS = [
    ("GPT-5.6 Sol", "125", "12.5", "750"),
    ("GPT-5.6 Terra", "50", "5", "300"),
    ("GPT-5.6 Luna", "5", "0.5", "30"),
    ("GPT-5.5 Cyber", "312.5", "31.25", "1,875"),
    ("GPT-5.5", "125", "12.5", "750"),
    ("GPT-5.4-Mini", "18.75", "1.875", "113"),
    ("GPT-5.4", "62.5", "6.25", "375"),
    ("GPT-5.3-Codex", "43.75", "4.375", "350"),
    ("GPT-5.2", "43.75", "4.375", "350"),
]


def rate_html(rows=TOKEN_ROWS):
    token_rows = "".join(
        f"<tr><td>{name}</td><td>{input_rate} credits</td>"
        f"<td>{cached} credits</td><td>{output} credits</td></tr>"
        for name, input_rate, cached, output in rows
    )
    return f"""
    <html><body>
      <table><tr><th>Model</th><th>Input tokens</th><th>Cached input tokens</th><th>Output tokens</th></tr>
      {token_rows}</table>
      <p>Codex does not charge for cache writes.</p>
      <table>
        <tr><th></th><th>Unit</th><th>GPT-5.6 Sol</th><th>GPT-5.6 Terra</th><th>GPT-5.6 Luna</th><th>GPT-5.5 Cyber</th><th>GPT-5.5</th><th>GPT-5.4</th></tr>
        <tr><td>Local Tasks</td><td>1 message</td><td>~14 credits</td><td>~6 credits</td><td>~1 credits</td><td>~56 credits</td><td>~14 credits</td><td>~7 credits</td></tr>
      </table>
    </body></html>
    """


SPEED_HTML = """
<p>It currently supports GPT-5.6, GPT-5.5, and GPT-5.4.</p>
<p>GPT-5.6 and GPT-5.5 consume credits at 2.5x the Standard rate;
GPT-5.4 consumes credits at 2x the Standard rate.</p>
"""


def manifest():
    models, legacy = parse_rate_page(rate_html())
    return {
        "schema": 1,
        "current_version": "2026-08-05",
        "generated_at": "2026-08-05T00:00:00Z",
        "sources": ["rate", "speed"],
        "versions": [
            {
                "id": "2026-08-05",
                "effective_at": "2026-08-05T00:00:00Z",
                "models": models,
                "fast_multipliers": parse_speed_page(SPEED_HTML),
                "legacy_models": legacy,
            }
        ],
    }


class RateCardScriptTests(unittest.TestCase):
    def test_no_change_is_idempotent(self):
        source = manifest()
        current = source["versions"][0]
        result, changed = apply_snapshot(
            source,
            copy.deepcopy(current["models"]),
            copy.deepcopy(current["legacy_models"]),
            copy.deepcopy(current["fast_multipliers"]),
            dt.datetime(2026, 8, 11, tzinfo=dt.timezone.utc),
        )
        self.assertFalse(changed)
        self.assertEqual(result, source)

    def test_new_model_and_rate_change_append_without_deleting_history(self):
        source = manifest()
        current = source["versions"][0]
        models = copy.deepcopy(current["models"])
        models[0]["input_credits_per_million"] = 126
        models.append(
            {
                "id": "gpt-5.7",
                "aliases": ["gpt-5.7"],
                "input_credits_per_million": 150,
                "cached_input_credits_per_million": 15,
                "output_credits_per_million": 900,
            }
        )
        result, changed = apply_snapshot(
            source,
            models,
            current["legacy_models"],
            current["fast_multipliers"],
            dt.datetime(2026, 8, 11, 1, 2, 3, tzinfo=dt.timezone.utc),
        )
        self.assertTrue(changed)
        self.assertEqual(len(result["versions"]), 2)
        self.assertEqual(result["versions"][0], source["versions"][0])
        self.assertEqual(result["current_version"], "2026-08-11")

    def test_page_structure_break_and_illegal_value_fail_closed(self):
        with self.assertRaises(RateCardError):
            parse_rate_page("<html>changed</html>")
        broken = list(TOKEN_ROWS)
        broken[0] = (broken[0][0], "free", broken[0][2], broken[0][3])
        with self.assertRaises(RateCardError):
            parse_rate_page(rate_html(broken))
        with self.assertRaises(RateCardError):
            parse_speed_page("supports some models at normal speed")
        with self.assertRaises(RateCardError):
            apply_snapshot(
                manifest(),
                manifest()["versions"][0]["models"],
                manifest()["versions"][0]["legacy_models"],
                [{"model_prefix": "gpt-5.6", "multiplier": 2.5}],
                dt.datetime(2026, 8, 11, tzinfo=dt.timezone.utc),
            )


if __name__ == "__main__":
    unittest.main()
