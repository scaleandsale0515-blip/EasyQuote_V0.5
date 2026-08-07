import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company_profile.dart';
import '../models/client.dart';
import '../models/quote_doc.dart';
import '../models/terms_preset.dart';
import '../utils/formatters.dart';
import 'pdf_builder.dart' show PdfFonts;
import 'pdf_templates.dart';

class PdfTemplateBuilders {
  static Future<Uint8List> build({
    required CompanyProfile profile,
    required Client? client,
    required QuoteDoc doc,
    required PdfTemplate template,
  }) async {
    final fonts = await PdfFonts.load();
    final safe = client ??
        Client(id: '', companyName: 'Demo Client',
            contactPerson: 'Contact Person', phone: '9999999999');

    switch (template.index) {
      case 1: return _buildBlueCorporate(profile, safe, doc, fonts, template);
      case 2: return _buildMinimalLine(profile, safe, doc, fonts, template);
      case 3: return _buildClassicBoxed(profile, safe, doc, fonts, template);
      case 4: return _buildModernSplit(profile, safe, doc, fonts, template);
      case 5: return _buildBoldMono(profile, safe, doc, fonts, template);
      case 6: return _buildSoftGray(profile, safe, doc, fonts, template);
      case 7: return _buildLetterhead(profile, safe, doc, fonts, template);
      default: throw Exception('Unknown template index: ${template.index}');
    }
  }

  static pw.MemoryImage? _img(String path) {
    if (path.isEmpty) return null;
    final f = File(path);
    if (!f.existsSync()) return null;
    try { return pw.MemoryImage(f.readAsBytesSync()); } catch (_) { return null; }
  }

