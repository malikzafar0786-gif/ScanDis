import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ScanFilter { original, grayscale, magicColor, autoEnhance }

class ManualAdjustments {
  final double brightness;
  final double contrast;
  final double saturation;
  final double highlights;
  final double shadows;
  final double blacks;
  final double whites;

  const ManualAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.blacks = 0,
    this.whites = 0,
  });
}

class _FilterParams {
  final Uint8List bytes;
  final ScanFilter filter;
  final ManualAdjustments adjustments;
  _FilterParams(this.bytes, this.filter, this.adjustments);
}

class ImageFilterService {
  final _uuid = const Uuid();

  /// Applies the chosen preset filter plus manual tone adjustments, and
  /// saves a NEW file, returning its path. The original scanned file is
  /// left untouched.
  ///
  /// All the actual pixel work happens on a background isolate (via
  /// compute()) so it can never freeze the UI thread — this is what fixes
  /// the intermittent "hangs then crashes" issue during Save.
  Future<String> applyFilter(
    String sourcePath,
    ScanFilter filter, {
    double brightness = 0,
    double contrast = 0,
    double saturation = 0,
    double highlights = 0,
    double shadows = 0,
    double blacks = 0,
    double whites = 0,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final adjustments = ManualAdjustments(
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      highlights: highlights,
      shadows: shadows,
      blacks: blacks,
      whites: whites,
    );

    final jpegBytes = await compute(_processInBackground, _FilterParams(bytes, filter, adjustments));

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_filtered.jpg';
    await File(outPath).writeAsBytes(jpegBytes);
    return outPath;
  }
}

/// Runs on a background isolate. Must be top-level/static — no access to
/// `this` or instance state.
Uint8List _processInBackground(_FilterParams params) {
  img.Image? image = img.decodeImage(params.bytes);
  if (image == null) {
    throw Exception('Could not decode image');
  }

  switch (params.filter) {
    case ScanFilter.original:
      break;

    case ScanFilter.grayscale:
      image = img.grayscale(image);
      image = img.normalize(image, min: 0, max: 255);
      image = img.adjustColor(image, contrast: 1.35, brightness: 1.05);

    case ScanFilter.magicColor:
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.6, brightness: 1.1);

    case ScanFilter.autoEnhance:
      image = img.gaussianBlur(image, radius: 1);
      image = img.normalize(image, min: 0, max: 255);
      image = img.adjustColor(image, contrast: 1.25, saturation: 1.05);
      image = img.convolution(
        image,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        div: 1,
      );
  }

  final adj = params.adjustments;

  if (adj.brightness != 0 || adj.contrast != 0 || adj.saturation != 0) {
    image = img.adjustColor(
      image,
      brightness: 1.0 + (adj.brightness / 100) * 0.6,
      contrast: 1.0 + (adj.contrast / 100) * 0.6,
      saturation: 1.0 + (adj.saturation / 100) * 0.6,
    );
  }

  // Highlights/Shadows/Blacks/Whites — tone-region curve via a 256-entry
  // lookup table. Each control only affects its own tonal range (a
  // triangular weight peaking there and fading to zero outside it), like
  // the equivalent sliders in Photoshop/Lightroom.
  if (adj.highlights != 0 || adj.shadows != 0 || adj.blacks != 0 || adj.whites != 0) {
    final lut = List<int>.generate(256, (v) {
      double offset = 0;
      offset += adj.shadows * 0.5 * _triangleWeight(v, 32, 64);
      offset += adj.highlights * 0.5 * _triangleWeight(v, 224, 64);
      offset += adj.blacks * 0.5 * _triangleWeight(v, 0, 80);
      offset += adj.whites * 0.5 * _triangleWeight(v, 255, 80);
      return (v + offset).round().clamp(0, 255);
    });

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        image.setPixelRgba(
          x,
          y,
          lut[p.r.round().clamp(0, 255)],
          lut[p.g.round().clamp(0, 255)],
          lut[p.b.round().clamp(0, 255)],
          p.a.round(),
        );
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

double _triangleWeight(int value, int center, int width) {
  final w = 1 - (value - center).abs() / width;
  return w.clamp(0.0, 1.0);
}
