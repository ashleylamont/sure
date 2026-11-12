import AppIntents
import SwiftUI
import WidgetKit

struct BudgetTrackEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Budget")
    static let defaultQuery = BudgetTrackQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct BudgetTrackQuery: EntityQuery {
    func defaultResult() async -> BudgetTrackEntity? { BudgetTrackEntity(id: "current", title: "Current budget") }
    func entities(for identifiers: [String]) async throws -> [BudgetTrackEntity] {
        let generation = SureWidgetStore.currentGeneration()
        var resolved = try await suggestedEntities().filter { identifiers.contains($0.id) }
        guard SureWidgetStore.hasCurrentConfig(generation: generation) else { return [] }
        let missing = Set(identifiers).subtracting(resolved.map(\.id))
        guard !missing.isEmpty else { return resolved }
        guard let config = SureWidgetStore.loadConfig(), (config.generation ?? 0) == generation else { return [] }
        let current = try await SpendingAPI.budgets(config).filter { $0.contains(Date()) }
        let labels = BudgetSelection.unambiguousLabels(current.map(\.name))
        resolved += current.filter { missing.contains("budget:\($0.id)") && labels.contains($0.name) }.map {
            BudgetTrackEntity(id: "budget:\($0.id)", title: $0.name)
        }
        // Preserve old configurations as visibly unresolved, never silently
        // replace an old area selection with the whole household budget.
        let unresolved = missing.subtracting(resolved.map(\.id))
        resolved += unresolved.map { BudgetTrackEntity(id: $0, title: "Reselect budget") }
        return SureWidgetStore.hasCurrentConfig(generation: generation) ? resolved : []
    }
    func suggestedEntities() async throws -> [BudgetTrackEntity] {
        guard let config = SureWidgetStore.loadConfig() else { return [] }
        let generation = SureWidgetStore.currentGeneration()
        guard (config.generation ?? 0) == generation else { return [] }
        let current = try await SpendingAPI.budgets(config).filter { $0.contains(Date()) }
        let labels = BudgetSelection.unambiguousLabels(current.map(\.name))
        let choices = current.count == 1 ? [BudgetTrackEntity(id: "current", title: "Current budget")] :
            current.filter { labels.contains($0.name) }.map { BudgetTrackEntity(id: "budget:\($0.id)", title: $0.name) }
        return SureWidgetStore.hasCurrentConfig(generation: generation) ? choices : []
    }
}

struct BudgetAreaEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Budget area")
    static let defaultQuery = BudgetAreaQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct BudgetAreaQuery: EntityQuery {
    @IntentParameterDependency(\BudgetTrackIntent.$track) var choice

    func entities(for identifiers: [String]) async throws -> [BudgetAreaEntity] {
        let generation = SureWidgetStore.currentGeneration()
        let resolved = try await suggestedEntities().filter { identifiers.contains($0.id) }
        guard SureWidgetStore.hasCurrentConfig(generation: generation) else { return [] }
        let missing = Set(identifiers).subtracting(resolved.map(\.id))
        // Retain missing IDs so a month/account change cannot silently produce
        // a partial pool or turn an unavailable selected area into whole budget.
        return resolved + missing.map { BudgetAreaEntity(id: $0, title: "Area unavailable") }
    }
    func suggestedEntities() async throws -> [BudgetAreaEntity] {
        guard let config = SureWidgetStore.loadConfig() else { return [] }
        let generation = SureWidgetStore.currentGeneration()
        guard (config.generation ?? 0) == generation,
              let track = BudgetTrack(id: choice?.track.id) else { return [] }
        if case .category = track { return [] }
        let budgets = try await SpendingAPI.budgets(config)
        guard let budget = BudgetSelection.currentBudget(budgets, track: track, at: Date()) else { return [] }
        let categories = try await SpendingAPI.categories(budget.id, config).filter { !$0.inheritsParent }
        let labels = BudgetSelection.unambiguousLabels(categories.map { $0.category.name })
        let choices = categories.filter { labels.contains($0.category.name) }.map {
            BudgetAreaEntity(id: $0.category.id, title: $0.category.name)
        }
        return SureWidgetStore.hasCurrentConfig(generation: generation) ? choices : []
    }
}

