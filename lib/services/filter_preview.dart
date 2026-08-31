import 'package:flutter/material.dart';
import 'image_filter_service.dart';

/// Produces approximate ColorFilter matrices so the UI can show a live
/// preview of each filter directly on the thumbnail (cheap, GPU-side),
/// without re-processing the actual image file until Save is tapped.
class FilterPreview {
  static ColorFilter matrixFor(
    ScanFilter filter, {
    double brightness = 0,
    double contrast = 0,
    double saturation = 0,
  }) {
    List<double> m;
    switch (filter) {
      case ScanFilter.original:
        m = _identity();
      case ScanFilter.grayscale:
        m = _grayscale(contrastBoost: 1.35);
      case ScanFilter.magicColor:
        m = _grayscale(contrastBoost: 1.6, brightnessBoost: 15);
      case ScanFilter.autoEnhance:
        m = _saturate(1.15);
    }

    if (brightness != 0 || contrast != 0 || saturation != 0) {
      m = _multiplyMatrices(m, _manualAdjust(brightness, contrast, saturation));
    }

    return ColorFilter.matrix(m);
  }

  static List<double> _identity() => [
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];

  static List<double> _grayscale({double contrastBoost = 1.0, double brightnessBoost = 0}) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final c = contrastBoost;
    final t = 128 * (1 - c) + brightnessBoost;
    return [
      r * c, g * c, b * c, 0, t,
      r * c, g * c, b * c, 0, t,
      r * c, g * c, b * c, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _saturate(double s) {
    const rL = 0.2126, gL = 0.7152, bL = 0.0722;
    final ir = (1 - s) * rL, ig = (1 - s) * gL, ib = (1 - s) * bL;
    return [
      ir + s, ig, ib, 0, 0,
      ir, ig + s, ib, 0, 0,
      ir, ig, ib + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  static List<double> _manualAdjust(double brightness, double contrast, double saturation) {
    // Must match ImageFilterService's mapping exactly so the live preview
    // matches what actually gets saved.
    final c = 1.0 + (contrast / 100) * 0.6;
    final s = 1.0 + (saturation / 100) * 0.6;
    final b = (brightness / 100) * 0.6 * 255; // additive approximation for the matrix

    final contrastT = 128 * (1 - c);
    const rL = 0.2126, gL = 0.7152, bL = 0.0722;
    final ir = (1 - s) * rL, ig = (1 - s) * gL, ib = (1 - s) * bL;

    return [
      c * (ir + s), c * ig, c * ib, 0, contrastT + b,
      c * ir, c * (ig + s), c * ib, 0, contrastT + b,
      c * ir, c * ig, c * (ib + s), 0, contrastT + b,
      0, 0, 0, 1, 0,
    ];
  }

  /// Approximate 4x5 matrix composition (applies [second] after [first]).
  static List<double> _multiplyMatrices(List<double> first, List<double> second) {
    List<double> result = List.filled(20, 0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 5; col++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += second[row * 5 + k] * first[k * 5 + col];
        }
        if (col == 4) sum += second[row * 5 + 4];
        result[row * 5 + col] = sum;
      }
    }
    return result;
  }
}
