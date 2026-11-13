import Foundation

@main
struct WidgetSessionGenerationTests {
    static func main() throws {
        let old: [String: Any] = ["generation": 7, "baseUrl": "https://old.example", "apiKey": "test-key", "headers": ["X-Proxy": "test-proxy"]]
        var writes = 0
        let same = try WidgetSessionGeneration.prepare(config: old, previous: old, current: 7) { _ in writes += 1; return true }
        precondition(same == 7 && writes == 0, "Unchanged config must retain generation")

        for (field, value) in [("baseUrl", "https://new.example" as Any), ("apiKey", "other-test-key" as Any), ("headers", ["X-Proxy": "other-proxy"] as Any)] {
            var nextConfig = old
            nextConfig[field] = value
            let inFlightGeneration = 7
            var persisted = inFlightGeneration
            let next = try WidgetSessionGeneration.prepare(config: nextConfig, previous: old, current: persisted) { persisted = $0; return true }
            precondition(next == 8 && persisted == next, "Identity change must persist invalidation first")
            precondition(inFlightGeneration != persisted, "Old success AND failure snapshots must be rejected")
            nextConfig["generation"] = next
            let repeated = try WidgetSessionGeneration.prepare(config: nextConfig, previous: nextConfig, current: next) { _ in preconditionFailure("Must not invalidate same identity twice") }
            precondition(repeated == next)
        }

        var different = old
        different["apiKey"] = "other-test-key"
        do {
            _ = try WidgetSessionGeneration.prepare(config: different, previous: old, current: 7) { _ in false }
            preconditionFailure("Must fail closed when invalidation cannot be saved")
        } catch WidgetSessionGeneration.Failure.invalidationFailed { }

        let initial = try WidgetSessionGeneration.prepare(config: old, previous: nil, current: 0) { $0 == 1 }
        precondition(initial == 1)
        var invalidated = old
        invalidated["generation"] = 6
        let recovered = try WidgetSessionGeneration.prepare(config: old, previous: invalidated, current: 7) { $0 == 8 }
        precondition(recovered == 8, "Stale config cannot reuse current identity")
        do {
            _ = try WidgetSessionGeneration.prepare(config: old, previous: nil, current: Int.max) { _ in preconditionFailure("Overflow must not persist") }
            preconditionFailure("Overflow must fail closed")
        } catch WidgetSessionGeneration.Failure.invalidationFailed { }
        print("Widget session generation regression checks passed")
    }
}
