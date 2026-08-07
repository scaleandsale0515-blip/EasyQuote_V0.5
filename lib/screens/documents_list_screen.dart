import 'package:flutter/material.dart';
import '../models/quote_doc.dart';
import '../models/client.dart';
import '../models/line_item.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/ids.dart';
import 'document_form_screen.dart';
import 'document_preview_screen.dart';

enum _StatusFilter { all, draft, sent, accepted, rejected, converted, paid, partiallyPaid, overdue }

enum _DateFilter { all, thisWeek, thisMonth, custom }

class DocumentsListScreen extends StatefulWidget {
  final DocType docType;
  /// When true, opens straight into the Overdue filter.
  final bool overdueOnly;
  /// Optional pre-applied status filter: 'paid' or 'outstanding' (from dashboard taps).
  final String? initialStatusFilter;
  const DocumentsListScreen({
    super.key,
    required this.docType,
    this.overdueOnly = false,
    this.initialStatusFilter,
  });

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  List<QuoteDoc> _allDocs = [];
  Map<String, Client> _clientsById = {};
  String _query = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  _DateFilter _dateFilter = _DateFilter.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    if (widget.overdueOnly) {
      _statusFilter = _StatusFilter.overdue;
    } else if (widget.initialStatusFilter == 'paid') {
      _statusFilter = _StatusFilter.paid;
    } else if (widget.initialStatusFilter == 'outstanding') {
      // "Outstanding" maps to showing all invoices with balance due —
      // we use partiallyPaid chip as the closest available, but actually
      // we filter by balanceDue in the _filtered getter instead.
      _statusFilter = _StatusFilter.all;
    }
    _reload();
  }

  void _reload() {
    final all = LocalDB.instance.getDocuments().where((d) => d.type == widget.docType).toList();
    all.sort((a, b) => b.date.compareTo(a.date));
    final clients = LocalDB.instance.getClients();
    setState(() {
      _allDocs = all;
      _clientsById = {for (final c in clients) c.id: c};
    });
  }

  List<QuoteDoc> get _filtered {
    var list = _allDocs;

    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((d) {
        final clientName = _clientsById[d.clientId]?.companyName.toLowerCase() ?? '';
        return d.refNo.toLowerCase().contains(q) || clientName.contains(q);
      }).toList();
    }

    switch (_statusFilter) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.overdue:
        list = list.where((d) => d.isOverdue).toList();
        break;
      case _StatusFilter.draft:
        list = list.where((d) => d.status == DocStatus.draft).toList();
        break;
      case _StatusFilter.sent:
        list = list.where((d) => d.status == DocStatus.sent).toList();
        break;
      case _StatusFilter.accepted:
        list = list.where((d) => d.status == DocStatus.accepted).toList();
        break;
      case _StatusFilter.rejected:
        list = list.where((d) => d.status == DocStatus.rejected).toList();
        break;
      case _StatusFilter.converted:
        list = list.where((d) => d.status == DocStatus.converted).toList();
        break;
      case _StatusFilter.paid:
        list = list.where((d) => d.status == DocStatus.paid).toList();
        break;
      case _StatusFilter.partiallyPaid:
        list = list.where((d) => d.status == DocStatus.partiallyPaid).toList();
        break;
    }

    final now = DateTime.now();
    switch (_dateFilter) {
      case _DateFilter.all:
        break;
      case _DateFilter.thisWeek:
        final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        list = list.where((d) => !d.date.isBefore(startOfWeek) && !d.date.isAfter(endOfWeek)).toList();
        break;
      case _DateFilter.thisMonth:
        list = list.where((d) => d.date.year == now.year && d.date.month == now.month).toList();
        break;
      case _DateFilter.custom:
        if (_customRange != null) {
          list = list
              .where((d) =>
                  !d.date.isBefore(_customRange!.start) &&
                  !d.date.isAfter(_customRange!.end.add(const Duration(days: 1))))
              .toList();
        }
        break;
    }

    return list;
  }

  Future<void> _openNew() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocumentFormScreen(docType: widget.docType)),
    );
    _reload();
  }

  Future<void> _openExisting(QuoteDoc d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocumentPreviewScreen(docId: d.id)),
    );
    _reload();
  }

  Future<bool> _confirmDuplicate(QuoteDoc d) async {
    final label = d.type == DocType.quotation ? 'Quotation' : 'Invoice';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duplicate this document?'),
        content: Text('Duplicate $label "${d.refNo}"? This creates a new copy as a Draft — the original is left unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<bool> _confirmConvert(QuoteDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Invoice?'),
        content: Text('Convert Quotation "${d.refNo}" into an Invoice? This creates a new Invoice and marks this Quotation as Converted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _duplicate(QuoteDoc d) async {
    if (!await _confirmDuplicate(d)) return;
    // Prefix comes from the SAME profile the original document is pinned
    // to, not whatever happens to be the active profile right now.
    final profile = await LocalDB.instance.resolveAndPinProfile(d);
    final seq = LocalDB.instance.nextCounter(d.type.name);
    final tag = d.type == DocType.quotation ? 'Q' : 'INV';
    final refNo = '${profile.prefix.isEmpty ? 'EQ' : profile.prefix}/$tag/${seq.toString().padLeft(2, '0')}';

    final copy = QuoteDoc(
      id: generateId(),
      type: d.type,
      refNo: refNo,
      date: DateTime.now(),
      clientId: d.clientId,
      termsId: d.termsId,
      termsSnapshot: d.termsSnapshot,
      includeTerms: d.includeTerms,
      // Duplicating keeps the SAME profile the original was issued from —
      // it does not pick up whatever the currently-active profile is.
      profileId: d.profileId,
      lineItems: d.lineItems.map((li) => LineItem(description: li.description, unit: li.unit, qty: li.qty, rate: li.rate)).toList(),
      headerNotes: List<String>.from(d.headerNotes),
      specNotes: List<String>.from(d.specNotes),
      introText: d.introText,
      siteLocation: d.siteLocation,
      gstPercent: d.gstPercent,
      includePO: d.includePO,
      poInName: d.poInName,
      poPercent: d.poPercent,
      status: DocStatus.draft,
    );
    await LocalDB.instance.saveDocument(copy);
    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated as ${copy.refNo}')),
    );
  }

  Future<void> _convertToInvoice(QuoteDoc d) async {
    if (d.type != DocType.quotation) return;
    if (!await _confirmConvert(d)) return;
    // Prefix comes from the SAME profile the original quotation is pinned
    // to, not whatever happens to be the active profile right now.
    final profile = await LocalDB.instance.resolveAndPinProfile(d);
    final seq = LocalDB.instance.nextCounter(DocType.invoice.name);
    final refNo = '${profile.prefix.isEmpty ? 'EQ' : profile.prefix}/INV/${seq.toString().padLeft(2, '0')}';

    final invoice = QuoteDoc(
      id: generateId(),
      type: DocType.invoice,
      refNo: refNo,
      date: DateTime.now(),
      clientId: d.clientId,
      termsId: d.termsId,
      termsSnapshot: d.termsSnapshot,
      includeTerms: d.includeTerms,
      // Converted invoice keeps the SAME profile the original quotation was
      // issued from — it does not pick up whatever is currently active.
      profileId: d.profileId,
      lineItems: d.lineItems.map((li) => LineItem(description: li.description, unit: li.unit, qty: li.qty, rate: li.rate)).toList(),
      headerNotes: List<String>.from(d.headerNotes),
      specNotes: List<String>.from(d.specNotes),
      introText: d.introText,
      siteLocation: d.siteLocation,
      gstPercent: d.gstPercent,
      includePO: d.includePO,
      poInName: d.poInName,
      poPercent: d.poPercent,
      status: DocStatus.draft,
    );
    await LocalDB.instance.saveDocument(invoice);

    d.status = DocStatus.converted;
    await LocalDB.instance.saveDocument(d);

    _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Converted to invoice ${invoice.refNo}')),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DocumentPreviewScreen(docId: invoice.id)),
    );
    _reload();
  }

  Future<void> _quickStatusChange(QuoteDoc d) async {
    final isQuotation = d.type == DocType.quotation;
    final options = isQuotation
        ? [DocStatus.draft, DocStatus.sent, DocStatus.accepted, DocStatus.rejected, DocStatus.converted]
        : [DocStatus.draft, DocStatus.sent, DocStatus.paid, DocStatus.partiallyPaid];

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text('Change status: ${d.refNo}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
            const Divider(height: 1),
            ...options.map((s) => ListTile(
                  leading: Icon(Icons.circle,
                      size: 10, color: _statusColor(s)),
                  title: Text(_statusLabel(s)),
                  selected: d.status == s,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    d.status = s;
                    if (s == DocStatus.paid && d.type == DocType.invoice) {
                      d.amountPaid = d.total;
                    }
                    await LocalDB.instance.saveDocument(d);
                    _reload();
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(QuoteDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('Remove "${d.refNo}" from this device. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.instance.deleteDocument(d.id);
      _reload();
    }
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _dateFilter = _DateFilter.custom;
      });
    }
  }

  Color _statusColor(DocStatus s) {
    switch (s) {
      case DocStatus.draft:
        return const Color(0xFF8B8678);
      case DocStatus.sent:
        return AppColors.blueprint;
      case DocStatus.accepted:
      case DocStatus.paid:
        return AppColors.ok;
      case DocStatus.rejected:
      case DocStatus.overdue:
        return AppColors.danger;
      case DocStatus.converted:
      case DocStatus.partiallyPaid:
        return AppColors.rebar;
    }
  }

  String _statusLabel(DocStatus s) {
    switch (s) {
      case DocStatus.draft:
        return 'Draft';
      case DocStatus.sent:
        return 'Sent';
      case DocStatus.accepted:
        return 'Accepted';
      case DocStatus.rejected:
        return 'Rejected';
      case DocStatus.converted:
        return 'Converted';
      case DocStatus.paid:
        return 'Paid';
      case DocStatus.partiallyPaid:
        return 'Partially Paid';
      case DocStatus.overdue:
        return 'Overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isQuotation = widget.docType == DocType.quotation;
    final docs = _filtered;

    final statusOptions = isQuotation
        ? const [
            _StatusFilter.all,
            _StatusFilter.draft,
            _StatusFilter.sent,
            _StatusFilter.accepted,
            _StatusFilter.rejected,
            _StatusFilter.converted,
          ]
        : const [
            _StatusFilter.all,
            _StatusFilter.draft,
            _StatusFilter.sent,
            _StatusFilter.paid,
            _StatusFilter.partiallyPaid,
            _StatusFilter.overdue,
          ];

    return Scaffold(
      appBar: AppBar(title: Text(isQuotation ? 'Quotations' : 'Invoices')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNew,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search by Ref. No. or client name',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              children: statusOptions
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: ChoiceChip(
                          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          label: Text(
                            s == _StatusFilter.all ? 'All' : _statusLabel(_statusFor(s)),
                            style: const TextStyle(height: 1.0),
                          ),
                          selected: _statusFilter == s,
                          onSelected: (_) => setState(() => _statusFilter = s),
                        ),
                      ))
                  .toList(),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              children: [
                _dateChip('This Week', _DateFilter.thisWeek),
                _dateChip('This Month', _DateFilter.thisMonth),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    label: Text(
                      _customRange == null
                          ? 'Custom Range'
                          : '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}',
                      style: const TextStyle(height: 1.0),
                    ),
                    selected: _dateFilter == _DateFilter.custom,
                    onSelected: (_) {
                      if (_dateFilter == _DateFilter.custom) {
                        setState(() {
                          _dateFilter = _DateFilter.all;
                          _customRange = null;
                        });
                      } else {
                        _pickCustomRange();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: docs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(isQuotation ? Icons.request_quote_outlined : Icons.receipt_long_outlined,
                              size: 48, color: AppColors.line),
                          const SizedBox(height: 12),
                          Text(
                            _allDocs.isEmpty
                                ? 'No ${isQuotation ? 'quotations' : 'invoices'} yet'
                                : 'Nothing matches this filter',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final d = docs[idx];
                      final client = _clientsById[d.clientId];
                      return Card(
                        child: ListTile(
                          title: Text(d.refNo, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${client?.companyName ?? '—'}  •  ${formatDate(d.date)}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          onTap: () => _openExisting(d),
                          onLongPress: () => _quickStatusChange(d),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatRupees(d.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: _statusColor(d.isOverdue ? DocStatus.overdue : d.status)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      d.isOverdue ? 'Overdue' : _statusLabel(d.status),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _statusColor(d.isOverdue ? DocStatus.overdue : d.status),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (action) {
                                  if (action == 'duplicate') _duplicate(d);
                                  if (action == 'convert') _convertToInvoice(d);
                                  if (action == 'delete') _confirmDelete(d);
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                                  if (isQuotation)
                                    const PopupMenuItem(value: 'convert', child: Text('Convert to Invoice')),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, _DateFilter f) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ChoiceChip(
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          label: Text(label, style: const TextStyle(height: 1.0)),
          selected: _dateFilter == f,
          onSelected: (_) => setState(() {
            _dateFilter = _dateFilter == f ? _DateFilter.all : f;
            _customRange = null;
          }),
        ),
      );

  DocStatus _statusFor(_StatusFilter f) {
    switch (f) {
      case _StatusFilter.draft:
        return DocStatus.draft;
      case _StatusFilter.sent:
        return DocStatus.sent;
      case _StatusFilter.accepted:
        return DocStatus.accepted;
      case _StatusFilter.rejected:
        return DocStatus.rejected;
      case _StatusFilter.converted:
        return DocStatus.converted;
      case _StatusFilter.paid:
        return DocStatus.paid;
      case _StatusFilter.partiallyPaid:
        return DocStatus.partiallyPaid;
      case _StatusFilter.overdue:
        return DocStatus.overdue;
      case _StatusFilter.all:
        return DocStatus.draft;
    }
  }
}
