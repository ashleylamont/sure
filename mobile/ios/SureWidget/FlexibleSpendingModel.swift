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
    struct Category: Decodable, Sendable { let id: String; let name: String; var parentID: String? = nil
        enum CodingKeys: String, CodingKey { case id, name; case parentID = "parent_id" }
    }
    let id: String
    let budgetID: String
    let currency: String
    let category: Category
    let available: String?
    let availableCents: Int?
    let budgetedCents: Int?
    let rolloverCents: Int?
    let inheritsParent: Bool
    var actualCents: Int? = nil
    enum CodingKeys: String, CodingKey {
        case id, currency, category
        case budgetID = "budget_id"
        case available = "available_to_spend", availableCents = "available_to_spend_cents"
        case budgetedCents = "display_budgeted_spending_cents"
        case rolloverCents = "rolled_over_amount_cents"
        case inheritsParent = "inherits_parent_budget"
        case actualCents = "actual_spending_cents"
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


/// Pure presentation calculations over an explicitly selected, disjoint pool.
/// This is a budget-rate estimate, never cash affordability or bank freshness.
struct SpendingPool: Sendable {
    let signals: [FlexibleSpendingSignal]

    func valid(at now: Date) -> Bool {
        guard !signals.isEmpty, signals.count <= 5, let first = signals.first,
              Set(signals.map { $0.category.id }).count == signals.count,
              Set(signals.map { $0.category.category.id }).count == signals.count,
              signals.allSatisfy({ $0.amount(at: now) != nil &&
                  $0.budget.id == first.budget.id && $0.category.currency == first.category.currency &&
                  $0.budget.startDate == first.budget.startDate && $0.budget.endDate == first.budget.endDate }) else { return false }
        let categoryIDs = Set(signals.map { $0.category.category.id })
        return !signals.contains { signal in
            signal.category.category.parentID.map { categoryIDs.contains($0) } ?? false
        }
    }

    func remaining(at now: Date) -> Decimal? {
        guard valid(at: now) else { return nil }
        return signals.reduce(Decimal.zero) { $0 + Decimal($1.category.availableCents!) }
    }

    func days(at now: Date, calendar requestedCalendar: Calendar = .current) -> (elapsed: Int, remaining: Int)? {
        guard valid(at: now), let budget = signals.first?.budget else { return nil }
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = requestedCalendar.timeZone
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let start = formatter.date(from: budget.startDate), let end = formatter.date(from: budget.endDate),
              formatter.string(from: start) == budget.startDate, formatter.string(from: end) == budget.endDate else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let elapsed = calendar.dateComponents([.day], from: start, to: today).day,
              let remaining = calendar.dateComponents([.day], from: today, to: end).day,
              elapsed >= 0, remaining >= 0 else { return nil }
        // Inclusive calendar days: no 24-hour division across daylight saving.
        return (elapsed + 1, remaining + 1)
    }

    func weeklyGuide(at now: Date) -> Decimal? {
        guard let remaining = remaining(at: now), let days = days(at: now), remaining > 0 else { return nil }
        return remaining * Decimal(min(7, days.remaining)) / Decimal(days.remaining)
    }

    func periodWeeklyAverage(at now: Date) -> Decimal? {
        guard let days = days(at: now), days.elapsed >= 7,
              signals.allSatisfy({ ($0.category.actualCents ?? -1) >= 0 }) else { return nil }
        let spent = signals.reduce(Decimal.zero) { $0 + Decimal($1.category.actualCents!) }
        return spent * 7 / Decimal(days.elapsed)
    }

    func suggestedReduction(at now: Date) -> Decimal? {
        guard let average = periodWeeklyAverage(at: now), let left = remaining(at: now),
              let days = days(at: now), left > 0 else { return nil }
        return max(0, average - left * 7 / Decimal(days.remaining))
    }

    func needsCutback(at now: Date) -> Bool {
        guard let reduction = suggestedReduction(at: now), let left = remaining(at: now),
              let days = days(at: now), let code = signals.first?.category.currency,
              Locale.commonISOCurrencyCodes.contains(code) else { return false }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let fiveMajorUnits = 5 * pow(Decimal(10), formatter.maximumFractionDigits)
        let sustainableWeeklyRate = left * 7 / Decimal(days.remaining)
        return reduction > max(fiveMajorUnits, sustainableWeeklyRate / 10)
    }

    enum PacePosition { case withinPlan, aroundPlan, easeOff }

    func pacePosition(at now: Date) -> PacePosition? {
        guard let reduction = suggestedReduction(at: now) else { return nil }
        if needsCutback(at: now) { return .easeOff }
        return reduction > 0 ? .aroundPlan : .withinPlan
    }

    func format(_ minorUnits: Decimal, approximate: Bool = false) -> String? {
        guard let code = signals.first?.category.currency,
              Locale.commonISOCurrencyCodes.contains(code) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let divisor = pow(Decimal(10), formatter.maximumFractionDigits)
        var value = minorUnits / divisor
        if approximate {
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 0, .down)
            value = rounded
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        }
        return formatter.string(from: value as NSDecimalNumber)
    }
}
