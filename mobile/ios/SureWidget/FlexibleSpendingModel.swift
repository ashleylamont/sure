import Foundation

struct SpendingBudget: Decodable, Sendable {
    let id: String
    let name: String
    let startDate: String
    let endDate: String
    let initialized: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, initialized
        case startDate = "start_date", endDate = "end_date"
    }
    func contains(_ date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        return initialized && startDate <= day && day <= endDate
    }
}

struct SpendingCategory: Decodable, Sendable {
    struct Category: Decodable, Sendable { let id: String; let name: String }
    let id: String
    let budgetID: String
    let currency: String
    let category: Category
    let available: String?
    let availableCents: Int?
    let budgetedCents: Int?
    let rolloverCents: Int?
    let inheritsParent: Bool
    enum CodingKeys: String, CodingKey {
        case id, currency, category
        case budgetID = "budget_id"
        case available = "available_to_spend", availableCents = "available_to_spend_cents"
        case budgetedCents = "display_budgeted_spending_cents"
        case rolloverCents = "rolled_over_amount_cents"
        case inheritsParent = "inherits_parent_budget"
    }
}

/// Budget headroom is not a cash forecast. Never extrapolate a daily pace from
/// fixed bills, lumpy purchases, or incompletely synced transactions.
struct FlexibleSpendingSignal: Sendable {
    let category: SpendingCategory
    let budget: SpendingBudget
    let fetchedAt: Date

    private var hasAllocation: Bool {
        guard let allocation = category.budgetedCents, let carry = category.rolloverCents else { return false }
        return allocation > 0 || carry > 0
    }

    func message(at now: Date) -> String {
        guard budget.contains(now) else { return "Choose this month’s category" }
        guard now.timeIntervalSince(fetchedAt) >= -60,
              now.timeIntervalSince(fetchedAt) < 6 * 60 * 60 else { return "Open Sure to check newer spending" }
        guard !category.inheritsParent, let amount = category.availableCents,
              category.available != nil, hasAllocation else { return "Set a category budget first" }
        if amount < 0 { return "Over budget · pause extras" }
        if amount == 0 { return "Budget used · pause extras" }
        return "Left in this category’s budget"
    }

    func amount(at now: Date) -> String? {
        guard budget.contains(now), now.timeIntervalSince(fetchedAt) >= -60,
              now.timeIntervalSince(fetchedAt) < 6 * 60 * 60,
              !category.inheritsParent, hasAllocation,
              category.availableCents != nil else { return nil }
        return category.available
    }
}

/// Shared result gate keeps an in-flight response from crossing login changes.
/// A nil response (including network failure) never falls back to old guidance.
enum FlexibleSpendingResult {
    static func accept(category: SpendingCategory?, budget: SpendingBudget?, selectedID: String,
                       startedGeneration: Int, currentGeneration: Int, showDetails: Bool,
                       fetchedAt: Date) -> FlexibleSpendingSignal? {
        guard showDetails, startedGeneration == currentGeneration,
              let category, let budget, category.id == selectedID,
              budget.id == category.budgetID else { return nil }
        return FlexibleSpendingSignal(category: category, budget: budget, fetchedAt: fetchedAt)
    }
}

/// The API has no owner label. Do not ask the user to guess between identical
/// household/personal budget labels or infer ownership from an opaque ID.
enum FlexibleCategoryLabels {
    static func unambiguous(_ labels: [String]) -> Set<String> {
        Set(Dictionary(grouping: labels, by: { $0 }).filter { $0.value.count == 1 }.keys)
    }
}
