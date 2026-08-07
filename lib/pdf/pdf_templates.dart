import 'package:pdf/pdf.dart';

/// Definition of one PDF template — name, accent color, and index.
class PdfTemplate {
  final int index;
  final String name;
  final PdfColor accent;
  final PdfColor accentLight;
  final PdfColor headerText;

  const PdfTemplate({
    required this.index,
    required this.name,
    required this.accent,
    required this.accentLight,
    required this.headerText,
  });

  static const all = [
    PdfTemplate(
      index: 0,
      name: 'Classic Dark',
      accent: PdfColor.fromInt(0xFF232220),
      accentLight: PdfColor.fromInt(0xFFE3DFD4),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 1,
      name: 'Blue Corporate',
      accent: PdfColor.fromInt(0xFF1565C0),
      accentLight: PdfColor.fromInt(0xFFE3F0FF),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 2,
      name: 'Minimal Line',
      accent: PdfColor.fromInt(0xFF111111),
      accentLight: PdfColor.fromInt(0xFFF5F5F5),
      headerText: PdfColor.fromInt(0xFF111111),
    ),
    PdfTemplate(
      index: 3,
      name: 'Classic Boxed',
      accent: PdfColor.fromInt(0xFF37474F),
      accentLight: PdfColor.fromInt(0xFFECEFF1),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 4,
      name: 'Modern Split',
      accent: PdfColor.fromInt(0xFF00695C),
      accentLight: PdfColor.fromInt(0xFFE0F2F1),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 5,
      name: 'Bold Monochrome',
      accent: PdfColor.fromInt(0xFF000000),
      accentLight: PdfColor.fromInt(0xFFF0F0F0),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 6,
      name: 'Soft Gray',
      accent: PdfColor.fromInt(0xFF78909C),
      accentLight: PdfColor.fromInt(0xFFF5F6F7),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
    PdfTemplate(
      index: 7,
      name: 'Letterhead Style',
      accent: PdfColor.fromInt(0xFFC62828),
      accentLight: PdfColor.fromInt(0xFFFFEBEE),
      headerText: PdfColor.fromInt(0xFFFFFFFF),
    ),
  ];
}
