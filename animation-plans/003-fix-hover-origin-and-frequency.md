# 003 — Make hover feedback subtle and origin-aware

- **Status**: DONE
- **Commit**: c743342
- **Severity**: MEDIUM
- **Category**: Physicality, purpose and frequency
- **Estimated scope**: 2 files, about 40 lines

## Problem

`Sources/CodexToolbox/Popover/RankingSection.swift` previously used `.transition(.scale)`
for a frequently shown hover icon. The default scale starts at zero, so the icon
appears from nothing. The whole card also scales on every hover at `:142`.

## Target

- Hover icon insertion starts at scale `0.94` plus opacity, never `0`.
- Use 160ms ease-out or the shared damping-1 spring.
- Remove whole-card hover scale; retain restrained stroke/color feedback.
- Under Reduced Motion, use only a 200ms opacity crossfade.

## Repo conventions to follow

- System icons remain SF Symbols.
- Hover is supplementary; native button focus and press states carry interaction.

## Steps

1. Replace the default scale transition with scale `0.94` plus opacity.
2. Remove whole-card hover scaling and reduce shadow changes.
3. Branch to opacity-only when Reduced Motion is enabled.

## Boundaries

- Do not change card geometry or ranking content.
- Do not add looping or decorative motion.

## Verification

- Move the pointer repeatedly across all cards; feedback must not feel busy.
- At slow speed, the icon materializes from 94%, not zero.
- With Reduce Motion enabled, only opacity changes.
