import Foundation

/// Changes to any credential-routing input invalidate fetches from the old login.
/// Persist invalidation before the caller writes new config or snapshot files.
enum WidgetSessionGeneration {
    enum Failure: Error { case invalidationFailed }

    static func prepare(
        config: [String: Any], previous: [String: Any]?, current: Int,
        persist: (Int) -> Bool
    ) throws -> Int {
        if let previous,
           (previous["generation"] as? Int ?? 0) == current,
           previous["apiKey"] as? String == config["apiKey"] as? String,
           previous["baseUrl"] as? String == config["baseUrl"] as? String,
           (previous["headers"] as? [String: String] ?? [:]) == (config["headers"] as? [String: String] ?? [:]) {
            return current
        }
        let (next, overflow) = current.addingReportingOverflow(1)
        guard !overflow, persist(next) else { throw Failure.invalidationFailed }
        return next
    }
}
