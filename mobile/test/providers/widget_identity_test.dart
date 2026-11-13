import 'package:flutter_test/flutter_test.dart';
import '../../lib/providers/auth_provider.dart';
void main() {
  bool changed({bool had = true, bool api = false, String? oldUser = 'one',
    String? newUser = 'one', String? oldKey, String? newKey}) =>
      AuthProvider.widgetIdentityChanged(hadIdentity: had, wasApiKey: api,
        previousUserID: oldUser, nextUserID: newUser,
        previousApiKey: oldKey, nextApiKey: newKey);
  test('same known user preserves widgets; account replacement revokes', () {
    expect(changed(), isFalse);
    expect(changed(newUser: 'two'), isTrue);
    expect(changed(oldUser: null), isTrue);
    expect(changed(newUser: null), isTrue);
    expect(changed(had: false, oldUser: null), isFalse);
  });
  test('API identities compare synthetic keys and invalidate mode changes', () {
    expect(changed(api: true, oldKey: 'synthetic-a', newKey: 'synthetic-a'), isFalse);
    expect(changed(api: true, oldKey: 'synthetic-a', newKey: 'synthetic-b'), isTrue);
    expect(changed(api: true, oldKey: 'synthetic-a'), isTrue);
    expect(changed(newKey: 'synthetic-b'), isTrue);
  });
}
