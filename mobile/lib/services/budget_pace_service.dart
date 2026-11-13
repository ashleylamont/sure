import 'package:flutter/services.dart';

/// A fresh native snapshot, calculated by the same code as the iOS widgets.
/// Financial amounts are already formatted by that code; Dart never recomputes
/// the budget or converts currency minor units.
class BudgetPaceBreakdown {
  const BudgetPaceBreakdown({
    required this.title,
    required this.areaNames,
    required this.periodStart,
    required this.periodEnd,
    required this.fetchedAt,
    required this.currency,
    required this.spent,
    required this.budget,
    required this.remaining,
    required this.expected,
    required this.deviation,
    required this.projected,
    required this.elapsedFraction,
    required this.paceRatio,
    required this.state,
    required this.early,
    required this.paceLabel,
  });

  final String title;
  final List<String> areaNames;
  final String periodStart;
  final String periodEnd;
  final DateTime fetchedAt;
  final String currency;
  final String spent;
  final String budget;
  final String remaining;
  final String expected;
  final String? deviation;
  final String? projected;
  final double elapsedFraction;
  final double? paceRatio;
  final String state;
  final bool early;
  final String paceLabel;

  factory BudgetPaceBreakdown.fromMap(Map<Object?, Object?> data) {
    String text(String key) {
      final value = data[key];
      if (value is! String || value.isEmpty) {
        throw const FormatException('Incomplete budget snapshot');
      }
      return value;
    }

    final names = data['areaNames'];
    final elapsed = data['elapsedFraction'];
    final ratio = data['paceRatio'];
    final timestamp = DateTime.tryParse(text('fetchedAt'));
    if (names is! List ||
        names.any((name) => name is! String) ||
        elapsed is! num ||
        !elapsed.isFinite ||
        elapsed < 0 ||
        elapsed > 1 ||
        (ratio != null && (ratio is! num || !ratio.isFinite || ratio < 0)) ||
        timestamp == null ||
        data['early'] is! bool) {
      throw const FormatException('Invalid budget snapshot');
    }
    final state = text('state');
    if (!{'ahead', 'behind', 'around', 'unavailable'}.contains(state)) {
      throw const FormatException('Invalid pace state');
    }
    String? optionalText(String key) {
      final value = data[key];
      if (value != null && value is! String) {
        throw const FormatException('Invalid budget amount');
      }
      return value as String?;
    }

    return BudgetPaceBreakdown(
      title: text('title'),
      areaNames: List<String>.unmodifiable(names.cast<String>()),
      periodStart: text('periodStart'),
      periodEnd: text('periodEnd'),
      fetchedAt: timestamp,
      currency: text('currency'),
      spent: text('spent'),
      budget: text('budget'),
      remaining: text('remaining'),
      expected: text('expected'),
      deviation: optionalText('deviation'),
      projected: optionalText('projected'),
      elapsedFraction: elapsed.toDouble(),
      paceRatio: (ratio as num?)?.toDouble(),
      state: state,
      early: data['early'] as bool,
      paceLabel: text('paceLabel'),
    );
  }
}

class BudgetPaceService {
  const BudgetPaceService({
    this.channel = const MethodChannel('am.sure.mobile/widget'),
  });

  final MethodChannel channel;

  Future<BudgetPaceBreakdown> load({
    required String budget,
    required List<String> areas,
  }) async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'loadBudgetPaceBreakdown',
      {'budget': budget, 'areas': areas},
    );
    if (result == null) throw const FormatException('No budget snapshot');
    return BudgetPaceBreakdown.fromMap(result);
  }
}
