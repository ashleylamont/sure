import Foundation

@main
struct WidgetCredentialMigrationTests {
    static func main() throws {
        enum Failure: Error { case locked }
        func data(_ generation: Int, key: String = "synthetic-key") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["baseUrl": "https://example.invalid",
              "apiKey": key, "headers": ["Authorization": "synthetic-proxy"], "generation": generation])
        }
        let legacy = try data(7)
        var stored: Data?
        var removed = false
        var writes = 0
        func migrate(_ bytes: Data? = nil, generation: Int = 7, locked: Bool = false,
                     verifies: Bool = true, removes: Bool = true) -> Bool {
            WidgetCredentialMigration.migrate(legacy: bytes, generation: generation,
                readSecure: { if locked { throw Failure.locked }; return stored },
                saveVerified: { candidate in writes += 1; if verifies { stored = candidate }; return verifies },
                removeLegacy: { removed = removes; return removes })
        }
        precondition(migrate(legacy))
        precondition(stored == legacy && removed && writes == 1)
        let parsed = WidgetCredentialMigration.object(stored!)!
        precondition(parsed["apiKey"] as? String == "synthetic-key")
        precondition((parsed["headers"] as? [String: String])?["Authorization"] == "synthetic-proxy")
        removed = false
        precondition(migrate(legacy) && removed && writes == 1, "Migration is idempotent")
        let secure = try data(7, key: "new-secure-key")
        stored = secure
        precondition(migrate(legacy) && stored == secure && writes == 1, "Legacy never overwrites current secure config")
        stored = nil; removed = false
        precondition(!migrate(legacy, locked: true) && !removed && writes == 1, "Locked/denied Keychain is not absence")
        precondition(!migrate(legacy, verifies: false) && !removed && stored == nil, "Failed verification preserves legacy for retry")
        precondition(!migrate(legacy, removes: false) && stored == legacy && !removed, "Failed file removal is reported")
        precondition(migrate(legacy) && removed, "Removal can retry without rewriting keychain")
        stored = nil; removed = false; writes = 0
        precondition(migrate(legacy, generation: 8) && removed && stored == nil && writes == 0, "Old login cannot be resurrected")
        removed = false
        precondition(migrate(Data("invalid".utf8)) && removed && writes == 0)
        removed = false
        precondition(migrate(nil) && !removed && writes == 0)
        stored = try data(6)
        precondition(migrate(legacy) && stored == legacy && writes == 1, "Current legacy can replace stale secure generation")
        print("Widget credential migration synthetic checks passed")
    }
}
