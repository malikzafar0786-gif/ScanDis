import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../services/image_filter_service.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';
import '../services/gemini_service.dart';
import '../services/watermark_service.dart';
import '../services/signature_service.dart';
import '../services/signature_digitizer_service.dart';
import '../services/filter_preview.dart';
import 'signature_pad_screen.dart';
import 'package:image_picker/image_picker.dart';

enum _EditTool { filters, adjust, watermark, sign, ai }

/// Step 2 of 3: Edit. One big live preview of the focused page, a filmstrip
/// to switch pages or reorder/delete, and a bottom tool switcher so only
/// one control group is visible at a time instead of everything stacked
/// on one screen.
class EditDocumentScreen extends StatefulWidget {
  final List<String> pages;
  final String? initialTitle;
  /// When editing an already-saved document, pass its id so Save updates
  /// that document in place instead of creating a new one.
  final String? existingDocumentId;
  final ScanFilter? initialFilter;
  const EditDocumentScreen({
    super.key,
    required this.pages,
    this.initialTitle,
    this.existingDocumentId,
    this.initialFilter,
  });

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
  double _highlights = 0;
  double _shadows = 0;
  double _blacks = 0;
  double _whites = 0;

  bool _addWatermark = false;
  bool _addTimestamp = false;
  final _watermarkController = TextEditingController();
  final _titleController = TextEditingController();

  bool _saving = false;

  final _filterService = ImageFilterService();
  final _pdfService = PdfService();
  final _ocrService = OcrService();
  final _watermarkService = WatermarkService();
  final _signatureService = SignatureService();
  final _digitizer = SignatureDigitizerService();
  final _gemini = GeminiService();
  final _picker = ImagePicker();

