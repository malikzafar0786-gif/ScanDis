import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/glass_card.dart';
import 'scanner_screen.dart';
import 'document_detail_screen.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, ScannedDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('"${doc.title}" will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<DocumentProvider>().deleteDocument(doc.id);
    }
  }

  void _openScanner(BuildContext context, {int? pageLimit, String? presetTitle, String label = 'New Scan'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          pageLimitOverride: pageLimit,
          presetTitlePrefix: presetTitle,
          appBarLabel: label,
        ),
      ),
    );
  }

  Future<void> _openQrScanner(BuildContext context) async {
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Scanned Result'),
          content: SelectableText(result),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ScanDis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: GlassCard(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Smart Search',
                    prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic_none_outlined, color: scheme.onSurfaceVariant, size: 20),
                          const SizedBox(width: 6),
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: scheme.primary,
                            child: Text('AI',
                                style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.bold, color: scheme.onPrimary)),
                          ),
                        ],
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => context.read<DocumentProvider>().setSearchQuery(v),
                ),
              ),
            ),
          ),

          // Quick-action shortcuts
          SliverToBoxAdapter(
            child: SizedBox(
              height: 92,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                scrollDirection: Axis.horizontal,
                children: [
                  _QuickAction(
                    icon: Icons.document_scanner_outlined,
                    label: 'Document',
                    onTap: () => _openScanner(context, label: 'Scan Document'),
                  ),
                  _QuickAction(
                    icon: Icons.badge_outlined,
                    label: 'ID Card',
                    onTap: () => _openScanner(context,
                        pageLimit: 2, presetTitle: 'ID_Card', label: 'Scan ID Card (front & back)'),
                  ),
                  _QuickAction(
                    icon: Icons.menu_book_outlined,
                    label: 'Multi-page',
                    onTap: () => _openScanner(context, presetTitle: 'Document', label: 'Scan Multi-page'),
                  ),
                  _QuickAction(
                    icon: Icons.qr_code_scanner_outlined,
                    label: 'QR / Barcode',
                    onTap: () => _openQrScanner(context),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'All',
                      icon: Icons.grid_view_rounded,
                      selected: docProvider.activeFolder == null && !docProvider.favoritesOnly,
                      onTap: () {
                        docProvider.setActiveFolder(null);
                        docProvider.setFavoritesOnly(false);
                      },
                    ),
                    _FilterChip(
                      label: 'Favorites',
                      icon: Icons.star_outline,
                      selected: docProvider.favoritesOnly,
                      onTap: () {
                        docProvider.setActiveFolder(null);
                        docProvider.setFavoritesOnly(!docProvider.favoritesOnly);
                      },
                    ),
                    for (final folder in docProvider.folders)
                      _FilterChip(
                        label: folder,
                        icon: Icons.folder_outlined,
                        selected: docProvider.activeFolder == folder,
                        onTap: () {
                          docProvider.setFavoritesOnly(false);
                          docProvider.setActiveFolder(
                              docProvider.activeFolder == folder ? null : folder);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Text('Gallery', style: Theme.of(context).textTheme.titleMedium),
            ),
          ),

          if (docProvider.isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (docProvider.documents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyHomeState(onScan: () => _openScanner(context)),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final doc = docProvider.documents[index];
                    return _DocumentTile(
                      doc: doc,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: doc.id)),
                      ),
                      onDelete: () => _confirmDelete(context, doc),
                    );
                  },
                  childCount: docProvider.documents.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Scan'),
        onPressed: () => _openScanner(context),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 74,
        child: GlassCard(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.symmetric(vertical: 10),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.primary, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final ScannedDocument doc;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _DocumentTile({required this.doc, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbPath = doc.pageImagePaths.isNotEmpty ? doc.pageImagePaths.first : null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbPath != null
                      ? Image.file(File(thumbPath), fit: BoxFit.cover)
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.description_outlined, size: 40, color: scheme.onSurfaceVariant),
                        ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        child: const Icon(Icons.delete_outline, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: GestureDetector(
                      onTap: () => context.read<DocumentProvider>().toggleFavorite(doc),
                      child: CircleAvatar(
                        radius: 13,
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        child: Icon(
                          doc.isFavorite ? Icons.star : Icons.star_outline,
                          size: 15,
                          color: doc.isFavorite ? scheme.primary : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${doc.pageImagePaths.length}p',
                        style: TextStyle(fontSize: 10, color: scheme.onPrimary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              color: scheme.surface.withValues(alpha: 0.7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doc.folder ?? DateFormat.MMMd().format(doc.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: Icon(icon, size: 16),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: selected ? scheme.primary : scheme.onSurfaceVariant, fontSize: 12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyHomeState({required this.onScan});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.folder_open_outlined, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text('No scans yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Use a shortcut above or tap "Scan" below to capture your first document.',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a Document'),
              onPressed: onScan,
            ),
          ],
        ),
      ),
    );
  }
}
