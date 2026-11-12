import Foundation

@main
struct FlexibleSpendingTests {
    static func main() throws {
        let now = Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let budget = SpendingBudget(id: "budget", name: "Monthly", startDate: today, endDate: today, initialized: true)
        func signal(_ cents: Int?, allocation: Int? = 10000, carry: Int? = 0, currency: String = "AUD", formatted: String? = "AU$50.00", inherited: Bool = false, fetched: Date? = nil, period: SpendingBudget? = nil) -> FlexibleSpendingSignal {
            FlexibleSpendingSignal(category: SpendingCategory(id: "category", budgetID: "budget", currency: currency,
                category: .init(id: "category-id", name: "Flexible"), available: formatted, availableCents: cents,
                budgetedCents: allocation, rolloverCents: carry, inheritsParent: inherited), budget: period ?? budget, fetchedAt: fetched ?? now)
        }
        precondition(signal(5000).message(at: now) == "Left in this category’s budget")
        precondition(signal(1).message(at: now) == "Left in this category’s budget", "Near limit is not over budget")
        precondition(signal(0).message(at: now) == "Budget used · pause extras")
        precondition(signal(-1).message(at: now) == "Over budget · pause extras")
        for bad in [signal(nil), signal(1, allocation: nil), signal(1, allocation: 0), signal(1, carry: nil), signal(1, formatted: nil), signal(1, inherited: true)] {
            precondition(bad.amount(at: now) == nil)
        }
        precondition(signal(-500, allocation: 1000, carry: -1500).message(at: now) == "Over budget · pause extras", "Negative carry does not erase a configured budget")
        precondition(signal(1000, allocation: 0, carry: 2000).amount(at: now) != nil, "Rollover-only envelope is funded")
        precondition(signal(-1, allocation: 0).message(at: now) == "Set a category budget first")
        for seconds in [-21600.0, 61.0] {
            let stale = signal(100, fetched: now.addingTimeInterval(seconds))
            precondition(stale.amount(at: now) == nil)
            precondition(stale.message(at: now) == "Open Sure to check newer spending")
        }
        for date in ["2000-01-01", "2100-01-01"] {
            let other = SpendingBudget(id: "budget", name: "Other", startDate: date, endDate: date, initialized: true)
            precondition(signal(100, period: other).amount(at: now) == nil)
        }
        let uninitialized = SpendingBudget(id: "budget", name: "Draft", startDate: today, endDate: today, initialized: false)
        precondition(signal(100, period: uninitialized).amount(at: now) == nil)
        for (currency, amount) in [("AUD", "AU$50.00"), ("JPY", "¥500"), ("KWD", "KWD 1.234")] {
            precondition(signal(100, currency: currency, formatted: amount).amount(at: now) == amount, "Never reinterpret currency minor units")
        }
        let json = #"{"id":"category","budget_id":"budget","currency":"AUD","category":{"id":"category-id","name":"Flexible"},"available_to_spend":"AU$1.00","available_to_spend_cents":100,"display_budgeted_spending_cents":0,"rolled_over_amount_cents":100,"inherits_parent_budget":false}"#
        let decoded = try JSONDecoder().decode(SpendingCategory.self, from: Data(json.utf8))
        precondition(decoded.availableCents == 100 && decoded.rolloverCents == 100)
        let category = signal(100).category
        func accepted(_ c: SpendingCategory? = nil, _ b: SpendingBudget? = nil, selected: String = "category", current: Int = 7, shown: Bool = true) -> FlexibleSpendingSignal? {
            FlexibleSpendingResult.accept(category: c, budget: b, selectedID: selected, startedGeneration: 7,
                currentGeneration: current, showDetails: shown, fetchedAt: now)
        }
        precondition(accepted(category, budget) != nil)
        precondition(accepted(category, budget, current: 8) == nil, "Logout or login switch drops in-flight response")
        precondition(accepted(category, budget, shown: false) == nil, "Hidden details cannot produce guidance")
        precondition(accepted(category, budget, selected: "removed-category") == nil)
        precondition(accepted(nil, budget) == nil, "Failed/missing category response never uses cached guidance")
        precondition(accepted(category, nil) == nil, "Failed/missing budget response never uses cached guidance")
        let mismatched = SpendingBudget(id: "another-owner-budget", name: "Other", startDate: today, endDate: today, initialized: true)
        precondition(accepted(category, mismatched) == nil)
        precondition(FlexibleCategoryLabels.unambiguous(["Fun · May", "Fun · May", "Groceries · May"]) == ["Groceries · May"])
        precondition(FlexibleCategoryLabels.unambiguous(["Fun · May", "Fun · May"]).isEmpty)
        precondition(FlexibleCategoryLabels.unambiguous([]).isEmpty)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        func day(_ text: String) -> Date {
            let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
            f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.date(from: text)!
        }
        let check = day("2026-10-15 12:00")
        let month = SpendingBudget(id: "budget", name: "October", startDate: "2026-10-01", endDate: "2026-10-31", initialized: true)
        func pooled(_ id: String = "a", remaining: Int = 17000, spent: Int? = 30000, currency: String = "AUD", parent: String? = nil, period: SpendingBudget? = nil) -> FlexibleSpendingSignal {
            // Category is immutable on the response, so construct with explicit ancestry.
            let category = SpendingCategory(id: id, budgetID: "budget", currency: currency,
                category: .init(id: id, name: id, parentID: parent), available: "formatted", availableCents: remaining,
                budgetedCents: 47000, rolloverCents: 0, inheritsParent: false, actualCents: spent)
            return FlexibleSpendingSignal(category: category, budget: period ?? month, fetchedAt: check)
        }
        let pool = SpendingPool(signals: [pooled()])
        precondition(pool.valid(at: check))
        precondition(pool.days(at: check, calendar: cal)?.elapsed == 15, "DST uses civil days")
        precondition(pool.days(at: check, calendar: cal)?.remaining == 17)
        precondition(pool.weeklyGuide(at: check) == 7000)
        precondition(pool.periodWeeklyAverage(at: check) == 14000)
        precondition(pool.suggestedReduction(at: check) == 7000)
        precondition(SpendingPool(signals: [pooled(), pooled("b")]).remaining(at: check) == 34000)
        precondition(!SpendingPool(signals: [pooled(), pooled()]).valid(at: check))
        precondition(!SpendingPool(signals: [pooled(), pooled("b", parent: "a")]).valid(at: check))
        precondition(!SpendingPool(signals: [pooled(), pooled("b", currency: "JPY")]).valid(at: check))
        precondition(!SpendingPool(signals: []).valid(at: check))
        precondition(!SpendingPool(signals: (0..<6).map { pooled(String($0)) }).valid(at: check))
        for left in [0, -100] {
            let used = SpendingPool(signals: [pooled(remaining: left)])
            precondition(used.weeklyGuide(at: check) == nil && used.suggestedReduction(at: check) == nil)
        }
        for actual in [nil, -100] as [Int?] {
            precondition(SpendingPool(signals: [pooled(spent: actual)]).periodWeeklyAverage(at: check) == nil)
        }
        let firstWeek = SpendingBudget(id: "budget", name: "Short", startDate: "2026-10-10", endDate: "2026-10-17", initialized: true)
        let short = SpendingPool(signals: [pooled(period: firstWeek)])
        precondition(short.weeklyGuide(at: check) == 17000, "Final three-day amount is not labelled per week")
        precondition(short.periodWeeklyAverage(at: check) == nil, "Wait seven days for estimate")
        precondition(pool.pacePosition(at: check) == .easeOff)
        precondition(SpendingPool(signals: [pooled(spent: 15001)]).pacePosition(at: check) == .aroundPlan)
        precondition(SpendingPool(signals: [pooled(spent: 15000)]).pacePosition(at: check) == .withinPlan)
        precondition(SpendingPool(signals: [pooled(spent: nil)]).pacePosition(at: check) == nil)
        precondition(pool.needsCutback(at: check))
        // Sustainable 7000/week: 10% threshold = 700 minor units; compare boundary.
        precondition(!SpendingPool(signals: [pooled(spent: 16500)]).needsCutback(at: check))
        precondition(SpendingPool(signals: [pooled(spent: 16501)]).needsCutback(at: check))
        precondition(!SpendingPool(signals: [pooled(spent: 15001)]).needsCutback(at: check))
        precondition(!SpendingPool(signals: [pooled(spent: 0)]).needsCutback(at: check))
        // Small budgets use a five-major-unit floor rather than sub-unit nudges.
        precondition(!SpendingPool(signals: [pooled(remaining: 1700, spent: 2571)]).needsCutback(at: check))
        precondition(SpendingPool(signals: [pooled(remaining: 1700, spent: 2572)]).needsCutback(at: check))
        for (code, minor, expected) in [("AUD", 1234, 12.34), ("JPY", 1234, 1234.0), ("KWD", 1234, 1.234)] {
            let value = SpendingPool(signals: [pooled(currency: code)]).format(Decimal(minor))!
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = code
            precondition(abs(f.number(from: value)!.doubleValue - expected) < 0.00001, "Currency minor units: \(code): \(value)")
        }
        precondition(SpendingPool(signals: [pooled(currency: "XYZ")]).format(1) == nil)
        print("Flexible spending model and result-gate regression checks passed")
    }
}
