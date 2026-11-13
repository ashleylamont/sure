import Foundation

@main
struct FlexibleSpendingTests {
    static func main() throws {
        let zone = TimeZone(identifier: "Australia/Sydney")!
        func date(_ value: String) -> Date {
            let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.date(from: value)!
        }
        let now = date("2026-10-15 12:00")
        func budget(id: String = "budget", start: String = "2026-10-01", end: String = "2026-10-30",
                    allocated: Int? = 100000, actual: Int? = 60000, available: Int? = 40000,
                    currency: String? = "AUD", initialized: Bool = true) -> SpendingBudget {
            SpendingBudget(id: id, name: "October", startDate: start, endDate: end, initialized: initialized,
                currency: currency, budgetedCents: allocated, actualCents: actual, availableCents: available)
        }
        func snapshot(_ b: SpendingBudget? = nil, fetched: Date? = nil) -> BudgetSnapshot? {
            BudgetSnapshot(budget: b ?? budget(), fetchedAt: fetched ?? now)
        }
        let normal = snapshot()!
        precondition(normal.problem(at: now) == nil)
        precondition(normal.pace(at: now, timeZone: zone) == Decimal(string: "1.2"))
        precondition(normal.projection(at: now) == 120000)
        precondition(normal.usedFraction(at: now) == 0.6)
        precondition(normal.remainingLabel == "remaining")
        precondition(normal.paceLabel(at: now) == "Above even pace")
        precondition(snapshot(budget(actual: 50000))!.pace(at: now, timeZone: zone) == 1)
        precondition(snapshot(budget(actual: 0))!.pace(at: now, timeZone: zone) == 0)
        precondition(snapshot(budget(actual: 0))!.paceLabel(at: now) == "Below even pace")
        let over = snapshot(budget(actual: 120000, available: -20000))!
        precondition(over.remainingLabel == "over budget")
        precondition(!over.remainingText.contains("-"))
        precondition(over.usedFraction(at: now) == 1)
        for bad in [budget(start: "2026-10-16"), budget(end: "2026-10-14"),
                    budget(start: "2026-10-32"), budget(initialized: false)] {
            precondition(snapshot(bad)!.problem(at: now) != nil)
            precondition(snapshot(bad)!.pace(at: now, timeZone: zone) == nil)
        }
        for factual in [budget(allocated: 0, actual: 1000, available: -1000),
                        budget(allocated: -1), budget(actual: -1000, available: 101000)] {
            let value = snapshot(factual)!
            precondition(value.problem(at: now) == nil, "Remaining stays factual with zero budget or refunds")
            precondition(value.usedFraction(at: now) == nil, "No progress with invalid denominator or refund net")
            precondition(value.paceProblem(at: now) != nil)
            precondition(value.pace(at: now) == nil)
        }
        for bad in [budget(allocated: nil), budget(actual: nil), budget(available: nil), budget(currency: nil), budget(currency: "XYZ")] {
            precondition(snapshot(bad) == nil)
        }
        precondition(snapshot(fetched: now.addingTimeInterval(-21600))!.problem(at: now) != nil)
        precondition(snapshot(fetched: now.addingTimeInterval(61))!.problem(at: now) != nil)
        precondition(snapshot(fetched: now.addingTimeInterval(-21599))!.problem(at: now) == nil)
        precondition(budget().days(at: now, timeZone: zone)?.elapsed == 15)
        precondition(budget().days(at: now, timeZone: zone)?.total == 30)
        precondition(BudgetDays(start: "2024-02-01", end: "2024-02-29", now: date("2024-02-29 12:00"), timeZone: zone)?.total == 29)
        precondition(BudgetDays(start: "2026-10-04", end: "2026-10-04", now: date("2026-10-04 12:00"), timeZone: zone)?.total == 1)
        precondition(BudgetDays(start: "2026-10-01", end: "2026-10-30", now: date("2026-10-01 00:01"), timeZone: zone)?.early == true)
        precondition(BudgetDays(start: "2026-10-01", end: "2026-10-30", now: date("2026-10-07 12:00"), timeZone: zone)?.early == false)
        precondition(BudgetDays(start: "2026-02-30", end: "2026-03-30", now: date("2026-03-15 12:00"), timeZone: zone) == nil)

        func category(id: String = "row", stableID: String = "category", owner: String = "budget", inherited: Bool = false,
                      actual: Int? = 60000, remaining: Int? = 90000) -> SpendingCategory {
            SpendingCategory(id: id, budgetID: owner, currency: "AUD", category: .init(id: stableID, name: "Fun"),
                availableCents: remaining, actualCents: actual, inheritsParent: inherited)
        }
        let rollover = BudgetSnapshot(budget: budget(), category: category(), fetchedAt: now)!
        precondition(rollover.envelope == 150000, "Use actual plus remaining, preserving category rollover")
        precondition(rollover.pace(at: now, timeZone: zone) == Decimal(string: "0.8"))
        precondition(BudgetSnapshot(budget: budget(), category: category(inherited: true), fetchedAt: now) == nil)
        precondition(BudgetSnapshot(budget: budget(), category: category(owner: "other"), fetchedAt: now) == nil)
        precondition(BudgetSnapshot(budget: budget(), category: category(actual: nil), fetchedAt: now) == nil)
        precondition(BudgetSnapshot(budget: budget(), category: category(remaining: nil), fetchedAt: now) == nil)
        for (code, expected) in [("AUD", 12.34), ("JPY", 1234.0), ("KWD", 1.234)] {
            let s = snapshot(budget(currency: code))!
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = code
            precondition(abs(f.number(from: s.formatted(1234))!.doubleValue - expected) < 0.00001)
        }
        // Default/current selection follows months only when the owner is unambiguous.
        precondition(BudgetSelection.currentBudget([budget()], track: .automatic, at: now)?.id == "budget")
        precondition(BudgetSelection.currentBudget([budget(), budget(id: "other")], track: .automatic, at: now) == nil)
        precondition(BudgetSelection.currentBudget([budget(), budget(id: "other")], track: .category("category"), at: now) == nil)
        precondition(BudgetSelection.currentBudget([budget(), budget(id: "other")], track: .budget("other"), at: now)?.id == "other")
        precondition(BudgetSelection.currentBudget([budget(end: "2026-10-14")], track: .automatic, at: now) == nil)
        precondition(BudgetSelection.category([category(id: "new-month-row")], stableID: "category", budgetID: "budget")?.id == "new-month-row")
        precondition(BudgetSelection.category([category(), category(id: "duplicate")], stableID: "category", budgetID: "budget") == nil)
        precondition(BudgetSelection.category([category(inherited: true)], stableID: "category", budgetID: "budget") == nil)
        precondition(BudgetSelection.unambiguousLabels(["November", "November", "Personal"]) == ["Personal"])
        precondition(BudgetTrack(id: nil) == .automatic)
        precondition(BudgetTrack(id: "current") == .automatic)
        precondition(BudgetTrack(id: "budget:../secret") == nil)
        precondition(BudgetTrack(id: "category:00000000-0000-0000-0000-000000000001") == .category("00000000-0000-0000-0000-000000000001"))
        let index = #"{"id":"budget","name":"October","start_date":"2026-10-01","end_date":"2026-10-30","initialized":true,"currency":"AUD","budgeted_spending_cents":100000}"#
        let decoded = try JSONDecoder().decode(SpendingBudget.self, from: Data(index.utf8))
        precondition(BudgetSnapshot(budget: decoded, fetchedAt: now) == nil, "Index cannot masquerade as detail")
        func area(_ id: String, name: String? = nil, parent: String? = nil, budgetID: String = "budget", currency: String = "AUD", spent: Int? = 1000, left: Int? = 2000, inherited: Bool = false) -> SpendingCategory {
            SpendingCategory(id: "row-" + id, budgetID: budgetID, currency: currency,
                category: .init(id: id, name: name ?? id, parentID: parent), availableCents: left,
                actualCents: spent, inheritsParent: inherited)
        }
        let hierarchy = [area("parent", spent: 3000, left: 4000), area("child", parent: "parent"), area("grandchild", parent: "child"), area("other")]
        let coalesced = BudgetSelection.areas(hierarchy, selectedIDs: ["parent", "child", "grandchild", "parent"], budgetID: "budget")!
        precondition(coalesced.map { $0.category.id } == ["parent"], "Parent includes descendants once; duplicates coalesce")
        let pooled = BudgetSnapshot(budget: budget(), categories: hierarchy, selectedIDs: ["parent", "child", "other"], fetchedAt: now)!
        precondition(pooled.spent == 4000 && pooled.remaining == 6000 && pooled.envelope == 10000)
        precondition(BudgetSelection.areas(hierarchy, selectedIDs: ["parent", "missing"], budgetID: "budget") == nil)
        precondition(BudgetSelection.areas([area("a", parent: "absent"), area("b")], selectedIDs: ["a", "b"], budgetID: "budget") == nil)
        precondition(BudgetSelection.areas([area("a", parent: "b"), area("b", parent: "a")], selectedIDs: ["a", "b"], budgetID: "budget") == nil)
        precondition(BudgetSelection.areas([area("a"), area("b", currency: "JPY")], selectedIDs: ["a", "b"], budgetID: "budget") == nil)
        precondition(BudgetSelection.areas([area("a"), area("b", budgetID: "other")], selectedIDs: ["a", "b"], budgetID: "budget") == nil)
        precondition(BudgetSnapshot(budget: budget(), categories: [area("a"), area("b", spent: nil)], selectedIDs: ["a", "b"], fetchedAt: now) == nil)
        precondition(BudgetSnapshot(budget: budget(), categories: [area("a"), area("b", left: nil)], selectedIDs: ["a", "b"], fetchedAt: now) == nil)
        precondition(BudgetSelection.areas([area("a"), area("b", parent: "a", inherited: true)], selectedIDs: ["a", "b"], budgetID: "budget")?.count == 1)
        precondition(BudgetSelection.areas([area("a"), area("b", parent: "a", inherited: true)], selectedIDs: ["b"], budgetID: "budget") == nil)
        let longScope = BudgetSnapshot(budget: budget(), categories: [area("a", name: "Very long groceries and personal care"), area("b", name: "Other very long discretionary spending")], selectedIDs: ["a", "b"], fetchedAt: now)!
        precondition(longScope.displayScope == "2 areas" && longScope.scope.contains("Very long"))
        let monthlyRow = area("stable", budgetID: "new-budget")
        precondition(BudgetSelection.areas([monthlyRow], selectedIDs: ["stable"], budgetID: "new-budget")?.first?.id == monthlyRow.id)
        for code in ["AUD", "JPY", "KWD", "CHF"] {
            precondition(CompactWidgetMoney.format(minorUnits: -123456, currency: code).contains("−"))
            precondition(CompactWidgetMoney.format(minorUnits: 123456, currency: code).contains("≈"))
            precondition(!CompactWidgetMoney.format(minorUnits: Decimal(Int.max), currency: code).contains("…"))
        }
        precondition(CompactWidgetMoney.format(minorUnits: 99999900, currency: "AUD").contains("1M"), "Promote 1000k rounding")
        precondition(CompactWidgetMoney.format(minorUnits: 1, currency: "AUD").contains("<"))
        precondition(CompactWidgetMoney.format(minorUnits: 12345600000, currency: "AUD").contains("123M"), "Large circles use whole scaled units")
        precondition(CompactWidgetMoney.format(minorUnits: 99950000, currency: "AUD").contains("1M"), "Promote whole-number suffix rounding")
        precondition(!over.compactRemainingText.contains("−"), "Over label already carries negative meaning")
        precondition(CompactWidgetMoney.format(minorUnits: 1234000, currency: "KWD").contains("1.2k"))
        precondition(CompactWidgetMoney.format(minorUnits: 1234, currency: "JPY").contains("1.2k"))
        let budgetID = "B8C564E1-E4AC-49AE-806D-08933A126152"
        let areaID = "C0F64214-CC7F-42FB-B8DD-7855CCAA3108"
        let link = BudgetPaceLink.make(budgetSelection: "budget:" + budgetID, areaIDs: [areaID, areaID])!
        let parts = URLComponents(url: link, resolvingAgainstBaseURL: false)!
        precondition(parts.scheme == "sureapp" && parts.host == "budget-pace")
        precondition(parts.queryItems?.filter { $0.name == "area" }.count == 1)
        precondition(BudgetPaceLink.make(budgetSelection: "../accounts", areaIDs: []) == nil)
        precondition(BudgetPaceLink.make(budgetSelection: "current", areaIDs: ["../credentials"]) == nil)
        let breakdown = BudgetBreakdown(snapshot: normal, areaNames: ["Example"])
        let payload = breakdown.payload(at: now)!
        precondition(payload["paceRatio"] as? Double == 1.2)
        precondition(payload["expected"] as? String == normal.formatted(normal.envelope / 2))
        precondition(payload["deviation"] as? String == normal.formatted(normal.spent - normal.envelope / 2))
        precondition(payload["areaNames"] as? [String] == ["Example"])
        precondition(breakdown.payload(at: now.addingTimeInterval(7 * 3600)) == nil)
        print("Budget Remaining/Pace math and selection regression checks passed")
    }
}
