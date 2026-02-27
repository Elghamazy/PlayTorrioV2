import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_server_service.dart';

class Manga {
  final int mangaId;
  final String hashId;
  final String title;
  final List<String> altTitles;
  final String synopsis;
  final String slug;
  final int rank;
  final String type;
  final MangaPoster poster;
  final String originalLanguage;
  final String status;
  final int finalVolume;
  final double finalChapter;
  final bool hasChapters;
  final double latestChapter;
  final int chapterUpdatedAt;
  final int startDate;
  final String endDate;
  final int createdAt;
  final int updatedAt;
  final double ratedAvg;
  final int ratedCount;
  final int followsTotal;
  final Map<String, String> links;
  final bool isNsfw;
  final int year;
  final List<int> termIds;

  Manga({
    required this.mangaId,
    required this.hashId,
    required this.title,
    required this.altTitles,
    required this.synopsis,
    required this.slug,
    required this.rank,
    required this.type,
    required this.poster,
    required this.originalLanguage,
    required this.status,
    required this.finalVolume,
    required this.finalChapter,
    required this.hasChapters,
    required this.latestChapter,
    required this.chapterUpdatedAt,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
    required this.ratedAvg,
    required this.ratedCount,
    required this.followsTotal,
    required this.links,
    required this.isNsfw,
    required this.year,
    required this.termIds,
  });

