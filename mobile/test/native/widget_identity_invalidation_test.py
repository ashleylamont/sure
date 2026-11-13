"""Source checks for ordering and fail-closed auth gating, not device tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
auth = (root / 'lib/providers/auth_provider.dart').read_text()
bridge = (root / 'lib/services/widget_bridge_service.dart').read_text()
main = (root / 'lib/main.dart').read_text()
replace = auth.split('Future<void> _acceptTokenIdentity(', 1)[1].split('Future<void> _loadStoredAuth()', 1)[0]
assert replace.index('await _invalidateWidgetsForIdentity') < replace.index('_tokens = tokens;')
assert auth.count('await _acceptTokenIdentity(') == 5
refresh = auth.split('Future<bool> _refreshToken()', 1)[1].split('Future<void> _setTelemetryUser', 1)[0]
assert '_invalidateWidgetsForIdentity' not in refresh
invalidate = auth.split('Future<void> _invalidateWidgetsForIdentity(', 1)[1].split('Future<void> _acceptTokenIdentity', 1)[0]
assert invalidate.index('_widgetPaceAllowed = false;') < invalidate.index('await WidgetBridgeService.instance.clear()')
assert 'catch (_) {\n      _widgetPaceAllowed = false;' in invalidate
assert '!await WidgetBridgeService.instance.isConnectionRevoked()' in auth
clear = bridge.split('Future<bool> clear()', 1)[1].split('Future<bool> _isKeyRevoked()', 1)[0]
assert clear.index('_epoch++;') < clear.index('return _enqueue')
assert 'if (!storageCleared) return false;' in clear
assert 'return false;' in clear
assert 'authProvider.widgetPaceAllowed' in main
print('Widget identity invalidation source checks passed')