  static String _trimZero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static pw.PageTheme _a4(pw.ThemeData t) => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 42, 48, 42),
        theme: t,
      );

  // ── Shared: items table ───────────────────────────────────────────────────

  static pw.Widget _itemsTable(QuoteDoc doc, PdfFonts f, PdfColor accent,
      PdfColor accentLight, PdfColor headerText) {
    pw.Widget cell(String t,
            {pw.TextAlign a = pw.TextAlign.left, bool hdr = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Text(t,
              style: pw.TextStyle(
                  font: hdr ? f.bold : f.regular,
                  fontSize: hdr ? 7.5 : 8.5,
                  color: hdr ? headerText : null),
              textAlign: a),
        );

    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFD8D3C8), width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.5),
        4: pw.FlexColumnWidth(1.8),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: accent),
          children: [
            cell('DESCRIPTION', hdr: true),
            cell('UNIT', hdr: true),
            cell('QTY', hdr: true),
            cell('RATE', a: pw.TextAlign.right, hdr: true),
            cell('AMOUNT', a: pw.TextAlign.right, hdr: true),
          ],
        ),
        ...doc.lineItems.map((li) => pw.TableRow(children: [
              cell(li.description),
              cell(li.unit, a: pw.TextAlign.center),
              cell(li.qty.toStringAsFixed(li.qty == li.qty.roundToDouble() ? 0 : 2),
                  a: pw.TextAlign.right),
              cell(formatRupees(li.rate), a: pw.TextAlign.right),
              cell(formatRupees(li.amount), a: pw.TextAlign.right),
            ])),
      ],
    );
  }

  static pw.Widget _totalsRight(QuoteDoc doc, PdfFonts f) {
    final rows = [
      ['Subtotal', formatRupees(doc.subtotal)],
      ['GST @ ${_trimZero(doc.gstPercent)}% (Extra)', formatRupees(doc.gstAmount)],
    ];
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 220,
        child: pw.Column(children: [
          ...rows.map((r) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(r[0], style: pw.TextStyle(font: f.regular, fontSize: 9)),
                pw.Text(r[1], style: pw.TextStyle(font: f.regular, fontSize: 9)),
              ])),
          pw.Divider(thickness: 1),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total', style: pw.TextStyle(font: f.bold, fontSize: 11)),
              pw.Text(formatRupees(doc.total), style: pw.TextStyle(font: f.bold, fontSize: 11)),
            ],
          ),
        ]),
      ),
    );
  }

  static pw.Widget _termsSection(TermsPreset? ts, PdfFonts f) {
    if (ts == null || ts.clauses.isEmpty) return pw.SizedBox();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Terms & Conditions',
          style: pw.TextStyle(
              font: f.bold, fontSize: 11, decoration: pw.TextDecoration.underline)),
      pw.SizedBox(height: 8),
      ...ts.clauses.asMap().entries.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                    width: 16,
                    child: pw.Text('${e.key + 1}.',
                        style: pw.TextStyle(font: f.bold, fontSize: 8.5))),
                pw.Expanded(
                    child: pw.Text(e.value,
                        style: pw.TextStyle(font: f.regular, fontSize: 8.5))),
              ],
            ),
          )),
    ]);
  }

  static pw.Widget _bankSig(CompanyProfile p, pw.MemoryImage? sig,
      pw.MemoryImage? stamp, PdfFonts f) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('BANK DETAILS', style: pw.TextStyle(font: f.bold, fontSize: 8.5)),
          pw.SizedBox(height: 3),
          pw.Text('Bank Name: ${p.bankName}', style: pw.TextStyle(font: f.regular, fontSize: 8)),
          pw.Text('A/C Type: ${p.acType}', style: pw.TextStyle(font: f.regular, fontSize: 8)),
          pw.Text('A/C Holder: ${p.acHolder}', style: pw.TextStyle(font: f.regular, fontSize: 8)),
          pw.Text('A/C No.: ${p.acNumber}', style: pw.TextStyle(font: f.regular, fontSize: 8)),
          pw.Text('IFSC: ${p.ifsc}', style: pw.TextStyle(font: f.regular, fontSize: 8)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('For, ${p.name}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
          pw.SizedBox(height: 8),
          if (sig != null) pw.Container(height: 36, child: pw.Image(sig, fit: pw.BoxFit.contain)),
          if (stamp != null) pw.Container(height: 40, child: pw.Image(stamp, fit: pw.BoxFit.contain)),
          if (sig == null && stamp == null)
            pw.Text(p.stampSignatureText.isEmpty ? p.name : p.stampSignatureText,
                style: pw.TextStyle(font: f.bold, fontSize: 9)),
          pw.SizedBox(height: 4),
          pw.Text('(Authorised Signatory & Stamp)',
              style: pw.TextStyle(font: f.regular, fontSize: 7.5,
                  color: const PdfColor.fromInt(0xFF5B5750))),
        ]),
      ],
    );
  }

  // ── Template 1: Blue Corporate ────────────────────────────────────────────

  static Future<Uint8List> _buildBlueCorporate(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (logo != null) pw.Container(height: 50, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 16)),
              if (p.tagline.isNotEmpty) pw.Text(p.tagline, style: pw.TextStyle(font: f.italic, fontSize: 8, color: t.accent)),
            ]),
            pw.Text(isQ ? 'QUOTATION' : 'INVOICE',
                style: pw.TextStyle(font: f.bold, fontSize: 22, color: t.accent)),
          ],
        ),
        pw.Container(height: 3, color: t.accent, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('To:', style: pw.TextStyle(font: f.bold, fontSize: 8.5, color: t.accent)),
              pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 10)),
              if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              if (c.phone.isNotEmpty) pw.Text('Mo: ${c.phone}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              if (c.email.isNotEmpty) pw.Text(c.email, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Ref: ${doc.refNo}', style: pw.TextStyle(font: f.bold, fontSize: 9, color: t.accent)),
              pw.Text('Date: ${formatDate(doc.date)}', style: pw.TextStyle(font: f.regular, fontSize: 9)),
              pw.SizedBox(height: 4),
              pw.Text('Total Due:', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              pw.Text(formatRupees(doc.total), style: pw.TextStyle(font: f.bold, fontSize: 14, color: t.accent)),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        _bankSig(p, sig, stamp, f),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 2: Minimal Line ──────────────────────────────────────────────

  static Future<Uint8List> _buildMinimalLine(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (logo != null) pw.Container(height: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 18)),
              if (p.address.isNotEmpty) pw.Text(p.address, style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: const PdfColor.fromInt(0xFF5B5750))),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(isQ ? 'Quotation' : 'Invoice', style: pw.TextStyle(font: f.bold, fontSize: 20)),
              pw.Text(formatDate(doc.date), style: pw.TextStyle(font: f.regular, fontSize: 9)),
            ]),
          ],
        ),
        pw.Divider(thickness: 0.8),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Invoice to:', style: pw.TextStyle(font: f.bold, fontSize: 8.5)),
              pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 10)),
              if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              if (c.phone.isNotEmpty) pw.Text(c.phone, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Invoice Number:', style: pw.TextStyle(font: f.bold, fontSize: 8.5)),
              pw.Text(doc.refNo, style: pw.TextStyle(font: f.regular, fontSize: 9)),
              pw.SizedBox(height: 4),
              pw.Text('Total Due:', style: pw.TextStyle(font: f.bold, fontSize: 8.5)),
              pw.Text(formatRupees(doc.total), style: pw.TextStyle(font: f.bold, fontSize: 13)),
            ]),
          ],
        ),
        pw.Divider(thickness: 0.8),
        pw.SizedBox(height: 8),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.8),
        _bankSig(p, sig, stamp, f),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 3: Classic Boxed ─────────────────────────────────────────────

  static Future<Uint8List> _buildClassicBoxed(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Center(
          child: pw.Text(isQ ? 'QUOTATION / CONTRACT' : 'TAX INVOICE',
              style: pw.TextStyle(font: f.bold, fontSize: 14, letterSpacing: 1.5)),
        ),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFD8D3C8))),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (logo != null) pw.Container(height: 40, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 13)),
                if (p.address.isNotEmpty) pw.Text(p.address, style: pw.TextStyle(font: f.regular, fontSize: 7.5)),
                if (p.phone1.isNotEmpty) pw.Text('Tel: ${p.phone1}', style: pw.TextStyle(font: f.regular, fontSize: 7.5)),
                if (p.email.isNotEmpty) pw.Text(p.email, style: pw.TextStyle(font: f.regular, fontSize: 7.5)),
              ]),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor.fromInt(0xFFD8D3C8))),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Bill To:', style: pw.TextStyle(font: f.bold, fontSize: 8.5, color: t.accent)),
                pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 10)),
                if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                if (c.phone.isNotEmpty) pw.Text('Mo: ${c.phone}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                pw.SizedBox(height: 6),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Ref No:', style: pw.TextStyle(font: f.bold, fontSize: 8)),
                  pw.Text(doc.refNo, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                ]),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Date:', style: pw.TextStyle(font: f.bold, fontSize: 8)),
                  pw.Text(formatDate(doc.date), style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                ]),
              ]),
            ),
          ),
        ]),
        pw.SizedBox(height: 12),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        _bankSig(p, sig, stamp, f),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 4: Modern Split ──────────────────────────────────────────────

  static Future<Uint8List> _buildModernSplit(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(isQ ? 'QUOTATION' : 'INVOICE',
                    style: pw.TextStyle(font: f.bold, fontSize: 24, color: t.accent)),
                pw.Text(formatDate(doc.date), style: pw.TextStyle(font: f.regular, fontSize: 9)),
                pw.SizedBox(height: 12),
                pw.Text('Prepared for:', style: pw.TextStyle(font: f.bold, fontSize: 8, color: t.accent)),
                pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 11)),
                if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                if (c.phone.isNotEmpty) pw.Text(c.phone, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              if (logo != null) pw.Container(height: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 13)),
              pw.SizedBox(height: 8),
              pw.Text('Ref: ${doc.refNo}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              pw.SizedBox(height: 8),
              pw.Text('Total:', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              pw.Text(formatRupees(doc.total), style: pw.TextStyle(font: f.bold, fontSize: 14, color: t.accent)),
            ]),
          ],
        ),
        pw.Divider(color: t.accent, thickness: 2),
        pw.SizedBox(height: 8),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        pw.Container(
          width: double.infinity,
          color: t.accent,
          padding: const pw.EdgeInsets.all(12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('BANK DETAILS',
                    style: pw.TextStyle(font: f.bold, fontSize: 8, color: PdfColors.white)),
                pw.Text('${p.bankName}  |  A/C: ${p.acNumber}  |  IFSC: ${p.ifsc}',
                    style: pw.TextStyle(font: f.regular, fontSize: 7.5, color: PdfColors.white)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('For, ${p.name}',
                    style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfColors.white)),
                if (sig != null) pw.Container(height: 30, child: pw.Image(sig, fit: pw.BoxFit.contain)),
                pw.Text('(Authorised Signatory)',
                    style: pw.TextStyle(font: f.regular, fontSize: 7, color: PdfColors.white)),
              ]),
            ],
          ),
        ),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 5: Bold Monochrome ───────────────────────────────────────────

  static Future<Uint8List> _buildBoldMono(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Container(
          width: double.infinity,
          color: t.accent,
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(isQ ? 'QUOTATION' : 'INVOICE',
                  style: pw.TextStyle(font: f.bold, fontSize: 20, color: PdfColors.white)),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 10, color: PdfColors.white)),
                if (p.phone1.isNotEmpty) pw.Text(p.phone1, style: pw.TextStyle(font: f.regular, fontSize: 8, color: PdfColors.white)),
              ]),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('ISSUED TO:', style: pw.TextStyle(font: f.bold, fontSize: 8, color: t.accent)),
              pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 11)),
              if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              if (c.phone.isNotEmpty) pw.Text(c.phone, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
            ])),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Ref No: ${doc.refNo}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              pw.Text('Date: ${formatDate(doc.date)}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
            ]),
          ],
        ),
        pw.SizedBox(height: 10),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        _bankSig(p, sig, stamp, f),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text('Thank you for your business!',
              style: pw.TextStyle(font: f.bold, fontSize: 11)),
        ),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 6: Soft Gray ─────────────────────────────────────────────────

  static Future<Uint8List> _buildSoftGray(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;

    pdf.addPage(pw.MultiPage(
      pageTheme: _a4(theme),
      build: (ctx) => [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (logo != null) pw.Container(height: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 14, color: t.accent)),
              if (p.tagline.isNotEmpty) pw.Text(p.tagline, style: pw.TextStyle(font: f.italic, fontSize: 8)),
            ]),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: t.accentLight, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(isQ ? 'Quotation' : 'Invoice', style: pw.TextStyle(font: f.bold, fontSize: 12, color: t.accent)),
                pw.Text(doc.refNo, style: pw.TextStyle(font: f.regular, fontSize: 9)),
                pw.Text(formatDate(doc.date), style: pw.TextStyle(font: f.regular, fontSize: 9)),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('To:', style: pw.TextStyle(font: f.bold, fontSize: 8, color: t.accent)),
              pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 10)),
              if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              if (c.phone.isNotEmpty) pw.Text(c.phone, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
            ])),
          ],
        ),
        pw.SizedBox(height: 10),
        _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
        pw.SizedBox(height: 8),
        _totalsRight(doc, f),
        pw.SizedBox(height: 16),
        pw.Container(
          color: t.accentLight,
          padding: const pw.EdgeInsets.all(10),
          child: _bankSig(p, sig, stamp, f),
        ),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          _termsSection(ts, f),
        ],
      ],
    ));
    return pdf.save();
  }

  // ── Template 7: Letterhead Style ──────────────────────────────────────────

  static Future<Uint8List> _buildLetterhead(CompanyProfile p, Client c,
      QuoteDoc doc, PdfFonts f, PdfTemplate t) async {
    final theme = pw.ThemeData.withFont(base: f.regular, bold: f.bold, italic: f.italic);
    final pdf = pw.Document(theme: theme);
    final logo = _img(p.logoPath);
    final sig = _img(p.signaturePath);
    final stamp = _img(p.stampPath);
    final isQ = doc.type == DocType.quotation;
    final ts = doc.termsSnapshot;
    const sidebarWidth = 55.0;

    pw.Widget page(List<pw.Widget> content) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Red left sidebar strip with vertical company name
        pw.Container(
          width: sidebarWidth,
          color: t.accent,
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: -1.5708,
              child: pw.Text(
                p.name.toUpperCase(),
                style: pw.TextStyle(
                    font: f.bold, fontSize: 9,
                    color: PdfColors.white, letterSpacing: 1.5),
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: content),
        ),
      ],
    );

    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        theme: theme,
      ),
      build: (ctx) => [
        pw.SizedBox(
          height: PdfPageFormat.a4.availableHeight,
          child: page([
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  if (logo != null) pw.Container(height: 44, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                  if (logo == null) pw.Text(p.name, style: pw.TextStyle(font: f.bold, fontSize: 14)),
                ]),
                pw.Text(isQ ? 'QUOTATION' : 'INVOICE',
                    style: pw.TextStyle(font: f.bold, fontSize: 18, color: t.accent)),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(children: [
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('To:', style: pw.TextStyle(font: f.bold, fontSize: 8.5, color: t.accent)),
                pw.Text(c.companyName, style: pw.TextStyle(font: f.bold, fontSize: 10)),
                if (c.contactPerson.isNotEmpty) pw.Text(c.contactPerson, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                if (c.phone.isNotEmpty) pw.Text(c.phone, style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              ])),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('Ref: ${doc.refNo}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
                pw.Text('Date: ${formatDate(doc.date)}', style: pw.TextStyle(font: f.regular, fontSize: 8.5)),
              ]),
            ]),
            pw.SizedBox(height: 10),
            _itemsTable(doc, f, t.accent, t.accentLight, t.headerText),
            pw.SizedBox(height: 8),
            _totalsRight(doc, f),
            pw.SizedBox(height: 14),
            _bankSig(p, sig, stamp, f),
          ]),
        ),
        if (doc.includeTerms && ts != null && ts.clauses.isNotEmpty) ...[
          pw.NewPage(),
          pw.Padding(
            padding: const pw.EdgeInsets.all(42),
            child: _termsSection(ts, f),
          ),
        ],
      ],
    ));
    return pdf.save();
  }
}
