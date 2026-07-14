# Full-bleed app icon adjustment

The portable build must not embed the rounded icon inside an additional transparent canvas. The dark background therefore reaches the full 1024-point artwork bounds, while the normal macOS rounded silhouette remains part of the artwork.

The vector concept is the single source for the legacy ICNS fallback. The icon-generation script renders that SVG into a 1024-pixel master and derives every required iconset size from it. The DMG build regenerates these files before packaging so the Finder icon cannot silently fall back to an older, inset raster.

Success criteria:

- no uniform light or transparent ring around the app icon;
- the dark background reaches the top, bottom, left, and right artwork edges;
- the radar, Codex badge, and terminal mark remain unchanged;
- the packaged application remains a valid Universal 2 signed bundle.
