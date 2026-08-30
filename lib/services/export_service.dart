import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class ExportService {
  /// Bundles all page images of a document into a single ZIP file and
  /// returns its path, ready to share.
  Future<String> exportPagesAsZip(String documentTitle, List<String> pageImagePaths) async {
    final archive = Archive();

    for (int i = 0; i < pageImagePaths.length; i++) {
      final file = File(pageImagePaths[i]);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final ext = pageImagePaths[i].split('.').last;
      archive.addFile(ArchiveFile('page_${i + 1}.$ext', bytes.length, bytes));
    }

    final zipBytes = ZipEncoder().encode(archive);

    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = documentTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final outPath = '${dir.path}/$safeTitle.zip';
    await File(outPath).writeAsBytes(zipBytes);
    return outPath;
  }
}
