import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../services/gemini_service.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../services/signature_digitizer_service.dart';
import '../services/signature_service.dart';
import '../services/reminder_service.dart';
import '../services/ocr_service.dart';
import 'package:uuid/uuid.dart';

const List<String> kDocumentCategories = [
  'Bills', 'ID Cards', 'Receipts', 'Notes', 'Reports', 'Contracts', 'Other',
];

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _gemini = GeminiService();
  final _chatController = TextEditingController();
  final _exportService = ExportService();
  final _pdfService = PdfService();
  final _digitizer = SignatureDigitizerService();
  final _signatureService = SignatureService();
  final _ocrService = OcrService();
  final _picker = ImagePicker();

  bool _aiLoading = false;
  String? _aiResult;
  bool _exporting = false;
  bool _toolBusy = false;

  Map<String, String>? _nameSuggestion; // {title, category}
  Map<String, String?>? _billInfo; // {amount, dueDate}

  @override
  void dispose() {
    _chatController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _exportAs(dynamic doc, String choice) async {
    setState(() => _exporting = true);
    try {
      switch (choice) {
        case 'pdf':
          if (doc.pdfPath == null) {
            _showError('No PDF available for this document.');
            return;
          }
          await Printing.sharePdf(
            bytes: File(doc.pdfPath!).readAsBytesSync(),
            filename: '${doc.title}.pdf',
          );
        case 'jpeg':
          final zipPath = await _exportService.exportPagesAsZip(
            doc.title, doc.pageImagePaths,
            format: ExportImageFormat.jpeg,
          );
          await Share.shareXFiles([XFile(zipPath)], text: '${doc.title} — JPEG pages');
        case 'png':
          final zipPath = await _exportService.exportPagesAsZip(
            doc.title, doc.pageImagePaths,
            format: ExportImageFormat.png,
          );
          await Share.shareXFiles([XFile(zipPath)], text: '${doc.title} — PNG pages');
        case 'text':
          final txtPath = await _exportService.exportTextFile(doc.title, doc.ocrText);
          await Share.shareXFiles([XFile(txtPath)], text: '${doc.title} — extracted text');
      }
    } catch (e) {
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _runAiAction(Future<String> Function() action) async {
    setState(() {
      _aiLoading = true;
      _aiResult = null;
      _nameSuggestion = null;
      _billInfo = null;
    });
    try {
      final result = await action();
      setState(() => _aiResult = result);
    } on GeminiException catch (e) {
      setState(() => _aiResult = '⚠️ ${e.message}');
    } catch (e) {
      setState(() => _aiResult = '⚠️ Unexpected error: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  Future<void> _suggestNameCategory(String ocrText) async {
    setState(() {
      _aiLoading = true;
      _aiResult = null;
      _nameSuggestion = null;
      _billInfo = null;
    });
    try {
      final suggestion = await _gemini.suggestTitleAndCategory(ocrText);
      setState(() => _nameSuggestion = suggestion);
    } on GeminiException catch (e) {
      setState(() => _aiResult = '⚠️ ${e.message}');
    } catch (e) {
      setState(() => _aiResult = '⚠️ Unexpected error: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  Future<void> _extractBillInfo(String ocrText) async {
    setState(() {
      _aiLoading = true;
      _aiResult = null;
      _nameSuggestion = null;
      _billInfo = null;
    });
    try {
      final info = await _gemini.extractBillInfo(ocrText);
      setState(() => _billInfo = info);
    } on GeminiException catch (e) {
      setState(() => _aiResult = '⚠️ ${e.message}');
    } catch (e) {
      setState(() => _aiResult = '⚠️ Unexpected error: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  Future<void> _applySuggestion(dynamic doc) async {
    if (_nameSuggestion == null) return;
    doc.title = _nameSuggestion!['title'] ?? doc.title;
    final category = _nameSuggestion!['category'];
    if (category != null && kDocumentCategories.contains(category)) {
      doc.folder = category;
    }
    await context.read<DocumentProvider>().updateDocument(doc);
    if (!mounted) return;
    setState(() => _nameSuggestion = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Applied.')));
  }

  Future<void> _scheduleReminder(dynamic doc) async {
    final dueDateStr = _billInfo?['dueDate'];
    if (dueDateStr == null) return;
    DateTime? dueDate;
    try {
      dueDate = DateTime.parse(dueDateStr);
    } catch (_) {
      _showError('Could not understand the date "$dueDateStr" — try setting it manually.');
      return;
    }

    await ReminderService.requestPermission();
    await ReminderService.scheduleBillReminder(
      documentId: doc.id,
      title: doc.title,
      dueDate: dueDate,
    );
    doc.billAmount = _billInfo?['amount'];
    doc.billDueDate = dueDate;
    await context.read<DocumentProvider>().updateDocument(doc);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder set for ${dueDate.toLocal().toString().split(' ').first}')),
    );
  }

  Future<void> _compressPdf(dynamic doc) async {
    setState(() => _toolBusy = true);
    try {
      final newPath = await _pdfService.compressPdf(doc.pageImagePaths, fileName: doc.title);
      doc.pdfPath = newPath;
      await context.read<DocumentProvider>().updateDocument(doc);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF compressed.')));
    } catch (e) {
      _showError('Compression failed: $e');
    } finally {
      if (mounted) setState(() => _toolBusy = false);
    }
  }

  Future<void> _digitizeSignatureFromPhoto(dynamic doc) async {
    final photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    setState(() => _toolBusy = true);
    try {
      final pngBytes = await _digitizer.digitizeFromPhoto(photo.path);
      if (doc.pageImagePaths.isEmpty) {
        _showError('No pages to apply the signature to.');
        return;
      }
      final signedPath = await _signatureService.applySignature(doc.pageImagePaths.first, pngBytes);
      doc.pageImagePaths[0] = signedPath;
      final newPdf = await _pdfService.generatePdfFromImages(doc.pageImagePaths, fileName: doc.title);
      doc.pdfPath = newPdf;
      await context.read<DocumentProvider>().updateDocument(doc);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Signature digitized and applied to page 1.')));
    } catch (e) {
      _showError('Could not digitize signature: $e');
    } finally {
      if (mounted) setState(() => _toolBusy = false);
    }
  }

  Future<void> _removePagesDialog(dynamic doc) async {
    if (doc.pageImagePaths.length <= 1) {
      _showError('This document only has one page.');
      return;
    }
    final toRemove = <int>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Remove Pages'),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 6, mainAxisSpacing: 6),
              itemCount: doc.pageImagePaths.length,
              itemBuilder: (context, i) {
                final selected = toRemove.contains(i);
                return GestureDetector(
                  onTap: () => setDialogState(
                      () => selected ? toRemove.remove(i) : toRemove.add(i)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: selected ? 0.35 : 1,
                          child: Image.file(File(doc.pageImagePaths[i]), fit: BoxFit.cover),
                        ),
                      ),
                      if (selected)
                        const Center(child: Icon(Icons.delete_outline, color: Colors.red)),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: toRemove.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Remove Selected'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || toRemove.isEmpty) return;
    if (toRemove.length >= doc.pageImagePaths.length) {
      _showError('Cannot remove all pages from a document.');
      return;
    }

    setState(() => _toolBusy = true);
    try {
      final remaining = <String>[
        for (int i = 0; i < doc.pageImagePaths.length; i++)
          if (!toRemove.contains(i)) doc.pageImagePaths[i],
      ];
      doc.pageImagePaths = remaining;
      doc.pdfPath = await _pdfService.generatePdfFromImages(remaining, fileName: doc.title);
      doc.ocrText = await _ocrService.extractTextFromPages(remaining);
      await context.read<DocumentProvider>().updateDocument(doc);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${toRemove.length} page(s) removed.')));
    } catch (e) {
      _showError('Could not remove pages: $e');
    } finally {
      if (mounted) setState(() => _toolBusy = false);
    }
  }

  Future<void> _mergeWithAnotherDocument(dynamic doc) async {
    final others =
        context.read<DocumentProvider>().documents.where((d) => d.id != doc.id).toList();
    if (others.isEmpty) {
      _showError('No other documents to merge with.');
      return;
    }

    final chosen = await showModalBottomSheet<dynamic>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Merge with which document?', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final other in others)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(other.title),
                subtitle: Text('${other.pageImagePaths.length} pages'),
                onTap: () => Navigator.pop(sheetContext, other),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    setState(() => _toolBusy = true);
    try {
      final mergedPages = <String>[...doc.pageImagePaths, ...chosen.pageImagePaths];
      final mergedTitle = 'Merged_${doc.title}_${chosen.title}';
      final pdfPath = await _pdfService.generatePdfFromImages(mergedPages, fileName: mergedTitle);
      final ocrText = await _ocrService.extractTextFromPages(mergedPages);

      final merged = ScannedDocument(
        id: const Uuid().v4(),
        title: mergedTitle,
        pageImagePaths: mergedPages,
        pdfPath: pdfPath,
        ocrText: ocrText,
        createdAt: DateTime.now(),
      );
      await context.read<DocumentProvider>().addDocument(merged);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Merged into a new document.')));
    } catch (e) {
      _showError('Merge failed: $e');
    } finally {
      if (mounted) setState(() => _toolBusy = false);
    }
  }

  Future<void> _pickFolder(dynamic doc) async {
    final choice = await showModalBottomSheet<String?>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('No folder'),
              onTap: () => Navigator.pop(sheetContext, null),
            ),
            for (final category in kDocumentCategories)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(category),
                onTap: () => Navigator.pop(sheetContext, category),
              ),
          ],
        ),
      ),
    );
    doc.folder = choice;
    await context.read<DocumentProvider>().updateDocument(doc);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final matches = docProvider.documents.where((d) => d.id == widget.documentId);
    final doc = matches.isNotEmpty ? matches.first : null;

    if (doc == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(doc.title),
          bottom: const TabBar(tabs: [
            Tab(text: 'Preview'),
            Tab(text: 'OCR Text'),
            Tab(text: 'AI Actions'),
            Tab(text: 'Tools'),
          ]),
          actions: [
            IconButton(
              icon: Icon(doc.isFavorite ? Icons.star : Icons.star_outline),
              tooltip: 'Favorite',
              onPressed: () => docProvider.toggleFavorite(doc),
            ),
            IconButton(
              icon: const Icon(Icons.folder_outlined),
              tooltip: 'Move to folder',
              onPressed: () => _pickFolder(doc),
            ),
            if (_exporting)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share_outlined),
                tooltip: 'Export',
                onSelected: (choice) => _exportAs(doc, choice),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF'))),
                  const PopupMenuItem(
                      value: 'jpeg', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Images (JPEG, ZIP)'))),
                  const PopupMenuItem(
                      value: 'png', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Images (PNG, ZIP)'))),
                  const PopupMenuItem(
                      value: 'text', child: ListTile(leading: Icon(Icons.text_snippet_outlined), title: Text('Text (.txt)'))),
                ],
              ),
          ],
        ),
        body: TabBarView(
          children: [
            // ---- Preview tab ----
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: doc.pageImagePaths.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(doc.pageImagePaths[i])),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---- OCR Text tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('Copy'),
                      onPressed: doc.ocrText.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: doc.ocrText));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
                            },
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      doc.ocrText.isEmpty ? 'No text detected.' : doc.ocrText,
                    ),
                  ),
                ],
              ),
            ),

            // ---- AI Actions tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('AI Tools', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.6,
                    children: [
                      _AiActionCard(
                        icon: Icons.summarize_outlined,
                        label: 'Summarize',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.summarize(doc.ocrText)),
                      ),
                      _AiActionCard(
                        icon: Icons.language,
                        label: 'AI OCR (Urdu/Arabic)',
                        enabled: !_aiLoading && doc.pageImagePaths.isNotEmpty,
                        onTap: () =>
                            _runAiAction(() => _gemini.extractTextFromImage(doc.pageImagePaths.first)),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → Urdu',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Urdu')),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → English',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'English')),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → Spanish',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Spanish')),
                      ),
                      _AiActionCard(
                        icon: Icons.auto_awesome_outlined,
                        label: 'Suggest Name & Folder',
                        enabled: !_aiLoading,
                        onTap: () => _suggestNameCategory(doc.ocrText),
                      ),
                      _AiActionCard(
                        icon: Icons.receipt_long_outlined,
                        label: 'Extract Bill Info',
                        enabled: !_aiLoading,
                        onTap: () => _extractBillInfo(doc.ocrText),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Text('Chat with this document', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: InputDecoration(
                            hintText: 'Ask a question about this document...',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: _aiLoading || _chatController.text.trim().isEmpty
                            ? null
                            : () => _runAiAction(
                                () => _gemini.chatWithDocument(doc.ocrText, _chatController.text.trim())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_aiLoading) const Center(child: CircularProgressIndicator()),
                  if (_nameSuggestion != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Suggested title: ${_nameSuggestion!['title']}'),
                          Text('Suggested folder: ${_nameSuggestion!['category']}'),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: () => _applySuggestion(doc),
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  if (_billInfo != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Amount: ${_billInfo!['amount'] ?? 'Not found'}'),
                          Text('Due date: ${_billInfo!['dueDate'] ?? 'Not found'}'),
                          if (_billInfo!['dueDate'] != null) ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              icon: const Icon(Icons.notifications_active_outlined),
                              label: const Text('Set Reminder'),
                              onPressed: () => _scheduleReminder(doc),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_aiResult != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: SelectableText(_aiResult!),
                    ),
                ],
              ),
            ),

            // ---- Tools tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('PDF Tools', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ListTile(
                    tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.compress_outlined),
                    title: const Text('Compress PDF'),
                    subtitle: const Text('Reduce file size for easier sharing'),
                    trailing: _toolBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _toolBusy ? null : () => _compressPdf(doc),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: const Text('Remove Pages'),
                    subtitle: const Text('Delete unwanted pages from this document'),
                    trailing: _toolBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _toolBusy ? null : () => _removePagesDialog(doc),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.merge_outlined),
                    title: const Text('Merge with Another Document'),
                    subtitle: const Text('Combine pages into one new document'),
                    trailing: _toolBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _toolBusy ? null : () => _mergeWithAnotherDocument(doc),
                  ),
                  const SizedBox(height: 20),
                  Text('Signature', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  ListTile(
                    tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: const Text('Digitize Paper Signature'),
                    subtitle: const Text('Photograph a signature — background removed, applied to page 1'),
                    trailing: _toolBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _toolBusy ? null : () => _digitizeSignatureFromPhoto(doc),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _AiActionCard({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: enabled ? scheme.primary : scheme.outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: enabled ? scheme.onSurface : scheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
