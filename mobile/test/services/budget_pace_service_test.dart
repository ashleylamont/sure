import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/services/budget_pace_service.dart';

Map<Object?, Object?> fixture() => {
      'title': 'November',
      'areaNames': ['Fun'],
      'periodStart': '2026-11-01',
      'periodEnd': '2026-11-30',
      'fetchedAt': '2026-11-13T05:00:00Z',
      'currency': 'AUD',
      'spent': r'A$10.00',
      'budget': r'A$20.00',
      'remaining': r'A$10.00',
      'expected': r'A$8.00',
      'deviation': r'+A$2.00',
      'projected': r'A$25.00',
      'elapsedFraction': 0.4,
      'paceRatio': 1.25,
      'state': 'ahead',
      'early': false,
      'paceLabel': '25% ahead of even pace',
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/pace');
  test('uses selection only and preserves native formatted values', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'loadBudgetPaceBreakdown');
      expect(call.arguments, {
        'budget': 'current',
        'areas': ['id']
      });
      return fixture();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final value = await const BudgetPaceService(channel: channel)
        .load(budget: 'current', areas: ['id']);
    expect(value.spent, r'A$10.00');
    expect(value.paceRatio, 1.25);
  });
  test('rejects malformed native payload', () {
    for (final bad in [
      {...fixture(), 'paceRatio': double.nan},
      {...fixture(), 'elapsedFraction': 2},
      {...fixture(), 'fetchedAt': 'not-a-date'},
      {...fixture(), 'state': 'invented'},
      {
        ...fixture(),
        'areaNames': [10]
      },
      {...fixture(), 'spent': null},
    ]) {
      expect(() => BudgetPaceBreakdown.fromMap(bad), throwsFormatException);
    }
  });
  test('accepts unavailable projection without inventing zero', () {
    final value = BudgetPaceBreakdown.fromMap({
      ...fixture(),
      'paceRatio': null,
      'projected': null,
      'deviation': null,
      'state': 'unavailable',
      'early': true
    });
    expect(value.projected, isNull);
    expect(value.paceRatio, isNull);
  });
}
