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
`flutter analyze --no-fatal-infos`. Full iOS build and simulator/device lifecycle
checks remain necessary; the standalone Swift check does not replace them.

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
