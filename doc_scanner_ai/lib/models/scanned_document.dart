import 'package:hive/hive.dart';

part 'scanned_document.g.dart';

// Run: flutter pub run build_runner build --delete-conflicting-outputs
// to generate scanned_document.g.dart

@HiveType(typeId: 0)
class ScannedDocument extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  List<String> pageImagePaths; // local paths of individual scanned pages

  @HiveField(3)
  String? pdfPath; // path of generated PDF

  @HiveField(4)
  String ocrText; // extracted text (all pages combined)

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  String appliedFilter; // 'original' | 'grayscale' | 'magic'

  ScannedDocument({
    required this.id,
    required this.title,
    required this.pageImagePaths,
    this.pdfPath,
    this.ocrText = '',
    required this.createdAt,
    this.appliedFilter = 'original',
  });
}
