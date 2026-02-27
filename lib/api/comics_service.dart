import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as hp;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_server_service.dart';
import 'comic_page_extractor.dart';

class Comic {
  final String title;
  final String url;
  final String poster;
  final String status;
  final String publication;
  final String summary;

  Comic({
    required this.title,
    required this.url,
    required this.poster,
    required this.status,
    required this.publication,
    required this.summary,
  });

  factory Comic.fromJson(Map<String, dynamic> json) {
    return Comic(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      poster: json['poster'] ?? '',
      status: json['status'] ?? '',
      publication: json['publication'] ?? '',
      summary: json['summary'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'poster': poster,
      'status': status,
      'publication': publication,
      'summary': summary,
    };
  }
}

class ComicChapter {
  final String title;
  final String url;
  final String dateAdded;

  ComicChapter({required this.title, required this.url, required this.dateAdded});
}

class ComicDetails {
  final Comic comic;
  final String otherName;
  final List<String> genres;
  final String publisher;
  final String writer;
  final String artist;
  final String publicationDate;
  final List<ComicChapter> chapters;

  ComicDetails({
    required this.comic,
    required this.otherName,
    required this.genres,
    required this.publisher,
    required this.writer,
    required this.artist,
    required this.publicationDate,
    required this.chapters,
  });
}

class ComicsService {
  static const String _baseUrl = 'https://readcomiconline.li';
  static const String _likedKey = 'liked_comics';

  Future<List<Comic>> getComics({int page = 1}) async {
    try {
      final url = '$_baseUrl/ComicList?page=$page';
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode == 200) {
        return _parseComics(response.body);
      }
    } catch (e) {
      debugPrint('Error fetching comics: $e');
    }
    return [];
  }

