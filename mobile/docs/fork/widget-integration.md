# Fork widget integration

This integration layers upstream PR [#4679](https://github.com/we-promise/sure/pull/4679)
(commit `f459b7798a6c1655f79de01f262e2b6f7b733026`) onto the fork's upstream sync.
It is experimental and separate from `main`. The current widget displays account
balances and net worth, not a spending recommendation or budget pace.

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

## Small follow-ups to evaluate

A budget-progress widget can reuse existing budget detail/category endpoints and
Sure Insights rather than introducing another ledger or prediction engine. Pick
explicit flexible categories, preserve server-calculated amounts and currency,
show freshness, and avoid treating fixed bills or lumpy purchases as linear daily
spending. Label remaining budget accurately; it is not cash safe to spend.

Upstream candidates worth reviewing separately include #4489 (bulk budget actuals
and uncategorized totals) and #4705 (browser notifications). They are not included
in this widget integration; each changes backend behavior and needs independent
validation before deployment.
