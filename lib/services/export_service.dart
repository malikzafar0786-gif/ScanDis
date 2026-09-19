import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum ExportImageFormat { jpeg, png }

class ExportService {
  /// Returns individual page image file paths, ready to share directly
  /// (no ZIP wrapper) — JPEG pages are used as-is; PNG converts each page
  /// to its own .png file first. This is what normal sharing (WhatsApp,
  /// email, etc.) should use, since a "photo.jpg.zip" file confuses most
  /// users compared to just receiving the actual image files.
  Future<List<String>> getShareablePageFiles(
    List<String> pageImagePaths, {
    ExportImageFormat format = ExportImageFormat.jpeg,
  }) async {
    if (format == ExportImageFormat.jpeg) return pageImagePaths;

    final dir = await getApplicationDocumentsDirectory();
    final result = <String>[];
    for (int i = 0; i < pageImagePaths.length; i++) {
      final file = File(pageImagePaths[i]);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final pngBytes = await compute(_convertToPng, bytes);
      final outPath = '${dir.path}/page_${i + 1}_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(pngBytes);
      result.add(outPath);
    }
    return result;
  }

  /// Bundles all page images of a document into a single ZIP file — kept
  /// as an explicit "Download All as ZIP" option for bulk saving, not the
  /// default for ordinary sharing.
  Future<String> exportPagesAsZip(
    String documentTitle,
    List<String> pageImagePaths, {
    ExportImageFormat format = ExportImageFormat.jpeg,
  }) async {
    final archive = Archive();

    for (int i = 0; i < pageImagePaths.length; i++) {
      final file = File(pageImagePaths[i]);
      if (!await file.exists()) continue;
      Uint8List bytes = await file.readAsBytes();
      String ext = pageImagePaths[i].split('.').last;

      if (format == ExportImageFormat.png) {
        // Decode/re-encode happens on a background isolate so converting
        // several full-resolution pages never freezes the UI.
        bytes = await compute(_convertToPng, bytes);
        ext = 'png';
      }

      archive.addFile(ArchiveFile('page_${i + 1}.$ext', bytes.length, bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Failed to create ZIP archive');
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = documentTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final suffix = format == ExportImageFormat.png ? '_png' : '_jpg';
    final outPath = '${dir.path}/$safeTitle$suffix.zip';
    await File(outPath).writeAsBytes(zipBytes);
    return outPath;
  }

  /// Saves the OCR text as a plain .txt file, ready to share.
  Future<String> exportTextFile(String documentTitle, String text) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = documentTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final outPath = '${dir.path}/$safeTitle.txt';
    await File(outPath).writeAsString(text);
    return outPath;
  }
}

Uint8List _convertToPng(Uint8List jpegBytes) {
  final image = img.decodeImage(jpegBytes);
  if (image == null) return jpegBytes;
  return Uint8List.fromList(img.encodePng(image));
}
