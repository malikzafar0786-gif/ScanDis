import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ScanFilter { original, grayscale, magicColor }

class ImageFilterService {
  final _uuid = const Uuid();

  /// Applies the chosen filter and saves a NEW file, returning its path.
  /// The original scanned file is left untouched.
  Future<String> applyFilter(String sourcePath, ScanFilter filter) async {
    final bytes = await File(sourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Could not decode image at $sourcePath');
    }

    switch (filter) {
      case ScanFilter.original:
        // no-op, just re-encode
        break;
      case ScanFilter.grayscale:
        image = img.grayscale(image);
        break;
      case ScanFilter.magicColor:
        // "Magic Color": grayscale + boosted contrast + brightness
        // simulates a high-contrast document scan look
        image = img.grayscale(image);
        image = img.adjustColor(image, contrast: 1.6, brightness: 1.1);
        break;
    }

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_filtered.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(image, quality: 92));
    return outPath;
  }
}
