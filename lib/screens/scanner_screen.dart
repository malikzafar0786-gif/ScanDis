import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'edit_document_screen.dart';

// Raise this if you want more pages per document. flutter_doc_scanner has
// no hard cap of its own.
const int kMaxScanPages = 50;

/// Step 1 of 3: Capture. Purely responsible for scanning pages, reordering,
/// and removing bad shots. All visual editing (filters/adjust/watermark/
/// signature) happens on the next screen, EditDocumentScreen — keeping this
/// screen focused and uncluttered.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<String> _capturedPages = [];
  bool _scanning = false;

  /// The plugin's native return shape varies by version/platform: it can
  /// come back as a custom `ImageScanResult` object (with an `.images`
  /// getter), a Map, a plain List, or a single String path. This handles
  /// all of them instead of assuming one shape and crashing on the others.
  /// It also normalizes "file://..." URIs to plain filesystem paths, since
  /// File() cannot open a URI string directly.
  String _normalizePath(String raw) {
    if (raw.startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {
        return raw.replaceFirst('file://', '');
      }
    }
    return raw;
  }

  List<String> _extractPaths(dynamic result) {
    if (result == null) return [];

    try {
      final dynamic images = (result as dynamic).images;
      if (images is List && images.isNotEmpty) {
        return images.map((e) => _normalizePath(e.toString())).toList();
      }
    } catch (_) {
      // Not that shape — fall through.
    }

    if (result is String) return [_normalizePath(result)];
    if (result is List) return result.map((e) => _normalizePath(e.toString())).toList();

    if (result is Map) {
      for (final key in ['images', 'Uri', 'uri', 'paths', 'imagePaths']) {
        final value = result[key];
        if (value is List) return value.map((e) => _normalizePath(e.toString())).toList();
        if (value is String) return [_normalizePath(value)];
      }
    }

    return [];
  }

  Future<void> _startScan() async {
    if (_capturedPages.length >= kMaxScanPages) {
      _showError('Maximum $kMaxScanPages pages reached for one document.');
      return;
    }

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _showError('Camera permission is required to scan documents.');
      return;
    }

    setState(() => _scanning = true);
    try {
      final remaining = kMaxScanPages - _capturedPages.length;
      final dynamic result =
          await FlutterDocScanner().getScannedDocumentAsImages(page: remaining);
      final paths = _extractPaths(result);
      if (paths.isNotEmpty) {
        setState(() => _capturedPages.addAll(paths));
      }
    } catch (e) {
      _showError('Scanning failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _removePage(int index) => setState(() => _capturedPages.removeAt(index));

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _goToEdit() async {
    if (_capturedPages.isEmpty) {
      _showError('Scan at least one page first.');
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditDocumentScreen(pages: List<String>.from(_capturedPages)),
      ),
    );
    if (saved == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('New Scan  •  ${_capturedPages.length}/$kMaxScanPages pages'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _capturedPages.isEmpty
                ? _EmptyCaptureState(scanning: _scanning, onScan: _startScan)
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _capturedPages.length,
                    itemBuilder: (context, i) => _PageThumb(
                      path: _capturedPages[i],
                      index: i,
                      onRemove: () => _removePage(i),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: _scanning
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_a_photo_outlined),
                      label: Text(_capturedPages.isEmpty ? 'Scan First Page' : 'Add Page'),
                      onPressed: _scanning ? null : _startScan,
                    ),
                  ),
                  if (_capturedPages.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Edit & Save'),
                        onPressed: _goToEdit,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCaptureState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;
  const _EmptyCaptureState({required this.scanning, required this.onScan});

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
              child: Icon(Icons.document_scanner_outlined, size: 48, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text('Scan your first page',
                style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Point your camera at a document. Edges are detected automatically.',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageThumb extends StatelessWidget {
  final String path;
  final int index;
  final VoidCallback onRemove;
  const _PageThumb({required this.path, required this.index, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: CircleAvatar(
            radius: 10,
            backgroundColor: Colors.black54,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
