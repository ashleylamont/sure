"""Source regression tripwires for pace routing; not a runtime biometric test.

Uses only source files. No credentials, network, simulator or device access.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
main = (root / 'lib/main.dart').read_text()
screen = (root / 'lib/screens/budget_pace_screen.dart').read_text()
link = (root / 'lib/services/budget_pace_link.dart').read_text()

assert 'bool _isLocked = true;' in main
assert 'bool _lockReady = false;' in main
assert '_hydrateInitialLock();' in main
hydrate = main.split('Future<void> _hydrateInitialLock() async {', 1)[1].split('Future<void> _markLockedIfEnabled()', 1)[0]
assert 'var enabled = true;' in hydrate
assert 'getBiometricEnabled()' in hydrate
assert 'catch (_)' in hydrate
assert '_isLocked = enabled;' in hydrate and '_lockReady = true;' in hydrate
routing = main.split('if (authProvider.isAuthenticated) {', 1)[1]
assert routing.index('if (!_lockReady)') < routing.index('BudgetPaceScreen(')
assert 'if (_paceLink != null && !_isLocked && authProvider.widgetPaceAllowed)' in ' '.join(routing.split())
assert 'authProvider.isLoading' in routing
assert '!identical(_paceAuthTokens, authProvider.tokens)' in routing
assert '_paceUserID != authProvider.user?.id' in routing
assert routing.index('_paceLink = null;') < routing.index('BudgetPaceScreen(')
assert 'if (_wasAuthenticated) {\n          _paceLink = null;' in routing

# Disposal / replacement prevents pending loads installing old results.
assert 'if (!mounted || request != _request) return;' in screen
assert '_snapshot = null;' in screen
assert "Text(hidden ? '••••' : value ?? 'Not available'" in screen
pace_card = screen.split('Widget _paceCard(', 1)[1]
assert pace_card.index('if (hidden)') < pace_card.index('final ratio = data.paceRatio;')
assert "areas.length > 20" in link
assert "k != 'budget' && k != 'area'" in link
print('Pace privacy routing source checks passed (runtime validation still required)')
