import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/document_provider.dart';
import '../services/reminder_service.dart';
import 'document_detail_screen.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final withReminders = docProvider.allDocuments.where((d) => d.billDueDate != null).toList()
      ..sort((a, b) => a.billDueDate!.compareTo(b.billDueDate!));

    return Scaffold(
      appBar: AppBar(title: const Text('Bill Reminders')),
      body: withReminders.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No reminders set yet.\nOpen a scanned bill → AI Actions → "Extract Bill Info" → "Set Reminder".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: withReminders.length,
              itemBuilder: (context, i) {
                final doc = withReminders[i];
                final overdue = doc.billDueDate!.isBefore(DateTime.now());
                return ListTile(
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    color: overdue ? Colors.red : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(doc.title),
                  subtitle: Text(
                    '${doc.billAmount ?? 'Amount unknown'} — due ${DateFormat.yMMMd().format(doc.billDueDate!)}'
                    '${overdue ? ' (overdue)' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel reminder',
                    onPressed: () async {
                      await ReminderService.cancelReminder(doc.id);
                      doc.billDueDate = null;
                      doc.billAmount = null;
                      await context.read<DocumentProvider>().updateDocument(doc);
                    },
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: doc.id)),
                  ),
                );
              },
            ),
    );
  }
}
