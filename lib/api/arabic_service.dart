import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import 'local_server_service.dart';
import 'stream_extractor.dart';

const String _baseUrl = 'https://larozaa.xyz';

// ── Models ──────────────────────────────────────────────────────────────────

class ArabicShow {
  final String id;
  final String title;
  final String poster;
  final String url;
  final bool isMovie;
  final String source; // 'larozaa' or 'dimatoon'

  ArabicShow({
    required this.id,
    required this.title,
    required this.poster,
    required this.url,
    this.isMovie = false,
    this.source = 'larozaa',
  });

  factory ArabicShow.fromJson(Map<String, dynamic> json) => ArabicShow(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        poster: json['poster'] ?? '',
        url: json['url'] ?? '',
        isMovie: json['isMovie'] == true,
        source: json['source'] ?? 'larozaa',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'url': url,
        'isMovie': isMovie,
        'source': source,
      };
}

class ArabicSeason {
  final int number;
  final String tabId;
  final List<ArabicEpisode> episodes;

  ArabicSeason({
    required this.number,
    required this.tabId,
    this.episodes = const [],
  });
}

class ArabicEpisode {
  final String id;
  final String title;
  final String poster;

  ArabicEpisode({
    required this.id,
    required this.title,
    this.poster = '',
  });
}

class ArabicServer {
  final int index;
  final String name;
  final String embedUrl;

  ArabicServer({
    required this.index,
    required this.name,
    required this.embedUrl,
  });
}

class ArabicShowDetail {
  final String title;
  final String poster;
  final String description;
  final List<ArabicSeason> seasons;

  ArabicShowDetail({
    required this.title,
    required this.poster,
    this.description = '',
    this.seasons = const [],
  });
}

// ── Category definitions ────────────────────────────────────────────────────

class ArabicCategory {
  final String slug;
  final String label;
  const ArabicCategory(this.slug, this.label);
}

const List<ArabicCategory> arabicCategories = [
  ArabicCategory('arabic-series46', 'مسلسلات عربية'),
  ArabicCategory('arabic-movies33', 'أفلام عربية'),
  ArabicCategory('turkish-3isk-seriess47', 'مسلسلات تركية'),
  ArabicCategory('ramadan-2026', 'رمضان 2026'),
  ArabicCategory('tv-programs12', 'برامج تلفزيونية'),
  ArabicCategory('all_movies_13', 'أفلام أجنبية'),
  ArabicCategory('indian-movies9', 'أفلام هندية'),
  ArabicCategory('7-aflammdblgh', 'أفلام مدبلجة'),
  ArabicCategory('anime-movies-7', 'أنمي'),
];

// ── Service ─────────────────────────────────────────────────────────────────