  factory Manga.fromJson(Map<String, dynamic> json) {
    return Manga(
      mangaId: json['manga_id'] is String ? int.tryParse(json['manga_id']) ?? 0 : (json['manga_id'] ?? 0),
      hashId: json['hash_id'] ?? '',
      title: json['title'] ?? '',
      altTitles: (json['alt_titles'] as List?)?.map((e) => e.toString()).toList() ?? [],
      synopsis: json['synopsis'] ?? '',
      slug: json['slug'] ?? '',
      rank: json['rank'] is String ? int.tryParse(json['rank']) ?? 0 : (json['rank'] ?? 0),
      type: json['type'] ?? '',
      poster: MangaPoster.fromJson(json['poster'] ?? {}),
      originalLanguage: json['original_language'] ?? '',
      status: json['status'] ?? '',
      finalVolume: json['final_volume'] is String ? int.tryParse(json['final_volume']) ?? 0 : (json['final_volume'] ?? 0),
      finalChapter: (json['final_chapter'] is String ? double.tryParse(json['final_chapter']) ?? 0 : json['final_chapter'] ?? 0).toDouble(),
      hasChapters: json['has_chapters'] ?? false,
      latestChapter: (json['latest_chapter'] is String ? double.tryParse(json['latest_chapter']) ?? 0 : json['latest_chapter'] ?? 0).toDouble(),
      chapterUpdatedAt: json['chapter_updated_at'] is String ? int.tryParse(json['chapter_updated_at']) ?? 0 : (json['chapter_updated_at'] ?? 0),
      startDate: json['start_date'] is String ? int.tryParse(json['start_date']) ?? 0 : (json['start_date'] ?? 0),
      endDate: json['end_date']?.toString() ?? '?',
      createdAt: json['created_at'] is String ? int.tryParse(json['created_at']) ?? 0 : (json['created_at'] ?? 0),
      updatedAt: json['updated_at'] is String ? int.tryParse(json['updated_at']) ?? 0 : (json['updated_at'] ?? 0),
      ratedAvg: (json['rated_avg'] is String ? double.tryParse(json['rated_avg']) ?? 0 : json['rated_avg'] ?? 0).toDouble(),
      ratedCount: json['rated_count'] is String ? int.tryParse(json['rated_count']) ?? 0 : (json['rated_count'] ?? 0),
      followsTotal: json['follows_total'] is String ? int.tryParse(json['follows_total']) ?? 0 : (json['follows_total'] ?? 0),
      links: (json['links'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? {},
      isNsfw: json['is_nsfw'] ?? false,
      year: json['year'] is String ? int.tryParse(json['year']) ?? 0 : (json['year'] ?? 0),
      termIds: (json['term_ids'] as List?)?.map((e) => e is String ? int.tryParse(e) ?? 0 : e as int).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'manga_id': mangaId,
      'hash_id': hashId,
      'title': title,
      'alt_titles': altTitles,
      'synopsis': synopsis,
      'slug': slug,
      'rank': rank,
      'type': type,
      'poster': poster.toJson(),
      'original_language': originalLanguage,
      'status': status,
      'final_volume': finalVolume,
      'final_chapter': finalChapter,
      'has_chapters': hasChapters,
      'latest_chapter': latestChapter,
      'chapter_updated_at': chapterUpdatedAt,
      'start_date': startDate,
      'end_date': endDate,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'rated_avg': ratedAvg,
      'rated_count': ratedCount,
      'follows_total': followsTotal,
      'links': links,
      'is_nsfw': isNsfw,
      'year': year,
      'term_ids': termIds,
    };
  }
}

class MangaPoster {
  final String small;
  final String medium;
  final String large;

  MangaPoster({
    required this.small,
    required this.medium,
    required this.large,
  });

  factory MangaPoster.fromJson(Map<String, dynamic> json) {
    return MangaPoster(
      small: json['small'] ?? '',
      medium: json['medium'] ?? '',
      large: json['large'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'small': small,
      'medium': medium,
      'large': large,
    };
  }
}

class MangaChapter {
  final int chapterId;
  final int mangaId;
  final double number;
  final String name;
  final String language;
  final int volume;
  final int votes;
  final int createdAt;
  final ScanlationGroup scanlationGroup;

  MangaChapter({
    required this.chapterId,
    required this.mangaId,
    required this.number,
    required this.name,
    required this.language,
    required this.volume,
    required this.votes,
    required this.createdAt,
    required this.scanlationGroup,
  });

  factory MangaChapter.fromJson(Map<String, dynamic> json) {
    return MangaChapter(
      chapterId: json['chapter_id'] ?? 0,
      mangaId: json['manga_id'] ?? 0,
      number: (json['number'] is String ? double.tryParse(json['number']) ?? 0 : json['number'] ?? 0).toDouble(),
      name: json['name'] ?? '',
      language: json['language'] ?? '',
      volume: json['volume'] ?? 0,
      votes: json['votes'] ?? 0,
      createdAt: json['created_at'] ?? 0,
      scanlationGroup: ScanlationGroup.fromJson(json['scanlation_group'] ?? {}),
    );
  }
}

class ScanlationGroup {
  final int scanlationGroupId;
  final String name;
  final String slug;

  ScanlationGroup({
    required this.scanlationGroupId,
    required this.name,
    required this.slug,
  });

  factory ScanlationGroup.fromJson(Map<String, dynamic> json) {
    return ScanlationGroup(
      scanlationGroupId: json['scanlation_group_id'] ?? 0,
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
    );
  }
}

class MangaService {
  static const String _baseUrl = 'https://comix.to/api/v2';
  static const String _likedKey = 'liked_manga';

  Future<List<Manga>> getManga({int page = 1, int? genreId}) async {
    try {
      var url = '$_baseUrl/manga?order[views_30d]=desc&genres_mode=and&limit=28&page=$page';
      if (genreId != null) {
        url = '$_baseUrl/manga?order[views_30d]=desc&genres[]=$genreId&genres_mode=and&limit=28&page=$page';
      }
      debugPrint('[MangaService] Fetching page $page: $url');
      final response = await http.get(Uri.parse(url));

      debugPrint('[MangaService] Response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('[MangaService] Response data status: ${data['status']}');
        if (data['status'] == 200 && data['result'] != null) {
          final items = data['result']['items'] as List;
          debugPrint('[MangaService] Found ${items.length} manga items');
          return items.map((item) => Manga.fromJson(item)).toList();
        } else {
          debugPrint('[MangaService] Invalid response structure: ${data.toString().substring(0, 200)}');
        }
      }
    } catch (e) {
      debugPrint('[MangaService] Error fetching manga: $e');
    }
    return [];
  }

  Future<List<Manga>> searchManga(String query, {int page = 1}) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = '$_baseUrl/manga?order[relevance]=desc&keyword=$encodedQuery&genres_mode=and&limit=28&page=$page';
      debugPrint('[MangaService] Searching page $page: $url');
      final response = await http.get(Uri.parse(url));

      debugPrint('[MangaService] Search response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('[MangaService] Search response data status: ${data['status']}');
        if (data['status'] == 200 && data['result'] != null) {
          final items = data['result']['items'] as List;
          debugPrint('[MangaService] Found ${items.length} search results');
          return items.map((item) => Manga.fromJson(item)).toList();
        } else {
          debugPrint('[MangaService] Invalid search response structure');
        }
      }
    } catch (e) {
      debugPrint('[MangaService] Error searching manga: $e');
    }
    return [];
  }

  Future<List<MangaChapter>> getChapters(String hashId) async {
    final List<MangaChapter> allChapters = [];
    int page = 1;
    
    while (true) {
      try {
        final url = '$_baseUrl/manga/$hashId/chapters?limit=100&page=$page&order[number]=desc';
        debugPrint('[MangaService] Fetching chapters page $page: $url');
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 200 && data['result'] != null) {
            final items = data['result']['items'] as List;
            if (items.isEmpty) {
              debugPrint('[MangaService] No more chapters, total: ${allChapters.length}');
              break;
            }
            allChapters.addAll(items.map((item) => MangaChapter.fromJson(item)));
            debugPrint('[MangaService] Fetched ${items.length} chapters from page $page');
            page++;
          } else {
            break;
          }
        } else {
          break;
        }
      } catch (e) {
        debugPrint('[MangaService] Error fetching chapters: $e');
        break;
      }
    }
    
