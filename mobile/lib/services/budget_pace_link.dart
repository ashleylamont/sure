/// Selection-only deep link. Money, credentials and server URLs never travel here.
class BudgetPaceLink {
  BudgetPaceLink(this.budget, this.areas);
  final String budget;
  final List<String> areas;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static BudgetPaceLink? parse(Uri uri) {
    if (uri.scheme != 'sureapp' ||
        uri.host != 'budget-pace' ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.queryParametersAll.keys.any((k) => k != 'budget' && k != 'area')) {
      return null;
    }
    final budgets = uri.queryParametersAll['budget'];
    if (budgets == null || budgets.length != 1) return null;
    final budget = budgets.single;
    if (budget != 'current' &&
        !(budget.startsWith('budget:') &&
            _uuid.hasMatch(budget.substring(7)))) {
      return null;
    }
    final areas = uri.queryParametersAll['area'] ?? const <String>[];
    if (areas.length > 20 || areas.any((id) => !_uuid.hasMatch(id)))
      return null;
    return BudgetPaceLink(budget, List.unmodifiable(areas.toSet()));
  }
}
