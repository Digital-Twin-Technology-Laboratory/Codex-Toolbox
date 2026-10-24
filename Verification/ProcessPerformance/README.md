# Synthetic partial-EOF transport comparison

Run from the repository root:

```sh
python3 Verification/ProcessPerformance/run.py --output /private/tmp/process-partial-eof.json
```

The harness compiles the actual `ProcessCodexAppServerTransport` twice with Swift 6 and `-O`: from baseline `8e12091545ce9f6c82711a433cd098695c651340`, and from the current checkout. The candidate includes its shared `BoundedProcess` implementation. Both use the same synthetic child, which reads one request, emits `partial` without a newline, and exits. No Codex installation, account, credentials or network is used.

Each request has a two-second timeout. `wall_seconds` covers the request; `cpu_seconds` is the calling process's user plus system CPU delta from `getrusage(RUSAGE_SELF)`, excluding the trivial shell child. Three repetitions are recorded by default. Compilation time is excluded.

The baseline should report `timeout` after busy-polling. The candidate should report the existing protocol error promptly. The recorded implementation-run results are in `docs/verification/evidence/2026-10-23-v1.4.2/process-partial-eof.json`. These are controlled component measurements, not full-app or sustained energy acceptance.