    return allChapters;
  }

  Future<List<String>> getChapterImages(String hashId, String slug, int chapterId, double chapterNumber) async {
    try {
      final url = 'https://comix.to/title/$hashId-$slug/$chapterId-chapter-${chapterNumber.toInt()}';
      debugPrint('[MangaService] Fetching chapter page: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
        },
      );

      debugPrint('[MangaService] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final html = response.body;
        final imageUrls = <String>[];
        
        // Find all self.__next_f.push calls
        final scriptPattern = RegExp(r'self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)', multiLine: true, dotAll: true);
        final scriptMatches = scriptPattern.allMatches(html);
        
        for (final match in scriptMatches) {
          if (match.group(1) != null) {
            String encoded = match.group(1)!;
            
            // Decode the escaped string
            String decoded = encoded
                .replaceAll(r'\"', '"')
                .replaceAll(r'\n', '\n')
                .replaceAll(r'\\', r'\');
            
            // Only look for .webp images
            if (decoded.contains('.webp')) {
              final imgPattern = RegExp(r'https://[^\s"\\]+\.webp', multiLine: true);
              final imgMatches = imgPattern.allMatches(decoded);
              
              for (final imgMatch in imgMatches) {
                final imgUrl = imgMatch.group(0)!;
                if (!imageUrls.contains(imgUrl)) {
                  imageUrls.add(imgUrl);
                }
              }
            }
          }
        }
        
        // If we found at least one webp image, construct the rest
        if (imageUrls.isNotEmpty) {
          final firstImage = imageUrls.first;
          debugPrint('[MangaService] First webp image: $firstImage');
          
          // Extract the base URL and pattern
          // Example: https://ek10.wowpic1.store/ii/bEqPbYfoOT0GmkXlQmqftDpIwoUNV/1.webp
          final match = RegExp(r'(https://[^/]+/[^/]+/[^/]+/)(\d+)(\.webp)').firstMatch(firstImage);
          
          if (match != null) {
            final baseUrl = match.group(1)!;
            final firstPageNum = match.group(2)!;
            final extension = match.group(3)!;
            
            // Determine if padding is used (01 vs 1)
            final usesPadding = firstPageNum.length > 1 && firstPageNum.startsWith('0');
            
            // Count how many images we found to determine total pages
            final pageCount = imageUrls.length;
            debugPrint('[MangaService] Constructing $pageCount pages from base: $baseUrl (padding: $usesPadding)');
            
            // Construct all page URLs and proxy them
            final constructedUrls = <String>[];
            for (int i = 1; i <= pageCount; i++) {
              final pageNum = usesPadding ? i.toString().padLeft(2, '0') : i.toString();
              final imageUrl = '$baseUrl$pageNum$extension';
              // Proxy the URL through local server to add referer header
              final proxiedUrl = LocalServerService().getMangaProxyUrl(imageUrl);
              constructedUrls.add(proxiedUrl);
            }
            
            debugPrint('[MangaService] Total images constructed: ${constructedUrls.length}');
            return constructedUrls;
          }
        }
        
        debugPrint('[MangaService] No webp images found');
      } else {
        debugPrint('[MangaService] HTTP error: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('[MangaService] Error fetching chapter images: $e');
      debugPrint('[MangaService] Stack trace: $stackTrace');
    }
    return [];
  }

  // Like Functionality
  Future<void> toggleLike(Manga manga) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    
    final index = likedJson.indexWhere((j) => Manga.fromJson(jsonDecode(j)).hashId == manga.hashId);
    
    if (index != -1) {
      likedJson.removeAt(index);
    } else {
      likedJson.add(jsonEncode(manga.toJson()));
    }
    
    await prefs.setStringList(_likedKey, likedJson);
  }

  Future<bool> isLiked(String hashId) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.any((j) => Manga.fromJson(jsonDecode(j)).hashId == hashId);
  }

  Future<List<Manga>> getLikedManga() async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.map((j) => Manga.fromJson(jsonDecode(j))).toList();
  }
}
