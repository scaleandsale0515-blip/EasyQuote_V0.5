import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/quote_doc.dart';
import '../storage/local_db.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'client_form_screen.dart';
import 'client_history_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Client> _allClients = [];
  Map<String, double> _outstandingByClient = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final clients = LocalDB.instance.getClients()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Compute outstanding balance per client from all invoices.
    final docs = LocalDB.instance.getDocuments();
    final outstanding = <String, double>{};
    for (final d in docs) {
      if (d.type != DocType.invoice) continue;
      if (d.status == DocStatus.paid) continue;
      if (d.balanceDue <= 0) continue;
      outstanding[d.clientId] = (outstanding[d.clientId] ?? 0) + d.balanceDue;
    }

    setState(() {
      _allClients = clients;
      _outstandingByClient = outstanding;
    });
  }

  List<Client> get _filtered {
    if (_query.trim().isEmpty) return _allClients;
    final q = _query.trim().toLowerCase();
    return _allClients.where((c) =>
        c.companyName.toLowerCase().contains(q) ||
        c.contactPerson.toLowerCase().contains(q) ||
        c.phone.contains(q)).toList();
  }

  Future<void> _openHistory(Client c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientHistoryScreen(client: c)),
    );
    _reload();
  }

  Future<void> _openForm({Client? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientFormScreen(existing: existing)),
    );
    _reload();
  }

  Future<void> _confirmDelete(Client c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete client?'),
        content: Text('Remove "${c.companyName}" from this device. This can\'t be undone.'),
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
      await LocalDB.instance.deleteClient(c.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search by name, contact or phone',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: clients.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 48, color: AppColors.line),
                          const SizedBox(height: 12),
                          Text(
                            _allClients.isEmpty ? 'No clients yet' : 'No clients match your search',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (_allClients.isEmpty)
                            const Text('Tap + to add your first client.',
                                style: TextStyle(color: AppColors.inkSoft)),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: clients.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = clients[i];
                      final outstanding = _outstandingByClient[c.id] ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text(
                            c.companyName.isEmpty ? '(unnamed)' : c.companyName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  if (c.contactPerson.isNotEmpty) c.contactPerson,
                                  if (c.phone.isNotEmpty) c.phone,
                                ].join('  •  '),
                              ),
                              if (outstanding > 0)
                                Text(
                                  'Outstanding: ${formatRupees(outstanding)}',
                                  style: const TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _openHistory(c),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                            onPressed: () => _confirmDelete(c),
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
}
