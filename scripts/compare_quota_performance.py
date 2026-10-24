#!/usr/bin/env python3
"""Compile frozen/current Core sources and compare one private, fixed fixture.

Pass an already captured fixture; this script never opens the live app's data.
Detailed outputs remain in the explicitly selected output directory.
"""
import argparse
import json
from pathlib import Path
import subprocess


def compare(a, b, path="root"):
    if isinstance(a, dict):
        assert isinstance(b, dict) and a.keys() == b.keys(), f"Different fields at {path}"
        for key in a:
            compare(a[key], b[key], f"{path}.{key}")
    elif isinstance(a, list):
        assert isinstance(b, list) and len(a) == len(b), f"Different length at {path}"
        for i, (x, y) in enumerate(zip(a, b)):
            compare(x, y, f"{path}[{i}]")
    elif isinstance(a, (float, int)) and not isinstance(a, bool):
        assert abs(a - b) <= 1e-6, f"Numerical mismatch at {path}"
    else:
        assert a == b, f"Value mismatch at {path}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--current", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    reports = []
    for label, root in [("baseline", args.baseline), ("candidate", args.current)]:
        binary = args.output / f"{label}-quota-probe"
        if not args.skip_build:
            subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-lsqlite3",
                *map(str, sorted((root / "Sources/CodexToolboxCore").rglob("*.swift"))),
                str(args.current / "Verification/Performance/main.swift"), "-o", str(binary)], check=True)
        report = args.output / f"{label}-quota-report.json"
        subprocess.run([str(binary), str(args.fixture), str(report)], check=True)
        reports.append(json.loads(report.read_text()))
    for field in ("days", "observations", "snapshots", "legacy", "native"):
        compare(reports[0][field], reports[1][field], field)
    print("Numerical comparison passed (tolerance 1e-6; precision, timestamps and missing values exact).")
    print(json.dumps({key: {"baseline": reports[0][key], "candidate": reports[1][key]}
                      for key in ("legacySeconds", "nativeSeconds")}, indent=2))


if __name__ == "__main__":
    main()
