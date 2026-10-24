#!/usr/bin/env python3
"""Scale an already anonymized quota fixture without reading live application data.

Copies occupy disjoint 180-day periods and use distinct task/continuity IDs.
Account identity, token values, percentages and relative sample timing are kept.
The most recent copy and the evaluation time are unchanged.
"""
import argparse
import datetime as dt
import json
from pathlib import Path


DATE_FIELDS = {"createdAt", "earliestCreatedAt", "dataAsOf", "collectedAt",
               "timestamp", "resetsAt", "dateKey"}
ID_FIELDS = {"rootTaskID", "continuityID", "id"}


def copy_period(value, copy_index, field=None):
    if isinstance(value, dict):
        return {k: copy_period(v, copy_index, k) for k, v in value.items()}
    if isinstance(value, list):
        return [copy_period(v, copy_index, "id" if field == "descendantIDs" else None) for v in value]
    if value is not None and field in DATE_FIELDS:
        offset = dt.timedelta(days=180 * copy_index)
        if isinstance(value, (int, float)):
            return value - offset.total_seconds()
        if field == "dateKey":
            return (dt.date.fromisoformat(value) - offset).isoformat()
        return (dt.datetime.fromisoformat(value.replace("Z", "+00:00")) - offset).isoformat().replace("+00:00", "Z")
    if isinstance(value, str) and field in ID_FIELDS:
        return f"copy-{copy_index}-{value}"
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--factor", type=int, default=5)
    args = parser.parse_args()
    if args.factor < 1:
        parser.error("factor must be positive")
    source = json.loads(args.input.read_text())
    result = dict(source)
    result["history"] = dict(source["history"])
    for field in ("days", "quotaObservations"):
        result["history"][field] = [row for n in range(args.factor)
            for row in copy_period(source["history"][field], n)]
    result["history"]["days"].sort(key=lambda row: row["dateKey"])
    result["history"]["quotaObservations"].sort(key=lambda row: row["timestamp"])
    result["snapshots"] = [row for n in range(args.factor)
        for row in copy_period(source["snapshots"], n)]
    args.output.write_text(json.dumps(result, separators=(",", ":")))
    args.output.chmod(0o600)
    print(json.dumps({"days": len(result["history"]["days"]),
        "observations": len(result["history"]["quotaObservations"]),
        "snapshots": len(result["snapshots"])}))


if __name__ == "__main__":
    main()
