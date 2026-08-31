import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../services/image_filter_service.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';
import '../services/watermark_service.dart';
import '../services/signature_service.dart';
import '../services/filter_preview.dart';
import 'signature_pad_screen.dart';

enum _EditTool { filters, adjust, watermark, sign }

/// Step 2 of 3: Edit. One big live preview of the focused page, a filmstrip
/// to switch pages or reorder/delete, and a bottom tool switcher so only
/// one control group is visible at a time instead of everything stacked
/// on one screen.
class EditDocumentScreen extends StatefulWidget {
  final List<String> pages;
  const EditDocumentScreen({super.key, required this.pages});

  @override
  State<EditDocumentScreen> createState() => _EditDocumentScreenState();
}

class _EditDocumentScreenState extends State<EditDocumentScreen> {
  late List<String> _pages;
  int _focusedIndex = 0;
  _EditTool _tool = _EditTool.filters;

  ScanFilter _selectedFilter = ScanFilter.original;
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;

  bool _addWatermark = false;
  final _watermarkController = TextEditingController();
  final _titleController = TextEditingController();

  bool _saving = false;

  final _filterService = ImageFilterService();
  final _pdfService = PdfService();
  final _ocrService = OcrService();
  final _watermarkService = WatermarkService();
  final _signatureService = SignatureService();

  @override
  void initState() {
    super.initState();
    _pages = List<String>.from(widget.pages);
    _titleController.text = 'Scan_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    _titleController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  void _removePage(int index) {
    setState(() {
      _pages.removeAt(index);
      if (_focusedIndex >= _pages.length) _focusedIndex = _pages.length - 1;
      if (_focusedIndex < 0) _focusedIndex = 0;
    });
  }

