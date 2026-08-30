import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ScanFilter { original, grayscale, magicColor, autoEnhance }

class ImageFilterService {
  final _uuid = const Uuid();

  /// Applies the chosen preset filter, then optional manual adjustments
  /// (brightness/contrast/saturation, each -100..100, 0 = no change),
  /// and saves a NEW file, returning its path. The original scanned file
  /// is left untouched.
  Future<String> applyFilter(
    String sourcePath,
    ScanFilter filter, {
    double brightness = 0,
    double contrast = 0,
    double saturation = 0,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Could not decode image at $sourcePath');
    }

    switch (filter) {
      case ScanFilter.original:
        break;

      case ScanFilter.grayscale:
        // Document-style B&W: grayscale + contrast-stretch so text goes
        // near-black and the page background goes near-white, instead of
        // the previous flat/muddy plain grayscale.
        image = img.grayscale(image);
        image = img.normalize(image, min: 0, max: 255);
        image = img.adjustColor(image, contrast: 1.35, brightness: 1.05);

      case ScanFilter.magicColor:
        image = img.grayscale(image);
        image = img.adjustColor(image, contrast: 1.6, brightness: 1.1);

      case ScanFilter.autoEnhance:
        // "AI Enhance / HD": denoise -> contrast-stretch -> sharpen, aimed
        // at making scanned text crisp and readable without distortion.
        image = img.gaussianBlur(image, radius: 1); // light denoise
        image = img.normalize(image, min: 0, max: 255); // full dynamic range
        image = img.adjustColor(image, contrast: 1.25, saturation: 1.05);
        image = img.convolution(
          image,
          filter: [0, -1, 0, -1, 5, -1, 0, -1, 0], // sharpen kernel
          div: 1,
        );
    }

    // Manual fine-tuning on top of the preset (sliders in the UI map
    // -100..100 to the multiplier ranges adjustColor expects).
    if (brightness != 0 || contrast != 0 || saturation != 0) {
      image = img.adjustColor(
        image,
        brightness: 1.0 + (brightness / 100),
        contrast: 1.0 + (contrast / 100),
        saturation: 1.0 + (saturation / 100),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_filtered.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(image, quality: 95));
    return outPath;
  }
}
