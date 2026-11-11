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
        print("Flexible spending model and result-gate regression checks passed")
    }
}
