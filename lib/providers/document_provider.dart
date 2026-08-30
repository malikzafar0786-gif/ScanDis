import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';
import '../services/storage_service.dart';

class DocumentProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<ScannedDocument> _documents = [];
  String _searchQuery = '';
  bool isLoading = false;

  List<ScannedDocument> get documents {
    if (_searchQuery.isEmpty) return _documents;
    return _documents
        .where((d) =>
            d.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            d.ocrText.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> loadDocuments() async {
    isLoading = true;
    notifyListeners();
    _documents = _storage.getAllDocuments();
    isLoading = false;
    notifyListeners();
  }

  Future<void> addDocument(ScannedDocument doc) async {
    await _storage.saveDocument(doc);
    await loadDocuments();
  }

  Future<void> updateDocument(ScannedDocument doc) async {
    await _storage.saveDocument(doc); // Hive put() overwrites by key
    await loadDocuments();
  }

  Future<void> deleteDocument(String id) async {
    await _storage.deleteDocument(id);
    await loadDocuments();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}
