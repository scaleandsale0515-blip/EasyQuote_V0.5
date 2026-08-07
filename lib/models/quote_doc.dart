import 'line_item.dart';
import 'terms_preset.dart';

enum DocType { quotation, invoice }

enum DocStatus {
  draft,
  sent,
  accepted,
  rejected,
  converted,
  paid,
  partiallyPaid,
  overdue,
}

class QuoteDoc {
  String id;
  DocType type;
  String refNo;
  DateTime date;
  DateTime? dueDate;
  String clientId;
  String termsId;
  TermsPreset? termsSnapshot;
  bool includeTerms;
  String profileId;

  List<LineItem> lineItems;
  List<String> headerNotes;
  List<String> specNotes;
  String introText;
  String siteLocation;

  /// Internal private notes — never printed on PDF, exported in Excel.
  String internalNotes;

  double gstPercent;
  bool includePO;
  String poInName;
  double poPercent;
  double amountPaid;

  DocStatus status;

  /// Follow-up reminder tracking for quotations.
  /// null = no custom reminder date set (uses default 3-day rule).
  /// Set when user picks "Remind me again" from the dismiss dialog.
  DateTime? followUpDate;
  /// true = user tapped "Follow-up Done" — never show reminder again.
  bool followUpDone;

  QuoteDoc({
    required this.id,
    required this.type,
    required this.refNo,
    required this.date,
    this.dueDate,
    this.clientId = '',
    this.termsId = '',
    this.termsSnapshot,
    this.includeTerms = true,
    this.profileId = '',
    List<LineItem>? lineItems,
    List<String>? headerNotes,
    List<String>? specNotes,
    this.introText = '',
    this.siteLocation = '',
    this.internalNotes = '',
    this.gstPercent = 18,
    this.includePO = false,
    this.poInName = '',
    this.poPercent = 0,
    this.amountPaid = 0,
    this.status = DocStatus.draft,
    this.followUpDate,
    this.followUpDone = false,
  })  : lineItems = lineItems ?? [],
        headerNotes = headerNotes ?? [],
        specNotes = specNotes ?? [];

  double get subtotal => lineItems.fold(0.0, (sum, li) => sum + li.amount);
  double get gstAmount => subtotal * (gstPercent / 100);
  double get total => subtotal + gstAmount;
  double get balanceDue => total - amountPaid;

  bool get isOverdue {
    if (type != DocType.invoice) return false;
    if (dueDate == null) return false;
    if (status == DocStatus.paid) return false;
    if (status == DocStatus.draft || status == DocStatus.rejected) return false;
    return dueDate!.isBefore(DateTime.now()) && balanceDue > 0.01;
  }

  /// Whether a follow-up reminder should show on the Dashboard today.
  bool get needsFollowUp {
    if (type != DocType.quotation) return false;
    if (followUpDone) return false;
    if (status == DocStatus.accepted || status == DocStatus.converted ||
        status == DocStatus.rejected) return false;
    final now = DateTime.now();
    if (followUpDate != null) {
      return !now.isBefore(followUpDate!);
    }
    // Default: 3 days after creation
    return now.isAfter(date.add(const Duration(days: 3)));
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'refNo': refNo,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'clientId': clientId,
        'termsId': termsId,
        'termsSnapshot': termsSnapshot?.toMap(),
        'includeTerms': includeTerms,
        'profileId': profileId,
        'lineItems': lineItems.map((e) => e.toMap()).toList(),
        'headerNotes': headerNotes,
        'specNotes': specNotes,
        'introText': introText,
        'siteLocation': siteLocation,
        'internalNotes': internalNotes,
        'gstPercent': gstPercent,
        'includePO': includePO,
        'poInName': poInName,
        'poPercent': poPercent,
        'amountPaid': amountPaid,
        'status': status.name,
        'followUpDate': followUpDate?.toIso8601String(),
        'followUpDone': followUpDone,
      };

  factory QuoteDoc.fromMap(Map<dynamic, dynamic> m) {
    var status = DocStatus.values.firstWhere(
        (e) => e.name == m['status'], orElse: () => DocStatus.draft);
    if (status == DocStatus.overdue) status = DocStatus.sent;

    return QuoteDoc(
      id: m['id'],
      type: DocType.values.firstWhere((e) => e.name == m['type'],
          orElse: () => DocType.quotation),
      refNo: m['refNo'] ?? '',
      date: DateTime.parse(m['date']),
      dueDate: m['dueDate'] != null ? DateTime.parse(m['dueDate']) : null,
      clientId: m['clientId'] ?? '',
      termsId: m['termsId'] ?? '',
      termsSnapshot: m['termsSnapshot'] != null
          ? TermsPreset.fromMap(Map<dynamic, dynamic>.from(m['termsSnapshot']))
          : null,
      includeTerms: m['includeTerms'] ?? true,
      profileId: m['profileId'] ?? '',
      lineItems: (m['lineItems'] as List? ?? [])
          .map((e) => LineItem.fromMap(e))
          .toList(),
      headerNotes: List<String>.from(m['headerNotes'] ?? []),
      specNotes: List<String>.from(m['specNotes'] ?? []),
      introText: m['introText'] ?? '',
      siteLocation: m['siteLocation'] ?? '',
      internalNotes: m['internalNotes'] ?? '',
      gstPercent: (m['gstPercent'] ?? 18).toDouble(),
      includePO: m['includePO'] ?? false,
      poInName: m['poInName'] ?? '',
      poPercent: (m['poPercent'] ?? 0).toDouble(),
      amountPaid: (m['amountPaid'] ?? 0).toDouble(),
      status: status,
      followUpDate: m['followUpDate'] != null
          ? DateTime.tryParse(m['followUpDate'])
          : null,
      followUpDone: m['followUpDone'] ?? false,
    );
  }
}