struct BudgetTrackIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Track spending"
    static let description = IntentDescription("Choose a budget. Leave Areas empty for the whole budget, or choose several areas. A parent includes its subcategories; selecting both counts them once. Current budget follows the month only when ownership is unambiguous.")
    @Parameter(title: "Budget") var track: BudgetTrackEntity?
    @Parameter(title: "Areas") var areas: [BudgetAreaEntity]?
}

private struct SpendingBudgetsResponse: Decodable {
    let budgets: [SpendingBudget]
    let pagination: SpendingPagination?
}
private struct SpendingPagination: Decodable {
    let totalPages: Int
    enum CodingKeys: String, CodingKey { case totalPages = "total_pages" }
}
private struct SpendingCategoriesResponse: Decodable {
    let categories: [SpendingCategory]
    let pagination: SpendingPagination?
    enum CodingKeys: String, CodingKey { case categories = "budget_categories", pagination }
}

private final class SpendingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum SpendingAPI {
    enum Failure: Error { case unavailable, incomplete }
    static func read<T: Decodable>(_ path: String, _ config: SureWidgetConfig) async throws -> T {
        guard let key = config.apiKey, !key.isEmpty,
              let url = URL(string: config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/" + path) else { throw Failure.unavailable }
        var request = URLRequest(url: url, timeoutInterval: 15)
        for (name, value) in config.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral, delegate: SpendingRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func budgets(_ config: SureWidgetConfig) async throws -> [SpendingBudget] {
        let response: SpendingBudgetsResponse = try await read("budgets?per_page=100", config)
        guard (response.pagination?.totalPages ?? 1) <= 1 else { throw Failure.incomplete }
        return response.budgets
    }
    static func categories(_ budgetID: String, _ config: SureWidgetConfig) async throws -> [SpendingCategory] {
        guard UUID(uuidString: budgetID) != nil else { throw Failure.unavailable }
        let response: SpendingCategoriesResponse = try await read("budget_categories?budget_id=\(budgetID)&per_page=100", config)
        guard (response.pagination?.totalPages ?? 1) <= 1 else { throw Failure.incomplete }
        return response.categories
    }
}

struct BudgetWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetSnapshot?
    let scope: String
    let message: String
    let generation: Int
    var preview = false
}

struct BudgetWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BudgetWidgetEntry { sample() }
    func snapshot(for configuration: BudgetTrackIntent, in context: Context) async -> BudgetWidgetEntry {
        if context.isPreview { return sample() }
        return await entry(configuration)
    }
    func timeline(for configuration: BudgetTrackIntent, in context: Context) async -> Timeline<BudgetWidgetEntry> {
        let current = await entry(configuration)
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let expiry = min(now.addingTimeInterval(6 * 60 * 60), tomorrow)
        let expired = BudgetWidgetEntry(date: expiry, snapshot: nil, scope: current.scope,
            message: "Open Sure to refresh", generation: current.generation)
        return Timeline(entries: [current, expired], policy: .after(now.addingTimeInterval(30 * 60)))
    }
    private func sample() -> BudgetWidgetEntry {
        let now = Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: 15, to: now)!
        let budget = SpendingBudget(id: "example", name: "Example budget", startDate: formatter.string(from: start),
            endDate: formatter.string(from: end), initialized: true, currency: "AUD", budgetedCents: 100000,
            actualCents: 60000, availableCents: 40000)
        return BudgetWidgetEntry(date: now, snapshot: BudgetSnapshot(budget: budget, fetchedAt: now),
            scope: "Example budget", message: "", generation: -1, preview: true)
    }
    private func entry(_ configuration: BudgetTrackIntent) async -> BudgetWidgetEntry {
        let generation = SureWidgetStore.currentGeneration()
        // Saved AppIntent titles may belong to a prior login; resolve names anew.
        var scope = "Current budget"
        func unavailable(_ message: String) -> BudgetWidgetEntry {
            BudgetWidgetEntry(date: Date(), snapshot: nil, scope: scope, message: message, generation: generation)
        }
        guard let config = SureWidgetStore.loadConfig(), (config.generation ?? 0) == generation,
              config.apiKey?.isEmpty == false else { return unavailable("Open Sure to connect") }
        guard let track = BudgetTrack(id: configuration.track?.id) else { return unavailable("Choose a track in Edit Widget") }
        switch track {
        case .automatic: break
        case .budget: scope = "Selected budget"
        case .category: return unavailable("Edit Widget: reselect Budget and Areas")
        }
        do {
            let budgets = try await SpendingAPI.budgets(config)
            guard let chosen = BudgetSelection.currentBudget(budgets, track: track, at: Date()) else {
                let current = budgets.filter { $0.contains(Date()) }
                if current.isEmpty { return unavailable("Set up a current budget in Sure") }
                if BudgetSelection.unambiguousLabels(current.map(\.name)).isEmpty {
                    return unavailable("Give budgets distinct names in Sure")
                }
                return unavailable("Choose a current budget in Edit Widget")
            }
            guard UUID(uuidString: chosen.id) != nil else { return unavailable("Open Sure to check this budget") }
            // The list omits actual/remaining values. Always fetch the detail.
            let budget: SpendingBudget = try await SpendingAPI.read("budgets/\(chosen.id)", config)
            guard budget.id == chosen.id else { return unavailable("Open Sure to refresh") }
            let selectedIDs = configuration.areas?.map(\.id) ?? []
            guard selectedIDs.allSatisfy({ UUID(uuidString: $0) != nil }), Set(selectedIDs).count <= 20 else {
                return unavailable("Choose up to 20 areas in Edit Widget")
            }
            var categories: [SpendingCategory] = []
            if !selectedIDs.isEmpty {
                categories = try await SpendingAPI.categories(budget.id, config)
                guard let selected = BudgetSelection.areas(categories, selectedIDs: selectedIDs, budgetID: budget.id) else {
                    return unavailable("Reselect areas in Edit Widget")
                }
                for selectedArea in selected {
                    guard UUID(uuidString: selectedArea.id) != nil else { return unavailable("Open Sure to check this area") }
                    let detail: SpendingCategory = try await SpendingAPI.read("budget_categories/\(selectedArea.id)", config)
                    guard detail.id == selectedArea.id, detail.category.id == selectedArea.category.id,
                          detail.category.parentID == selectedArea.category.parentID,
                          detail.budgetID == budget.id, detail.currency == selectedArea.currency,
                          detail.inheritsParent == selectedArea.inheritsParent else { return unavailable("Open Sure to refresh") }
                    categories = categories.map { $0.id == detail.id ? detail : $0 }
                }
            }
            guard SureWidgetStore.hasCurrentConfig(generation: generation) else { return unavailable("Open Sure to reconnect") }
            guard let snapshot = BudgetSnapshot(budget: budget, categories: categories, selectedIDs: selectedIDs, fetchedAt: Date()) else {
                return unavailable("Open Sure to check budget amounts")
            }
            scope = snapshot.displayScope
            if let problem = snapshot.problem(at: Date()) { return unavailable(problem) }
            return BudgetWidgetEntry(date: Date(), snapshot: snapshot, scope: scope, message: "", generation: generation)
        } catch {
            return unavailable("Open Sure to check the connection")
        }
    }
}