  // Pre-save AI: OCR is run on-demand (not automatically) so AI actions
  // are usable from this same screen instead of only after Save.
  String? _preSaveOcrText;
  bool _extractingText = false;
  bool _aiLoading = false;
  String? _aiResult;
  final _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pages = List<String>.from(widget.pages);
    _titleController.text =
        widget.initialTitle ?? 'Scan_${DateTime.now().millisecondsSinceEpoch}';
    if (widget.initialFilter != null) {
      _selectedFilter = widget.initialFilter!;
    }
  }

  @override
  void dispose() {
    _watermarkController.dispose();
    _titleController.dispose();
    _chatController.dispose();
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

  Future<void> _digitizeSignatureFromPhoto() async {
    final photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    setState(() => _saving = true);
    try {
      final pngBytes = await _digitizer.digitizeFromPhoto(photo.path);
      final signedPath = await _signatureService.applySignature(_pages[_focusedIndex], pngBytes);
      setState(() => _pages[_focusedIndex] = signedPath);
    } catch (e) {
      _showError('Could not digitize signature: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _extractTextForAi() async {
    setState(() => _extractingText = true);
    try {
      final text = await _ocrService.extractTextFromPages(_pages);
      setState(() => _preSaveOcrText = text);
    } catch (e) {
      _showError('Text extraction failed: $e');
    } finally {
      if (mounted) setState(() => _extractingText = false);
    }
  }

  Future<void> _runAiAction(Future<String> Function() action) async {
    setState(() {
      _aiLoading = true;
      _aiResult = null;
    });
    try {
      final result = await action();
      setState(() => _aiResult = result);
    } on GeminiException catch (e) {
      setState(() => _aiResult = '⚠️ ${e.message}');
    } catch (e) {
      setState(() => _aiResult = '⚠️ Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
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
          highlights: _highlights,
          shadows: _shadows,
          blacks: _blacks,
          whites: _whites,
        );
        if (_addWatermark && _watermarkController.text.trim().isNotEmpty) {
          filtered = await _watermarkService.applyWatermark(filtered, _watermarkController.text.trim());
        }
        if (_addTimestamp) {
          filtered = await _watermarkService.applyTimestamp(filtered, DateTime.now());
        }
        filteredPaths.add(filtered);
      }

      final pdfPath = await _pdfService.generatePdfFromImages(filteredPaths, fileName: title);
      final ocrText = await _ocrService.extractTextFromPages(filteredPaths);

      if (!mounted) return;
      final docProvider = context.read<DocumentProvider>();

      ScannedDocument doc;
      if (widget.existingDocumentId != null) {
        // Preserve folder/favorite/tags/bill info from the original —
        // re-editing should only change what this screen actually touches
        // (pages, filter, title), not silently wipe organization metadata.
        final existing = docProvider.documents.where((d) => d.id == widget.existingDocumentId);
        final original = existing.isNotEmpty ? existing.first : null;
        doc = ScannedDocument(
          id: widget.existingDocumentId!,
          title: title,
          pageImagePaths: filteredPaths,
          pdfPath: pdfPath,
          ocrText: ocrText,
          createdAt: original?.createdAt ?? DateTime.now(),
          appliedFilter: _selectedFilter.name,
          folder: original?.folder,
          isFavorite: original?.isFavorite ?? false,
          tags: original?.tags,
          billAmount: original?.billAmount,
          billDueDate: original?.billDueDate,
        );
        await docProvider.updateDocument(doc);
      } else {
        doc = ScannedDocument(
          id: const Uuid().v4(),
          title: title,
          pageImagePaths: filteredPaths,
          pdfPath: pdfPath,
          ocrText: ocrText,
          createdAt: DateTime.now(),
          appliedFilter: _selectedFilter.name,
        );
        await docProvider.addDocument(doc);
      }
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
      highlights: _highlights,
      shadows: _shadows,
      blacks: _blacks,
      whites: _whites,
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
                _ToolTab(
                  icon: Icons.auto_awesome,
                  label: 'AI',
                  selected: _tool == _EditTool.ai,
                  onTap: () => setState(() => _tool = _EditTool.ai),
                ),
              ],
            ),
          ),

          // Active tool panel.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            constraints: const BoxConstraints(minHeight: 96, maxHeight: 320),
            child: SingleChildScrollView(child: _buildToolPanel(scheme)),
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
            _slider(Icons.wb_sunny_outlined, 'Highlights', _highlights,
                (v) => setState(() => _highlights = v)),
            _slider(Icons.nightlight_outlined, 'Shadows', _shadows,
                (v) => setState(() => _shadows = v)),
            _slider(Icons.circle, 'Blacks', _blacks, (v) => setState(() => _blacks = v)),
            _slider(Icons.circle_outlined, 'Whites', _whites, (v) => setState(() => _whites = v)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  _brightness = 0;
                  _contrast = 0;
                  _saturation = 0;
                  _highlights = 0;
                  _shadows = 0;
                  _blacks = 0;
                  _whites = 0;
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _addTimestamp,
              onChanged: (v) => setState(() => _addTimestamp = v),
              title: const Text('Add scan date/time stamp'),
              subtitle: const Text('Small tag in the bottom-right corner'),
            ),
          ],
        );

      case _EditTool.sign:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.draw_outlined),
              label: Text('Draw Signature — Page ${_focusedIndex + 1}'),
              onPressed: _saving ? null : _signFocusedPage,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text('Photo of Paper Signature — Page ${_focusedIndex + 1}'),
              onPressed: _saving ? null : _digitizeSignatureFromPhoto,
            ),
          ],
        );

      case _EditTool.ai:
        return _buildAiPanel(scheme);
    }
  }

  Widget _buildAiPanel(ColorScheme scheme) {
    if (_preSaveOcrText == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Extract text once to enable AI tools (Summarize, Translate, Chat) before saving.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: _extractingText
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.text_fields),
            label: Text(_extractingText ? 'Extracting...' : 'Extract Text'),
            onPressed: _extractingText ? null : _extractTextForAi,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _aiChip('Summarize', Icons.summarize_outlined,
                () => _runAiAction(() => _gemini.summarize(_preSaveOcrText!))),
            _aiChip('→ Urdu', Icons.translate_outlined,
                () => _runAiAction(() => _gemini.translate(_preSaveOcrText!, 'Urdu'))),
            _aiChip('→ English', Icons.translate_outlined,
                () => _runAiAction(() => _gemini.translate(_preSaveOcrText!, 'English'))),
            _aiChip('→ Spanish', Icons.translate_outlined,
                () => _runAiAction(() => _gemini.translate(_preSaveOcrText!, 'Spanish'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                decoration: const InputDecoration(
                  hintText: 'Ask a question about this document...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send, size: 18),
              onPressed: _aiLoading || _chatController.text.trim().isEmpty
                  ? null
                  : () => _runAiAction(
                      () => _gemini.chatWithDocument(_preSaveOcrText!, _chatController.text.trim())),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_aiLoading) const Center(child: CircularProgressIndicator()),
        if (_aiResult != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _aiResult!));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
                    },
                  ),
                ),
                SelectableText(_aiResult!),
              ],
            ),
          ),
      ],
    );
  }

  Widget _aiChip(String label, IconData icon, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: _aiLoading ? null : onTap,
    );
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
