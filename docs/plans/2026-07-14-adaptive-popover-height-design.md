# Adaptive popover height design

The blank region is caused by two independent fixed 680-point heights: `DashboardView` always claims the chart-sized frame, and `StatusItemController` always assigns the same `NSPopover.contentSize`. Hiding `TrendChartView` removes the chart content but neither outer size changes.

The popover will keep its existing 430-point width and use two explicit height presets. The chart-visible layout remains 680 points, while the chart-hidden layout uses a compact 460-point height that contains the status header, four ranking cards, padding, divider, and footer without reserving chart space. A shared app-level `DashboardLayout` owns these dimensions so SwiftUI and AppKit cannot drift.

`DashboardView` will derive its frame height from the observable `showsTrendChart` setting. `StatusItemController` will retain the app model, recompute `contentSize` when `UserDefaults` changes, and recompute once immediately before opening. This covers toggling the setting while the popover is either open or closed. Existing scrolling remains available for error messages and expanded ranking content.

Verification will cover both configuration values through a release build plus live visual inspection. The chart-hidden state must have no large blank region and must show the footer; the chart-visible state must retain the existing chart layout. The final result will be released as `v0.1.0-beta.4` with build number 4.
