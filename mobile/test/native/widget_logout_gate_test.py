"""Run the real store logic with synthetic Keychain and temp-container dependencies."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
source = (root / 'ios/SureWidget/SureWidgetShared.swift').read_text().split('// MARK: - Sure API')[0]
source = source.replace('import WidgetKit', '')
start = source.index('    static func containerURL() -> URL? {')
end = source.index('    static func currentGeneration()', start)
source = source[:start] + '    static func containerURL() -> URL? { TestState.directory }\n\n' + source[end:]
source += '''
enum TestState { static var directory: URL! }
enum WidgetCredentialStore {
    static var data: Data?
    static var locked = false
    enum Failure: Error { case locked }
    static func readData() throws -> Data? {
        if locked { throw Failure.locked }
        return data
    }
}
@main struct Tests {
    static func main() throws {
        TestState.directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = SureWidgetConfig(baseUrl: "https://example.invalid", headers: [:], apiKey: "synthetic", generation: 0)
        WidgetCredentialStore.data = try JSONEncoder().encode(config)
        let snapshot = SureWidgetSnapshot(updatedAt: Date(), accounts: [], netWorth: nil, generation: 0)
        precondition(SureWidgetStore.hasCurrentConfig(generation: 0))
        precondition(!SureWidgetStore.hasCurrentConfig(generation: 1))
        SureWidgetStore.saveSnapshot(snapshot)
        precondition(SureWidgetStore.loadSnapshot() != nil)
        // Logout succeeds in Keychain, but generation file cannot be bumped.
        WidgetCredentialStore.data = nil
        precondition(SureWidgetStore.currentGeneration() == 0)
        precondition(!SureWidgetStore.hasCurrentConfig(generation: 0))
        precondition(SureWidgetStore.loadSnapshot() == nil)
        let file = TestState.directory.appendingPathComponent("sure-widget-snapshot.json")
        try FileManager.default.removeItem(at: file)
        SureWidgetStore.saveSnapshot(snapshot)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        WidgetCredentialStore.data = try JSONEncoder().encode(config)
        WidgetCredentialStore.locked = true
        precondition(!SureWidgetStore.hasCurrentConfig(generation: 0))
        WidgetCredentialStore.locked = false
        WidgetCredentialStore.data = Data("malformed".utf8)
        precondition(!SureWidgetStore.hasCurrentConfig(generation: 0))
        print("Widget logout cache gate tests passed (synthetic dependencies)")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='sure-logout-test-') as folder:
    folder = pathlib.Path(folder)
    swift = folder / 'Test.swift'
    swift.write_text(source)
    binary = folder / 'test'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(folder)], check=True)
