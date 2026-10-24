#!/usr/bin/env python3
"""Compare the real Swift transport using a local, synthetic partial-EOF child."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FILES = [
    "Sources/CodexToolboxCore/AppMetadata.swift",
    "Sources/CodexToolboxCore/ResetCredits/ResetCreditsClient.swift",
    "Sources/CodexToolboxCore/Domain/ResetCreditModels.swift",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="8e12091545ce9f6c82711a433cd098695c651340")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    results = {}
    with tempfile.TemporaryDirectory(prefix="toolbox-process-performance-") as temp:
        temporary = Path(temp)
        baseline_sources = []
        for relative in FILES:
            destination = temporary / Path(relative).name
            destination.write_bytes(subprocess.check_output(["git", "show", f"{args.baseline}:{relative}"], cwd=ROOT))
            baseline_sources.append(destination)
        sources = {
            "baseline": baseline_sources,
            "candidate": [ROOT / relative for relative in FILES] + [ROOT / "Sources/CodexToolboxCore/Networking/BoundedProcess.swift"],
        }
        for name, files in sources.items():
            executable = temporary / name
            subprocess.run(["swiftc", "-swift-version", "6", "-O", "-parse-as-library", *map(str, files),
                            str(HERE / "Probe.swift"), "-o", str(executable)], check=True, cwd=ROOT)
            results[name] = [json.loads(subprocess.check_output([str(executable), str(HERE / "partial-eof")], text=True))
                             for _ in range(args.runs)]
    text = json.dumps(results, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
