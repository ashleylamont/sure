import Foundation

struct SpendingBudget: Decodable, Sendable {
    let id: String
    let name: String
    let startDate: String
    let endDate: String
    let initialized: Bool
    var currency: String? = nil
    var budgetedCents: Int? = nil
    var actualCents: Int? = nil
    var availableCents: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, initialized, currency
        case startDate = "start_date", endDate = "end_date"
        case budgetedCents = "budgeted_spending_cents"
        case actualCents = "actual_spending_cents"
        case availableCents = "available_to_spend_cents"
    }

    func days(at now: Date, timeZone: TimeZone = .current) -> BudgetDays? {
        guard initialized else { return nil }
        return BudgetDays(start: startDate, end: endDate, now: now, timeZone: timeZone)
    }
    func contains(_ date: Date) -> Bool { days(at: date) != nil }
}

struct SpendingCategory: Decodable, Sendable {
    struct Category: Decodable, Sendable {
        let id: String
        let name: String
    }
    let id: String
    let budgetID: String
    let currency: String
    let category: Category
    let availableCents: Int?
    let actualCents: Int?
    let inheritsParent: Bool
    enum CodingKeys: String, CodingKey {
        case id, currency, category
        case budgetID = "budget_id"
        case availableCents = "available_to_spend_cents"
        case actualCents = "actual_spending_cents"
        case inheritsParent = "inherits_parent_budget"
    }
}

/// API dates are Gregorian civil dates. Inclusive days avoid DST-hour artefacts.
struct BudgetDays: Sendable {
    let elapsed: Int
    let total: Int
    var early: Bool { elapsed < 7 }

    init?(start: String, end: String, now: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let first = formatter.date(from: start), let last = formatter.date(from: end),
              formatter.string(from: first) == start, formatter.string(from: last) == end,
              let length = calendar.dateComponents([.day], from: first, to: last).day,
              let passed = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: now)).day,
              length >= 0, passed >= 0, passed <= length else { return nil }
        elapsed = passed + 1
        total = length + 1
    }
}

enum BudgetTrack: Equatable {
    case automatic
    case budget(String)
    case category(String)

    init?(id: String?) {
        guard let id, id != "current" else { self = .automatic; return }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, UUID(uuidString: parts[1]) != nil else { return nil }
        switch parts[0] {
        case "budget": self = .budget(parts[1])
        case "category": self = .category(parts[1])
        default: return nil
        }
    }
}

enum BudgetSelection {
    static func currentBudget(_ budgets: [SpendingBudget], track: BudgetTrack, at now: Date) -> SpendingBudget? {
        let current = budgets.filter { $0.contains(now) }
        switch track {
        case .automatic, .category: return current.count == 1 ? current.first : nil
        case .budget(let id):
            let matches = current.filter { $0.id == id }
            return matches.count == 1 ? matches.first : nil
        }
    }
    static func category(_ categories: [SpendingCategory], stableID: String, budgetID: String) -> SpendingCategory? {
        let matches = categories.filter { $0.category.id == stableID && $0.budgetID == budgetID && !$0.inheritsParent }
        return matches.count == 1 ? matches.first : nil
    }
    static func unambiguousLabels(_ labels: [String]) -> Set<String> {
        Set(Dictionary(grouping: labels, by: { $0 }).filter { $0.value.count == 1 }.keys)
    }
}

struct BudgetSnapshot: Sendable {
    let scope: String
    let budget: SpendingBudget
    let currency: String
    let spent: Decimal
    let remaining: Decimal
    let envelope: Decimal
    let fetchedAt: Date

    init?(budget: SpendingBudget, category: SpendingCategory? = nil, fetchedAt: Date) {
        self.budget = budget
        self.fetchedAt = fetchedAt
        if let category {
            guard category.budgetID == budget.id, !category.inheritsParent,
                  let actual = category.actualCents, let available = category.availableCents else { return nil }
            scope = category.category.name
            currency = category.currency
            spent = Decimal(actual)
            remaining = Decimal(available)
            // Category detail includes own/child rollover in available. Summing
            // actual + available preserves that effective envelope exactly once.
            envelope = Decimal(actual) + Decimal(available)
        } else {
            guard let currency = budget.currency, let actual = budget.actualCents,
                  let available = budget.availableCents, let allocation = budget.budgetedCents else { return nil }
            self.currency = currency
            scope = budget.name
            spent = Decimal(actual)
            remaining = Decimal(available)
            envelope = Decimal(allocation)
        }
        guard Locale.commonISOCurrencyCodes.contains(currency) else { return nil }
    }

    func problem(at now: Date, timeZone: TimeZone = .current) -> String? {
        guard budget.days(at: now, timeZone: timeZone) != nil else { return "Choose a current budget" }
        let age = now.timeIntervalSince(fetchedAt)
        guard age >= -60, age < 6 * 60 * 60 else { return "Open Sure to refresh" }
        return nil
    }

    func paceProblem(at now: Date, timeZone: TimeZone = .current) -> String? {
        if let problem = problem(at: now, timeZone: timeZone) { return problem }
        guard envelope > 0 else { return "Set a budget amount in Sure" }
        guard spent >= 0 else { return "Check refunded spending in Sure" }
        return nil
    }

    func usedFraction(at now: Date) -> Double? {
        guard problem(at: now) == nil, envelope > 0, spent >= 0 else { return nil }
        return min(1, max(0, NSDecimalNumber(decimal: spent / envelope).doubleValue))
    }
    func pace(at now: Date, timeZone: TimeZone = .current) -> Decimal? {
        guard paceProblem(at: now, timeZone: timeZone) == nil,
              let days = budget.days(at: now, timeZone: timeZone) else { return nil }
        return spent * Decimal(days.total) / (envelope * Decimal(days.elapsed))
    }
    func projection(at now: Date) -> Decimal? {
        guard let pace = pace(at: now) else { return nil }
        return pace * envelope
    }
    func paceLabel(at now: Date) -> String {
        guard let pace = pace(at: now) else { return "Pace unavailable" }
        if pace > 1 { return "Above even pace" }
        if pace < 1 { return "Below even pace" }
        return "At even pace"
    }
    func formatted(_ minorUnits: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let major = minorUnits / pow(Decimal(10), formatter.maximumFractionDigits)
        return formatter.string(from: major as NSDecimalNumber) ?? "—"
    }
    var remainingText: String { formatted(remaining < 0 ? -remaining : remaining) }
    var remainingLabel: String { remaining < 0 ? "over budget" : "remaining" }
    var endLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: budget.endDate) else { return budget.endDate }
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}