class ArabicService {
  static const String _likedKey = 'liked_arabic';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ar,en;q=0.9',
      };

  Future<String> _fetchHtml(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    return response.body;
  }

  // ── Browse ──────────────────────────────────────────────────────────

  /// Browse latest series (default landing page).
  Future<List<ArabicShow>> browse({int page = 1}) async {
    try {
      final url = '$_baseUrl/moslslat4.php?&page=$page';
      debugPrint('[ArabicService] Browse page $page: $url');
      final html = await _fetchHtml(url);
      return _parseCards(html);
    } catch (e) {
      debugPrint('[ArabicService] Error browsing: $e');
      return [];
    }
  }

  /// Browse by category.
  Future<List<ArabicShow>> browseCategory(String catSlug, {int page = 1}) async {
    try {
      final url = '$_baseUrl/category.php?cat=$catSlug&page=$page&order=DESC';
      debugPrint('[ArabicService] Category $catSlug page $page');
      final html = await _fetchHtml(url);
      return _parseCards(html, isMovie: _isMovieCategory(catSlug));
    } catch (e) {
      debugPrint('[ArabicService] Error browsing category: $e');
      return [];
    }
  }

  bool _isMovieCategory(String slug) {
    return slug.contains('movie') || slug.contains('aflam');
  }

  // ── Search ──────────────────────────────────────────────────────────

  Future<List<ArabicShow>> search(String query, {int page = 1}) async {
    try {
      final encoded = Uri.encodeComponent(query);
      final url = '$_baseUrl/search.php?keywords=$encoded&page=$page';
      debugPrint('[ArabicService] Searching: $query');
      final html = await _fetchHtml(url);
      return _parseCards(html);
    } catch (e) {
      debugPrint('[ArabicService] Error searching: $e');
      return [];
    }
  }

  // ── Show details (series with seasons & episodes) ───────────────────

  Future<ArabicShowDetail> getShowDetails(String showId) async {
    try {
      final url = '$_baseUrl/view-serie1.php?ser=$showId';
      debugPrint('[ArabicService] Getting show details: $showId');
      final html = await _fetchHtml(url);
      return _parseShowDetails(html);
    } catch (e) {
      debugPrint('[ArabicService] Error getting show details: $e');
      return ArabicShowDetail(title: '', poster: '');
    }
  }

  // ── Servers for a video ──────────────────────────────────────────────

  Future<List<ArabicServer>> getServers(String videoId) async {
    try {
      final url = '$_baseUrl/play.php?vid=$videoId';
      debugPrint('[ArabicService] Getting servers for: $videoId');
      final html = await _fetchHtml(url);
      return _parseServers(html);
    } catch (e) {
      debugPrint('[ArabicService] Error getting servers: $e');
      return [];
    }
  }

  // ── Parsing ─────────────────────────────────────────────────────────

  List<ArabicShow> _parseCards(String html, {bool isMovie = false}) {
    final doc = html_parser.parse(html);
    final cards = doc.querySelectorAll('li.col-xs-6.col-sm-4.col-md-3');
    final results = <ArabicShow>[];

    for (final card in cards) {
      final a = card.querySelector('a[href]');
      if (a == null) continue;

      final href = a.attributes['href'] ?? '';
      final title = a.attributes['title'] ?? a.text.trim();
      if (title.isEmpty) continue;

      // Image: prefer data-echo (lazy), fallback to src
      final img = card.querySelector('img');
      String poster = '';
      if (img != null) {
        poster = img.attributes['data-echo'] ?? '';
        if (poster.isEmpty || poster.startsWith('data:')) {
          poster = img.attributes['src'] ?? '';
        }
        if (poster.startsWith('data:')) poster = '';
        if (poster.isNotEmpty && !poster.startsWith('http')) {
          poster = '$_baseUrl/$poster';
        }
      }

      // Extract show ID from URL
      String id = '';
      String url = href;
      if (!url.startsWith('http')) url = '$_baseUrl/$url';

      final serMatch = RegExp(r'ser=([^&]+)').firstMatch(href);
      final vidMatch = RegExp(r'vid=([^&]+)').firstMatch(href);
      if (serMatch != null) {
        id = serMatch.group(1)!;
      } else if (vidMatch != null) {
        id = vidMatch.group(1)!;
      }

      if (id.isEmpty) continue;

      // Determine if movie based on URL pattern or category flag
      final showIsMovie = isMovie || href.contains('video.php');

      results.add(ArabicShow(
        id: id,
        title: title.trim(),
        poster: poster,
        url: url,
        isMovie: showIsMovie,
      ));
    }

    return results;
  }

  ArabicShowDetail _parseShowDetails(String html) {
    final doc = html_parser.parse(html);

    // Title
    final titleEl = doc.querySelector('h2') ?? doc.querySelector('h1');
    final title = titleEl?.text.trim() ?? '';

    // Poster
    String poster = '';
    final posterImg = doc.querySelector('img[src*="uploads/thumbs"]') ??
        doc.querySelector('img[data-echo*="uploads/thumbs"]');
    if (posterImg != null) {
      poster = posterImg.attributes['src'] ?? posterImg.attributes['data-echo'] ?? '';
      if (poster.isNotEmpty && !poster.startsWith('http')) {
        poster = poster.startsWith('//') ? 'https:$poster' : '$_baseUrl/$poster';
      }
    }

    // Description
    final descEl = doc.querySelector('.pm-video-content') ??
        doc.querySelector('.description') ??
        doc.querySelector('.story');
    final description = descEl?.text.trim() ?? '';

    // Seasons & Episodes
    final seasons = <ArabicSeason>[];
    final seasonButtons = doc.querySelectorAll('.SeasonsBoxUL button.tablinks');

    if (seasonButtons.isNotEmpty) {
      // Multi-season show
      for (int i = 0; i < seasonButtons.length; i++) {
        final tabId = 'Season${i + 1}';
        final seasonDiv = doc.querySelector('#$tabId');
        final episodes = <ArabicEpisode>[];

        if (seasonDiv != null) {
          final epLinks = seasonDiv.querySelectorAll('a[href*="video.php"]');
          for (final ep in epLinks) {
            final epHref = ep.attributes['href'] ?? '';
            final epTitle = ep.text.trim();
            if (epTitle.isEmpty && epHref.isEmpty) continue;

            final vidMatch = RegExp(r'vid=([^&]+)').firstMatch(epHref);
            if (vidMatch == null) continue;

            // Episode poster
            final epImg = ep.parent?.querySelector('img');
            String epPoster = '';
            if (epImg != null) {
              epPoster = epImg.attributes['src'] ?? epImg.attributes['data-echo'] ?? '';
              if (epPoster.startsWith('data:')) epPoster = '';
              if (epPoster.isNotEmpty && !epPoster.startsWith('http')) {
                epPoster = '$_baseUrl/$epPoster';
              }
            }

            episodes.add(ArabicEpisode(
              id: vidMatch.group(1)!,
              title: epTitle.isNotEmpty ? epTitle : 'الحلقة ${episodes.length + 1}',
              poster: epPoster,
            ));
          }
        }

        seasons.add(ArabicSeason(
          number: i + 1,
          tabId: tabId,
          episodes: episodes,
        ));
      }
    } else {
      // Single season or episode list without tabs
      final allEpLinks = doc.querySelectorAll('a[href*="video.php"]');
      if (allEpLinks.isNotEmpty) {
        final episodes = <ArabicEpisode>[];
        for (final ep in allEpLinks) {
          final epHref = ep.attributes['href'] ?? '';
          final epTitle = ep.text.trim();
          final vidMatch = RegExp(r'vid=([^&]+)').firstMatch(epHref);
          if (vidMatch == null) continue;

          final epImg = ep.parent?.querySelector('img');
          String epPoster = '';
          if (epImg != null) {
            epPoster = epImg.attributes['src'] ?? epImg.attributes['data-echo'] ?? '';
            if (epPoster.startsWith('data:')) epPoster = '';
            if (epPoster.isNotEmpty && !epPoster.startsWith('http')) {
              epPoster = '$_baseUrl/$epPoster';
            }
          }

          episodes.add(ArabicEpisode(
            id: vidMatch.group(1)!,
            title: epTitle.isNotEmpty ? epTitle : 'الحلقة ${episodes.length + 1}',
            poster: epPoster,
          ));
        }
        if (episodes.isNotEmpty) {
          seasons.add(ArabicSeason(number: 1, tabId: 'Season1', episodes: episodes));
        }
      }
    }

    return ArabicShowDetail(
      title: title,
      poster: poster,
      description: description,
      seasons: seasons,
    );
  }

  List<ArabicServer> _parseServers(String html) {
    final doc = html_parser.parse(html);
    final items = doc.querySelectorAll('.WatchList li');
    final servers = <ArabicServer>[];

    for (final item in items) {
      final embedUrl = item.attributes['data-embed-url'] ?? '';
      if (embedUrl.isEmpty) continue;

      final idStr = item.attributes['data-embed-id'] ?? '${servers.length + 1}';
      final name = item.text.trim();

      servers.add(ArabicServer(
        index: int.tryParse(idStr) ?? servers.length + 1,
        name: name.isNotEmpty ? name : 'سيرفر ${servers.length + 1}',
        embedUrl: embedUrl,
      ));
    }

    // If WatchList is empty, try the iframe directly
    if (servers.isEmpty) {
      final iframe = doc.querySelector('iframe[src]');
      if (iframe != null) {
        final src = iframe.attributes['src'] ?? '';
        if (src.isNotEmpty) {
          servers.add(ArabicServer(index: 1, name: 'سيرفر 1', embedUrl: src));
        }
      }
    }

    return servers;
  }

  // ── Likes / Favorites ───────────────────────────────────────────────

  /// Try to extract a direct stream URL (m3u8/mp4) from a server embed page
  /// by unpacking PACKER-obfuscated JWPlayer configs via plain HTTP.
  /// Returns the stream URL or null if the server can't be cracked this way.
  Future<String?> tryExtractDirectUrl(String embedUrl) async {
    try {
      final response = await _client.get(Uri.parse(embedUrl), headers: {
        ..._headers,
        'Referer': '$_baseUrl/',
      });
      if (response.statusCode != 200) return null;
      final html = response.body;

      // 1. Try PACKER unpacking: eval(function(p,a,c,k,e,d){...}('...',N,N,'...'
      final packed = RegExp(
        r"eval\(function\(p,a,c,k,e,d\)\{.*?\}\('(.+)',(\d+),(\d+),'(.+?)'\.split\('\|'\)",
        dotAll: true,
      ).firstMatch(html);

      if (packed != null) {
        final url = _unpackAndFindStream(
          packed.group(1)!,
          int.parse(packed.group(2)!),
          int.parse(packed.group(3)!),
          packed.group(4)!,
        );
        if (url != null) return url;
      }

      // 2. Try direct pattern match (mp4plus style)
      final direct = RegExp(r'file\s*:\s*"(https?://[^"]+\.(?:m3u8|mp4)[^"]*)"')
          .firstMatch(html);
      if (direct != null) return direct.group(1);

      return null;
    } catch (e) {
      debugPrint('[ArabicService] Extract error for $embedUrl: $e');
      return null;
    }
  }

  String? _unpackAndFindStream(String p, int a, int c, String keywords) {
    final kw = keywords.split('|');
    const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    String toBase(int n, int radix) {
      if (n == 0) return '0';
      final buf = StringBuffer();
      var val = n;
      while (val > 0) {
        buf.write(chars[val % radix]);
        val = val ~/ radix;
      }
      return buf.toString().split('').reversed.join();
    }

    var result = p;
    for (var i = c - 1; i >= 0; i--) {
      if (kw[i].isNotEmpty) {
        final token = toBase(i, a);
        result = result.replaceAll(RegExp('\\b$token\\b'), kw[i]);
      }
    }

    // Find m3u8 URL first, then mp4
    final m3u8 = RegExp(r'https?://[^\s"]+\.m3u8[^\s"]*').firstMatch(result);
    if (m3u8 != null) return m3u8.group(0);

    final mp4 = RegExp(r'https?://[^\s"]+\.mp4[^\s"]*').firstMatch(result);
    if (mp4 != null) return mp4.group(0);

    return null;
  }

  Future<void> toggleLike(ArabicShow show) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    final idx = list.indexWhere((e) {
      final m = jsonDecode(e) as Map<String, dynamic>;
      return m['id'] == show.id;
    });
    if (idx >= 0) {
      list.removeAt(idx);
    } else {
      list.insert(0, jsonEncode(show.toJson()));
    }
    await prefs.setStringList(_likedKey, list);
  }

  Future<bool> isLiked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    return list.any((e) {
      final m = jsonDecode(e) as Map<String, dynamic>;
      return m['id'] == id;
    });
  }

  Future<List<ArabicShow>> getLiked() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_likedKey) ?? [];
    return list.map((e) => ArabicShow.fromJson(jsonDecode(e))).toList();
  }

  // ── Static extraction helper (used by player for on-demand server switch) ──

  /// Domains that crash the WebView — skip entirely.
  static const _webViewBlacklist = ['mixdrop', 'm1xdrop', 'dsvplay'];

  /// Shahid/MBC embed hosts whose PACKER scripts link to unreliable CDN mirrors.
  /// Their JWPlayer/Shaka actually loads the real MBC CDN stream → use WebView.
  static const _packerSkipHosts = ['ramadan-series.site', 'watch-rmdan.shop'];

  /// Extract a playable stream URL from an embed URL.
  /// Tries PACKER first (fast HTTP), then WebView fallback.
  /// Returns null if extraction fails.
  static Future<ExtractedMedia?> extractStreamUrl(String embedUrl) async {
    final service = ArabicService();
    final host = Uri.tryParse(embedUrl)?.host ?? '';

    // Phase 1: PACKER / direct HTTP (fast) — skip for hosts with unreliable PACKER
    if (!_packerSkipHosts.any((d) => host.contains(d))) {
      final directUrl = await service.tryExtractDirectUrl(embedUrl);
      if (directUrl != null) {
        final uri = Uri.tryParse(embedUrl);
        final origin = uri != null ? '${uri.scheme}://${uri.host}' : '';
        final headers = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
          'Referer': origin.isNotEmpty ? '$origin/' : embedUrl,
          'Origin': origin,
        };
        // Proxy the stream through local server so headers apply to all HLS sub-requests
        final proxy = LocalServerService();
        final proxyUrl = proxy.getHlsProxyUrl(directUrl, headers);
        return ExtractedMedia(url: proxyUrl, headers: {});
      }
    } else {
      debugPrint('[ArabicService] Skipping PACKER for $host — using WebView');
    }

    // Phase 2: WebView fallback (skip blacklisted)
    if (_webViewBlacklist.any((d) => host.contains(d))) return null;

    try {
      final result = await StreamExtractor().extract(embedUrl, timeout: const Duration(seconds: 15));
      if (result == null) return null;
      // Proxy WebView results too so headers apply to all HLS sub-requests
      if (result.headers.isNotEmpty) {
        final proxy = LocalServerService();
        final proxyUrl = proxy.getHlsProxyUrl(result.url, result.headers);
        return ExtractedMedia(url: proxyUrl, audioUrl: result.audioUrl, headers: {});
      }
      return result;
    } catch (e) {
      debugPrint('[ArabicService] WebView extract failed: $e');
      return null;
    }
  }

  // ── DimaToon (dima-toon.com) ─────────────────────────────────────────

  static const _dimaToonBase = 'https://www.dima-toon.com';

  /// Search dima-toon.com via its AJAX endpoint.
  Future<List<ArabicShow>> searchDimaToon(String query) async {
    try {
      final res = await http.post(
        Uri.parse('$_dimaToonBase/wp-admin/admin-ajax.php'),
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'action=cartoon_search_action&term=${Uri.encodeComponent(query)}',
      );
      if (res.statusCode != 200) return [];
      final doc = html_parser.parse(res.body);
      final items = doc.querySelectorAll('.search-result-item');
      final results = <ArabicShow>[];
      for (final item in items) {
        final a = item.querySelector('a[href]');
        final img = item.querySelector('img');
        if (a == null) continue;
        final href = a.attributes['href'] ?? '';
        final title = a.text.trim();
        final poster = img?.attributes['src'] ?? '';
        if (title.isEmpty || href.isEmpty) continue;
        results.add(ArabicShow(
          id: href,
          title: title,
          poster: poster,
          url: href,
          source: 'dimatoon',
        ));
      }
      debugPrint('[DimaToon] Search "$query" → ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('[DimaToon] Search error: $e');
      return [];
    }
  }

  /// Get show details from dima-toon.com (poster, description, episodes).
  Future<ArabicShowDetail> getDimaToonDetails(String showUrl) async {
    try {
      final html = await _fetchHtml(showUrl);
      final doc = html_parser.parse(html);

      final titleEl = doc.querySelector('h1, .entry-title, .term-title');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = doc.querySelector('.cartoon-image img');
      final poster = imgEl?.attributes['src'] ?? '';

      final storyEl = doc.querySelector('.brief-story');
      String description = storyEl?.text.trim() ?? '';
      // Remove the "قصة الكرتون :" prefix if present
      description = description.replaceFirst(RegExp(r'^قصة الكرتون\s*:\s*'), '');

      final episodeEls = doc.querySelectorAll('.episode-box a[href]');
      final episodes = <ArabicEpisode>[];
      for (final a in episodeEls) {
        final href = a.attributes['href'] ?? '';
        final epTitle = a.text.trim();
        if (href.isEmpty || epTitle.isEmpty) continue;
        episodes.add(ArabicEpisode(id: href, title: epTitle));
      }

      return ArabicShowDetail(
        title: title,
        poster: poster,
        description: description,
        seasons: [
          ArabicSeason(number: 1, tabId: '1', episodes: episodes),
        ],
      );
    } catch (e) {
      debugPrint('[DimaToon] Details error: $e');
      return ArabicShowDetail(title: '', poster: '');
    }
  }

  /// Get the direct MP4 URL from a dima-toon episode page.
  Future<String?> getDimaToonVideoUrl(String episodeUrl) async {
    try {
      final html = await _fetchHtml(episodeUrl);
      final doc = html_parser.parse(html);
      final source = doc.querySelector('source[src]');
      final src = source?.attributes['src'];
      if (src != null && src.isNotEmpty) {
        debugPrint('[DimaToon] Video URL: $src');
        return src;
      }
      // Fallback: regex for .mp4 URL
      final match = RegExp(r'https?://[^"\s]+\.mp4[^"\s]*').firstMatch(html);
      return match?.group(0);
    } catch (e) {
      debugPrint('[DimaToon] Video URL error: $e');
      return null;
    }
  }
}
