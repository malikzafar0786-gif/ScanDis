import 'package:flutter/foundation.dart';
import '../models/scanned_document.dart';
import '../services/storage_service.dart';

class DocumentProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<ScannedDocument> _documents = [];
  String _searchQuery = '';
  String? _activeFolder; // null = "All"
  bool _favoritesOnly = false;
  bool isLoading = false;

  List<ScannedDocument> get documents {
    Iterable<ScannedDocument> result = _documents;

    if (_activeFolder != null) {
      result = result.where((d) => d.folder == _activeFolder);
    }
    if (_favoritesOnly) {
      result = result.where((d) => d.isFavorite);
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((d) =>
          d.title.toLowerCase().contains(q) ||
          d.ocrText.toLowerCase().contains(q) ||
          d.tags.any((t) => t.toLowerCase().contains(q)));
    }
    return result.toList();
  }

  /// Distinct folder names currently in use, for the folder chips UI.
  List<String> get folders {
    final set = <String>{};
    for (final d in _documents) {
      if (d.folder != null && d.folder!.isNotEmpty) set.add(d.folder!);
    }
    final list = set.toList()..sort();
    return list;
  }

  String? get activeFolder => _activeFolder;
  bool get favoritesOnly => _favoritesOnly;

  void setActiveFolder(String? folder) {
    _activeFolder = folder;
    notifyListeners();
  }

  void setFavoritesOnly(bool value) {
    _favoritesOnly = value;
    notifyListeners();
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

  Future<void> toggleFavorite(ScannedDocument doc) async {
    doc.isFavorite = !doc.isFavorite;
    await updateDocument(doc);
  }

  Future<void> setFolder(ScannedDocument doc, String? folder) async {
    doc.folder = folder;
    await updateDocument(doc);
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