  Future<void> _signFocusedPage() async {
    final bytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (bytes == null) return;

    setState(() => _saving = true);
    try {
      final signedPath = await _signatureService.applySignature(_pages[_focusedIndex], bytes);
      setState(() => _pages[_focusedIndex] = signedPath);
    } catch (e) {
      _showError('Could not add signature: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    if (_pages.isEmpty) {
      _showError('No pages left to save.');
      return;
    }
    final title = _titleController.text.trim().isEmpty
        ? 'Scan_${DateTime.now().millisecondsSinceEpoch}'
        : _titleController.text.trim();

    setState(() => _saving = true);
    try {
      final filteredPaths = <String>[];
      for (final path in _pages) {
        var filtered = await _filterService.applyFilter(
          path,
          _selectedFilter,
          brightness: _brightness,
          contrast: _contrast,
          saturation: _saturation,
        );
        if (_addWatermark && _watermarkController.text.trim().isNotEmpty) {
          filtered = await _watermarkService.applyWatermark(filtered, _watermarkController.text.trim());
        }
        filteredPaths.add(filtered);
      }

      final pdfPath = await _pdfService.generatePdfFromImages(filteredPaths, fileName: title);
      final ocrText = await _ocrService.extractTextFromPages(filteredPaths);

      final doc = ScannedDocument(
        id: const Uuid().v4(),
        title: title,
        pageImagePaths: filteredPaths,
        pdfPath: pdfPath,
        ocrText: ocrText,
        createdAt: DateTime.now(),
        appliedFilter: _selectedFilter.name,
      );

      if (!mounted) return;
      await context.read<DocumentProvider>().addDocument(doc);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError('Failed to save document: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit')),
        body: const Center(child: Text('No pages left. Go back and scan again.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final previewFilter = FilterPreview.matrixFor(
      _selectedFilter,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
    );

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Document title',
          ),
        ),
      ),
      body: Column(
        children: [
          // Big live preview of the focused page.
          Expanded(
            child: Container(
              width: double.infinity,
              color: scheme.surfaceContainerLow,
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColorFiltered(
                  colorFilter: previewFilter,
                  child: Image.file(
                    File(_pages[_focusedIndex]),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
          ),

          // Filmstrip: switch focused page, delete bad ones.
          SizedBox(
            height: 74,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              itemBuilder: (context, i) {
                final selected = i == _focusedIndex;
                return GestureDetector(
                  onTap: () => setState(() => _focusedIndex = i),
                  child: Container(
                    width: 54,
                    margin: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: selected ? scheme.primary : Colors.black12,
                                  width: selected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Image.file(File(_pages[i]), fit: BoxFit.cover),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 1,
                          right: 1,
                          child: GestureDetector(
                            onTap: () => _removePage(i),
                            child: const CircleAvatar(
                              radius: 9,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 1),

          // Tool switcher — only one panel visible at a time.
          Container(
            color: scheme.surface,
            child: Row(
              children: [
                _ToolTab(
                  icon: Icons.auto_fix_high,
                  label: 'Filters',
                  selected: _tool == _EditTool.filters,
                  onTap: () => setState(() => _tool = _EditTool.filters),
                ),
                _ToolTab(
                  icon: Icons.tune,
                  label: 'Adjust',
                  selected: _tool == _EditTool.adjust,
                  onTap: () => setState(() => _tool = _EditTool.adjust),
                ),
                _ToolTab(
                  icon: Icons.branding_watermark_outlined,
                  label: 'Stamp',
                  selected: _tool == _EditTool.watermark,
                  onTap: () => setState(() => _tool = _EditTool.watermark),
                ),
                _ToolTab(
                  icon: Icons.draw_outlined,
                  label: 'Sign',
                  selected: _tool == _EditTool.sign,
                  onTap: () => setState(() => _tool = _EditTool.sign),
                ),
              ],
            ),
          ),

          // Active tool panel.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            constraints: const BoxConstraints(minHeight: 96),
            child: _buildToolPanel(scheme),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving...' : 'Save Document'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolPanel(ColorScheme scheme) {
    switch (_tool) {
      case _EditTool.filters:
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(ScanFilter.original, 'Original', Icons.image_outlined, scheme),
              _filterChip(ScanFilter.grayscale, 'B&W', Icons.contrast, scheme),
              _filterChip(ScanFilter.magicColor, 'Magic Color', Icons.auto_fix_high, scheme),
              _filterChip(ScanFilter.autoEnhance, 'HD Enhance', Icons.auto_awesome, scheme),
            ],
          ),
        );

      case _EditTool.adjust:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _slider(Icons.brightness_6_outlined, 'Brightness', _brightness,
                (v) => setState(() => _brightness = v)),
            _slider(Icons.contrast, 'Contrast', _contrast, (v) => setState(() => _contrast = v)),
            _slider(
                Icons.palette_outlined, 'Color', _saturation, (v) => setState(() => _saturation = v)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _brightness = 0;
                  _contrast = 0;
                  _saturation = 0;
                }),
                child: const Text('Reset'),
              ),
            ),
          ],
        );

      case _EditTool.watermark:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _addWatermark,
              onChanged: (v) => setState(() => _addWatermark = v),
              title: const Text('Add watermark / stamp'),
            ),
            if (_addWatermark)
              TextField(
                controller: _watermarkController,
                decoration: const InputDecoration(
                  hintText: 'e.g. CONFIDENTIAL',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
          ],
        );

      case _EditTool.sign:
        return Center(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.draw_outlined),
            label: Text('Sign Page ${_focusedIndex + 1}'),
            onPressed: _saving ? null : _signFocusedPage,
          ),
        );
    }
  }

  Widget _filterChip(ScanFilter filter, String label, IconData icon, ColorScheme scheme) {
    final selected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(IconData icon, String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
            ],
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: -100,
            max: 100,
            divisions: 40,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 34, child: Text(value.round().toString(), textAlign: TextAlign.end)),
      ],
    );
  }
}

class _ToolTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToolTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2.5),
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
