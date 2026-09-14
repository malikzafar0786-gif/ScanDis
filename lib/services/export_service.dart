import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum ExportImageFormat { jpeg, png }

class ExportService {
  /// Bundles all page images of a document into a single ZIP file, either
  /// as-is (JPEG, the format pages are already saved in) or converted to
  /// PNG, and returns the ZIP's path, ready to share.
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
