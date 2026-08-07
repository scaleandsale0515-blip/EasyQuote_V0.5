import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:printing/printing.dart';

import '../models/quote_doc.dart';
import '../models/line_item.dart';
import '../models/terms_preset.dart';
import '../pdf/pdf_builder.dart';
import '../pdf/pdf_templates.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';

class PdfTemplatesScreen extends StatefulWidget {
  const PdfTemplatesScreen({super.key});

  @override
  State<PdfTemplatesScreen> createState() => _PdfTemplatesScreenState();
}

class _PdfTemplatesScreenState extends State<PdfTemplatesScreen> {
  int _activeIndex = 0;
  final Map<int, Uint8List?> _thumbnails = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _activeIndex = LocalDB.instance.getActivePdfTemplate();
    _generateThumbnails();
  }

  QuoteDoc _demoDoc() {
    final profile = LocalDB.instance.getActiveProfile();
    final clients = LocalDB.instance.getClients();
    final terms = LocalDB.instance.getTermsPresets();
    return QuoteDoc(
      id: 'demo',
      type: DocType.quotation,
      refNo: '${profile.prefix.isEmpty ? 'EQ' : profile.prefix}/Q/01',
      date: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 7)),
      clientId: clients.isNotEmpty ? clients.first.id : '',
      profileId: profile.id,
      termsId: terms.isNotEmpty ? terms.first.id : '',
      termsSnapshot: terms.isNotEmpty ? terms.first : null,
      includeTerms: true,
      gstPercent: profile.defaultGST > 0 ? profile.defaultGST : 18,
      siteLocation: 'Ahmedabad Site, Gujarat',
      lineItems: [
        LineItem(description: 'RCC Hollow Core Wall Panel (M30)', unit: 'Sqm', qty: 150, rate: 850),
        LineItem(description: 'Precast Column System', unit: 'Nos', qty: 20, rate: 4500),
        LineItem(description: 'Paver Block 60mm M30', unit: 'Sqm', qty: 200, rate: 420),
      ],
    );
  }

  Future<void> _generateThumbnails() async {
    final doc = _demoDoc();
    final profile = LocalDB.instance.getActiveProfile();
    final clients = LocalDB.instance.getClients();
    final client = clients.isNotEmpty ? clients.first : null;

    for (final t in PdfTemplate.all) {
      try {
        final bytes = await DocumentPdfBuilder.build(
          profile: profile,
          client: client ??
              (LocalDB.instance.getClients().isNotEmpty
                  ? LocalDB.instance.getClients().first
                  : _dummyClient()),
          doc: doc,
          templateIndex: t.index,
        );

        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/template_thumb_${t.index}.pdf');
        await file.writeAsBytes(bytes);

        final pdfDoc = await pdfx.PdfDocument.openFile(file.path);
        final page = await pdfDoc.getPage(1);
        final pageImage = await page.render(
          width: page.width * 0.4,
          height: page.height * 0.4,
          format: pdfx.PdfPageImageFormat.png,
        );
        await page.close();
        await pdfDoc.close();

        if (mounted) {
          setState(() => _thumbnails[t.index] = pageImage?.bytes);
        }
      } catch (_) {
        if (mounted) setState(() => _thumbnails[t.index] = null);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  _dummyClient() {
    return (LocalDB.instance.getClients().isNotEmpty)
        ? LocalDB.instance.getClients().first
        : null;
  }

  Future<void> _openPreview(PdfTemplate t) async {
    final doc = _demoDoc();
    final profile = LocalDB.instance.getActiveProfile();
    final clients = LocalDB.instance.getClients();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TemplatePreviewScreen(
          template: t,
          isActive: t.index == _activeIndex,
          onSelect: () => _selectTemplate(t),
          generatePdf: () async {
            return await DocumentPdfBuilder.build(
              profile: profile,
              client: clients.isNotEmpty ? clients.first : null,
              doc: doc,
              templateIndex: t.index,
            );
          },
        ),
      ),
    );
  }

  Future<void> _selectTemplate(PdfTemplate t) async {
    await LocalDB.instance.setActivePdfTemplate(t.index);
    if (mounted) setState(() => _activeIndex = t.index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Templates')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Select the layout used for all your Quotation & Invoice PDFs. '
              'Tap any template to preview it with your company details.',
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Generating previews…', style: TextStyle(color: AppColors.inkSoft)),
                ],
              ),
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: PdfTemplate.all.length,
              itemBuilder: (context, i) {
                final t = PdfTemplate.all[i];
                final isActive = t.index == _activeIndex;
                final thumb = _thumbnails[t.index];
                return GestureDetector(
                  onTap: () => _openPreview(t),
                  child: Stack(
                    children: [
                      Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isActive
                                ? Color.fromARGB(
                                    (t.accent.alpha * 255).round(),
                                    (t.accent.red * 255).round(),
                                    (t.accent.green * 255).round(),
                                    (t.accent.blue * 255).round(),
                                  )
                                : AppColors.line,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: thumb != null
                                  ? Image.memory(thumb, fit: BoxFit.cover,
                                      width: double.infinity)
                                  : Container(
                                      color: const Color(0xFFF5F5F5),
                                      child: const Center(
                                        child: Icon(Icons.picture_as_pdf_outlined,
                                            size: 36, color: AppColors.line),
                                      ),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.ok,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(color: Colors.white, fontSize: 9.5,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Full-screen template preview ─────────────────────────────────────────────

class _TemplatePreviewScreen extends StatelessWidget {
  final PdfTemplate template;
  final bool isActive;
  final VoidCallback onSelect;
  final Future<Uint8List> Function() generatePdf;

  const _TemplatePreviewScreen({
    required this.template,
    required this.isActive,
    required this.onSelect,
    required this.generatePdf,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(template.name)),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (_) => generatePdf(),
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              initialPageFormat: PdfPageFormat.a4,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isActive
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Select this template?'),
                            content: Text(
                              'Use "${template.name}" for all future Quotation & Invoice PDFs?',
                            ),
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('No'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Yes, Select'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          onSelect();
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                child: Text(isActive ? 'Currently Active' : 'Select Template'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
