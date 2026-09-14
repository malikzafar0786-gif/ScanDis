import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';

class _PassportSize {
  final String label;
  final double widthMm;
  final double heightMm;
  const _PassportSize(this.label, this.widthMm, this.heightMm);
}

const List<_PassportSize> _kSizes = [
  _PassportSize('Pakistan / NADRA (35×45mm)', 35, 45),
  _PassportSize('US Passport (2×2 in)', 50.8, 50.8),
  _PassportSize('UK / Schengen (35×45mm)', 35, 45),
  _PassportSize('India (35×45mm)', 35, 45),
];

const double _kPrintDpi = 300;

class PassportPhotoScreen extends StatefulWidget {
  const PassportPhotoScreen({super.key});

  @override
  State<PassportPhotoScreen> createState() => _PassportPhotoScreenState();
}

class _PassportPhotoScreenState extends State<PassportPhotoScreen> {
  final _picker = ImagePicker();
  final GlobalKey _cropBoundaryKey = GlobalKey();

  String? _sourcePath;
  _PassportSize _selectedSize = _kSizes[0];
  Uint8List? _finalPhoto;
  Uint8List? _printSheet;
  bool _processing = false;

  double get _aspectRatio => _selectedSize.widthMm / _selectedSize.heightMm;

  Future<void> _pickImage() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final photo = await _picker.pickImage(source: choice, imageQuality: 95);
    if (photo == null) return;
    setState(() {
      _sourcePath = photo.path;
      _finalPhoto = null;
      _printSheet = null;
    });
  }

  Future<void> _cropAndGenerate() async {
    setState(() => _processing = true);
    try {
      final boundary =
          _cropBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final capturedImage = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await capturedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Could not capture crop');

      final targetWidth = (_selectedSize.widthMm / 25.4 * _kPrintDpi).round();
      final targetHeight = (_selectedSize.heightMm / 25.4 * _kPrintDpi).round();

      final decoded = img.decodePng(byteData.buffer.asUint8List());
      if (decoded == null) throw Exception('Could not decode captured crop');
      final resized = img.copyResize(decoded, width: targetWidth, height: targetHeight);

      setState(() {
        _finalPhoto = Uint8List.fromList(img.encodeJpg(resized, quality: 95));
        _printSheet = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Crop failed: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _generatePrintSheet() async {
    if (_finalPhoto == null) return;
    setState(() => _processing = true);
    try {
      final photo = img.decodeJpg(_finalPhoto!);
      if (photo == null) throw Exception('Could not decode photo');

      const sheetWidthPx = 4 * 300;
      const sheetHeightPx = 6 * 300;
      const margin = 20;
      const spacing = 12;

      final cols = ((sheetWidthPx - margin * 2) / (photo.width + spacing)).floor().clamp(1, 20);
      final rows = ((sheetHeightPx - margin * 2) / (photo.height + spacing)).floor().clamp(1, 20);

      final sheet = img.Image(width: sheetWidthPx, height: sheetHeightPx, numChannels: 3);
      img.fill(sheet, color: img.ColorRgb8(255, 255, 255));

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final x = margin + c * (photo.width + spacing);
          final y = margin + r * (photo.height + spacing);
          img.compositeImage(sheet, photo, dstX: x, dstY: y);
        }
      }

      setState(() => _printSheet = Uint8List.fromList(img.encodeJpg(sheet, quality: 95)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print sheet failed: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _share(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${const Uuid().v4()}_$name.jpg';
    await File(path).writeAsBytes(bytes);
    await Share.shareXFiles([XFile(path)], text: name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Passport Photo Maker')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<_PassportSize>(
              value: _selectedSize,
              decoration: const InputDecoration(labelText: 'Photo size', border: OutlineInputBorder()),
              items: _kSizes
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (s) => setState(() {
                _selectedSize = s!;
                _finalPhoto = null;
                _printSheet = null;
              }),
            ),
            const SizedBox(height: 16),
            if (_sourcePath == null)
              Container(
                height: 320,
                decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
                child: Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Choose a Face Photo'),
                    onPressed: _pickImage,
                  ),
                ),
              )
            else ...[
              Text('Pinch/drag to position your face inside the frame:',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: _aspectRatio,
                child: RepaintBoundary(
                  key: _cropBoundaryKey,
                  child: ClipRect(
                    child: Container(
                      color: Colors.grey.shade900,
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.file(File(_sourcePath!), fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: _pickImage, child: const Text('Change Photo')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _processing ? null : _cropAndGenerate,
                      child: _processing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Crop Photo'),
                    ),
                  ),
                ],
              ),
            ],
            if (_finalPhoto != null) ...[
              const SizedBox(height: 20),
              Text('Result', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Center(
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: scheme.outline)),
                  child: Image.memory(_finalPhoto!, height: 180),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share Photo'),
                      onPressed: () => _share(_finalPhoto!, 'passport_photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.grid_view_outlined),
                      label: const Text('Print Sheet'),
                      onPressed: _processing ? null : _generatePrintSheet,
                    ),
                  ),
                ],
              ),
            ],
            if (_printSheet != null) ...[
              const SizedBox(height: 20),
              Text('4×6" Print Sheet (multiple copies)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Image.memory(_printSheet!),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share Print Sheet'),
                onPressed: () => _share(_printSheet!, 'passport_print_sheet'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
