"""Static regression for Flutter's supported UIScene startup and widget bridge."""
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[2]
info = plistlib.loads((root / 'ios/Runner/Info.plist').read_bytes())
manifest = info['UIApplicationSceneManifest']
assert manifest['UIApplicationSupportsMultipleScenes'] is False
scene, = manifest['UISceneConfigurations']['UIWindowSceneSessionRoleApplication']
assert scene == {
    'UISceneClassName': 'UIWindowScene',
    'UISceneConfigurationName': 'flutter',
    'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).SceneDelegate',
    'UISceneStoryboardFile': 'Main',
}
source = (root / 'ios/Runner/AppDelegate.swift').read_text()
assert 'class SceneDelegate: FlutterSceneDelegate {}' in source
assert 'FlutterAppDelegate, FlutterImplicitEngineDelegate' in source
launch, engine = source.split('  func didInitializeImplicitFlutterEngine(', 1)
engine = engine.split('/// Stores connection secrets', 1)[0]
assert 'WidgetBridge.migrateLegacyConfig()' in launch
assert 'GeneratedPluginRegistrant.register' not in launch
assert 'GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)' in engine
assert 'engineBridge.pluginRegistry.registrar(forPlugin: "SureWidgetBridge")' in engine
assert 'name: "am.sure.mobile/widget"' in engine
assert 'WidgetBridge.handle(call, result: result)' in engine
print('UIScene manifest and engine-bound widget registration checks passed')
