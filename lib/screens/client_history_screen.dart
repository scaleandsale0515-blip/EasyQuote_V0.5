import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/quote_doc.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'client_form_screen.dart';
import 'document_preview_screen.dart';

enum _HistoryFilter { all, thisMonth, quarter, custom }

class ClientHistoryScreen extends StatefulWidget {
  final Client client;
  const ClientHistoryScreen({super.key, required this.client});

  @override
  State<ClientHistoryScreen> createState() => _ClientHistoryScreenState();
}

class _ClientHistoryScreenState extends State<ClientHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _query = '';
  _HistoryFilter _filter = _HistoryFilter.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<QuoteDoc> _docs(DocType type) {
    final now = DateTime.now();
    var docs = LocalDB.instance
        .getDocuments()
        .where((d) => d.clientId == widget.client.id && d.type == type)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      docs = docs.where((d) {
        final desc = d.lineItems.map((l) => l.description.toLowerCase()).join(' ');
        return d.refNo.toLowerCase().contains(q) ||
            d.siteLocation.toLowerCase().contains(q) ||
            desc.contains(q) ||
            formatRupees(d.total).contains(q);
      }).toList();
    }

    switch (_filter) {
      case _HistoryFilter.all:
        break;
      case _HistoryFilter.thisMonth:
        docs = docs.where((d) => d.date.year == now.year && d.date.month == now.month).toList();
        break;
      case _HistoryFilter.quarter:
        final start = DateTime(now.year, now.month - 2, 1);
        docs = docs.where((d) => !d.date.isBefore(start)).toList();
        break;
      case _HistoryFilter.custom:
        if (_customRange != null) {
          docs = docs
              .where((d) =>
                  !d.date.isBefore(_customRange!.start) &&
                  !d.date.isAfter(_customRange!.end.add(const Duration(days: 1))))
              .toList();
        }
        break;
    }
    return docs;
  }

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _customRange,
    );
    if (picked != null) setState(() { _customRange = picked; _filter = _HistoryFilter.custom; });
  }

  @override
  Widget build(BuildContext context) {
    final allDocs = LocalDB.instance.getDocuments()
        .where((d) => d.clientId == widget.client.id).toList();
    final allInvoices = allDocs.where((d) => d.type == DocType.invoice).toList();

    final totalBusiness = allDocs.fold(0.0, (s, d) => s + d.total);
    final totalInvoiced = allInvoices.fold(0.0, (s, d) => s + d.total);
    final totalPaid = allInvoices.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? d.total : d.amountPaid));
    final outstanding = allInvoices.fold(0.0, (s, d) => s + (d.status == DocStatus.paid ? 0 : d.balanceDue));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.client.companyName.isEmpty ? 'Client' : widget.client.companyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Client',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ClientFormScreen(existing: widget.client)),
              );
              setState(() {});
            },
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Summary stats
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    _stat('Total Business', formatRupees(totalBusiness)),
                    _stat('Invoiced', formatRupees(totalInvoiced)),
                    _stat('Paid', formatRupees(totalPaid), color: AppColors.ok),
                    _stat('Outstanding', formatRupees(outstanding), color: AppColors.danger),
                  ]),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Search by Ref. No., location, description, amount',
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                // Filter chips
                SizedBox(
                  height: 40,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _chip('All', _HistoryFilter.all),
                      _chip('This Month', _HistoryFilter.thisMonth),
                      _chip('Quarter', _HistoryFilter.quarter),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                          label: Text(
                            _customRange == null ? 'Custom' :
                            '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}',
                            style: const TextStyle(height: 1.0),
                          ),
                          selected: _filter == _HistoryFilter.custom,
                          onSelected: (_) => _filter == _HistoryFilter.custom
                              ? setState(() { _filter = _HistoryFilter.all; _customRange = null; })
                              : _pickCustom(),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tabs
                TabBar(
                  controller: _tabCtrl,
                  tabs: [
                    Tab(text: 'Quotations (${_docs(DocType.quotation).length})'),
                    Tab(text: 'Invoices (${_docs(DocType.invoice).length})'),
                  ],
                ),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _docList(DocType.quotation),
            _docList(DocType.invoice),
          ],
        ),
      ),
    );
  }

  Widget _docList(DocType type) {
    final docs = _docs(type);
    if (docs.isEmpty) {
      return Center(
        child: Text(
          'No ${type == DocType.quotation ? 'quotations' : 'invoices'} match.',
          style: const TextStyle(color: AppColors.inkSoft),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = docs[i];
        return Card(
          child: ListTile(
            title: Text(d.refNo, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${formatDate(d.date)}${d.siteLocation.isNotEmpty ? '  •  ${d.siteLocation}' : ''}'),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatRupees(d.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(d.isOverdue ? 'Overdue' : d.status.name,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DocumentPreviewScreen(docId: d.id)),
            ),
          ),
        );
      },
    );
  }

  Widget _stat(String label, String value, {Color color = AppColors.ink}) =>
      Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color)),
          Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.inkSoft), textAlign: TextAlign.center),
        ]),
      );

  Widget _chip(String label, _HistoryFilter f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          label: Text(label, style: const TextStyle(height: 1.0)),
          selected: _filter == f,
          onSelected: (_) => setState(() {
            _filter = _filter == f ? _HistoryFilter.all : f;
            _customRange = null;
          }),
        ),
      );
}
