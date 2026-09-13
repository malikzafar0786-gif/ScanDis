import 'package:hive_flutter/hive_flutter.dart';
import '../models/scanned_document.dart';

class StorageService {
  static const String boxName = 'documents_box';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ScannedDocumentAdapter());
    await Hive.openBox<ScannedDocument>(boxName);
  }

  Box<ScannedDocument> get _box => Hive.box<ScannedDocument>(boxName);

  List<ScannedDocument> getAllDocuments() {
    final docs = _box.values.toList();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  Future<void> saveDocument(ScannedDocument doc) async {
    await _box.put(doc.id, doc);
  }

  Future<void> deleteDocument(String id) async {
    await _box.delete(id);
  }

  ScannedDocument? getDocument(String id) => _box.get(id);
}
