import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  String? _result;
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null) return;
    setState(() {
      _result = value;
      _handled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR / Barcode')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _handled
                ? const Center(child: Icon(Icons.check_circle, color: Colors.green, size: 64))
                : MobileScanner(onDetect: _onDetect),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _result == null
                  ? const Text('Point the camera at a QR code or barcode')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Result:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SelectableText(_result!),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() {
                                  _result = null;
                                  _handled = false;
                                }),
                                child: const Text('Scan Again'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.pop(context, _result),
                                child: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
