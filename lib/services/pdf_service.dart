import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PdfService {
  final _uuid = const Uuid();

  /// Combines multiple page images into a single PDF file.
  /// Returns the saved PDF's local file path.
  Future<String> generatePdfFromImages(List<String> imagePaths, {String? fileName, int jpegQuality = 92}) async {
    final pdf = pw.Document();

    for (final path in imagePaths) {
      final imageBytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(imageBytes);
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'scan_${_uuid.v4()}';
    final outPath = '${dir.path}/$name.pdf';
    final file = File(outPath);
    await file.writeAsBytes(await pdf.save());
    return outPath;
  }

  /// Merges the page images of several documents (in the given order) into
  /// one new combined PDF. Operates on the underlying page images rather
  /// than the PDF bytes directly, since Dart's `pdf` package is a writer,
  /// not a general-purpose PDF editor.
  Future<String> mergeDocuments(List<List<String>> documentsPageLists, {String? fileName}) async {
    final allPages = documentsPageLists.expand((pages) => pages).toList();
    return generatePdfFromImages(allPages, fileName: fileName ?? 'Merged_${_uuid.v4()}');
  }

  /// Produces a new PDF containing only the pages at [pageIndexesToKeep]
  /// (0-based, in the order given) — used for "extract pages" / "remove
  /// pages" tools.
  Future<String> extractPages(
    List<String> allPageImagePaths,
    List<int> pageIndexesToKeep, {
    String? fileName,
  }) async {
    final selected = pageIndexesToKeep
        .where((i) => i >= 0 && i < allPageImagePaths.length)
        .map((i) => allPageImagePaths[i])
        .toList();
    return generatePdfFromImages(selected, fileName: fileName ?? 'Extracted_${_uuid.v4()}');
  }

  /// Re-encodes the page images at a lower JPEG quality and regenerates
  /// the PDF, trading some visual quality for a smaller file size.
  /// [quality] 1-100 (lower = smaller file, more compression artifacts).
  Future<String> compressPdf(List<String> pageImagePaths, {int quality = 55, String? fileName}) async {
    final dir = await getApplicationDocumentsDirectory();
    final compressedPaths = <String>[];

    for (final path in pageImagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        compressedPaths.add(path);
        continue;
      }
      final outPath = '${dir.path}/${_uuid.v4()}_compressed.jpg';
      await File(outPath).writeAsBytes(img.encodeJpg(image, quality: quality));
      compressedPaths.add(outPath);
    }

    return generatePdfFromImages(compressedPaths, fileName: fileName ?? 'Compressed_${_uuid.v4()}');
  }
}
