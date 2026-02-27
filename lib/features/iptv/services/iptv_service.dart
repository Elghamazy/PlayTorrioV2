import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iptv_credential.dart';
import '../models/iptv_user_info.dart';
import '../models/iptv_category.dart';
import '../models/iptv_channel.dart';
import '../models/iptv_movie.dart';
import '../models/iptv_series.dart';
import 'xtream_api_service.dart';
import 'm3u_parser_service.dart';

/// Unified IPTV service that wraps both Xtream and M3U modes.
/// Singleton with session state.
class IptvService {
  static final IptvService _instance = IptvService._internal();
  factory IptvService() => _instance;
  IptvService._internal();

  static const String _credentialKey = 'iptv_credential';

  IptvCredential? _credential;
  IptvUserInfo? _userInfo;
  XtreamApiService? _xtreamApi;

  // M3U cached data
  List<IptvChannel>? _m3uChannels;
  List<IptvCategory>? _m3uCategories;

  // Cache
  final Map<String, List<IptvChannel>> _liveStreamCache = {};
  final Map<String, List<IptvMovie>> _vodStreamCache = {};
  final Map<String, List<IptvSeries>> _seriesCache = {};
  List<IptvCategory>? _liveCategoriesCache;
  List<IptvCategory>? _vodCategoriesCache;
  List<IptvCategory>? _seriesCategoriesCache;
  DateTime? _cacheTimestamp;

  // Notifier for login state changes
  static final ValueNotifier<bool> loginStateNotifier = ValueNotifier<bool>(false);

  IptvCredential? get credential => _credential;
  IptvUserInfo? get userInfo => _userInfo;
  bool get isLoggedIn => _credential != null;
  bool get isXtream => _credential?.type == IptvLoginType.xtream;

