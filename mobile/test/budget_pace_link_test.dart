import 'package:flutter_test/flutter_test.dart';
import '../lib/services/budget_pace_link.dart';

void main() {
  test('accepts current and selected areas, coalesces duplicates', () {
    const id = '12345678-1234-1234-1234-123456789abc';
    final link = BudgetPaceLink.parse(
        Uri.parse('sureapp://budget-pace?budget=current&area=$id&area=$id'))!;
    expect(link.budget, 'current');
    expect(link.areas, [id]);
  });
  test('rejects malformed or data-bearing links', () {
    for (final url in [
      'https://budget-pace?budget=current',
      'sureapp://budget-pace?budget=current&amount=500',
      'sureapp://budget-pace?budget=current&budget=current',
      'sureapp://budget-pace?budget=budget:bad',
      'sureapp://budget-pace?budget=current&area=bad',
      'sureapp://budget-pace?budget=current#fragment',
      'sureapp://budget-pace/path?budget=current',
      'sureapp://budget-pace',
    ]) {
      expect(BudgetPaceLink.parse(Uri.parse(url)), isNull, reason: url);
    }
  });
}
