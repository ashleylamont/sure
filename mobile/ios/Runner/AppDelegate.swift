import UIKit
import Flutter
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = WidgetBridge.migrateLegacyConfig()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // With UIScene the storyboard creates the engine after application launch.
  // Register plugins and channels against that engine, not the old app window.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SureWidgetBridge") {
      let channel = FlutterMethodChannel(
        name: "am.sure.mobile/widget",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        WidgetBridge.handle(call, result: result)
      }
    }
  }
}

// Flutter's scene delegate forwards URL/lifecycle events to the engine/plugins.
// Kept in this source file so all existing Runner build configurations include it.
class SceneDelegate: FlutterSceneDelegate {}

/// Stores connection secrets in shared Keychain and financial snapshots in the App Group.
/// Keep the group lookup and generation handling in sync with SureWidgetStore
/// in the widget target.
enum WidgetBridge {
  private static let baseGroup = "group.am.sure.mobile"
  private static let configFile = "sure-widget-config.json"
  private static let snapshotFile = "sure-widget-snapshot.json"
  private static let generationFile = "sure-widget-generation.json"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      // The widget extension needs iOS 17.
      if #available(iOS 17.0, *) {
        result(containerURL() != nil)
      } else {
        result(false)
      }

    case "update":
      guard let args = call.arguments as? [String: Any], let dir = containerURL() else {
        result(false)
        return
      }
      var generation = currentGeneration(in: dir)
      let snapshotURL = dir.appendingPathComponent(snapshotFile)
      var ok = true
      if var config = args["config"] as? [String: Any] {
        // Invalidate in-flight widget fetches before changing connection identity.
        // Otherwise a previous login can repopulate the deleted snapshot.
        guard migrateLegacyConfig() else { result(false); return }
        let previous = WidgetCredentialStore.load()
        let oldGeneration = generation
        do {
          generation = try WidgetSessionGeneration.prepare(
            config: config, previous: previous, current: generation
          ) { next in
            write(["generation": next], to: dir.appendingPathComponent(generationFile))
          }
        } catch {
          result(false)
          return
        }
        if generation != oldGeneration {
          try? FileManager.default.removeItem(at: snapshotURL)
        }
        config["generation"] = generation
        guard WidgetCredentialStore.save(config) else {
          WidgetCenter.shared.reloadAllTimelines()
          result(false)
          return
        }
        // No connection secrets are written to the shared filesystem anymore.
      }
      if var snapshot = args["snapshot"] as? [String: Any] {
        // Cached data only fills an empty widget; it never replaces newer data.
        let replaceExisting = args["replaceExisting"] as? Bool ?? true
        if replaceExisting || !hasSnapshot(in: dir, generation: generation) {
          snapshot["generation"] = generation
          ok = write(snapshot, to: snapshotURL) && ok
        } else if let netWorth = snapshot["netWorth"] as? String,
                  var existing = readObject(at: snapshotURL) {
          // Keep the saved accounts but take the newer net worth.
          existing["netWorth"] = netWorth
          ok = write(existing, to: snapshotURL) && ok
        }
      }
      WidgetCenter.shared.reloadAllTimelines()
      result(ok)

    case "clear":
      guard let dir = containerURL() else {
        result(WidgetCredentialStore.clear())
        return
      }
      // Invalidate first, so a widget fetch already in progress can't save
      // the old account's data after the files are deleted. If that fails,
      // report it: the files are still deleted, but the caller retries.
      let (nextGeneration, overflow) = currentGeneration(in: dir).addingReportingOverflow(1)
      let invalidated = !overflow && write(["generation": nextGeneration], to: dir.appendingPathComponent(generationFile))
      let credentialsCleared = WidgetCredentialStore.clear()
      for name in [configFile, snapshotFile] {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
      }
      WidgetCenter.shared.reloadAllTimelines()
      result(invalidated && credentialsCleared)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult
  static func migrateLegacyConfig() -> Bool {
    guard let dir = containerURL() else { return false }
    let url = dir.appendingPathComponent(configFile)
    guard FileManager.default.fileExists(atPath: url.path) else { return true }
    // A locked file is not silently mistaken for an absent file.
    guard let legacy = try? Data(contentsOf: url) else { return false }
    return WidgetCredentialMigration.migrate(legacy: legacy, generation: currentGeneration(in: dir),
      readSecure: WidgetCredentialStore.readData, saveVerified: WidgetCredentialStore.saveVerified) {
        do { try FileManager.default.removeItem(at: url); return true } catch { return false }
      }
  }

  private static func readObject(at url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func currentGeneration(in dir: URL) -> Int {
    readObject(at: dir.appendingPathComponent(generationFile))?["generation"] as? Int ?? 0
  }

  private static func hasSnapshot(in dir: URL, generation: Int) -> Bool {
    guard let snapshot = readObject(at: dir.appendingPathComponent(snapshotFile)) else { return false }
    return (snapshot["generation"] as? Int ?? 0) == generation
  }

  @discardableResult
  private static func write(_ object: Any, to url: URL) -> Bool {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      return false
    }
  }

  /// Re-signing tools such as AltStore and SideStore rename the App Group and
  /// record the new name under `ALTAppGroups`.
  static func containerURL() -> URL? {
    let info = Bundle.main.infoDictionary ?? [:]
    var groups = (info["ALTAppGroups"] as? [String]) ?? []
    if let configured = info["SureAppGroup"] as? String { groups.append(configured) }
    groups.append(baseGroup)

    for group in groups {
      if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        return url
      }
    }
    return nil
  }
}
