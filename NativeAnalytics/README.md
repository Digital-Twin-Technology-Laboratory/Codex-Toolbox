# Read-only identity and task usage bridge

The Universal 2 helper is pinned to OpenAI Codex revision `b741e480e203f037ca726bc2a76d99a8e8668e66` and Rust 1.95.0. Source hashes and dependency locks remain unchanged.

Build 54 allows two fixed read commands: `identity` and `taskUsage`. Identity keeps schema 2 and returns ChatGPT, API, signed-out or unknown authentication. Task usage returns schema 3 with the same installation-salted account/user fingerprint, timestamps, completeness, plan and cumulative 5-hour/weekly percentages. No credentials, email, original account IDs or native dollar costs are output; error bodies are suppressed.

Task queries send only 1–100 disjoint roots, creation dates and their legacy descendant IDs (at most 1,000 IDs per request) to the official account endpoint. They never send task titles, prompts or file contents. The helper checks identity before/after each query; Swift also validates account generations, including A → B → A, before displaying results. API/external-provider modes do not request ChatGPT task reports.

Machine-wide Token history stays separate. `native-task-quota-v1.json` holds account-isolated raw snapshots for 90 days. Normal polling is five minutes, with launch/open/wake/day-boundary checks. Sleeps, membership/plan changes, backwards watermarks and corrections break comparison segments. Complete same-day native task values and fully covered day boundaries use `=`; observed partial differences and calibrated local estimates use `≈`. Missing data stays unavailable. Per-task percentages compare recorded consumption against a full allowance and may exceed 100%; they are not capped against the current remaining balance.

Historical rollout identity stays unknown. Approximate calibration aligns same-account native steps with non-API local events of the same model/effort/speed; it does not write the current identity into historical rollout evidence. Other devices or undetected mixed-account events can affect approximation, and tooltips describe that coverage.

The local cost experiment defaults off even on upgrade. Pricing/rate requests and local cost conversions run only when explicitly enabled. Quota analysis needs no pricing request. Quota/reset cards still use the separate fixed app-server `account/rateLimits/read` method. No redemption, arbitrary HTTP command, account mutation or public release is implemented.
