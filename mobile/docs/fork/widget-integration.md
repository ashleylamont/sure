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

## Signing and validation notes

- Configure a personal signing team, bundle IDs and shared App Group for both
  Runner and SureWidget. The upstream signing values are not portable credentials.
- Keep the server private and TLS verification enabled. The OpenAI MCP tunnel is
  not a general-purpose mobile API endpoint.
- Runner and SureWidget must share the same explicit Keychain access group in
  their entitlements and `SureWidgetKeychainGroup` Info.plist setting. The default
  is `$(AppIdentifierPrefix)$(SURE_WIDGET_KEYCHAIN_GROUP)`; personal re-signing must
  preserve a matching provisioned group in both targets. Project-level defaults
  are `SURE_BUNDLE_IDENTIFIER=am.sure.mobile`,
  `SURE_APP_GROUP=group.$(SURE_BUNDLE_IDENTIFIER)` and
  `SURE_WIDGET_KEYCHAIN_GROUP=$(SURE_BUNDLE_IDENTIFIER).widget`. Override the base
  bundle ID and `DEVELOPMENT_TEAM` for a personal build; both target IDs, App Group
  and Keychain group follow together. Use explicit group overrides if an existing
  provisioned group uses different names. A Personal Team may lack App Groups;
  verify provisioning rather than removing required entitlements. Missing/mismatched entitlements
  fail closed, rather than falling back to a plaintext config.
- Test logout, key/server changes, failed refresh, stale data and privacy mode.
  Widget refresh frequency is ultimately controlled by iOS.

## Three glanceable widgets

- **Account Balances** keeps the existing balance view and its meaningful balance
  options.
- **Budget Remaining** shows one authoritative remaining/over-budget amount,
  scope, used bar and period end.
- **Budget Pace** is a speedometer against a straight-line spending reference:
  100% means spending exactly at an even pace through the period. The medium view
  adds projected period-end spending and the budget envelope. It does not tell
  the user to cut back merely because rent or another lumpy expense posted early.

The budget widgets have two meaningful controls: **Budget** defaults to the
unambiguous current budget; optional **Areas** selects any combination of budget
categories. Leave Areas empty for the whole budget. A parent includes its
subcategories, so overlapping parent/child choices are counted once, not added
together twice. Every chosen area must resolve in the same current budget and
currency; incomplete or ambiguous selections never silently become partial sums.
Stable category identities follow new periods. An explicitly selected period
budget must be reselected after it ends. Old single-category configurations ask
for reselection instead of silently switching to the whole budget.
There are no view, estimate-enable or show-details switches. System
privacy-sensitive rendering remains enabled, consistent with balances.

The implementation provides square `systemSmall`, wider `systemMedium`, and
rectangular plus one-slot `accessoryCircular` Lock Screen layouts. The circular
Lock Screen family is the clarified tiny footprint; it is not a single-icon Home
Screen widget. Balances also support the circular Lock Screen family, showing
configured net worth when available or the first account from the existing list.

The budget list omits actuals, so the provider reads the selected budget/category
**detail** endpoint. Whole-budget remaining uses `available_to_spend_cents`;
category remaining preserves rollover. The category's effective envelope is
actual spending plus remaining. Pace is:

```
spent / (envelope × elapsed inclusive calendar days / total inclusive days)
```

Dates use Gregorian civil days in the current timezone, not fixed 24-hour periods.
The projection is a linear reference, not a prediction of bill timing or cash
availability. Early periods are labelled estimates. Missing values and expired periods show a useful unavailable state. Nonpositive
envelopes and negative net spending suppress the Pace calculation, while the
Remaining widget still shows the authoritative amount for explicit zero budgets
or refunds. Zero/negative remaining is represented as used/over budget, without
negative progress. Currency formatting handles minor
unit exponents rather than assuming every currency uses cents.

A refresh failure does not reuse an old spending signal. Retrieval expires at
six hours or local midnight; iOS controls actual refresh timing. Bank transaction
feeds may lag even when a widget fetch is recent. Credential/generation checks
prevent old-account names and results from appearing after a login change.

Run the synthetic model tests from `mobile/`:

```sh
xcrun swiftc -parse-as-library ios/SureWidget/FlexibleSpendingModel.swift \
  test/native/FlexibleSpendingTests.swift -o /tmp/sure-budget-widget-tests
/tmp/sure-budget-widget-tests
```

Coverage includes DST/leap days, early and expired periods, zero/negative/missing
values, rollover, currency exponents, owner ambiguity and stable category
selection. Native component renders are not full WidgetKit/gallery lifecycle
validation. All redesign testing is simulator-only; the physical phone is not a
live testing target.

## Separate follow-ups

Shared-Keychain and privacy/lifecycle validation remain unverified. This is a
test-coverage limitation, not a known credential exposure. Upstream #4489 (bulk budget actuals and uncategorized
totals) and #4705 (browser notifications) are candidates for separate review, not
included in this integration. Each changes backend behavior and needs independent
validation before deployment. Sure Insights currently needs contextual filtering
and wording fixes before it is suitable for direct widget presentation.


## Widget credential storage

The complete widget connection configuration, including the API key and all
proxy headers, is stored in a single shared Keychain item. It uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, is not synchronizable, and
never requests an authentication prompt from a background refresh. Widget
refresh while locked is therefore possible after the first unlock since boot;
these credentials are not included in transferable Keychain backups.

Runner migrates an existing `sure-widget-config.json` on launch or configuration
update. A current-generation legacy item is saved and read back from Keychain
before the old file is removed. Locked/denied Keychain access and failed
verification preserve the legacy file for retry, but the widget never reads it
or falls back to it. An already-current secure item wins over legacy data; a
pre-logout file is removed without being reactivated. File-removal failure is
reported as unsuccessful migration. Deleting the file does not erase historic
backups or storage snapshots that may have contained older versions.

