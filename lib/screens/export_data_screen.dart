import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/quote_doc.dart';
import '../storage/local_db.dart';
import '../storage/local_files.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

enum _ExportDateFilter { thisWeek, thisMonth, last3Months, custom }
enum _InvoiceStatusFilter { all, paidOnly }

class ExportDataScreen extends StatefulWidget {
  const ExportDataScreen({super.key});

  @override
  State<ExportDataScreen> createState() => _ExportDataScreenState();
}

class _ExportDataScreenState extends State<ExportDataScreen> {
  _ExportDateFilter _dateFilter = _ExportDateFilter.thisMonth;
  _InvoiceStatusFilter _invoiceFilter = _InvoiceStatusFilter.all;
  DateTimeRange? _customRange;
  bool _exporting = false;

  List<QuoteDoc> _applyDateFilter(List<QuoteDoc> docs) {
    final now = DateTime.now();
    switch (_dateFilter) {
      case _ExportDateFilter.thisWeek:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return docs.where((d) => !d.date.isBefore(start)).toList();
      case _ExportDateFilter.thisMonth:
        return docs
            .where((d) => d.date.year == now.year && d.date.month == now.month)
            .toList();
      case _ExportDateFilter.last3Months:
        final start = DateTime(now.year, now.month - 2, 1);
        return docs.where((d) => !d.date.isBefore(start)).toList();
      case _ExportDateFilter.custom:
        if (_customRange == null) return docs;
        return docs
            .where((d) =>
                !d.date.isBefore(_customRange!.start) &&
                !d.date.isAfter(_customRange!.end.add(const Duration(days: 1))))
            .toList();
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final allDocs = LocalDB.instance.getDocuments();
      final clients = {for (final c in LocalDB.instance.getClients()) c.id: c};

      final filtered = _applyDateFilter(allDocs);
      var quotations = filtered.where((d) => d.type == DocType.quotation).toList();
      var invoices = filtered.where((d) => d.type == DocType.invoice).toList();

      if (_invoiceFilter == _InvoiceStatusFilter.paidOnly) {
        invoices = invoices
            .where((d) => d.status == DocStatus.paid || d.status == DocStatus.partiallyPaid)
            .toList();
      }

      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Quotations');

      // ── Quotations sheet ──────────────────────────────────────────────────
      final qSheet = excel['Quotations'];
      final qHeaders = [
        'Ref No', 'Date', 'Client Name', 'Site Location',
        'Item Description', 'Unit', 'Qty', 'Rate', 'Amount (₹)',
        'Subtotal (₹)', 'GST %', 'GST Amount (₹)', 'Total (₹)',
        'Status', 'Notes'
      ];
      qSheet.appendRow(qHeaders.map((h) => TextCellValue(h)).toList());

      for (final doc in quotations) {
        final client = clients[doc.clientId];
        final clientName = client?.companyName ?? '—';
        for (final li in doc.lineItems) {
          qSheet.appendRow([
            TextCellValue(doc.refNo),
            TextCellValue(formatDateDMY(doc.date)),
            TextCellValue(clientName),
            TextCellValue(doc.siteLocation),
            TextCellValue(li.description),
            TextCellValue(li.unit),
            DoubleCellValue(li.qty),
            DoubleCellValue(li.rate),
            DoubleCellValue(li.amount),
            DoubleCellValue(doc.subtotal),
            DoubleCellValue(doc.gstPercent),
            DoubleCellValue(doc.gstAmount),
            DoubleCellValue(doc.total),
            TextCellValue(doc.status.name),
            TextCellValue(doc.internalNotes),
          ]);
        }
        if (doc.lineItems.isEmpty) {
          qSheet.appendRow([
            TextCellValue(doc.refNo),
            TextCellValue(formatDateDMY(doc.date)),
            TextCellValue(clientName),
            TextCellValue(doc.siteLocation),
            TextCellValue('—'),
            TextCellValue(''),
            DoubleCellValue(0),
            DoubleCellValue(0),
            DoubleCellValue(0),
            DoubleCellValue(doc.subtotal),
            DoubleCellValue(doc.gstPercent),
            DoubleCellValue(doc.gstAmount),
            DoubleCellValue(doc.total),
            TextCellValue(doc.status.name),
            TextCellValue(doc.internalNotes),
          ]);
        }
      }

      // ── Invoices sheet ────────────────────────────────────────────────────
      excel.copy('Quotations', 'Invoices');
      final iSheet = excel['Invoices'];
      // Clear the copied content
      iSheet.rows.clear();

      final iHeaders = [
        'Ref No', 'Date', 'Due Date', 'Client Name', 'Site Location',
        'Item Description', 'Unit', 'Qty', 'Rate', 'Amount (₹)',
        'Subtotal (₹)', 'GST %', 'GST Amount (₹)', 'Total (₹)',
        'Amount Paid (₹)', 'Balance Due (₹)', 'Status', 'Notes'
      ];
      iSheet.appendRow(iHeaders.map((h) => TextCellValue(h)).toList());

      for (final doc in invoices) {
        final client = clients[doc.clientId];
        final clientName = client?.companyName ?? '—';
        final dueDate = doc.dueDate != null ? formatDateDMY(doc.dueDate!) : '—';
        for (final li in doc.lineItems) {
          iSheet.appendRow([
            TextCellValue(doc.refNo),
            TextCellValue(formatDateDMY(doc.date)),
            TextCellValue(dueDate),
            TextCellValue(clientName),
            TextCellValue(doc.siteLocation),
            TextCellValue(li.description),
            TextCellValue(li.unit),
            DoubleCellValue(li.qty),
            DoubleCellValue(li.rate),
            DoubleCellValue(li.amount),
            DoubleCellValue(doc.subtotal),
            DoubleCellValue(doc.gstPercent),
            DoubleCellValue(doc.gstAmount),
            DoubleCellValue(doc.total),
            DoubleCellValue(doc.amountPaid),
            DoubleCellValue(doc.balanceDue),
            TextCellValue(doc.status.name),
            TextCellValue(doc.internalNotes),
          ]);
        }
        if (doc.lineItems.isEmpty) {
          iSheet.appendRow([
            TextCellValue(doc.refNo),
            TextCellValue(formatDateDMY(doc.date)),
            TextCellValue(dueDate),
            TextCellValue(clientName),
            TextCellValue(doc.siteLocation),
            TextCellValue('—'),
            TextCellValue(''), TextCellValue(''),
            DoubleCellValue(0), DoubleCellValue(0),
            DoubleCellValue(doc.subtotal),
            DoubleCellValue(doc.gstPercent),
            DoubleCellValue(doc.gstAmount),
            DoubleCellValue(doc.total),
            DoubleCellValue(doc.amountPaid),
            DoubleCellValue(doc.balanceDue),
            TextCellValue(doc.status.name),
            TextCellValue(doc.internalNotes),
          ]);
        }
      }

      final now = DateTime.now();
      final stamp = '${now.day.toString().padLeft(2, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-${now.year}';
      final dir = await LocalFiles.exportsDirectory();
      final file = File('${dir.path}/EasyQuote_Export_$stamp.xlsx');
      await file.writeAsBytes(excel.encode()!);

      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'EasyQuote Export — $stamp',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('DATE FILTER',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: AppColors.blueprintDk, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _dateChip('This Week', _ExportDateFilter.thisWeek),
              _dateChip('This Month', _ExportDateFilter.thisMonth),
              _dateChip('Last 3 Months', _ExportDateFilter.last3Months),
              ChoiceChip(
                label: Text(_customRange == null
                    ? 'Custom Range'
                    : '${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)}'),
                selected: _dateFilter == _ExportDateFilter.custom,
                onSelected: (_) async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: _customRange,
                  );
                  if (picked != null) {
                    setState(() {
                      _customRange = picked;
                      _dateFilter = _ExportDateFilter.custom;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('INVOICE STATUS FILTER',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: AppColors.blueprintDk, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          const Text('Applies to the Invoice sheet only. Quotations always export all.',
              style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _invoiceFilter == _InvoiceStatusFilter.all,
                onSelected: (_) => setState(() => _invoiceFilter = _InvoiceStatusFilter.all),
              ),
              ChoiceChip(
                label: const Text('Paid Only'),
                selected: _invoiceFilter == _InvoiceStatusFilter.paidOnly,
                onSelected: (_) => setState(() => _invoiceFilter = _InvoiceStatusFilter.paidOnly),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 10),
          const Text(
            'The Excel file will have two sheets:\n'
            '• Quotations — all line items, with notes\n'
            '• Invoices — all line items, payment details, with notes\n\n'
            'Each line item gets its own row. Ref No, Date, Client Name '
            'are repeated on each row for easy filtering in Excel.',
            style: TextStyle(color: AppColors.inkSoft, height: 1.55, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_outlined),
            label: Text(_exporting ? 'Generating...' : 'Export to Excel'),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, _ExportDateFilter f) => ChoiceChip(
        label: Text(label),
        selected: _dateFilter == f,
        onSelected: (_) => setState(() => _dateFilter = f),
      );
}
