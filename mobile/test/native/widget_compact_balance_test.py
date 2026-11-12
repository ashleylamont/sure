"""Exercise actual compact balance/model logic with synthetic values only."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
shared = (root / "ios/SureWidget/SureWidgetShared.swift").read_text()
accounts = (root / "ios/SureWidget/SureAccountsWidget.swift").read_text()
models = shared[shared.index("struct SureWidgetAccount:"):shared.index("// MARK: - App Group storage")]
money = shared[shared.index("struct SureWidgetMoney:"):shared.index("private struct BalanceSheetResponse:")]
helpers = accounts[accounts.index("extension AccountsEntry {"):accounts.index("// MARK: - Views")]
source = "import Foundation\n" + models + money + """
struct AccountsWidgetIntent { var showLiabilities = true; var showNetWorth = true }
struct AccountsEntry { let snapshot: SureWidgetSnapshot?; let configuration: AccountsWidgetIntent }
""" + helpers + r'''
@main struct Tests {
    static func main() throws {
        var existing: [String: Any] = ["netWorth": "old", "netWorthAmount": 100,
            "netWorthCurrency": "AUD", "accounts": "unchanged"]
        let netWorth = "$50.00"
        // NET_WORTH_MERGE
        precondition(existing["netWorth"] as? String == "$50.00")
        precondition(existing["netWorthAmount"] == nil && existing["netWorthCurrency"] == nil)
        precondition(existing["accounts"] as? String == "unchanged")
        let decoder = JSONDecoder()
        for raw in [#"{"amount":"1234.56","currency":"AUD","formatted":"$1,234.56"}"#,
                    #"{"amount":1234.56,"currency":"AUD","formatted":"$1,234.56"}"#] {
            let value = try decoder.decode(SureWidgetMoney.self, from: Data(raw.utf8))
            precondition(value.amount == Decimal(string: "1234.56"))
        }
        let legacy = try decoder.decode(SureWidgetSnapshot.self,
            from: Data(#"{"updatedAt":0,"accounts":[],"netWorth":"$123,456,789.00","generation":0}"#.utf8))
        precondition(legacy.netWorthAmount == nil && legacy.netWorthCurrency == nil)
        precondition(AccountsEntry(snapshot: legacy, configuration: .init()).circularAmount == "Open Sure")
        let debt = SureWidgetAccount(id: "a", name: "Long account name", balance: "-$1,234.56",
            balanceCents: -123456, currency: "AUD", classification: "liability")
        let saved = SureWidgetSnapshot(updatedAt: Date(), accounts: [debt], netWorth: "-$1,234.56", generation: 0,
            netWorthAmount: Decimal(string: "-1234.56"), netWorthCurrency: "AUD")
        let entry = AccountsEntry(snapshot: saved, configuration: .init())
        precondition(entry.circularAmount?.contains("-") == true || entry.circularAmount?.contains("−") == true)
        var config = AccountsWidgetIntent(); config.showNetWorth = false
        let accountEntry = AccountsEntry(snapshot: saved, configuration: config)
        precondition(accountEntry.circularAmount == entry.circularAmount)
        let francs = SureWidgetSnapshot(updatedAt: Date(), accounts: [], netWorth: "CHF400", generation: 0,
            netWorthAmount: 400, netWorthCurrency: "CHF")
        precondition(AccountsEntry(snapshot: francs, configuration: .init()).circularCurrencyLabel == "CHF")
        let extreme = SureWidgetAccount(id: "b", name: "Extreme", balance: "synthetic", balanceCents: Int.min,
            currency: "AUD", classification: "liability")
        let extremeEntry = AccountsEntry(snapshot: SureWidgetSnapshot(updatedAt: Date(), accounts: [debt, extreme]), configuration: config)
        precondition(extremeEntry.accounts.first?.id == "b")
        print("Compact balance metadata, signed values and legacy fallback checks passed")
    }
}
'''
bridge = (root / "ios/Runner/AppDelegate.swift").read_text()
merge = bridge[bridge.index('          existing["netWorth"] = netWorth'):]
merge = merge[:merge.index('          ok = write(existing, to: snapshotURL)')]
source = source.replace("// NET_WORTH_MERGE", merge)
with tempfile.TemporaryDirectory(prefix="sure-compact-balance-") as directory:
    directory = pathlib.Path(directory)
    swift = directory / "Test.swift"
    swift.write_text(source)
    binary = directory / "test"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(root / "ios/SureWidget/FlexibleSpendingModel.swift"), str(swift), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
