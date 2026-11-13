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
  test('category rows preserve values and validate ratios/status', () {
    final row = {
      'name': 'Fun',
      'spent': '150',
      'budget': '100',
      'remaining': '-50',
      'spentFraction': 1.5
    };
    final value = BudgetPaceBreakdown.fromMap({
      ...fixture(),
      'categoryBreakdown': [row],
      'categoryBreakdownStatus': 'partial',
      'categoryBreakdownNote': 'Partial'
    });
    expect(value.categories.single.spentFraction, 1.5);
    expect(value.categories.single.remaining, '-50');
    for (final bad in [
      {
        ...fixture(),
        'categoryBreakdown': [
          {...row, 'spentFraction': double.nan}
        ]
      },
      {
        ...fixture(),
        'categoryBreakdown': [
          {...row, 'spent': 150}
        ]
      },
      {...fixture(), 'categoryBreakdownStatus': 'unknown'},
    ]) {
      expect(() => BudgetPaceBreakdown.fromMap(bad), throwsFormatException);
    }
    expect(
        BudgetPaceBreakdown.fromMap({
          ...fixture(),
          'categoryBreakdown': [
            {...row, 'spentFraction': null}
          ]
        }).categories.single.spentFraction,
        isNull);
  });
  test('category remaining label is native formatted with legacy fallback', () {
    final row = {
      'name': 'Fun',
      'spent': '150',
      'budget': '100',
      'remaining': '-50'
    };
    BudgetPaceCategory parse(Map<String, Object> data) =>
        BudgetPaceCategory.fromMap(data);
    expect(parse(row).remainingLabel, isNull);
    expect(
        parse({...row, 'remainingLabel': r'A$50 over budget'}).remainingLabel,
        r'A$50 over budget');
    expect(parse({...row, 'remainingLabel': r'A$50 left'}).remainingLabel,
        r'A$50 left');
    expect(() => parse({...row, 'remainingLabel': 50}), throwsFormatException);
  });
  test('category projection preserves native formatting and unavailable state',
      () {
    final row = {
      'name': 'Fun',
      'spent': '150',
      'budget': '100',
      'remaining': '-50'
    };
    expect(BudgetPaceCategory.fromMap(row).projected, isNull);
    final value = BudgetPaceCategory.fromMap(
        {...row, 'projected': 'AUD 333.33', 'early': true});
    expect(value.projected, 'AUD 333.33');
    expect(value.early, isTrue);
    for (final bad in [
      {...row, 'projected': 333},
      {...row, 'projected': ''},
      {...row, 'early': 'yes'}
    ]) {
      expect(() => BudgetPaceCategory.fromMap(bad), throwsFormatException);
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
