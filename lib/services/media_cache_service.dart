import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:convert';

class MediaCacheService {
  static final MediaCacheService _instance = MediaCacheService._internal();
  factory MediaCacheService() => _instance;
  MediaCacheService._internal();

  Future<String> _getCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/media_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  String _generateCacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<File?> getCachedMedia(String url) async {
    try {
      final cacheDir = await _getCacheDir();
      final cacheKey = _generateCacheKey(url);
      final file = File('$cacheDir/$cacheKey');
      
      if (await file.exists()) {
        // Check if file is older than 7 days
        final lastModified = await file.lastModified();
        final age = DateTime.now().difference(lastModified);
        if (age.inDays > 7) {
          await file.delete();
          return null;
        }
        return file;
      }
    } catch (e) {
      debugPrint('Error getting cached media: $e');
    }
    return null;
  }

  Future<File?> cacheMedia(String url) async {
    try {
      final cached = await getCachedMedia(url);
      if (cached != null) return cached;

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final cacheDir = await _getCacheDir();
        final cacheKey = _generateCacheKey(url);
        final file = File('$cacheDir/$cacheKey');
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      debugPrint('Error caching media: $e');
    }
    return null;
  }

  Future<void> clearOldCache() async {
    try {
      final cacheDir = await _getCacheDir();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        final cutoff = DateTime.now().subtract(const Duration(days: 7));
        
        for (final entity in entities) {
          if (entity is File) {
            final lastModified = await entity.lastModified();
            if (lastModified.isBefore(cutoff)) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error clearing old media cache: $e');
    }
  }

  Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDir();
      final dir = Directory(cacheDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing media cache: $e');
    }
  }
}