  // ─── Persistence ────────────────────────────────────────────
  Future<void> loadSavedCredential() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_credentialKey);
      if (json != null) {
        _credential = IptvCredential.fromJson(jsonDecode(json));
        if (_credential!.type == IptvLoginType.xtream) {
          _xtreamApi = XtreamApiService(
            serverUrl: _credential!.serverUrl!,
            username: _credential!.username!,
            password: _credential!.password!,
          );
        }
        loginStateNotifier.value = true;
      }
    } catch (e) {
      debugPrint('Failed to load IPTV credentials: $e');
    }
  }

  Future<void> _saveCredential(IptvCredential cred) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_credentialKey, jsonEncode(cred.toJson()));
  }

  // ─── Login ──────────────────────────────────────────────────
  Future<IptvUserInfo> loginXtream(String serverUrl, String username, String password) async {
    final api = XtreamApiService(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
    final userInfo = await api.authenticate();
    if (!userInfo.auth) {
      api.dispose();
      throw Exception('Invalid credentials');
    }

    _xtreamApi?.dispose();
    _xtreamApi = api;
    _credential = IptvCredential.xtream(server: serverUrl, user: username, pass: password);
    _userInfo = userInfo;
    _clearCache();
    await _saveCredential(_credential!);
    loginStateNotifier.value = true;
    return userInfo;
  }

  Future<void> loginM3u(String url) async {
    final parser = M3uParserService();
    final result = await parser.parseFromUrl(url);
    _m3uChannels = result.channels;
    _m3uCategories = result.categories;
    _credential = IptvCredential.m3u(url: url);
    _userInfo = null;
    _xtreamApi?.dispose();
    _xtreamApi = null;
    _clearCache();
    await _saveCredential(_credential!);
    loginStateNotifier.value = true;
  }

  Future<void> logout() async {
    _xtreamApi?.dispose();
    _xtreamApi = null;
    _credential = null;
    _userInfo = null;
    _m3uChannels = null;
    _m3uCategories = null;
    _clearCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credentialKey);
    loginStateNotifier.value = false;
  }

  void _clearCache() {
    _liveStreamCache.clear();
    _vodStreamCache.clear();
    _seriesCache.clear();
    _liveCategoriesCache = null;
    _vodCategoriesCache = null;
    _seriesCategoriesCache = null;
    _cacheTimestamp = null;
  }

  bool get _isCacheExpired {
    if (_cacheTimestamp == null) return true;
    return DateTime.now().difference(_cacheTimestamp!).inMinutes > 30;
  }

  // ─── Refresh user info ─────────────────────────────────────
  Future<void> refreshUserInfo() async {
    if (!isXtream || _xtreamApi == null) return;
    try {
      _userInfo = await _xtreamApi!.authenticate();
    } catch (_) {}
  }

  // ─── Live TV ────────────────────────────────────────────────
  Future<List<IptvCategory>> getLiveCategories() async {
    if (_credential?.type == IptvLoginType.m3u) {
      return _m3uCategories ?? [];
    }
    if (_liveCategoriesCache != null && !_isCacheExpired) return _liveCategoriesCache!;
    _liveCategoriesCache = await _xtreamApi!.getLiveCategories();
    _cacheTimestamp = DateTime.now();
    return _liveCategoriesCache!;
  }

  Future<List<IptvChannel>> getLiveStreams({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) {
      final all = _m3uChannels ?? [];
      if (categoryId == null) return all;
      return all.where((c) => c.categoryId == categoryId || c.categoryName == categoryId).toList();
    }
    final key = categoryId ?? '_all';
    if (_liveStreamCache.containsKey(key) && !_isCacheExpired) {
      return _liveStreamCache[key]!;
    }
    final streams = await _xtreamApi!.getLiveStreams(categoryId: categoryId);
    _liveStreamCache[key] = streams;
    _cacheTimestamp = DateTime.now();
    return streams;
  }

  String getLiveStreamUrl(IptvChannel channel) {
    if (channel.streamUrl != null) return channel.streamUrl!;
    return _xtreamApi!.getLiveStreamUrl(channel.streamId);
  }

  // ─── VOD (Movies) ──────────────────────────────────────────
  Future<List<IptvCategory>> getVodCategories() async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    if (_vodCategoriesCache != null && !_isCacheExpired) return _vodCategoriesCache!;
    _vodCategoriesCache = await _xtreamApi!.getVodCategories();
    _cacheTimestamp = DateTime.now();
    return _vodCategoriesCache!;
  }

  Future<List<IptvMovie>> getVodStreams({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    final key = categoryId ?? '_all';
    if (_vodStreamCache.containsKey(key) && !_isCacheExpired) {
      return _vodStreamCache[key]!;
    }
    final streams = await _xtreamApi!.getVodStreams(categoryId: categoryId);
    _vodStreamCache[key] = streams;
    _cacheTimestamp = DateTime.now();
    return streams;
  }

  Future<VodInfo> getVodInfo(int vodId) async {
    return _xtreamApi!.getVodInfo(vodId);
  }

  String getMovieUrl(int streamId, String containerExtension) {
    return _xtreamApi!.getMovieUrl(streamId, containerExtension);
  }

  // ─── Series ─────────────────────────────────────────────────
  Future<List<IptvCategory>> getSeriesCategories() async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    if (_seriesCategoriesCache != null && !_isCacheExpired) return _seriesCategoriesCache!;
    _seriesCategoriesCache = await _xtreamApi!.getSeriesCategories();
    _cacheTimestamp = DateTime.now();
    return _seriesCategoriesCache!;
  }

  Future<List<IptvSeries>> getSeries({String? categoryId}) async {
    if (_credential?.type == IptvLoginType.m3u) return [];
    final key = categoryId ?? '_all';
    if (_seriesCache.containsKey(key) && !_isCacheExpired) {
      return _seriesCache[key]!;
    }
    final series = await _xtreamApi!.getSeries(categoryId: categoryId);
    _seriesCache[key] = series;
    _cacheTimestamp = DateTime.now();
    return series;
  }

  Future<SeriesInfo> getSeriesInfo(int seriesId) async {
    return _xtreamApi!.getSeriesInfo(seriesId);
  }

  String getEpisodeUrl(int episodeId, String containerExtension) {
    return _xtreamApi!.getEpisodeUrl(episodeId, containerExtension);
  }
}
