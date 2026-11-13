import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/privacy_provider.dart';
import '../services/budget_pace_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/sure_card.dart';

/// Read-only explanation of a widget's selection. The authenticated app owns
/// navigation and biometric gating. The URL carries selection IDs, never money.
class BudgetPaceScreen extends StatefulWidget {
  const BudgetPaceScreen({
    super.key,
    required this.budget,
    required this.areas,
    required this.onClose,
    this.loader,
  });

  final String budget;
  final List<String> areas;
  final VoidCallback onClose;
  final Future<BudgetPaceBreakdown> Function()? loader;

  @override
  State<BudgetPaceScreen> createState() => _BudgetPaceScreenState();
}

class _BudgetPaceScreenState extends State<BudgetPaceScreen> {
  BudgetPaceBreakdown? _snapshot;
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BudgetPaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.budget != widget.budget ||
        oldWidget.areas.join(',') != widget.areas.join(',')) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _snapshot = null;
    });
    try {
      final result = await (widget.loader?.call() ??
          const BudgetPaceService()
              .load(budget: widget.budget, areas: widget.areas));
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      // Avoid rendering server details, identifiers, or old financial data.
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<PrivacyProvider>().hidden;
    final data = _snapshot;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Spending pace'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onClose,
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed || data == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(SureSpacing.xxxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                                'Could not load this budget. Check the widget connection in Sure, then try again.',
                                textAlign: TextAlign.center),
                            const SizedBox(height: SureSpacing.xl),
                            TextButton(
                                onPressed: _load,
                                child: const Text('Try again')),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(SureSpacing.xl),
                        children: [
                          Text(data.title,
                              style: Theme.of(context).textTheme.titleLarge),
                          if (data.areaNames.isNotEmpty) ...[
                            const SizedBox(height: SureSpacing.sm),
                            Text(data.areaNames.join(' · ')),
                          ],
                          const SizedBox(height: SureSpacing.sm),
                          Text(
                              '${data.periodStart} to ${data.periodEnd} · ${data.currency}'),
                          const SizedBox(height: SureSpacing.xl),
                          SureCard(child: _paceCard(context, data, hidden)),
                          const SizedBox(height: SureSpacing.xl),
                          SureCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('If this average continues',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: SureSpacing.sm),
                                Text(
                                    hidden
                                        ? '••••'
                                        : data.projected ?? 'Not available',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const Text(
                                    'Projected spending by the end of this period.'),
                                _metric(
                                    'Period pace budget', data.budget, hidden),
                                _metric('Remaining', data.remaining, hidden),
                              ],
                            ),
                          ),
                          const SizedBox(height: SureSpacing.xl),
                          _categories(context, data, hidden),
                          const SizedBox(height: SureSpacing.xl),
                          Text(
                              'Updated ${DateFormat.yMMMd().add_jm().format(data.fetchedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: SureSpacing.md),
                          const Text(
                              'Bank transactions may arrive late. Bills and one-off purchases can shift the pace temporarily.'),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('How this is worked out'),
                            children: [
                              _metric(
                                  'Time elapsed',
                                  '${(data.elapsedFraction * 100).round()}%',
                                  hidden),
                              _metric('Difference (+ above / − below)',
                                  data.deviation, hidden),
                              const Text(
                                  'Even pace spreads the pace budget evenly across this period. The projection extends your average spending so far, not a prediction of your bills. Category budgets include rollover; the whole-budget comparison uses the period allocation. Remaining is budget headroom, not cash available to spend.'),
                            ],
                          ),
                          const SizedBox(height: SureSpacing.xxxl),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _paceCard(
      BuildContext context, BudgetPaceBreakdown data, bool hidden) {
    final palette = SureColors.of(context).palette;
    if (hidden) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SureSpacing.xxxl),
        child: Column(children: [
          Icon(Icons.visibility_off_outlined),
          SizedBox(height: SureSpacing.md),
          Text('Financial details hidden')
        ]),
      );
    }
    final ratio = data.paceRatio;
    return Column(
      children: [
        if (!hidden) ...[
          const SizedBox(height: SureSpacing.md),
          Text('Spent ${data.spent} vs ${data.expected} expected by today',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SureSpacing.md),
        ],
        if (!data.early && ratio != null)
          Semantics(
            container: true,
            label: '${ratio.toStringAsFixed(2)} times even spending pace',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 280,
                height: 150,
                child: CustomPaint(
                    painter: _PaceGauge(
                        ratio,
                        palette.borderSecondary,
                        palette.textPrimary,
                        data.state == 'ahead'
                            ? palette.warning
                            : palette.success)),
              ),
            ),
          ),
        if (!data.early && ratio != null) ...[
          Text('${(ratio * 100).round()}% of even pace',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          const SizedBox(height: SureSpacing.md),
        ],
        Text(data.early ? 'Building a picture' : data.paceLabel,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center),
        const SizedBox(height: SureSpacing.md),
        Text(
            data.early
                ? 'More of the period needs to pass before the pace estimate is useful.'
                : ratio == null
                    ? 'A pace comparison is not available for this budget.'
                    : 'The centre mark is 100%: even pace.',
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _categories(
      BuildContext context, BudgetPaceBreakdown data, bool hidden) {
    final palette = SureColors.of(context).palette;
    return SureCard(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('By category', style: Theme.of(context).textTheme.titleLarge),
        if (data.categoryStatus == 'partial') const Text('Partial breakdown'),
        if (data.categories.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SureSpacing.md),
            child: Text(hidden
                ? 'Financial details hidden'
                : data.categoryStatus == 'complete'
                    ? 'No spending or allocated amounts in these categories.'
                    : 'Category details are not available. The overall figures above still apply.'),
          ),
        for (final row in data.categories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SureSpacing.md),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(row.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: SureSpacing.sm),
                  Text(hidden ? '••••' : '${row.spent} spent of ${row.budget}'),
                  if (!hidden && row.spentFraction != null) ...[
                    const SizedBox(height: SureSpacing.sm),
                    Semantics(
                      label:
                          '${row.name}: ${(row.spentFraction! * 100).round()} percent of budget used',
                      child: ExcludeSemantics(
                          child: LinearProgressIndicator(
                        value: row.spentFraction!.clamp(0, 1),
                        color: row.spentFraction! > 1
                            ? palette.warning
                            : palette.textSecondary,
                        backgroundColor: palette.borderSecondary,
                      )),
                    ),
                  ],
                  const SizedBox(height: SureSpacing.sm),
                  Text(hidden
                      ? '••••'
                      : row.remainingLabel ?? '${row.remaining} remaining'),
                ]),
          ),
        if (!hidden && data.categoryNote.isNotEmpty)
          Text(data.categoryNote, style: Theme.of(context).textTheme.bodySmall),
      ],
    ));
  }

  Widget _metric(String label, String? value, bool hidden) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SureSpacing.md),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SureSpacing.xl,
          runSpacing: SureSpacing.xs,
          children: [
            Text(label),
            Text(hidden ? '••••' : value ?? 'Not available',
                style: Theme.of(context).textTheme.titleMedium)
          ],
        ),
      );
}

class _PaceGauge extends CustomPainter {
  const _PaceGauge(this.ratio, this.track, this.ink, this.signal);
  final double ratio;
  final Color track;
  final Color ink;
  final Color signal;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2 - 16, size.height - 20);
    final centre = Offset(size.width / 2, size.height - 12);
    final arc = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawArc(
        arc,
        math.pi,
        math.pi,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
    final angle = math.pi + ratio.clamp(0, 2) / 2 * math.pi;
    canvas.drawArc(
        arc,
        math.pi,
        angle - math.pi,
        false,
        Paint()
          ..color = signal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        Offset(centre.dx, centre.dy - radius - 9),
        Offset(centre.dx, centre.dy - radius + 9),
        Paint()
          ..color = ink
          ..strokeWidth = 3);
    canvas.drawLine(
        centre,
        centre + Offset(math.cos(angle), math.sin(angle)) * (radius - 20),
        Paint()
          ..color = ink
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(centre, 5, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _PaceGauge oldDelegate) =>
      ratio != oldDelegate.ratio ||
      track != oldDelegate.track ||
      ink != oldDelegate.ink ||
      signal != oldDelegate.signal;
}
