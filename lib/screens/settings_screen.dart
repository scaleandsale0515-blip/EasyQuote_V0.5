import 'package:flutter/material.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import 'login_password_screen.dart';
import 'pdf_templates_screen.dart';
import 'export_data_screen.dart';
import 'app_terms_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _followUpEnabled = true;

  @override
  void initState() {
    super.initState();
    _followUpEnabled = LocalDB.instance.getFollowUpEnabled();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _tile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF Templates',
            subtitle: 'Choose the layout for your Quotation & Invoice PDFs',
            onTap: () => _push(const PdfTemplatesScreen()),
          ),
          _tile(
            icon: Icons.lock_person_outlined,
            label: 'Login ID & Password',
            subtitle: 'Set a personal login for daily access',
            onTap: () => _push(const LoginPasswordScreen()),
          ),
          _tile(
            icon: Icons.table_chart_outlined,
            label: 'Export Data',
            subtitle: 'Export quotations & invoices to Excel',
            onTap: () => _push(const ExportDataScreen()),
          ),
          const Divider(height: 24),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined, color: AppColors.blueprint),
              title: const Text('Quotation Follow-up Reminders',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Show a reminder on the Dashboard 3 days after a quotation is created, '
                'so you never forget to follow up with a client.',
                style: TextStyle(fontSize: 12),
              ),
              value: _followUpEnabled,
              onChanged: (v) async {
                await LocalDB.instance.setFollowUpEnabled(v);
                setState(() => _followUpEnabled = v);
              },
            ),
          ),
          const Divider(height: 24),
          _tile(
            icon: Icons.gavel_outlined,
            label: 'Terms & Conditions',
            subtitle: 'App legal terms (for Play Store)',
            onTap: () => _push(const AppTermsScreen()),
          ),
        ],
      ),
    );
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Widget _tile({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: AppColors.blueprint),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
