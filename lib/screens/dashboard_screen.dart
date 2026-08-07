import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/company_profile.dart';
import '../models/quote_doc.dart';
import '../models/client.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'documents_list_screen.dart';
import 'backup_screen.dart';
import 'document_preview_screen.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum _StatFilter { all, thisMonth, quarter, custom }
enum _GraphMetric { invoiceTotal, amountPaid, outstanding, quotationCount }
enum _GraphPeriod { month, quarter, year, custom }

// ─── Dashboard Screen ─────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  _StatFilter _statFilter = _StatFilter.quarter;
  DateTimeRange? _statCustomRange;
  _GraphMetric _metric = _GraphMetric.invoiceTotal;
  _GraphPeriod _graphPeriod = _GraphPeriod.month;
  DateTimeRange? _graphCustomRange;
  bool _autoBackupNoticeDismissed = false;

  // ─── Stat filter helpers ──────────────────────────────────────────────────

  List<QuoteDoc> _applyStatFilter(List<QuoteDoc> docs) {
    final now = DateTime.now();
    switch (_statFilter) {
      case _StatFilter.all: return docs;
      case _StatFilter.thisMonth:
        return docs.where((d) => d.date.year == now.year && d.date.month == now.month).toList();
      case _StatFilter.quarter:
        final start = DateTime(now.year, now.month - 2, 1);
        return docs.where((d) => !d.date.isBefore(start)).toList();
      case _StatFilter.custom:
        if (_statCustomRange == null) return docs;
        return docs.where((d) =>
            !d.date.isBefore(_statCustomRange!.start) &&
            !d.date.isAfter(_statCustomRange!.end.add(const Duration(days: 1)))).toList();
    }
  }

  String _statHelperText() {
    final now = DateTime.now();
    const months = ['January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    switch (_statFilter) {
      case _StatFilter.all: return '';
      case _StatFilter.thisMonth:
        return 'Showing data for ${months[now.month - 1]} ${now.year}';
      case _StatFilter.quarter:
        final m1 = DateTime(now.year, now.month - 2);
        final m2 = DateTime(now.year, now.month - 1);
        return 'Showing data for ${months[m1.month - 1]}, ${months[m2.month - 1]}, ${months[now.month - 1]} ${now.year}';
      case _StatFilter.custom:
        if (_statCustomRange == null) return '';
        return 'Showing data from ${formatDate(_statCustomRange!.start)} to ${formatDate(_statCustomRange!.end)}';
    }
  }

  Future<void> _pickStatCustom() async {
    final picked = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: _statCustomRange);
    if (picked != null) setState(() { _statCustomRange = picked; _statFilter = _StatFilter.custom; });
  }

  Future<void> _pickGraphCustom() async {
    final picked = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: _graphCustomRange);
    if (picked != null) setState(() { _graphCustomRange = picked; _graphPeriod = _GraphPeriod.custom; });
  }

  // ─── Greeting ─────────────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Widget _buildGreeting(CompanyProfile profile) {
    final logoPath = profile.logoPath;
    final hasLogo = logoPath.isNotEmpty && File(logoPath).existsSync();
    final initial = profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'E';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          // Logo or initial avatar
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: AppColors.blueprintDk.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasLogo
                ? Image.file(File(logoPath), fit: BoxFit.cover)
                : Center(
                    child: Text(initial,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                            color: AppColors.blueprintDk)),
                  ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
              Text(profile.name.isEmpty ? 'EasyQuote' : profile.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Graph data ───────────────────────────────────────────────────────────

  _ChartData _buildChartData(List<QuoteDoc> allDocs) {
    final now = DateTime.now();
    final relevantDocs = _metric == _GraphMetric.quotationCount
        ? allDocs.where((d) => d.type == DocType.quotation).toList()
        : allDocs.where((d) => d.type == DocType.invoice).toList();

    double metricValue(List<QuoteDoc> bucket) {
      switch (_metric) {
        case _GraphMetric.invoiceTotal:
          return bucket.fold(0.0, (s, d) => s + d.total);
        case _GraphMetric.amountPaid:
          return bucket.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? d.total : d.amountPaid));
        case _GraphMetric.outstanding:
          return bucket.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? 0.0 : d.balanceDue));
        case _GraphMetric.quotationCount:
          return bucket.length.toDouble();
      }
    }

    List<_Bar> bars;
    switch (_graphPeriod) {
      case _GraphPeriod.month:
        final Map<int, List<QuoteDoc>> byDay = {};
        for (final d in relevantDocs) {
          if (d.date.year == now.year && d.date.month == now.month) {
            byDay.putIfAbsent(d.date.day, () => []).add(d);
          }
        }
        if (byDay.isEmpty) {
          bars = [_Bar('—', 0)];
        } else {
          final sorted = byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
          bars = sorted.map((e) => _Bar('${e.key}', metricValue(e.value))).toList();
        }
        break;

      case _GraphPeriod.quarter:
        const qLabels = ['Q1', 'Q2', 'Q3', 'Q4'];
        bars = List.generate(4, (qi) {
          final qDocs = relevantDocs.where((d) {
            if (d.date.year != now.year) return false;
            return ((d.date.month - 1) ~/ 3) == qi;
          }).toList();
          return _Bar(qLabels[qi], metricValue(qDocs));
        });
        break;

      case _GraphPeriod.year:
        const mLabels = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
        bars = List.generate(12, (mi) {
          final mDocs = relevantDocs.where((d) =>
              d.date.year == now.year && d.date.month == mi + 1).toList();
          return _Bar(mLabels[mi], metricValue(mDocs));
        });
        break;

      case _GraphPeriod.custom:
        if (_graphCustomRange == null) { bars = [_Bar('—', 0)]; break; }
        final rangeStart = _graphCustomRange!.start;
        final rangeEnd = _graphCustomRange!.end;
        final spanDays = rangeEnd.difference(rangeStart).inDays + 1;
        if (spanDays <= 31) {
          final Map<String, List<QuoteDoc>> byDay = {};
          for (final d in relevantDocs) {
            if (!d.date.isBefore(rangeStart) && !d.date.isAfter(rangeEnd)) {
              final key = '${d.date.day}/${d.date.month}';
              byDay.putIfAbsent(key, () => []).add(d);
            }
          }
          bars = byDay.isEmpty ? [_Bar('No data', 0)] :
              (byDay.entries.toList()..sort((a,b) {
                final ap = a.key.split('/').map(int.parse).toList();
                final bp = b.key.split('/').map(int.parse).toList();
                if (ap[1] != bp[1]) return ap[1].compareTo(bp[1]);
                return ap[0].compareTo(bp[0]);
              })).map((e) => _Bar(e.key, metricValue(e.value))).toList();
        } else if (spanDays <= 90) {
          final weeks = <DateTime>[];
          var ws = rangeStart;
          while (!ws.isAfter(rangeEnd)) { weeks.add(ws); ws = ws.add(const Duration(days: 7)); }
          bars = weeks.map((ws) {
            final we = ws.add(const Duration(days: 6));
            return _Bar('${ws.day}/${ws.month}', metricValue(relevantDocs.where((d) =>
                !d.date.isBefore(ws) && !d.date.isAfter(we)).toList()));
          }).toList();
        } else {
          const mLabels = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
          final months = <DateTime>[];
          var cur = DateTime(rangeStart.year, rangeStart.month);
          while (!cur.isAfter(rangeEnd)) { months.add(cur); cur = DateTime(cur.year, cur.month + 1); }
          bars = months.map((m) => _Bar(mLabels[m.month - 1],
              metricValue(relevantDocs.where((d) =>
                  d.date.year == m.year && d.date.month == m.month).toList()))).toList();
        }
        break;
    }

    // Best performing month (always year view regardless of filter)
    final allInvoices = allDocs.where((d) => d.type == DocType.invoice).toList();
    final now2 = DateTime.now();
    double bestVal = 0;
    int bestMonth = 0;
    for (int mi = 1; mi <= 12; mi++) {
      final v = allInvoices.where((d) => d.date.year == now2.year && d.date.month == mi)
          .fold(0.0, (s, d) => s + d.total);
      if (v > bestVal) { bestVal = v; bestMonth = mi; }
    }
    const mNames = ['January','February','March','April','May','June',
        'July','August','September','October','November','December'];
    final bestMonthStr = bestVal > 0
        ? 'Best month: ${mNames[bestMonth - 1]} ${now2.year} — ${formatRupees(bestVal)}'
        : null;

    final maxVal = bars.fold(0.0, (a, b) => a > b.value ? a : b.value);
    return _ChartData(bars: bars, maxVal: maxVal, bestMonth: bestMonthStr);
  }

  // ─── Follow-up cards ──────────────────────────────────────────────────────

  List<QuoteDoc> _followUpDocs(List<QuoteDoc> allDocs, Map<String, Client> clientsById) {
    if (!LocalDB.instance.getFollowUpEnabled()) return [];
    return allDocs.where((d) => d.needsFollowUp).toList();
  }

  Widget _buildFollowUpCard(QuoteDoc doc, Map<String, Client> clientsById) {
    final client = clientsById[doc.clientId];
    final clientName = client?.companyName ?? 'Unknown Client';
    final location = doc.siteLocation.isNotEmpty ? doc.siteLocation : '';

    return Card(
      color: const Color(0xFFEFF8F1),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF4CAF50), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DocumentPreviewScreen(docId: doc.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: Color(0xFF388E3C), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TAKE FOLLOW UP',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800,
                            color: Color(0xFF2E7D32), letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text('$clientName${location.isNotEmpty ? ' • $location' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${doc.refNo}  •  Created ${formatDate(doc.date)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              Column(
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    onPressed: () async {
                      doc.followUpDone = true;
                      await LocalDB.instance.saveDocument(doc);
                      setState(() {});
                    },
                    child: const Text('Done', style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.inkSoft),
                    onPressed: () => _showFollowUpDismissDialog(doc),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showFollowUpDismissDialog(QuoteDoc doc) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss follow-up?'),
        content: Text('What would you like to do with "${doc.refNo}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reject'),
            child: const Text('Mark as Rejected'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'snooze'),
            child: const Text('Remind me again'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (action == 'reject') {
      doc.status = DocStatus.rejected;
      doc.followUpDone = true;
      await LocalDB.instance.saveDocument(doc);
      setState(() {});
    } else if (action == 'snooze') {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 3)),
        firstDate: DateTime.now(),
        lastDate: DateTime(2100),
      );
      if (date != null) {
        doc.followUpDate = date;
        await LocalDB.instance.saveDocument(doc);
        setState(() {});
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allDocs = LocalDB.instance.getDocuments();
    final clients = LocalDB.instance.getClients();
    final clientsById = {for (final c in clients) c.id: c};
    final profile = LocalDB.instance.getActiveProfile();

    final filteredDocs = _applyStatFilter(allDocs);
    final filteredInvoices = filteredDocs.where((d) => d.type == DocType.invoice).toList();
    final filteredQuotations = filteredDocs.where((d) => d.type == DocType.quotation).toList();

    final totalQuoted = filteredQuotations.fold(0.0, (s, d) => s + d.total);
    final totalInvoiced = filteredInvoices.fold(0.0, (s, d) => s + d.total);
    final totalPaid = filteredInvoices.fold(0.0,
        (s, d) => s + (d.status == DocStatus.paid ? d.total : d.amountPaid));
    final totalOutstanding = filteredInvoices.fold(0.0,
        (s, d) => s + (d.status == DocStatus.paid ? 0.0 : d.balanceDue));

    final allInvoices = allDocs.where((d) => d.type == DocType.invoice).toList();
    final overdueInvoices = allInvoices.where((d) => d.isOverdue).toList();
    final overdueTotal = overdueInvoices.fold(0.0, (s, d) => s + d.balanceDue);

    final followUps = _followUpDocs(allDocs, clientsById);
    final chart = _buildChartData(allDocs);

    // Auto-backup done notice
    final showAutoBackupNotice = !_autoBackupNoticeDismissed &&
        LocalDB.instance.getShowAutoBackupDoneNotice();
    if (showAutoBackupNotice) {
      // Clear the flag after reading so it only shows once per backup event.
      LocalDB.instance.setShowAutoBackupDoneNotice(false);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(0),
        children: [
          // ── Greeting ─────────────────────────────────────────────────────
          _buildGreeting(profile),

          // ── Auto-backup done notice ───────────────────────────────────────
          if (showAutoBackupNotice && !_autoBackupNoticeDismissed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: const Color(0xFFF0F7FF),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.backup_outlined, color: AppColors.blueprint),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'Auto-backup done today. Last backup: ${formatDate(LocalDB.instance.getLastAutoBackupAt() ?? DateTime.now())}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _autoBackupNoticeDismissed = true),
                    ),
                  ]),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Follow-up cards (if any) ──────────────────────────────
                if (followUps.isNotEmpty) ...[
                  ...followUps.map((doc) => _buildFollowUpCard(doc, clientsById)),
                ],

                // ── Overdue alert (FIRST — only if there are overdue) ─────
                if (overdueInvoices.isNotEmpty) ...[
                  _overdueCard(overdueInvoices.length, overdueTotal),
                  const SizedBox(height: 14),
                ],

                // ── Stat card filter ─────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _statChip('All', _StatFilter.all),
                    _statChip('This Month', _StatFilter.thisMonth),
                    _statChip('Quarter', _StatFilter.quarter),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        label: Text(
                          _statFilter == _StatFilter.custom && _statCustomRange != null
                              ? '${formatDate(_statCustomRange!.start)} – ${formatDate(_statCustomRange!.end)}'
                              : 'Custom Range',
                          style: const TextStyle(height: 1.0),
                        ),
                        selected: _statFilter == _StatFilter.custom,
                        onSelected: (_) => _statFilter == _StatFilter.custom
                            ? setState(() { _statFilter = _StatFilter.all; _statCustomRange = null; })
                            : _pickStatCustom(),
                      ),
                    ),
                  ]),
                ),
                if (_statHelperText().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_statHelperText(),
                        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  ),
                const SizedBox(height: 10),

                // ── 4 stat cards (clickable) ──────────────────────────────
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.6,
                  children: [
                    _statCard('Quotations', filteredQuotations.length.toString(),
                        formatRupees(totalQuoted),
                        onTap: () => _goToTab(context, DocType.quotation)),
                    _statCard('Invoices', filteredInvoices.length.toString(),
                        formatRupees(totalInvoiced),
                        onTap: () => _goToTab(context, DocType.invoice)),
                    _statCard('Amount Paid', '', formatRupees(totalPaid),
                        color: AppColors.ok,
                        onTap: () => _goToTabFiltered(context, DocType.invoice, 'paid')),
                    _statCard('Outstanding', '', formatRupees(totalOutstanding),
                        color: AppColors.danger,
                        onTap: () => _goToTabFiltered(context, DocType.invoice, 'outstanding')),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Graph: metric dropdown + period filter ────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildMetricDropdown(),
                    const SizedBox(width: 8),
                    Expanded(child: _buildPeriodFilter()),
                  ],
                ),
                _buildGraphCustomRangeTile(),
                const SizedBox(height: 8),

                // ── Chart ─────────────────────────────────────────────────
                SizedBox(
                  height: 200,
                  child: chart.maxVal == 0
                      ? const Center(child: Text('No data for this period',
                          style: TextStyle(color: AppColors.inkSoft)))
                      : BarChart(BarChartData(
                          maxY: chart.maxVal * 1.25,
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => AppColors.blueprintDk,
                              getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
                                _metric == _GraphMetric.quotationCount
                                    ? rod.toY.toInt().toString()
                                    : formatRupees(rod.toY),
                                const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.w700, fontSize: 11),
                              ),
                            ),
                          ),
                          barGroups: List.generate(chart.bars.length, (i) =>
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: chart.bars[i].value,
                                color: AppColors.blueprint,
                                width: chart.bars.length > 10 ? 10 : chart.bars.length > 6 ? 16 : 22,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ])),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= chart.bars.length) return const SizedBox();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(chart.bars[i].label,
                                      style: const TextStyle(fontSize: 9, color: AppColors.inkSoft)),
                                );
                              },
                            )),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                        )),
                ),

                // ── Best performing month ────────────────────────────────
                if (chart.bestMonth != null) ...[
                  const SizedBox(height: 6),
                  Text('★  ${chart.bestMonth}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.rebar, fontWeight: FontWeight.w600)),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Navigation helpers for clickable stat cards
  void _goToTab(BuildContext context, DocType type) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocumentsListScreen(docType: type),
    ));
  }

  void _goToTabFiltered(BuildContext context, DocType type, String filter) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocumentsListScreen(
        docType: type,
        initialStatusFilter: filter,
      ),
    ));
  }

  // ─── UI widgets ───────────────────────────────────────────────────────────

  Widget _statChip(String label, _StatFilter f) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          label: Text(label, style: const TextStyle(height: 1.0)),
          selected: _statFilter == f,
          onSelected: (_) => setState(() {
            _statFilter = _statFilter == f && f != _StatFilter.all ? _StatFilter.all : f;
            _statCustomRange = null;
          }),
        ),
      );

  Widget _buildMetricDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_GraphMetric>(
          value: _metric,
          isDense: true,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5,
              color: AppColors.blueprintDk, letterSpacing: 0.3),
          items: const [
            DropdownMenuItem(value: _GraphMetric.invoiceTotal, child: Text('Invoice Total')),
            DropdownMenuItem(value: _GraphMetric.amountPaid, child: Text('Amount Paid')),
            DropdownMenuItem(value: _GraphMetric.outstanding, child: Text('Outstanding')),
            DropdownMenuItem(value: _GraphMetric.quotationCount, child: Text('Quotation Count')),
          ],
          onChanged: (v) => setState(() => _metric = v ?? _metric),
        ),
      ),
    );
  }

  Widget _buildPeriodFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _periodChip('Month', _GraphPeriod.month),
          _periodChip('Quarter', _GraphPeriod.quarter),
          _periodChip('Year', _GraphPeriod.year),
          Padding(
            padding: const EdgeInsets.only(right: 0),
            child: ChoiceChip(
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              label: const Text('Custom', style: TextStyle(height: 1.0, fontSize: 11.5)),
              selected: _graphPeriod == _GraphPeriod.custom,
              onSelected: (_) => _graphPeriod == _GraphPeriod.custom
                  ? setState(() { _graphPeriod = _GraphPeriod.month; _graphCustomRange = null; })
                  : _pickGraphCustom(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, _GraphPeriod p) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          label: Text(label, style: const TextStyle(height: 1.0, fontSize: 11.5)),
          selected: _graphPeriod == p,
          onSelected: (_) => setState(() {
            _graphPeriod = _graphPeriod == p ? _GraphPeriod.month : p;
            _graphCustomRange = null;
          }),
        ),
      );

  Widget _buildGraphCustomRangeTile() {
    if (_graphPeriod != _GraphPeriod.custom) return const SizedBox.shrink();
    return InkWell(
      onTap: _pickGraphCustom,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          _graphCustomRange == null
              ? 'Tap to pick a custom date range'
              : 'Range: ${formatDate(_graphCustomRange!.start)} – ${formatDate(_graphCustomRange!.end)}  (tap to change)',
          style: const TextStyle(color: AppColors.blueprintDk, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _overdueCard(int count, double amount) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const DocumentsListScreen(docType: DocType.invoice, overdueOnly: true))),
      child: Card(
        color: const Color(0xFFFBEFEC),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OVERDUE INVOICES',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 0.5,
                      fontWeight: FontWeight.w700, color: AppColors.danger)),
              const SizedBox(height: 4),
              Text('$count invoice${count == 1 ? '' : 's'} • ${formatRupees(amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.danger),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String label, String count, String amount,
      {Color color = AppColors.ink, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: AppColors.inkSoft, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              if (count.isNotEmpty)
                Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(amount, style: TextStyle(
                  fontSize: count.isEmpty ? 17 : 12,
                  fontWeight: FontWeight.w600,
                  color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _Bar {
  final String label;
  final double value;
  const _Bar(this.label, this.value);
}

class _ChartData {
  final List<_Bar> bars;
  final double maxVal;
  final String? bestMonth;
  _ChartData({required this.bars, required this.maxVal, this.bestMonth});
}
