import AppIntents
import SwiftUI
import WidgetKit

struct FlexibleCategoryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Flexible budget category")
    static let defaultQuery = FlexibleCategoryQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct FlexibleCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FlexibleCategoryEntity] {
        // Resolve against the current login, never reuse a prior account’s name.
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [FlexibleCategoryEntity] {
        guard let config = SureWidgetStore.loadConfig() else { return [] }
        let generation = SureWidgetStore.currentGeneration()
        guard (config.generation ?? 0) == generation else { return [] }
        let budgets: SpendingBudgetsResponse = try await SpendingAPI.read("budgets?per_page=100", config)
        guard (budgets.pagination?.totalPages ?? 1) <= 1 else { throw SpendingAPI.Failure.incomplete }
        var entities: [FlexibleCategoryEntity] = []
        for budget in budgets.budgets.filter({ $0.contains(Date()) }) {
            let response: SpendingCategoriesResponse = try await SpendingAPI.read(
                "budget_categories?budget_id=\(budget.id)&per_page=100", config)
            // A truncated list is not presented as complete.
            guard (response.pagination?.totalPages ?? 1) <= 1 else { throw SpendingAPI.Failure.incomplete }
            entities += response.categories.filter { !$0.inheritsParent }.map {
                FlexibleCategoryEntity(id: $0.id, title: "\($0.category.name) · \(budget.name)")
            }
        }
        guard generation == SureWidgetStore.currentGeneration(),
              (config.generation ?? 0) == generation else { return [] }
        let allowed = FlexibleCategoryLabels.unambiguous(entities.map(\.title))
        let choices = entities.filter { allowed.contains($0.title) }
        if !entities.isEmpty && choices.isEmpty { throw SpendingAPI.Failure.ambiguousBudgets }
        return choices
    }
}

struct FlexibleSpendingIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Flexible spending"
    static let description = IntentDescription("Choose a flexible category, not bills or a one-off purchase. Remaining budget is not cash safe to spend. Choose again when the budget month changes. Ambiguous category/month names shared by multiple owners are omitted.")
    @Parameter(title: "Flexible category") var category: FlexibleCategoryEntity?
    @Parameter(title: "Show financial details", default: false) var showDetails: Bool
}

private struct SpendingBudgetsResponse: Decodable {
    let budgets: [SpendingBudget]
    let pagination: SpendingCategoriesResponse.Pagination?
}
private struct SpendingCategoriesResponse: Decodable {
    struct Pagination: Decodable {
        let totalPages: Int
        enum CodingKeys: String, CodingKey { case totalPages = "total_pages" }
    }
    let categories: [SpendingCategory]
    let pagination: Pagination?
    enum CodingKeys: String, CodingKey { case categories = "budget_categories", pagination }
}

private final class SpendingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the widget key to a redirected endpoint.
    }
}

