import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class _CachedUrl {
  final String url;
  final DateTime cachedAt;
  _CachedUrl(this.url) : cachedAt = DateTime.now();
  bool get isExpired => DateTime.now().difference(cachedAt).inHours >= 5;
}

class MusicTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String cover;
  final int duration;
  final String? localPath;

  MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.cover,
    required this.duration,
    this.localPath,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final artistObj = json['artist'];
    final albumObj = json['album'];
    
    // Check if this is a raw API response or our saved JSON
    String artistName = 'Unknown Artist';
    if (artistObj is Map) {
      artistName = artistObj['name'] ?? 'Unknown Artist';
    } else if (artistObj is String) {
      artistName = artistObj;
    }

    String albumTitle = '';
    String coverUrl = '';
    if (albumObj is Map) {
      albumTitle = albumObj['title'] ?? '';
      coverUrl = albumObj['cover_xl'] ?? albumObj['cover_big'] ?? albumObj['cover_medium'] ?? albumObj['cover_small'] ?? '';
    } else if (albumObj is String) {
      albumTitle = albumObj;
      coverUrl = json['cover'] ?? '';
    }

    return MusicTrack(
      id: json['id'].toString(),
      title: json['title'] ?? 'Unknown Title',
      artist: artistName,
      album: albumTitle,
      cover: coverUrl.isNotEmpty ? coverUrl : (json['cover'] ?? ''),
      duration: json['duration'] ?? 0,
      localPath: json['localPath'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'cover': cover,
    'duration': duration,
    'localPath': localPath,
  };
}

class MusicAlbum {
  final String id;
  final String title;
  final String artist;
  final String cover;
  final int? nbTracks;

  MusicAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.cover,
    this.nbTracks,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> json) {
    final artistObj = json['artist'] ?? {};

    return MusicAlbum(
      id: json['id'].toString(),
      title: json['title'] ?? '',
      artist: artistObj['name'] ?? 'Unknown Artist',
      cover: json['cover_xl'] ?? json['cover_big'] ?? json['cover_medium'] ?? json['cover_small'] ?? '',
      nbTracks: json['nb_tracks'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'cover': cover,
    'nbTracks': nbTracks,
  };
}

class MusicService {
  final _yt = YoutubeExplode();
  static const String _proxyUrl = 'https://deezer-proxy.aymanisthedude1.workers.dev/?url=';

  // Caches for fast playback
  final Map<String, String> _videoIdCache = {};
  final Map<String, _CachedUrl> _streamUrlCache = {};

  Future<List<MusicTrack>> searchTracks(String query) async {
    try {
      // Use Uri to properly encode non-ASCII characters (Arabic, etc.)
      final targetUri = Uri.https('api.deezer.com', '/search', {'q': query});
      final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
      
      final response = await http.get(Uri.parse(proxiedUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'] as List;
        return items.map((item) => MusicTrack.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('MusicService: Search tracks error: $e');
    }
    return [];
  }

  Future<List<MusicTrack>> getTrendingTracks({int index = 0, int limit = 20}) async {
    try {
      final targetUri = Uri.https('api.deezer.com', '/chart/0/tracks', {
        'index': index.toString(),
        'limit': limit.toString(),
      });
      final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
      
      final response = await http.get(Uri.parse(proxiedUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'] as List;
        return items.map((item) => MusicTrack.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('MusicService: Get trending tracks error: $e');
    }
    return [];
  }

  Future<List<MusicAlbum>> searchAlbums(String query) async {
    try {
      final targetUri = Uri.https('api.deezer.com', '/search/album', {'q': query});
      final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUri.toString())}';
      
      final response = await http.get(Uri.parse(proxiedUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final albums = data['data'] as List;
        return albums.map((item) => MusicAlbum.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('MusicService: Search albums error: $e');
    }
    return [];
  }

  Future<List<MusicTrack>> getAlbumTracks(String albumId) async {
    try {
      final targetUrl = 'https://api.deezer.com/album/$albumId';
      final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUrl)}';
      
      final albumResponse = await http.get(Uri.parse(proxiedUrl));
      if (albumResponse.statusCode == 200) {
        final albumData = json.decode(albumResponse.body);
        final items = albumData['tracks']['data'] as List;
        
        return items.map((trackJson) {
           trackJson['album'] = {
             'title': albumData['title'],
             'cover_xl': albumData['cover_xl'],
             'cover_big': albumData['cover_big'],
             'cover_medium': albumData['cover_medium'],
             'cover_small': albumData['cover_small'],
           };
           return MusicTrack.fromJson(trackJson);
        }).toList();
      }
    } catch (e) {
      debugPrint('MusicService: Get album tracks error: $e');
    }
    return [];
  }

  Future<List<MusicTrack>> getRelatedTracks(String trackId) async {
    try {
      final targetUrl = 'https://api.deezer.com/track/$trackId/related';
      final proxiedUrl = '$_proxyUrl${Uri.encodeComponent(targetUrl)}';
      
      final response = await http.get(Uri.parse(proxiedUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'];
        if (items is List) {
          return items.map((item) => MusicTrack.fromJson(item)).toList();
        }
      }
    } catch (e) {
      debugPrint('MusicService: Get related tracks error: $e');
    }
    return [];
  }

  Future<String?> getYoutubeVideoId(String title, String artist) async {
    final cacheKey = '$title|$artist';
    if (_videoIdCache.containsKey(cacheKey)) {
      debugPrint('MusicService: Video ID cache hit for "$title"');
      return _videoIdCache[cacheKey];
    }

    try {
      final videoId = await Isolate.run(() async {
        final yt = YoutubeExplode();
        try {
          final searchQuery = '$title - $artist (Official Audio)';
          final searchList = await yt.search.search(searchQuery);
          if (searchList.isNotEmpty) {
            for (final video in searchList) {
              if (video.duration != null && video.duration!.inSeconds > 60) {
                return video.id.value;
              }
            }
            return searchList.first.id.value;
          }
        } finally {
          yt.close();
        }
        return null;
      });

      if (videoId != null) _videoIdCache[cacheKey] = videoId;
      return videoId;
    } catch (e) {
      debugPrint('MusicService: YouTube matching error: $e');
    }
    return null;
  }

  /// Fast stream URL fetching for playback — runs in isolate with caching
  Future<String?> getYoutubeStreamUrl(String videoId) async {
    final cached = _streamUrlCache[videoId];
    if (cached != null && !cached.isExpired) {
      debugPrint('MusicService: Stream URL cache hit');
      return cached.url;
    }

    try {
      final url = await Isolate.run(() async {
        final yt = YoutubeExplode();
        try {
          final manifest = await yt.videos.streamsClient.getManifest(
            videoId,
            ytClients: [YoutubeApiClient.androidVr],
          );
          final audioStreams = manifest.audioOnly.toList();
          if (audioStreams.isEmpty) return null;
          audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
          return audioStreams.first.url.toString();
        } finally {
          yt.close();
        }
      });

      if (url != null) _streamUrlCache[videoId] = _CachedUrl(url);
      return url;
    } catch (e) {
      debugPrint('MusicService: Stream URL error: $e');
      return null;
    }
  }

  Future<StreamManifest?> getYoutubeManifest(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidVr],
      );
    } catch (e) {
      debugPrint('MusicService: Get manifest error: $e');
      return null;
    }
  }

  YoutubeExplode get yt => _yt;

  void dispose() {
    _yt.close();
  }
}
