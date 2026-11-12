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
        var parentID: String? = nil
        enum CodingKeys: String, CodingKey { case id, name; case parentID = "parent_id" }
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
    /// A parent already includes descendant actuals/rollover. Coalesce selections
    /// using the complete current hierarchy before reading/summing details.
    static func areas(_ categories: [SpendingCategory], selectedIDs: [String], budgetID: String) -> [SpendingCategory]? {
        let selected = Set(selectedIDs)
        guard !selected.isEmpty else { return [] }
        let grouped = Dictionary(grouping: categories.filter { $0.budgetID == budgetID }, by: { $0.category.id })
        guard selected.allSatisfy({ grouped[$0]?.count == 1 }),
              Set(selected.compactMap { grouped[$0]?.first?.currency }).count == 1 else { return nil }
        var retained: [SpendingCategory] = []
        for id in selected {
            guard let category = grouped[id]?.first else { return nil }
            var ancestor = category.category.parentID
            var visited: Set<String> = [id]
            var covered = false
            while let parent = ancestor {
                guard visited.insert(parent).inserted else { return nil }
                if selected.contains(parent) { covered = true }
                guard let nodes = grouped[parent], nodes.count == 1, let node = nodes.first else {
                    // One category cannot overlap anything; an absent ancestor
                    // is only unsafe when combining several areas.
                    if selected.count == 1 { break }
                    return nil
                }
                ancestor = node.category.parentID
            }
            if !covered {
                guard !category.inheritsParent else { return nil }
                retained.append(category)
            }
        }
        return retained.sorted { $0.category.name.localizedStandardCompare($1.category.name) == .orderedAscending }
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
    let areaCount: Int
    var displayScope: String {
        if areaCount > 2 || (areaCount > 1 && scope.count > 20) { return "\(areaCount) areas" }
        if scope.count > 20 { return areaCount == 0 ? "Whole budget" : "Selected area" }
        return scope
    }

    init?(budget: SpendingBudget, category: SpendingCategory? = nil, fetchedAt: Date) {
        self.init(budget: budget, categories: category.map { [$0] } ?? [],
                  selectedIDs: category.map { [$0.category.id] } ?? [], fetchedAt: fetchedAt)
    }

    init?(budget: SpendingBudget, categories: [SpendingCategory], selectedIDs: [String], fetchedAt: Date) {
        self.budget = budget
        self.fetchedAt = fetchedAt
        if !selectedIDs.isEmpty {
            guard let selected = BudgetSelection.areas(categories, selectedIDs: selectedIDs, budgetID: budget.id),
                  !selected.isEmpty, let first = selected.first,
                  selected.allSatisfy({ $0.currency == first.currency && $0.actualCents != nil && $0.availableCents != nil }),
                  budget.currency == nil || budget.currency == first.currency else { return nil }
            scope = selected.map { $0.category.name }.joined(separator: " + ")
            areaCount = selected.count
            currency = first.currency
            spent = selected.reduce(Decimal.zero) { $0 + Decimal($1.actualCents!) }
            remaining = selected.reduce(Decimal.zero) { $0 + Decimal($1.availableCents!) }
            // Each nonoverlapping area's actual + available preserves rollover once.
            envelope = spent + remaining
        } else {
            guard let currency = budget.currency, let actual = budget.actualCents,
                  let available = budget.availableCents, let allocation = budget.budgetedCents else { return nil }
            self.currency = currency
            areaCount = 0
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
    var compactRemainingText: String { CompactWidgetMoney.format(minorUnits: remaining < 0 ? -remaining : remaining, currency: currency) }

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

/// Explicit approximation for tiny circles; exact figures stay in accessibility.
enum CompactWidgetMoney {
    static func format(minorUnits: Decimal, currency: String) -> String {
        guard Locale.commonISOCurrencyCodes.contains(currency) else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let major = (minorUnits < 0 ? -minorUnits : minorUnits) / pow(Decimal(10), formatter.maximumFractionDigits)
        let units: [(Decimal, String)] = [(1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1000, "k")]
        // Promote values that round to the next suffix, rather than 1000k.
        let scale = units.first { major >= $0.0 * Decimal(string: "0.9995")! }
        let scaled = major / (scale?.0 ?? 1)
        let number = NumberFormatter()
        number.locale = Locale(identifier: "en_US_POSIX")
        number.numberStyle = .decimal
        number.usesGroupingSeparator = false
        number.minimumFractionDigits = 0
        number.maximumFractionDigits = scale == nil || scaled >= 10 ? 0 : 1
        let digits = number.string(from: scaled as NSDecimalNumber) ?? "—"
        // The full currency and exact amount remain in the accessibility label.
        // A generic currency mark is omitted if the code's symbol is too long.
        let symbol = formatter.currencySymbol ?? ""
        let shortSymbol = symbol.count <= 2 ? symbol : ""
        let sign = minorUnits < 0 ? "−" : ""
        if major > 0 && major < 1 { return sign + "<" + shortSymbol + "1" }
        if major >= 1_000_000_000_000_000 {
            number.numberStyle = .scientific
            number.maximumFractionDigits = 1
            return "≈" + sign + shortSymbol + (number.string(from: major as NSDecimalNumber) ?? "—")
        }
        return "≈" + sign + shortSymbol + digits + (scale?.1 ?? "")
    }
}