private enum SpendingAPI {
    enum Failure: LocalizedError {
        case unavailable, incomplete, ambiguousBudgets
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Could not read this budget. Open Sure to check the connection."
            case .incomplete: return "Too many budgets or categories for this experimental widget."
            case .ambiguousBudgets: return "Multiple owners have matching budget names. This widget cannot safely distinguish them yet."
            }
        }
    }
    static func read<T: Decodable>(_ path: String, _ config: SureWidgetConfig) async throws -> T {
        guard let key = config.apiKey, !key.isEmpty,
              let url = URL(string: config.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/" + path)
        else { throw Failure.unavailable }
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
}

struct FlexibleSpendingEntry: TimelineEntry {
    let date: Date
    let signal: FlexibleSpendingSignal?
    let message: String
    let generation: Int
    let showDetails: Bool
}

struct FlexibleSpendingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlexibleSpendingEntry {
        FlexibleSpendingEntry(date: Date(), signal: nil, message: "Choose a flexible category in Edit Widget", generation: -1, showDetails: false)
    }
    func snapshot(for configuration: FlexibleSpendingIntent, in context: Context) async -> FlexibleSpendingEntry {
        if context.isPreview { return placeholder(in: context) }
        return await entry(configuration)
    }
    func timeline(for configuration: FlexibleSpendingIntent, in context: Context) async -> Timeline<FlexibleSpendingEntry> {
        let current = await entry(configuration)
        // Explicit expiry even if iOS delays the next network refresh.
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let expiry = min(now.addingTimeInterval(6 * 60 * 60), midnight)
        let expired = FlexibleSpendingEntry(date: expiry, signal: nil, message: "Open Sure to check newer spending", generation: current.generation, showDetails: configuration.showDetails)
        return Timeline(entries: [current, expired], policy: .after(Date().addingTimeInterval(30 * 60)))
    }
    private func entry(_ configuration: FlexibleSpendingIntent) async -> FlexibleSpendingEntry {
        let generation = SureWidgetStore.currentGeneration()
        func unavailable(_ message: String) -> FlexibleSpendingEntry {
            FlexibleSpendingEntry(date: Date(), signal: nil, message: message, generation: generation, showDetails: configuration.showDetails)
        }
        guard configuration.showDetails else { return unavailable("Financial details hidden · Edit Widget to show") }
        guard let entity = configuration.category else { return unavailable("Choose a flexible category in Edit Widget") }
        guard let config = SureWidgetStore.loadConfig(), (config.generation ?? 0) == generation,
              config.apiKey?.isEmpty == false else { return unavailable("Open Sure → Home Screen Widget to connect") }
        // Entity IDs are server-generated UUIDs, not arbitrary URL fragments.
        guard UUID(uuidString: entity.id) != nil else { return unavailable("Choose this month’s category") }
        do {
            let category: SpendingCategory = try await SpendingAPI.read("budget_categories/\(entity.id)", config)
            guard UUID(uuidString: category.budgetID) != nil else { return unavailable("Budget unavailable") }
            let budget: SpendingBudget = try await SpendingAPI.read("budgets/\(category.budgetID)", config)
            guard let signal = FlexibleSpendingResult.accept(category: category, budget: budget,
                selectedID: entity.id, startedGeneration: generation,
                currentGeneration: SureWidgetStore.currentGeneration(),
                showDetails: configuration.showDetails, fetchedAt: Date()) else { return unavailable("Open Sure to reconnect") }
            return FlexibleSpendingEntry(date: Date(), signal: signal, message: signal.message(at: Date()), generation: generation, showDetails: true)
        } catch {
            // No cached financial recommendation after a failed refresh.
            return unavailable("Budget unavailable · open Sure to check")
        }
    }
}

struct FlexibleSpendingView: View {
    let entry: FlexibleSpendingEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Flexible spending").font(.caption.weight(.semibold))
            if entry.generation != SureWidgetStore.currentGeneration() {
                Text("Open Sure to connect").font(.caption)
            } else if entry.showDetails, let signal = entry.signal {
                Text(signal.category.category.name).font(.headline).lineLimit(1)
                if let amount = signal.amount(at: entry.date) {
                    Text("\(amount) \(signal.category.currency)").font(.title2.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
                }
                Text(signal.message(at: entry.date)).font(.caption)
                Text("\(signal.budget.name) · ends \(signal.budget.endDate)").font(.caption2).lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 3) { Text("Fetched"); Text(signal.fetchedAt, style: .time) }.font(.caption2)
                Text("Bank updates may lag. Not spendable cash.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(entry.message).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct FlexibleSpendingWidget: Widget {
    let kind = "SureFlexibleSpendingWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: FlexibleSpendingIntent.self, provider: FlexibleSpendingProvider()) { entry in
            FlexibleSpendingView(entry: entry)
        }
        .configurationDisplayName("Flexible spending")
        .description("A selected category’s remaining budget, not a forecast or safe-to-spend amount.")
        .supportedFamilies([.systemMedium])
    }
}
