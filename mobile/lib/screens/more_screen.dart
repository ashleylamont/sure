import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/sure_list_group.dart';
import 'budgets_screen.dart';
import 'calendar_screen.dart';
import 'cash_flow_screen.dart';
import 'recent_transactions_screen.dart';
import 'widget_settings_screen.dart';
import '../services/widget_bridge_service.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, this.onOpenSpendingPace});

  final ValueChanged<String>? onOpenSpendingPace;

  Future<void> _openBudgets(BuildContext context) async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (routeContext) => BudgetsScreen(
          onOpenSpendingPace: onOpenSpendingPace == null
              ? null
              : (budgetId) => Navigator.pop(routeContext, budgetId),
        ),
      ),
    );
    // Return to AppWrapper's auth/biometric-gated layer, never push pace above it.
    if (context.mounted && selected != null) onOpenSpendingPace?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      // Setting an explicit ListView padding opts out of the scroll view's
      // automatic safe-area inset, so restore it with SafeArea (keeps the group
      // clear of the status bar / home indicator).
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SureListGroup(
              children: [
                if (onOpenSpendingPace != null)
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      leading: _iconBadge(context, Icons.speed),
                      title: const Text('Spending pace'),
                      subtitle: const Text(
                          'Choose a current budget, then open Spending pace'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openBudgets(context),
                    ),
                  ),
                SureListRow(
                  leading: _iconBadge(context, Icons.pie_chart_outline),
                  title: l.moreBudgets,
                  subtitle: l.moreBudgetsSubtitle,
                  showChevron: true,
                  onTap: () => _openBudgets(context),
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.calendar_month),
                  title: l.moreCalendar,
                  subtitle: l.moreCalendarSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                  },
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.insights),
                  title: l.moreCashFlow,
                  subtitle: l.moreCashFlowSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CashFlowScreen(),
                      ),
                    );
                  },
                ),
                SureListRow(
                  leading: _iconBadge(context, Icons.receipt_long),
                  title: l.moreRecentTransactions,
                  subtitle: l.moreRecentTransactionsSubtitle,
                  showChevron: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RecentTransactionsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            if (WidgetBridgeService.instance.isSupported) ...[
              const SizedBox(height: 16),
              SureListGroup(
                children: [
                  SureListRow(
                    leading: _iconBadge(context, Icons.widgets_outlined),
                    title: 'Home Screen Widget',
                    subtitle: 'Let the widget refresh balances on its own',
                    showChevron: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const WidgetSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _iconBadge(BuildContext context, IconData icon) {
    final palette = SureColors.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      ),
      child: Icon(icon, color: palette.textPrimary),
    );
  }
}