private struct BudgetUnavailableView: View {
    let title: String
    let scope: String
    let message: String
    let icon: String
    var compact = false
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 2) {
                Text(scope).font(.caption2.weight(.semibold)).lineLimit(1)
                Label(title, systemImage: icon).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(message).font(.caption2).lineLimit(2).minimumScaleFactor(0.7)
            }
        } else {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold))
            Text(scope).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        }
    }
}

struct BudgetRemainingView: View {
    let entry: BudgetWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var compact: Bool { family == .accessoryRectangular }
    private var circular: Bool { family == .accessoryCircular }
    var body: some View {
        Group {
            if let snapshot = usableSnapshot {
                if circular {
                    let amount = VStack(spacing: 0) {
                        Text(snapshot.compactRemainingText).font(.system(size: 12, weight: .semibold, design: .rounded)).minimumScaleFactor(0.8).lineLimit(1).allowsTightening(true)
                        Text("\(snapshot.remaining < 0 ? "over" : "left") \(snapshot.currency)").font(.system(size: 9))
                    }
                    Group {
                        if let used = snapshot.usedFraction(at: entry.date) {
                            Gauge(value: used, in: 0...1) { Text("budget") } currentValueLabel: { amount }
                                .gaugeStyle(.accessoryCircularCapacity).tint(.accentColor)
                        } else { amount }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(snapshot.scope): \(snapshot.remainingText) \(snapshot.remainingLabel). Bank data may lag.")
                } else {
                VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                    Text(entry.scope).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).accessibilityLabel(snapshot.scope)
                    Text(snapshot.remainingText).font(compact ? .title3.bold() : .system(size: 32, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.65).lineLimit(1)
                    Text(snapshot.remainingLabel).font(.caption)
                    if !compact {
                        Spacer(minLength: 2)
                        if let used = snapshot.usedFraction(at: entry.date) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule().fill(Color.accentColor).frame(width: geometry.size.width * used)
                                }
                            }
                            .frame(height: 4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Budget used")
                            .accessibilityValue(used.formatted(.percent.precision(.fractionLength(0))))
                        }
                        HStack {
                            Text("Ends \(snapshot.endLabel)")
                            if family == .systemMedium { Spacer(); Text("Fetched \(snapshot.fetchedAt, style: .time)") }
                        }.font(.caption2).foregroundStyle(.secondary)
                        if family == .systemMedium { Text("Bank data may lag · budget, not cash").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                }
            } else if circular {
                Image(systemName: "chart.bar.xaxis").accessibilityLabel("Budget remaining. \(connectionMessage)")
            } else {
                BudgetUnavailableView(title: "Budget remaining", scope: safeScope,
                    message: connectionMessage, icon: "chart.bar.fill", compact: compact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: circular ? .center : .topLeading)
        // Widgets have fixed geometry. Keep typography legible within it;
        // full amounts and meaning remain available to VoiceOver.
        .dynamicTypeSize(.xSmall ... .large)
        .privacySensitive()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    private var usableSnapshot: BudgetSnapshot? {
        guard entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation),
              let snapshot = entry.snapshot, snapshot.problem(at: entry.date) == nil else { return nil }
        return snapshot
    }
    private var safeScope: String {
        entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation) ? entry.scope : "Current budget"
    }
    private var connectionMessage: String {
        entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation) ? entry.message : "Open Sure to connect"
    }
}

struct BudgetPaceView: View {
    let entry: BudgetWidgetEntry
    @Environment(\.widgetFamily) private var family
    private var compact: Bool { family == .accessoryRectangular }
    private var circular: Bool { family == .accessoryCircular }
    var body: some View {
        Group {
            if let snapshot = usableSnapshot, let ratio = snapshot.pace(at: entry.date) {
                let value = NSDecimalNumber(decimal: ratio).doubleValue
                if circular {
                    Gauge(value: min(2, max(0, value)), in: 0...2) {
                        Text("pace").font(.system(size: 10, weight: .medium))
                    } currentValueLabel: {
                        Text(compactPercent(value)).font(.system(size: 14, weight: .semibold, design: .rounded)).minimumScaleFactor(0.8).lineLimit(1).allowsTightening(true)
                    }.gaugeStyle(.accessoryCircular).tint(.accentColor)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(snapshot.scope): \(percent(value)) of even pace. 100 percent is even pace. Bank data may lag.")
                } else {
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    Text(entry.scope).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).accessibilityLabel(snapshot.scope)
                    if compact {
                        Text("\(percent(value)) · \(snapshot.paceLabel(at: entry.date))").font(.headline).minimumScaleFactor(0.6).lineLimit(1)
                        Text("100% = even pace · estimate").font(.caption2)
                    } else {
                        HStack(spacing: 16) {
                            Gauge(value: min(2, max(0, value)), in: 0...2) {
                                Text("Pace")
                            } currentValueLabel: {
                                Text(percent(value)).font(.system(.body, design: .rounded).weight(.semibold)).minimumScaleFactor(0.55)
                            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("200") }
                            .gaugeStyle(.accessoryCircular).tint(.accentColor)
                            .accessibilityLabel("Budget pace").accessibilityValue("\(percent(value)); 100 percent is even pace")
                            if family == .systemMedium {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(snapshot.paceLabel(at: entry.date)).font(.headline)
                                    if let projected = snapshot.projection(at: entry.date) {
                                        Text("\(snapshot.formatted(projected)) projected").font(.subheadline)
                                    }
                                    Text("\(snapshot.formatted(snapshot.envelope)) budget").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: family == .systemMedium ? .leading : .center)
                        if family == .systemSmall { Text(snapshot.paceLabel(at: entry.date)).font(.caption).lineLimit(1).minimumScaleFactor(0.7) }
                        Text("100% = even pace").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(snapshot.budget.days(at: entry.date)?.early == true ? "Early estimate · data may lag" : "Linear estimate · data may lag")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                }
            } else if circular {
                Image(systemName: "gauge.with.needle").accessibilityLabel("Budget pace. \(connectionMessage)")
            } else {
                BudgetUnavailableView(title: "Budget pace", scope: safeScope,
                    message: connectionMessage, icon: "gauge.with.needle", compact: compact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: circular ? .center : .topLeading)
        // Widgets have fixed geometry. Keep typography legible within it;
        // full amounts and meaning remain available to VoiceOver.
        .dynamicTypeSize(.xSmall ... .large)
        .privacySensitive()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }
    private func compactPercent(_ value: Double) -> String {
        value >= 10 ? ">999%" : percent(value)
    }
    private var usableSnapshot: BudgetSnapshot? {
        guard entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation),
              let snapshot = entry.snapshot, snapshot.paceProblem(at: entry.date) == nil else { return nil }
        return snapshot
    }
    private var safeScope: String {
        entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation) ? entry.scope : "Current budget"
    }
    private var connectionMessage: String {
        guard entry.preview || SureWidgetStore.hasCurrentConfig(generation: entry.generation) else { return "Open Sure to connect" }
        return entry.snapshot?.paceProblem(at: entry.date) ?? entry.message
    }
}

struct FlexibleSpendingWidget: Widget {
    let kind = "SureFlexibleSpendingWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BudgetTrackIntent.self, provider: BudgetWidgetProvider()) { BudgetRemainingView(entry: $0) }
            .configurationDisplayName("Budget Remaining")
            .description("See what remains in the current whole budget or one category. Budget headroom is not cash available to spend; bank data can lag.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct BudgetPaceWidget: Widget {
    let kind = "SureBudgetPaceWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BudgetTrackIntent.self, provider: BudgetWidgetProvider()) { BudgetPaceView(entry: $0) }
            .configurationDisplayName("Budget Pace")
            .description("A speedometer against even spending through the budget period. 100% means even pace, not a safety limit. Rent and lumpy purchases can distort this linear reference; bank data can lag.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}
