import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/neon_helper.dart';
import '../widgets/expense_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _month;
  late int _year;
  bool _loading = false;
  Map<String, double> _totals = {};
  double _totalSpent = 0;

  static const _months = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _load();
  }

  Future<void> _load() async {
    if (!NeonHelper.isReady) return;
    setState(() => _loading = true);
    try {
      final totals = await NeonHelper.instance.getTotalByCategory(month: _month, year: _year);
      final total = totals.values.fold(0.0, (a, b) => a + b);
      setState(() {
        _totals = totals;
        _totalSpent = total;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year--;
      } else {
        _month--;
      }
    });
    _load();
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_year > now.year || (_year == now.year && _month >= now.month)) return;
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month == now.month && _year == now.year;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _MonthSelector(
                label: '${_months[_month - 1]} $_year',
                onPrev: _prevMonth,
                onNext: _isCurrentMonth ? null : _nextMonth,
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!NeonHelper.isReady)
              const SliverFillRemaining(
                child: Center(
                  child: Text('Banco de dados não configurado.'),
                ),
              )
            else if (_totals.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum gasto em ${_months[_month - 1]}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _TotalCard(total: _totalSpent, formatter: currencyFmt),
                ),
              ),
              SliverToBoxAdapter(
                child: CategoryPieChart(data: _totals),
              ),
              SliverToBoxAdapter(
                child: _CategoryList(totals: _totals, totalSpent: _totalSpent, formatter: currencyFmt),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  const _MonthSelector({required this.label, required this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          SizedBox(
            width: 160,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: onNext == null ? Theme.of(context).disabledColor : null),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final double total;
  final NumberFormat formatter;

  const _TotalCard({required this.total, required this.formatter});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total do mês',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              formatter.format(total),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final Map<String, double> totals;
  final double totalSpent;
  final NumberFormat formatter;

  const _CategoryList({
    required this.totals,
    required this.totalSpent,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text('Por categoria',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ...entries.map((e) {
              final pct = totalSpent > 0 ? e.value / totalSpent : 0.0;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key,
                            style: Theme.of(context).textTheme.bodyMedium),
                        Text(formatter.format(e.value),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: pct,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