Connection changes still persist generation invalidation before storing the new
identity. Logout invalidates the generation and deletes the Keychain item and
shared financial files; deletion failure is reported for retry. Snapshot reads,
saves, result acceptance, category suggestions and rendered entries also require
a current readable Keychain config, not just a matching generation file. Thus a
failed generation-file write cannot revive old data after credential deletion.
If both invalidation and credential deletion fail, clear reports failure and must
be retried. WidgetKit may retain an already-rendered image until its reload. Account, net
worth and flexible-spending API requests refuse redirects so API keys/proxy
headers are not forwarded to another endpoint. No app login/refresh tokens are
shared with the widget.

Synthetic migration checks (no real Keychain items or credentials):

```sh
xcrun swiftc -target arm64-apple-macosx15.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path /tmp/sure-widget-swift-cache \
  ios/Runner/WidgetCredentialStore.swift \
  test/native/WidgetCredentialMigrationTests.swift \
  -o /tmp/sure-widget-credential-tests
/tmp/sure-widget-credential-tests
```

These exercise key/header preservation, verification failure, locked versus
missing storage, failed cleanup, retries, stale generations and an existing
secure identity. The unsigned simulator compile does not prove provisioned
cross-process Keychain access. Verify store/read/logout/first-unlock behavior
with synthetic credentials on the signed app and widget before live use.

Additional synthetic/static regressions (run from `mobile`):

```sh
python3 test/native/widget_credential_entitlements_test.py
python3 test/native/widget_logout_gate_test.py
```

The logout test compiles the real store with a temporary directory and synthetic
Keychain dependency, including missing/locked/malformed credentials while the
generation file remains unchanged. It is not a real SecItem test. An isolated
ad-hoc two-app simulator SecItem probe on 2026-11-12 installed successfully but
was blocked at launch by simulator security policy, before any storage check;
therefore real signed app/extension storage sharing remains unverified.

## Physical-device startup validation (2026-11-12)

A signed Debug install exposed an iOS 27.2 launch crash in
`UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`. Runner now uses
Flutter 3.44's UIScene manifest and `FlutterSceneDelegate`, with plugin and custom
widget-channel registration in `didInitializeImplicitFlutterEngine`. The channel
still uses that engine's registrar messenger; credential migration remains in
application startup and retries on widget configuration updates. Check the wiring
with `python3 test/native/widget_scene_lifecycle_test.py` from `mobile/`.

A signed Release build with local bundle/team overrides compiled, installed, and
visibly reached the Configuration screen on a physical iPhone running iOS 27.2.
Use Release for standalone phone use rather than relying on debug/JIT tooling.
Both app and extension signatures/profiles were valid with matching App Groups
and private-first/shared-second Keychain access groups. Personal Team profiles
expire after seven days and require re-signing/reinstallation. No live credentials
were entered during this validation; cross-process credential storage, real
widget refresh and locked-device/logout behavior still need acceptance testing.

The final full Rails rerun was interrupted to reduce laptop load; its temporary
app, Redis and PostgreSQL containers were stopped without deleting volumes. This
is not a passing full-suite result. Native regression checks, Flutter's 320 tests,
analysis (informational notices only), and Ruby/ERB/Biome/Brakeman gates passed.

## Redesign validation

Fresh synthetic native component captures grounded the redesign: the previous
weekly/steer view was dense and its primary number did not match the intervention
being suggested. The replacement gives each gallery entry one task and one main
signal. Native captures cover small, medium and Lock Screen layouts, not the full
WidgetKit gallery or refresh lifecycle. Fixed widget typography is constrained
to fit; semantic accessibility labels retain the full amounts and meanings.

Remote backend verification: run 43149947064 passed the full unit/integration,
encryption and system tests plus CI static gates on published commit 5746167e.
All subsequent changes are native/mobile files and mobile build workflows, so the tested Rails code
and CI workflow are unchanged. No Docker tests need to run on the laptop for
these native-only changes.

The final native model suite and unsigned arm64 simulator build pass. Synthetic
component QA inspected normal, over-budget, missing, stale, old-generation,
refund/zero and long-label/large-value fixtures in the supported sizes, including
light/dark. A native Capsule progress bar replaced a platform progress control
that could not be captured reliably. The redesigned binary has not been installed
on or live-tested on the physical phone. Existing flexible-spending widgets may
need removing/re-adding because the AppIntent configuration has been simplified.


## Compact text and multiple areas

Circular Pace uses the literal short label “pace”, not a truncated budget/month
name. Larger layouts summarize long scopes as “3 areas”; full scope is retained
for accessibility. Compact monetary figures explicitly use approximation and
short suffixes; negative balances preserve their sign and ISO currency remains
visible when the usual symbol will not fit. Numeric net-worth metadata comes
from the API, never from parsing locale-formatted text. Formatted-only updates
clear old numeric metadata so the tiny and full views cannot disagree.

Flutter CI and app minimum now use 3.44.4, matching the validated toolchain and
UIScene APIs. The old 3.32.4 CI pin could not compile FlutterImplicitEngineDelegate
or FlutterSceneDelegate. This updates mobile build/test workflows only, not Rails
sources or the backend CI workflow.

Both iOS CI jobs disable Flutter Swift Package Manager via the supported
`FLUTTER_SWIFT_PACKAGE_MANAGER=false` environment override, matching local builds.
This preserves CocoaPods and avoids automatic partial migration/mixed Sentry
dependency resolution. No global developer Flutter configuration is changed.
