# Fork widget integration

This integration layers upstream PR [#4679](https://github.com/we-promise/sure/pull/4679)
(commit `f459b7798a6c1655f79de01f262e2b6f7b733026`) onto the fork's upstream sync.
It is experimental and separate from `main`. The original widget displays account
balances and net worth. A separate experimental Flexible spending widget now
offers remaining-budget, weekly-guide and optional period-average views for an
explicitly selected flexible-spending pool.

The fork additionally invalidates in-flight widget refreshes when the API key,
server URL or proxy headers change. Run its native regression checks on macOS:

```sh
mkdir -p /tmp/sure-widget-swift-cache
xcrun swiftc -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path /tmp/sure-widget-swift-cache \
  ios/Runner/WidgetSessionGeneration.swift \
  test/native/WidgetSessionGenerationTests.swift \
  -o /tmp/sure-widget-generation-tests
/tmp/sure-widget-generation-tests
```

Run from `mobile/`. Also run `flutter test` and
`flutter analyze --no-fatal-infos`. Full simulator/device lifecycle checks remain
necessary; the standalone Swift check does not replace them.

## Local iOS simulator build

Verified with Xcode 27.2, Flutter 3.44.4 and CocoaPods 1.16.2 on Apple Silicon.
The Podfile keeps pod deployment targets at least iOS 15 for Xcode 27 compatibility.
Use the existing CocoaPods integration and an explicit arm64 simulator build:

```sh
FLUTTER_SWIFT_PACKAGE_MANAGER=false flutter pub get
(cd ios && pod install)
cd ios
FLUTTER_SWIFT_PACKAGE_MANAGER=false xcodebuild \
  -workspace Runner.xcworkspace -scheme Runner -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  BUILD_DIR="$PWD/../build/ios" build
```

This builds Runner and its embedded SureWidget extension without device signing.
The generic `flutter build ios --simulator` route with this toolchain failed during
Flutter's dual-architecture framework check; the explicit arm64 command above passed.
The environment override is per command and avoids an automatic Swift Package
Manager migration of this CocoaPods project.

A clean iPhone 18 Pro simulator on iOS 27.2 accepted the built application and
`simctl launch` returned a process ID. The embedded extension declares
`com.apple.widgetkit-extension`. No credentials or live financial data were used.
Visual login-screen and widget lifecycle checks remain unverified because the
host Mac locked before UI inspection.

## Before using live data

- Configure a personal signing team, bundle IDs and shared App Group for both
  Runner and SureWidget. The upstream signing values are not portable credentials.
- Keep the server private and TLS verification enabled. The OpenAI MCP tunnel is
  not a general-purpose mobile API endpoint.
- Review credential storage: this upstream widget writes its API key and custom
  headers into the protected App Group config file, readable after first unlock.
  Prefer shared Keychain storage before adding real credentials.
- Test logout, key/server changes, failed refresh, stale data and privacy mode.
  Widget refresh frequency is ultimately controlled by iOS.

## Flexible spending widget

Add the medium Home Screen or rectangular Lock Screen **Flexible spending**
widget. In Edit Widget, choose **Remaining budget**, **Weekly guide**, or
**Spending steer**. Add several copies with different views to compare.
Enable **Show financial details** explicitly; it is off by default.

Select one category plus up to four additional flexible categories from the same
current budget and currency. Duplicates, inherited/shared child budgets and
parent/child combinations fail closed. Fixed bills and planned lumpy purchases
are not suitable: the user chooses which categories are flexible. At month end,
select the new month's categories explicitly; the widget never silently switches
owners or budget months.

The widget reads each selected category's **detail** endpoint, because the index
omits derived actuals. It sums the integer minor-unit `available_to_spend_cents`
amounts, including rollover, and formats the result in their shared currency.
A positive monthly allocation or positive rollover counts as a configured
budget. Negative rollover does not hide overspending against a positive
allocation. Zero remaining means the budget is used; negative means over budget.
Near the limit is not called over budget. No cash forecast or raw Insight is shown.

- **Remaining budget** shows the pool's remaining or over-budget amount.
- **Weekly guide** divides remaining budget across the inclusive calendar days
  to reset. In the final partial week it shows the total for those remaining
  days, not a seven-day amount. This recalculates as spending arrives; it is not
  a fixed weekly envelope.
- **Spending steer** optionally compares that rate with the **period-to-date
  average** after at least seven calendar days. It does not claim recent 14-day
  history. Enable **Estimate from period average** to try it; otherwise it falls
  back to the weekly guide. Only a reduction above both 10% of the sustainable
  weekly rate and five major currency units produces an “Ease off” warning.
  A smaller positive reduction says “Around plan”; zero says “Within plan”.
  Missing/negative actuals suppress the comparison. Exhausted budgets show
  pause/review, never negative daily allowances. Approximate rates use whole
  currency units with the correct currency exponent (for example JPY vs KWD).

All views use retrieved budget records, not a bank-sync completeness guarantee.
If recent transactions are delayed or miscategorised, disable the pace estimate
and use remaining budget with caution. The API has no reliable per-category
feed-completeness signal; no automatic completeness claim is made. No transaction
queries or background snapshot service were added.

“Fetched” is only the API retrieval time: bank updates may lag. Failed requests
show unavailable rather than cached guidance. Timeline guidance expires after
six hours or at the next local midnight, whichever comes first. iOS controls
refresh and rendering; these are not real-time banking alerts. Detail responses
must match the selected category and budget and the current session generation.
Logout reloads all widget timelines. All displayed details are privacy-sensitive.
The new widget uses no separate financial disk cache and refuses HTTP redirects
so the API key is not forwarded to a different endpoint.

The chooser deliberately fails rather than silently truncating a response with
more than 100 budgets or categories. Matching category/month labels across owners
are omitted because the API does not label the owner; if every choice is
ambiguous, selection reports an error. The widget will not guess household
versus personal budget. API permissions, unavailable preview/server
features, and missing categories can prevent selection. The category API may
recompute persisted derived rollovers on reads, matching the existing web page;
it does not edit allocations. Credentials remain subject to the App Group
storage limitation above, so live use still awaits that privacy hardening.

Native model/result-gate checks (synthetic data only):

```sh
xcrun swiftc -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path /tmp/sure-widget-swift-cache \
  ios/SureWidget/FlexibleSpendingModel.swift \
  test/native/FlexibleSpendingTests.swift \
  -o /tmp/sure-flexible-spending-tests
/tmp/sure-flexible-spending-tests
```

These cover near/zero/over-budget, rollover-only and negative-carry funding,
missing fields, stale/future timestamps, expired/uninitialized periods,
AUD/JPY/KWD formatting, pooled-category validation, daylight-saving dates,
partial weeks, missing/negative actuals, materiality boundaries, hidden details,
missing responses, selection mismatch and session invalidation. They are not an end-to-end network
or WidgetKit lifecycle test. Live category discovery, system privacy redaction,
logout rendering and month transition still need signed-device testing.


## Separate follow-ups

Shared Keychain storage and signed-device privacy/lifecycle validation remain
before live credential use. Upstream #4489 (bulk budget actuals and uncategorized
totals) and #4705 (browser notifications) are candidates for separate review, not
included in this integration. Each changes backend behavior and needs independent
validation before deployment. Sure Insights currently needs contextual filtering
and wording fixes before it is suitable for direct widget presentation.