  Future<List<Comic>> searchComics(String query) async {
    try {
      final url = '$_baseUrl/Search/Comic';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'keyword=$query',
      );

      if (response.statusCode == 200) {
        return _parseComics(response.body);
      }
    } catch (e) {
      debugPrint('Error searching comics: $e');
    }
    return [];
  }

  Future<ComicDetails?> getComicDetails(Comic comic) async {
    try {
      var url = comic.url.startsWith('http') ? comic.url : '$_baseUrl${comic.url}';
      // Ensure we don't have duplicate s2
      if (!url.contains('s=s2')) {
        url += url.contains('?') ? '&s=s2' : '?s=s2';
      }
      
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (response.statusCode != 200) return null;

      final document = hp.parse(response.body);
      final infoParas = document.querySelectorAll('.barContent p');
      
      String otherName = 'None';
      List<String> genres = [];
      String publisher = 'Unknown';
      String writer = 'Unknown';
      String artist = 'Unknown';
      String publicationDate = 'Unknown';

      for (var p in infoParas) {
        final infoSpan = p.querySelector('.info');
        if (infoSpan == null) continue;
        final label = infoSpan.text.toLowerCase();
        final content = p.text.replaceFirst(infoSpan.text, '').trim();

        if (label.contains('other name')) otherName = content;
        if (label.contains('genres')) {
          genres = p.querySelectorAll('a').map((e) => e.text.trim()).toList();
        }
        if (label.contains('publisher')) publisher = content;
        if (label.contains('writer')) writer = content;
        if (label.contains('artist')) artist = content;
        if (label.contains('publication date')) publicationDate = content;
      }

      final chapters = <ComicChapter>[];
      final table = document.querySelector('table.listing');
      if (table != null) {
        final rows = table.querySelectorAll('tr');
        for (var row in rows) {
          final link = row.querySelector('a');
          if (link != null) {
            final tds = row.querySelectorAll('td');
            final date = tds.length > 1 ? tds[1].text.trim() : '';
            
            var chapterUrl = link.attributes['href'] ?? '';
            if (chapterUrl.isNotEmpty && !chapterUrl.contains('s=s2')) {
              chapterUrl += chapterUrl.contains('?') ? '&s=s2' : '?s=s2';
            }

            chapters.add(ComicChapter(
              title: link.text.trim(),
              url: chapterUrl,
              dateAdded: date,
            ));
          }
        }
      }

      return ComicDetails(
        comic: comic,
        otherName: otherName,
        genres: genres,
        publisher: publisher,
        writer: writer,
        artist: artist,
        publicationDate: publicationDate,
        chapters: chapters,
      );
    } catch (e) {
      debugPrint('Error getting comic details: $e');
      return null;
    }
  }

  Future<List<String>> getChapterPages(String chapterUrl, ComicPageExtractor extractor) async {
    try {
      // MANDATORY: Add &s=s2 to the URL
      var url = chapterUrl.startsWith('http') ? chapterUrl : '$_baseUrl$chapterUrl';
      if (!url.contains('s=s2')) {
        url += url.contains('?') ? '&s=s2' : '?s=s2';
      }

      debugPrint('[ComicsService] Extracting page count from: $url');
      
      // Use provided extractor instance
      final pageCount = await extractor.getPageCount(url);
      
      if (pageCount == null || pageCount == 0) {
        debugPrint('[ComicsService] Could not determine page count');
        return [];
      }
      
      debugPrint('[ComicsService] Comic has $pageCount pages');
      
      // Return URLs for each page (they'll be loaded on-demand)
      final pageUrls = List.generate(
        pageCount,
        (index) => '$url#${index + 1}',
      );
      
      return pageUrls;
    } catch (e) {
      debugPrint('Error getting chapter pages: $e');
      return [];
    }
  }

  // Get a single page image URL (called on-demand when user navigates)
  Future<String?> getPageImage(String pageUrl, ComicPageExtractor extractor) async {
    try {
      debugPrint('[ComicsService] Fetching single page: $pageUrl');
      
      // Use provided extractor instance
      final imageUrl = await extractor.extractSinglePage(pageUrl);
      
      if (imageUrl == null || imageUrl.isEmpty) {
        debugPrint('[ComicsService] No image found for page');
        return null;
      }
      
      debugPrint('[ComicsService] Page image: $imageUrl');
      
      // Proxy the URL
      return LocalServerService().getComicProxyUrl(imageUrl);
    } catch (e) {
      debugPrint('Error getting page image: $e');
      return null;
    }
  }

  String _step1(String l) {
    if (l.length < 50) return l;
    return l.substring(15, 33) + l.substring(50);
  }

  String _step2(String l) {
    if (l.length < 11) return l;
    return l.substring(0, l.length - 11) + l[l.length - 2] + l[l.length - 1];
  }

  String decodeComicUrl(String encodedStr, {String baseUrl = 'https://ano1.rconet.biz/pic'}) {
    try {
      String l = encodedStr;
      
      // 1. If it's a full URL, extract just the encoded part after the domain
      if (l.startsWith('http')) {
        final uri = Uri.tryParse(l);
        if (uri != null) {
          // Extract path without leading slash
          l = uri.path;
          if (l.startsWith('/')) l = l.substring(1);
          // Add back query params if they exist
          if (uri.query.isNotEmpty) {
            l = '$l?${uri.query}';
          }
        }
      }
      
      // 2. Initial Cleanup - the obfuscated 'e'
      l = l.replaceAll('c5__OydMWk_', 'e');
      
      // 3. Identify and separate query params
      String query = '';
      int queryIndex = l.indexOf('?');
      if (queryIndex != -1) {
        query = l.substring(queryIndex);
        l = l.substring(0, queryIndex);
      }
      
      // 4. Remove quality suffix before processing
      l = l.replaceAll('=s1600', '').replaceAll('=s0', '');

      // 5. Run Steps
      l = _step1(l);
      l = _step2(l);
      
      // 6. Base64 Decode
      List<int> bytes = base64.decode(l);
      
      // 7. Decode binary to string using latin1 (ISO-8859-1)
      String decoded = latin1.decode(bytes);
      
      // 8. Final character removal (Remove 4 chars at index 13)
      if (decoded.length > 17) {
        decoded = decoded.substring(0, 13) + decoded.substring(17);
      }
      
      // 9. Reconstruct URL - prepend baseUrl and append quality/query
      String finalBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      return '$finalBase/$decoded=s1600$query';
    } catch (e) {
      debugPrint('[ComicsService] Decode error for string: ${encodedStr.length > 20 ? encodedStr.substring(0, 20) : encodedStr}... -> $e');
      return '';
    }
  }

  List<Comic> _parseComics(String html) {
    final List<Comic> comics = [];
    final document = hp.parse(html);
    final items = document.querySelectorAll('.list-comic .item, .item');

    for (var item in items) {
      final titleAttr = item.attributes['title'] ?? '';
      final titleDoc = hp.parse(titleAttr);
      
      final title = titleDoc.querySelector('.title')?.text ?? item.querySelector('.title')?.text ?? 'Unknown';
      final status = _extractFromTitle(titleAttr, 'Status:');
      final publication = _extractFromTitle(titleAttr, 'Publication:');
      final summary = titleDoc.querySelector('.description')?.text ?? 'No summary available';

      final link = item.querySelector('a');
      final url = link?.attributes['href'] ?? '';
      
      final img = item.querySelector('img');
      var poster = img?.attributes['src'] ?? '';
      if (poster.isNotEmpty && !poster.startsWith('http')) {
        poster = '$_baseUrl$poster';
      }

      if (title != 'Unknown' && url.isNotEmpty) {
        comics.add(Comic(
          title: title.trim(),
          url: url,
          poster: poster,
          status: status,
          publication: publication,
          summary: summary.trim(),
        ));
      }
    }
    return comics;
  }

  String _extractFromTitle(String titleAttr, String label) {
    final doc = hp.parse(titleAttr);
    final strongs = doc.querySelectorAll('strong');
    for (var strong in strongs) {
      if (strong.text.contains(label)) {
        final parentText = strong.parent?.text ?? '';
        return parentText.replaceFirst(strong.text, '').trim();
      }
    }
    return 'Unknown';
  }

  // Like Functionality
  Future<void> toggleLike(Comic comic) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    
    final index = likedJson.indexWhere((j) => Comic.fromJson(jsonDecode(j)).url == comic.url);
    
    if (index != -1) {
      likedJson.removeAt(index);
    } else {
      likedJson.add(jsonEncode(comic.toJson()));
    }
    
    await prefs.setStringList(_likedKey, likedJson);
  }

  Future<bool> isLiked(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.any((j) => Comic.fromJson(jsonDecode(j)).url == url);
  }

  Future<List<Comic>> getLikedComics() async {
    final prefs = await SharedPreferences.getInstance();
    final likedJson = prefs.getStringList(_likedKey) ?? [];
    return likedJson.map((j) => Comic.fromJson(jsonDecode(j))).toList();
  }
}
