import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryService {
  static final WatchHistoryService _instance = WatchHistoryService._internal();
  factory WatchHistoryService() => _instance;
  
  WatchHistoryService._internal() {
    _init();
  }

  static const String _key = 'watch_history';
  final _controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _current = [];

  Stream<List<Map<String, dynamic>>> get historyStream => _controller.stream;
  List<Map<String, dynamic>> get current => _current;

  Future<void> _init() async {
    _current = await getHistory();
    _controller.add(_current);
  }

  // Save progress
  Future<void> saveProgress({
    required int tmdbId,
    String? imdbId,
    required String title,
    required String posterPath,
    required String method, // 'stream', 'torrent', 'amri', or 'stremio_direct'
    required String sourceId, // extraction source or magnet link
    required int position, // milliseconds
    required int duration, // milliseconds
    int? season,
    int? episode,
    String? episodeTitle,
    String? magnetLink, // Full magnet link for torrents
    int? fileIndex, // File index for multi-file torrents
    String? streamUrl, // Direct stream URL (for stremio_direct)
    String? stremioId, // Custom Stremio item ID
    String? stremioAddonBaseUrl, // Addon base URL for re-fetching
    String? stremioType, // 'movie' or 'series'
    String? mediaType, // 'movie' or 'tv'
  }) async {
    // Determine unique ID for this item to prevent duplicates
    // For movies: tmdbId
    // For episodes: tmdbId_S{season}_E{episode}
    final String uniqueId = season != null && episode != null 
        ? '${tmdbId}_S${season}_E$episode' 
        : '$tmdbId';

    final entry = {
      'uniqueId': uniqueId,
      'tmdbId': tmdbId,
      'imdbId': imdbId,
      'title': title,
      'posterPath': posterPath,
      'method': method,
      'sourceId': sourceId,
      'position': position,
      'duration': duration,
      'season': season,
      'episode': episode,
      'episodeTitle': episodeTitle,
      'magnetLink': magnetLink, // Save full magnet link
      'fileIndex': fileIndex, // Save file index
      'streamUrl': streamUrl, // Save direct stream URL
      'stremioId': stremioId, // Save stremio item ID
      'stremioAddonBaseUrl': stremioAddonBaseUrl, // Save addon base URL
      'stremioType': stremioType, // Save stremio type
      'mediaType': mediaType, // Save media type
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_key);
      List<dynamic> list = jsonString != null ? json.decode(jsonString) : [];

      // Remove existing entry with same uniqueId
      list.removeWhere((item) => item['uniqueId'] == uniqueId);

      // Add new entry to the beginning
      list.insert(0, entry);

      // Optional: Limit history size (e.g., 50 items)
      if (list.length > 50) {
        list = list.sublist(0, 50);
      }

      await prefs.setString(_key, json.encode(list));
      debugPrint('[WatchHistory] Saved progress for $title ($uniqueId) at $position ms');
      debugPrint('[WatchHistory] Method: $method, MagnetLink: ${magnetLink?.substring(0, 50)}..., FileIndex: $fileIndex');
      
      // Emit update
      _current = list.cast<Map<String, dynamic>>();
      _controller.add(_current);
    } catch (e) {
      debugPrint('[WatchHistory] Error saving progress: $e');
    }
  }

  // Get all history
  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_key);
      if (jsonString == null) return [];
      
      final List<dynamic> list = json.decode(jsonString);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[WatchHistory] Error fetching history: $e');
      return [];
    }
  }

  // Get specific item progress
  Future<Map<String, dynamic>?> getProgress(int tmdbId, {int? season, int? episode}) async {
    final String uniqueId = season != null && episode != null 
        ? '${tmdbId}_S${season}_E$episode' 
        : '$tmdbId';
    
    try {
      final history = await getHistory();
      final match = history.firstWhere(
        (item) => item['uniqueId'] == uniqueId,
        orElse: () => {},
      );
      return match.isNotEmpty ? match : null;
    } catch (e) {
      return null;
    }
  }

  // Remove item
  Future<void> removeItem(String uniqueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_key);
      if (jsonString == null) return;

      List<dynamic> list = json.decode(jsonString);
      list.removeWhere((item) => item['uniqueId'] == uniqueId);
      
      await prefs.setString(_key, json.encode(list));
      
      // Emit update
      _current = list.cast<Map<String, dynamic>>();
      _controller.add(_current);
    } catch (e) {
      debugPrint('[WatchHistory] Error removing item: $e');
    }
  }
  
  void dispose() {
    _controller.close();
  }
}
